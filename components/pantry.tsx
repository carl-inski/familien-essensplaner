"use client";

// Vorrat des Haushalts (immer zu Hause, z. B. Salz und Pfeffer): laden, ergänzen, entfernen.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { IconClose, IconHome } from "./icons";
import { Section } from "./ui";
import { useApp } from "./app-data";
import { pantryParts } from "@/lib/pantry";

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
    setItems(((data ?? []) as { name: string }[]).map((r) => r.name));
  }, [sb]);

  useEffect(() => {
    let alive = true;
    sb.from("ep_pantry")
      .select("name")
      .order("name")
      .then(({ data }) => alive && setItems(((data ?? []) as { name: string }[]).map((r) => r.name)));
    return () => {
      alive = false;
    };
  }, [sb]);

  /** Merkt eine Zutat (bei Sammelzeilen jeden Teil) als immer zu Hause; liefert die Einträge zurück */
  const add = useCallback(
    async (ingredient: string) => {
      const names = pantryParts(ingredient);
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
              <IconHome size={14} /> {n.charAt(0).toUpperCase() + n.slice(1)}
              <button className="pressable -mr-1 ml-0.5 p-0.5" aria-label={`${n} entfernen`} onClick={() => void pantry.remove([n])}><IconClose size={13} /></button>
            </span>
          ))}
          {!pantry.items.length && <span className="t-sub" style={{ color: "var(--label-2)" }}>Noch nichts eingetragen.</span>}
        </div>
        <form
          className="mt-3 flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (draft.trim()) void pantry.add(draft).then(() => setDraft(""));
          }}
        >
          <input className="input flex-1" placeholder="z. B. Olivenöl, Zucker" value={draft} onChange={(e) => setDraft(e.target.value)} aria-label="Vorrat ergänzen" />
          <button className="btn btn-tinted pressable" type="submit" disabled={!draft.trim()}>Hinzufügen</button>
        </form>
      </div>
    </Section>
  );
}
