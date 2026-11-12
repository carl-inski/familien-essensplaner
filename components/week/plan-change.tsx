"use client";

// „Was ändert sich?“ – eine Karte für jede Planänderung, egal ob von Hand
// („Heute auswärts“, „Verschieben“ im Wochenplan) oder als Vorschlag der KI.
// Die Vorschau rechnet lib/plan-change.ts; geschrieben wird erst nach „Übernehmen“.

import { useMemo, useState } from "react";
import { useApp } from "@/components/app-data";
import { IconCalendar, IconCart } from "@/components/icons";
import { usePantry } from "@/components/pantry";
import { Sheet } from "@/components/sheet";
import { useShopping } from "@/components/shopping/use-shopping";
import { useToast } from "@/components/toast";
import { WEEKDAY_SHORT, addDays, formatDateDE, weekdayIndex } from "@/lib/dates";
import { haptic } from "@/lib/haptics";
import { MEALS, MEAL_LABEL } from "@/lib/meals";
import { changeProblem, nextFreeSlot, previewChange, slotName, type ChangePreview, type PlanChange, type SlotRef } from "@/lib/plan-change";
import type { MealPlanEntry } from "@/lib/types";

/** Vorschau für eine Änderung und die Funktion, die sie wirklich ausführt */
export function usePlanChange(change: PlanChange | null) {
  const { sb, recipesById, members, today } = useApp();
  const { plan, attendance, purchases, loaded, reload } = useShopping();
  const pantry = usePantry();
  // Zeitpunkt der Vorschau: einmal beim Öffnen genügt
  const [now] = useState(() => new Date().toISOString());

  const preview: ChangePreview | null = useMemo(
    () => (change && loaded ? previewChange(change, { plan, purchases, recipes: recipesById, members, attendance, pantry: pantry.set, today, now }) : null),
    [change, loaded, plan, purchases, recipesById, members, attendance, pantry.set, today, now],
  );

  /** Schreibt die Änderung. Die Datenbank prüft dieselben Regeln noch einmal. */
  async function commit(): Promise<string | null> {
    if (!change) return "Keine Änderung";
    const problem = changeProblem(change, plan, today);
    if (problem) return problem;
    if (change.kind === "auswaerts") {
      const entry = plan.find((p) => p.date === change.slot.date && p.meal === change.slot.meal)!;
      const { error } = await sb.from("ep_meal_plan").update({ status: "ausgefallen", note: entry.note ?? "Auswärts essen" }).eq("id", entry.id);
      if (error) return error.message;
    } else {
      const { error } = await sb.rpc("ep_plan_move", { p_from_date: change.from.date, p_from_meal: change.from.meal, p_to_date: change.to.date, p_to_meal: change.to.meal });
      if (error) return error.message;
    }
    await reload();
    return null;
  }

  return { preview, plan, loaded, commit };
}

/** Die Vorschau selbst: erst der Plan, dann der Einkauf */
export function ChangeLines({ preview }: { preview: ChangePreview | null }) {
  if (!preview) return <div className="skeleton h-16 w-full" style={{ borderRadius: 12 }} aria-busy="true" />;
  if (preview.problem) return <p className="t-sub" style={{ color: "var(--red)" }}>{preview.problem}</p>;
  return (
    <div className="flex flex-col gap-2.5">
      <p className="t-sub flex gap-2.5">
        <IconCalendar size={18} className="mt-0.5 shrink-0" style={{ color: "var(--accent)" }} />
        <span className="font-medium">{preview.plan.join(" ")}</span>
      </p>
      <p className="t-sub flex gap-2.5">
        <IconCart size={18} className="mt-0.5 shrink-0" style={{ color: "var(--accent)" }} />
        <span>{preview.shopping.join(" ")}</span>
      </p>
    </div>
  );
}

export type ChangeIntent = { kind: "auswaerts"; slot: SlotRef } | { kind: "verschieben"; from: SlotRef };

/** Fenster aus dem Wochenplan: bei „Verschieben“ erst das Ziel wählen, dann bestätigen */
export function PlanChangeSheet({ intent, onClose, onDone }: { intent: ChangeIntent | null; onClose: () => void; onDone: () => void }) {
  return (
    <Sheet open={intent !== null} onClose={onClose} title={intent?.kind === "auswaerts" ? "Auswärts essen" : "Gericht verschieben"}>
      {intent && <Body key={JSON.stringify(intent)} intent={intent} onDone={onDone} />}
    </Sheet>
  );
}

function Body({ intent, onDone }: { intent: ChangeIntent; onDone: () => void }) {
  const { today, recipesById } = useApp();
  const toast = useToast();
  const [change, setChange] = useState<PlanChange | null>(intent.kind === "auswaerts" ? intent : null);
  const { preview, plan, loaded, commit } = usePlanChange(change);
  const [busy, setBusy] = useState(false);
  const from = intent.kind === "auswaerts" ? intent.slot : intent.from;
  const free = intent.kind === "auswaerts" && loaded ? nextFreeSlot(plan, from, today) : null;

  async function apply() {
    setBusy(true);
    const error = await commit();
    setBusy(false);
    if (error) return toast({ text: error, tone: "error" });
    haptic("success");
    toast({ text: preview?.plan[0] ?? "Geändert" });
    onDone();
  }

  // Ziele: die nächsten acht Tage, beide Mahlzeiten – ohne die Mahlzeit selbst
  const targets: SlotRef[] = Array.from({ length: 8 }, (_, i) => addDays(today, i))
    .flatMap((date) => MEALS.map((meal) => ({ date, meal })))
    .filter((s) => !(s.date === from.date && s.meal === from.meal));
  const dishAt = (s: SlotRef): MealPlanEntry | undefined => plan.find((p) => p.date === s.date && p.meal === s.meal && (p.recipe_id || p.leftover_of));
  const days = [...new Set(targets.map((t) => t.date))];

  return (
    <div className="flex flex-col gap-4 pb-4">
      {intent.kind === "verschieben" && (
        <div>
          <p className="t-section mb-2">Wohin?</p>
          <ul className="group" role="radiogroup" aria-label="Ziel">
            {days.map((date) => (
              <li key={date} className="row !py-2">
                <span className="t-sub w-16 shrink-0 font-medium">{date === today ? "Heute" : `${WEEKDAY_SHORT[weekdayIndex(date)]} ${formatDateDE(date, { day: "numeric", month: "numeric" })}`}</span>
                <span className="flex min-w-0 flex-1 flex-wrap justify-end gap-1.5">
                  {targets.filter((t) => t.date === date).map((t) => {
                    const on = change?.kind === "verschieben" && change.to.date === t.date && change.to.meal === t.meal;
                    const there = dishAt(t);
                    const title = there ? (there.recipe_id ? recipesById.get(there.recipe_id)?.title ?? "Gericht" : "Reste") : null;
                    return (
                      <button key={t.meal} role="radio" aria-checked={on} className="chip pressable max-w-full" data-on={on} onClick={() => setChange({ kind: "verschieben", from, to: t })}>
                        <span className="truncate">{MEAL_LABEL[t.meal]}{title ? ` · tauscht mit ${title}` : ""}</span>
                      </button>
                    );
                  })}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {change && (
        <div className="card px-4 py-3" role="status" aria-label="Was ändert sich?">
          <p className="t-section mb-2">Was ändert sich?</p>
          <ChangeLines preview={preview} />
        </div>
      )}

      <button className="btn btn-primary pressable w-full" disabled={busy || !change || !preview || !!preview.problem} onClick={apply}>
        {busy ? "Speichert …" : !change ? "Ziel wählen" : change.kind === "auswaerts" ? "Gericht ausfallen lassen" : "Verschieben"}
      </button>
      {free && change?.kind === "auswaerts" && (
        <button className="btn btn-tinted pressable w-full" disabled={busy} onClick={() => setChange({ kind: "verschieben", from, to: free })}>
          Lieber auf {slotName(free, today)} verschieben
        </button>
      )}
    </div>
  );
}
