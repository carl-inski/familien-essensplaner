"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { IconBook, IconCalendar, IconCart, IconPeople, IconShelf } from "./icons";

const TABS = [
  { href: "/woche", label: "Woche", Icon: IconCalendar },
  { href: "/rezepte", label: "Rezepte", Icon: IconBook },
  { href: "/regal", label: "Regal", Icon: IconShelf },
  { href: "/einkaufsliste", label: "Einkauf", Icon: IconCart },
  { href: "/haushalt", label: "Haushalt", Icon: IconPeople },
];

export function TabBar() {
  const path = usePathname();
  return (
    <nav className="material tabbar fixed inset-x-0 bottom-0 z-40" aria-label="Hauptnavigation">
      <ul className="mx-auto grid max-w-2xl grid-cols-5">
        {TABS.map(({ href, label, Icon }) => {
          const active = path === href || path.startsWith(href + "/");
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
