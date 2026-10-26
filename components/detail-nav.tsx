"use client";

// Details als Fenster (Sheet) statt eigener Seite – auf dem Handy wie in iOS:
// Rezept (?r=…), Kochbuch (?b=…) und Profil (?profil) öffnen sich über der aktuellen
// Seite; „Zurück“ bzw. Wischen schließt sie wieder. Am Computer bleiben es Seiten.
// Der Zustand steht in der URL, damit Zurück-Geste und Teilen funktionieren.

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import type { ComponentProps, MouseEvent } from "react";
import { useIsDesktop } from "./use-media";

export type DetailKey = "r" | "b" | "profil";

// Welche Fenster wir selbst per push geöffnet haben: die schließt „Zurück“ (router.back),
// alle anderen (z. B. aus einem geteilten Link) ein replace ohne den Parameter.
const pushed = new Set<DetailKey>();
export const forgetPushed = (key: DetailKey) => pushed.delete(key);

const DESKTOP_HREF: Record<DetailKey, (v: string) => string> = {
  r: (v) => `/rezepte/${v}`,
  b: (v) => `/regal/${v}`,
  profil: () => "/haushalt",
};

export function useDetailNav() {
  const router = useRouter();
  const pathname = usePathname();
  const desktop = useIsDesktop();

  const open = (key: DetailKey, value = "1") => {
    if (desktop) return router.push(DESKTOP_HREF[key](value));
    const next = new URLSearchParams(window.location.search);
    next.set(key, value);
    pushed.add(key);
    router.push(`${pathname}?${next}`, { scroll: false });
  };

  const close = (key: DetailKey) => {
    if (pushed.has(key)) {
      pushed.delete(key);
      router.back();
      return;
    }
    const next = new URLSearchParams(window.location.search);
    next.delete(key);
    const qs = next.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
  };

  return { open, close, desktop };
}

/**
 * Link zu einem Rezept oder Kochbuch: am Computer eine normale Seite, auf dem Handy
 * ein Fenster über der aktuellen Ansicht. Mittelklick & Co. bleiben normale Links.
 */
export function DetailLink({ kind, id, onClick, ...rest }: { kind: "r" | "b"; id: string } & Omit<ComponentProps<typeof Link>, "href">) {
  const { open, desktop } = useDetailNav();
  return (
    <Link
      {...rest}
      href={DESKTOP_HREF[kind](id)}
      onClick={(e: MouseEvent<HTMLAnchorElement>) => {
        onClick?.(e);
        if (desktop || e.defaultPrevented || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
        e.preventDefault();
        open(kind, id);
      }}
    />
  );
}
