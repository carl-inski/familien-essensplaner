"use client";

// Handy: großer Titel, der beim Scrollen in eine schwebende, transluzente Navigationsleiste übergeht.
// Computer: ruhige Kopfzeile – links nur der Weg zurück, rechts Aktionen und „KI fragen“;
// darunter der große Titel, optional ein Titelbild und die KI-Zeile immer an derselben Stelle.

import Link from "next/link";
import { useEffect, useRef, useState, type ReactNode } from "react";
import type { AssistantContext } from "@/lib/ai/assistant-schemas";
import { AiButton, AiPromptBar } from "./assistant/ai-panel";
import { IconChevronLeft } from "./icons";

interface Props {
  title: string;
  subtitle?: ReactNode;
  back?: { href: string; label: string };
  trailing?: ReactNode;
  children?: ReactNode; // z. B. Suchfeld unter dem Titel
  /** Breite wie der Seiteninhalt: schmal (Standard), mittel oder breit (Computer) */
  width?: "narrow" | "medium" | "wide";
  /** Titelbild über dem Titel, nur am Computer */
  cover?: ReactNode;
  /** Bezug für „KI fragen“ oben rechts und die KI-Zeile, z. B. das offene Rezept */
  aiKontext?: AssistantContext;
  /** KI-Zeile unter dem Titel – auf jeder Seite an derselben Stelle und gleich breit */
  ai?: { placeholder: string; suggestions: string[] };
}

const PAGE_CLASS = { narrow: "page", medium: "page-medium", wide: "page-wide" } as const;

export function PageHeader({ title, subtitle, back, trailing, children, width = "narrow", cover, aiKontext, ai }: Props) {
  const page = PAGE_CLASS[width];
  const sentinel = useRef<HTMLDivElement>(null);
  const [compact, setCompact] = useState(false);

  useEffect(() => {
    const el = sentinel.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => setCompact(!e.isIntersecting), { rootMargin: "-52px 0px 0px 0px" });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <>
      <div
        className={`topbar app-fixed fixed top-0 z-30 transition-[background-color,box-shadow] duration-200 ${compact ? "material navbar-edge" : ""}`}
        data-compact={compact}
        style={{ paddingTop: "env(safe-area-inset-top)" }}
      >
        <div className={`topbar-row ${page} flex h-11 items-center gap-2 px-2`}>
          {/* Handy: Zurück-Link links, Titel erscheint beim Scrollen in der Mitte */}
          <div className="flex min-w-20 items-center lg:hidden">
            {back && (
              <Link href={back.href} className="pressable t-sub flex items-center gap-0.5 py-2 pr-2" style={{ color: "var(--accent)" }}>
                <IconChevronLeft size={22} />
                <span className="max-w-28 truncate">{back.label}</span>
              </Link>
            )}
          </div>
          <div
            className="t-headline flex-1 truncate text-center transition-opacity duration-200 lg:hidden"
            style={{ opacity: compact ? 1 : 0 }}
            aria-hidden={!compact}
          >
            {title}
          </div>
          {/* Computer: nur der Weg zurück – der Titel steht groß darunter */}
          <div className="hidden min-w-0 flex-1 items-center lg:flex">
            {back && (
              <Link href={back.href} className="crumb pressable">
                <IconChevronLeft size={16} />
                <span className="truncate">{back.label}</span>
              </Link>
            )}
          </div>
          <div className="flex min-w-20 items-center justify-end gap-1 pr-1 lg:min-w-0">
            {trailing}
            <span className="hidden lg:contents"><AiButton kontext={aiKontext} /></span>
          </div>
        </div>
      </div>
      {cover && <div className="page-cover hidden lg:block">{cover}</div>}
      <header className={`page-header ${page} flex flex-col`} data-cover={!!cover}>
        <h1 className="t-large-title">{title}</h1>
        {subtitle && <div className="t-sub mt-1" style={{ color: "var(--label-2)" }}>{subtitle}</div>}
        {/* Handy: unter den Bedienelementen der Seite. Computer: direkt unter dem Titel. */}
        {ai && <AiPromptBar className="page-ai order-last mt-4 lg:order-none" kontext={aiKontext} placeholder={ai.placeholder} suggestions={ai.suggestions} />}
        <div ref={sentinel} aria-hidden className="h-px" />
        {children}
      </header>
    </>
  );
}

export function IconButton({ label, onClick, children, href, className = "" }: { label: string; onClick?: () => void; children: ReactNode; href?: string; className?: string }) {
  const cls = `icon-button pressable flex h-9 w-9 items-center justify-center rounded-full ${className}`;
  if (href)
    return (
      <Link href={href} aria-label={label} title={label} className={cls}>
        {children}
      </Link>
    );
  return (
    <button aria-label={label} title={label} className={cls} onClick={onClick}>
      {children}
    </button>
  );
}
