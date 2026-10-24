"use client";

import { motion, useReducedMotion } from "motion/react";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { useApp } from "@/components/app-data";
import { IconChevronLeft, IconChevronRight, IconChef, IconCheck, IconLeftovers, IconPeople, IconPlus, IconSparkles, IconWarning } from "@/components/icons";
import { AccountButton } from "@/components/account-button";
import { AiPromptBar } from "@/components/assistant/ai-panel";
import { useAssistant } from "@/components/assistant/assistant-provider";
import { IconButton, PageHeader } from "@/components/nav";
import { RecipePicker } from "@/components/recipe-picker";
import { useToast } from "@/components/toast";
import { Avatar, DIET_LABEL, DietIcon, RecipeImage } from "@/components/ui";
import { useIsDesktop } from "@/components/use-media";
import { SlotSheet, type Slot } from "@/components/week/slot-sheet";
import { MEALS, useWeek } from "@/components/week/use-week";
import { WEEKDAY_LONG, WEEKDAY_SHORT, formatDateDE, parseISODate, isoWeekString, shiftWeek, weekNumberLabel, weekdayIndex } from "@/lib/dates";
import { MEAL_LABEL, slotKey } from "@/lib/meals";
import { eaters, effectiveStatus, servingsFor } from "@/lib/planning";
import { isDinnerCandidate, meatRuleHint, pickSuggestion, type PlannedDish } from "@/lib/suggest";
import type { Meal, MealPlanEntry, Recipe } from "@/lib/types";
import { inBackground } from "@/lib/background";

export default function WeekPage() {
  return (
    <Suspense>
      <Week />
    </Suspense>
  );
}

function Week() {
  const params = useSearchParams();
  const router = useRouter();
  const app = useApp();
  const { today, members, recipes, recipesById, stats, cookbooksById, sb, reloadHistory } = app;
  const toast = useToast();
  const isoWeek = params.get("w") ?? isoWeekString(today);
  const week = useWeek(isoWeek);
  const { dates, attendance, plan, setStatus, upsertSlot } = week;
  const [pickerFor, setPickerFor] = useState<Slot | null>(null);
  const [sheetFor, setSheetFor] = useState<Slot | null>(null);
  const desktop = useIsDesktop();
  const { ask } = useAssistant();
  const reduce = useReducedMotion();

  // Richtung des letzten Wochenwechsels: die neue Woche kommt von dort, wohin man geblättert hat
  const [shown, setShown] = useState({ week: isoWeek, dir: 0 });
  if (shown.week !== isoWeek) setShown({ week: isoWeek, dir: isoWeek > shown.week ? 1 : -1 });
  const enter = {
    initial: reduce || !shown.dir ? { opacity: 0 } : { opacity: 0, x: shown.dir * 32 },
    animate: { opacity: 1, x: 0 },
    transition: reduce ? { duration: 0.15 } : { type: "spring" as const, bounce: 0, duration: 0.35 },
  };

  const go = (w: string) => router.replace(`/woche?w=${w}`, { scroll: false });

  // Computer: ← und → blättern durch die Wochen, solange kein Feld und kein Dialog den Fokus hat
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || (e.key !== "ArrowLeft" && e.key !== "ArrowRight")) return;
      const t = e.target as HTMLElement | null;
      if (t?.closest("input, textarea, select, [contenteditable], [role=dialog]") || document.querySelector("[role=dialog]")) return;
      e.preventDefault();
      router.replace(`/woche?w=${shiftWeek(isoWeek, e.key === "ArrowLeft" ? -1 : 1)}`, { scroll: false });
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [isoWeek, router]);

  // Für die Fleischregel zählt die Reihenfolge der Gerichte: Mo mittag, Mo abend, Di mittag, …
  const plannedDishes = (exclude?: Slot): PlannedDish[] =>
    plan
      .filter((p) => p.recipe_id && p.status !== "ausgefallen" && !(exclude && p.date === exclude.date && p.meal === exclude.meal))
      .map((p) => ({ date: slotKey(p.date, p.meal), recipe_id: p.recipe_id, diet: recipesById.get(p.recipe_id!)?.diet ?? null }));

  async function planRecipe(slot: Slot, recipe: Recipe) {
    const hint = meatRuleHint(plannedDishes(slot), slotKey(slot.date, slot.meal), recipe.diet);
    const { error } = await upsertSlot(slot.date, slot.meal, { recipe_id: recipe.id, leftover_of: null, status: "geplant" });
    if (error) toast({ text: error.message, tone: "error" });
    else if (hint) toast({ text: hint, tone: "warning" });
  }

  async function suggest(slot: Slot, avoid: string[] = []) {
    const pool = recipes.filter((r) => !avoid.includes(r.id) && isDinnerCandidate(r));
    const pick = pickSuggestion(pool, stats, plannedDishes(slot), slotKey(slot.date, slot.meal), today);
    if (!pick) {
      toast({ text: "Kein passender Vorschlag – alles kürzlich gekocht oder die Fleischregel greift." });
      return;
    }
    const recipe = recipesById.get(pick.id)!;
    const { error } = await upsertSlot(slot.date, slot.meal, { recipe_id: recipe.id, leftover_of: null, status: "geplant" });
    if (error) return toast({ text: error.message, tone: "error" });
    inBackground(
      sb.from("ep_suggestions").insert({
        household_id: app.household.id,
        iso_week: isoWeek,
        recipe_id: recipe.id,
        origin: recipe.cookbook_id ? "regal" : "sammlung",
        generated_by: "regel",
        status: "angenommen",
        reason_shown: stats.get(recipe.id) ? `${stats.get(recipe.id)!.days_since} Tage nicht gekocht` : "noch nie gekocht",
      }),
      "Vorschläge",
    );
    const book = recipe.cookbook_id ? cookbooksById.get(recipe.cookbook_id) : null;
    toast({
      text: book ? `${recipe.title} – aus deinem Regal: ${book.title}${recipe.cookbook_page ? `, S. ${recipe.cookbook_page}` : ""}` : `Vorschlag: ${recipe.title}`,
      action: { label: "Anderer", run: () => void suggest(slot, [...avoid, recipe.id]) },
    });
  }

  async function markCooked(entry: MealPlanEntry, cooked: boolean) {
    const { error } = await upsertSlot(entry.date, entry.meal, { status: cooked ? "gekocht" : "geplant" });
    if (error) return toast({ text: error.message, tone: "error" });
    if (cooked) {
      const servings = servingsFor(entry, plan, members, attendance);
      await sb.from("ep_cooking_history").update({ servings }).eq("meal_plan_id", entry.id);
    }
    await reloadHistory();
    if (cooked) toast({ text: "Als gekocht markiert", action: { label: "Rückgängig", run: () => void markCooked(entry, false) } });
  }

  const plannedCount = plan.filter((p) => MEALS.includes(p.meal) && (p.recipe_id || p.leftover_of)).length;
  const slotLabel = (s: Slot) => `${WEEKDAY_LONG[weekdayIndex(s.date)]} ${MEAL_LABEL[s.meal]}`;

  return (
    <>
      <PageHeader
        title="Woche"
        icon="🗓️"
        width="wide"
        subtitle={`${weekNumberLabel(isoWeek)} · ${formatDateDE(dates[0], { day: "numeric", month: "long" })} – ${formatDateDE(dates[6], { day: "numeric", month: "long" })} · ${plannedCount}/${dates.length * MEALS.length} geplant`}
        trailing={
          <>
            <IconButton label="Vorige Woche" onClick={() => go(shiftWeek(isoWeek, -1))}><IconChevronLeft /></IconButton>
            <IconButton label="Nächste Woche" onClick={() => go(shiftWeek(isoWeek, 1))}><IconChevronRight /></IconButton>
            <AccountButton />
          </>
        }
      >
        <div className="mt-3 flex flex-col gap-4 lg:flex-row lg:items-center lg:gap-3">
        <div className="flex items-center gap-2">
          <button className="chip pressable" onClick={() => go(shiftWeek(isoWeek, -1))} title="Vorige Woche (←)">
            <IconChevronLeft size={16} /> Vorige
          </button>
          {isoWeek !== isoWeekString(today) && (
            <button className="chip pressable" data-on="true" onClick={() => go(isoWeekString(today))}>Diese Woche</button>
          )}
          <button className="chip pressable" onClick={() => go(shiftWeek(isoWeek, 1))} title="Nächste Woche (→)">
            Nächste <IconChevronRight size={16} />
          </button>
        </div>
        <AiPromptBar
          className="lg:ml-auto lg:w-full lg:max-w-xl"
          placeholder="Frag die KI zur Woche …"
          suggestions={["Füll die offenen Abende dieser Woche", "Was steht diese Woche an?", "Wer kocht wann?", "Was haben wir lange nicht gegessen?"]}
        />
        </div>
      </PageHeader>

      {desktop ? (
        // Computer: die sieben Tage nebeneinander; Mittag und Abend liegen über alle Tage auf einer Linie (Subgrid)
        <div className="page-wide mt-6 overflow-x-auto pb-2">
          <motion.div key={isoWeek} {...enter} className="grid grid-cols-[repeat(7,minmax(8.25rem,1fr))] gap-1.5" style={{ gridTemplateRows: "auto auto auto" }}>
            {!week.loaded
              ? dates.map((d) => <div key={d} className="skeleton row-span-3 h-[30rem]" />)
              : dates.map((date) => dayColumn(date))}
          </motion.div>
        </div>
      ) : (
        <motion.div key={isoWeek} {...enter} className="page mt-4 flex flex-col gap-3">
          {!week.loaded
            ? dates.map((d) => <div key={d} className="skeleton h-72" style={{ borderRadius: 14 }} />)
            : dates.map((date) => dayCard(date))}
        </motion.div>
      )}

      <RecipePicker
        open={pickerFor !== null}
        onClose={() => setPickerFor(null)}
        title={pickerFor ? `${slotLabel(pickerFor)} planen` : undefined}
        onPick={(r) => {
          const s = pickerFor!;
          setPickerFor(null);
          void planRecipe(s, r);
        }}
      />

      <SlotSheet
        slot={sheetFor}
        onClose={() => setSheetFor(null)}
        week={week}
        onChangeRecipe={(s) => {
          setSheetFor(null);
          setPickerFor(s);
        }}
        onSuggest={(s) => void suggest(s)}
        onCooked={(e, c) => void markCooked(e, c)}
      />
    </>
  );

  // Als Funktionen statt Komponenten, damit die Karten bei jedem Render nicht neu gemountet werden
  function dayCard(date: string) {
    const idx = weekdayIndex(date);
    const isToday = date === today;
    const isPast = date < today;
    return (
      <article
        key={date}
        className="card overflow-hidden"
        style={{ opacity: isPast && !isToday ? 0.86 : 1, boxShadow: isToday ? "0 0 0 2px var(--accent)" : undefined }}
        aria-label={`${WEEKDAY_LONG[idx]}, ${formatDateDE(date)}`}
      >
        <header className="flex items-center gap-2 px-4 pt-3">
          <h2 className="t-headline">
            {WEEKDAY_SHORT[idx]} <span style={{ color: "var(--label-2)", fontWeight: 500 }}>{formatDateDE(date, { day: "numeric", month: "numeric" })}</span>
          </h2>
          {isToday && <span className="badge" style={{ background: "var(--accent)", color: "var(--on-accent)" }}>Heute</span>}
        </header>
        {MEALS.map((meal, i) => slotBlock(date, meal, i > 0))}
      </article>
    );
  }

  function slotInfo(date: string, meal: Meal) {
    const slot: Slot = { date, meal };
    const entry = plan.find((p) => p.date === date && p.meal === meal) ?? null;
    const count = eaters(members, attendance, date, meal);
    const recipe = entry?.recipe_id ? recipesById.get(entry.recipe_id) : null;
    const source = entry?.leftover_of ? plan.find((p) => p.id === entry.leftover_of) : null;
    const sourceRecipe = source?.recipe_id ? recipesById.get(source.recipe_id) : null;
    const book = recipe?.cookbook_id ? cookbooksById.get(recipe.cookbook_id) : null;
    const cook = entry?.cook_id ? members.find((m) => m.id === entry.cook_id) : null;
    const cook2 = entry?.cook2_id ? members.find((m) => m.id === entry.cook2_id) : null;
    const cookMissing =
      (cook && effectiveStatus(cook, date, meal, attendance).status === "weg") ||
      (cook2 && effectiveStatus(cook2, date, meal, attendance).status === "weg");
    const hasMeal = !!recipe || !!source;
    const cancelled = entry?.status === "ausgefallen";
    const nobody = count === 0;
    const baseDetail = cancelled
      ? "ausgefallen"
      : source
        ? `von ${WEEKDAY_LONG[weekdayIndex(source.date)]} ${MEAL_LABEL[source.meal]}`
        : book
          ? `aus deinem Regal · ${book.title}${recipe?.cookbook_page ? `, S. ${recipe.cookbook_page}` : ""}`
          : recipe?.time_text ?? (recipe?.servings ? `Rezept für ${recipe.servings}` : "");
    // Zutaten schon gekauft (Einkauf erledigt) – sieht man auch im Plan
    const detail = entry?.shopped_at && entry.status === "geplant" && !cancelled ? `eingekauft ✓${baseDetail ? ` · ${baseDetail}` : ""}` : baseDetail;
    return { slot, entry, count, recipe, source, sourceRecipe, cook, cook2, cookMissing, hasMeal, cancelled, nobody, detail };
  }

  function slotBlock(date: string, meal: Meal, divider: boolean) {
    const { slot, entry, count, recipe, sourceRecipe, cook, cook2, cookMissing, hasMeal, cancelled, nobody, detail } = slotInfo(date, meal);

    return (
      <section
        key={meal}
        aria-label={`${WEEKDAY_LONG[weekdayIndex(date)]} ${MEAL_LABEL[meal]}`}
        className="pt-2.5"
        style={divider ? { boxShadow: "inset 0 0.5px 0 var(--separator)", marginTop: 4 } : undefined}
      >
        <div className="flex items-center px-4">
          <h3 className="t-section">{MEAL_LABEL[meal]}</h3>
          <span className="t-footnote ml-auto flex items-center gap-1 tabular-nums" style={{ color: "var(--label-2)" }} aria-label={`${count} Esser`}>
            <IconPeople size={15} /> {count}
          </span>
        </div>

        {/* Anwesenheit: ein Tipp pro Person */}
        <div className="scroll-x flex gap-1.5 px-4 pt-2 pb-1">
          {members.map((m) => {
            const s = effectiveStatus(m, date, meal, attendance);
            const here = s.status === "da";
            return (
              <button
                key={m.id}
                className="pressable flex shrink-0 items-center gap-1.5 rounded-full py-1 pr-2.5 pl-1"
                style={{ background: here ? "var(--fill)" : "transparent", boxShadow: here ? undefined : "inset 0 0 0 1px var(--separator)" }}
                aria-pressed={here}
                aria-label={`${m.name}: ${here ? "da" : "weg"}${s.guests ? ` mit ${s.guests} Gästen` : ""} – tippen zum Ändern`}
                onClick={() => void setStatus(m.id, date, meal, here ? "weg" : "da")}
              >
                <Avatar member={m} size={24} dim={!here} />
                <span className="t-footnote font-medium" style={{ color: here ? "var(--label)" : "var(--label-3)", textDecoration: here ? undefined : "line-through" }}>
                  {m.name}
                </span>
                {s.guests > 0 && <span className="t-caption font-semibold" style={{ color: "var(--accent)" }}>+{s.guests}</span>}
              </button>
            );
          })}
        </div>

        {/* Gericht */}
        <div className="px-2 pb-2">
          {hasMeal ? (
            <button className="row pressable rounded-xl" onClick={() => setSheetFor(slot)}>
              {recipe ? (
                <RecipeImage recipe={recipe} className="h-12 w-12 shrink-0 text-sm" rounded={10} />
              ) : (
                <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-[10px]" style={{ background: "var(--fill)", color: "var(--label-2)" }}>
                  <IconLeftovers />
                </span>
              )}
              <span className="min-w-0 flex-1">
                <span className="t-headline flex items-center gap-1.5" style={{ textDecoration: cancelled ? "line-through" : undefined }}>
                  <span className="truncate">{recipe ? recipe.title : `Reste: ${sourceRecipe?.title ?? "–"}`}</span>
                  {recipe && <DietIcon diet={recipe.diet} size={15} />}
                </span>
                <span className="t-footnote block truncate" style={{ color: "var(--label-2)" }}>{detail}</span>
              </span>
              <IconChevronRight size={18} style={{ color: "var(--label-3)" }} />
            </button>
          ) : nobody ? (
            <p className="t-footnote px-2 py-2" style={{ color: "var(--label-3)" }}>Niemand da – nichts zu planen.</p>
          ) : (
            <div className="flex gap-2 px-2 py-1">
              <button className="btn btn-tinted pressable flex-1" onClick={() => setPickerFor(slot)}>
                <IconPlus size={18} /> Planen
              </button>
              <button className="btn btn-gray pressable" onClick={() => void suggest(slot)} aria-label="Vorschlag einfügen">
                <IconSparkles size={18} /> Vorschlag
              </button>
            </div>
          )}

          {hasMeal && !cancelled && (
            <div className="flex items-center gap-2 px-2 pt-1 pb-1">
              <button className="chip pressable" onClick={() => setSheetFor(slot)} style={cookMissing ? { background: "var(--red-soft)", color: "var(--red)" } : undefined}>
                {cookMissing ? (
                  <><IconWarning size={16} /> Koch fehlt</>
                ) : cook ? (
                  <><Avatar member={cook} size={20} /> {cook.name}{cook2 ? ` & ${cook2.name}` : ""}</>
                ) : (
                  <><IconChef size={16} /> Koch wählen</>
                )}
              </button>
              {recipe && entry && date <= today && (
                entry.status === "gekocht" ? (
                  <button className="chip pressable ml-auto" style={{ background: "var(--green-soft)", color: "var(--green)" }} onClick={() => void markCooked(entry, false)} aria-label="Gekocht – tippen zum Rückgängigmachen">
                    <IconCheck size={16} /> Gekocht
                  </button>
                ) : (
                  <button className="chip pressable ml-auto" onClick={() => void markCooked(entry, true)}>
                    gekocht ✓
                  </button>
                )
              )}
            </div>
          )}
        </div>
      </section>
    );
  }

  // ---------- Computer: Board wie in Notion – eine graue Spalte pro Tag, Karten darin ----------

  function dayColumn(date: string) {
    const idx = weekdayIndex(date);
    const isToday = date === today;
    const isPast = date < today;
    return (
      <article
        key={date}
        className="board-lane row-span-3 grid min-w-0 grid-cols-[minmax(0,1fr)] grid-rows-subgrid"
        data-today={isToday}
        data-past={isPast && !isToday}
        aria-label={`${WEEKDAY_LONG[idx]}, ${formatDateDE(date)}`}
      >
        <header className="flex items-center gap-2 px-2 pt-2 pb-1">
          <h2 className="t-sub min-w-0 flex-1 truncate font-semibold">{WEEKDAY_LONG[idx]}</h2>
          {isToday && <span className="sr-only">Heute</span>}
          <span className="board-date tabular-nums" data-today={isToday}>{parseISODate(date).getUTCDate()}</span>
        </header>
        {MEALS.map((meal) => slotCell(date, meal))}
      </article>
    );
  }

  function slotCell(date: string, meal: Meal) {
    const { slot, entry, count, recipe, sourceRecipe, cook, cook2, cookMissing, hasMeal, cancelled, nobody, detail } = slotInfo(date, meal);
    const title = recipe ? recipe.title : `Reste: ${sourceRecipe?.title ?? "–"}`;
    const slotName = `${WEEKDAY_LONG[weekdayIndex(date)]} ${MEAL_LABEL[meal]}`;

    return (
      <section key={meal} aria-label={slotName} className="flex min-w-0 flex-col gap-1.5 px-1 pt-2 pb-1.5">
        <div className="flex items-center gap-1 px-1">
          <h3 className="t-footnote font-semibold" style={{ color: "var(--label-2)" }}>{MEAL_LABEL[meal]}</h3>
          <span className="t-caption ml-auto flex items-center gap-1 tabular-nums" style={{ color: "var(--label-3)" }} aria-label={`${count} Esser`} title={`${count} Esser`}>
            <IconPeople size={13} /> {count}
          </span>
        </div>

        {/* Anwesenheit: Avatare, ein Klick pro Person */}
        <div className="flex flex-wrap gap-[3px] px-1">
          {members.map((m) => {
            const s = effectiveStatus(m, date, meal, attendance);
            const here = s.status === "da";
            const label = `${m.name}: ${here ? "da" : "weg"}${s.guests ? ` mit ${s.guests} Gästen` : ""}`;
            return (
              <button
                key={m.id}
                className="pressable relative rounded-full"
                style={{ boxShadow: here ? undefined : "0 0 0 1px var(--separator)" }}
                aria-pressed={here}
                aria-label={`${label} – klicken zum Ändern`}
                title={label}
                onClick={() => void setStatus(m.id, date, meal, here ? "weg" : "da")}
              >
                <Avatar member={m} size={22} dim={!here} />
                {s.guests > 0 && (
                  <span className="absolute -top-1 -right-1.5 rounded-full px-1 text-[10px] leading-[14px] font-semibold" style={{ background: "var(--accent)", color: "var(--on-accent)" }}>
                    +{s.guests}
                  </span>
                )}
              </button>
            );
          })}
        </div>

        {/* Gericht als Karte mit Titelbild und Eigenschaften */}
        {hasMeal ? (
          <div className="board-card" data-cancelled={cancelled}>
            <button className="pressable-soft flex w-full min-w-0 flex-col text-left" onClick={() => setSheetFor(slot)} title={`${title}${detail ? ` – ${detail}` : ""}`}>
              {recipe ? (
                <RecipeImage recipe={recipe} className="aspect-[16/10] w-full text-sm" rounded={0} />
              ) : (
                <span className="flex aspect-[16/10] w-full items-center justify-center" style={{ background: "var(--fill)", color: "var(--label-3)" }}>
                  <IconLeftovers size={26} />
                </span>
              )}
              <span className="block min-w-0 px-2.5 pt-2">
                <span className="line-clamp-2 text-[0.875rem] leading-snug font-semibold break-words hyphens-auto" style={{ textDecoration: cancelled ? "line-through" : undefined }}>
                  {title}
                </span>
                <span className="t-caption mt-1 flex items-center gap-1" style={{ color: "var(--label-2)" }}>
                  {recipe?.diet && <span className={`tag tag-${recipe.diet}`}><DietIcon diet={recipe.diet} size={11} />{DIET_LABEL[recipe.diet]}</span>}
                  <span className="min-w-0 truncate">{cancelled ? "ausgefallen" : recipe ? recipe.time_text ?? "" : detail}</span>
                </span>
              </span>
            </button>
            {!cancelled && (
              <div className="flex flex-wrap items-center gap-1 px-1.5 pt-1.5 pb-1.5">
                <button
                  className="board-prop pressable min-w-0"
                  onClick={() => setSheetFor(slot)}
                  data-warn={!!cookMissing}
                  title={cookMissing ? "Koch fehlt" : cook ? `Kocht: ${cook.name}${cook2 ? ` & ${cook2.name}` : ""}` : "Koch wählen"}
                >
                  {cookMissing ? (
                    <><IconWarning size={13} /> <span className="truncate">Koch fehlt</span></>
                  ) : cook ? (
                    <><Avatar member={cook} size={16} /> <span className="truncate">{cook.name}{cook2 ? ` & ${cook2.name}` : ""}</span></>
                  ) : (
                    <><IconChef size={13} /> <span className="truncate">Koch wählen</span></>
                  )}
                </button>
                {recipe && entry && date <= today && (
                  entry.status === "gekocht" ? (
                    <button className="board-prop pressable ml-auto" data-done="true" onClick={() => void markCooked(entry, false)} aria-label="Gekocht – klicken zum Rückgängigmachen" title="Gekocht – klicken zum Rückgängigmachen">
                      <IconCheck size={13} /> Gekocht
                    </button>
                  ) : (
                    <button className="board-prop pressable ml-auto" onClick={() => void markCooked(entry, true)} title="Als gekocht markieren">
                      <IconCheck size={13} /> gekocht?
                    </button>
                  )
                )}
              </div>
            )}
          </div>
        ) : nobody ? (
          <p className="t-caption px-2 py-1.5" style={{ color: "var(--label-3)" }}>Niemand da</p>
        ) : (
          <div className="flex flex-col gap-0.5">
            <button className="board-add pressable" onClick={() => setPickerFor(slot)}>
              <IconPlus size={15} /> Planen
            </button>
            <div className="flex gap-0.5">
              <button className="board-add pressable flex-1" onClick={() => void suggest(slot)} title="Lange nicht Gekochtes vorschlagen">
                Vorschlag
              </button>
              <button
                className="board-add board-add-ai pressable flex-1"
                onClick={() => ask(`Schlag mir für ${slotName} (${formatDateDE(date)}) ein passendes Gericht vor und plane es ein.`)}
                title="Die KI schlägt etwas vor"
              >
                <IconSparkles size={13} /> KI
              </button>
            </div>
          </div>
        )}
      </section>
    );
  }
}
