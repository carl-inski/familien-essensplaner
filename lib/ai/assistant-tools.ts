import "server-only";
import { tool } from "ai";
import { z } from "zod";
import { WEEKDAY_LONG, addDays, weekdayIndex } from "@/lib/dates";
import { cookStatsFromHistory } from "@/lib/history";
import { matchByIngredients } from "@/lib/leftovers";
import { MEALS, MEAL_LABEL, slotKey } from "@/lib/meals";
import { buildShoppingList, effectiveStatus, needsShopping, presentMembers } from "@/lib/planning";
import { rankedCandidates, type PlannedDish } from "@/lib/suggest";
import type { Attendance, Cookbook, CookingHistoryEntry, Meal, MealPlanEntry, Member, Recipe } from "@/lib/types";
import { AnwesenheitInput, BuchInput, EinplanenInput, EntwurfInput, GerichteEntfernenInput, MehrereEinplanenInput, NotizInput } from "./assistant-schemas";
import type { AiContext } from "./guard";

// Werkzeuge des Assistenten. Lesen läuft hier auf dem Server mit der Session
// des Nutzers (RLS); Schreiben hat kein execute und wird im Browser bestätigt.

interface HouseholdData {
  members: Member[];
  recipes: Recipe[];
  cookbooks: Cookbook[];
  history: CookingHistoryEntry[];
}

function loader(ctx: AiContext, today: string) {
  let cached: Promise<HouseholdData> | null = null;
  const load = () =>
    (cached ??= (async () => {
      // Vergangene Gerichte gelten als gekocht – vor dem Lesen der Historie verbuchen
      await ctx.sb.rpc("ep_mark_past_cooked");
      const [m, r, c, h] = await Promise.all([
        ctx.sb.from("ep_members").select("*").order("position"),
        ctx.sb.from("ep_recipes").select("*, ep_recipe_ingredients(*)").order("title"),
        ctx.sb.from("ep_cookbooks").select("*").order("title"),
        ctx.sb.from("ep_cooking_history").select("*").order("cooked_on", { ascending: false }),
      ]);
      return {
        members: (m.data ?? []) as Member[],
        recipes: (r.data ?? []) as Recipe[],
        cookbooks: (c.data ?? []) as Cookbook[],
        history: (h.data ?? []) as CookingHistoryEntry[],
      };
    })());
  const stats = async () => cookStatsFromHistory((await load()).history, today);
  return { load, stats };
}

const dayLabel = (d: string) => `${WEEKDAY_LONG[weekdayIndex(d)]}, ${d}`;

export function assistantTools(ctx: AiContext, today: string) {
  const { load, stats } = loader(ctx, today);

  const summary = async (r: Recipe) => {
    const s = (await stats()).get(r.id);
    const { cookbooks } = await load();
    return {
      id: r.id,
      titel: r.title,
      ernaehrung: r.diet,
      minuten: r.time_min,
      kategorien: r.categories,
      zuletzt_gekocht_vor_tagen: s ? s.days_since : null,
      kochbuch: r.cookbook_id ? cookbooks.find((c) => c.id === r.cookbook_id)?.title ?? null : null,
    };
  };

  return {
    rezepte_suchen: tool({
      description: "Sucht in der Rezeptsammlung der Familie. Ohne Suchbegriff: alle Rezepte, gefiltert. Liefert ids für rezept_lesen und einplanen.",
      inputSchema: z.object({
        suche: z.string().nullable().describe("Titel, Zutat oder Stichwort, sonst null"),
        ernaehrung: z.enum(["vegetarisch", "fisch", "fleisch"]).nullable(),
        max_minuten: z.number().int().nullable(),
        nicht_gekocht_seit_tagen: z.number().int().nullable().describe("nur Rezepte, die mindestens so lange nicht gekocht wurden"),
        anzahl: z.number().int().min(1).max(30).nullable().describe("Standard 12"),
      }),
      execute: async (q) => {
        const { recipes } = await load();
        let list = recipes;
        if (q.suche?.trim()) {
          const { data } = await ctx.sb.rpc("ep_search_recipes", { q: q.suche.trim() });
          const ids = new Set(((data ?? []) as { id: string }[]).map((d) => d.id));
          const term = q.suche.trim().toLowerCase();
          list = list.filter((r) => ids.has(r.id) || r.title.toLowerCase().includes(term));
        }
        if (q.ernaehrung) list = list.filter((r) => r.diet === q.ernaehrung);
        if (q.max_minuten) list = list.filter((r) => r.time_min !== null && r.time_min <= q.max_minuten!);
        const st = await stats();
        if (q.nicht_gekocht_seit_tagen) list = list.filter((r) => (st.get(r.id)?.days_since ?? Infinity) >= q.nicht_gekocht_seit_tagen!);
        const rows = await Promise.all(list.slice(0, q.anzahl ?? 12).map(summary));
        return { treffer: list.length, rezepte: rows };
      },
    }),

    rezept_lesen: tool({
      description: "Liest ein Rezept vollständig: Zutaten, Zubereitung, Tipp, Notizen der Familie, Kochhistorie.",
      inputSchema: z.object({ id: z.string() }),
      execute: async ({ id }) => {
        const { recipes, members, history } = await load();
        const r = recipes.find((x) => x.id === id);
        if (!r) return { fehler: "Rezept nicht gefunden" };
        const { data: notes } = await ctx.sb.from("ep_recipe_notes").select("body, member_id, created_at").eq("recipe_id", id).order("created_at", { ascending: false }).limit(20);
        return {
          ...(await summary(r)),
          portionen: r.servings,
          zeit: r.time_text,
          zutaten: (r.ep_recipe_ingredients ?? []).sort((a, b) => a.position - b.position).map((i) => `${i.group_name ? `[${i.group_name}] ` : ""}${i.amount_text ?? ""} ${i.name}`.trim()),
          zubereitung: r.steps,
          tipp: r.tip,
          seite: r.cookbook_page,
          naehrwerte: r.nutrition?.text ?? null,
          notizen: (notes ?? []).map((n) => ({ von: members.find((m) => m.id === n.member_id)?.name ?? "?", text: n.body, am: String(n.created_at).slice(0, 10) })),
          gekocht_am: history.filter((h) => h.recipe_id === id).slice(0, 5).map((h) => h.cooked_on),
        };
      },
    }),

    woche_lesen: tool({
      description: "Liest Plan und Anwesenheit für mehrere Tage (Mittag und Abend): Gericht, Koch, wer da ist und wer nicht.",
      inputSchema: z.object({
        von: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().describe("Startdatum, Standard heute"),
        tage: z.number().int().min(1).max(14).nullable().describe("Standard 7"),
      }),
      execute: async ({ von, tage }) => {
        const from = von ?? today;
        const to = addDays(from, (tage ?? 7) - 1);
        const { members, recipes } = await load();
        const [p, a] = await Promise.all([
          ctx.sb.from("ep_meal_plan").select("*").gte("date", from).lte("date", to),
          ctx.sb.from("ep_attendance").select("*").gte("date", from).lte("date", to).in("member_id", members.map((m) => m.id)),
        ]);
        const plan = (p.data ?? []) as MealPlanEntry[];
        const attendance = (a.data ?? []) as Attendance[];
        const days: unknown[] = [];
        for (let d = from; d <= to; d = addDays(d, 1)) {
          for (const meal of MEALS) {
            const e = plan.find((x) => x.date === d && x.meal === meal);
            const r = e?.recipe_id ? recipes.find((x) => x.id === e.recipe_id) : null;
            const present = members.filter((m) => effectiveStatus(m, d, meal, attendance).status === "da");
            days.push({
              tag: dayLabel(d),
              mahlzeit: MEAL_LABEL[meal],
              gericht: r ? { id: r.id, titel: r.title, ernaehrung: r.diet } : e?.leftover_of ? "Reste" : null,
              status: e?.status ?? null,
              koch: e?.cook_id ? members.find((m) => m.id === e.cook_id)?.name ?? null : null,
              da: present.map((m) => m.name),
              weg: members.filter((m) => !present.includes(m)).map((m) => m.name),
            });
          }
        }
        return { tage: days };
      },
    }),

    lange_nicht_gegessen: tool({
      description: "Rezepte, die am längsten nicht gekocht wurden, plus noch nie gekochte.",
      inputSchema: z.object({ anzahl: z.number().int().min(1).max(30).nullable() }),
      execute: async ({ anzahl }) => {
        const { recipes } = await load();
        const st = await stats();
        const sorted = [...recipes].sort((a, b) => (st.get(b.id)?.days_since ?? 1e6) - (st.get(a.id)?.days_since ?? 1e6));
        return { rezepte: await Promise.all(sorted.slice(0, anzahl ?? 12).map(summary)) };
      },
    }),

    regal: tool({
      description: "Die Kochbücher im Regal der Familie mit Anzahl verknüpfter Rezepte.",
      inputSchema: z.object({}),
      execute: async () => {
        const { cookbooks, recipes } = await load();
        return {
          buecher: cookbooks.map((c) => ({ id: c.id, titel: c.title, autoren: c.authors, isbn: c.isbn, rezepte: recipes.filter((r) => r.cookbook_id === c.id).length })),
        };
      },
    }),

    einkaufsliste: tool({
      description:
        "Aktuelle Einkaufsliste: Zutaten aller kommenden Gerichte ab heute, für die noch nicht eingekauft wurde (Mengen nach Anwesenheit, Vorrat wie Salz ausgelassen), plus Posten unter „Noch offen“.",
      inputSchema: z.object({ bis: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().describe("nur Gerichte bis zu diesem Datum, sonst alle") }),
      execute: async ({ bis }) => {
        const to = bis ?? addDays(today, 42);
        const { members, recipes } = await load();
        const [p, a, v, x] = await Promise.all([
          ctx.sb.from("ep_meal_plan").select("*").gte("date", today).lte("date", addDays(today, 42)),
          ctx.sb.from("ep_attendance").select("*").gte("date", today).lte("date", addDays(today, 42)).in("member_id", members.map((m) => m.id)),
          ctx.sb.from("ep_pantry").select("name"),
          ctx.sb.from("ep_shopping_extra").select("text"),
        ]);
        const plan = (p.data ?? []) as MealPlanEntry[];
        const pantry = new Set(((v.data ?? []) as { name: string }[]).map((r) => r.name));
        const include = (e: MealPlanEntry) => needsShopping(e, today) && e.date <= to;
        const items = buildShoppingList(plan, new Map(recipes.map((r) => [r.id, r])), members, (a.data ?? []) as Attendance[], pantry, include);
        return {
          gerichte: plan.filter(include).map((e) => ({ tag: dayLabel(e.date), mahlzeit: MEAL_LABEL[e.meal], gericht: recipes.find((r) => r.id === e.recipe_id)?.title ?? null })),
          schon_eingekauft: plan.filter((e) => e.shopped_at && e.recipe_id).map((e) => ({ tag: dayLabel(e.date), gericht: recipes.find((r) => r.id === e.recipe_id)?.title ?? null })),
          noch_offen: ((x.data ?? []) as { text: string }[]).map((r) => r.text),
          zutaten: items.filter((i) => !i.pantry).map((i) => ({ text: i.text, bereich: i.aisle })),
          immer_zu_hause: items.filter((i) => i.pantry).map((i) => i.name),
        };
      },
    }),

    vorschlaege_finden: tool({
      description:
        "Findet für offene Mahlzeiten eines Zeitraums passende Rezepte aus der Sammlung. Die Hausregeln (Fleischregel, 14-Tage-Sperre, keine Snacks am Abend) sind schon angewendet. Danach mit mehrere_einplanen vorschlagen.",
      inputSchema: z.object({
        von: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().describe("Standard heute"),
        bis: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().describe("Standard Sonntag dieser Woche bzw. 6 Tage nach von"),
        mahlzeiten: z.array(z.enum(["mittag", "abend"])).nullable().describe("Standard beide"),
        max_minuten: z.number().int().nullable(),
        ernaehrung: z.enum(["vegetarisch", "fisch", "fleisch"]).nullable(),
      }),
      execute: async (q) => {
        const from = q.von ?? today;
        const to = q.bis ?? addDays(from, 6);
        const meals = (q.mahlzeiten?.length ? q.mahlzeiten : MEALS) as Meal[];
        const { members, recipes } = await load();
        const st = await stats();
        const [p, a, rej] = await Promise.all([
          ctx.sb.from("ep_meal_plan").select("*").gte("date", addDays(from, -3)).lte("date", addDays(to, 3)),
          ctx.sb.from("ep_attendance").select("*").gte("date", from).lte("date", to).in("member_id", members.map((m) => m.id)),
          ctx.sb.from("ep_suggestions").select("recipe_id, reject_reason, created_at").eq("status", "abgelehnt").gte("created_at", new Date(Date.now() - 14 * 86400000).toISOString()),
        ]);
        const plan = (p.data ?? []) as MealPlanEntry[];
        const attendance = (a.data ?? []) as Attendance[];
        const rejected = (rej.data ?? []) as { recipe_id: string | null; reject_reason: string | null }[];
        const exclude = new Set(rejected.map((r) => r.recipe_id).filter((x): x is string => !!x));
        const planned: PlannedDish[] = plan
          .filter((e) => e.recipe_id && e.status !== "ausgefallen")
          .map((e) => ({ date: slotKey(e.date, e.meal), recipe_id: e.recipe_id, diet: recipes.find((r) => r.id === e.recipe_id)?.diet ?? null }));
        let pool = recipes.filter((r) => (r.ep_recipe_ingredients?.length ?? 0) > 0 || r.cookbook_id);
        if (q.max_minuten) pool = pool.filter((r) => r.time_min !== null && r.time_min <= q.max_minuten!);
        if (q.ernaehrung) pool = pool.filter((r) => r.diet === q.ernaehrung);

        const slots = [];
        for (let d = from; d <= to; d = addDays(d, 1)) {
          for (const meal of meals) {
            const entry = plan.find((e) => e.date === d && e.meal === meal);
            if (entry?.recipe_id || entry?.leftover_of || entry?.status === "ausgefallen") continue;
            const present = presentMembers(members, attendance, d, meal);
            if (!present.length) continue;
            const candidates = rankedCandidates(pool, st, planned, slotKey(d, meal), today, { dinner: meal === "abend", exclude });
            slots.push({
              tag: dayLabel(d),
              datum: d,
              mahlzeit: meal,
              esser: present.map((m) => m.name),
              kandidaten: await Promise.all(candidates.slice(0, 6).map(summary)),
            });
          }
        }
        return {
          offene_mahlzeiten: slots,
          kuerzlich_abgelehnt: rejected.filter((r) => r.reject_reason).map((r) => ({ rezept: recipes.find((x) => x.id === r.recipe_id)?.title ?? null, grund: r.reject_reason })),
          hinweis: "Wähle pro Mahlzeit einen Kandidaten, abwechslungsreich (nicht zweimal dasselbe, nicht zwei Fleischgerichte direkt hintereinander). Der Nutzer bestätigt auf der Karte.",
        };
      },
    }),

    rezepte_mit_zutaten: tool({
      description: "„Was koche ich damit?“: Rezepte aus der Sammlung (inkl. Kochbüchern im Regal), die möglichst viele der genannten Zutaten verwenden.",
      inputSchema: z.object({ zutaten: z.array(z.string()).min(1).max(12).describe("vorhandene Zutaten oder Reste, z. B. ['Zucchini', 'Feta']") }),
      execute: async ({ zutaten }) => {
        const { recipes } = await load();
        const hits = matchByIngredients(recipes, zutaten);
        return {
          treffer: await Promise.all(hits.map(async (h) => ({ ...(await summary(h.recipe)), passende_zutaten: h.matched, weitere_zutaten: h.missing }))),
          hinweis: hits.length ? undefined : "Nichts in der Sammlung passt – schlage eine eigene Idee vor und biete rezept_entwurf_oeffnen an.",
        };
      },
    }),

    // ---- Schreiben: nur mit Bestätigung im Browser (kein execute) ----
    mehrere_einplanen: tool({
      description: "Schlägt mehrere Gerichte auf einmal vor (z. B. die Woche füllen). Steht dort schon etwas, wird es ersetzt. Der Nutzer wählt auf einer Karte aus und übernimmt.",
      inputSchema: MehrereEinplanenInput,
    }),
    einplanen: tool({
      description:
        "Schlägt vor, ein Rezept an einem Tag einzuplanen – auch um ein schon geplantes Gericht zu ersetzen („Montag lieber was anderes“). Der Nutzer bestätigt mit „Übernehmen“. Vorher mit woche_lesen prüfen, was dort schon steht.",
      inputSchema: EinplanenInput,
    }),
    anwesenheit_setzen: tool({
      description: "Schlägt vor, jemanden für eine Mahlzeit als da oder weg einzutragen. Der Nutzer bestätigt.",
      inputSchema: AnwesenheitInput,
    }),
    notiz_hinzufuegen: tool({
      description: "Schlägt eine Notiz zu einem Rezept vor (z. B. 'Kinder mochten es'). Der Nutzer bestätigt.",
      inputSchema: NotizInput,
    }),
    rezept_entwurf_oeffnen: tool({
      description: "Öffnet ein neues Rezept vorbefüllt im Formular, z. B. eine Idee oder ein Rezept aus einem Foto im Chat. Der Nutzer prüft und sichert dort.",
      inputSchema: EntwurfInput,
    }),
    gerichte_entfernen: tool({
      description: "Schlägt vor, geplante Gerichte aus dem Plan zu nehmen (z. B. „lösch die Gerichte vom nächsten Montag“). Koch und Notiz der Mahlzeit bleiben. Der Nutzer bestätigt.",
      inputSchema: GerichteEntfernenInput,
    }),
    buch_hinzufuegen: tool({
      description:
        "Schlägt vor, ein Kochbuch ins Regal zu stellen, z. B. nach Titel oder einem Foto vom Cover oder der Rückseite. Vorher mit regal prüfen, ob es schon dasteht. Mit ISBN ergänzt die App Cover und Angaben. Der Nutzer bestätigt.",
      inputSchema: BuchInput,
    }),
  };
}

/** Tage der nächsten zwei Wochen für die Datumsauflösung im System-Prompt */
export function calendarHint(today: string): string {
  return Array.from({ length: 14 }, (_, i) => addDays(today, i))
    .map((d, i) => `${i === 0 ? "heute " : i === 1 ? "morgen " : ""}${WEEKDAY_LONG[weekdayIndex(d)]} = ${d}`)
    .join("; ");
}
