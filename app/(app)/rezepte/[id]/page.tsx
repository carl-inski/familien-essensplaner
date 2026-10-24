"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { useApp } from "@/components/app-data";
import { IconCalendar, IconCart, IconClock, IconDownload, IconEdit, IconPeople, IconTrash } from "@/components/icons";
import { IconButton, PageHeader } from "@/components/nav";
import { PlanSheet } from "@/components/plan-sheet";
import { RecipeNotes } from "@/components/recipe-notes";
import { Sheet } from "@/components/sheet";
import { useToast } from "@/components/toast";
import { DIET_LABEL, DietIcon, Empty, RecipeImage, Section, Stepper, downloadText, lastCookedLabel } from "@/components/ui";
import { bringDeeplink, recipePublicUrl } from "@/lib/bring";
import { addDays, formatDateDE } from "@/lib/dates";
import { recipeToMarkdown } from "@/lib/markdown";
import { scaleIngredients } from "@/lib/planning";
import { scaledAmountText } from "@/lib/quantity";
import { recipeToDraft } from "@/lib/recipe-draft";

export default function RecipeDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const app = useApp();
  const { recipesById, cookbooksById, stats, history, members, sb, today, household, reloadHistory, reloadRecipes } = app;
  const toast = useToast();
  const recipe = recipesById.get(id);
  const [servings, setServings] = useState<number | null>(null);
  const [planOpen, setPlanOpen] = useState(false);
  const [pastOpen, setPastOpen] = useState(false);
  const [pastDate, setPastDate] = useState(addDays(today, -7));

  const target = servings ?? recipe?.servings ?? 4;
  const scaled = useMemo(() => (recipe ? scaleIngredients(recipe.ep_recipe_ingredients ?? [], recipe.servings, target) : []), [recipe, target]);
  const groups = useMemo(() => {
    const g: { name: string | null; items: typeof scaled }[] = [];
    for (const i of scaled) {
      const last = g[g.length - 1];
      if (last && last.name === i.group_name) last.items.push(i);
      else g.push({ name: i.group_name, items: [i] });
    }
    return g;
  }, [scaled]);

  if (!recipe) return <Empty title="Rezept nicht gefunden" action={<Link className="btn btn-tinted" href="/rezepte">Zur Sammlung</Link>} />;

  const book = recipe.cookbook_id ? cookbooksById.get(recipe.cookbook_id) : null;
  const myHistory = history.filter((h) => h.recipe_id === recipe.id);
  const hasIngredients = (recipe.ep_recipe_ingredients ?? []).length > 0;
  const scalable = hasIngredients && recipe.servings !== null;

  async function addHistory(cooked_on: string, source: "manuell" | "nachgetragen") {
    const { error } = await sb.from("ep_cooking_history").insert({ household_id: household.id, recipe_id: recipe!.id, cooked_on, source, servings: target, cook_id: app.me.id });
    if (error) return toast({ text: error.message, tone: "error" });
    await reloadHistory();
    toast({ text: source === "manuell" ? "Als heute gekocht eingetragen" : "Nachgetragen" });
  }

  async function removeHistory(hid: string) {
    await sb.from("ep_cooking_history").delete().eq("id", hid);
    await reloadHistory();
  }

  async function deleteRecipe() {
    if (!confirm(`„${recipe!.title}“ wirklich löschen? Die Kochhistorie dieses Rezepts geht dabei verloren.`)) return;
    const { error } = await sb.from("ep_recipes").delete().eq("id", recipe!.id);
    if (error) return toast({ text: error.message, tone: "error" });
    await reloadRecipes();
    router.replace("/rezepte");
  }

  const bringHref = bringDeeplink(recipePublicUrl(recipe.public_slug, scalable ? target : null));
  const nutritionEntries = recipe.nutrition ? Object.entries(recipe.nutrition).filter(([k]) => k !== "text") : [];

  return (
    <>
      <PageHeader
        title={recipe.title}
        back={{ href: "/rezepte", label: "Rezepte" }}
        trailing={<IconButton label="Bearbeiten" href={`/rezepte/${recipe.id}/bearbeiten`}><IconEdit /></IconButton>}
        subtitle={recipe.subtitle ?? undefined}
      />

      <div className="mx-auto max-w-2xl px-4">
        <RecipeImage recipe={recipe} className="mt-4 aspect-[16/9] w-full text-6xl" rounded={16} />

        <div className="mt-3 flex flex-wrap gap-2">
          {recipe.diet && <span className="chip"><DietIcon diet={recipe.diet} size={15} /> {DIET_LABEL[recipe.diet]}</span>}
          {recipe.time_text && <span className="chip"><IconClock size={15} /> {recipe.time_text}</span>}
          {recipe.servings_text && <span className="chip"><IconPeople size={15} /> {recipe.servings_text}</span>}
          {recipe.categories.map((c) => <span key={c} className="chip">{c}</span>)}
        </div>

        {book && (
          <Link href={`/regal/${book.id}`} className="card pressable mt-3 flex items-center gap-3 px-4 py-3">
            <span className="t-sub flex-1">
              <span style={{ color: "var(--label-2)" }}>aus deinem Regal:</span> <strong>{book.title}</strong>
              {recipe.cookbook_page ? `, S. ${recipe.cookbook_page}` : ""}
            </span>
            {!recipe.cookbook_link_confirmed && <span className="badge" style={{ background: "var(--yellow-soft)" }}>zu bestätigen</span>}
          </Link>
        )}

        <p className="t-footnote mt-3 px-1" style={{ color: "var(--label-2)" }}>{lastCookedLabel(stats.get(recipe.id))}</p>

        <div className="mt-4 grid grid-cols-2 gap-2">
          <button className="btn btn-primary pressable" onClick={() => setPlanOpen(true)}><IconCalendar size={18} /> Einplanen</button>
          {hasIngredients ? (
            <a className="btn btn-tinted pressable" href={bringHref} target="_blank" rel="noopener"><IconCart size={18} /> In Bring</a>
          ) : (
            <button className="btn btn-tinted" disabled title="Erst Zutaten ergänzen"><IconCart size={18} /> In Bring</button>
          )}
        </div>

        <Section
          title="Zutaten"
          trailing={scalable ? <Stepper label="Portionen" value={target} min={1} max={40} onChange={setServings} /> : undefined}
          footer={!hasIngredients ? "Nur Verweis aufs Kochbuch – Zutaten ergänzen, um zu skalieren und nach Bring zu exportieren." : scalable ? `Mengen für ${target} Portionen` : "Ohne Portionsangabe nicht skalierbar."}
        >
          {groups.map((g, gi) => (
            <div key={gi} className="mb-3">
              {g.name && <p className="t-footnote mb-1 px-4 font-semibold" style={{ color: "var(--label-2)" }}>{g.name}</p>}
              <ul className="group">
                {g.items.map((i, ii) => (
                  <li key={ii} className="row justify-between gap-4">
                    <span className="t-sub">{i.name}</span>
                    <span className="t-sub shrink-0 text-right tabular-nums" style={{ color: "var(--label-2)" }}>
                      {scalable ? scaledAmountText(i.amount_text, i.scaled_amount, i.scaled_unit, i) : i.amount_text}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </Section>

        {recipe.steps.length > 0 && (
          <Section title="Zubereitung">
            <ol className="flex flex-col gap-3">
              {recipe.steps.map((s, i) => (
                <li key={i} className="card flex gap-3 px-4 py-3">
                  <span className="t-headline tabular-nums" style={{ color: "var(--accent)" }}>{i + 1}</span>
                  <span className="t-sub">{s}</span>
                </li>
              ))}
            </ol>
          </Section>
        )}

        {recipe.tip && (
          <Section title="Tipp">
            <p className="card t-sub px-4 py-3">{recipe.tip}</p>
          </Section>
        )}

        <RecipeNotes recipeId={recipe.id} />

        {nutritionEntries.length > 0 && (
          <Section title="Nährwerte pro Portion" footer={recipe.nutrition_estimated ? "geschätzt" : "laut Rezept"}>
            <div className="card grid grid-cols-3 gap-px overflow-hidden">
              {nutritionEntries.map(([k, v]) => (
                <div key={k} className="px-3 py-2">
                  <p className="t-headline tabular-nums">{v}</p>
                  <p className="t-caption" style={{ color: "var(--label-2)" }}>{k === "kcal" ? "kcal" : k}</p>
                </div>
              ))}
            </div>
          </Section>
        )}

        <Section title="Kochhistorie">
          <div className="group">
            {myHistory.map((h) => (
              <div key={h.id} className="row">
                <span className="t-sub flex-1">
                  {formatDateDE(h.cooked_on)}
                  <span className="t-footnote ml-2" style={{ color: "var(--label-2)" }}>
                    {h.source === "plan" ? "aus dem Plan" : h.source === "manuell" ? "außerhalb des Plans" : "nachgetragen"}
                    {h.cook_id ? ` · ${members.find((m) => m.id === h.cook_id)?.name ?? ""}` : ""}
                    {h.servings ? ` · ${h.servings} Port.` : ""}
                  </span>
                </span>
                {h.source !== "plan" && (
                  <button className="pressable p-1" aria-label="Eintrag löschen" style={{ color: "var(--label-3)" }} onClick={() => removeHistory(h.id)}><IconTrash size={18} /></button>
                )}
              </div>
            ))}
            {!myHistory.length && <div className="row t-sub" style={{ color: "var(--label-2)" }}>Noch nie gekocht</div>}
          </div>
          <div className="mt-2 flex flex-wrap gap-2">
            <button className="btn btn-gray btn-sm pressable" onClick={() => addHistory(today, "manuell")}>Heute außerhalb des Plans gekocht</button>
            <button className="btn btn-gray btn-sm pressable" onClick={() => setPastOpen(true)}>Früher schon mal gekocht …</button>
          </div>
        </Section>

        <Section title="Mehr">
          <div className="group">
            <button className="row pressable" onClick={() => downloadText(`${recipe.title}.md`, recipeToMarkdown(recipeToDraft(recipe, cookbooksById)) + "\n")}>
              <IconDownload size={20} /> <span className="t-sub flex-1">Als Markdown exportieren</span>
            </button>
            <Link className="row pressable" href={`/rezepte/${recipe.id}/bearbeiten`}>
              <IconEdit size={20} /> <span className="t-sub flex-1">Bearbeiten</span>
            </Link>
            <button className="row pressable" style={{ color: "var(--red)" }} onClick={deleteRecipe}>
              <IconTrash size={20} /> <span className="t-sub flex-1">Rezept löschen</span>
            </button>
          </div>
        </Section>
      </div>

      <PlanSheet recipe={planOpen ? recipe : null} onClose={() => setPlanOpen(false)} />

      <Sheet open={pastOpen} onClose={() => setPastOpen(false)} title="Früher gekocht">
        <p className="t-sub mb-3" style={{ color: "var(--label-2)" }}>Ungefähres Datum reicht – es zählt für „Lange nicht gegessen“ und die Vorschläge.</p>
        <input className="input" type="date" max={today} value={pastDate} onChange={(e) => setPastDate(e.target.value)} />
        <button className="btn btn-primary pressable mt-4 w-full" onClick={async () => { await addHistory(pastDate, "nachgetragen"); setPastOpen(false); }}>Nachtragen</button>
      </Sheet>
    </>
  );
}
