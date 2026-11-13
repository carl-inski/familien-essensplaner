"use client";

// Vorrat des Haushalts (immer zu Hause, z. B. Salz und Pfeffer): laden, ergänzen, entfernen.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { IconClose, IconHome } from "./icons";
import { Section } from "./ui";
import { useApp } from "./app-data";
import { useShopping } from "./shopping/use-shopping";
import { useToast } from "./toast";
import { formatStampDE } from "@/lib/dates";
import { isValidEntry, pantryEntriesFromInput, pantryLabel } from "@/lib/pantry";
import { STOCK_DAYS, shoppingState, stockEntryFromText } from "@/lib/shopping";
import { inBackground } from "@/lib/background";

export function usePantry() {
  const { sb, household } = useApp();
  const [items, setItems] = useState<string[]>([]);
  // Schreibvorgänge nacheinander, sonst überholt ein Löschen das vorherige Einfügen
  const queue = useRef<Promise<unknown>>(Promise.resolve());
  const serial = useCallback(<T,>(fn: () => PromiseLike<T>): Promise<T> => {
    const run = queue.current.then(fn);
    queue.current = run.catch(() => undefined);
    return run;
  }, []);

  const reload = useCallback(async () => {
    const { data } = await sb.from("ep_pantry").select("name").order("name");
    setItems(((data ?? []) as { name: string }[]).map((r) => r.name).filter(isValidEntry));
  }, [sb]);

  useEffect(() => {
    let alive = true;
    sb.from("ep_pantry")
      .select("name")
      .order("name")
      .then(({ data }) => {
        const names = ((data ?? []) as { name: string }[]).map((r) => r.name);
        // Bruchstücke wie „-unterschenkel“ aus einer älteren Version still entfernen
        const broken = names.filter((n) => !isValidEntry(n));
        if (broken.length) inBackground(sb.from("ep_pantry").delete().eq("household_id", household.id).in("name", broken), "Vorrat aufräumen");
        if (alive) setItems(names.filter(isValidEntry));
      });
    return () => {
      alive = false;
    };
  }, [sb, household.id]);

  /** Merkt Vorratseinträge (siehe pantryEntriesToAdd / pantryEntriesFromInput) */
  const add = useCallback(
    async (entries: string[]) => {
      const names = [...new Set(entries.map((e) => e.trim()).filter(Boolean))];
      if (!names.length) return [];
      setItems((cur) => [...new Set([...cur, ...names])].sort((a, b) => a.localeCompare(b, "de")));
      const { error } = await serial(() => sb.from("ep_pantry").upsert(names.map((name) => ({ household_id: household.id, name })), { onConflict: "household_id,name" }));
      if (error) await reload();
      return error ? [] : names;
    },
    [sb, household.id, reload, serial],
  );

  const remove = useCallback(
    async (names: string[]) => {
      setItems((cur) => cur.filter((n) => !names.includes(n)));
      const { error } = await serial(() => sb.from("ep_pantry").delete().eq("household_id", household.id).in("name", names));
      if (error) await reload();
    },
    [sb, household.id, reload, serial],
  );

  const set = useMemo(() => new Set(items), [items]);
  return { items, set, add, remove };
}

export function PantrySection() {
  const pantry = usePantry();
  const [draft, setDraft] = useState("");
  return (
    <Section title="Immer zu Hause" footer="Steht nie auf der Einkaufsliste. Auf der Liste fügst du Zutaten mit dem Häuschen hinzu.">
      <div className="card px-3 py-3">
        <div className="flex flex-wrap gap-2">
          {pantry.items.map((n) => (
            <span key={n} className="chip">
              <IconHome size={14} /> {pantryLabel(n)}
              <button className="pressable -mr-1 ml-0.5 p-0.5" aria-label={`${n} entfernen`} onClick={() => void pantry.remove([n])}><IconClose size={13} /></button>
            </span>
          ))}
          {!pantry.items.length && <span className="t-sub" style={{ color: "var(--label-2)" }}>Noch nichts eingetragen.</span>}
        </div>
        <form
          className="mt-3 flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (draft.trim()) void pantry.add(pantryEntriesFromInput(draft)).then(() => setDraft(""));
          }}
        >
          <input className="input flex-1" placeholder="z. B. Olivenöl, Zucker" value={draft} onChange={(e) => setDraft(e.target.value)} aria-label="Vorrat ergänzen" />
          <button className="btn btn-tinted pressable" type="submit" disabled={!draft.trim()}>Hinzufügen</button>
        </form>
      </div>
    </Section>
  );
}

/**
 * Vorrat Stufe 1: was gerade zu Hause ist und für kein Gericht verplant.
 * Entsteht von selbst (Gericht fällt nach dem Einkauf aus, weniger Esser, „Noch da“ auf
 * der Liste) oder wird hier von Hand eingetragen. Zählt beim nächsten passenden Gericht mit.
 */
export function StockSection() {
  const { household, me, recipesById, members, today } = useApp();
  const pantry = usePantry();
  const toast = useToast();
  const { plan, attendance, purchases, loaded, buy, undo } = useShopping();
  const [draft, setDraft] = useState("");
  const [now] = useState(() => new Date().toISOString());
  const stock = useMemo(
    () => (loaded ? shoppingState({ plan, recipes: recipesById, members, attendance, pantry: pantry.set, purchases, today, now }).stock : []),
    [loaded, plan, recipesById, members, attendance, pantry.set, purchases, today, now],
  );

  function add() {
    const rows = draft
      .split(/[,\n]/)
      .map((t) => stockEntryFromText(t, household.id, me.id, () => crypto.randomUUID()))
      .filter((r) => r !== null);
    if (!rows.length) return;
    buy(rows);
    setDraft("");
  }

  function usedUp(ids: string[], name: string) {
    const rows = purchases.filter((p) => ids.includes(p.id));
    undo(rows.map((p) => p.client_id));
    toast({
      text: `${name}: aufgebraucht`,
      action: { label: "Rückgängig", run: () => void buy(rows.map(({ household_id, meal_plan_id, item_key, name, amount, unit, bought_by, source }) => ({ client_id: crypto.randomUUID(), household_id, meal_plan_id, item_key, name, amount, unit, bought_by, source }))) },
    });
  }

  return (
    <Section title="Vorrat · gerade da" footer={`Wird beim Einkauf abgezogen, sobald ein Gericht es braucht. Nach ${STOCK_DAYS} Tagen verschwindet ein Eintrag von selbst.`}>
      <div className="card px-3 py-3">
        {stock.length > 0 ? (
          <ul className="flex flex-col">
            {stock.map((x) => (
              <li key={x.key} className="flex items-center gap-2 py-1.5">
                <span className="min-w-0 flex-1">
                  <span className="t-sub block">{x.text}</span>
                  <span className="t-caption block" style={{ color: "var(--label-2)" }}>seit {formatStampDE(x.since)}</span>
                </span>
                <button className="btn-plain t-footnote pressable font-semibold" onClick={() => usedUp(x.purchaseIds, x.name)} aria-label={`${x.name} ist aufgebraucht`}>Aufgebraucht</button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="t-sub" style={{ color: "var(--label-2)" }}>{loaded ? "Nichts eingetragen. Was nach dem Einkauf übrig bleibt, landet von selbst hier." : "Lädt …"}</p>
        )}
        <form
          className="mt-3 flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            add();
          }}
        >
          <input className="input flex-1" placeholder="z. B. 500 g Reis, Eier" value={draft} onChange={(e) => setDraft(e.target.value)} aria-label="Vorrat eintragen" />
          <button className="btn btn-tinted pressable" type="submit" disabled={!draft.trim()}>Eintragen</button>
        </form>
      </div>
    </Section>
  );
}
