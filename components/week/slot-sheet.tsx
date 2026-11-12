"use client";

import Link from "next/link";
import { DetailLink } from "@/components/detail-nav";
import { useState } from "react";
import { PlanChangeSheet, type ChangeIntent } from "./plan-change";
import { useApp } from "@/components/app-data";
import { IconChevronRight, IconDice, IconSparkles, IconTrash } from "@/components/icons";
import { Sheet } from "@/components/sheet";
import { useToast } from "@/components/toast";
import { Avatar, DietIcon, RecipeImage, Section, Segmented, Stepper } from "@/components/ui";
import { WEEKDAY_LONG, formatDateDE, weekdayIndex } from "@/lib/dates";
import { effectiveStatus, presentMembers, servingsFor } from "@/lib/planning";
import { MEAL_LABEL, slotKey } from "@/lib/meals";
import type { Meal, MealPlanEntry, PlanStatus } from "@/lib/types";
import type { useWeek } from "./use-week";

export interface Slot {
  date: string;
  meal: Meal;
}

interface Props {
  slot: Slot | null;
  onClose: () => void;
  week: ReturnType<typeof useWeek>;
  onChangeRecipe: (slot: Slot) => void;
  onSuggest: (slot: Slot) => void;
}

export function SlotSheet({ slot, onClose, week, onChangeRecipe, onSuggest }: Props) {
  return (
    <Sheet
      open={slot !== null}
      onClose={onClose}
      title={slot ? `${WEEKDAY_LONG[weekdayIndex(slot.date)].slice(0, 2)}, ${formatDateDE(slot.date, { day: "numeric", month: "short" })} · ${MEAL_LABEL[slot.meal]}` : ""}
    >
      {slot && <SlotContent slot={slot} week={week} onChangeRecipe={onChangeRecipe} onSuggest={onSuggest} />}
    </Sheet>
  );
}

function SlotContent({ slot, week, onChangeRecipe, onSuggest }: Omit<Props, "slot" | "onClose"> & { slot: Slot }) {
  const { date, meal } = slot;
  const { members, recipesById, cookbooksById, today } = useApp();
  const toast = useToast();
  const { plan, attendance, upsertSlot, setStatus } = week;
  const entry = plan.find((p) => p.date === date && p.meal === meal) ?? null;
  const recipe = entry?.recipe_id ? recipesById.get(entry.recipe_id) : null;
  const present = presentMembers(members, attendance, date, meal);
  const book = recipe?.cookbook_id ? cookbooksById.get(recipe.cookbook_id) : null;
  const [changing, setChanging] = useState<ChangeIntent | null>(null);
  // Verschieben und Auswärts: nur für geplante Gerichte ab heute
  const movable = !!entry && (!!recipe || !!entry.leftover_of) && date >= today && entry.status !== "ausgefallen";
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
  const here = slotKey(date, meal);
  const leftoverSources = plan
    .filter((p) => slotKey(p.date, p.meal) < here && p.recipe_id && !p.leftover_of && p.status !== "ausgefallen")
    .sort((a, b) => slotKey(a.date, a.meal).localeCompare(slotKey(b.date, b.meal)));

  async function save(patch: Partial<MealPlanEntry>) {
    const { error } = await upsertSlot(date, meal, patch);
    if (error) toast({ text: error.message.includes("Abwesende") ? "Abwesende Personen können nicht kochen." : error.message, tone: "error" });
  }

  return (
    <div className="pb-4">
      <Section title="Gericht">
        <div className="group">
          {recipe ? (
            <DetailLink kind="r" id={recipe.id} className="row pressable">
              <RecipeImage recipe={recipe} className="h-12 w-12 shrink-0 text-sm" rounded={10} />
              <span className="min-w-0 flex-1">
                <span className="t-headline flex items-center gap-1.5"><span className="truncate">{recipe.title}</span><DietIcon diet={recipe.diet} size={15} /></span>
                <span className="t-footnote block truncate" style={{ color: "var(--label-2)" }}>
                  {book ? `aus deinem Regal · ${book.title}${recipe.cookbook_page ? `, S. ${recipe.cookbook_page}` : ""}` : "Rezept öffnen"}
                </span>
              </span>
              <IconChevronRight size={18} style={{ color: "var(--label-3)" }} />
            </DetailLink>
          ) : entry?.leftover_of ? (
            <div className="row t-sub">Reste von {(() => {
              const src = plan.find((p) => p.id === entry.leftover_of);
              return src ? `${WEEKDAY_LONG[weekdayIndex(src.date)]} ${MEAL_LABEL[src.meal]} (${recipesById.get(src.recipe_id!)?.title ?? "?"})` : "–";
            })()}</div>
          ) : (
            <div className="row t-sub" style={{ color: "var(--label-2)" }}>Noch nichts geplant</div>
          )}
          <div className="flex flex-wrap gap-2 px-4 py-3">
            <button className="btn btn-tinted btn-sm pressable" onClick={() => onChangeRecipe(slot)}>{recipe ? "Ändern" : "Rezept wählen"}</button>
            <button className="btn btn-gray btn-sm pressable" onClick={() => onSuggest(slot)}><IconSparkles size={16} /> Vorschlag</button>
            {date >= today && <Link className="btn btn-gray btn-sm pressable" href={`/entscheiden?datum=${date}&mahlzeit=${meal}`}><IconDice size={16} /> Ausspielen</Link>}
            {movable && (
              <>
                <button className="btn btn-gray btn-sm pressable" onClick={() => setChanging({ kind: "verschieben", from: slot })}>Verschieben</button>
                <button className="btn btn-gray btn-sm pressable" onClick={() => setChanging({ kind: "auswaerts", slot })}>Auswärts</button>
              </>
            )}
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
                {WEEKDAY_LONG[weekdayIndex(src.date)].slice(0, 2)} {MEAL_LABEL[src.meal]} · {recipesById.get(src.recipe_id!)?.title}
              </button>
            ))}
          </div>
        )}
      </Section>

      <Section title="Wer isst mit?" footer="Die Zahl zählt die Person mit, + für mitgebrachte Gäste. Auf 0 heißt: nicht da.">
        <div className="group">
          {members.map((m) => {
            const s = effectiveStatus(m, date, meal, attendance);
            const count = s.status === "da" ? 1 + s.guests : 0;
            return (
              <div key={m.id} className="row">
                <Avatar member={m} size={28} dim={s.status === "weg"} />
                <span className="min-w-0 flex-1">
                  <span className="t-sub block" style={s.status === "weg" ? { color: "var(--label-2)" } : undefined}>{m.name}</span>
                  {(s.status === "weg" || s.guests > 0) && (
                    <span className="t-caption block" style={{ color: "var(--label-2)" }}>
                      {s.status === "weg" ? "nicht da" : `mit ${s.guests} ${s.guests === 1 ? "Gast" : "Gästen"}`}
                    </span>
                  )}
                </span>
                <Stepper
                  label={`${m.name} und Gäste`}
                  value={count}
                  max={21}
                  onChange={(n) => void (n === 0 ? setStatus(m.id, date, meal, "weg") : setStatus(m.id, date, meal, "da", n - 1))}
                />
              </div>
            );
          })}
        </div>
      </Section>

      {entry && (recipe || entry.leftover_of) && (
        <>
          {recipe && (
            <Section title="Portionen" footer={entry.servings_override ? `Automatisch wären es ${autoServings}.` : "Automatisch aus Anwesenheit, Gästen und Resten."}>
              <div className="group">
                <div className="row justify-between">
                  <span className="t-sub">{entry.servings_override ? "Von Hand" : "Automatisch"}</span>
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
                  const here = effectiveStatus(m, date, meal, attendance).status === "da";
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
                      const here = effectiveStatus(m, date, meal, attendance).status === "da";
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
              onChange={(s) => save({ status: s })}
              // Ist der Tag vorbei, gilt ein Gericht von selbst als gekocht
              options={[
                date < today && recipe ? { value: "gekocht" as PlanStatus, label: "Gekocht" } : { value: "geplant" as PlanStatus, label: "Geplant" },
                { value: "ausgefallen", label: "Ausgefallen" },
              ]}
            />
          </Section>
        </>
      )}

      <PlanChangeSheet intent={changing} onClose={() => setChanging(null)} onDone={() => { setChanging(null); void week.reload(); }} />

      <Section title="Notiz">
        <textarea
          className="input"
          placeholder={meal === "abend" ? "z. B. doppelt kochen fürs Mittagessen morgen" : "z. B. Reste vom Vorabend"}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          onBlur={() => note !== (entry?.note ?? "") && save({ note: note || null })}
        />
      </Section>
    </div>
  );
}
