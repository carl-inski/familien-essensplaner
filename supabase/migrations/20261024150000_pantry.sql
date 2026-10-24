-- Vorrat: Zutaten, die der Haushalt immer im Haus hat (z. B. Salz, Pfeffer).
-- Sie erscheinen nicht auf der Einkaufsliste und gehen nicht an Bring!.

create table public.ep_pantry (
  household_id uuid not null references public.ep_households(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  created_at timestamptz not null default now(),
  primary key (household_id, name)
);

alter table public.ep_pantry enable row level security;

create policy ep_pantry_all on public.ep_pantry for all to authenticated
  using (household_id in (select public.ep_my_household_ids()))
  with check (household_id in (select public.ep_my_household_ids()));

-- Startwerte: hat praktisch jeder Haushalt
insert into public.ep_pantry (household_id, name)
select h.id, n from public.ep_households h, unnest(array['salz', 'pfeffer']) as n
on conflict do nothing;
