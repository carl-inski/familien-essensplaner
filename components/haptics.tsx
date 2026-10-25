"use client";

// Haptik an einer Stelle: Umschalter, Abhaken, Zähler und Tabs geben ein kurzes
// Feedback. Einzelne Elemente können mit data-haptic="medium|success|…" abweichen
// oder es mit data-haptic="off" abschalten.

import { useEffect } from "react";
import { haptic, isHapticSwitch, type HapticKind } from "@/lib/haptics";

const LIGHT = [
  "[aria-pressed]",
  "[role=radio]",
  "[role=tab]",
  "[role=switch]",
  "input[type=checkbox]",
  "[data-tab]",
  "button[aria-label$=' erhöhen']",
  "button[aria-label$=' verringern']",
].join(",");

export function Haptics() {
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (isHapticSwitch(e.target)) return;
      const el = (e.target as Element | null)?.closest?.(`[data-haptic], ${LIGHT}`);
      if (!el || (el as HTMLButtonElement).disabled) return;
      const kind = el.getAttribute("data-haptic");
      if (kind === "off") return;
      haptic((kind as HapticKind | null) ?? "light");
    };
    document.addEventListener("click", onClick, true);
    return () => document.removeEventListener("click", onClick, true);
  }, []);
  return null;
}
