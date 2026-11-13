-- Einkauf auf Zutatenebene: jeder bestätigte Kauf als Menge je Gericht und Zutat.
-- Damit zeigt die Liste nach einer Planänderung nur die Differenz, ein ausgefallenes
-- Gericht behält seine Käufe („ist noch da“), und alle im Laden sehen dieselben Haken.
-- Die Rechnung steht in lib/shopping.ts. ep_meal_plan.shopped_at bleibt für die
-- bisherige App-Version bestehen und wird beim Abschließen weiter mitgeschrieben.

create table if not exists public.ep_purchases (
  id uuid primary key default gen_random_uuid(),
  -- vom Gerät vergeben: doppeltes Senden (Funkloch, Wiederholung) erzeugt keinen zweiten Kauf
  client_id uuid not null unique,
  household_id uuid not null references public.ep_households(id) on delete cascade,
  -- Gericht, für das gekauft wurde; null bei „Noch offen“-Posten oder gelöschtem Planeintrag
  meal_plan_id uuid references public.ep_meal_plan(id) on delete set null,
  -- Zutat und Einheit (lib/shopping.ts purchaseKey) oder „x:<id>“ für einen „Noch offen“-Posten
  item_key text not null check (length(item_key) between 1 and 200),
  name text not null check (length(trim(name)) between 1 and 200),
  amount numeric check (amount is null or amount > 0),
  unit text,
  bought_by uuid references public.ep_members(id) on delete set null,
  bought_at timestamptz not null default now()
);
create index if not exists ep_purchases_household on public.ep_purchases (household_id, bought_at desc);
create index if not exists ep_purchases_meal_plan on public.ep_purchases (meal_plan_id);
create index if not exists ep_purchases_bought_by on public.ep_purchases (bought_by);

alter table public.ep_purchases enable row level security;
create policy ep_purchases_all on public.ep_purchases for all to authenticated
  using (household_id in (select public.ep_my_household_ids()))
  with check (household_id in (select public.ep_my_household_ids()));

alter publication supabase_realtime add table public.ep_purchases;
