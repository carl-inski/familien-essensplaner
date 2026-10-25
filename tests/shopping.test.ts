import { describe, expect, it } from "vitest";
import { aisleFor } from "../lib/aisles";
import { matchByIngredients } from "../lib/leftovers";
import { pantryEntriesFor, pantryEntriesToAdd, withoutPantry } from "../lib/pantry";
import { buildShoppingList, needsShopping } from "../lib/planning";
import { parseAmount, scaledAmountText, shoppingKey } from "../lib/quantity";
import { knusprLinks, knusprPrompt } from "../lib/knuspr";
import { checkBatch, rankedCandidates } from "../lib/suggest";
import type { CookStats, Ingredient, MealPlanEntry, Member, Recipe } from "../lib/types";

const ing = (name: string, amount_text: string | null, position = 0): Ingredient => ({ position, group_name: null, name, amount_text, ...parseAmount(amount_text) });
const recipe = (id: string, title: string, ingredients: Ingredient[], extra: Partial<Recipe> = {}): Recipe =>
  ({ id, title, servings: 4, ep_recipe_ingredients: ingredients, diet: "vegetarisch", tags: [], categories: [], cookbook_id: null, ...extra }) as Recipe;
const member = (id: string): Member => ({ id, household_id: "h", name: id, email: null, user_id: null, role: "member", default_week: {}, position: 0 });
const entry = (id: string, date: string, recipe_id: string): MealPlanEntry => ({ id, household_id: "h", date, meal: "abend", recipe_id, leftover_of: null, cook_id: null, cook2_id: null, servings_override: null, status: "geplant", note: null });
const four = ["a", "b", "c", "d"].map(member);

describe("Umrechnen ohne KI", () => {
  it("rechnet US-Maße fest in g und ml um", () => {
    expect(parseAmount("1 cup")).toEqual({ amount: 240, unit: "ml" });
    expect(parseAmount("8 oz")).toEqual({ amount: 230, unit: "g" });
    expect(parseAmount("1 lb")).toEqual({ amount: 450, unit: "g" });
    expect(parseAmount("2 tbsp")).toEqual({ amount: 2, unit: "EL" });
    expect(parseAmount("1 Esslöffel")).toEqual({ amount: 1, unit: "EL" });
  });
  it("zeigt US-Maße metrisch an", () => {
    expect(scaledAmountText("1 cup", 240, "ml", { amount: 240, unit: "ml" })).toBe("240 ml");
    expect(scaledAmountText("2 cups (gehackt)", 960, "ml", { amount: 480, unit: "ml" })).toBe("960 ml (gehackt)");
  });
  it("fasst EL und TL derselben Zutat zusammen", () => {
    const r1 = recipe("r1", "A", [ing("Olivenöl", "2 EL")]);
    const r2 = recipe("r2", "B", [ing("Olivenöl", "3 TL")]);
    const list = buildShoppingList([entry("1", "2026-10-26", "r1"), entry("2", "2026-10-27", "r2")], new Map([["r1", r1], ["r2", r2]]), four, []);
    expect(list.filter((i) => i.name === "Olivenöl")).toEqual([expect.objectContaining({ amount: 3, unit: "EL", text: "3 EL Olivenöl" })]);
  });
});

describe("Gleiche Zutaten zusammenfassen", () => {
  it("erkennt Schreibweisen und Beschreibungen", () => {
    expect(shoppingKey("Basmati-Reis")).toBe(shoppingKey("Basmatireis"));
    expect(shoppingKey("Ingwer (frisch, gerieben)")).toBe(shoppingKey("Ingwer (frisch)"));
    expect(shoppingKey("Frühlingszwiebeln")).toBe(shoppingKey("Frühlingszwiebel"));
    expect(shoppingKey("frischer Koriander")).toBe(shoppingKey("Koriander"));
    expect(shoppingKey("Knoblauchzehen, gehackt")).toBe(shoppingKey("Knoblauchzehen"));
    expect(shoppingKey("TK-Spinat")).toBe(shoppingKey("Spinat (TK)"));
    expect(shoppingKey("Getrockneter Oregano")).toBe(shoppingKey("Oregano (getrocknet)"));
    expect(shoppingKey("Eier")).toBe(shoppingKey("Ei"));
  });
  it("hält andere Waren auseinander", () => {
    expect(shoppingKey("Koriander (gemahlen)")).not.toBe(shoppingKey("Koriander"));
    expect(shoppingKey("Kichererbsen (Dose)")).not.toBe(shoppingKey("Kichererbsen (getrocknet)"));
    expect(shoppingKey("TK-Spinat")).not.toBe(shoppingKey("Spinat (frisch)"));
    expect(shoppingKey("rote Zwiebel")).not.toBe(shoppingKey("Zwiebel"));
    expect(shoppingKey("Reis")).not.toBe(shoppingKey("Basmatireis"));
  });
  it("summiert sie auf der Liste unter dem kürzeren Namen", () => {
    const r1 = recipe("r1", "Curry", [ing("Basmati-Reis", "300 g"), ing("Ingwer (frisch, gerieben)", "20 g")]);
    const r2 = recipe("r2", "Teriyaki", [ing("Basmatireis", "300 g"), ing("Ingwer (frisch)", "20 g")]);
    const list = buildShoppingList([entry("1", "2026-10-26", "r1"), entry("2", "2026-10-27", "r2")], new Map([["r1", r1], ["r2", r2]]), four, []);
    expect(list.map((i) => i.text).sort()).toEqual(["40 g Ingwer (frisch)", "600 g Basmatireis"]);
    expect(list.find((i) => i.name === "Basmatireis")?.recipes).toEqual(["Curry", "Teriyaki"]);
  });
});

describe("Einkauf sortiert und Vorrat", () => {
  const r = recipe("r", "Pasta", [ing("Penne", "500 g"), ing("Zwiebeln", "2"), ing("Parmesan", "50 g"), ing("Salz, Pfeffer", null), ing("Olivenöl, Salz", null), ing("Pfeffer, frisch gemahlen", null)]);
  const list = buildShoppingList([entry("1", "2026-10-26", "r")], new Map([["r", r]]), four, [], new Set(["salz", "pfeffer"]));

  it("sortiert nach Supermarkt-Gang", () => {
    const aisles = list.filter((i) => !i.pantry).map((i) => i.aisle);
    expect(aisles).toEqual(["Obst & Gemüse", "Kühlregal", "Trockenware", "Trockenware"]);
  });
  it("blendet Vorrat aus und kürzt Sammelzeilen", () => {
    expect(list.filter((i) => i.pantry).map((i) => i.name).sort()).toEqual(["Pfeffer, frisch gemahlen", "Salz, Pfeffer"]);
    expect(list.find((i) => i.name === "Olivenöl")?.pantry).toBeUndefined();
  });
  it("erkennt Teile und Varianten", () => {
    const p = new Set(["salz", "pfeffer"]);
    expect(pantryEntriesToAdd("Muskat, Salz und Pfeffer")).toEqual(["muskat", "salz", "pfeffer"]);
    expect(withoutPantry("Muskat, Salz, Pfeffer", p)).toBe("Muskat");
    expect(withoutPantry("schwarzer Pfeffer", p)).toBeNull();
    expect(withoutPantry("Meersalz", p)).toBe("Meersalz");
    expect(withoutPantry("Pfeffer, frisch gemahlen", p)).toBeNull();
    expect(withoutPantry("Kokosnussöl oder Olivenöl", new Set(["olivenöl"]))).toBeNull();
    expect(withoutPantry("Zwiebeln, fein gewürfelt", p)).toBe("Zwiebeln, fein gewürfelt");
    expect(withoutPantry("Meersalz, schwarzer Pfeffer", p)).toBe("Meersalz");
    expect(pantryEntriesFor("Salz, Pfeffer", p)).toEqual(["salz", "pfeffer"]);
  });
  it("ordnet Salate nicht dem Kühlregal zu", () => {
    expect(aisleFor("Eisbergsalat oder Butterlatich")).toBe("Obst & Gemüse");
    expect(aisleFor("Frische Ananas (oder 500 g aus der Dose)")).toBe("Obst & Gemüse");
  });
});

describe("Wochenvorschläge prüfen", () => {
  const today = "2026-10-24";
  const stats = new Map<string, CookStats>([["alt", { recipe_id: "alt", last_cooked_on: "2026-10-20", times_cooked: 1, days_since: 4 }]]);
  it("markiert Fleisch-Häufung, Sperre und Doppelte im Stapel", () => {
    const res = checkBatch(
      [
        { slot: "2026-10-26#2", recipe_id: "f1", diet: "fleisch" },
        { slot: "2026-10-27#2", recipe_id: "f2", diet: "fleisch" },
        { slot: "2026-10-28#2", recipe_id: "alt", diet: "vegetarisch" },
        { slot: "2026-10-29#2", recipe_id: "v1", diet: "vegetarisch" },
        { slot: "2026-10-30#2", recipe_id: "v1", diet: "vegetarisch" },
      ],
      [],
      stats,
      today,
    );
    expect(res.map((r) => r.problem && r.problem.split(" ")[0])).toEqual([null, "Zu", "Vor", null, "Steht"]);
  });
  it("Kandidaten: keine Snacks abends, länger nicht gekocht zuerst", () => {
    const rs = [
      { id: "snack", diet: "vegetarisch" as const, cookbook_id: null, tags: ["snack"], categories: [] },
      { id: "neu", diet: "vegetarisch" as const, cookbook_id: null, tags: [], categories: [] },
      { id: "alt", diet: "vegetarisch" as const, cookbook_id: null, tags: [], categories: [] },
    ];
    expect(rankedCandidates(rs, stats, [], "2026-10-26#2", today, { dinner: true }).map((r) => r.id)).toEqual(["neu"]);
  });
});

describe("Was koche ich damit?", () => {
  it("bewertet nach Anzahl passender Zutaten", () => {
    const a = recipe("a", "Zucchini-Feta-Pasta", [ing("Zucchini", "2"), ing("Feta", "200 g"), ing("Penne", "400 g")]);
    const b = recipe("b", "Shakshuka", [ing("Tomaten (Dose)", "1"), ing("Feta", "100 g"), ing("Eier", "4")]);
    const c = recipe("c", "Curry", [ing("Kokosmilch", "400 ml")]);
    const hits = matchByIngredients([a, b, c], ["Zucchini", "Feta"]);
    expect(hits.map((h) => h.recipe.id)).toEqual(["a", "b"]);
    expect(hits[0].matched).toEqual(["Zucchini", "Feta"]);
  });
});

describe("Einkauf über Wochengrenzen", () => {
  const r1 = recipe("r1", "Pasta", [ing("Penne", "500 g")]);
  const r2 = recipe("r2", "Curry", [ing("Kokosmilch", "400 ml")]);
  const r3 = recipe("r3", "Suppe", [ing("Linsen", "250 g")]);
  const recipes = new Map([["r1", r1], ["r2", r2], ["r3", r3]]);
  const today = "2026-10-29";
  const plan: MealPlanEntry[] = [
    entry("alt", "2026-10-27", "r1"), // schon gegessen
    { ...entry("eingekauft", "2026-10-30", "r2"), shopped_at: "2026-10-26T10:00:00Z" },
    entry("offen", "2026-11-02", "r3"), // nächste Woche
    { ...entry("gekocht", "2026-10-29", "r1"), status: "gekocht" },
  ];

  it("nimmt nur kommende, noch nicht eingekaufte Gerichte", () => {
    expect(plan.filter((p) => needsShopping(p, today)).map((p) => p.id)).toEqual(["offen"]);
  });
  it("kauft nur die ausgewählten Gerichte ein", () => {
    const list = buildShoppingList(plan, recipes, four, [], new Set(), (e) => needsShopping(e, today));
    expect(list.map((i) => i.name)).toEqual(["Linsen"]);
  });
});

describe("Knuspr-Auftrag", () => {
  it("listet jede Zutat und öffnet Claude oder ChatGPT vorbefüllt", () => {
    const prompt = knusprPrompt(["600 g Basmatireis", "1 Limette"]);
    expect(prompt).toContain("Knuspr");
    expect(prompt).toContain("Nicht bestellen");
    expect(prompt.split("\n").slice(-2)).toEqual(["- 600 g Basmatireis", "- 1 Limette"]);
    const links = knusprLinks(prompt);
    expect(links.claude.startsWith("https://claude.ai/new?q=")).toBe(true);
    expect(decodeURIComponent(links.chatgpt.split("?q=")[1])).toBe(prompt);
  });
});
