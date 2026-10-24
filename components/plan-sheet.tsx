"use client";

// Einplanen eines Rezepts: Tag und Mahlzeit (Mittag/Abend) der nächsten zwei Wochen wählen

import { useEffect, useState } from "react";
import { useApp } from "./app-data";
import { Sheet } from "./sheet";
import { useToast } from "./toast";
import { WEEKDAY_LONG, addDays, formatDateDE, weekdayIndex } from "@/lib/dates";
import { MEALS, MEAL_LABEL } from "@/lib/meals";
import type { Meal, MealPlanEntry, Recipe } from "@/lib/types";

export function PlanSheet({ recipe, onClose }: { recipe: Recipe | null; onClose: () => void }) {
  return (
    <Sheet open={!!recipe} onClose={onClose} title={recipe ? `${recipe.title} einplanen` : ""}>
      {recipe && <PlanList recipe={recipe} onDone={onClose} />}
    </Sheet>
  );
}

function PlanList({ recipe, onDone }: { recipe: Recipe; onDone: () => void }) {
  const { sb, household, today, recipesById } = useApp();
  const toast = useToast();
  const [upcoming, setUpcoming] = useState<MealPlanEntry[]>([]);
  const days = Array.from({ length: 14 }, (_, i) => addDays(today, i));

  useEffect(() => {
    let cancelled = false;
    sb.from("ep_meal_plan")
      .select("*")
      .gte("date", today)
      .lte("date", addDays(today, 13))
      .then(({ data }) => !cancelled && setUpcoming((data ?? []) as MealPlanEntry[]));
    return () => {
      cancelled = true;
    };
  }, [sb, today]);

  async function planOn(date: string, meal: Meal) {
    const { error } = await sb
      .from("ep_meal_plan")
      .upsert({ household_id: household.id, date, meal, recipe_id: recipe.id, leftover_of: null, status: "geplant" }, { onConflict: "household_id,date,meal" });
    onDone();
    toast(
      error
        ? { text: error.message, tone: "error" }
        : { text: `${recipe.title}: ${WEEKDAY_LONG[weekdayIndex(date)]}, ${formatDateDE(date, { day: "numeric", month: "numeric" })} · ${MEAL_LABEL[meal]}` },
    );
  }

  return (
    <ul className="group">
      {days.map((d) => (
        <li key={d} className="row flex-col !items-stretch gap-2">
          <span className="t-sub font-medium">
            {WEEKDAY_LONG[weekdayIndex(d)]}, {formatDateDE(d, { day: "numeric", month: "long" })}
          </span>
          <div className="grid grid-cols-2 gap-2">
            {MEALS.map((meal) => {
              const e = upcoming.find((u) => u.date === d && u.meal === meal);
              const current = e?.recipe_id ? recipesById.get(e.recipe_id)?.title : e?.leftover_of ? "Reste" : null;
              return (
                <button
                  key={meal}
                  className="pressable flex min-h-11 flex-col items-start justify-center rounded-xl px-3 py-1.5 text-left"
                  style={{ background: current ? "var(--fill)" : "var(--accent-soft)" }}
                  onClick={() => planOn(d, meal)}
                >
                  <span className="t-footnote font-semibold" style={{ color: current ? "var(--label)" : "var(--accent)" }}>{MEAL_LABEL[meal]}</span>
                  <span className="t-caption w-full truncate" style={{ color: "var(--label-2)" }}>{current ? `ersetzt: ${current}` : "frei"}</span>
                </button>
              );
            })}
          </div>
        </li>
      ))}
    </ul>
  );
}
