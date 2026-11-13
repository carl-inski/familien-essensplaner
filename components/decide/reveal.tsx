"use client";

// Auflösung: je nach Spiel dreht sich erst das Rad oder wachsen die Löffel-Balken,
// dann erscheint der Sieger. Der Ausgang steht schon fest (session.state.reveal) –
// die Animation zeigt ihn auf jedem Handy gleich.

import { motion, useReducedMotion } from "motion/react";
import { useEffect, useMemo, useState } from "react";
import type { Reveal } from "@/lib/decide";
import type { Recipe } from "@/lib/types";

type Lookup = (id: string) => Recipe | undefined;

const WHEEL_COLORS = ["#e4572e", "#f3a712", "#4c9f70", "#2b78d4", "#9b5de5", "#e56b9a", "#17a2a2", "#8d6e4b"];

/** Zeigt die Spannungs-Animation und ruft danach onDone */
export function RevealShow({ reveal, winner, get, onDone }: { reveal: Reveal; winner: string; get: Lookup; onDone: () => void }) {
  const reduce = useReducedMotion();
  const instant = reduce || (reveal.kind !== "rad" && reveal.kind !== "loeffel" && reveal.kind !== "jagd");

  useEffect(() => {
    if (!instant) return;
    const t = setTimeout(onDone, reduce ? 0 : 900);
    return () => clearTimeout(t);
  }, [instant, reduce, onDone]);

  if (reveal.kind === "rad" && !reduce) return <Wheel options={reveal.options} weights={reveal.weights} winner={winner} get={get} onDone={onDone} />;
  if ((reveal.kind === "loeffel" || reveal.kind === "jagd") && !reduce)
    return <Bars options={reveal.options} totals={reveal.totals} mins={reveal.mins} unit={reveal.kind === "jagd" ? "🍽️" : "🥄"} winner={winner} get={get} onDone={onDone} />;
  if (reduce) return null;
  return (
    <div className="flex flex-col items-center gap-3 py-16" role="status">
      <motion.span className="text-6xl" animate={{ rotate: [0, -14, 14, -10, 10, 0], scale: [1, 1.15, 1] }} transition={{ duration: 0.9 }} aria-hidden>🥁</motion.span>
      <p className="t-headline">Und es gibt …</p>
    </div>
  );
}

function Wheel({ options, weights, winner, get, onDone }: { options: string[]; weights: number[]; winner: string; get: Lookup; onDone: () => void }) {
  const total = weights.reduce((a, b) => a + b, 0);
  const segments = useMemo(() => {
    const before = (i: number) => weights.slice(0, i).reduce((a, b) => a + b, 0);
    return options.map((id, i) => ({
      id,
      from: (before(i) / total) * 360,
      to: (before(i + 1) / total) * 360,
      color: WHEEL_COLORS[i % WHEEL_COLORS.length],
    }));
  }, [options, weights, total]);
  const win = segments.find((s) => s.id === winner) ?? segments[0];
  // Der Zeiger steht oben (0°): das Rad dreht so, dass die Mitte des Siegerfelds dort landet
  const target = 360 * 6 - (win.from + win.to) / 2;

  return (
    <div className="flex flex-col items-center gap-4" role="status" aria-label="Das Glücksrad dreht sich">
      <div className="relative w-full max-w-xs">
        <span className="absolute -top-1 left-1/2 z-10 -translate-x-1/2 text-3xl leading-none" style={{ color: "var(--label)" }} aria-hidden>▼</span>
        <motion.div initial={{ rotate: 0 }} animate={{ rotate: target }} transition={{ duration: 5, ease: [0.12, 0.7, 0.1, 1] }} onAnimationComplete={() => setTimeout(onDone, 700)}>
          <svg viewBox="-104 -104 208 208" className="w-full drop-shadow-lg" aria-hidden>
            {segments.map((s, i) => (
              <g key={s.id}>
                <path d={slice(s.from, s.to)} fill={s.color} stroke="#fff" strokeWidth={1.5} />
                <text {...labelAt((s.from + s.to) / 2)} fill="#fff" fontSize={15} fontWeight={800} textAnchor="middle" dominantBaseline="central">{i + 1}</text>
              </g>
            ))}
            <circle r={13} fill="#fff" />
            <circle r={6} fill="var(--accent)" />
          </svg>
        </motion.div>
      </div>
      <ol className="grid w-full max-w-sm grid-cols-1 gap-1">
        {segments.map((s, i) => (
          <li key={s.id} className="t-footnote flex items-center gap-2">
            <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[11px] font-bold text-white" style={{ background: s.color }}>{i + 1}</span>
            <span className="min-w-0 flex-1 truncate">{get(s.id)?.title ?? "?"}</span>
            <span className="tabular-nums" style={{ color: "var(--label-2)" }}>{Math.round((weights[i] / total) * 100)} %</span>
          </li>
        ))}
      </ol>
    </div>
  );
}

const point = (deg: number, r: number) => {
  const rad = ((deg - 90) * Math.PI) / 180;
  return [Math.cos(rad) * r, Math.sin(rad) * r] as const;
};

function slice(from: number, to: number): string {
  if (to - from >= 359.99) return "M 0 -100 A 100 100 0 1 1 -0.01 -100 Z";
  const [x1, y1] = point(from, 100);
  const [x2, y2] = point(to, 100);
  return `M 0 0 L ${x1.toFixed(2)} ${y1.toFixed(2)} A 100 100 0 ${to - from > 180 ? 1 : 0} 1 ${x2.toFixed(2)} ${y2.toFixed(2)} Z`;
}

function labelAt(deg: number) {
  const [x, y] = point(deg, 68);
  return { x: x.toFixed(2), y: y.toFixed(2) };
}

function Bars({ options, totals, mins, unit, winner, get, onDone }: { options: string[]; totals: number[]; mins: number[]; unit: string; winner: string; get: Lookup; onDone: () => void }) {
  const max = Math.max(1, ...totals);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const a = setTimeout(() => setShown(true), 1900);
    const b = setTimeout(onDone, 3200);
    return () => {
      clearTimeout(a);
      clearTimeout(b);
    };
  }, [onDone]);

  return (
    <div className="flex flex-col gap-2.5" role="status" aria-label="Die Stimmen werden gezählt">
      {options.map((id, i) => {
        const won = shown && id === winner;
        return (
          <div key={id}>
            <div className="t-footnote mb-1 flex justify-between gap-2">
              <span className="truncate font-medium" style={{ color: won ? "var(--accent)" : undefined }}>{won ? "🏆 " : ""}{get(id)?.title ?? "?"}</span>
              <span className="shrink-0 tabular-nums" style={{ color: "var(--label-2)" }}>{totals[i]} {unit}{mins[i] === 0 ? " · nicht von allen" : ""}</span>
            </div>
            <div className="h-3 overflow-hidden rounded-full" style={{ background: "var(--fill)" }}>
              <motion.div
                className="h-full rounded-full"
                style={{ background: won ? "var(--accent)" : mins[i] === 0 ? "var(--label-3)" : "var(--green)" }}
                initial={{ width: 0 }}
                animate={{ width: `${(totals[i] / max) * 100}%` }}
                transition={{ duration: 1.5, delay: 0.15 + i * 0.08, ease: "easeOut" }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}

const CONFETTI = ["🎉", "🍝", "🥕", "🍅", "✨", "🧀", "🌶️", "🥦", "🍋", "🎊"];

/** Konfetti aus Essen – einmal beim Sieger, nicht bei „Bewegung reduzieren“ */
export function Confetti() {
  const reduce = useReducedMotion();
  // Feste Bahnen (kein Zufall beim Rendern): 18 Stück, verteilt über die Breite
  const bits = useMemo(
    () => Array.from({ length: 18 }, (_, i) => ({ left: 4 + ((i * 53) % 92), delay: (i % 6) * 0.07, turn: i % 2 ? 220 : -220, emoji: CONFETTI[i % CONFETTI.length], drift: ((i * 37) % 60) - 30 })),
    [],
  );
  if (reduce) return null;
  return (
    <div className="pointer-events-none fixed inset-0 z-50 overflow-hidden" aria-hidden>
      {bits.map((b, i) => (
        <motion.span
          key={i}
          className="absolute -top-10 text-3xl"
          style={{ left: `${b.left}%` }}
          initial={{ y: 0, x: 0, rotate: 0, opacity: 1 }}
          animate={{ y: "110vh", x: b.drift, rotate: b.turn, opacity: [1, 1, 0.9, 0] }}
          transition={{ duration: 2.4, delay: b.delay, ease: "easeIn" }}
        >
          {b.emoji}
        </motion.span>
      ))}
    </div>
  );
}

export function revealLine(reveal: Reveal, players: number): string {
  switch (reveal.kind) {
    case "match":
      return players > 1 ? "Match! Darauf haben alle Lust." : "Darauf hast du Lust.";
    case "finale":
      return players > 1 ? "Niemand hat es gestrichen – das passt für alle." : "Das bleibt übrig.";
    case "einzig":
      return players > 1 ? "Das Einzige, das niemand gestrichen hat." : "Das Einzige, das du nicht gestrichen hast.";
    case "duell":
      return "Turniersieger!";
    case "rad":
      return "Das Rad hat entschieden.";
    case "loeffel":
      return players > 1 ? "Die meisten Löffel, und von allen welche." : "Dein Favorit.";
    case "jagd":
      return players > 1 ? "Alle haben danach geschnappt." : "Am häufigsten geschnappt.";
    case "zug":
      return players > 1 ? `Gewonnen mit ${reveal.taps} Taps aus der ganzen Familie.` : `Gewonnen mit ${reveal.taps} Taps.`;
  }
}
