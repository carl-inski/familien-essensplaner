"use client";

// Die Spielflächen: jede zeigt die Aufgabe der Runde und ruft am Ende onSubmit mit der
// Abgabe auf. Was eine Abgabe bedeutet, steht in lib/decide.ts.

import { AnimatePresence, animate, motion, useMotionValue, useReducedMotion, useTransform } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { IconCheck, IconClock, IconClose, IconMinus, IconPlus } from "@/components/icons";
import { DIET_LABEL, DietIcon, RecipeImage } from "@/components/ui";
import { JAGD_SECONDS, JAGD_SHOWS, JAGD_VISIBLE_MS, SPOONS, SPOONS_PER_DISH, TICKETS, ZUG_MAX_TPS, ZUG_SECONDS, type DecideState } from "@/lib/decide";
import { haptic } from "@/lib/haptics";
import type { Recipe } from "@/lib/types";

type Lookup = (id: string) => Recipe | undefined;
type Submit = (payload: unknown) => void;

/** Fehlt ein Rezept (inzwischen gelöscht), bleibt die Runde spielbar */
const titleOf = (get: Lookup, id: string) => get(id)?.title ?? "Gelöschtes Rezept";

function Meta({ recipe }: { recipe: Recipe | undefined }) {
  if (!recipe) return null;
  return (
    <span className="t-caption flex flex-wrap items-center gap-x-2" style={{ color: "var(--label-2)" }}>
      {recipe.diet && <span className="flex items-center gap-0.5"><DietIcon diet={recipe.diet} size={12} />{DIET_LABEL[recipe.diet]}</span>}
      {recipe.time_min !== null && <span className="flex items-center gap-0.5"><IconClock size={12} />{recipe.time_min} Min.</span>}
    </span>
  );
}

function Picture({ recipe, className }: { recipe: Recipe | undefined; className: string }) {
  return <RecipeImage recipe={recipe ?? { title: "?", image_url: null, diet: null }} className={className} rounded={0} />;
}

export function GameBoard({ state, get, onSubmit }: { state: DecideState; get: Lookup; onSubmit: Submit }) {
  switch (state.phase) {
    case "deck":
      return <SwipeDeck key={state.deckNo} deck={state.deck} get={get} onSubmit={onSubmit} />;
    case "finale":
      return <Finale options={state.options} get={get} onSubmit={onSubmit} />;
    case "sieb":
      return <Sieve options={state.options} get={get} onSubmit={onSubmit} />;
    case "duell":
      return <Duel key={state.stage} pairs={state.pairs} get={get} onSubmit={onSubmit} />;
    case "lose":
      return <Allocate options={state.options} get={get} total={TICKETS} perDish={TICKETS} unit="🎟️" noun={["Los", "Lose"]} onSubmit={(v) => onSubmit({ tickets: v })} />;
    case "loeffel":
      return <Allocate options={state.options} get={get} total={SPOONS} perDish={SPOONS_PER_DISH} unit="🥄" noun={["Löffel", "Löffel"]} onSubmit={(v) => onSubmit({ spoons: v })} />;
    case "jagd":
      return <PlateHunt options={state.options} get={get} onSubmit={onSubmit} />;
    case "zug":
      return <TugOfWar key={state.stage} pairs={state.pairs} get={get} onSubmit={onSubmit} />;
    case "fertig":
      return null;
  }
}

// ---------------------------------------------------------------------------
// Swipen
// ---------------------------------------------------------------------------

type Vote = 0 | 1 | 2;

function SwipeDeck({ deck, get, onSubmit }: { deck: string[]; get: Lookup; onSubmit: Submit }) {
  const [votes, setVotes] = useState<Record<string, Vote>>({});
  const [last, setLast] = useState<Vote>(1);
  const index = Object.keys(votes).length;
  const current = deck[index];
  const next = deck[index + 1];

  function vote(v: Vote) {
    if (!current) return;
    haptic(v === 2 ? "success" : "light");
    const all = { ...votes, [current]: v };
    setLast(v);
    setVotes(all);
    if (Object.keys(all).length === deck.length) setTimeout(() => onSubmit(all), 260);
  }

  return (
    <div className="mx-auto flex w-full max-w-sm flex-col items-center gap-3">
      {/* Höhe begrenzt: Karte, Zähler und Knöpfe passen über die Tableiste, auch auf kleinen Handys */}
      <div className="relative w-full" style={{ height: "min(26rem, calc(100dvh - 25rem))", minHeight: "14rem" }}>
        {next && (
          <div key={next} className="card absolute inset-0 overflow-hidden" style={{ transform: "scale(0.94) translateY(14px)", opacity: 0.7 }} aria-hidden>
            <Picture recipe={get(next)} className="h-full w-full text-5xl" />
          </div>
        )}
        <AnimatePresence custom={last}>
          {current && <SwipeCard key={current} recipe={get(current)} title={titleOf(get, current)} onVote={vote} />}
        </AnimatePresence>
        {!current && (
          <div className="absolute inset-0 flex items-center justify-center">
            <p className="t-headline" style={{ color: "var(--label-2)" }}>Stapel durch!</p>
          </div>
        )}
      </div>
      <p className="t-footnote tabular-nums" style={{ color: "var(--label-2)" }} aria-live="polite">{Math.min(index + 1, deck.length)} von {deck.length}</p>
      <div className="flex items-center gap-5">
        <RoundButton label="Heute nicht" color="var(--red)" onClick={() => vote(0)} disabled={!current}><IconClose size={30} strokeWidth={2.4} /></RoundButton>
        <RoundButton label="Unbedingt!" color="#b7791f" small onClick={() => vote(2)} disabled={!current}><span className="text-2xl" aria-hidden>★</span></RoundButton>
        <RoundButton label="Lust drauf" color="var(--green)" onClick={() => vote(1)} disabled={!current}><span className="text-3xl leading-none" aria-hidden>♥</span></RoundButton>
      </div>
    </div>
  );
}

function RoundButton({ label, color, small = false, disabled, onClick, children }: { label: string; color: string; small?: boolean; disabled?: boolean; onClick: () => void; children: React.ReactNode }) {
  const size = small ? 54 : 68;
  return (
    <button
      className="card pressable flex items-center justify-center rounded-full"
      style={{ width: size, height: size, color, borderRadius: 999, boxShadow: "0 4px 18px rgba(0,0,0,.12)", opacity: disabled ? 0.4 : 1 }}
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  );
}

const EXIT = {
  exit: (v: Vote) => ({
    x: v === 1 ? 420 : v === 0 ? -420 : 0,
    y: v === 2 ? -640 : 40,
    rotate: v === 1 ? 18 : v === 0 ? -18 : 0,
    opacity: 0,
    transition: { duration: 0.26, ease: "easeIn" as const },
  }),
};

function SwipeCard({ recipe, title, onVote }: { recipe: Recipe | undefined; title: string; onVote: (v: Vote) => void }) {
  const reduce = useReducedMotion();
  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const rotate = useTransform(x, [-220, 220], [-14, 14]);
  const yes = useTransform(x, [24, 120], [0, 1]);
  const no = useTransform(x, [-120, -24], [1, 0]);
  const wow = useTransform(y, [-130, -40], [1, 0]);

  return (
    <motion.div
      className="card absolute inset-0 cursor-grab touch-none overflow-hidden select-none active:cursor-grabbing"
      style={{ x, y, rotate, boxShadow: "0 10px 34px rgba(0,0,0,.16)" }}
      drag
      dragElastic={1}
      dragMomentum={false}
      variants={EXIT}
      exit="exit"
      initial={reduce ? { opacity: 0 } : { scale: 0.94, y: 14, opacity: 0.7 }}
      animate={{ scale: 1, y: 0, opacity: 1 }}
      transition={{ type: "spring", bounce: 0.2, duration: 0.35 }}
      onDragEnd={(_, info) => {
        // Wie weit die Karte mit ihrem Schwung noch fliegen würde, entscheidet
        const dx = info.offset.x + info.velocity.x * 0.18;
        const dy = info.offset.y + info.velocity.y * 0.18;
        if (dy < -150 && Math.abs(dx) < 110) return onVote(2);
        if (dx > 110) return onVote(1);
        if (dx < -110) return onVote(0);
        void animate(x, 0, { type: "spring", bounce: 0.3, duration: 0.4 });
        void animate(y, 0, { type: "spring", bounce: 0.3, duration: 0.4 });
      }}
    >
      <Picture recipe={recipe} className="pointer-events-none h-full w-full text-6xl" />
      <div className="pointer-events-none absolute inset-x-0 bottom-0 p-4 pt-16" style={{ background: "linear-gradient(to top, rgba(0,0,0,.78), transparent)", color: "#fff" }}>
        <h3 className="t-title leading-tight">{title}</h3>
        <p className="t-footnote mt-1 flex flex-wrap gap-x-2 opacity-90">
          {recipe?.diet && <span>{DIET_LABEL[recipe.diet]}</span>}
          {recipe && recipe.time_min !== null && <span>{recipe.time_min} Min.</span>}
          {recipe?.subtitle && <span className="truncate">{recipe.subtitle}</span>}
        </p>
      </div>
      <Stamp opacity={yes} text="LUST!" color="#22a04b" className="top-6 left-5 -rotate-12" />
      <Stamp opacity={no} text="NÖ" color="#e0352b" className="top-6 right-5 rotate-12" />
      <Stamp opacity={wow} text="UNBEDINGT ★" color="#d69a1c" className="bottom-28 left-1/2 -translate-x-1/2" />
    </motion.div>
  );
}

function Stamp({ opacity, text, color, className }: { opacity: ReturnType<typeof useTransform<number, number>>; text: string; color: string; className: string }) {
  return (
    <motion.span
      className={`pointer-events-none absolute rounded-lg border-[3px] px-2.5 py-0.5 text-2xl font-extrabold tracking-wide whitespace-nowrap ${className}`}
      style={{ opacity, color, borderColor: color, background: "rgba(255,255,255,.9)" }}
      aria-hidden
    >
      {text}
    </motion.span>
  );
}

// ---------------------------------------------------------------------------
// Aussieben
// ---------------------------------------------------------------------------

function Sieve({ options, get, onSubmit }: { options: string[]; get: Lookup; onSubmit: Submit }) {
  const [out, setOut] = useState<Set<string>>(new Set());
  const left = options.length - out.size;

  function toggle(id: string) {
    haptic("light");
    setOut((cur) => {
      const next = new Set(cur);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-3 gap-2.5 sm:grid-cols-4">
        {options.map((id) => {
          const gone = out.has(id);
          return (
            <motion.button
              key={id}
              className="card pressable relative flex flex-col overflow-hidden text-left"
              aria-pressed={gone}
              aria-label={`${titleOf(get, id)}${gone ? " – gestrichen" : ""}`}
              animate={{ scale: gone ? 0.92 : 1, rotate: gone ? -3 : 0, opacity: gone ? 0.45 : 1 }}
              transition={{ type: "spring", bounce: 0.35, duration: 0.3 }}
              onClick={() => toggle(id)}
            >
              <Picture recipe={get(id)} className="aspect-square w-full text-2xl" />
              <span className="t-caption line-clamp-2 min-h-[2.4em] p-1.5 leading-tight font-semibold">{titleOf(get, id)}</span>
              {gone && (
                <span className="absolute inset-0 flex items-center justify-center" style={{ color: "var(--red)" }} aria-hidden>
                  <IconClose size={64} strokeWidth={3} />
                </span>
              )}
            </motion.button>
          );
        })}
      </div>
      <button className="btn btn-primary pressable w-full" disabled={left === 0} onClick={() => onSubmit({ out: [...out] })}>
        {left === 0 ? "Lass mindestens eins übrig" : out.size === 0 ? "Alles okay – weiter" : `Fertig · ${left} ${left === 1 ? "bleibt" : "bleiben"}`}
      </button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Duell
// ---------------------------------------------------------------------------

function Duel({ pairs, get, onSubmit }: { pairs: [string, string][]; get: Lookup; onSubmit: Submit }) {
  const reduce = useReducedMotion();
  const [picks, setPicks] = useState<string[]>([]);
  const pair = pairs[picks.length];

  function pick(id: string) {
    haptic("medium");
    const all = [...picks, id];
    setPicks(all);
    if (all.length === pairs.length) setTimeout(() => onSubmit({ picks: all }), 200);
  }

  if (!pair) return <p className="t-headline py-16 text-center" style={{ color: "var(--label-2)" }}>Abgegeben!</p>;

  return (
    <div className="mx-auto flex w-full max-w-md flex-col items-center gap-3">
      {pairs.length > 1 && <p className="t-footnote tabular-nums" style={{ color: "var(--label-2)" }}>Duell {picks.length + 1} von {pairs.length}</p>}
      <AnimatePresence mode="wait">
        <motion.div
          key={pair.join()}
          className="relative grid w-full grid-cols-2 gap-3"
          initial={reduce ? { opacity: 0 } : { opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.96, transition: { duration: 0.12 } }}
          transition={{ type: "spring", bounce: 0.3, duration: 0.4 }}
        >
          {pair.map((id) => (
            <button key={id} className="card pressable flex flex-col overflow-hidden text-left" onClick={() => pick(id)}>
              <Picture recipe={get(id)} className="aspect-[3/4] w-full text-4xl" />
              <span className="flex flex-col gap-0.5 p-2.5">
                <span className="t-sub line-clamp-2 min-h-[2.5em] leading-tight font-semibold">{titleOf(get, id)}</span>
                <Meta recipe={get(id)} />
              </span>
            </button>
          ))}
          <span
            className="pointer-events-none absolute top-[38%] left-1/2 flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full text-sm font-extrabold"
            style={{ background: "var(--accent)", color: "var(--on-accent)", boxShadow: "0 0 0 4px var(--bg)" }}
            aria-hidden
          >
            VS
          </span>
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Lose und Löffel verteilen
// ---------------------------------------------------------------------------

function Allocate({ options, get, total, perDish, unit, noun, onSubmit }: { options: string[]; get: Lookup; total: number; perDish: number; unit: string; noun: [string, string]; onSubmit: (v: Record<string, number>) => void }) {
  const [given, setGiven] = useState<Record<string, number>>({});
  const used = Object.values(given).reduce((a, b) => a + b, 0);
  const left = total - used;

  function change(id: string, d: number) {
    const now = given[id] ?? 0;
    const next = now + d;
    if (next < 0 || next > perDish || (d > 0 && left === 0)) return;
    haptic("light");
    setGiven({ ...given, [id]: next });
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="text-center text-2xl tracking-widest" aria-label={`${left} ${noun[left === 1 ? 0 : 1]} übrig`}>
        {Array.from({ length: total }).map((_, i) => (
          <span key={i} style={{ opacity: i < left ? 1 : 0.18, filter: i < left ? undefined : "grayscale(1)" }} aria-hidden>{unit}</span>
        ))}
      </p>
      <ul className="group">
        {options.map((id) => {
          const n = given[id] ?? 0;
          return (
            <li key={id} className="row !py-2">
              <button className="pressable flex min-w-0 flex-1 items-center gap-3 text-left" onClick={() => change(id, 1)} aria-label={`${titleOf(get, id)}: ${noun[0]} dazu`}>
                <RecipeImage recipe={get(id) ?? { title: "?", image_url: null, diet: null }} className="h-12 w-12 shrink-0 text-sm" rounded={10} />
                <span className="min-w-0 flex-1">
                  <span className="t-sub line-clamp-2 leading-tight font-medium">{titleOf(get, id)}</span>
                  <span className="block h-5 text-sm tracking-wider" aria-hidden>{unit.repeat(n)}</span>
                </span>
              </button>
              <span className="inline-flex shrink-0 items-center rounded-full" style={{ background: "var(--fill)" }}>
                <button className="pressable flex h-10 w-10 items-center justify-center" aria-label={`${titleOf(get, id)}: ${noun[0]} weg`} disabled={n === 0} style={{ opacity: n === 0 ? 0.3 : 1 }} onClick={() => change(id, -1)}><IconMinus size={18} /></button>
                <span className="t-headline w-5 text-center tabular-nums">{n}</span>
                <button className="pressable flex h-10 w-10 items-center justify-center" aria-label={`${titleOf(get, id)}: ${noun[0]} dazu`} disabled={left === 0 || n >= perDish} style={{ opacity: left === 0 || n >= perDish ? 0.3 : 1 }} onClick={() => change(id, 1)}><IconPlus size={18} /></button>
              </span>
            </li>
          );
        })}
      </ul>
      <button className="btn btn-primary pressable w-full" disabled={left > 0} onClick={() => onSubmit(given)}>
        {left > 0 ? `Noch ${left} ${noun[left === 1 ? 0 : 1]} verteilen` : "Abgeben"}
      </button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Finale beim Swipen: eins streichen
// ---------------------------------------------------------------------------

function Finale({ options, get, onSubmit }: { options: string[]; get: Lookup; onSubmit: Submit }) {
  const [strike, setStrike] = useState<string | null>(null);
  return (
    <div className="flex flex-col gap-3">
      <ul className="group">
        {options.map((id) => {
          const gone = strike === id;
          return (
            <li key={id}>
              <button className="row pressable w-full text-left" aria-pressed={gone} onClick={() => { haptic("light"); setStrike(gone ? null : id); }}>
                <RecipeImage recipe={get(id) ?? { title: "?", image_url: null, diet: null }} className="h-14 w-14 shrink-0 text-sm" rounded={10} />
                <span className="min-w-0 flex-1" style={{ opacity: gone ? 0.4 : 1 }}>
                  <span className="t-sub line-clamp-2 leading-tight font-semibold" style={{ textDecoration: gone ? "line-through" : undefined }}>{titleOf(get, id)}</span>
                  <Meta recipe={get(id)} />
                </span>
                <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full" style={{ background: gone ? "var(--red)" : "var(--fill)", color: gone ? "#fff" : "var(--label-3)" }} aria-hidden>
                  <IconClose size={18} strokeWidth={2.4} />
                </span>
              </button>
            </li>
          );
        })}
      </ul>
      <button className="btn btn-primary pressable w-full" onClick={() => onSubmit({ strike })}>
        {strike ? <>Gestrichen – weiter</> : <><IconCheck size={18} /> Mir ist alles recht</>}
      </button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Countdown vor den Reaktionsspielen
// ---------------------------------------------------------------------------

/** 3 – 2 – 1 – Los, dann onGo. Groß in der Mitte, damit alle gleichzeitig starten. */
function Countdown({ onGo }: { onGo: () => void }) {
  const [n, setN] = useState(3);
  const reduce = useReducedMotion();
  const go = useRef(onGo);
  useEffect(() => {
    go.current = onGo;
  }, [onGo]);
  useEffect(() => {
    if (n === 0) {
      const t = setTimeout(() => go.current(), 450);
      return () => clearTimeout(t);
    }
    const t = setTimeout(() => {
      haptic(n === 1 ? "medium" : "light");
      setN(n - 1);
    }, 650);
    return () => clearTimeout(t);
  }, [n]);
  return (
    <div className="flex h-56 items-center justify-center" role="status" aria-live="assertive">
      <AnimatePresence mode="popLayout">
        <motion.span
          key={n}
          className="text-7xl font-extrabold tabular-nums"
          style={{ color: "var(--accent)" }}
          initial={reduce ? { opacity: 0 } : { opacity: 0, scale: 0.4 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={reduce ? { opacity: 0 } : { opacity: 0, scale: 1.6 }}
          transition={{ type: "spring", bounce: 0.4, duration: 0.4 }}
        >
          {n === 0 ? "Los!" : n}
        </motion.span>
      </AnimatePresence>
    </div>
  );
}

function TimeBar({ total, left }: { total: number; left: number }) {
  return (
    <div className="h-2 w-full overflow-hidden rounded-full" style={{ background: "var(--fill)" }} role="timer" aria-label={`Noch ${Math.ceil(left)} Sekunden`}>
      <div className="h-full rounded-full transition-[width] duration-100 ease-linear" style={{ width: `${Math.max(0, (left / total) * 100)}%`, background: left < total * 0.25 ? "var(--red)" : "var(--accent)" }} />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tellerjagd: Teller fliegen vorbei, schnapp dir, worauf du Lust hast
// ---------------------------------------------------------------------------

interface Spawn {
  key: number;
  id: string;
  at: number;
  x: number;
  y: number;
  drift: number;
}

function makeSpawns(options: string[]): Spawn[] {
  const order = options.flatMap((id) => Array.from({ length: JAGD_SHOWS }, () => id));
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  const step = (JAGD_SECONDS * 1000 - JAGD_VISIBLE_MS) / order.length;
  return order.map((id, i) => ({ key: i, id, at: i * step + Math.random() * step * 0.4, x: 4 + Math.random() * 62, y: 4 + Math.random() * 62, drift: (Math.random() - 0.5) * 60 }));
}

function PlateHunt({ options, get, onSubmit }: { options: string[]; get: Lookup; onSubmit: Submit }) {
  const reduce = useReducedMotion();
  const [phase, setPhase] = useState<"ready" | "count" | "play" | "done">("ready");
  const [elapsed, setElapsed] = useState(0);
  const [caught, setCaught] = useState<Record<string, number>>({});
  const [gone, setGone] = useState<Set<number>>(new Set());
  const [pops, setPops] = useState<{ key: number; x: number; y: number }[]>([]);
  const startedAt = useRef(0);
  const sent = useRef(false);

  // Jedes Gericht fliegt gleich oft vorbei, in zufälliger Reihenfolge und an zufälligen Stellen
  const [spawns] = useState(() => makeSpawns(options));

  useEffect(() => {
    if (phase !== "play") return;
    startedAt.current = performance.now();
    const t = setInterval(() => {
      const ms = performance.now() - startedAt.current;
      setElapsed(ms);
      if (ms >= JAGD_SECONDS * 1000) setPhase("done");
    }, 80);
    return () => clearInterval(t);
  }, [phase]);

  useEffect(() => {
    if (phase !== "done" || sent.current) return;
    sent.current = true;
    haptic("success");
    const t = setTimeout(() => onSubmit({ caught }), 900);
    return () => clearTimeout(t);
  }, [phase, caught, onSubmit]);

  const total = Object.values(caught).reduce((a, b) => a + b, 0);
  const visible = phase === "play" ? spawns.filter((s) => !gone.has(s.key) && elapsed >= s.at && elapsed < s.at + JAGD_VISIBLE_MS) : [];

  // Schon geschnappt? Zweiter Tipp auf denselben Teller zählt nicht
  const grabbed = useRef(new Set<number>());
  function grab(s: Spawn) {
    if (phase !== "play" || grabbed.current.has(s.key)) return;
    grabbed.current.add(s.key);
    haptic("light");
    setGone((g) => new Set(g).add(s.key));
    setCaught((c) => ({ ...c, [s.id]: Math.min(JAGD_SHOWS, (c[s.id] ?? 0) + 1) }));
    setPops((p) => [...p.slice(-6), { key: s.key, x: s.x, y: s.y }]);
  }

  if (phase === "ready")
    return (
      <div className="mx-auto flex max-w-sm flex-col items-center gap-4 text-center">
        <p className="t-sub" style={{ color: "var(--label-2)" }}>Diese Teller fliegen gleich vorbei. Tipp an, was du heute essen willst, so oft du es erwischst.</p>
        <ul className="flex flex-wrap justify-center gap-2">
          {options.map((id) => <li key={id} className="chip">{titleOf(get, id)}</li>)}
        </ul>
        <button className="btn btn-primary pressable mt-2 w-full" onClick={() => setPhase("count")}>Bereit</button>
      </div>
    );
  if (phase === "count") return <Countdown onGo={() => setPhase("play")} />;

  return (
    <div className="mx-auto flex w-full max-w-md flex-col gap-3">
      <TimeBar total={JAGD_SECONDS} left={phase === "done" ? 0 : JAGD_SECONDS - elapsed / 1000} />
      <div
        className="relative w-full touch-manipulation overflow-hidden rounded-[22px] select-none"
        style={{ height: "min(26rem, calc(100dvh - 20rem))", minHeight: "16rem", background: "var(--fill)" }}
        aria-label="Spielfeld"
      >
        <AnimatePresence>
          {visible.map((s) => {
            const recipe = get(s.id);
            return (
              <motion.button
                key={s.key}
                className="absolute flex w-[34%] flex-col items-center gap-1"
                style={{ left: `${s.x}%`, top: `${s.y}%` }}
                initial={reduce ? { opacity: 0 } : { opacity: 0, scale: 0.3, rotate: -20 }}
                animate={reduce ? { opacity: 1 } : { opacity: 1, scale: 1, rotate: 0, x: s.drift }}
                exit={reduce ? { opacity: 0 } : { opacity: 0, scale: 0.5 }}
                transition={reduce ? { duration: 0.15 } : { opacity: { duration: 0.15 }, scale: { type: "spring", bounce: 0.5, duration: 0.4 }, rotate: { type: "spring", bounce: 0.5, duration: 0.4 }, x: { duration: JAGD_VISIBLE_MS / 1000, ease: "linear" } }}
                onPointerDown={() => grab(s)}
                aria-label={`${titleOf(get, s.id)} schnappen`}
              >
                <span className="aspect-square w-full overflow-hidden rounded-full" style={{ boxShadow: "0 0 0 5px var(--surface), 0 8px 22px rgba(0,0,0,.18)" }}>
                  <RecipeImage recipe={recipe ?? { title: "?", image_url: null, diet: null }} className="h-full w-full text-2xl" rounded={999} />
                </span>
                <span className="t-caption line-clamp-2 rounded-full px-2 py-0.5 text-center leading-tight font-semibold" style={{ background: "var(--surface)" }}>{titleOf(get, s.id)}</span>
              </motion.button>
            );
          })}
        </AnimatePresence>
        <AnimatePresence>
          {pops.map((p) => (
            <motion.span
              key={`pop-${p.key}`}
              className="pointer-events-none absolute text-2xl font-extrabold"
              style={{ left: `${p.x + 12}%`, top: `${p.y + 8}%`, color: "var(--accent)" }}
              initial={{ opacity: 1, y: 0 }}
              animate={{ opacity: 0, y: reduce ? 0 : -40 }}
              transition={{ duration: 0.7 }}
              onAnimationComplete={() => setPops((cur) => cur.filter((x) => x.key !== p.key))}
              aria-hidden
            >
              +1
            </motion.span>
          ))}
        </AnimatePresence>
        {phase === "done" && (
          <div className="absolute inset-0 flex items-center justify-center" role="status">
            <span className="t-title">Abpfiff!</span>
          </div>
        )}
      </div>
      <p className="t-sub text-center tabular-nums" aria-live="polite">{total} Teller geschnappt</p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tauziehen: zwei Gerichte, fünf Sekunden, so schnell tippen wie möglich
// ---------------------------------------------------------------------------

function TugOfWar({ pairs, get, onSubmit }: { pairs: [string, string][]; get: Lookup; onSubmit: Submit }) {
  const reduce = useReducedMotion();
  const [index, setIndex] = useState(0);
  const [phase, setPhase] = useState<"count" | "pull" | "pause">("count");
  const [left, setLeft] = useState(0);
  const [right, setRight] = useState(0);
  const [results, setResults] = useState<[number, number][]>([]);
  const [remaining, setRemaining] = useState(ZUG_SECONDS);
  const cap = ZUG_SECONDS * ZUG_MAX_TPS;
  const pair = pairs[index];

  useEffect(() => {
    if (phase !== "pull") return;
    const start = performance.now();
    const t = setInterval(() => {
      const r = ZUG_SECONDS - (performance.now() - start) / 1000;
      setRemaining(Math.max(0, r));
      if (r <= 0) setPhase("pause");
    }, 80);
    return () => clearInterval(t);
  }, [phase]);

  useEffect(() => {
    if (phase !== "pause") return;
    haptic("success");
    const all = [...results, [left, right] as [number, number]];
    const t = setTimeout(() => {
      if (all.length === pairs.length) return onSubmit({ taps: all });
      setResults(all);
      setLeft(0);
      setRight(0);
      setRemaining(ZUG_SECONDS);
      setIndex(index + 1);
      setPhase("count");
    }, 1100);
    return () => clearTimeout(t);
    // nur beim Wechsel in die Pause
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase]);

  if (!pair) return <p className="t-headline py-16 text-center" style={{ color: "var(--label-2)" }}>Abgegeben!</p>;

  // Seil: -1 ganz links, +1 ganz rechts
  const balance = left + right === 0 ? 0 : (right - left) / Math.max(10, left + right);
  const pull = (side: "l" | "r") => {
    if (phase !== "pull") return;
    if (side === "l") setLeft((n) => Math.min(cap, n + 1));
    else setRight((n) => Math.min(cap, n + 1));
    haptic("light");
  };

  return (
    <div className="mx-auto flex w-full max-w-md flex-col gap-3">
      {pairs.length > 1 && <p className="t-footnote text-center tabular-nums" style={{ color: "var(--label-2)" }}>Duell {index + 1} von {pairs.length}</p>}
      {phase === "count" ? (
        <>
          <div className="grid grid-cols-2 gap-3 text-center">
            {pair.map((id) => <p key={id} className="t-headline line-clamp-2">{titleOf(get, id)}</p>)}
          </div>
          <Countdown onGo={() => setPhase("pull")} />
        </>
      ) : (
        <>
          <TimeBar total={ZUG_SECONDS} left={phase === "pause" ? 0 : remaining} />
          {/* Seil mit Knoten: wandert zur Seite, auf die du mehr tippst */}
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
              const n = side === 0 ? left : right;
              return (
                // Kein Motion-Tap hier: der fängt schnelle Folgetipps ab. Rückmeldung per CSS (:active)
                <button
                  key={id}
                  className="card flex touch-manipulation flex-col overflow-hidden text-left transition-transform duration-75 select-none active:scale-[0.96]"
                  style={{ opacity: phase === "pause" ? 0.6 : 1 }}
                  onPointerDown={(e) => {
                    e.preventDefault();
                    pull(side === 0 ? "l" : "r");
                  }}
                  aria-label={`Für ${titleOf(get, id)} ziehen`}
                  disabled={phase !== "pull"}
                >
                  <Picture recipe={get(id)} className="aspect-[4/3] w-full text-3xl" />
                  <span className="flex flex-col gap-0.5 p-2.5">
                    <span className="t-sub line-clamp-2 min-h-[2.5em] leading-tight font-semibold">{titleOf(get, id)}</span>
                    <span className="text-2xl font-extrabold tabular-nums" style={{ color: "var(--accent)" }}>{n}</span>
                  </span>
                </button>
              );
            })}
          </div>
          <p className="t-sub text-center" style={{ color: "var(--label-2)" }} aria-live="polite">
            {phase === "pause" ? "Gesichert. Gleich geht es weiter." : "Tippen, tippen, tippen!"}
          </p>
        </>
      )}
    </div>
  );
}
