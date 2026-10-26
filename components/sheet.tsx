"use client";

// Bottom Sheet mit direkter Manipulation:
// - folgt dem Finger 1:1 – am Griff/Kopf jederzeit, im Inhalt, sobald er ganz oben steht
//   und man weiter nach unten zieht (wie bei iOS); respektiert den Greifpunkt
// - Gummiband-Widerstand nach oben
// - beim Loslassen: Momentum-Projektion entscheidet zwischen Schließen und Zurückfedern,
//   die Feder übernimmt die Fingergeschwindigkeit
// - jederzeit unterbrechbar (Feder startet vom aktuellen Wert)
// - Reduce Motion: Überblenden statt Gleiten, Wischen zum Schließen geht trotzdem
// - Computer: zentrierter Dialog, der aus Unschärfe und leichter Verkleinerung auftaucht – ohne Wischgeste;
//   er wächst aus der Richtung des Klicks, der ihn geöffnet hat, und schrumpft dorthin zurück

import { AnimatePresence, animate, motion, useMotionValue, useReducedMotion, useTransform } from "motion/react";
import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { haptic } from "@/lib/haptics";
import { useIsDesktop } from "./use-media";

const SPRING_SHEET = { type: "spring" as const, bounce: 0.15, duration: 0.35 };
const SPRING_SETTLE = { type: "spring" as const, bounce: 0, duration: 0.3 };
const SPRING_DIALOG = { type: "spring" as const, bounce: 0, duration: 0.3 };
const DIALOG_HIDDEN = { opacity: 0, scale: 0.94, filter: "blur(8px)" };
const DIALOG_SHOWN = { opacity: 1, scale: 1, filter: "blur(0px)" };

// Letzter Klick: Ursprung für den Dialog, damit er räumlich an seinem Auslöser hängt
let lastPointer: { x: number; y: number; t: number } | null = null;
if (typeof window !== "undefined") {
  window.addEventListener("pointerdown", (e) => (lastPointer = { x: e.clientX, y: e.clientY, t: e.timeStamp }), { capture: true, passive: true });
}

/** Apples Projektionsfunktion aus "Designing Fluid Interfaces" */
function project(velocity: number, decelerationRate = 0.998) {
  return ((velocity / 1000) * decelerationRate) / (1 - decelerationRate);
}

function rubberband(overshoot: number, dimension: number, constant = 0.55) {
  return (overshoot * dimension * constant) / (dimension + constant * Math.abs(overshoot));
}

interface SheetProps {
  open: boolean;
  onClose: () => void;
  title?: string;
  children: ReactNode;
  /** Aktion rechts im Kopf, z. B. "Fertig" */
  action?: ReactNode;
  /** maximale Höhe in dvh */
  maxHeight?: number;
}

export function Sheet(props: SheetProps) {
  if (typeof document === "undefined") return null;
  return createPortal(
    <AnimatePresence>{props.open ? <SheetBody key="sheet" {...props} /> : null}</AnimatePresence>,
    document.body,
  );
}

function SheetBody({ onClose, title, children, action, maxHeight = 92 }: SheetProps) {
  const reduce = useReducedMotion();
  const dialog = useIsDesktop();
  // Wischen ist direkte Bedienung, keine Animation – daher auch bei „Bewegung reduzieren“
  const draggable = !dialog;
  // Pixel statt "100%": die Wischgeste rechnet mit dem aktuellen Zahlenwert weiter
  const [offscreen] = useState(() => (typeof window === "undefined" ? 900 : window.innerHeight));
  const y = useMotionValue(0);
  const sheetRef = useRef<HTMLDivElement>(null);
  const headRef = useRef<HTMLDivElement>(null);
  const bodyRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const scrimOpacity = useTransform(y, (v) => {
    const h = sheetRef.current?.offsetHeight ?? 600;
    return Math.max(0, 1 - Math.max(0, v) / h);
  });
  const closeRef = useRef(onClose);
  useEffect(() => {
    closeRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const opener = document.activeElement as HTMLElement | null;
    sheetRef.current?.focus();
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
      // Fokus zurück dorthin, wo er vorher war (Tastatur und VoiceOver)
      if (opener?.isConnected) opener.focus({ preventScroll: true });
    };
  }, [onClose]);

  // Vor dem ersten Bild: Skalierungs-Ursprung auf den auslösenden Klick legen
  useLayoutEffect(() => {
    const el = sheetRef.current;
    if (!dialog || !el || !lastPointer || performance.now() - lastPointer.t > 1000) return;
    const r = el.getBoundingClientRect();
    const clamp = (v: number) => Math.min(1, Math.max(0, v));
    el.style.transformOrigin = `${clamp((lastPointer.x - r.left) / r.width) * 100}% ${clamp((lastPointer.y - r.top) / r.height) * 100}%`;
  }, [dialog]);

  // Wischgeste mit Touch-Ereignissen: nur so lässt sich im Inhalt das Scrollen
  // abfangen, sobald er oben angekommen ist (preventDefault braucht passive: false)
  useEffect(() => {
    const sheet = sheetRef.current;
    if (!draggable || !sheet) return;
    let drag: { startY: number; startValue: number; fromHead: boolean; active: boolean; samples: { t: number; y: number }[] } | null = null;

    const start = (e: TouchEvent) => {
      if (e.touches.length !== 1) return;
      const target = e.target as Node;
      const fromHead = !!headRef.current?.contains(target);
      // Knöpfe im Kopf (Schließen, Aktion) bleiben Knöpfe – gezogen wird erst bei Bewegung
      if (!fromHead && !bodyRef.current?.contains(target)) return;
      y.stop(); // Unterbrechen: vom aktuellen Wert weiter
      const t = e.touches[0];
      drag = { startY: t.clientY, startValue: Number(y.get()) || 0, fromHead, active: fromHead, samples: [{ t: e.timeStamp, y: t.clientY }] };
    };

    const move = (e: TouchEvent) => {
      if (!drag) return;
      const t = e.touches[0];
      const dy = t.clientY - drag.startY;
      if (!drag.active) {
        // Inhalt: nur übernehmen, wenn er ganz oben steht und nach unten gezogen wird
        const atTop = (bodyRef.current?.scrollTop ?? 0) <= 0;
        if (dy > 4 && atTop) {
          drag.active = true;
          drag.startY = t.clientY; // ab hier 1:1, ohne Sprung
        } else if (Math.abs(dy) > 4) {
          drag = null; // normales Scrollen
          return;
        } else return;
      }
      e.preventDefault();
      const raw = drag.startValue + (t.clientY - drag.startY);
      const h = sheet.offsetHeight || 600;
      y.set(raw < 0 ? (drag.fromHead ? rubberband(raw, h) : 0) : raw);
      drag.samples.push({ t: e.timeStamp, y: t.clientY });
      if (drag.samples.length > 5) drag.samples.shift();
    };

    const end = (e: TouchEvent) => {
      const d = drag;
      drag = null;
      if (!d || !d.active) return;
      const first = d.samples[0];
      const lastTouch = e.changedTouches[0];
      const last = { t: e.timeStamp, y: lastTouch ? lastTouch.clientY : first.y };
      const dt = Math.max(1, last.t - first.t);
      const velocity = ((last.y - first.y) / dt) * 1000; // px/s
      const h = sheet.offsetHeight || 600;
      const current = Number(y.get()) || 0;
      if (current < 2 && velocity < 50) return void animate(y, 0, reduce ? { duration: 0 } : SPRING_SHEET);
      const projected = current + project(velocity);
      if (projected > h * 0.5 && velocity > -200) {
        haptic("light");
        animate(y, h, reduce ? { duration: 0.15 } : { ...SPRING_SETTLE, velocity }).then(() => closeRef.current());
      } else {
        animate(y, 0, reduce ? { duration: 0.15 } : { ...SPRING_SHEET, velocity });
      }
    };

    sheet.addEventListener("touchstart", start, { passive: true });
    sheet.addEventListener("touchmove", move, { passive: false });
    sheet.addEventListener("touchend", end);
    sheet.addEventListener("touchcancel", end);
    return () => {
      sheet.removeEventListener("touchstart", start);
      sheet.removeEventListener("touchmove", move);
      sheet.removeEventListener("touchend", end);
      sheet.removeEventListener("touchcancel", end);
    };
  }, [draggable, reduce, y]);

  return (
    <div className={`fixed inset-0 z-50 flex justify-center ${dialog ? "items-center p-8" : "items-end"}`} role="presentation">
      <motion.div
        className="absolute inset-0"
        style={{ background: "var(--scrim)", opacity: draggable ? scrimOpacity : undefined }}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        transition={{ duration: 0.2 }}
        onClick={onClose}
      />
      <motion.div
        ref={sheetRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={title ? titleId : undefined}
        tabIndex={-1}
        className={`sheet relative flex w-full flex-col outline-none ${dialog ? "sheet-dialog max-w-lg" : "max-w-xl"}`}
        style={dialog ? { maxHeight: `min(${maxHeight}dvh, 46rem)` } : { y, maxHeight: `${maxHeight}dvh` }}
        initial={reduce ? { opacity: 0 } : dialog ? DIALOG_HIDDEN : { y: offscreen }}
        animate={reduce ? { opacity: 1 } : dialog ? DIALOG_SHOWN : { y: 0 }}
        exit={reduce ? { opacity: 0 } : dialog ? DIALOG_HIDDEN : { y: offscreen }}
        transition={reduce ? { duration: 0.2 } : dialog ? SPRING_DIALOG : SPRING_SHEET}
      >
        <div ref={headRef} className={`flex shrink-0 flex-col items-center px-4 pb-1 select-none ${draggable ? "touch-none pt-2" : "pt-3"}`}>
          {!dialog && <div className="sheet-grabber" />}
          <div className={`flex min-h-9 w-full items-center gap-2 ${dialog ? "" : "mt-2"}`}>
            <button className="btn-plain pressable t-sub min-w-16 text-left" style={{ color: "var(--accent)" }} onClick={onClose}>
              Schließen
            </button>
            <h2 id={titleId} className="t-headline flex-1 truncate text-center">{title}</h2>
            <div className="flex min-w-16 justify-end">{action}</div>
          </div>
        </div>
        <div ref={bodyRef} className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pt-2 pb-6">{children}</div>
      </motion.div>
    </div>
  );
}
