"use client";

// Haptik an einer Stelle: Umschalter, Abhaken, Zähler und Tabs geben ein kurzes
// Feedback. Einzelne Elemente können mit data-haptic="medium|success|…" abweichen
// oder es mit data-haptic="off" abschalten.

import { useEffect } from "react";
import { attachIOSHaptic, haptic, hapticsEnabled, iosHapticsSupported, type HapticKind } from "@/lib/haptics";

const TARGETS = [
  "[data-haptic]:not([data-haptic=off])",
  "button[aria-pressed]",
  "button[role=radio]",
  "a[data-tab]",
  "button[data-tab]",
  "button[aria-label$=' erhöhen']",
  "button[aria-label$=' verringern']",
].join(",");

export function Haptics() {
  useEffect(() => {
    document.documentElement.dataset.haptics = hapticsEnabled() ? "on" : "off";

    // iPhone: Etiketten einfügen – auch für alles, was später erscheint (Sheets, Listen)
    if (iosHapticsSupported()) {
      const scan = (root: ParentNode) => {
        root.querySelectorAll<HTMLElement>(TARGETS).forEach((el) => {
          if (el instanceof HTMLButtonElement || el instanceof HTMLAnchorElement || el.getAttribute("role") === "button") attachIOSHaptic(el);
        });
      };
      scan(document);
      let queued = false;
      const observer = new MutationObserver(() => {
        if (queued) return;
        queued = true;
        requestAnimationFrame(() => {
          queued = false;
          scan(document);
        });
      });
      observer.observe(document.body, { childList: true, subtree: true });
      return () => observer.disconnect();
    }

    // Android & Co.: Vibration API beim Klick
    const onClick = (e: MouseEvent) => {
      const el = (e.target as Element | null)?.closest?.(TARGETS);
      if (!el || (el as HTMLButtonElement).disabled) return;
      haptic((el.getAttribute("data-haptic") as HapticKind | null) ?? "light");
    };
    document.addEventListener("click", onClick, true);
    return () => document.removeEventListener("click", onClick, true);
  }, []);
  return null;
}
