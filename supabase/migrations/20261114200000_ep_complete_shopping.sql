-- A stable request ID preserves the original receipt if the response is lost.
create table public.ep_shopping_completions (
  id uuid primary key,
  household_id uuid not null references public.ep_households(id) on delete cascade,
  member_id uuid not null references public.ep_members(id) on delete cascade,
  receipt jsonb,
  undone_at timestamptz
);
create index ep_shopping_completions_member on public.ep_shopping_completions (member_id);
create index ep_shopping_completions_household on public.ep_shopping_completions (household_id);
alter table public.ep_shopping_completions enable row level security;
revoke all on public.ep_shopping_completions from public, anon, authenticated;
grant select, insert on public.ep_shopping_completions to authenticated;
grant update (receipt, undone_at) on public.ep_shopping_completions to authenticated;
create policy ep_shopping_completions_member_access on public.ep_shopping_completions for all to authenticated
  using (exists (select 1 from public.ep_link_member() m
                where m.id = ep_shopping_completions.member_id and m.household_id = ep_shopping_completions.household_id))
  with check (exists (select 1 from public.ep_link_member() m
                     where m.id = ep_shopping_completions.member_id and m.household_id = ep_shopping_completions.household_id));

create function public.ep_complete_shopping(
  p_household uuid, p_completion_id uuid, p_purchases jsonb, p_meals uuid[], p_extras uuid[],
  p_expected_dishes jsonb default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  actor_member_id uuid;
  finished_at timestamptz := clock_timestamp();
  marked uuid[];
  bought uuid[];
  extras jsonb;
  saved_receipt jsonb;
begin
  select m.id into actor_member_id
  from public.ep_members m
  where m.household_id = p_household and m.user_id = (select auth.uid());
  if actor_member_id is null or p_household not in (select public.ep_my_household_ids()) then
    raise exception 'Kein Zugang zu diesem Haushalt' using errcode = '42501';
  end if;

  insert into public.ep_shopping_completions (id, household_id, member_id)
  values (p_completion_id, p_household, actor_member_id)
  on conflict (id) do nothing;

  select receipt into saved_receipt from public.ep_shopping_completions
  where id = p_completion_id and household_id = p_household and member_id = actor_member_id for update;
  if not found then
    raise exception 'Einkaufsabschluss gehört nicht zu diesem Mitglied' using errcode = '42501';
  end if;
  if saved_receipt is not null then return saved_receipt; end if;

  perform 1 from public.ep_meal_plan m
  where m.household_id = p_household and m.id = any(p_meals)
  order by m.id for update;

  -- Check a refreshed list before accepting a top-up for an already marked meal.
  -- Requests queued by older clients keep the original behavior.
  if p_expected_dishes is not null and exists (
    select 1
    from unnest(p_meals) as selected(id)
    left join public.ep_meal_plan m on m.id = selected.id and m.household_id = p_household
    left join jsonb_to_recordset(p_expected_dishes->'dishes') as expected(
      id uuid, recipe_id uuid, servings_override integer, shopped_at timestamptz, purchase_ids uuid[]
    ) on expected.id = selected.id
    where m.id is null or expected.id is null
      or m.status <> 'geplant' or m.recipe_id is null or m.leftover_of is not null
      or (m.recipe_id, m.servings_override, m.shopped_at) is distinct from
         (expected.recipe_id, expected.servings_override, expected.shopped_at)
      or array(
        select p.client_id from public.ep_purchases p
        where p.household_id = p_household and p.meal_plan_id = m.id
          and p.bought_at >= (p_expected_dishes->>'bought_since')::timestamptz
        order by p.client_id
      ) is distinct from expected.purchase_ids
  ) then
    raise exception 'Einkaufsliste wurde inzwischen geändert' using errcode = '40001';
  end if;

  with inserted as (
  insert into public.ep_purchases (client_id, household_id, meal_plan_id, item_key, name, amount, unit, bought_by, source)
  select x.client_id, p_household, x.meal_plan_id, x.item_key, x.name, x.amount, x.unit, actor_member_id, 'kauf'
  from jsonb_to_recordset(p_purchases) as x(client_id uuid, meal_plan_id uuid, item_key text, name text, amount numeric, unit text)
  join public.ep_meal_plan m on m.id = x.meal_plan_id and m.household_id = p_household
  where m.id = any(p_meals) and m.status = 'geplant' and m.recipe_id is not null and m.leftover_of is null
    and (m.shopped_at is null or p_expected_dishes is not null)
  on conflict (client_id) do nothing
  returning client_id
  )
  select coalesce(array_agg(client_id), '{}') into bought from inserted;

  with changed as (
  update public.ep_meal_plan
  set shopped_at = finished_at
  where household_id = p_household and id = any(p_meals) and shopped_at is null
    and status = 'geplant' and recipe_id is not null and leftover_of is null
  returning id
  )
  select coalesce(array_agg(id), '{}') into marked from changed;

  delete from public.ep_purchases p
  where p.household_id = p_household
    and p.item_key in (select 'x:' || e.id::text from public.ep_shopping_extra e
                       where e.household_id = p_household and e.id = any(p_extras));
  with removed as (
    delete from public.ep_shopping_extra where household_id = p_household and id = any(p_extras)
    returning id, member_id, text, aisle, carried, created_at
  )
  select coalesce(jsonb_agg(to_jsonb(removed)), '[]') into extras from removed;
  saved_receipt := jsonb_build_object('timestamp', finished_at, 'meal_ids', marked, 'purchase_ids', bought, 'extras', extras);
  update public.ep_shopping_completions set receipt = saved_receipt where id = p_completion_id;
  return saved_receipt;
end;
$$;

create function public.ep_undo_shopping_completion(p_household uuid, p_completion_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  completion public.ep_shopping_completions;
begin
  select * into completion from public.ep_shopping_completions
  where household_id = p_household and id = p_completion_id for update;
  if not found or completion.receipt is null then
    raise exception 'Einkaufsabschluss nicht verfügbar' using errcode = '42501';
  end if;
  if completion.undone_at is not null then return; end if;

  update public.ep_meal_plan set shopped_at = null
  where household_id = p_household and shopped_at = (completion.receipt->>'timestamp')::timestamptz
    and id in (select value::uuid from jsonb_array_elements_text(completion.receipt->'meal_ids'));
  delete from public.ep_purchases
  where household_id = p_household
    and client_id in (select value::uuid from jsonb_array_elements_text(completion.receipt->'purchase_ids'));
  insert into public.ep_shopping_extra (id, household_id, member_id, text, aisle, carried, created_at)
    select e.id, p_household, m.id, e.text, e.aisle, e.carried, e.created_at
    from jsonb_to_recordset(completion.receipt->'extras') as e(id uuid, member_id uuid, text text, aisle text, carried boolean, created_at timestamptz)
    left join public.ep_members m on m.id = e.member_id and m.household_id = p_household
    on conflict (id) do nothing;
  update public.ep_shopping_completions set undone_at = clock_timestamp() where id = p_completion_id;
end;
$$;

create function public.ep_return_meal_to_shopping(p_household uuid, p_meal uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.ep_meal_plan set shopped_at = null
  where household_id = p_household and id = p_meal and status = 'geplant' and recipe_id is not null
    and leftover_of is null;
  if not found then
    raise exception 'Gericht ist nicht mehr verfügbar' using errcode = 'P0002';
  end if;
  delete from public.ep_purchases where household_id = p_household and meal_plan_id = p_meal;
end;
$$;

revoke execute on function public.ep_complete_shopping(uuid, uuid, jsonb, uuid[], uuid[], jsonb) from public, anon;
revoke execute on function public.ep_return_meal_to_shopping(uuid, uuid) from public, anon;
grant execute on function public.ep_complete_shopping(uuid, uuid, jsonb, uuid[], uuid[], jsonb) to authenticated;
grant execute on function public.ep_return_meal_to_shopping(uuid, uuid) to authenticated;
revoke execute on function public.ep_undo_shopping_completion(uuid, uuid) from public, anon;
grant execute on function public.ep_undo_shopping_completion(uuid, uuid) to authenticated;
