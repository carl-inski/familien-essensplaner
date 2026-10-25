"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useApp } from "@/components/app-data";
import { IconCalendar } from "@/components/icons";
import { PageHeader } from "@/components/nav";
import { PlanSheet } from "@/components/plan-sheet";
import { DIET_LABEL, DietIcon, Empty, Section } from "@/components/ui";
import { formatDateDE } from "@/lib/dates";
import type { Diet, Recipe } from "@/lib/types";

export default function LongNotEatenPage() {
  const { recipes, stats, cookbooks, cookbooksById } = useApp();
  const [diet, setDiet] = useState<Diet | null>(null);
  const [book, setBook] = useState<string | null>(null);
  const [planFor, setPlanFor] = useState<Recipe | null>(null);

  const filtered = useMemo(() => recipes.filter((r) => (!diet || r.diet === diet) && (!book || r.cookbook_id === book)), [recipes, diet, book]);
  const cooked = filtered.filter((r) => stats.has(r.id)).sort((a, b) => stats.get(b.id)!.days_since - stats.get(a.id)!.days_since);
  const never = filtered.filter((r) => !stats.has(r.id));

  const row = (r: Recipe) => {
    const s = stats.get(r.id);
    const b = r.cookbook_id ? cookbooksById.get(r.cookbook_id) : null;
    return (
      <li key={r.id} className="row">
        <Link href={`/rezepte/${r.id}`} className="min-w-0 flex-1">
          <span className="t-sub flex items-center gap-1.5 font-medium"><span className="truncate">{r.title}</span><DietIcon diet={r.diet} size={14} /></span>
          <span className="t-footnote block truncate" style={{ color: "var(--label-2)" }}>
            {s ? `${formatDateDE(s.last_cooked_on)} · ${s.times_cooked}×` : b ? b.title : "noch nie gekocht"}
          </span>
        </Link>
        {s && <span className="t-headline shrink-0 tabular-nums" style={{ color: s.days_since > 60 ? "var(--accent)" : "var(--label-2)" }}>{s.days_since} T.</span>}
        <button className="pressable shrink-0 p-2" style={{ color: "var(--accent)" }} aria-label={`${r.title} einplanen`} onClick={() => setPlanFor(r)}><IconCalendar size={20} /></button>
      </li>
    );
  };

  return (
    <>
      <PageHeader title="Lange nicht gegessen" back={{ href: "/haushalt", label: "Profil" }}>
        <div className="scroll-x -mx-4 mt-3 flex gap-2 px-4">
          {(["vegetarisch", "fisch", "fleisch"] as Diet[]).map((d) => (
            <button key={d} className="chip pressable" data-on={diet === d} onClick={() => setDiet(diet === d ? null : d)}><DietIcon diet={d} size={15} /> {DIET_LABEL[d]}</button>
          ))}
          <select className="chip" value={book ?? ""} onChange={(e) => setBook(e.target.value || null)} aria-label="Kochbuch">
            <option value="">Alle Bücher</option>
            {cookbooks.map((c) => <option key={c.id} value={c.id}>{c.title}</option>)}
          </select>
        </div>
      </PageHeader>
      <div className="page lg:[&>*]:max-w-3xl">
        <Section title="Zuletzt gekocht · Tage seitdem">
          {cooked.length ? <ul className="group">{cooked.map(row)}</ul> : <Empty title="Noch keine Kochhistorie" text="Markiere Gerichte im Wochenplan als „gekocht ✓“ oder trage sie auf der Rezeptseite nach." />}
        </Section>
        <Section title={`Noch nie gekocht · ${never.length}`}>
          <ul className="group">{never.map(row)}</ul>
        </Section>
      </div>
      <PlanSheet recipe={planFor} onClose={() => setPlanFor(null)} />
    </>
  );
}
