"use client";

import { useMemo, useState } from "react";
import { useApp } from "./app-data";
import { IconSearch } from "./icons";
import { Sheet } from "./sheet";
import { DietIcon, RecipeImage, Segmented, lastCookedLabel } from "./ui";
import type { Recipe } from "@/lib/types";

type Tab = "alle" | "lange" | "regal";

export function matchesQuery(r: Recipe, q: string): boolean {
  const s = q.trim().toLowerCase();
  if (!s) return true;
  return (
    r.title.toLowerCase().includes(s) ||
    (r.subtitle ?? "").toLowerCase().includes(s) ||
    r.tags.some((t) => t.includes(s)) ||
    r.categories.some((c) => c.toLowerCase().includes(s)) ||
    (r.ep_recipe_ingredients ?? []).some((i) => i.name.toLowerCase().includes(s))
  );
}

export function RecipePicker({ open, onClose, onPick, title = "Gericht wählen" }: { open: boolean; onClose: () => void; onPick: (r: Recipe) => void; title?: string }) {
  const { recipes, stats, cookbooksById } = useApp();
  const [q, setQ] = useState("");
  const [tab, setTab] = useState<Tab>("alle");

  const list = useMemo(() => {
    let l = recipes.filter((r) => matchesQuery(r, q));
    if (tab === "regal") l = l.filter((r) => r.cookbook_id);
    if (tab === "lange") {
      l = [...l].sort((a, b) => {
        const da = stats.get(a.id)?.days_since ?? Infinity;
        const db = stats.get(b.id)?.days_since ?? Infinity;
        return db - da;
      });
    }
    return l;
  }, [recipes, q, tab, stats]);

  return (
    <Sheet open={open} onClose={onClose} title={title}>
      <div className="sticky top-0 z-10 -mx-4 flex flex-col gap-2 px-4 pb-3" style={{ background: "inherit" }}>
        <label className="relative block">
          <span className="absolute top-1/2 left-3 -translate-y-1/2" style={{ color: "var(--label-3)" }}>
            <IconSearch size={18} />
          </span>
          <input className="input pl-9" placeholder="Rezept oder Zutat suchen" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Rezept suchen" />
        </label>
        <Segmented
          label="Auswahl"
          value={tab}
          onChange={setTab}
          options={[
            { value: "alle", label: "Alle" },
            { value: "lange", label: "Lange nicht" },
            { value: "regal", label: "Aus dem Regal" },
          ]}
        />
      </div>
      <ul className="group">
        {list.map((r) => {
          const book = r.cookbook_id ? cookbooksById.get(r.cookbook_id) : null;
          return (
            <li key={r.id} className="row-wrap">
              <button className="row pressable" onClick={() => onPick(r)}>
                <RecipeImage recipe={r} className="h-11 w-11 shrink-0 text-[13px]" rounded={9} />
                <span className="min-w-0 flex-1">
                  <span className="t-sub flex items-center gap-1.5 font-medium">
                    <span className="truncate">{r.title}</span>
                    <DietIcon diet={r.diet} size={14} />
                  </span>
                  <span className="t-footnote block truncate" style={{ color: "var(--label-2)" }}>
                    {book ? `aus deinem Regal · ${book.title} · ` : ""}
                    {lastCookedLabel(stats.get(r.id))}
                  </span>
                </span>
              </button>
            </li>
          );
        })}
        {!list.length && <li className="row t-sub" style={{ color: "var(--label-2)" }}>Nichts gefunden.</li>}
      </ul>
    </Sheet>
  );
}
