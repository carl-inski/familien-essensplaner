"use client";

import { motion, useReducedMotion } from "motion/react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useApp } from "./app-data";
import { Avatar } from "./ui";
import { IconBook, IconCalendar, IconCart, IconPeople, IconShelf } from "./icons";

const TABS = [
  { href: "/woche", label: "Woche", Icon: IconCalendar },
  { href: "/rezepte", label: "Rezepte", Icon: IconBook },
  { href: "/regal", label: "Regal", Icon: IconShelf },
  { href: "/einkaufsliste", label: "Einkauf", Icon: IconCart },
  { href: "/haushalt", label: "Haushalt", Icon: IconPeople },
];

const isActive = (path: string, href: string) => path === href || path.startsWith(href + "/");

/** Handy und Tablet: schwebende Tableiste unten */
export function TabBar() {
  const path = usePathname();
  return (
    <nav className="material tabbar fixed inset-x-0 bottom-0 z-40 lg:hidden" aria-label="Hauptnavigation">
      <ul className="mx-auto grid max-w-2xl grid-cols-5">
        {TABS.map(({ href, label, Icon }) => {
          const active = isActive(path, href);
          return (
            <li key={href}>
              <Link
                href={href}
                aria-current={active ? "page" : undefined}
                className="pressable flex flex-col items-center gap-0.5 pt-2 pb-1.5"
                style={{ color: active ? "var(--accent)" : "var(--label-2)" }}
              >
                <Icon size={25} strokeWidth={active ? 2.1 : 1.7} />
                <span className="text-[10.5px] font-medium tracking-[0.01em]">{label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

/** Computer: Seitenleiste links – schmal als Leiste mit Symbolen (lg), breit mit Beschriftung (xl) */
export function Sidebar() {
  const path = usePathname();
  const { me, household } = useApp();
  const reduce = useReducedMotion();
  return (
    <nav className="sidebar fixed inset-y-0 left-0 z-40 hidden flex-col lg:flex" aria-label="Hauptnavigation">
      <Link href="/woche" className="pressable flex h-16 shrink-0 items-center justify-center gap-2.5 xl:justify-start xl:px-5" aria-label="Essensplaner – zur Woche">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/icon.svg" alt="" width={30} height={30} className="rounded-[8px]" />
        <span className="t-headline hidden xl:inline">Essensplaner</span>
      </Link>
      <ul className="flex flex-col gap-1 px-2 xl:px-3">
        {TABS.map(({ href, label, Icon }) => {
          const active = isActive(path, href);
          return (
            <li key={href}>
              <Link
                href={href}
                aria-current={active ? "page" : undefined}
                className="sidebar-item pressable relative flex flex-col items-center gap-1 rounded-xl py-2 xl:flex-row xl:gap-3 xl:px-3"
              >
                {/* Die Markierung gleitet zum neuen Eintrag, statt zu springen */}
                {active && (
                  <motion.span
                    layoutId="sidebar-active"
                    className="absolute inset-0 rounded-xl"
                    style={{ background: "var(--accent-soft)" }}
                    transition={reduce ? { duration: 0 } : { type: "spring", bounce: 0, duration: 0.35 }}
                    aria-hidden
                  />
                )}
                <Icon size={22} strokeWidth={active ? 2.1 : 1.8} className="relative" />
                <span className="relative text-[11px] font-medium tracking-[0.01em] xl:text-[0.9375rem] xl:tracking-[-0.008em]">{label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
      <Link
        href="/haushalt"
        className="sidebar-item pressable mx-2 mt-auto mb-3 flex items-center justify-center gap-2.5 rounded-xl py-2 xl:mx-3 xl:justify-start xl:px-3"
        title={`Angemeldet als ${me.name} · ${household.name}`}
      >
        <Avatar member={me} size={30} />
        <span className="hidden min-w-0 leading-tight xl:block">
          <span className="t-footnote block truncate font-semibold" style={{ color: "var(--label)" }}>{me.name}</span>
          <span className="t-caption block truncate">{household.name}</span>
        </span>
      </Link>
    </nav>
  );
}
