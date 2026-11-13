"use client";

// Tauziehen live: Alle Handys laufen im selben Takt (Serverzeit, lib/decide.ts zugTimeline)
// und schicken sich ihre Taps über Supabase Realtime (Broadcast, ohne Datenbank).
// Das Seil zeigt die Summe der ganzen Familie. Gewertet wird wie bisher mit den
// Abgaben jeder Person am Ende (advance in lib/decide.ts) – die Live-Anzeige ist nur Anzeige.

import { motion, useReducedMotion } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { useApp } from "@/components/app-data";
import { RecipeImage } from "@/components/ui";
import { ZUG_MAX_TPS, ZUG_SECONDS, zugTimeline } from "@/lib/decide";
import { haptic } from "@/lib/haptics";
import type { Recipe } from "@/lib/types";

type Lookup = (id: string) => Recipe | undefined;
type Pull = { d: number; l: number; r: number };

const CAP = ZUG_SECONDS * ZUG_MAX_TPS;
const SEND_EVERY_MS = 150;

/** Abstand der eigenen Uhr zur Serveruhr (ms). Drei Messungen, die schnellste zählt. */
function useServerOffset(): number | null {
  const { sb } = useApp();
  const [offset, setOffset] = useState<number | null>(null);
  useEffect(() => {
    let alive = true;
    (async () => {
      let best: { rtt: number; offset: number } | null = null;
      for (let i = 0; i < 3; i++) {
        const t0 = Date.now();
        const { data, error } = await sb.rpc("ep_server_now");
        const t1 = Date.now();
        if (error || typeof data !== "number") continue;
        const sample = { rtt: t1 - t0, offset: data - (t0 + t1) / 2 };
        if (!best || sample.rtt < best.rtt) best = sample;
      }
      // Ohne Messung: eigene Uhr – besser als gar nicht spielen
      if (alive) setOffset(best?.offset ?? 0);
    })();
    return () => {
      alive = false;
    };
  }, [sb]);
  return offset;
}

const titleOf = (get: Lookup, id: string) => get(id)?.title ?? "Gelöschtes Rezept";

export function LiveTug({ pairs, get, onSubmit, sessionId, startedAt }: { pairs: [string, string][]; get: Lookup; onSubmit: (payload: unknown) => void; sessionId: string; startedAt: string }) {
  const { sb, me } = useApp();
  const reduce = useReducedMotion();
  const offset = useServerOffset();
  const [now, setNow] = useState(() => Date.now());
  // Eigene Taps je Duell [links, rechts]: State für die Anzeige, Ref für Senden und Abgabe
  const [own, setOwn] = useState<[number, number][]>(() => pairs.map(() => [0, 0]));
  const mine = useRef(own);
  // Letzter Stand der anderen: je Person Duell und Taps
  const [others, setOthers] = useState<Record<string, Pull>>({});
  const channel = useRef<ReturnType<typeof sb.channel> | null>(null);
  const dirty = useRef(false);
  const sent = useRef(false);

  const start = Date.parse(startedAt);
  const step = offset === null ? null : zugTimeline(now + offset - start, pairs.length);
  const duel = step && !step.done ? step.duel : pairs.length - 1;

  // Takt: 20 Mal pro Sekunde nachsehen, wo der gemeinsame Ablauf steht
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 50);
    return () => clearInterval(t);
  }, []);

  // Live-Kanal der Runde
  useEffect(() => {
    const ch = sb
      .channel(`ep-zug-${sessionId}`, { config: { broadcast: { self: false } } })
      .on("broadcast", { event: "taps" }, ({ payload }) => {
        const p = payload as { m?: string; d?: number; l?: number; r?: number };
        if (!p.m || typeof p.d !== "number") return;
        setOthers((cur) => ({ ...cur, [p.m!]: { d: p.d!, l: Math.min(CAP, p.l ?? 0), r: Math.min(CAP, p.r ?? 0) } }));
      })
      .subscribe();
    channel.current = ch;
    return () => {
      channel.current = null;
      void sb.removeChannel(ch);
    };
  }, [sb, sessionId]);

  // Eigene Taps gebündelt senden. Ein Takt für die ganze Runde: hinge er an `step`, würde er
  // bei jedem Bildaufbau (20× pro Sekunde) neu starten und nie feuern.
  const current = useRef(duel);
  useEffect(() => {
    current.current = duel;
  }, [duel]);
  useEffect(() => {
    const t = setInterval(() => {
      if (!dirty.current || !channel.current || sent.current) return;
      dirty.current = false;
      const d = current.current;
      const [l, r] = mine.current[d] ?? [0, 0];
      void channel.current.send({ type: "broadcast", event: "taps", payload: { m: me.id, d, l, r } });
    }, SEND_EVERY_MS);
    return () => clearInterval(t);
  }, [me.id]);

  // Ablauf vorbei: eigene Taps abgeben – auch wer zu spät kam, hält niemanden auf
  useEffect(() => {
    if (!step?.done || sent.current) return;
    sent.current = true;
    haptic("success");
    onSubmit({ taps: mine.current });
  }, [step?.done, onSubmit]);

  if (!step) return <p className="t-sub py-16 text-center" style={{ color: "var(--label-2)" }} role="status">Uhren werden abgeglichen …</p>;
  if (step.done) return <p className="t-headline py-16 text-center" style={{ color: "var(--label-2)" }}>Abgegeben!</p>;

  const pair = pairs[duel];
  const [ownL, ownR] = own[duel] ?? [0, 0];
  const team = Object.values(others).filter((o) => o.d === duel);
  const left = ownL + team.reduce((s, o) => s + o.l, 0);
  const right = ownR + team.reduce((s, o) => s + o.r, 0);
  // Seil: -1 ganz links, +1 ganz rechts
  const balance = left + right === 0 ? 0 : (right - left) / Math.max(10, left + right);
  const pulling = step.phase === "pull";

  function pull(side: 0 | 1) {
    if (!pulling) return;
    const row = mine.current[duel];
    if (!row || row[side] >= CAP) return;
    const next = mine.current.map((r, i) => (i === duel ? ((side === 0 ? [r[0] + 1, r[1]] : [r[0], r[1] + 1]) as [number, number]) : r));
    mine.current = next;
    dirty.current = true;
    setOwn(next);
    haptic("light");
  }

  const count = Math.ceil(step.msLeft / 1000);

  return (
    <div className="mx-auto flex w-full max-w-md flex-col gap-3">
      {pairs.length > 1 && <p className="t-footnote text-center tabular-nums" style={{ color: "var(--label-2)" }}>Duell {duel + 1} von {pairs.length}</p>}

      <div className="flex h-16 items-center justify-center" aria-live="assertive">
        {step.phase === "wait" && <span className="t-headline" style={{ color: "var(--label-2)" }}>Gleich geht’s los …</span>}
        {step.phase === "count" && <span className="text-6xl font-extrabold tabular-nums" style={{ color: "var(--accent)" }}>{count}</span>}
        {step.phase === "pull" && <span className="text-4xl font-extrabold tabular-nums" style={{ color: count <= 1 ? "var(--red)" : "var(--accent)" }}>{count} s</span>}
        {step.phase === "pause" && (
          <span className="t-headline">{left === right ? "Unentschieden!" : `Vorne: ${titleOf(get, left > right ? pair[0] : pair[1])}`}</span>
        )}
      </div>

      {/* Seil mit Knoten: wandert zur Seite, an der die Familie stärker zieht */}
      <div className="relative h-8" aria-hidden>
        <div className="absolute top-1/2 right-0 left-0 h-1.5 -translate-y-1/2 rounded-full" style={{ background: "repeating-linear-gradient(90deg, #b88a55 0 10px, #9c7142 10px 14px)" }} />
        <div className="absolute top-0 left-1/2 h-8 w-0.5 -translate-x-1/2" style={{ background: "var(--label-3)" }} />
        <motion.div
          className="absolute top-1/2 h-6 w-6 -translate-x-1/2 -translate-y-1/2 rounded-full"
          style={{ background: "var(--accent)", boxShadow: "0 0 0 3px var(--surface)" }}
          animate={{ left: `${50 + balance * 42}%` }}
          transition={reduce ? { duration: 0 } : { type: "spring", stiffness: 400, damping: 30 }}
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        {pair.map((id, side) => {
          const total = side === 0 ? left : right;
          const own = side === 0 ? ownL : ownR;
          return (
            // Kein Motion-Tap: der fängt schnelle Folgetipps ab. Rückmeldung per CSS (:active)
            <button
              key={id}
              className="card flex touch-manipulation flex-col overflow-hidden text-left transition-transform duration-75 select-none active:scale-[0.96]"
              style={{ opacity: pulling ? 1 : 0.7 }}
              onPointerDown={(e) => {
                e.preventDefault();
                pull(side as 0 | 1);
              }}
              aria-label={`Für ${titleOf(get, id)} ziehen`}
              disabled={!pulling}
            >
              <RecipeImage recipe={get(id) ?? { title: "?", image_url: null, diet: null }} className="aspect-[4/3] w-full text-3xl" rounded={0} />
              <span className="flex flex-col gap-0.5 p-2.5">
                <span className="t-sub line-clamp-2 min-h-[2.5em] leading-tight font-semibold">{titleOf(get, id)}</span>
                <span className="text-2xl font-extrabold tabular-nums" style={{ color: "var(--accent)" }}>{total}</span>
                <span className="t-caption tabular-nums" style={{ color: "var(--label-2)" }}>davon du: {own}</span>
              </span>
            </button>
          );
        })}
      </div>
      <p className="t-sub text-center" style={{ color: "var(--label-2)" }}>
        {pulling ? "Tippen, tippen, tippen!" : step.phase === "pause" ? "Nächstes Duell kommt gleich." : "Alle starten gleichzeitig."}
      </p>
    </div>
  );
}
