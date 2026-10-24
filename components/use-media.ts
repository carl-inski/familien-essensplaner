"use client";

import { useSyncExternalStore } from "react";

/** Ab dieser Breite (Tailwind lg) gilt die Computer-Ansicht: Seitenleiste, Wochenraster, Dialoge statt Sheets */
export const DESKTOP_QUERY = "(min-width: 64rem)";

export function useMedia(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const mq = window.matchMedia(query);
      mq.addEventListener("change", onChange);
      return () => mq.removeEventListener("change", onChange);
    },
    () => window.matchMedia(query).matches,
    () => false,
  );
}

export function useIsDesktop(): boolean {
  return useMedia(DESKTOP_QUERY);
}
