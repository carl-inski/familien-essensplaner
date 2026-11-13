// Planänderungen mit Vorschau (Tests in tests/plan-change.test.ts).
//
// „Heute auswärts“ und „Verschieben“ ändern den Plan nie blind: Erst wird die Änderung
// auf einer Kopie durchgespielt, dann sagt die Vorschau in normaler Sprache, was sich
// ändert – am Plan, an den Portionen und an der Einkaufsliste. Dieselbe Vorschau zeigt
// die App bei einer Änderung von Hand und bei einem Vorschlag der KI.
//
// Verschieben tauscht den Inhalt zweier Mahlzeiten (das Ziel darf leer sein). Die Käufe
// wandern mit dem Gericht, Koch und Notiz bleiben beim Tag. In der Datenbank macht das
// die RPC ep_plan_move in einem Schritt; `applyChange` bildet sie hier nach.

import { WEEKDAY_LONG, WEEKDAY_SHORT, addDays, daysBetween, formatDateDE, weekdayIndex } from "./dates";
import { MEAL_LABEL, slotKey } from "./meals";
import { servingsFor, shoppingLine } from "./planning";
import { shoppingState, type Purchase } from "./shopping";
import type { Attendance, Meal, MealPlanEntry, Member, Recipe } from "./types";

export interface SlotRef {
  date: string;
  meal: Meal;
}

export type PlanChange = { kind: "auswaerts"; slot: SlotRef } | { kind: "verschieben"; from: SlotRef; to: SlotRef };

export interface ChangeContext {
  plan: MealPlanEntry[];
  purchases: Purchase[];
  recipes: Map<string, Recipe>;
  members: Member[];
  attendance: Attendance[];
  pantry?: Set<string>;
  today: string;
  now: string;
}

export interface ChangePreview {
  /** Warum die Änderung nicht geht; dann sind die anderen Felder leer */
  problem: string | null;
  /** Was am Plan passiert, z. B. „Gnocchi auf Freitag.“ */
  plan: string[];
  /** Was das für den Einkauf heißt */
  shopping: string[];
}

const at = (plan: MealPlanEntry[], s: SlotRef) => plan.find((p) => p.date === s.date && p.meal === s.meal);
const hasDish = (e: MealPlanEntry | undefined): e is MealPlanEntry => !!e && (!!e.recipe_id || !!e.leftover_of);
const sameSlot = (a: SlotRef, b: SlotRef) => a.date === b.date && a.meal === b.meal;

/** „heute Abend“, „Freitagabend“, weiter weg „Fr 20.11. Abend“ */
export function slotName(s: SlotRef, today: string): string {
  const diff = daysBetween(today, s.date);
  const meal = MEAL_LABEL[s.meal];
  if (diff === 0) return `heute ${meal}`;
  if (diff === 1) return `morgen ${meal}`;
  if (diff > 1 && diff < 7) return `${WEEKDAY_LONG[weekdayIndex(s.date)]} ${meal}`;
  return `${WEEKDAY_SHORT[weekdayIndex(s.date)]} ${formatDateDE(s.date, { day: "numeric", month: "numeric" })} ${meal}`;
}

/** Prüft, ob die Änderung überhaupt geht – dieselben Regeln wie in ep_plan_move */
export function changeProblem(change: PlanChange, plan: MealPlanEntry[], today: string): string | null {
  const from = change.kind === "auswaerts" ? change.slot : change.from;
  const source = at(plan, from);
  if (from.date < today) return "Vergangene Mahlzeiten lassen sich nicht mehr ändern.";
  if (!hasDish(source)) return "Dort ist nichts geplant.";
  if (change.kind === "auswaerts") return source.status === "ausgefallen" ? "Das Gericht ist schon als ausgefallen markiert." : null;
  if (change.to.date < today) return "In die Vergangenheit lässt sich nichts verschieben.";
  if (sameSlot(change.from, change.to)) return "Das Gericht steht schon dort.";
  const target = at(plan, change.to);
  if (target && (source.leftover_of === target.id || target.leftover_of === source.id)) return "Ein Gericht und seine Reste lassen sich nicht tauschen.";
  return null;
}

/**
 * Spielt die Änderung auf einer Kopie durch. Voraussetzung: `changeProblem` ist null.
 * Liefert den Plan und die Käufe so, wie sie danach in der Datenbank stehen.
 */
export function applyChange(change: PlanChange, plan: MealPlanEntry[], purchases: Purchase[]): { plan: MealPlanEntry[]; purchases: Purchase[] } {
  if (change.kind === "auswaerts") {
    return { plan: plan.map((p) => (sameSlot(p, change.slot) ? { ...p, status: "ausgefallen" as const } : p)), purchases };
  }
  const a = at(plan, change.from)!;
  const b: MealPlanEntry = at(plan, change.to) ?? {
    id: `neu-${slotKey(change.to.date, change.to.meal)}`,
    household_id: a.household_id,
    ...change.to,
    recipe_id: null,
    leftover_of: null,
    cook_id: null,
    cook2_id: null,
    servings_override: null,
    status: "geplant",
    note: null,
  };
  // Inhalt tauschen; Portionen rechnen sich am neuen Tag neu aus der Anwesenheit
  const content = (e: MealPlanEntry) => ({ recipe_id: e.recipe_id, leftover_of: e.leftover_of, servings_override: null, status: "geplant" as const, shopped_at: null });
  const swap = (id: string | null) => (id === a.id ? b.id : id === b.id ? a.id : id);
  const rest = plan.filter((p) => p.id !== a.id && p.id !== b.id).map((p) => (p.leftover_of === a.id || p.leftover_of === b.id ? { ...p, leftover_of: swap(p.leftover_of) } : p));
  return {
    plan: [...rest, { ...a, ...content(b) }, { ...b, ...content(a) }],
    purchases: purchases.map((p) => (p.meal_plan_id === a.id || p.meal_plan_id === b.id ? { ...p, meal_plan_id: swap(p.meal_plan_id) } : p)),
  };
}

export function previewChange(change: PlanChange, ctx: ChangeContext): ChangePreview {
  const problem = changeProblem(change, ctx.plan, ctx.today);
  if (problem) return { problem, plan: [], shopping: [] };

  const title = (e: MealPlanEntry | undefined) => (e?.recipe_id ? ctx.recipes.get(e.recipe_id)?.title ?? "Gericht" : "Reste");
  const after = applyChange(change, ctx.plan, ctx.purchases);
  const lines: string[] = [];

  if (change.kind === "auswaerts") {
    lines.push(`${title(at(ctx.plan, change.slot))} fällt ${slotName(change.slot, ctx.today)} aus.`);
  } else {
    const source = at(ctx.plan, change.from)!;
    const target = at(ctx.plan, change.to);
    lines.push(`${title(source)} auf ${slotName(change.to, ctx.today)}.`);
    if (hasDish(target)) lines.push(`${title(target)} dafür auf ${slotName(change.from, ctx.today)}.`);
    if (source.recipe_id) {
      const before = servingsFor(source, ctx.plan, ctx.members, ctx.attendance);
      const now = servingsFor(at(after.plan, change.to)!, after.plan, ctx.members, ctx.attendance);
      if (now !== before) {
        const n = Math.abs(now - before);
        lines.push(`${n} ${n === 1 ? "Portion" : "Portionen"} ${now > before ? "mehr" : "weniger"} (${now} statt ${before}).`);
      }
      if (now === 0) lines.push("Achtung: Dann ist niemand zum Essen da.");
    }
  }

  return { problem: null, plan: lines, shopping: shoppingDiff(ctx, after) };
}

/** Vergleicht die Einkaufsliste vor und nach der Änderung */
function shoppingDiff(ctx: ChangeContext, after: { plan: MealPlanEntry[]; purchases: Purchase[] }): string[] {
  const base = { recipes: ctx.recipes, members: ctx.members, attendance: ctx.attendance, pantry: ctx.pantry, today: ctx.today, now: ctx.now };
  const was = shoppingState({ ...base, plan: ctx.plan, purchases: ctx.purchases });
  const will = shoppingState({ ...base, plan: after.plan, purchases: after.purchases });

  type Row = { name: string; amount: number | null; unit: string | null };
  const flat = (s: typeof was) => new Map<string, Row>(s.open.flatMap((i) => i.rows.map((r) => [r.key, { name: r.name, amount: r.amount, unit: r.unit }] as const)));
  const before = flat(was);
  const next = flat(will);
  const more: string[] = [];
  const less: string[] = [];
  for (const [key, row] of next) {
    const old = before.get(key);
    if (!old) more.push(shoppingLine(row));
    else if (row.amount !== null && old.amount !== null && Math.abs(row.amount - old.amount) > 0.0005) {
      const delta = Number(Math.abs(row.amount - old.amount).toFixed(3));
      (row.amount > old.amount ? more : less).push(shoppingLine({ ...row, amount: delta }));
    }
  }
  for (const [key, row] of before) if (!next.has(key)) less.push(shoppingLine(row));

  const hadStock = new Set(was.stock.map((s) => s.key));
  const kept = will.stock.filter((s) => !hadStock.has(s.key)).map((s) => s.text);

  const out: string[] = [];
  if (more.length) out.push(`Zusätzlich auf der Liste: ${more.join(", ")}.`);
  if (less.length) out.push(`Nicht mehr nötig: ${less.join(", ")}.`);
  if (kept.length) out.push(`Schon gekauft und bleibt da: ${kept.join(", ")}.`);
  if (!out.length) out.push("Die Einkaufsliste bleibt, wie sie ist.");
  return out;
}

/** Nächste freie Mahlzeit derselben Art (z. B. der nächste Abend ohne Gericht), höchstens eine Woche voraus */
export function nextFreeSlot(plan: MealPlanEntry[], from: SlotRef, today: string): SlotRef | null {
  const start = from.date < today ? today : from.date;
  for (let i = 1; i <= 7; i++) {
    const slot = { date: addDays(start, i), meal: from.meal };
    if (!hasDish(at(plan, slot))) return slot;
  }
  return null;
}
