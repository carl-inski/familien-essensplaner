"use client";

// Die Mittwoch-Situation zum Ausprobieren. Kein Bild und keine Attrappe: Hier rechnet
// dieselbe Logik wie in der App (lib/plan-change.ts, lib/shopping.ts) mit einer
// Beispielwoche. Gespeichert wird nichts.

import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useMemo, useState } from "react";
import { IconCart, IconCheck, IconFork } from "@/components/icons";
import { applyChange, previewChange, type PlanChange } from "@/lib/plan-change";
import { servingsFor, shoppingLine } from "@/lib/planning";
import { parseAmount } from "@/lib/quantity";
import { purchasesFor, shoppingState, type Purchase } from "@/lib/shopping";
import type { Attendance, Ingredient, MealPlanEntry, Member, Recipe } from "@/lib/types";

// Beispielwoche: Mittwoch ist „heute“
const TODAY = "2026-11-11";
const NOW = "2026-11-11T16:30:00Z";
const WED = { date: "2026-11-11", meal: "abend" as const };
const FRI = { date: "2026-11-13", meal: "abend" as const };
const SAT = { date: "2026-11-14", meal: "abend" as const };
const DAY: Record<string, string> = { [WED.date]: "Mi", [FRI.date]: "Fr", [SAT.date]: "Sa" };

const ing = (name: string, amount_text: string | null, position: number): Ingredient => ({ position, group_name: null, name, amount_text, ...parseAmount(amount_text) });
const recipe = (id: string, title: string, list: [string, string | null][]) =>
  ({ id, title, image_url: null, servings: 4, diet: "vegetarisch", tags: [], categories: [], cookbook_id: null, ep_recipe_ingredients: list.map(([n, a], i) => ing(n, a, i)) }) as unknown as Recipe;

const RECIPES = new Map(
  [
    recipe("gnocchi", "Tomaten-Gnocchi", [["Gnocchi", "600 g"], ["Tomaten", "800 g"], ["Mozzarella", "2"], ["Basilikum", null]]),
    recipe("lachs", "Ofenlachs", [["Lachsfilet", "600 g"], ["Kartoffeln", "800 g"], ["Zitrone", "1"]]),
  ].map((r) => [r.id, r]),
);
const MEMBERS: Member[] = ["a", "b", "c"].map((id, position) => ({ id, household_id: "demo", name: id, email: null, user_id: null, role: "member", default_week: {}, position }));
const entry = (id: string, slot: { date: string; meal: "abend" }, recipe_id: string): MealPlanEntry => ({ id, household_id: "demo", ...slot, recipe_id, leftover_of: null, cook_id: null, cook2_id: null, servings_override: null, status: "geplant", note: null });
const PLAN = [entry("mi", WED, "gnocchi"), entry("sa", SAT, "lachs")];
const GUESTS: Attendance[] = [{ id: "g", member_id: "a", date: FRI.date, meal: "abend", status: "da", guests: 2 }];

// Für Mittwoch ist schon eingekauft, für drei Personen
const BOUGHT: Purchase[] = (() => {
  const s = shoppingState({ plan: [PLAN[0]], recipes: RECIPES, members: MEMBERS, attendance: [], purchases: [], today: TODAY, now: NOW });
  let n = 0;
  return s.open.flatMap((i) => purchasesFor(i, "demo", "a", () => `demo-${++n}`)).map((p) => ({ ...p, id: p.client_id, bought_at: NOW }));
})();
const BOUGHT_TEXT = BOUGHT.map((p) => shoppingLine(p)).join(", ");
const MOVE: PlanChange = { kind: "verschieben", from: WED, to: FRI };

export function LandingDemo() {
  const reduce = useReducedMotion();
  const [out, setOut] = useState(false);
  const [guests, setGuests] = useState(false);

  const view = useMemo(() => {
    const attendance = out && guests ? GUESTS : [];
    const ctx = { plan: PLAN, purchases: BOUGHT, recipes: RECIPES, members: MEMBERS, attendance, today: TODAY, now: NOW };
    const after = out ? applyChange(MOVE, PLAN, BOUGHT) : { plan: PLAN, purchases: BOUGHT };
    const list = shoppingState({ ...ctx, plan: after.plan, purchases: after.purchases });
    const rows = [WED, FRI, SAT].map((slot) => {
      const e = after.plan.find((p) => p.date === slot.date && p.recipe_id);
      return { day: DAY[slot.date], recipe: e ? RECIPES.get(e.recipe_id!)! : null, servings: e ? servingsFor(e, after.plan, MEMBERS, attendance) : 0, away: out && slot.date === WED.date };
    });
    return { rows, open: list.open, preview: out ? previewChange(MOVE, ctx) : null };
  }, [out, guests]);

  const spring = reduce ? { duration: 0 } : { type: "spring" as const, bounce: 0.15, duration: 0.45 };

  return (
    <div className="rounded-[22px] bg-surface p-4 sm:p-5" style={{ boxShadow: "var(--lift)" }}>
      <p className="text-[0.8125rem] font-semibold text-label-2">Probiert es aus: Mittwoch, 17:30 Uhr</p>
      <div className="mt-2.5 flex flex-wrap gap-2">
        <Toggle on={out} onClick={() => { setOut(!out); if (out) setGuests(false); }}>Heute essen wir auswärts</Toggle>
        <Toggle on={guests} disabled={!out} onClick={() => setGuests(!guests)}>Freitag kommen zwei Gäste</Toggle>
      </div>

      <ul className="mt-4 flex flex-col gap-1.5">
        {view.rows.map((row) => (
          <li key={row.day} className="flex min-h-[52px] items-center gap-3 rounded-[14px] bg-bg px-3 py-2">
            <span className="w-7 shrink-0 text-sm font-semibold text-label-2">{row.day}</span>
            <AnimatePresence mode="popLayout" initial={false}>
              {row.recipe ? (
                <motion.span key={row.recipe.id} layoutId={`dish-${row.recipe.id}`} transition={spring} className="flex min-w-0 flex-1 items-center gap-2.5">
                  <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[10px]" style={{ background: "var(--accent-soft)", color: "var(--accent)" }} aria-hidden>
                    <IconFork size={18} />
                  </span>
                  <span className="min-w-0 flex-1 truncate text-[0.9375rem] font-semibold">{row.recipe.title}</span>
                  <span className="shrink-0 text-sm tabular-nums text-label-2">für {row.servings}</span>
                </motion.span>
              ) : (
                <motion.span key="leer" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="flex-1 text-[0.9375rem] text-label-2">
                  {row.away ? "Auswärts" : "Noch frei"}
                </motion.span>
              )}
            </AnimatePresence>
          </li>
        ))}
      </ul>

      <div className="mt-4 border-t border-separator pt-3.5" aria-live="polite">
        <p className="min-h-[2.75rem] text-[0.9375rem] leading-snug">
          {view.preview ? (
            <>
              <strong className="font-semibold">{view.preview.plan.join(" ")}</strong> {view.preview.shopping.join(" ")}
            </>
          ) : (
            <span className="text-label-2">Für Mittwoch ist schon eingekauft. Auf der Liste steht nur noch der Samstag.</span>
          )}
        </p>
        <p className="mt-3 flex items-center gap-1.5 text-[0.8125rem] font-semibold text-label-2">
          <IconCart size={15} /> Einkaufsliste
        </p>
        <ul className="mt-1.5 flex flex-wrap gap-1.5">
          <AnimatePresence initial={false}>
            {view.open.map((item) => (
              <motion.li
                key={item.key}
                layout={!reduce}
                initial={reduce ? false : { opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={reduce ? { opacity: 0 } : { opacity: 0, scale: 0.9 }}
                transition={spring}
                className="rounded-full px-2.5 py-1 text-sm font-medium"
                // Hervorgehoben: was durch die Änderung dazukommt (alles außer dem Samstag)
                style={item.rows.some((r) => r.parts.some((x) => x.entryId !== "sa")) ? { background: "var(--accent-soft)", color: "var(--accent)" } : { background: "var(--fill)" }}
              >
                {item.text}
              </motion.li>
            ))}
          </AnimatePresence>
        </ul>
        <p className="mt-2.5 flex items-center gap-1.5 text-[0.8125rem] text-label-2">
          <IconCheck size={14} className="shrink-0" /> Schon gekauft: {BOUGHT_TEXT}
        </p>
      </div>
    </div>
  );
}

function Toggle({ on, disabled, onClick, children }: { on: boolean; disabled?: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      disabled={disabled}
      onClick={onClick}
      className="inline-flex min-h-[40px] items-center gap-2 rounded-full px-3.5 text-[0.9375rem] font-semibold transition-[background-color,color,transform] duration-200 active:scale-[0.97] disabled:opacity-40"
      style={{ background: on ? "var(--accent)" : "var(--accent-soft)", color: on ? "var(--on-accent)" : "var(--accent)" }}
    >
      <span className="flex h-4 w-4 items-center justify-center rounded-full" style={{ boxShadow: on ? undefined : "inset 0 0 0 1.5px currentColor", background: on ? "var(--on-accent)" : undefined, color: on ? "var(--accent)" : undefined }} aria-hidden>
        {on && <IconCheck size={11} strokeWidth={3.2} />}
      </span>
      {children}
    </button>
  );
}
