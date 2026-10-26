"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useApp } from "@/components/app-data";
import { BookCover, BookSheet } from "@/components/book";
import { DetailLink } from "@/components/detail-nav";
import { IconChevronRight, IconEdit, IconPlus, IconTrash } from "@/components/icons";
import { IconButton, PageHeader } from "@/components/nav";
import { RecipePicker } from "@/components/recipe-picker";
import { Sheet } from "@/components/sheet";
import { useToast } from "@/components/toast";
import { DietIcon, Empty, Section, lastCookedLabel } from "@/components/ui";
import { bookQuelle, presentCookbook } from "@/lib/medien";
import type { Diet, Recipe } from "@/lib/types";

/** Kochbuch-Ansicht: eigene Seite (Computer) oder Fenster über der aktuellen Ansicht (Handy) */
export function BookView({ id, inSheet = false, onDone }: { id: string; inSheet?: boolean; onDone?: () => void }) {
  const router = useRouter();
  const { cookbooksById, recipes, stats, sb, household, reloadRecipes, reloadCookbooks } = useApp();
  const toast = useToast();
  const stored = cookbooksById.get(id);
  const book = stored ? presentCookbook(stored) : undefined;
  const quelle = book ? bookQuelle(book) : null;
  const [editing, setEditing] = useState(false);
  const [linking, setLinking] = useState(false);
  const [pending, setPending] = useState<Recipe | null>(null);
  const [page, setPage] = useState("");
  const [refOpen, setRefOpen] = useState(false);
  const [refTitle, setRefTitle] = useState("");
  const [refDiet, setRefDiet] = useState<Diet>("vegetarisch");

  if (!book) return inSheet ? <Empty title="Buch nicht gefunden" /> : <Empty title="Buch nicht gefunden" action={<Link href="/regal" className="btn btn-tinted">Zum Regal</Link>} />;
  const linked = recipes.filter((r) => r.cookbook_id === book.id).sort((a, b) => (a.cookbook_page ?? 9999) - (b.cookbook_page ?? 9999) || a.title.localeCompare(b.title, "de"));

  async function link(r: Recipe, p: string) {
    const { error } = await sb.from("ep_recipes").update({ cookbook_id: book!.id, cookbook_page: p ? Number.parseInt(p, 10) : null, cookbook_link_confirmed: true }).eq("id", r.id);
    if (error) return toast({ text: error.message, tone: "error" });
    await reloadRecipes();
    setPending(null);
    setPage("");
  }

  async function confirmLink(r: Recipe) {
    await sb.from("ep_recipes").update({ cookbook_link_confirmed: true }).eq("id", r.id);
    await reloadRecipes();
    toast({ text: "Verknüpfung bestätigt" });
  }

  async function addReference() {
    if (!refTitle.trim()) return;
    const { error } = await sb.from("ep_recipes").insert({
      household_id: household.id,
      title: refTitle.trim(),
      diet: refDiet,
      cookbook_id: book!.id,
      cookbook_page: page ? Number.parseInt(page, 10) : null,
      categories: [],
      tags: [],
      servings: null,
    });
    if (error) return toast({ text: error.message, tone: "error" });
    await reloadRecipes();
    setRefOpen(false);
    setRefTitle("");
    setPage("");
    toast({ text: "Verweis angelegt – planbar, Zutaten später ergänzen" });
  }

  async function remove() {
    if (!confirm(`„${book!.title}“ aus dem Regal entfernen? Verknüpfte Rezepte bleiben erhalten.`)) return;
    await sb.from("ep_cookbooks").delete().eq("id", book!.id);
    await Promise.all([reloadCookbooks(), reloadRecipes()]);
    if (inSheet) onDone?.();
    else router.replace("/regal");
  }

  return (
    <>
      {!inSheet && <PageHeader title={book.title} back={{ href: "/regal", label: "Regal" }} trailing={<IconButton label="Bearbeiten" onClick={() => setEditing(true)}><IconEdit /></IconButton>} />}
      <div className={inSheet ? "" : "page lg:[&>*]:max-w-3xl"}>
        {inSheet && <h2 className="t-title-2 mb-3 px-1">{book.title}</h2>}
        <div className={`flex gap-4 ${inSheet ? "" : "mt-4"}`}>
          <BookCover book={book} className="h-44 w-30 shrink-0" />
          <dl className="t-sub flex flex-col gap-1.5">
            {book.authors.length > 0 && <div><dt className="t-caption" style={{ color: "var(--label-2)" }}>Autor</dt><dd>{book.authors.join(", ")}</dd></div>}
            {book.publisher && <div><dt className="t-caption" style={{ color: "var(--label-2)" }}>Verlag</dt><dd>{book.publisher}{book.year ? `, ${book.year}` : ""}</dd></div>}
            {book.isbn && (
              <div>
                <dt className="t-caption" style={{ color: "var(--label-2)" }}>ISBN</dt>
                <dd className="tabular-nums">{book.isbn}</dd>
                {quelle && <dd className="t-caption" style={{ color: "var(--label-2)" }}>{quelle}</dd>}
              </div>
            )}
            {book.notes && <div><dd className="t-footnote" style={{ color: "var(--label-2)" }}>{book.notes}</dd></div>}
            {!book.isbn && <button className="btn btn-tinted btn-sm pressable mt-1 self-start" onClick={() => setEditing(true)}>ISBN ergänzen</button>}
            {inSheet && book.isbn && <button className="btn btn-gray btn-sm pressable mt-1 self-start" onClick={() => setEditing(true)}><IconEdit size={15} /> Bearbeiten</button>}
          </dl>
        </div>

        <Section title={`Rezepte · ${linked.length}`}>
          <ul className="group">
            {linked.map((r) => (
              <li key={r.id} className="row">
                <DetailLink kind="r" id={r.id} className="pressable flex min-w-0 flex-1 items-center gap-3">
                  <span className="t-footnote w-10 shrink-0 tabular-nums" style={{ color: "var(--label-2)" }}>{r.cookbook_page ? `S. ${r.cookbook_page}` : "S. –"}</span>
                  <span className="min-w-0 flex-1">
                    <span className="t-sub flex items-center gap-1.5 font-medium"><span className="truncate">{r.title}</span><DietIcon diet={r.diet} size={14} /></span>
                    <span className="t-footnote block truncate" style={{ color: "var(--label-2)" }}>
                      {lastCookedLabel(stats.get(r.id))}{!(r.ep_recipe_ingredients ?? []).length ? " · nur Verweis" : ""}
                    </span>
                  </span>
                  <IconChevronRight size={16} style={{ color: "var(--label-3)" }} />
                </DetailLink>
                {!r.cookbook_link_confirmed && (
                  <button className="badge pressable shrink-0" style={{ background: "var(--yellow-soft)" }} onClick={() => confirmLink(r)} aria-label={`Verknüpfung von ${r.title} bestätigen`}>
                    zu bestätigen ✓
                  </button>
                )}
              </li>
            ))}
            {!linked.length && <li className="row t-sub" style={{ color: "var(--label-2)" }}>Noch keine Rezepte verknüpft</li>}
          </ul>
          <div className="mt-2 flex flex-wrap gap-2">
            <button className="btn btn-tinted btn-sm pressable" onClick={() => setLinking(true)}><IconPlus size={16} /> Rezept aus Sammlung</button>
            <button className="btn btn-gray btn-sm pressable" onClick={() => setRefOpen(true)}><IconPlus size={16} /> Nur Verweis (Titel + Seite)</button>
          </div>
        </Section>

        <Section>
          <button className="row card pressable" style={{ color: "var(--red)" }} onClick={remove}><IconTrash size={20} /> <span className="t-sub">Aus dem Regal entfernen</span></button>
        </Section>
      </div>

      <BookSheet open={editing} onClose={() => setEditing(false)} book={stored ? presentCookbook(stored) : book} />
      <RecipePicker open={linking} onClose={() => setLinking(false)} title="Rezept verknüpfen" onPick={(r) => { setLinking(false); setPending(r); setPage(r.cookbook_page?.toString() ?? ""); }} />
      <Sheet open={!!pending} onClose={() => setPending(null)} title="Seite angeben">
        <p className="t-sub mb-3">{pending?.title} → {book.title}</p>
        <input className="input" inputMode="numeric" placeholder="Seitenzahl (optional)" value={page} onChange={(e) => setPage(e.target.value.replace(/\D/g, ""))} />
        <button className="btn btn-primary pressable mt-4 w-full" onClick={() => pending && link(pending, page)}>Verknüpfen</button>
      </Sheet>
      <Sheet open={refOpen} onClose={() => setRefOpen(false)} title="Verweis anlegen">
        <div className="flex flex-col gap-2">
          <input className="input" placeholder="Rezepttitel" value={refTitle} onChange={(e) => setRefTitle(e.target.value)} />
          <input className="input" inputMode="numeric" placeholder="Seite" value={page} onChange={(e) => setPage(e.target.value.replace(/\D/g, ""))} />
          <div className="segmented">
            {(["vegetarisch", "fisch", "fleisch"] as Diet[]).map((d) => (
              <button key={d} data-on={refDiet === d} className="pressable" onClick={() => setRefDiet(d)}>{d === "vegetarisch" ? "Vegetarisch" : d === "fisch" ? "Fisch" : "Fleisch"}</button>
            ))}
          </div>
          <p className="t-footnote" style={{ color: "var(--label-2)" }}>Planbar, aber erst nach dem Ergänzen der Zutaten skalier- und nach Bring exportierbar.</p>
          <button className="btn btn-primary pressable mt-2" disabled={!refTitle.trim()} onClick={addReference}>Anlegen</button>
        </div>
      </Sheet>
    </>
  );
}
