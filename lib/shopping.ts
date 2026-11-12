// Einkauf auf Zutatenebene (Tests in tests/purchases.test.ts).
//
// Bisher hing „eingekauft“ am Gericht (ep_meal_plan.shopped_at). Jetzt wird jeder Kauf
// als Menge je Gericht und Zutat festgehalten (ep_purchases). Daraus folgt alles Weitere:
//  - Für drei gekauft, jetzt essen fünf mit → offen ist nur die Differenz.
//  - Gericht fällt nach dem Einkauf aus → der Kauf bleibt und steht unter „Ist noch da“;
//    braucht ein anderes Gericht dieselbe Zutat, wird er dort angerechnet.
//  - Zwei Personen im Laden sehen dieselben Haken, weil die Käufe in der Datenbank liegen.
//
// Bewusst einfach gehalten: keine Packungsgrößen, kein Warenbestand, keine Preise.

import { aisleFor, aisleRank } from "./aisles";
import { buildShoppingList, mergeUnits, shoppingLine } from "./planning";
import { displayName, parseAmount, shoppingKey, splitIngredientLine } from "./quantity";
import type { Attendance, MealPlanEntry, Member, Recipe, ShoppingItem } from "./types";

export interface Purchase {
  id: string;
  /** vom Gerät vergeben – doppeltes Senden erzeugt keinen zweiten Kauf */
  client_id: string;
  household_id: string;
  /** Gericht, für das gekauft wurde; null bei „Noch offen“-Posten oder gelöschtem Planeintrag */
  meal_plan_id: string | null;
  item_key: string;
  name: string;
  amount: number | null;
  unit: string | null;
  bought_by: string | null;
  bought_at: string;
  /** kauf = im Laden abgehakt, vorrat = „ist noch da“ (bestätigt, nicht gekauft) */
  source?: "kauf" | "vorrat";
}

/** Offener Bedarf einer Zutat in einer Einheit; `parts` sagt, welches Gericht wie viel davon braucht */
export interface OpenPart extends ShoppingItem {
  key: string;
  parts: { entryId: string; amount: number | null }[];
  /** Deckt, was schon da ist (anderes Gericht ausgefallen oder kleiner geworden)? */
  usedStock: boolean;
}

/** Eine Zeile der Liste: dieselbe Zutat, auch über Einheiten hinweg („2 EL + 50 ml Olivenöl“) */
export interface OpenItem extends ShoppingItem {
  key: string;
  rows: OpenPart[];
  usedStock: boolean;
}

/** Gekauft, aber gerade keinem Gericht zugeordnet */
export interface StockItem {
  key: string;
  name: string;
  amount: number | null;
  unit: string | null;
  text: string;
  purchaseIds: string[];
  /** seit wann (frühester Eintrag, ISO) */
  since: string;
}

/** Vor Kurzem abgehakt – bleibt durchgestrichen stehen, damit man es zurücknehmen kann */
export interface BoughtItem {
  key: string;
  name: string;
  text: string;
  aisle: string;
  purchaseIds: string[];
  by: string | null;
  /** nicht gekauft, sondern als „ist noch da“ bestätigt */
  fromStock: boolean;
}

export interface ShoppingState {
  open: OpenItem[];
  stock: StockItem[];
  bought: BoughtItem[];
  /** Gerichte, für die alles da ist */
  covered: Set<string>;
}

/** Abgehaktes bleibt so lange durchgestrichen auf der Liste sichtbar */
export const RECENT_HOURS = 12;
/** Was länger liegt, gilt nicht mehr als „ist noch da“ */
export const STOCK_DAYS = 21;

export const purchaseKey = (i: Pick<ShoppingItem, "name" | "unit">) => `${shoppingKey(i.name)}|${i.unit ?? ""}`;
export const extraKey = (extraId: string) => `x:${extraId}`;
const isExtraKey = (key: string) => key.startsWith("x:");

const round = (n: number) => Number(n.toFixed(3));

/** Gericht, für das eingekauft wird: ab heute, mit Rezept, kein Rest, nicht ausgefallen oder gekocht */
export function isShoppable(entry: MealPlanEntry, today: string): boolean {
  return !!entry.recipe_id && !entry.leftover_of && entry.status === "geplant" && entry.date >= today;
}

interface Args {
  plan: MealPlanEntry[];
  recipes: Map<string, Recipe>;
  members: Member[];
  attendance: Attendance[];
  pantry?: Set<string>;
  purchases: Purchase[];
  today: string;
  /** Zeitpunkt für „vor Kurzem“ und „noch da“ (ISO) */
  now: string;
  /** Nur diese Gerichte stehen diesmal auf der Liste (Auswahl „bis Tag X“ / abgewählt) */
  include?: (entry: MealPlanEntry) => boolean;
}

export function shoppingState({ plan, recipes, members, attendance, pantry = new Set(), purchases, today, now, include }: Args): ShoppingState {
  const nowMs = Date.parse(now);
  const byEntry = new Map<string, Purchase[]>();
  for (const p of purchases) {
    if (!p.meal_plan_id || isExtraKey(p.item_key)) continue;
    byEntry.set(p.meal_plan_id, [...(byEntry.get(p.meal_plan_id) ?? []), p]);
  }

  const dishes = plan.filter((e) => isShoppable(e, today) && recipes.has(e.recipe_id!));
  const dishIds = new Set(dishes.map((d) => d.id));
  const planById = new Map(plan.map((e) => [e.id, e]));

  const open = new Map<string, OpenPart>();
  const stock = new Map<string, StockItem>();
  const covered = new Set<string>();
  const missingByDish = new Map<string, string[]>();

  const boughtAt = new Map(purchases.map((p) => [p.id, p.bought_at]));
  const addStock = (key: string, name: string, amount: number | null, unit: string | null, ids: string[]) => {
    const since = ids.map((id) => boughtAt.get(id) ?? now).sort()[0] ?? now;
    const cur = stock.get(key);
    if (cur) {
      // „ist da, Menge unbekannt“ schlägt jede Zahl
      cur.amount = cur.amount !== null && amount !== null ? round(cur.amount + amount) : null;
      cur.purchaseIds.push(...ids);
      if (since < cur.since) cur.since = since;
    } else stock.set(key, { key, name, amount, unit, text: "", purchaseIds: [...ids], since });
  };

  for (const dish of dishes) {
    const bought = byEntry.get(dish.id) ?? [];
    // Mit der alten App als „eingekauft“ markiert und ohne einzelne Käufe: gilt als erledigt
    if (dish.shopped_at && !bought.length) {
      covered.add(dish.id);
      continue;
    }
    const need = buildShoppingList(plan, recipes, members, attendance, pantry, (e) => e.id === dish.id).filter((i) => !i.pantry);
    const needKeys = new Set(need.map(purchaseKey));
    const listed = !include || include(dish);
    let missing = false;
    // Zusammengesetzte Angabe („16 + 1 Bund“): solange nichts davon gekauft ist, so stehen lassen
    const untouched = (item: ShoppingItem) => item.text.includes(" + ");

    for (const item of need) {
      const key = purchaseKey(item);
      const mine = bought.filter((p) => p.item_key === key);
      const have = mine.reduce((s, p) => s + (p.amount ?? 0), 0);
      const deficit = item.amount === null ? (mine.length ? 0 : null) : round(Math.max(0, item.amount - have));
      // Mehr gekauft als jetzt gebraucht (weniger Esser): der Rest ist noch da
      if (item.amount !== null && have > item.amount + 0.0005) addStock(key, item.name, round(have - item.amount), item.unit, mine.map((p) => p.id));
      if (deficit === 0) continue;
      missing = true;
      if (!listed) continue;
      const keepText = untouched(item) && !mine.length;
      const row = open.get(key);
      if (row) {
        if (row.amount !== null && deficit !== null) row.amount = round(row.amount + deficit);
        row.text = "";
        for (const r of item.recipes) if (!row.recipes.includes(r)) row.recipes.push(r);
        row.parts.push({ entryId: dish.id, amount: deficit });
      } else {
        open.set(key, { ...item, key, text: keepText ? item.text : "", amount: deficit, recipes: [...item.recipes], parts: [{ entryId: dish.id, amount: deficit }], usedStock: false });
      }
    }
    if (missing) missingByDish.set(dish.id, need.map(purchaseKey));
    else if (bought.length) covered.add(dish.id);

    // Gekauft für eine Zutat, die das Gericht nicht mehr braucht (Rezept getauscht)
    for (const p of bought) if (!needKeys.has(p.item_key) && isFresh(p, nowMs)) addStock(p.item_key, p.name, p.amount, p.unit, [p.id]);
  }

  // Käufe für Gerichte, die ausgefallen oder aus dem Plan genommen sind. Was gekocht wurde
  // oder in der Vergangenheit liegt (nicht mehr geladen), ist verbraucht.
  for (const p of purchases) {
    if (isExtraKey(p.item_key) || !isFresh(p, nowMs)) continue;
    if (p.meal_plan_id && dishIds.has(p.meal_plan_id)) continue;
    const entry = p.meal_plan_id ? planById.get(p.meal_plan_id) : undefined;
    if (p.meal_plan_id && (!entry || entry.status === "gekocht")) continue;
    addStock(p.item_key, p.name, p.amount, p.unit, [p.id]);
  }

  // Was noch da ist, zuerst verbrauchen. Die Käufe selbst bleiben unverändert – die Rechnung
  // zieht sie bei jedem Aufbau der Liste neu ab.
  // „Reis ist da“ ohne Menge deckt Reis in jeder Einheit
  const anyAmount = new Map([...stock.values()].filter((s) => s.amount === null).map((s) => [shoppingKey(s.name), s]));
  for (const [key, row] of open) {
    const have = stock.get(key) ?? anyAmount.get(shoppingKey(row.name));
    if (!have) continue;
    row.usedStock = true;
    if (row.amount === null || have.amount === null) {
      open.delete(key);
      continue;
    }
    row.amount = round(row.amount - Math.min(have.amount, row.amount));
    row.text = "";
    if (row.amount <= 0) open.delete(key);
  }
  for (const [dishId, keys] of missingByDish) if (!keys.some((k) => open.has(k))) covered.add(dishId);

  // Dieselbe Zutat in mehreren Einheiten wird eine Zeile
  const groups = new Map<string, OpenPart[]>();
  for (const row of open.values()) {
    const k = shoppingKey(row.name);
    groups.set(k, [...(groups.get(k) ?? []), row]);
  }
  const openList: OpenItem[] = [...groups.entries()].map(([key, rows]) => {
    const merged = rows.length === 1 && rows[0].text ? rows[0] : mergeUnits(rows.map((r) => ({ ...r, text: shoppingLine(r) })))[0];
    return { ...merged, key, aisle: rows[0].aisle, recipes: [...new Set(rows.flatMap((r) => r.recipes))], rows, usedStock: rows.some((r) => r.usedStock) };
  });
  const recentMs = nowMs - RECENT_HOURS * 3600_000;
  const recent = new Map<string, { name: string; purchases: Purchase[] }>();
  for (const p of purchases) {
    if (isExtraKey(p.item_key) || Date.parse(p.bought_at) < recentMs) continue;
    // Von Hand eingetragener Vorrat ist kein Haken auf der Liste
    if (p.source === "vorrat" && !p.meal_plan_id) continue;
    const k = shoppingKey(p.name);
    const cur = recent.get(k);
    if (cur) cur.purchases.push(p);
    else recent.set(k, { name: p.name, purchases: [p] });
  }
  const bought: BoughtItem[] = [...recent.entries()]
    // Was noch offen ist, steht nicht zusätzlich durchgestrichen da
    .filter(([k]) => !groups.has(k))
    .map(([key, { name, purchases: mine }]) => {
      const units = new Map<string, number | null>();
      for (const p of mine) {
        const u = p.unit ?? "";
        const cur = units.get(u);
        units.set(u, p.amount === null || cur === null ? null : round((cur ?? 0) + p.amount));
      }
      const parts = [...units.entries()].map(([u, a]) => ({ name, amount: a, unit: u || null }));
      const amounts = parts.filter((x) => x.amount !== null).map((x) => shoppingLine({ ...x, name: "" }).trim());
      return { key, name, text: amounts.length ? `${amounts.join(" + ")} ${name}` : name, aisle: aisleFor(name), purchaseIds: mine.map((p) => p.id), by: mine[0].bought_by, fromStock: mine.every((p) => p.source === "vorrat") };
    });

  const byAisle = <T extends { aisle: string; name: string }>(a: T, b: T) => aisleRank(a.aisle) - aisleRank(b.aisle) || a.name.localeCompare(b.name, "de");
  return {
    open: openList.sort(byAisle),
    stock: [...stock.values()].map((s) => ({ ...s, text: shoppingLine(s) })).sort((a, b) => a.name.localeCompare(b.name, "de")),
    bought: bought.sort(byAisle),
    covered,
  };
}

function isFresh(p: Purchase, nowMs: number): boolean {
  return Date.parse(p.bought_at) >= nowMs - STOCK_DAYS * 86400_000;
}

export interface NewPurchase {
  client_id: string;
  household_id: string;
  meal_plan_id: string | null;
  item_key: string;
  name: string;
  amount: number | null;
  unit: string | null;
  bought_by: string | null;
  source?: "kauf" | "vorrat";
}

const TO_BASE: Record<string, [string, number]> = { kg: ["g", 1000], l: ["ml", 1000] };

/**
 * Von Hand eingetragener Vorrat: „500 g Reis“, „1 kg Mehl“ oder nur „Eier“.
 * Mengen landen in der Einheit der Einkaufsliste (g, ml), damit sie sich verrechnen lassen.
 */
export function stockEntryFromText(text: string, householdId: string, memberId: string | null, newId: () => string): NewPurchase | null {
  const line = splitIngredientLine(text.trim());
  const name = displayName(line.name).trim();
  if (!name) return null;
  let { amount, unit } = parseAmount(line.amount_text);
  if (amount !== null && unit && TO_BASE[unit]) {
    amount = round(amount * TO_BASE[unit][1]);
    unit = TO_BASE[unit][0];
  }
  if (amount !== null && amount <= 0) amount = null;
  if (amount === null) unit = null;
  return { client_id: newId(), household_id: householdId, meal_plan_id: null, item_key: purchaseKey({ name, unit }), name, amount, unit, bought_by: memberId, source: "vorrat" };
}

/**
 * Zeile abhaken: Käufe über genau die offene Menge, verteilt auf die beteiligten Gerichte.
 * Deckt der Vorrat einen Teil, wird nur der Rest gekauft.
 */
export function purchasesFor(item: OpenItem, householdId: string, memberId: string | null, newId: () => string, source: "kauf" | "vorrat" = "kauf"): NewPurchase[] {
  const out: NewPurchase[] = [];
  for (const row of item.rows) {
    let left = row.amount;
    for (const part of row.parts) {
      const amount = left === null || part.amount === null ? null : round(Math.min(part.amount, left));
      if (amount !== null && amount <= 0) continue;
      if (left !== null && amount !== null) left = round(left - amount);
      out.push({ client_id: newId(), household_id: householdId, meal_plan_id: part.entryId, item_key: row.key, name: row.name, amount, unit: row.unit, bought_by: memberId, source });
    }
  }
  return out;
}
