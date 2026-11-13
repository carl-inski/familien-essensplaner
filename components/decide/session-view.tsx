"use client";

// Eine Runde von der Lobby bis zum Sieger.

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useApp } from "@/components/app-data";
import { DetailLink } from "@/components/detail-nav";
import { IconCalendar, IconCheck } from "@/components/icons";
import { PageHeader } from "@/components/nav";
import { useToast } from "@/components/toast";
import { Avatar, Empty, RecipeImage, Segmented } from "@/components/ui";
import { GAMES, phaseTitle, type DecidePlayer, type DecideSession, type DecideState } from "@/lib/decide";
import { WEEKDAY_LONG, WEEKDAY_SHORT, addDays, formatDateDE, weekdayIndex } from "@/lib/dates";
import { haptic } from "@/lib/haptics";
import { MEALS, MEAL_LABEL } from "@/lib/meals";
import type { Meal, MealPlanEntry, Member } from "@/lib/types";
import { GameBoard } from "./games";
import { Confetti, RevealShow, revealLine } from "./reveal";
import { useDecide } from "./use-decide";

export function slotLabel(date: string, meal: Meal, today: string): string {
  const day = date === today ? "Heute" : `${WEEKDAY_LONG[weekdayIndex(date)]}, ${formatDateDE(date, { day: "numeric", month: "short" })}`;
  return `${day} · ${MEAL_LABEL[meal]}`;
}

export function SessionView({ id }: { id: string }) {
  const { members, me, recipesById, today } = useApp();
  const toast = useToast();
  const decide = useDecide(id);
  const { session, players, mine } = decide;
  const get = useCallback((rid: string) => recipesById.get(rid), [recipesById]);
  const back = { href: "/entscheiden", label: "Spielen" };

  if (session === undefined)
    return (
      <>
        <PageHeader title="Entscheiden" back={back} />
        <div className="page mt-4" aria-busy="true"><div className="skeleton h-72 w-full" style={{ borderRadius: 14 }} /></div>
      </>
    );
  if (session === null || session.status === "cancelled")
    return (
      <>
        <PageHeader title="Entscheiden" back={back} />
        <Empty title={session ? "Die Runde wurde abgebrochen" : "Diese Runde gibt es nicht mehr"} action={<Link href="/entscheiden" className="btn btn-tinted pressable">Neue Runde</Link>} />
      </>
    );

  const game = GAMES.find((g) => g.id === session.game)!;
  const playing = players.map((p) => ({ player: p, member: members.find((m) => m.id === p.member_id) })).filter((x): x is { player: DecidePlayer; member: Member } => !!x.member);
  const fail = (e: { message: string } | null) => e && toast({ text: e.message, tone: "error" });
  const subtitle = session.date && session.meal ? slotLabel(session.date, session.meal, today) : "Was gibt’s?";

  return (
    <>
      <PageHeader title={`${game.emoji} ${game.title}`} subtitle={subtitle} back={back} />
      <div className="page mt-4 pb-6">
        {session.status === "lobby" && (
          <Lobby
            session={session}
            playing={playing}
            joined={!!mine}
            hostName={members.find((m) => m.id === session.created_by)?.name ?? "Jemand"}
            isHost={session.created_by === me.id}
            othersInFamily={members.filter((m) => m.user_id && m.id !== me.id).length}
            onJoin={async () => fail(await decide.join())}
            onLeave={async () => fail(await decide.removePlayer(me.id))}
            onStart={async () => fail(await decide.start())}
            onCancel={async () => fail(await decide.cancel())}
          />
        )}

        {session.status === "playing" && (() => {
          const state = session.state as DecideState;
          const head = phaseTitle(state, players.length);
          const done = mine ? mine.round_done >= session.round : true;
          return (
            <>
              <div className="mb-4 text-center">
                <h2 className="t-title">{head.title}</h2>
                {!done && <p className="t-sub mt-1" style={{ color: "var(--label-2)" }}>{head.text}</p>}
              </div>
              {!done ? (
                <GameBoard key={session.round} state={state} get={get} onSubmit={async (payload) => fail(await decide.submit(payload))} />
              ) : (
                <Waiting
                  playing={playing}
                  round={session.round}
                  spectator={!mine}
                  meId={me.id}
                  onSkip={async (memberId) => fail(await decide.removePlayer(memberId))}
                />
              )}
              <button className="btn-plain t-footnote pressable mx-auto mt-8 block" style={{ color: "var(--label-2)" }} onClick={async () => confirm("Runde für alle abbrechen?") && fail(await decide.cancel())}>
                Runde abbrechen
              </button>
            </>
          );
        })()}

        {session.status === "done" && <Result session={session} players={players.length} />}
      </div>
    </>
  );
}

function Lobby({ session, playing, joined, hostName, isHost, othersInFamily, onJoin, onLeave, onStart, onCancel }: {
  session: DecideSession;
  playing: { player: DecidePlayer; member: Member }[];
  joined: boolean;
  hostName: string;
  isHost: boolean;
  othersInFamily: number;
  onJoin: () => void;
  onLeave: () => void;
  onStart: () => void;
  onCancel: () => void;
}) {
  const game = GAMES.find((g) => g.id === session.game)!;
  const solo = playing.length <= 1;
  return (
    <div className="flex flex-col items-center gap-5 text-center">
      <div>
        <p className="text-6xl" aria-hidden>{game.emoji}</p>
        <p className="t-sub mx-auto mt-2 max-w-xs" style={{ color: "var(--label-2)" }}>{game.text}</p>
      </div>

      <div className="card w-full px-4 py-4">
        <p className="t-section mb-3">Mit dabei</p>
        <ul className="flex flex-wrap justify-center gap-4">
          {playing.map(({ member }) => (
            <li key={member.id} className="flex w-16 flex-col items-center gap-1">
              <Avatar member={member} size={48} />
              <span className="t-caption w-full truncate font-medium">{member.name}</span>
            </li>
          ))}
          {!playing.length && <li className="t-sub" style={{ color: "var(--label-2)" }}>Noch niemand</li>}
        </ul>
        {othersInFamily > 0 && (
          <p className="t-footnote mt-4" style={{ color: "var(--label-2)" }}>
            Die anderen öffnen die App am eigenen Handy – oben erscheint „Mitspielen“.
          </p>
        )}
      </div>

      {joined ? (
        <>
          <button className="btn btn-primary pressable w-full" onClick={onStart}>
            {solo ? "Allein losspielen" : `Los geht’s zu ${playing.length === 2 ? "zweit" : playing.length === 3 ? "dritt" : `${playing.length}.`}`}
          </button>
          {!isHost && <p className="t-footnote" style={{ color: "var(--label-2)" }}>{hostName} hat die Runde eröffnet. Starten darf, wer zuerst drückt.</p>}
          <button className="btn-plain t-footnote pressable" style={{ color: "var(--label-2)" }} onClick={isHost ? onCancel : onLeave}>
            {isHost ? "Runde abbrechen" : "Doch nicht mitspielen"}
          </button>
        </>
      ) : (
        <button className="btn btn-primary pressable w-full" onClick={onJoin}>Mitspielen</button>
      )}
    </div>
  );
}

function Waiting({ playing, round, spectator, meId, onSkip }: { playing: { player: DecidePlayer; member: Member }[]; round: number; spectator: boolean; meId: string; onSkip: (memberId: string) => void }) {
  const open = playing.filter((p) => p.player.round_done < round);
  return (
    <div className="flex flex-col items-center gap-4 text-center" role="status">
      <p className="t-sub" style={{ color: "var(--label-2)" }}>
        {spectator ? "Die Runde läuft – du schaust zu." : open.length ? "Abgegeben! Warten auf die anderen …" : "Alle fertig – es geht weiter …"}
      </p>
      <ul className="flex flex-wrap justify-center gap-5">
        {playing.map(({ player, member }) => {
          const done = player.round_done >= round;
          return (
            <li key={member.id} className="flex w-16 flex-col items-center gap-1">
              <span className="relative">
                <Avatar member={member} size={52} dim={!done} />
                {done && (
                  <span className="absolute -right-1 -bottom-1 flex h-6 w-6 items-center justify-center rounded-full text-white" style={{ background: "var(--green)", boxShadow: "0 0 0 2px var(--bg)" }}>
                    <IconCheck size={14} strokeWidth={3} />
                  </span>
                )}
              </span>
              <span className="t-caption w-full truncate font-medium">{member.name}</span>
              <span className="t-caption" style={{ color: "var(--label-2)" }}>{done ? "fertig" : "überlegt …"}</span>
            </li>
          );
        })}
      </ul>
      {!spectator && open.filter((p) => p.member.id !== meId).length > 0 && (
        <details className="mt-2">
          <summary className="t-footnote pressable cursor-pointer" style={{ color: "var(--label-2)" }}>Jemand ist weg?</summary>
          <div className="mt-2 flex flex-wrap justify-center gap-2">
            {open.filter((p) => p.member.id !== meId).map(({ member }) => (
              <button key={member.id} className="chip pressable" onClick={() => confirm(`Ohne ${member.name} weiterspielen?`) && onSkip(member.id)}>Ohne {member.name} weiter</button>
            ))}
          </div>
        </details>
      )}
    </div>
  );
}

function Result({ session, players }: { session: DecideSession; players: number }) {
  const { recipesById, today } = useApp();
  const [shown, setShown] = useState(false);
  const finish = useCallback(() => setShown(true), []);
  const get = useCallback((rid: string) => recipesById.get(rid), [recipesById]);
  const state = session.state as DecideState;
  const reveal = state.phase === "fertig" ? state.reveal : null;
  const winner = session.winner_recipe_id ? recipesById.get(session.winner_recipe_id) : undefined;

  if (!shown && reveal && session.winner_recipe_id) return <RevealShow reveal={reveal} winner={session.winner_recipe_id} get={get} onDone={finish} />;

  return (
    <div className="mx-auto flex max-w-sm flex-col items-center gap-4 text-center">
      <Confetti />
      <p className="t-section">Es gibt</p>
      {winner ? (
        <DetailLink kind="r" id={winner.id} className="card pressable w-full overflow-hidden text-left">
          <RecipeImage recipe={winner} className="aspect-[4/3] w-full text-6xl" rounded={0} />
          <span className="block p-4">
            <span className="t-title block leading-tight">{winner.title}</span>
            {reveal && <span className="t-sub mt-1 block" style={{ color: "var(--label-2)" }}>{revealLine(reveal, players)}</span>}
          </span>
        </DetailLink>
      ) : (
        <p className="t-headline">Das Rezept gibt es nicht mehr.</p>
      )}
      {session.date && session.meal ? (
        <>
          <p className="t-sub flex items-center gap-1.5 rounded-full px-3 py-1.5" style={{ background: "var(--green-soft)", color: "var(--green)" }}>
            <IconCalendar size={16} /> Steht im Wochenplan: {slotLabel(session.date, session.meal, today)}
          </p>
          <Link href={session.date >= today ? `/woche?ab=${session.date}` : "/woche"} className="btn btn-primary pressable w-full">Zum Wochenplan</Link>
        </>
      ) : (
        winner && <ScheduleWinner session={session} />
      )}
      <Link href="/entscheiden" className="btn btn-gray pressable w-full">Nicht überzeugt? Nochmal spielen</Link>
    </div>
  );
}

/** Erst nach der Entscheidung: Wann gibt es das? Vorgewählt ist der Wunsch aus dem Wochenplan, sonst der nächste freie Abend. */
function ScheduleWinner({ session }: { session: DecideSession }) {
  const { sb, today, recipesById } = useApp();
  const toast = useToast();
  const [plan, setPlan] = useState<MealPlanEntry[] | null>(null);
  const [picked, setPicked] = useState<{ date: string; meal: Meal } | null>(null);
  const [busy, setBusy] = useState(false);
  const days = Array.from({ length: 8 }, (_, i) => addDays(today, i));

  useEffect(() => {
    let alive = true;
    sb.from("ep_meal_plan").select("*").gte("date", today).lte("date", addDays(today, 7))
      .then(({ data }) => alive && setPlan((data ?? []) as MealPlanEntry[]));
    return () => {
      alive = false;
    };
  }, [sb, today]);

  const taken = (date: string, meal: Meal) => plan?.find((p) => p.date === date && p.meal === meal && (p.recipe_id || p.leftover_of));
  const suggested = session.suggested_date && session.suggested_date >= today ? { date: session.suggested_date, meal: session.suggested_meal ?? ("abend" as Meal) } : null;
  const firstFree = { date: days.find((d) => !taken(d, "abend")) ?? today, meal: "abend" as Meal };
  const slot = picked ?? suggested ?? firstFree;
  const there = taken(slot.date, slot.meal);
  const thereTitle = there ? (there.recipe_id ? recipesById.get(there.recipe_id)?.title ?? "ein Gericht" : "Reste") : null;

  async function save() {
    setBusy(true);
    const { error } = await sb.rpc("ep_decide_schedule", { p_session: session.id, p_date: slot.date, p_meal: slot.meal });
    setBusy(false);
    if (error) return toast({ text: error.message, tone: "error" });
    haptic("success");
  }

  return (
    <div className="card w-full px-4 py-4 text-left">
      <p className="t-headline">Wann gibt’s das?</p>
      <div className="scroll-x -mx-4 mt-3 flex gap-2 px-4" role="radiogroup" aria-label="Tag">
        {days.map((d) => (
          <button key={d} role="radio" aria-checked={slot.date === d} className="chip pressable shrink-0" data-on={slot.date === d} onClick={() => setPicked({ date: d, meal: slot.meal })}>
            {d === today ? "Heute" : d === addDays(today, 1) ? "Morgen" : `${WEEKDAY_SHORT[weekdayIndex(d)]} ${formatDateDE(d, { day: "numeric", month: "numeric" })}`}
          </button>
        ))}
      </div>
      <div className="mt-2">
        <Segmented<Meal> label="Mahlzeit" value={slot.meal} onChange={(meal) => setPicked({ date: slot.date, meal })} options={MEALS.map((m) => ({ value: m, label: MEAL_LABEL[m] }))} />
      </div>
      <p className="t-footnote mt-2" style={{ color: "var(--label-2)" }}>{thereTitle ? `Dort steht schon ${thereTitle}, das wird ersetzt.` : "Dort ist noch nichts geplant."}</p>
      <button className="btn btn-primary pressable mt-3 w-full" disabled={busy || plan === null} onClick={save}>
        {busy ? "Plant ein …" : "In den Wochenplan"}
      </button>
    </div>
  );
}
