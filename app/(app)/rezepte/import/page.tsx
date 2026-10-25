"use client";

import { useState } from "react";
import { useApp } from "@/components/app-data";
import { IconDownload, IconUpload } from "@/components/icons";
import { PageHeader } from "@/components/nav";
import { useToast } from "@/components/toast";
import { DietIcon, Section, downloadText } from "@/components/ui";
import { collectionToMarkdown, parseRecipeCollection, type RecipeDraft } from "@/lib/markdown";
import { draftToIngredientRows, normalizeTitle, recipeRowFor, recipeToDraft, resolveCookbook, type CookbookChoice } from "@/lib/recipe-draft";

type Choice = "neu" | "ueberspringen" | "ueberschreiben" | "kopie";

interface Item {
  draft: RecipeDraft;
  duplicateId: string | null;
  choice: Choice;
  book: CookbookChoice | null;
}

export default function ImportExportPage() {
  const { sb, household, recipes, cookbooks, cookbooksById, reloadRecipes, reloadCookbooks } = useApp();
  const toast = useToast();
  const [items, setItems] = useState<Item[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [paste, setPaste] = useState("");

  function analyse(text: string) {
    const drafts = parseRecipeCollection(text);
    if (!drafts.length) return toast({ text: "Keine Rezepte im erwarteten Format gefunden.", tone: "error" });
    setItems(
      drafts.map((d) => {
        const dup = recipes.find((r) => normalizeTitle(r.title) === normalizeTitle(d.title));
        return { draft: d, duplicateId: dup?.id ?? null, choice: dup ? "ueberspringen" : "neu", book: resolveCookbook(d, cookbooks) };
      }),
    );
  }

  async function runImport() {
    if (!items) return;
    setBusy(true);
    let done = 0;
    const created = new Map<string, string>();
    for (const it of items) {
      if (it.choice === "ueberspringen") continue;
      let cookbookId: string | null = it.book?.match?.id ?? null;
      if (it.book?.create) {
        const key = it.book.create.toLowerCase();
        if (!created.has(key)) {
          const { data } = await sb.from("ep_cookbooks").insert({ household_id: household.id, title: it.book.create, notes: "Beim Import angelegt – zu bestätigen" }).select("id").single();
          if (data) created.set(key, (data as { id: string }).id);
        }
        cookbookId = created.get(key) ?? null;
      }
      const { image_url, ...rest } = recipeRowFor(it.draft, cookbookId, !!it.book?.confirmed);
      const row = {
        ...rest,
        ...(image_url ? { image_url } : {}),
        title: it.choice === "kopie" ? `${it.draft.title} (Kopie)` : it.draft.title,
        household_id: household.id,
      };
      const res =
        it.choice === "ueberschreiben" && it.duplicateId
          ? await sb.from("ep_recipes").update(row).eq("id", it.duplicateId).select("id").single()
          : await sb.from("ep_recipes").insert(row).select("id").single();
      if (res.error) {
        toast({ text: `${it.draft.title}: ${res.error.message}`, tone: "error" });
        continue;
      }
      const id = (res.data as { id: string }).id;
      await sb.from("ep_recipe_ingredients").delete().eq("recipe_id", id);
      const ingRows = draftToIngredientRows(it.draft, id);
      if (ingRows.length) await sb.from("ep_recipe_ingredients").insert(ingRows);
      done++;
    }
    await Promise.all([reloadRecipes(), reloadCookbooks()]);
    setBusy(false);
    setItems(null);
    setPaste("");
    toast({ text: `${done} Rezept${done === 1 ? "" : "e"} importiert` });
  }

  function exportAll() {
    const md = collectionToMarkdown(recipes.map((r) => recipeToDraft(r, cookbooksById)));
    downloadText("rezeptsammlung.md", md);
  }

  const setChoice = (i: number, choice: Choice) => setItems((l) => l!.map((x, j) => (j === i ? { ...x, choice } : x)));

  return (
    <>
      <PageHeader title="Import & Export" icon="📥" back={{ href: "/haushalt", label: "Profil" }} />
      <div className="mx-auto max-w-2xl px-4">
        <Section title="Export" footer="Gleiches Format wie die Rezeptsammlung inkl. Inhaltsverzeichnis – lässt sich wieder importieren.">
          <button className="btn btn-tinted pressable w-full" onClick={exportAll}><IconDownload size={18} /> Ganze Sammlung als Markdown ({recipes.length})</button>
        </Section>

        <Section title="Import" footer="Ein Rezept pro ## Überschrift, getrennt durch ---. Zutaten als Tabelle, Schritte nummeriert.">
          <div className="flex flex-col gap-2">
            <label className="btn btn-gray pressable w-full">
              <IconUpload size={18} /> Markdown-Datei wählen
              <input type="file" accept=".md,.markdown,text/markdown,text/plain" className="hidden" onChange={async (e) => { const f = e.target.files?.[0]; if (f) analyse(await f.text()); e.target.value = ""; }} />
            </label>
            <textarea className="input font-mono text-sm" rows={5} placeholder="… oder Markdown hier einfügen" value={paste} onChange={(e) => setPaste(e.target.value)} />
            {paste.trim() && <button className="btn btn-tinted pressable" onClick={() => analyse(paste)}>Vorschau</button>}
          </div>
        </Section>

        {items && (
          <Section title={`Vorschau · ${items.length} Rezepte`}>
            <ul className="flex flex-col gap-2">
              {items.map((it, i) => (
                <li key={i} className="card px-4 py-3">
                  <div className="flex items-start gap-2">
                    <div className="min-w-0 flex-1">
                      <p className="t-sub flex items-center gap-1.5 font-semibold"><span className="truncate">{it.draft.title}</span><DietIcon diet={it.draft.diet} size={14} /></p>
                      <p className="t-footnote" style={{ color: "var(--label-2)" }}>
                        {it.draft.ingredients.length} Zutaten · {it.draft.steps.length} Schritte
                        {it.draft.servings ? ` · ${it.draft.servings} Port.` : ""}
                        {it.draft.nutrition ? " · Nährwerte" : ""}
                      </p>
                      {it.book && (
                        <p className="t-footnote" style={{ color: "var(--accent)" }}>
                          {it.book.create ? `neues Buch „${it.book.create}“ (zu bestätigen)` : `→ ${it.book.match!.title}${it.book.confirmed ? "" : " (Vorschlag, zu bestätigen)"}`}
                        </p>
                      )}
                    </div>
                    {it.duplicateId && <span className="badge shrink-0" style={{ background: "var(--yellow-soft)" }}>Duplikat</span>}
                  </div>
                  {it.duplicateId ? (
                    <div className="segmented mt-2">
                      {([["ueberspringen", "Überspringen"], ["ueberschreiben", "Überschreiben"], ["kopie", "Als Kopie"]] as [Choice, string][]).map(([v, l]) => (
                        <button key={v} data-on={it.choice === v} className="pressable" onClick={() => setChoice(i, v)}>{l}</button>
                      ))}
                    </div>
                  ) : (
                    <label className="t-footnote mt-2 flex items-center gap-2">
                      <input type="checkbox" checked={it.choice === "neu"} onChange={(e) => setChoice(i, e.target.checked ? "neu" : "ueberspringen")} /> importieren
                    </label>
                  )}
                </li>
              ))}
            </ul>
            <button className="btn btn-primary pressable mt-4 w-full" disabled={busy} onClick={runImport}>
              {busy ? "Importiert …" : `${items.filter((x) => x.choice !== "ueberspringen").length} Rezepte importieren`}
            </button>
          </Section>
        )}
      </div>
    </>
  );
}
