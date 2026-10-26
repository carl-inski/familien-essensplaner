"use client";

// Fenster für Rezept (?r=), Kochbuch (?b=) und Profil (?profil) – auf jeder Seite.
// Gestapelt wie in iOS: ein Rezept aus einem Kochbuch liegt über dem Kochbuch.

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useEffect } from "react";
import { BookView } from "./book-view";
import { forgetPushed, useDetailNav } from "./detail-nav";
import { HouseholdView } from "./household-view";
import { RecipeView } from "./recipe-view";
import { Sheet } from "./sheet";

export function DetailSheets() {
  return (
    <Suspense>
      <Host />
    </Suspense>
  );
}

function Host() {
  const params = useSearchParams();
  const { close } = useDetailNav();
  const r = params.get("r");
  const b = params.get("b");
  const profil = params.has("profil");

  // Mit der Zurück-Geste geschlossen: nicht mehr als „selbst geöffnet“ merken
  useEffect(() => {
    if (!r) forgetPushed("r");
    if (!b) forgetPushed("b");
    if (!profil) forgetPushed("profil");
  }, [r, b, profil]);

  return (
    <>
      <Sheet open={profil} onClose={() => close("profil")} title="Haushalt & Konto">
        <HouseholdView inSheet />
      </Sheet>
      <Sheet open={!!b} onClose={() => close("b")}>
        {b && <BookView id={b} inSheet onDone={() => close("b")} />}
      </Sheet>
      <Sheet
        open={!!r}
        onClose={() => close("r")}
        action={r ? <Link href={`/rezepte/${r}/bearbeiten`} className="btn-plain t-sub pressable font-semibold">Bearbeiten</Link> : null}
      >
        {r && <RecipeView id={r} inSheet onDone={() => close("r")} />}
      </Sheet>
    </>
  );
}
