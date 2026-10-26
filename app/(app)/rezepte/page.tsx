"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useApp } from "@/components/app-data";
import { IconClock, IconNote, IconPlus, IconSearch } from "@/components/icons";
import { CollectionSwitch } from "@/components/collection-switch";
import { DetailLink } from "@/components/detail-nav";
import { PageHeader } from "@/components/nav";
import { matchesQuery } from "@/components/recipe-picker";
import { Sheet } from "@/components/sheet";
import { DIET_LABEL, DietIcon, Empty, RecipeImage, lastCookedLabel } from "@/components/ui";
import type { Diet, Recipe } from "@/lib/types";

type Sort = "az" | "zuletzt" | "laengst" | "haeufig" | "neu";
const SORTS: { value: Sort; label: string }[] = [
  { value: "az", label: "A–Z" },
  { value: "zuletzt", label: "Zuletzt gekocht" },
  { value: "laengst", label: "Am längsten nicht gekocht" },
  { value: "haeufig", label: "Am häufigsten gekocht" },
  { value: "neu", label: "Neu hinzugefügt" },
];
const TIMES = [20, 30, 60];

interface Filters {
  category: string | null;
  tag: string | null;
  diet: Diet | null;
  maxTime: number | null;
  cookbook: string | null;
  never: boolean;
  notWeeks: number | null;
}
const EMPTY: Filters = { category: null, tag: null, diet: null, maxTime: null, cookbook: null, never: false, notWeeks: null };

export default function RecipesPage() {
  const { sb, recipes, stats, cookbooks, cookbooksById } = useApp();
  const [q, setQ] = useState("");
  const [server, setServer] = useState<{ term: string; ids: Set<string> } | null>(null);
  const serverHits = server && server.term === q.trim() ? server.ids : null;
  const [filters, setFilters] = useState<Filters>(EMPTY);
  const [sort, setSort] = useState<Sort>("az");
  const [filterOpen, setFilterOpen] = useState(false);

  // Volltextsuche (deutsch, Trigramm) – ergänzt die sofortige lokale Suche
  useEffect(() => {
    const term = q.trim();
    if (term.length < 2) return;
    const t = setTimeout(async () => {
      const { data } = await sb.rpc("ep_search_recipes", { q: term });
      setServer({ term, ids: new Set(((data ?? []) as { id: string }[]).map((d) => d.id)) });
    }, 180);
    return () => clearTimeout(t);
  }, [q, sb]);

  const categories = useMemo(() => [...new Set(recipes.flatMap((r) => r.categories))].sort((a, b) => a.localeCompare(b, "de")), [recipes]);
  const tags = useMemo(() => [...new Set(recipes.flatMap((r) => r.tags))].sort(), [recipes]);

  const list = useMemo(() => {
    const f = filters;
    const l = recipes.filter((r) => {
      if (q.trim() && !(matchesQuery(r, q) || serverHits?.has(r.id))) return false;
      if (f.category && !r.categories.includes(f.category)) return false;
      if (f.tag && !r.tags.includes(f.tag)) return false;
      if (f.diet && r.diet !== f.diet) return false;
      if (f.maxTime && !(r.time_min !== null && r.time_min <= f.maxTime)) return false;
      if (f.cookbook && r.cookbook_id !== f.cookbook) return false;
      const s = stats.get(r.id);
      if (f.never && s) return false;
      if (f.notWeeks && s && s.days_since < f.notWeeks * 7) return false;
      return true;
    });
    const days = (r: Recipe) => stats.get(r.id)?.days_since ?? Number.POSITIVE_INFINITY;
    const cmp: Record<Sort, (a: Recipe, b: Recipe) => number> = {
      az: (a, b) => a.title.localeCompare(b.title, "de"),
      zuletzt: (a, b) => days(a) - days(b),
      laengst: (a, b) => days(b) - days(a),
      haeufig: (a, b) => (stats.get(b.id)?.times_cooked ?? 0) - (stats.get(a.id)?.times_cooked ?? 0),
      neu: (a, b) => b.created_at.localeCompare(a.created_at),
    };
    return l.sort((a, b) => cmp[sort](a, b) || a.title.localeCompare(b.title, "de"));
  }, [recipes, q, serverHits, filters, sort, stats]);

  const active = Object.entries(filters).filter(([, v]) => v !== null && v !== false).length;
  const set = (patch: Partial<Filters>) => setFilters((f) => ({ ...f, ...patch }));

  return (
    <>
      <PageHeader
        title="Rezepte"
        width="wide"
        tabRoot
        subtitle={`${recipes.length} Rezepte in der Sammlung`}
      >
        <CollectionSwitch active="rezepte" />
        <div className="lg:mt-3 lg:flex lg:items-center lg:gap-3">
          <label className="relative mt-3 block lg:mt-0 lg:w-80 lg:shrink-0">
            <span className="absolute top-1/2 left-3 -translate-y-1/2" style={{ color: "var(--label-3)" }}><IconSearch size={18} /></span>
            <input className="input pl-9" type="search" placeholder="Titel, Zutat, Tag …" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Rezepte durchsuchen" />
          </label>
          <div className="scroll-x -mx-4 mt-3 flex gap-2 px-4 lg:mx-0 lg:mt-0 lg:flex-wrap lg:px-0">
            <button className="chip pressable" data-on={active > 0} onClick={() => setFilterOpen(true)}>
              Filter{active ? ` · ${active}` : ""}
            </button>
            {(["vegetarisch", "fisch", "fleisch"] as Diet[]).map((d) => (
              <button key={d} className="chip pressable" data-on={filters.diet === d} onClick={() => set({ diet: filters.diet === d ? null : d })}>
                <DietIcon diet={d} size={15} /> {DIET_LABEL[d]}
              </button>
            ))}
            {TIMES.map((t) => (
              <button key={t} className="chip pressable" data-on={filters.maxTime === t} onClick={() => set({ maxTime: filters.maxTime === t ? null : t })}>
                ≤ {t} Min.
              </button>
            ))}
            <button className="chip pressable" data-on={filters.never} onClick={() => set({ never: !filters.never })}>Nie gekocht</button>
          </div>
        </div>
        <div className="mt-3 flex items-center justify-between">
          <span className="t-footnote" style={{ color: "var(--label-2)" }}>{list.length} Treffer</span>
          <select className="t-footnote w-auto appearance-none rounded-lg bg-transparent py-1 text-right font-medium" style={{ color: "var(--accent)" }} value={sort} onChange={(e) => setSort(e.target.value as Sort)} aria-label="Sortierung">
            {SORTS.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
          </select>
        </div>
      </PageHeader>

      <div className="page-wide mt-2 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 lg:gap-4 xl:grid-cols-5 2xl:grid-cols-6">
        {/* Immer zuerst: schnell ein neues Rezept anlegen – so groß wie die Rezeptkacheln */}
        <Link href="/rezepte/neu" className="card pressable flex flex-col overflow-hidden" aria-label="Neues Rezept">
          <span className="flex aspect-[4/3] w-full items-center justify-center" style={{ background: "var(--accent-soft)", color: "var(--accent)" }}>
            <IconPlus size={36} strokeWidth={2} />
          </span>
          <span className="flex flex-1 flex-col gap-1 p-3">
            <span className="t-sub font-semibold leading-snug">Neues Rezept</span>
            <span className="t-caption" style={{ color: "var(--label-2)" }}>Von Hand, aus einem Link oder Foto</span>
          </span>
        </Link>
        {list.map((r) => {
          const book = r.cookbook_id ? cookbooksById.get(r.cookbook_id) : null;
          return (
            <DetailLink key={r.id} kind="r" id={r.id} className="card pressable flex flex-col overflow-hidden">
              <RecipeImage recipe={r} className="aspect-[4/3] w-full text-3xl" rounded={0} />
              <div className="flex flex-1 flex-col gap-1 p-3">
                <h3 className="t-sub line-clamp-2 font-semibold leading-snug">{r.title}</h3>
                <div className="t-caption flex flex-wrap items-center gap-x-2 gap-y-0.5" style={{ color: "var(--label-2)" }}>
                  {r.diet && <span className={`tag tag-${r.diet}`}><DietIcon diet={r.diet} size={11} />{DIET_LABEL[r.diet]}</span>}
                  {r.time_min !== null && <span className="flex items-center gap-0.5"><IconClock size={12} />{r.time_min} Min.</span>}
                  {r.servings && <span>{r.servings} Port.</span>}
                </div>
                {book && (
                  <p className="t-caption truncate" style={{ color: "var(--accent)" }}>
                    {book.title}{r.cookbook_page ? `, S. ${r.cookbook_page}` : ""}{!r.cookbook_link_confirmed ? " · zu bestätigen" : ""}
                  </p>
                )}
                <p className="t-caption mt-auto flex items-center gap-1.5 pt-1" style={{ color: "var(--label-2)" }}>
                  <span className="min-w-0 flex-1 truncate">{lastCookedLabel(stats.get(r.id))}</span>
                  {(r.ep_recipe_notes?.[0]?.count ?? 0) > 0 && (
                    <span className="flex shrink-0 items-center gap-0.5" aria-label={`${r.ep_recipe_notes![0].count} Notizen`}>
                      <IconNote size={13} /> {r.ep_recipe_notes![0].count}
                    </span>
                  )}
                </p>
              </div>
            </DetailLink>
          );
        })}
      </div>
      {!list.length && <Empty title="Keine Rezepte gefunden" text="Suche oder Filter anpassen." action={active ? <button className="btn btn-tinted pressable" onClick={() => setFilters(EMPTY)}>Filter zurücksetzen</button> : undefined} />}

      <Sheet open={filterOpen} onClose={() => setFilterOpen(false)} title="Filter" action={<button className="btn-plain t-sub pressable font-semibold" onClick={() => setFilters(EMPTY)}>Zurücksetzen</button>}>
        <FilterBlock label="Kategorie">
          {categories.map((c) => <button key={c} className="chip pressable" data-on={filters.category === c} onClick={() => set({ category: filters.category === c ? null : c })}>{c}</button>)}
        </FilterBlock>
        <FilterBlock label="Tags">
          {tags.map((t) => <button key={t} className="chip pressable" data-on={filters.tag === t} onClick={() => set({ tag: filters.tag === t ? null : t })}>#{t}</button>)}
        </FilterBlock>
        <FilterBlock label="Zeit">
          {[...TIMES, null].map((t) => <button key={String(t)} className="chip pressable" data-on={filters.maxTime === t} onClick={() => set({ maxTime: t })}>{t ? `≤ ${t} Min.` : "egal"}</button>)}
        </FilterBlock>
        <FilterBlock label="Kochbuch">
          {cookbooks.filter((c) => recipes.some((r) => r.cookbook_id === c.id)).map((c) => (
            <button key={c.id} className="chip pressable" data-on={filters.cookbook === c.id} onClick={() => set({ cookbook: filters.cookbook === c.id ? null : c.id })}>{c.title}</button>
          ))}
        </FilterBlock>
        <FilterBlock label="Kochhistorie">
          <button className="chip pressable" data-on={filters.never} onClick={() => set({ never: !filters.never, notWeeks: null })}>nie gekocht</button>
          {[2, 4, 8, 12].map((w) => (
            <button key={w} className="chip pressable" data-on={filters.notWeeks === w} onClick={() => set({ notWeeks: filters.notWeeks === w ? null : w, never: false })}>nicht in den letzten {w} Wochen</button>
          ))}
        </FilterBlock>
        <button className="btn btn-primary pressable mt-6 w-full" onClick={() => setFilterOpen(false)}>{list.length} Rezepte anzeigen</button>
      </Sheet>
    </>
  );
}

function FilterBlock({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="mt-4">
      <p className="t-section mb-2">{label}</p>
      <div className="flex flex-wrap gap-2">{children}</div>
    </div>
  );
}
