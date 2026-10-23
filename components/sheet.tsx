"use client";

// Bottom Sheet mit direkter Manipulation:
// - folgt dem Finger 1:1 (ab dem Griff oder dem Kopfbereich), respektiert den Greifpunkt
// - Gummiband-Widerstand nach oben
// - beim Loslassen: Momentum-Projektion entscheidet zwischen Schließen und Zurückfedern,
//   die Feder übernimmt die Fingergeschwindigkeit
// - jederzeit unterbrechbar (Feder startet vom aktuellen Wert)
// - Reduce Motion: Überblenden statt Gleiten

import { AnimatePresence, animate, motion, useMotionValue, useReducedMotion, useTransform } from "motion/react";
import { useCallback, useEffect, useId, useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";

const SPRING_SHEET = { type: "spring" as const, bounce: 0.15, duration: 0.35 };
const SPRING_SETTLE = { type: "spring" as const, bounce: 0, duration: 0.3 };

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
  const y = useMotionValue(0);
  const sheetRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const drag = useRef<{ startY: number; startValue: number; samples: { t: number; y: number }[] } | null>(null);
  const scrimOpacity = useTransform(y, (v) => {
    const h = sheetRef.current?.offsetHeight ?? 600;
    return Math.max(0, 1 - Math.max(0, v) / h);
  });

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    sheetRef.current?.focus();
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onClose]);

  const onPointerDown = useCallback((e: React.PointerEvent) => {
    if (reduce) return;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    y.stop(); // Unterbrechen: vom aktuellen Wert weiter
    drag.current = { startY: e.clientY, startValue: y.get(), samples: [{ t: e.timeStamp, y: e.clientY }] };
  }, [reduce, y]);

  const onPointerMove = useCallback((e: React.PointerEvent) => {
    const d = drag.current;
    if (!d) return;
    const raw = d.startValue + (e.clientY - d.startY);
    const h = sheetRef.current?.offsetHeight ?? 600;
    y.set(raw < 0 ? rubberband(raw, h) : raw);
    d.samples.push({ t: e.timeStamp, y: e.clientY });
    if (d.samples.length > 5) d.samples.shift();
  }, [y]);

  const onPointerUp = useCallback((e: React.PointerEvent) => {
    const d = drag.current;
    drag.current = null;
    if (!d) return;
    const first = d.samples[0];
    const last = { t: e.timeStamp, y: e.clientY };
    const dt = Math.max(1, last.t - first.t);
    const velocity = ((last.y - first.y) / dt) * 1000; // px/s
    const h = sheetRef.current?.offsetHeight ?? 600;
    const projected = y.get() + project(velocity);
    if (projected > h * 0.5 && velocity > -200) {
      animate(y, h, { ...SPRING_SETTLE, velocity }).then(onClose);
    } else {
      animate(y, 0, { ...SPRING_SHEET, velocity });
    }
  }, [onClose, y]);

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center" role="presentation">
      <motion.div
        className="absolute inset-0"
        style={{ background: "var(--scrim)", opacity: reduce ? undefined : scrimOpacity }}
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
        className="sheet relative flex w-full max-w-xl flex-col outline-none"
        style={{ y, maxHeight: `${maxHeight}dvh` }}
        initial={reduce ? { opacity: 0 } : { y: "100%" }}
        animate={reduce ? { opacity: 1 } : { y: 0 }}
        exit={reduce ? { opacity: 0 } : { y: "100%" }}
        transition={reduce ? { duration: 0.2 } : SPRING_SHEET}
      >
        <div
          className="flex shrink-0 cursor-grab touch-none flex-col items-center px-4 pt-2 pb-1 active:cursor-grabbing"
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
        >
          <div className="sheet-grabber" />
          <div className="mt-2 flex min-h-9 w-full items-center gap-2">
            <button className="btn-plain pressable t-sub min-w-16 text-left" style={{ color: "var(--accent)" }} onClick={onClose}>
              Schließen
            </button>
            <h2 id={titleId} className="t-headline flex-1 truncate text-center">{title}</h2>
            <div className="flex min-w-16 justify-end">{action}</div>
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pt-2 pb-6">{children}</div>
      </motion.div>
    </div>
  );
}
