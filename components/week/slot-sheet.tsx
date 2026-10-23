"use client";

import Link from "next/link";
import { useState } from "react";
import { useApp } from "@/components/app-data";
import { IconChevronRight, IconSparkles, IconTrash } from "@/components/icons";
import { Sheet } from "@/components/sheet";
import { useToast } from "@/components/toast";
import { Avatar, DietIcon, RecipeImage, Section, Segmented, Stepper } from "@/components/ui";
import { WEEKDAY_LONG, formatDateDE, weekdayIndex } from "@/lib/dates";
import { effectiveStatus, presentMembers, servingsFor } from "@/lib/planning";
import type { MealPlanEntry, PlanStatus } from "@/lib/types";
import { MEAL, type useWeek } from "./use-week";

interface Props {
  date: string | null;
  onClose: () => void;
  week: ReturnType<typeof useWeek>;
  onChangeRecipe: (date: string) => void;
  onSuggest: (date: string) => void;
  onCooked: (entry: MealPlanEntry, cooked: boolean) => void;
}

export function SlotSheet({ date, onClose, week, onChangeRecipe, onSuggest, onCooked }: Props) {
  return (
    <Sheet open={date !== null} onClose={onClose} title={date ? `${WEEKDAY_LONG[weekdayIndex(date)]}, ${formatDateDE(date, { day: "numeric", month: "long" })}` : ""}>
      {date && <SlotContent date={date} week={week} onChangeRecipe={onChangeRecipe} onSuggest={onSuggest} onCooked={onCooked} />}
    </Sheet>
  );
}

function SlotContent({ date, week, onChangeRecipe, onSuggest, onCooked }: Omit<Props, "date" | "onClose"> & { date: string }) {
  const { members, recipesById, cookbooksById, today } = useApp();
  const toast = useToast();
  const { plan, attendance, upsertSlot, setStatus } = week;
  const entry = plan.find((p) => p.date === date && p.meal === MEAL) ?? null;
  const recipe = entry?.recipe_id ? recipesById.get(entry.recipe_id) : null;
  const present = presentMembers(members, attendance, date, MEAL);
  const book = recipe?.cookbook_id ? cookbooksById.get(recipe.cookbook_id) : null;
  const [note, setNote] = useState(entry?.note ?? "");
  const [noteFor, setNoteFor] = useState(entry?.note);
  if (noteFor !== entry?.note) {
    // Notiz wurde woanders geändert (Realtime)
    setNoteFor(entry?.note);
    setNote(entry?.note ?? "");
  }

  const autoServings = entry ? servingsFor({ ...entry, servings_override: null }, plan, members, attendance) : present.length;
  const servings = entry?.servings_override ?? autoServings;

  // Frühere Slots dieser Woche mit Rezept → als Reste-Quelle wählbar
  const leftoverSources = plan.filter((p) => p.date < date && p.recipe_id && !p.leftover_of && p.status !== "ausgefallen");

  async function save(patch: Partial<MealPlanEntry>) {
    const { error } = await upsertSlot(date, patch);
    if (error) toast({ text: error.message.includes("Abwesende") ? "Abwesende Personen können nicht kochen." : error.message, tone: "error" });
  }

  return (
    <div className="pb-4">
      <Section title="Gericht">
        <div className="group">
          {recipe ? (
            <Link href={`/rezepte/${recipe.id}`} className="row pressable">
              <RecipeImage recipe={recipe} className="h-12 w-12 shrink-0 text-sm" rounded={10} />
              <span className="min-w-0 flex-1">
                <span className="t-headline flex items-center gap-1.5"><span className="truncate">{recipe.title}</span><DietIcon diet={recipe.diet} size={15} /></span>
                <span className="t-footnote block truncate" style={{ color: "var(--label-2)" }}>
                  {book ? `aus deinem Regal · ${book.title}${recipe.cookbook_page ? `, S. ${recipe.cookbook_page}` : ""}` : "Rezept öffnen"}
                </span>
              </span>
              <IconChevronRight size={18} style={{ color: "var(--label-3)" }} />
            </Link>
          ) : entry?.leftover_of ? (
            <div className="row t-sub">Reste von {(() => {
              const src = plan.find((p) => p.id === entry.leftover_of);
              return src ? `${WEEKDAY_LONG[weekdayIndex(src.date)]} (${recipesById.get(src.recipe_id!)?.title ?? "?"})` : "–";
            })()}</div>
          ) : (
            <div className="row t-sub" style={{ color: "var(--label-2)" }}>Noch nichts geplant</div>
          )}
          <div className="flex flex-wrap gap-2 px-4 py-3">
            <button className="btn btn-tinted btn-sm pressable" onClick={() => onChangeRecipe(date)}>{recipe ? "Ändern" : "Rezept wählen"}</button>
            <button className="btn btn-gray btn-sm pressable" onClick={() => onSuggest(date)}><IconSparkles size={16} /> Vorschlag</button>
            {(recipe || entry?.leftover_of) && (
              <button className="btn btn-gray btn-sm pressable" style={{ color: "var(--red)" }} onClick={() => save({ recipe_id: null, leftover_of: null, status: "geplant", servings_override: null })}>
                <IconTrash size={16} /> Entfernen
              </button>
            )}
          </div>
        </div>
        {leftoverSources.length > 0 && (
          <div className="scroll-x mt-2 flex gap-2 px-1">
            <span className="t-footnote shrink-0 self-center pl-3" style={{ color: "var(--label-2)" }}>Reste von:</span>
            {leftoverSources.map((src) => (
              <button
                key={src.id}
                className="chip pressable shrink-0"
                data-on={entry?.leftover_of === src.id}
                onClick={() => save({ recipe_id: null, leftover_of: entry?.leftover_of === src.id ? null : src.id, status: "geplant" })}
              >
                {WEEKDAY_LONG[weekdayIndex(src.date)].slice(0, 2)} · {recipesById.get(src.recipe_id!)?.title}
              </button>
            ))}
          </div>
        )}
      </Section>

      {entry && (recipe || entry.leftover_of) && (
        <>
          {recipe && (
            <Section title="Portionen" footer={entry.servings_override ? `Automatisch wären es ${autoServings}.` : "Automatisch aus Anwesenheit, Gästen und Resten."}>
              <div className="group">
                <div className="row justify-between">
                  <span className="t-sub">{entry.servings_override ? "Manuell" : "Automatisch"}</span>
                  <div className="flex items-center gap-2">
                    {entry.servings_override && (
                      <button className="btn-plain t-footnote pressable" onClick={() => save({ servings_override: null })}>Zurücksetzen</button>
                    )}
                    <Stepper label="Portionen" value={servings} min={1} max={40} onChange={(v) => save({ servings_override: v })} />
                  </div>
                </div>
              </div>
            </Section>
          )}

          <Section title="Kochdienst" footer="Nur anwesende Personen können kochen.">
            <div className="card px-4 py-3">
              <p className="t-footnote mb-2" style={{ color: "var(--label-2)" }}>Kocht</p>
              <div className="flex flex-wrap gap-2">
                {members.map((m) => {
                  const here = effectiveStatus(m, date, MEAL, attendance).status === "da";
                  return (
                    <button key={m.id} className="chip pressable" data-on={entry.cook_id === m.id} disabled={!here} style={!here ? { opacity: 0.35 } : undefined}
                      onClick={() => save({ cook_id: entry.cook_id === m.id ? null : m.id, cook2_id: entry.cook2_id === m.id ? null : entry.cook2_id })}>
                      <Avatar member={m} size={20} dim={!here} /> {m.name}
                    </button>
                  );
                })}
              </div>
              {entry.cook_id && (
                <>
                  <p className="t-footnote mt-3 mb-2" style={{ color: "var(--label-2)" }}>Hilft (optional)</p>
                  <div className="flex flex-wrap gap-2">
                    {members.filter((m) => m.id !== entry.cook_id).map((m) => {
                      const here = effectiveStatus(m, date, MEAL, attendance).status === "da";
                      return (
                        <button key={m.id} className="chip pressable" data-on={entry.cook2_id === m.id} disabled={!here} style={!here ? { opacity: 0.35 } : undefined}
                          onClick={() => save({ cook2_id: entry.cook2_id === m.id ? null : m.id })}>
                          {m.name}
                        </button>
                      );
                    })}
                  </div>
                </>
              )}
            </div>
          </Section>

          <Section title="Status">
            <Segmented<PlanStatus>
              label="Status"
              value={entry.status}
              onChange={(s) => (s === "gekocht" || entry.status === "gekocht" ? onCooked(entry, s === "gekocht") : save({ status: s }))}
              options={[
                { value: "geplant", label: "Geplant" },
                ...(date <= today && recipe ? [{ value: "gekocht" as PlanStatus, label: "Gekocht ✓" }] : []),
                { value: "ausgefallen", label: "Ausgefallen" },
              ]}
            />
          </Section>
        </>
      )}

      <Section title="Wer isst mit?" footer="Gäste zählen bei den Portionen und im Einkauf mit.">
        <div className="group">
          {members.map((m) => {
            const s = effectiveStatus(m, date, MEAL, attendance);
            return (
              <div key={m.id} className="row">
                <Avatar member={m} size={28} dim={s.status === "weg"} />
                <span className="t-sub flex-1">{m.name}</span>
                {s.status === "da" && (
                  <Stepper label={`Gäste von ${m.name}`} value={s.guests} max={20} onChange={(g) => void setStatus(m.id, date, "da", g)} />
                )}
                <button className="chip pressable" data-on={s.status === "da"} onClick={() => void setStatus(m.id, date, s.status === "da" ? "weg" : "da")}>
                  {s.status === "da" ? "da" : "weg"}
                </button>
              </div>
            );
          })}
        </div>
      </Section>

      <Section title="Notiz">
        <textarea
          className="input"
          placeholder="z. B. doppelt kochen fürs Mittagessen"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          onBlur={() => note !== (entry?.note ?? "") && save({ note: note || null })}
        />
      </Section>
    </div>
  );
}
