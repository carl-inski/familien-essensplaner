"use client";

// Entscheiden: Was gibt es? Vier kleine Spiele, allein oder mit der ganzen Familie,
// jede Person am eigenen Handy. Der Sieger landet direkt im Wochenplan.
//   /entscheiden                        → Runde eröffnen oder einer laufenden beitreten
//   /entscheiden?datum=…&mahlzeit=…     → dasselbe, Mahlzeit vorgewählt (aus dem Wochenplan)
//   /entscheiden?s=<id>                 → die Runde selbst

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useMemo, useState } from "react";
import { useApp } from "@/components/app-data";
import { SessionView, slotLabel } from "@/components/decide/session-view";
import { useOpenSessions } from "@/components/decide/use-open-sessions";
import { PageHeader } from "@/components/nav";
import { folderLabel } from "@/components/organize";
import { useToast } from "@/components/toast";
import { Section, Segmented } from "@/components/ui";
import { GAMES, candidateCount, pickCandidates, type Game } from "@/lib/decide";
import { WEEKDAY_SHORT, addDays, daysFrom, formatDateDE, weekdayIndex } from "@/lib/dates";
import { haptic } from "@/lib/haptics";
import { MEALS, MEAL_LABEL } from "@/lib/meals";
import type { PlannedDish } from "@/lib/suggest";
import type { Meal, MealPlanEntry } from "@/lib/types";

export default function DecidePage() {
  return (
    <Suspense>
      <Decide />
    </Suspense>
  );
}

function Decide() {
  const params = useSearchParams();
  const s = params.get("s");
  if (s) return <SessionView key={s} id={s} />;
  return <Start />;
}

function Start() {
  const params = useSearchParams();
  const router = useRouter();
  const toast = useToast();
  const { sb, me, household, members, recipes, recipesById, folders, stats, today } = useApp();
  const open = useOpenSessions();
  const days = useMemo(() => daysFrom(today, 7), [today]);
  const [plan, setPlan] = useState<MealPlanEntry[] | null>(null);

  const wantDate = params.get("datum");
  const wantMeal = params.get("mahlzeit");
  // Vorgabe aus dem Wochenplan – oder der Nutzer wählt; sonst die nächste freie Mahlzeit
  const [picked, setPicked] = useState<{ date: string; meal: Meal } | null>(
    wantDate && /^\d{4}-\d{2}-\d{2}$/.test(wantDate) && wantDate >= today ? { date: wantDate, meal: wantMeal === "mittag" ? "mittag" : "abend" } : null,
  );
  const [game, setGame] = useState<Game>("swipe");
  const [folderId, setFolderId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    sb.from("ep_meal_plan")
      .select("*")
      .gte("date", addDays(today, -3))
      .lte("date", addDays(today, 10))
      .then(({ data }) => !cancelled && setPlan((data ?? []) as MealPlanEntry[]));
    return () => {
      cancelled = true;
    };
  }, [sb, today]);

  const taken = (date: string, meal: Meal) => plan?.find((p) => p.date === date && p.meal === meal && (p.recipe_id || p.leftover_of)) ?? null;
  const firstFree: { date: string; meal: Meal } = { date: days.find((d) => !taken(d, "abend")) ?? today, meal: "abend" };
  const slot = picked ?? firstFree;
  const current = taken(slot.date, slot.meal);
  const currentTitle = current?.recipe_id ? recipesById.get(current.recipe_id)?.title : current ? "Reste" : null;
  const dateOptions = picked && !days.includes(picked.date) ? [...days, picked.date] : days;
  const pool = folderId ? recipes.filter((r) => r.folder_id === folderId) : recipes;

  async function start() {
    setBusy(true);
    const seed = Math.floor(Math.random() * 2147483647);
    const planned: PlannedDish[] = (plan ?? [])
      .filter((p) => p.recipe_id && p.status !== "ausgefallen" && !(p.date === slot.date && p.meal === slot.meal))
      .map((p) => ({ date: p.date, recipe_id: p.recipe_id, diet: recipesById.get(p.recipe_id!)?.diet ?? null }));
    const candidates = pickCandidates(recipes, stats, planned, slot.date, today, seed, { count: candidateCount(game), folderId });
    if (candidates.length < 2) {
      setBusy(false);
      return toast({ text: folderId ? "In diesem Ordner sind zu wenige Rezepte zum Spielen." : "Zum Spielen braucht es mindestens zwei Rezepte in der Sammlung.", tone: "warning" });
    }
    const { data, error } = await sb
      .from("ep_decide_sessions")
      .insert({ household_id: household.id, created_by: me.id, date: slot.date, meal: slot.meal, game, seed, candidates })
      .select("id")
      .single();
    if (error || !data) {
      setBusy(false);
      return toast({ text: error?.message ?? "Die Runde konnte nicht eröffnet werden.", tone: "error" });
    }
    const id = (data as { id: string }).id;
    await sb.from("ep_decide_players").insert({ session_id: id, member_id: me.id });
    haptic("success");
    router.push(`/entscheiden?s=${id}`);
  }

  return (
    <>
      <PageHeader title="Entscheiden" subtitle="Was gibt’s? Spielt es aus." tabRoot />
      <div className="page">
        {open.length > 0 && (
          <Section title="Läuft gerade">
            <ul className="group">
              {open.map((o) => {
                const g = GAMES.find((x) => x.id === o.game);
                const host = members.find((m) => m.id === o.created_by)?.name ?? "Jemand";
                return (
                  <li key={o.id}>
                    <Link href={`/entscheiden?s=${o.id}`} className="row pressable">
                      <span className="text-2xl" aria-hidden>{g?.emoji}</span>
                      <span className="min-w-0 flex-1">
                        <span className="t-sub block font-semibold">{g?.title} · {slotLabel(o.date, o.meal, today)}</span>
                        <span className="t-footnote block" style={{ color: "var(--label-2)" }}>{host} {o.status === "lobby" ? "wartet auf Mitspieler" : "spielt schon"}</span>
                      </span>
                      <span className="btn btn-tinted btn-sm">{o.status === "lobby" ? "Mitspielen" : "Ansehen"}</span>
                    </Link>
                  </li>
                );
              })}
            </ul>
          </Section>
        )}

        <Section title="Für wann?" footer={currentTitle ? `Dort steht schon „${currentTitle}“ – der Sieger ersetzt es.` : "Der Sieger wird direkt in den Wochenplan eingetragen."}>
          <div className="scroll-x -mx-4 flex gap-2 px-4" role="radiogroup" aria-label="Tag">
            {dateOptions.map((d) => (
              <button key={d} role="radio" aria-checked={slot.date === d} className="chip pressable shrink-0" data-on={slot.date === d} onClick={() => setPicked({ date: d, meal: slot.meal })}>
                {d === today ? "Heute" : d === addDays(today, 1) ? "Morgen" : `${WEEKDAY_SHORT[weekdayIndex(d)]} ${formatDateDE(d, { day: "numeric", month: "numeric" })}`}
              </button>
            ))}
          </div>
          <div className="mt-2">
            <Segmented<Meal> label="Mahlzeit" value={slot.meal} onChange={(meal) => setPicked({ date: slot.date, meal })} options={MEALS.map((m) => ({ value: m, label: MEAL_LABEL[m] }))} />
          </div>
        </Section>

        <Section title="Welches Spiel?">
          <div className="grid grid-cols-2 gap-2.5" role="radiogroup" aria-label="Spiel">
            {GAMES.map((g) => {
              const on = game === g.id;
              return (
                <button
                  key={g.id}
                  role="radio"
                  aria-checked={on}
                  className="card pressable flex flex-col items-start gap-1 p-3 text-left"
                  style={{ boxShadow: on ? "inset 0 0 0 2px var(--accent)" : undefined, background: on ? "var(--accent-soft)" : undefined }}
                  onClick={() => { haptic("light"); setGame(g.id); }}
                >
                  <span className="text-3xl" aria-hidden>{g.emoji}</span>
                  <span className="t-headline">{g.title}</span>
                  <span className="t-caption leading-snug" style={{ color: "var(--label-2)" }}>{g.text}</span>
                </button>
              );
            })}
          </div>
        </Section>

        {folders.length > 0 && (
          <Section title="Woraus?">
            <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Rezepte">
              <button role="radio" aria-checked={folderId === null} className="chip pressable" data-on={folderId === null} onClick={() => setFolderId(null)}>Alle Rezepte</button>
              {folders.map((f) => (
                <button key={f.id} role="radio" aria-checked={folderId === f.id} className="chip pressable" data-on={folderId === f.id} onClick={() => setFolderId(f.id)}>{folderLabel(f)}</button>
              ))}
            </div>
          </Section>
        )}

        <button className="btn btn-primary pressable mt-8 w-full" disabled={busy || plan === null || pool.length < 2} onClick={start}>
          {busy ? "Mischt die Karten …" : "Runde eröffnen"}
        </button>
        <p className="t-footnote mt-2 text-center" style={{ color: "var(--label-2)" }}>
          {pool.length < 2 ? "Dafür braucht es mindestens zwei Rezepte." : "Allein oder zusammen: Die anderen steigen am eigenen Handy ein."}
        </p>
      </div>
    </>
  );
}
