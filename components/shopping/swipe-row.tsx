"use client";

// Listenzeile mit versteckten Aktionsknöpfen wie in iOS: nach links wischen (oder lange
// drücken) zeigt „Ist noch da“ und „Immer zu Hause“, ganz durchwischen löst die
// Hauptaktion (rechts außen) direkt aus. Am Computer stehen die Knöpfe rechts in der Zeile.

import { animate, motion, useMotionValue, useReducedMotion } from "motion/react";
import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { haptic } from "@/lib/haptics";

const ONE_W = 104;
const TWO_W = 176;
const FULL_SWIPE = 240;

export interface RowAction {
  /** für Screenreader und Tooltip */
  label: string;
  /** kurzer Text unter dem Symbol */
  short: string;
  icon: ReactNode;
  run: () => void;
}

// Nur eine Zeile gleichzeitig offen
const openers = new Set<(id: string) => void>();
const announceOpen = (id: string) => openers.forEach((f) => f(id));

export function SwipeRow({
  children,
  actionLabel,
  actionShort = "Immer da",
  actionIcon,
  onAction,
  secondary,
  desktop,
}: {
  children: (opts: { onClick: (fn: () => void) => () => void }) => ReactNode;
  actionLabel: string;
  actionShort?: string;
  actionIcon: ReactNode;
  onAction: () => void;
  /** zweite Aktion links neben der Hauptaktion */
  secondary?: RowAction;
  desktop: boolean;
}) {
  const ACTION_W = secondary ? TWO_W : ONE_W;
  const id = useId();
  const x = useMotionValue(0);
  const reduce = useReducedMotion();
  const [open, setOpen] = useState(false);
  const dragged = useRef(false);
  const press = useRef<ReturnType<typeof setTimeout> | null>(null);

  const settle = (to: number) => animate(x, to, reduce ? { duration: 0 } : { type: "spring", bounce: 0, duration: 0.3 });
  const close = () => {
    setOpen(false);
    settle(0);
  };
  const reveal = () => {
    setOpen(true);
    settle(-ACTION_W);
    announceOpen(id);
  };

  useEffect(() => {
    const onOther = (other: string) => other !== id && (setOpen(false), settle(0));
    openers.add(onOther);
    return () => void openers.delete(onOther);
  });

  if (desktop)
    return (
      <li className="flex items-stretch">
        {children({ onClick: (fn) => fn })}
        {secondary && (
          <button className="pressable flex w-11 shrink-0 items-center justify-center" style={{ color: "var(--label-2)" }} aria-label={secondary.label} title={secondary.label} onClick={secondary.run}>
            {secondary.icon}
          </button>
        )}
        <button className="pressable flex w-12 shrink-0 items-center justify-center" style={{ color: "var(--label-2)" }} aria-label={actionLabel} title={actionLabel} onClick={onAction}>
          {actionIcon}
        </button>
      </li>
    );

  const cancelPress = () => press.current && (clearTimeout(press.current), (press.current = null));

  return (
    <li className="relative overflow-hidden">
      {secondary && (
        <button
          className="absolute inset-y-0 flex flex-col items-center justify-center gap-0.5 text-[12px] font-semibold"
          style={{ right: ACTION_W / 2, width: ACTION_W / 2, background: "var(--green)", color: "#fff" }}
          aria-label={secondary.label}
          tabIndex={open ? 0 : -1}
          onFocus={reveal}
          onClick={() => {
            haptic("medium");
            close();
            secondary.run();
          }}
        >
          {secondary.icon}
          <span>{secondary.short}</span>
        </button>
      )}
      <button
        className="absolute inset-y-0 right-0 flex flex-col items-center justify-center gap-0.5 text-[12px] font-semibold"
        style={{ width: secondary ? ACTION_W / 2 : ACTION_W, background: "var(--accent)", color: "var(--on-accent)" }}
        aria-label={actionLabel}
        tabIndex={open ? 0 : -1}
        onFocus={reveal}
        onClick={() => {
          haptic("medium");
          close();
          onAction();
        }}
      >
        {actionIcon}
        <span>{actionShort}</span>
      </button>
      <motion.div
        className="relative"
        style={{ x, background: "var(--surface)", touchAction: "pan-y" }}
        drag="x"
        dragDirectionLock
        dragConstraints={{ left: -ACTION_W, right: 0 }}
        dragElastic={{ left: 0.6, right: 0.05 }}
        dragMomentum={false}
        onDragStart={() => {
          dragged.current = true;
          cancelPress();
        }}
        onDragEnd={(_, info) => {
          setTimeout(() => (dragged.current = false), 0);
          if (info.offset.x < -FULL_SWIPE) {
            haptic("medium");
            close();
            onAction();
          } else if (x.get() < -ACTION_W / 2 || info.velocity.x < -400) {
            if (!open) haptic("light");
            reveal();
          } else close();
        }}
        onPointerDown={(e) => {
          if (e.pointerType !== "touch") return;
          cancelPress();
          press.current = setTimeout(() => {
            dragged.current = true; // der folgende Tipp hakt nicht ab
            haptic("light");
            reveal();
          }, 500);
        }}
        onPointerUp={cancelPress}
        onPointerCancel={cancelPress}
      >
        {children({
          // Wischen/Langdruck oder offene Zeile: Tipp schließt nur, statt abzuhaken
          onClick: (fn) => () => {
            if (dragged.current) {
              dragged.current = false;
              return;
            }
            if (open) return close();
            fn();
          },
        })}
      </motion.div>
    </li>
  );
}
