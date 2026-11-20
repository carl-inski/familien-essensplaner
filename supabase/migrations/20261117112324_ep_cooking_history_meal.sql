alter table public.ep_cooking_history
  add column meal text
    check (meal in ('fruehstueck', 'mittag', 'abend', 'snack'));

-- Keep past entries intact. Serialize new direct logs for each recipe and day.
create function public.ep_check_direct_cooking_log()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    new.household_id::text || '/' || new.recipe_id::text || '/' || (new.cooked_on - date '2000-01-01')::text, 0
  ));
  if exists (
    select 1 from public.ep_cooking_history as history
    where history.household_id = new.household_id
      and history.recipe_id = new.recipe_id
      and history.cooked_on = new.cooked_on
      and history.source = 'manuell'
  ) then
    raise unique_violation using message = 'ep_direct_cooking_log_once';
  end if;
  return new;
end;
$$;

create trigger ep_direct_cooking_log_once
before insert on public.ep_cooking_history
for each row when (new.source = 'manuell')
execute function public.ep_check_direct_cooking_log();
