"use client";

// Großer Titel, der beim Scrollen in eine schwebende, transluzente Navigationsleiste übergeht.

import Link from "next/link";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { IconChevronLeft } from "./icons";

interface Props {
  title: string;
  subtitle?: ReactNode;
  back?: { href: string; label: string };
  trailing?: ReactNode;
  children?: ReactNode; // z. B. Suchfeld unter dem Titel
  /** Breite wie der Seiteninhalt: schmal (Standard), mittel oder breit (Computer) */
  width?: "narrow" | "medium" | "wide";
}

const PAGE_CLASS = { narrow: "page", medium: "page-medium", wide: "page-wide" } as const;

export function PageHeader({ title, subtitle, back, trailing, children, width = "narrow" }: Props) {
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
        className={`app-fixed fixed right-0 top-0 z-40 transition-[background-color,box-shadow] duration-200 ${compact ? "material navbar-edge" : ""}`}
        style={{ paddingTop: "env(safe-area-inset-top)" }}
      >
        <div className={`${page} flex h-11 items-center gap-2 px-2 lg:px-6`}>
          <div className="flex min-w-20 items-center">
            {back && (
              <Link href={back.href} className="pressable t-sub flex items-center gap-0.5 py-2 pr-2" style={{ color: "var(--accent)" }}>
                <IconChevronLeft size={22} />
                <span className="max-w-28 truncate">{back.label}</span>
              </Link>
            )}
          </div>
          <div
            className="t-headline flex-1 truncate text-center transition-opacity duration-200"
            style={{ opacity: compact ? 1 : 0 }}
            aria-hidden={!compact}
          >
            {title}
          </div>
          <div className="flex min-w-20 items-center justify-end gap-1 pr-1">{trailing}</div>
        </div>
      </div>
      <header className={page} style={{ paddingTop: "calc(env(safe-area-inset-top) + 48px)" }}>
        <h1 className="t-large-title">{title}</h1>
        {subtitle && <div className="t-sub mt-1" style={{ color: "var(--label-2)" }}>{subtitle}</div>}
        <div ref={sentinel} aria-hidden className="h-px" />
        {children}
      </header>
    </>
  );
}

export function IconButton({ label, onClick, children, href }: { label: string; onClick?: () => void; children: ReactNode; href?: string }) {
  const cls = "icon-button pressable flex h-9 w-9 items-center justify-center rounded-full";
  const style = { color: "var(--accent)" };
  if (href)
    return (
      <Link href={href} aria-label={label} title={label} className={cls} style={style}>
        {children}
      </Link>
    );
  return (
    <button aria-label={label} title={label} className={cls} style={style} onClick={onClick}>
      {children}
    </button>
  );
}
