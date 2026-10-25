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
 * Wocheneinkauf: alle geplanten Slots, skaliert, gleiche Zutat + Einheit summiert,
 * Zutaten ohne Menge nur einmal gelistet. Vorrat (Salz, Pfeffer …) landet in
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
  return mergeSpoons([...byKey.values()]).sort(
    (a, b) => aisleRank(a.aisle) - aisleRank(b.aisle) || a.name.localeCompare(b.name, "de"),
  );
}

/** Gleiche Zutat in EL und TL → in EL zusammenfassen (1 EL = 3 TL, auf ½ EL gerundet) */
function mergeSpoons(items: ShoppingItem[]): ShoppingItem[] {
  const out: ShoppingItem[] = [];
  for (const item of items) {
    if (item.unit !== "TL" || item.amount === null) {
      out.push(item);
      continue;
    }
    const el = items.find((x) => x.unit === "EL" && x.amount !== null && shoppingKey(x.name) === shoppingKey(item.name));
    if (!el) {
      out.push(item);
      continue;
    }
    el.amount = Math.ceil(((el.amount ?? 0) + item.amount / 3) * 2) / 2;
    el.recipes = [...new Set([...el.recipes, ...item.recipes])];
    el.text = shoppingLine(el);
  }
  return out;
}

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
