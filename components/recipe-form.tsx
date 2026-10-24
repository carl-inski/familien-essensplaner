"use client";

import { useRouter } from "next/navigation";
import { useState, type ReactNode } from "react";
import { useApp } from "./app-data";
import { IconArrowDown, IconArrowUp, IconCamera, IconPlus, IconTrash } from "./icons";
import { PageHeader } from "./nav";
import { useToast } from "./toast";
import { DIET_LABEL, RecipeImage, Section, Segmented } from "./ui";
import { parseNutrition, parseTimeMinutes, slugifyTag, type RecipeDraft } from "@/lib/markdown";
import { dishPhoto } from "@/lib/medien";
import { parseAmount } from "@/lib/quantity";
import { matchCookbook, suggestCookbook } from "@/lib/recipe-draft";
import type { Diet, Recipe } from "@/lib/types";

interface IngRow { key: number; group_name: string; name: string; amount_text: string }

let keySeq = 0;
const nextKey = () => ++keySeq;

/**
 * Formular für neue und bestehende Rezepte. `draft` füllt ein neues Rezept vor
 * (Import aus Link, Foto oder vom Assistenten), `intro` steht über dem Formular.
 */
export function RecipeForm({ recipe, draft, notice, intro }: { recipe?: Recipe; draft?: RecipeDraft | null; notice?: string; intro?: ReactNode }) {
  const { sb, household, cookbooks, reloadRecipes } = useApp();
  const router = useRouter();
  const toast = useToast();
  const d = recipe ? null : draft ?? null;
  const draftBook = d?.cookbook ? matchCookbook(d.cookbook.title, cookbooks) : d ? suggestCookbook(d, cookbooks) : null;
  const [title, setTitle] = useState(recipe?.title ?? d?.title ?? "");
  const [subtitle, setSubtitle] = useState(recipe?.subtitle ?? d?.subtitle ?? "");
  const [source, setSource] = useState(recipe?.source ?? d?.source ?? "");
  const [categories, setCategories] = useState((recipe?.categories ?? d?.categories)?.join(" / ") ?? "");
  const [tags, setTags] = useState((recipe?.tags ?? d?.tags)?.join(", ") ?? "");
  const [diet, setDiet] = useState<Diet>(recipe?.diet ?? d?.diet ?? "vegetarisch");
  const [timeText, setTimeText] = useState(recipe?.time_text ?? d?.time_text ?? "");
  const [timeMin, setTimeMin] = useState((recipe?.time_min ?? d?.time_min)?.toString() ?? "");
  const [servings, setServings] = useState((recipe ? recipe.servings : d ? d.servings : 4)?.toString() ?? "");
  const [servingsText, setServingsText] = useState(recipe?.servings_text ?? d?.servings_text ?? "");
  const [cookbookId, setCookbookId] = useState(recipe?.cookbook_id ?? draftBook?.id ?? "");
  const [page, setPage] = useState((recipe?.cookbook_page ?? (draftBook ? d?.cookbook?.page : null))?.toString() ?? "");
  // Vom Import erkannte Bücher muss jemand bestätigen
  const [confirmed, setConfirmed] = useState(recipe?.cookbook_link_confirmed ?? !draftBook);
  const [tip, setTip] = useState(recipe?.tip ?? d?.tip ?? "");
  const [nutrition, setNutrition] = useState(((recipe?.nutrition ?? d?.nutrition) as { text?: string } | null)?.text ?? "");
  const [imageUrl, setImageUrl] = useState(recipe?.image_url ?? d?.image_url ?? "");
  const [ings, setIngs] = useState<IngRow[]>(
    recipe
      ? (recipe.ep_recipe_ingredients ?? []).map((i) => ({ key: nextKey(), group_name: i.group_name ?? "", name: i.name, amount_text: i.amount_text ?? "" }))
      : (d?.ingredients ?? []).map((i) => ({ key: nextKey(), group_name: i.group_name ?? "", name: i.name, amount_text: i.amount_text ?? "" })),
  );
  const [steps, setSteps] = useState<{ key: number; text: string }[]>((recipe?.steps ?? d?.steps ?? []).map((t) => ({ key: nextKey(), text: t })));
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  function move<T>(list: T[], i: number, d: number): T[] {
    const j = i + d;
    if (j < 0 || j >= list.length) return list;
    const copy = [...list];
    [copy[i], copy[j]] = [copy[j], copy[i]];
    return copy;
  }

  async function upload(file: File) {
    setUploading(true);
    const ext = file.name.split(".").pop()?.toLowerCase() || "jpg";
    const path = `${household.id}/${crypto.randomUUID()}.${ext}`;
    const { error } = await sb.storage.from("ep-images").upload(path, file, { contentType: file.type, upsert: false });
    setUploading(false);
    if (error) return toast({ text: `Upload fehlgeschlagen: ${error.message}`, tone: "error" });
    setImageUrl(sb.storage.from("ep-images").getPublicUrl(path).data.publicUrl);
  }

  async function save() {
    if (!title.trim()) return toast({ text: "Bitte einen Titel eingeben", tone: "error" });
    setSaving(true);
    const cats = categories.split("/").map((c) => c.trim()).filter(Boolean);
    const servingsNum = servings.trim() ? Number.parseInt(servings, 10) : null;
    const nutritionObj = nutrition.trim() ? parseNutrition(nutrition.trim()) : null;
    const row = {
      household_id: household.id,
      title: title.trim(),
      subtitle: subtitle.trim() || null,
      source: source.trim() || null,
      categories: cats,
      tags: tags.trim() ? tags.split(",").map(slugifyTag).filter(Boolean) : cats.map(slugifyTag),
      diet,
      time_text: timeText.trim() || null,
      time_min: timeMin.trim() ? Number.parseInt(timeMin, 10) : parseTimeMinutes(timeText),
      servings: Number.isFinite(servingsNum) ? servingsNum : null,
      servings_text: servingsText.trim() || (servingsNum ? String(servingsNum) : null),
      steps: steps.map((s) => s.text.trim()).filter(Boolean),
      tip: tip.trim() || null,
      nutrition: nutritionObj,
      cookbook_id: cookbookId || null,
      cookbook_page: cookbookId && page.trim() ? Number.parseInt(page, 10) : null,
      cookbook_link_confirmed: cookbookId ? confirmed : true,
      image_url: imageUrl || null,
    };
    const res = recipe
      ? await sb.from("ep_recipes").update(row).eq("id", recipe.id).select("id").single()
      : await sb.from("ep_recipes").insert(row).select("id").single();
    if (res.error) {
      setSaving(false);
      return toast({ text: res.error.message, tone: "error" });
    }
    const id = (res.data as { id: string }).id;
    await sb.from("ep_recipe_ingredients").delete().eq("recipe_id", id);
    const rows = ings
      .filter((i) => i.name.trim())
      .map((i, position) => {
        const parsed = parseAmount(i.amount_text);
        return { recipe_id: id, position, group_name: i.group_name.trim() || null, name: i.name.trim(), amount_text: i.amount_text.trim() || null, ...parsed };
      });
    if (rows.length) {
      const { error } = await sb.from("ep_recipe_ingredients").insert(rows);
      if (error) toast({ text: error.message, tone: "error" });
    }
    await reloadRecipes();
    setSaving(false);
    router.replace(`/rezepte/${id}`);
  }

  return (
    <>
      <PageHeader
        title={recipe ? "Bearbeiten" : "Neues Rezept"}
        icon={recipe ? "✏️" : "📝"}
        back={{ href: recipe ? `/rezepte/${recipe.id}` : "/rezepte", label: recipe ? "Rezept" : "Rezepte" }}
        trailing={<button className="btn-plain t-sub pressable font-semibold" disabled={saving} onClick={save}>{saving ? "Speichert …" : "Sichern"}</button>}
      />
      <div className="mx-auto max-w-2xl px-4">
        {intro}
        {notice && (
          <p className="card t-sub mt-4 px-4 py-3" role="status" style={{ background: "var(--accent-soft)" }}>{notice}</p>
        )}
        <Section title="Foto">
          <div className="flex items-center gap-3">
            <RecipeImage recipe={{ title: title || "?", image_url: imageUrl || null, diet }} className="h-20 w-20 text-2xl" rounded={14} />
            <label className="btn btn-gray pressable">
              <IconCamera size={18} /> {uploading ? "Lädt …" : imageUrl ? "Ersetzen" : "Foto wählen"}
              <input type="file" accept="image/*" className="hidden" onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])} />
            </label>
            {imageUrl && <button className="btn-plain t-sub pressable" onClick={() => setImageUrl("")}>Entfernen</button>}
          </div>
          {!imageUrl && dishPhoto(title) && (
            <p className="t-footnote mt-2" style={{ color: "var(--label-2)" }}>Beispielbild aus frei lizenzierter Quelle. Ein eigenes Foto ersetzt es.</p>
          )}
        </Section>

        <Section title="Grunddaten">
          <div className="flex flex-col gap-2">
            <input className="input" placeholder="Titel" value={title} onChange={(e) => setTitle(e.target.value)} aria-label="Titel" />
            <input className="input" placeholder="Untertitel (optional)" value={subtitle} onChange={(e) => setSubtitle(e.target.value)} aria-label="Untertitel" />
            <input className="input" placeholder="Quelle: URL oder Text (optional)" value={source} onChange={(e) => setSource(e.target.value)} aria-label="Quelle" />
            <input className="input" placeholder="Kategorien, getrennt mit / (z. B. Pasta / Fisch / One-Pot)" value={categories} onChange={(e) => setCategories(e.target.value)} aria-label="Kategorien" />
            <input className="input" placeholder="Tags, mit Komma (leer = aus Kategorien)" value={tags} onChange={(e) => setTags(e.target.value)} aria-label="Tags" />
            <Segmented<Diet> label="Ernährung" value={diet} onChange={setDiet} options={(["vegetarisch", "fisch", "fleisch"] as Diet[]).map((d) => ({ value: d, label: DIET_LABEL[d] }))} />
          </div>
        </Section>

        <Section title="Zeit & Portionen">
          <div className="grid grid-cols-2 gap-2">
            <input className="input col-span-2" placeholder="Zeit als Text (z. B. Vorbereitung 15 Min. / Garzeit 45 Min.)" value={timeText} onChange={(e) => setTimeText(e.target.value)} aria-label="Zeit" />
            <input className="input" inputMode="numeric" placeholder={`Minuten gesamt${parseTimeMinutes(timeText) ? ` (${parseTimeMinutes(timeText)})` : ""}`} value={timeMin} onChange={(e) => setTimeMin(e.target.value.replace(/\D/g, ""))} aria-label="Minuten gesamt" />
            <input className="input" inputMode="numeric" placeholder="Portionen" value={servings} onChange={(e) => setServings(e.target.value.replace(/\D/g, ""))} aria-label="Portionen" />
            <input className="input col-span-2" placeholder="Portionen-Text (optional, z. B. 4 (2 Pizzen))" value={servingsText} onChange={(e) => setServingsText(e.target.value)} aria-label="Portionen-Text" />
          </div>
        </Section>

        <Section title="Kochbuch">
          <div className="grid grid-cols-3 gap-2">
            <select className="input col-span-2" value={cookbookId} onChange={(e) => setCookbookId(e.target.value)} aria-label="Kochbuch">
              <option value="">– keins –</option>
              {cookbooks.map((c) => <option key={c.id} value={c.id}>{c.title}</option>)}
            </select>
            <input className="input" inputMode="numeric" placeholder="Seite" value={page} disabled={!cookbookId} onChange={(e) => setPage(e.target.value.replace(/\D/g, ""))} aria-label="Seite" />
          </div>
          {cookbookId && (
            <label className="t-sub mt-2 flex items-center gap-2 px-1">
              <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} /> Verknüpfung bestätigt
            </label>
          )}
        </Section>

        <Section title="Zutaten" footer="Menge als Text, z. B. „200 g“, „2–3 EL“, „nach Geschmack“. Gruppe optional (z. B. Teig, Sauce).">
          <div className="flex flex-col gap-2">
            {ings.map((ing, i) => (
              <div key={ing.key} className="card flex flex-col gap-1.5 p-2">
                <div className="flex gap-1.5">
                  <input className="input flex-[2]" placeholder="Zutat" value={ing.name} onChange={(e) => setIngs((l) => l.map((x) => (x.key === ing.key ? { ...x, name: e.target.value } : x)))} aria-label={`Zutat ${i + 1}`} />
                  <input className="input flex-1" placeholder="Menge" value={ing.amount_text} onChange={(e) => setIngs((l) => l.map((x) => (x.key === ing.key ? { ...x, amount_text: e.target.value } : x)))} aria-label={`Menge ${i + 1}`} />
                </div>
                <div className="flex items-center gap-1">
                  <input className="input t-footnote !min-h-8 flex-1 !py-1" placeholder="Gruppe (optional)" value={ing.group_name} onChange={(e) => setIngs((l) => l.map((x) => (x.key === ing.key ? { ...x, group_name: e.target.value } : x)))} aria-label={`Gruppe ${i + 1}`} />
                  <button className="pressable p-2" aria-label="Nach oben" onClick={() => setIngs((l) => move(l, i, -1))}><IconArrowUp size={18} /></button>
                  <button className="pressable p-2" aria-label="Nach unten" onClick={() => setIngs((l) => move(l, i, 1))}><IconArrowDown size={18} /></button>
                  <button className="pressable p-2" aria-label="Entfernen" style={{ color: "var(--red)" }} onClick={() => setIngs((l) => l.filter((x) => x.key !== ing.key))}><IconTrash size={18} /></button>
                </div>
              </div>
            ))}
            <button className="btn btn-tinted pressable" onClick={() => setIngs((l) => [...l, { key: nextKey(), group_name: l[l.length - 1]?.group_name ?? "", name: "", amount_text: "" }])}>
              <IconPlus size={18} /> Zutat
            </button>
          </div>
        </Section>

        <Section title="Zubereitung">
          <div className="flex flex-col gap-2">
            {steps.map((s, i) => (
              <div key={s.key} className="card flex gap-2 p-2">
                <span className="t-headline w-6 pt-2 text-center" style={{ color: "var(--accent)" }}>{i + 1}</span>
                <textarea className="input flex-1" rows={2} value={s.text} onChange={(e) => setSteps((l) => l.map((x) => (x.key === s.key ? { ...x, text: e.target.value } : x)))} aria-label={`Schritt ${i + 1}`} />
                <div className="flex flex-col">
                  <button className="pressable p-1.5" aria-label="Nach oben" onClick={() => setSteps((l) => move(l, i, -1))}><IconArrowUp size={18} /></button>
                  <button className="pressable p-1.5" aria-label="Nach unten" onClick={() => setSteps((l) => move(l, i, 1))}><IconArrowDown size={18} /></button>
                  <button className="pressable p-1.5" aria-label="Entfernen" style={{ color: "var(--red)" }} onClick={() => setSteps((l) => l.filter((x) => x.key !== s.key))}><IconTrash size={18} /></button>
                </div>
              </div>
            ))}
            <button className="btn btn-tinted pressable" onClick={() => setSteps((l) => [...l, { key: nextKey(), text: "" }])}><IconPlus size={18} /> Schritt</button>
          </div>
        </Section>

        <Section title="Tipp & Nährwerte">
          <div className="flex flex-col gap-2">
            <textarea className="input" placeholder="Tipp (optional)" value={tip} onChange={(e) => setTip(e.target.value)} aria-label="Tipp" />
            <input className="input" placeholder="Nährwerte pro Portion, z. B. 442 kcal | Fett 23,7 g | Eiweiß 42 g" value={nutrition} onChange={(e) => setNutrition(e.target.value)} aria-label="Nährwerte" />
          </div>
        </Section>

        <button className="btn btn-primary pressable mt-8 w-full" disabled={saving} onClick={save}>{saving ? "Speichert …" : "Rezept sichern"}</button>
      </div>
    </>
  );
}
