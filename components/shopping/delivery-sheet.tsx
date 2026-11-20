"use client";

// Lieferdienst: offene Posten nacheinander im Shop suchen und in den Warenkorb legen.
// REWE und Knuspr bieten fremden Apps keinen Warenkorb-Zugriff; die Suche pro Posten
// funktioniert dagegen immer. Was schon im Warenkorb liegt, merkt sich das Gerät für
// genau diesen Listenstand.

import { useState } from "react";
import { Segmented } from "@/components/ui";
import { DELIVERY_SHOPS, shopSearchTerm, shopSearchUrl, type DeliveryShop } from "@/lib/delivery";
import { knusprLinks } from "@/lib/knuspr";

export interface DeliveryItem {
  key: string;
  text: string;
  name: string;
}

const storeKey = (shop: DeliveryShop, version: string) => `ep-delivery-${shop}-${version}`;

function readDone(shop: DeliveryShop, version: string): Set<string> {
  try {
    return new Set(JSON.parse(sessionStorage.getItem(storeKey(shop, version)) ?? "[]") as string[]);
  } catch {
    return new Set();
  }
}

export function DeliverySheetBody({
  items,
  version,
  knusprPrompt,
  initialShop = "rewe",
  onCopyPrompt,
}: {
  items: DeliveryItem[];
  version: string;
  knusprPrompt: string;
  initialShop?: DeliveryShop;
  onCopyPrompt: () => void;
}) {
  const [shop, setShop] = useState<DeliveryShop>(initialShop);
  const [done, setDone] = useState<Set<string>>(() => (typeof window === "undefined" ? new Set() : readDone(initialShop, version)));

  function switchShop(next: DeliveryShop) {
    setShop(next);
    setDone(readDone(next, version));
  }

  function mark(key: string, on: boolean) {
    setDone((cur) => {
      const next = new Set(cur);
      if (on) next.add(key);
      else next.delete(key);
      try {
        sessionStorage.setItem(storeKey(shop, version), JSON.stringify([...next]));
      } catch {
        // privater Modus: Haken gelten nur bis zum Schließen
      }
      return next;
    });
  }

  const info = DELIVERY_SHOPS[shop];
  const count = items.filter((i) => done.has(i.key)).length;

  return (
    <div className="pb-2">
      <Segmented
        label="Lieferdienst"
        value={shop}
        onChange={switchShop}
        options={[{ value: "rewe", label: "REWE" }, { value: "knuspr", label: "Knuspr" }]}
      />
      <p className="t-footnote mt-3" style={{ color: "var(--label-2)" }}>
        Tippe einen Posten an: Die {info.name}-Suche öffnet sich, du legst das passende Produkt in den Warenkorb.
        Bestellt und bezahlt wird bei {info.name}.
      </p>

      {shop === "knuspr" && (
        <details className="card mt-3 px-4 py-3">
          <summary className="t-sub cursor-pointer font-semibold">Schneller mit KI: alles auf einmal</summary>
          <p className="t-footnote mt-2" style={{ color: "var(--label-2)" }}>
            Mit dem Knuspr-Konnektor in Claude oder ChatGPT legt die KI alle Posten in deinen Warenkorb. Einmalig dort „Knuspr“ verbinden.
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            <a className="btn btn-gray pressable" href={knusprLinks(knusprPrompt).claude} target="_blank" rel="noopener">In Claude</a>
            <a className="btn btn-gray pressable" href={knusprLinks(knusprPrompt).chatgpt} target="_blank" rel="noopener">In ChatGPT</a>
            <button className="btn-plain t-sub pressable font-semibold" onClick={onCopyPrompt}>Auftrag kopieren</button>
          </div>
        </details>
      )}

      <p className="t-section mt-5 mb-2" aria-live="polite">
        {count} von {items.length} im Warenkorb
      </p>
      <ul className="group">
        {items.map((item) => {
          const isDone = done.has(item.key);
          const term = shopSearchTerm(item.name);
          return (
            <li key={item.key} className="row">
              <button
                className="pressable flex h-7 w-7 shrink-0 items-center justify-center rounded-full"
                style={{ background: isDone ? "var(--accent)" : "transparent", boxShadow: isDone ? undefined : "inset 0 0 0 1.5px var(--label-3)", color: "var(--on-accent)" }}
                aria-label={isDone ? `${item.text}: aus dem Warenkorb nehmen` : `${item.text}: als im Warenkorb markieren`}
                aria-pressed={isDone}
                onClick={() => mark(item.key, !isDone)}
              >
                {isDone && "✓"}
              </button>
              <a
                className="pressable min-w-0 flex-1"
                href={shopSearchUrl(shop, item.name)}
                target="_blank"
                rel="noopener"
                onClick={() => mark(item.key, true)}
              >
                <span className="t-sub block truncate" style={isDone ? { color: "var(--label-3)", textDecoration: "line-through" } : undefined}>
                  {item.text}
                </span>
                {term !== item.text && (
                  <span className="t-caption block truncate" style={{ color: "var(--label-2)" }}>Suche: {term}</span>
                )}
              </a>
              <span aria-hidden style={{ color: "var(--label-3)" }}>↗</span>
            </li>
          );
        })}
      </ul>

      <a className="btn btn-primary pressable mt-5 w-full" href={info.home} target="_blank" rel="noopener">
        Zum {info.name}-Warenkorb
      </a>
    </div>
  );
}
