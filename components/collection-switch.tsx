"use client";

// Handy: Rezepte und Kochbücher teilen sich den Tab „Rezepte“ – umschalten oben auf der Seite.
// Am Computer stehen beide ohnehin in der Seitenleiste.

import Link from "next/link";

export function CollectionSwitch({ active }: { active: "rezepte" | "regal" }) {
  return (
    <nav className="segmented mt-3 lg:hidden" aria-label="Sammlung">
      <Link href="/rezepte" data-on={active === "rezepte"} aria-current={active === "rezepte" ? "page" : undefined} className="pressable" replace>
        Rezepte
      </Link>
      <Link href="/regal" data-on={active === "regal"} aria-current={active === "regal" ? "page" : undefined} className="pressable" replace>
        Kochbücher
      </Link>
    </nav>
  );
}
