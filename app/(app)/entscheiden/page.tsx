"use client";

// Entscheiden: Was gibt es? Vier kleine Spiele, allein oder mit der ganzen Familie,
// jede Person am eigenen Handy. Der Sieger landet direkt im Wochenplan.
//   /entscheiden                        → Runde eröffnen; läuft schon eine, steht nur sie da
//   /entscheiden?datum=…&mahlzeit=…     → dasselbe, Mahlzeit für nach dem Spiel vorgewählt (aus dem Wochenplan)
//   /entscheiden?s=<id>                 → die Runde selbst

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { useApp } from "@/components/app-data";
import { SessionView, slotLabel } from "@/components/decide/session-view";
import { useOpenSessions } from "@/components/decide/use-open-sessions";
import { PageHeader } from "@/components/nav";
import { folderLabel } from "@/components/organize";
import { useToast } from "@/components/toast";
import { Avatar, Section } from "@/components/ui";
import { GAMES, candidateCount, pickCandidates, type DecideSession, type Game } from "@/lib/decide";
import { addDays } from "@/lib/dates";
import { haptic } from "@/lib/haptics";
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

const newSeed = () => Math.floor(Math.random() * 2147483647);

function Start() {
  const params = useSearchParams();
  const router = useRouter();
  const toast = useToast();
  const { sb, recipes, recipesById, folders, stats, today } = useApp();
  const open = useOpenSessions();
  const running = open[0] ?? null;
  const [plan, setPlan] = useState<MealPlanEntry[] | null>(null);
  // Kam man aus dem Wochenplan („Ausspielen“), ist diese Mahlzeit nach dem Spiel vorgewählt
  const wantDate = params.get("datum");
  const wantMeal = params.get("mahlzeit");
  const suggested = wantDate && /^\d{4}-\d{2}-\d{2}$/.test(wantDate) && wantDate >= today ? { date: wantDate, meal: (wantMeal === "mittag" ? "mittag" : "abend") as Meal } : null;
  const [game, setGame] = useState<Game>("swipe");
  const [folderId, setFolderId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    sb.from("ep_meal_plan")
      .select("*")
      .gte("date", addDays(today, -3))
      .lte("date", addDays(today, 14))
      .then(({ data }) => !cancelled && setPlan((data ?? []) as MealPlanEntry[]));
    return () => {
      cancelled = true;
    };
  }, [sb, today]);

  const pool = folderId ? recipes.filter((r) => r.folder_id === folderId) : recipes;

  async function start() {
    setBusy(true);
    const seed = newSeed();
    // Der Tag steht noch nicht fest: Regeln (nicht gerade gekocht, schon geplant, Fleisch) für heute anwenden
    const target = suggested?.date ?? today;
    const planned: PlannedDish[] = (plan ?? [])
      .filter((p) => p.recipe_id && p.status !== "ausgefallen" && !(suggested && p.date === suggested.date && p.meal === suggested.meal))
      .map((p) => ({ date: p.date, recipe_id: p.recipe_id, diet: recipesById.get(p.recipe_id!)?.diet ?? null }));
    const candidates = pickCandidates(recipes, stats, planned, target, today, seed, { count: candidateCount(game), folderId });
    if (candidates.length < 2) {
      setBusy(false);
      return toast({ text: folderId ? "In diesem Ordner sind zu wenige Rezepte zum Spielen." : "Zum Spielen braucht es mindestens zwei Rezepte in der Sammlung.", tone: "warning" });
    }
    const { data, error } = await sb.rpc("ep_decide_create", {
      p_game: game,
      p_seed: seed,
      p_candidates: candidates,
      p_suggested_date: suggested?.date ?? null,
      p_suggested_meal: suggested?.meal ?? null,
    });
    const row = ((data ?? []) as { id: string; already_open: boolean }[])[0];
    if (error || !row) {
      setBusy(false);
      return toast({ text: error?.message ?? "Die Runde konnte nicht eröffnet werden.", tone: "error" });
    }
    if (row.already_open) toast({ text: "Es läuft schon eine Runde – du bist jetzt dort." });
    else haptic("success");
    router.push(`/entscheiden?s=${row.id}`);
  }

  return (
    <>
      <PageHeader title="Entscheiden" subtitle="Was gibt’s? Spielt es aus." tabRoot />
      <div className="page">
        {running ? (
          <RunningRound session={running} />
        ) : (
          <>
            {suggested && (
              <p className="t-sub card mt-4 px-4 py-3" style={{ background: "var(--accent-soft)" }}>
                Der Sieger kommt danach auf {slotLabel(suggested.date, suggested.meal, today)}, wenn ihr nichts anderes wählt.
              </p>
            )}

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
              {pool.length < 2 ? "Dafür braucht es mindestens zwei Rezepte." : "Allein oder zusammen: Die anderen steigen am eigenen Handy ein. Wann es das Gericht gibt, wählt ihr danach."}
            </p>
          </>
        )}
      </div>
    </>
  );
}

/** Läuft schon eine Runde, ist sie das Einzige auf der Seite: groß, mit allen, die mitspielen */
function RunningRound({ session }: { session: DecideSession }) {
  const { sb, me, members } = useApp();
  const toast = useToast();
  const [players, setPlayers] = useState<string[]>([]);
  const g = GAMES.find((x) => x.id === session.game);
  const host = members.find((m) => m.id === session.created_by)?.name ?? "Jemand";
  const lobby = session.status === "lobby";

  useEffect(() => {
    let alive = true;
    const load = () =>
      sb.from("ep_decide_players").select("member_id").eq("session_id", session.id)
        .then(({ data }) => alive && setPlayers(((data ?? []) as { member_id: string }[]).map((p) => p.member_id)));
    void load();
    const t = setInterval(load, 4000);
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, [sb, session.id]);

  const mine = players.includes(me.id);
  const people = players.map((id) => members.find((m) => m.id === id)).filter((m): m is NonNullable<typeof m> => !!m);

  return (
    <section className="mt-4 overflow-hidden rounded-[22px]" style={{ background: "var(--accent-soft)" }} aria-label="Laufende Runde">
      <div className="flex flex-col items-center gap-4 px-5 pt-8 pb-6 text-center">
        <span className="text-6xl" aria-hidden>{g?.emoji}</span>
        <div>
          <p className="t-title">{lobby ? `${host} hat eine Runde ${g?.title} eröffnet` : `Hier wird gerade ${g?.title} gespielt`}</p>
          <p className="t-sub mt-1" style={{ color: "var(--label-2)" }}>
            {lobby ? (mine ? "Die anderen können noch einsteigen." : "Steig ein, bevor es losgeht.") : mine ? "Du spielst mit." : "Neue Mitspieler können nicht mehr dazukommen, zuschauen geht."}
          </p>
        </div>
        {people.length > 0 && (
          <ul className="flex flex-wrap justify-center gap-4">
            {people.map((m) => (
              <li key={m.id} className="flex w-14 flex-col items-center gap-1">
                <Avatar member={m} size={44} />
                <span className="t-caption w-full truncate font-medium">{m.name}</span>
              </li>
            ))}
          </ul>
        )}
        <Link href={`/entscheiden?s=${session.id}`} className="btn btn-primary pressable w-full max-w-xs">
          {lobby && !mine ? "Mitspielen" : mine ? "Weiterspielen" : "Zuschauen"}
        </Link>
      </div>
      <div className="px-5 pb-5 text-center">
        <button
          className="btn-plain t-footnote pressable"
          style={{ color: "var(--label-2)" }}
          onClick={async () => {
            if (!confirm("Diese Runde für alle beenden?")) return;
            const { error } = await sb.from("ep_decide_sessions").update({ status: "cancelled" }).eq("id", session.id).in("status", ["lobby", "playing"]);
            if (error) toast({ text: error.message, tone: "error" });
          }}
        >
          Runde hängt? Für alle beenden
        </button>
      </div>
    </section>
  );
}
