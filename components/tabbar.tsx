"use client";

import { motion, useReducedMotion } from "motion/react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { useApp } from "./app-data";
import { useAssistant } from "./assistant/assistant-provider";
import { Avatar } from "./ui";
import { IconBook, IconCalendar, IconCart, IconHistory, IconPeople, IconPlus, IconShelf, IconSidebar, IconSparkles } from "./icons";

// Handy: Tableiste im Liquid-Glass-Stil von iOS – links eine Glaskapsel mit
// Woche, Rezepte (inkl. Regal) und Einkauf, rechts die KI als eigener runder Knopf.
// Das Konto sitzt oben rechts auf den Tab-Seiten (PageHeader).
const TABS = [
  { href: "/woche", label: "Woche", Icon: IconCalendar, also: [] as string[] },
  { href: "/rezepte", label: "Rezepte", Icon: IconBook, also: ["/regal"] },
  { href: "/einkaufsliste", label: "Einkauf", Icon: IconCart, also: [] },
];

const isActive = (path: string, href: string) => path === href || path.startsWith(href + "/");

// Tippen: Solange ein Textfeld den Fokus hat (Tastatur offen), taucht die Tableiste ab
// und die KI-Eingabe rückt an die Tastatur – wie in iOS-Apps. Auswahlfelder, Schalter
// & Co. öffnen keine Tastatur und zählen nicht.
const NO_KEYBOARD = /^(checkbox|radio|button|submit|reset|file|range|color|image|hidden)$/;
function syncKeyboard() {
  const el = document.activeElement;
  const typing =
    (el instanceof HTMLInputElement && !NO_KEYBOARD.test(el.type)) ||
    el instanceof HTMLTextAreaElement ||
    (el instanceof HTMLElement && el.isContentEditable);
  if (typing) document.documentElement.dataset.keyboard = "open";
  else delete document.documentElement.dataset.keyboard;
}

/** Handy und Tablet: schwebende Glas-Tableiste unten */
export function TabBar() {
  const path = usePathname();
  const reduce = useReducedMotion();
  const kiActive = isActive(path, "/assistent");
  const spring = reduce ? { duration: 0 } : { type: "spring" as const, bounce: 0.2, duration: 0.4 };

  useEffect(() => {
    if (!matchMedia("(pointer: coarse)").matches) return;
    // Beim Wechsel zwischen Feldern (Pfeile über der Tastatur) nicht kurz aufblitzen
    const later = () => setTimeout(syncKeyboard, 0);
    const vv = window.visualViewport;
    document.addEventListener("focusin", syncKeyboard);
    document.addEventListener("focusout", later);
    // Feld verschwindet mit Fokus (Speichern, Seitenwechsel): die Tastatur geht zu, der Viewport wächst
    vv?.addEventListener("resize", syncKeyboard);
    return () => {
      document.removeEventListener("focusin", syncKeyboard);
      document.removeEventListener("focusout", later);
      vv?.removeEventListener("resize", syncKeyboard);
      delete document.documentElement.dataset.keyboard;
    };
  }, []);
  useEffect(syncKeyboard, [path]);

  return (
    <nav className="tabbar-dock fixed inset-x-0 z-40 flex items-end justify-center gap-3 px-4 lg:hidden" aria-label="Hauptnavigation">
      <ul className="glass tabbar-pill flex min-w-0 max-w-md flex-1 items-stretch rounded-full p-1">
        {TABS.map(({ href, label, Icon, also }) => {
          const active = [href, ...also].some((h) => isActive(path, h));
          return (
            <li key={href} className="relative flex-1">
              <Link
                href={href}
                data-tab
                aria-current={active ? "page" : undefined}
                className="tabbar-item relative flex h-[54px] flex-col items-center justify-center gap-0.5 rounded-full"
                style={{ color: active ? "var(--accent)" : "var(--label)" }}
              >
                {active && <motion.span layoutId="tabbar-active" className="tabbar-active absolute inset-0 rounded-full" transition={spring} aria-hidden />}
                <Icon size={24} strokeWidth={active ? 2.1 : 1.8} className="relative" />
                <span className="relative text-[10.5px] font-semibold tracking-[0.01em]">{label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
      <Link
        href="/assistent"
        data-tab
        aria-label="KI"
        aria-current={kiActive ? "page" : undefined}
        className="glass tabbar-ai flex h-[62px] w-[62px] shrink-0 items-center justify-center rounded-full"
        data-active={kiActive}
      >
        <IconSparkles size={26} strokeWidth={kiActive ? 2.1 : 1.8} />
      </Link>
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
