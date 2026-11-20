create table public.ep_recipe_ratings (
  recipe_id uuid not null references public.ep_recipes(id) on delete cascade,
  member_id uuid not null references public.ep_members(id) on delete cascade,
  stars smallint not null check (stars between 1 and 5),
  primary key (recipe_id, member_id)
);

create index ep_recipe_ratings_member on public.ep_recipe_ratings (member_id);

alter table public.ep_recipe_ratings enable row level security;
revoke all on public.ep_recipe_ratings from public, anon, authenticated;
grant select, insert, update on public.ep_recipe_ratings to authenticated;

create policy ep_recipe_ratings_read on public.ep_recipe_ratings for select to authenticated
  using (public.ep_recipe_in_my_household(recipe_id));

create policy ep_recipe_ratings_create on public.ep_recipe_ratings for insert to authenticated
  with check (member_id = public.ep_my_member_for_recipe(recipe_id));

create policy ep_recipe_ratings_edit on public.ep_recipe_ratings for update to authenticated
  using (member_id = public.ep_my_member_for_recipe(recipe_id))
  with check (member_id = public.ep_my_member_for_recipe(recipe_id));

create table public.ep_weekly_budgets (
  household_id uuid primary key references public.ep_households(id) on delete cascade,
  budget_cents integer check (budget_cents between 1 and 10000000)
);

alter table public.ep_weekly_budgets enable row level security;
revoke all on public.ep_weekly_budgets from public, anon, authenticated;
grant select, insert, update on public.ep_weekly_budgets to authenticated;

create policy ep_weekly_budgets_read on public.ep_weekly_budgets for select to authenticated
  using (household_id in (select public.ep_my_household_ids()));

create policy ep_weekly_budgets_create on public.ep_weekly_budgets for insert to authenticated
  with check (household_id in (select public.ep_my_household_ids()));

create policy ep_weekly_budgets_edit on public.ep_weekly_budgets for update to authenticated
  using (household_id in (select public.ep_my_household_ids()))
  with check (household_id in (select public.ep_my_household_ids()));
