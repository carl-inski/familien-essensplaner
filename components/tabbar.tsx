"use client";

import { motion, useReducedMotion } from "motion/react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { useApp } from "./app-data";
import { useAssistant } from "./assistant/assistant-provider";
import { Avatar } from "./ui";
import { IconBook, IconCalendar, IconCart, IconHistory, IconPeople, IconPlus, IconShelf, IconSidebar, IconSparkles } from "./icons";

const TABS = [
  { href: "/woche", label: "Woche", Icon: IconCalendar },
  { href: "/rezepte", label: "Rezepte", Icon: IconBook },
  { href: "/assistent", label: "KI", Icon: IconSparkles },
  { href: "/einkaufsliste", label: "Einkauf", Icon: IconCart },
  { href: "/regal", label: "Regal", Icon: IconShelf },
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

// Computer: Seitenleiste im Stil von Notion – Haushalt oben, die KI als erster Eintrag,
// darunter die Bereiche in zwei Gruppen. Einklappbar (⌘\), der Zustand bleibt auf dem Gerät.
const GROUPS = [
  {
    label: "Planen",
    items: [
      { href: "/woche", label: "Woche", Icon: IconCalendar },
      { href: "/einkaufsliste", label: "Einkauf", Icon: IconCart },
    ],
  },
  {
    label: "Sammlung",
    items: [
      { href: "/rezepte", label: "Rezepte", Icon: IconBook },
      { href: "/rezepte/lange-nicht", label: "Lange nicht gegessen", Icon: IconHistory },
      { href: "/regal", label: "Regal", Icon: IconShelf },
    ],
  },
];
const ALL_HREFS = [...GROUPS.flatMap((g) => g.items.map((i) => i.href)), "/haushalt", "/assistent"];
const SIDEBAR_KEY = "seitenleiste";

/** Der längste passende Eintrag gewinnt: /rezepte/lange-nicht markiert nicht auch /rezepte */
function activeHref(path: string) {
  return ALL_HREFS.filter((h) => isActive(path, h)).sort((a, b) => b.length - a.length)[0];
}

export function Sidebar() {
  const path = usePathname();
  const { me, household } = useApp();
  const { ask, panelOpen, panelAvailable, setPanelOpen, aiEnabled } = useAssistant();
  const reduce = useReducedMotion();
  const [collapsed, setCollapsed] = useState(() => {
    try {
      return typeof window !== "undefined" && localStorage.getItem(SIDEBAR_KEY) === "zu";
    } catch {
      return false;
    }
  });
  const current = activeHref(path);
  const spring = reduce ? { duration: 0 } : { type: "spring" as const, bounce: 0, duration: 0.3 };
  // Die Markierung gleitet zum neuen Eintrag, statt zu springen
  const marker = <motion.span layoutId="sidebar-active" className="sidebar-marker absolute inset-0" transition={spring} aria-hidden />;

  useEffect(() => {
    document.documentElement.dataset.sidebar = collapsed ? "collapsed" : "open";
    try {
      localStorage.setItem(SIDEBAR_KEY, collapsed ? "zu" : "auf");
    } catch {}
  }, [collapsed]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "\\") {
        e.preventDefault();
        setCollapsed((c) => !c);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const item = (href: string, label: string, Icon: typeof IconCalendar) => {
    const active = current === href;
    return (
      <li key={href}>
        <Link href={href} aria-current={active ? "page" : undefined} className="sidebar-item pressable relative">
          {active && marker}
          <Icon size={18} strokeWidth={active ? 2 : 1.7} className="relative shrink-0" />
          <span className="relative truncate">{label}</span>
        </Link>
      </li>
    );
  };

  return (
    <>
      <nav className="sidebar fixed inset-y-0 left-0 z-40 hidden flex-col lg:flex" aria-label="Hauptnavigation" inert={collapsed}>
        {/* Haushalt wie der Workspace in Notion */}
        <div className="flex h-12 shrink-0 items-center gap-1 px-2 pt-1">
          <Link href="/woche" className="sidebar-item pressable relative min-w-0 flex-1 !font-semibold" style={{ color: "var(--label)" }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/icon.svg" alt="" width={20} height={20} className="shrink-0 rounded-[5px]" />
            <span className="truncate">{household.name}</span>
          </Link>
          <button className="sidebar-tool pressable" onClick={() => setCollapsed(true)} aria-label="Seitenleiste einklappen" title="Seitenleiste einklappen (⌘\)">
            <IconSidebar size={18} />
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-2 pb-2">
          <ul className="flex flex-col gap-px">
            {panelAvailable && aiEnabled !== false ? (
              <li>
                <button className="sidebar-item sidebar-ai pressable relative w-full" aria-pressed={panelOpen} onClick={() => (panelOpen ? setPanelOpen(false) : ask())} title="KI ein- und ausblenden (⌘J)">
                  <span className="ai-orb flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full"><IconSparkles size={13} /></span>
                  <span className="flex-1 truncate text-left">KI-Assistent</span>
                  <kbd>⌘J</kbd>
                </button>
              </li>
            ) : (
              item("/assistent", "KI-Assistent", IconSparkles)
            )}
            <li>
              <Link href="/rezepte/neu" className="sidebar-item pressable relative">
                <IconPlus size={18} strokeWidth={1.7} className="shrink-0" />
                <span className="truncate">Neues Rezept</span>
              </Link>
            </li>
          </ul>

          {GROUPS.map((g) => (
            <div key={g.label} className="mt-5">
              <p className="sidebar-heading">{g.label}</p>
              <ul className="flex flex-col gap-px">{g.items.map((i) => item(i.href, i.label, i.Icon))}</ul>
            </div>
          ))}
        </div>

        <div className="shrink-0 px-2 pb-3">
          <Link
            href="/haushalt"
            aria-current={current === "/haushalt" ? "page" : undefined}
            className="sidebar-item pressable relative !h-11"
            title={`Angemeldet als ${me.name} · ${household.name}`}
          >
            {current === "/haushalt" && marker}
            <span className="relative"><Avatar member={me} size={26} /></span>
            <span className="relative min-w-0 leading-tight">
              <span className="block truncate" style={{ color: "var(--label)" }}>{me.name}</span>
              <span className="t-caption block truncate">Haushalt & Konto</span>
            </span>
            <IconPeople size={16} className="relative ml-auto shrink-0 opacity-60" />
          </Link>
        </div>
      </nav>
      {collapsed && (
        <button className="sidebar-reveal pressable hidden lg:flex" onClick={() => setCollapsed(false)} aria-label="Seitenleiste ausklappen" title="Seitenleiste ausklappen (⌘\)">
          <IconSidebar size={18} />
        </button>
      )}
    </>
  );
}
