// Anwesenheit, Esserzahl, Portionen und Wocheneinkauf (Briefing 4.2, 4.8, 7)

import { WEEKDAY_KEYS, weekdayIndex } from "./dates";
import { aisleFor, aisleRank, isPantryBasic } from "./aisles";
import { pantryKey, withoutPantry } from "./pantry";
import { displayName, formatAmount, scaleAmount, shoppingKey } from "./quantity";
import type { Attendance, AttendanceStatus, Ingredient, Meal, MealPlanEntry, Member, Recipe, ShoppingItem } from "./types";

export function effectiveStatus(member: Member, date: string, meal: Meal, attendance: Attendance[]): { status: AttendanceStatus; guests: number; explicit: boolean } {
  const row = attendance.find((a) => a.member_id === member.id && a.date === date && a.meal === meal);
  if (row) return { status: row.status, guests: row.status === "da" ? row.guests : 0, explicit: true };
  const def = member.default_week?.[WEEKDAY_KEYS[weekdayIndex(date)]]?.[meal];
  return { status: def ?? "da", guests: 0, explicit: false };
}

export function eaters(members: Member[], attendance: Attendance[], date: string, meal: Meal): number {
  let n = 0;
  for (const m of members) {
    const s = effectiveStatus(m, date, meal, attendance);
    if (s.status === "da") n += 1 + s.guests;
  }
  return n;
}

export function presentMembers(members: Member[], attendance: Attendance[], date: string, meal: Meal): Member[] {
  return members.filter((m) => effectiveStatus(m, date, meal, attendance).status === "da");
}

/** Portionen, für die ein Slot kocht: Esser des Slots + Esser aller Reste-Slots, die darauf verweisen. */
export function servingsFor(entry: MealPlanEntry, plan: MealPlanEntry[], members: Member[], attendance: Attendance[]): number {
  if (entry.servings_override) return entry.servings_override;
  let total = eaters(members, attendance, entry.date, entry.meal);
  for (const other of plan) {
    if (other.leftover_of === entry.id && other.status !== "ausgefallen") {
      total += eaters(members, attendance, other.date, other.meal);
    }
  }
  return total;
}

export interface ScaledIngredient extends Ingredient {
  scaled_amount: number | null;
  scaled_unit: string | null;
  text: string;
}

export function scaleIngredients(ingredients: Ingredient[], recipeServings: number | null, targetServings: number): ScaledIngredient[] {
  const factor = recipeServings ? targetServings / recipeServings : 1;
  return ingredients.map((i) => {
    if (i.amount === null || !recipeServings) {
      const text = i.amount_text ? `${i.amount_text} ${i.name}` : i.name;
      return { ...i, scaled_amount: i.amount, scaled_unit: i.unit, text: i.amount === null ? `${i.name}${i.amount_text ? ` (${i.amount_text})` : ""}` : text };
    }
    const s = scaleAmount(i.amount, i.unit, factor);
    return { ...i, scaled_amount: s.amount, scaled_unit: s.unit, text: `${formatAmount(s.amount, s.unit)} ${displayName(i.name)}`.trim() };
  });
}

/** Einkaufszeile wie "940 g Hähnchenschenkel" für Bring/JSON-LD */
export function shoppingLine(item: Pick<ShoppingItem, "amount" | "unit" | "name">): string {
  return item.amount === null ? item.name : `${formatAmount(item.amount, item.unit)} ${item.name}`.trim();
}

/**
 * Wocheneinkauf: alle geplanten Slots, skaliert, gleiche Zutat summiert (auch über
 * Einheiten hinweg, siehe mergeUnits), Zutaten ohne Menge nur einmal gelistet. Vorrat (Salz, Pfeffer …) landet in
 * `pantry` statt auf der Liste. Sortiert nach Supermarkt-Gang, dann alphabetisch.
 */
export function buildShoppingList(
  plan: MealPlanEntry[],
  recipes: Map<string, Recipe>,
  members: Member[],
  attendance: Attendance[],
  pantrySet: Set<string> = new Set(),
  /** Nur diese Gerichte einkaufen; Portionen rechnen trotzdem mit dem ganzen Plan (Reste) */
  include?: (entry: MealPlanEntry) => boolean,
): ShoppingItem[] {
  const byKey = new Map<string, ShoppingItem>();
  for (const entry of plan) {
    if (!entry.recipe_id || entry.leftover_of || entry.status === "ausgefallen") continue;
    if (include && !include(entry)) continue;
    const recipe = recipes.get(entry.recipe_id);
    if (!recipe?.ep_recipe_ingredients?.length) continue;
    const servings = servingsFor(entry, plan, members, attendance);
    if (servings === 0) continue;
    for (const ing of scaleIngredients(recipe.ep_recipe_ingredients, recipe.servings, servings)) {
      if (isPantryBasic(ing.name)) continue;
      const rest = withoutPantry(ing.name, pantrySet);
      const inPantry = rest === null;
      const name = displayName(rest ?? ing.name);
      const unit = ing.scaled_amount === null ? null : ing.scaled_unit;
      const key = `${shoppingKey(name)}|${ing.scaled_amount === null ? "-" : unit ?? ""}`;
      const existing = byKey.get(key);
      if (existing) {
        if (existing.amount !== null && ing.scaled_amount !== null) existing.amount = Number((existing.amount + ing.scaled_amount).toFixed(3));
        if (!existing.recipes.includes(recipe.title)) existing.recipes.push(recipe.title);
        // Schreibweisen weichen ab („Basmati-Reis“/„Basmatireis“): die kürzere zeigen
        if (name.length < existing.name.length) existing.name = name;
        existing.text = shoppingLine(existing);
      } else {
        const item: ShoppingItem = {
          name,
          amount: ing.scaled_amount,
          unit,
          text: "",
          aisle: ing.aisle ?? aisleFor(name),
          recipes: [recipe.title],
          ...(inPantry ? { pantry: pantryKey(ing.name) } : {}),
        };
        item.text = shoppingLine(item);
        byKey.set(key, item);
      }
    }
  }
  return mergeUnits([...byKey.values()]).sort(
    (a, b) => aisleRank(a.aisle) - aisleRank(b.aisle) || a.name.localeCompare(b.name, "de"),
  );
}

const TO_BASE: Record<string, [string, number]> = { g: ["g", 1], kg: ["g", 1000], ml: ["ml", 1], l: ["ml", 1000] };
const SPOON_ML: Record<string, number> = { EL: 15, TL: 5 };

/**
 * Jede Zutat genau eine Zeile, auch über Einheiten hinweg:
 * - kg/g und l/ml werden addiert
 * - EL und TL werden zu ml, wenn die Zutat auch in ml vorkommt (1 EL = 15 ml, auf 5 ml
 *   gerundet), sonst TL zu EL (auf ½ EL gerundet)
 * - „2 Knoblauchzehen“ zählt wie „2 Zehen Knoblauch“
 * - ohne Menge („Olivenöl“) hängt sich an eine Angabe mit Menge an
 * - was sich nicht umrechnen lässt, steht nebeneinander: „16 + 1 Bund Frühlingszwiebeln“
 */
export function mergeUnits(items: ShoppingItem[]): ShoppingItem[] {
  const groups = new Map<string, ShoppingItem[]>();
  for (const raw of items) {
    const clove = raw.amount !== null && raw.unit === null ? raw.name.match(/^(.+?)zehen?$/iu) : null;
    const item = clove ? { ...raw, name: clove[1], unit: "Zehen" } : raw;
    const key = `${shoppingKey(item.name)}|${item.pantry ?? ""}`;
    groups.set(key, [...(groups.get(key) ?? []), item]);
  }
  const out: ShoppingItem[] = [];
  for (const group of groups.values()) {
    const measured = group.filter((i) => i.amount !== null);
    const hasMl = measured.some((i) => i.unit === "ml" || i.unit === "l");
    const hasEl = measured.some((i) => i.unit === "EL");
    const byUnit = new Map<string, { amount: number; unit: string | null; rounded?: "ml" | "EL" }>();
    for (const item of measured) {
      let amount = item.amount!;
      let unit = item.unit;
      let rounded: "ml" | "EL" | undefined;
      if (unit && TO_BASE[unit]) {
        amount *= TO_BASE[unit][1];
        unit = TO_BASE[unit][0];
      } else if (unit && SPOON_ML[unit] && hasMl) {
        amount *= SPOON_ML[unit];
        unit = "ml";
        rounded = "ml";
      } else if (unit === "TL" && hasEl) {
        amount /= 3;
        unit = "EL";
        rounded = "EL";
      }
      const part = byUnit.get(unit ?? "");
      if (part) {
        part.amount += amount;
        part.rounded ??= rounded;
      } else byUnit.set(unit ?? "", { amount, unit, rounded });
    }
    const parts = [...byUnit.values()]
      .map((p) => ({ unit: p.unit, amount: p.rounded === "ml" ? Math.ceil(p.amount / 5) * 5 : p.rounded === "EL" ? Math.ceil(p.amount * 2) / 2 : Number(p.amount.toFixed(3)) }))
      // Gewicht und Volumen zuerst, dann Stückzahl, dann Bund, Dose …
      .sort((a, b) => unitRank(a.unit) - unitRank(b.unit));
    const name = group.map((i) => i.name).reduce((a, b) => (b.length < a.length ? b : a));
    const merged: ShoppingItem = {
      ...group[0],
      name,
      amount: parts[0]?.amount ?? null,
      unit: parts[0]?.unit ?? null,
      recipes: [...new Set(group.flatMap((i) => i.recipes))],
    };
    merged.text = parts.length > 1 ? `${parts.map((p) => formatAmount(p.amount, p.unit)).join(" + ")} ${name}` : shoppingLine(merged);
    out.push(merged);
  }
  return out;
}

const unitRank = (unit: string | null) => (unit === "g" || unit === "ml" ? 0 : unit === "EL" || unit === "TL" ? 1 : unit === null ? 2 : 3);

export function groupByAisle(items: ShoppingItem[]): [string, ShoppingItem[]][] {
  const groups = new Map<string, ShoppingItem[]>();
  for (const item of items) {
    const list = groups.get(item.aisle) ?? [];
    list.push(item);
    groups.set(item.aisle, list);
  }
  return [...groups.entries()];
}

/**
 * Gerichte, für die noch eingekauft werden muss: ab heute, mit Rezept,
 * kein Rest, nicht ausgefallen oder schon gekocht, noch nicht eingekauft.
 */
export function needsShopping(entry: MealPlanEntry, today: string): boolean {
  return !!entry.recipe_id && !entry.leftover_of && entry.status === "geplant" && entry.date >= today && !entry.shopped_at;
}
