import { describe, expect, it } from "vitest";
import { parseAmount } from "../lib/quantity";
import { extraKey, purchasesFor, shoppingState, stockEntryFromText, type NewPurchase, type Purchase } from "../lib/shopping";
import type { Attendance, Ingredient, MealPlanEntry, Member, Recipe } from "../lib/types";

const TODAY = "2026-11-11";
const NOW = "2026-11-11T17:30:00Z";

const ing = (name: string, amount_text: string | null, position = 0): Ingredient => ({ position, group_name: null, name, amount_text, ...parseAmount(amount_text) });
const recipe = (id: string, title: string, ingredients: Ingredient[], servings = 4): Recipe =>
  ({ id, title, servings, ep_recipe_ingredients: ingredients, diet: "vegetarisch", tags: [], categories: [], cookbook_id: null }) as unknown as Recipe;
const member = (id: string): Member => ({ id, household_id: "h", name: id, email: null, user_id: null, role: "member", default_week: {}, position: 0 });
const entry = (id: string, date: string, recipe_id: string | null, extra: Partial<MealPlanEntry> = {}): MealPlanEntry => ({
  id, household_id: "h", date, meal: "abend", recipe_id, leftover_of: null, cook_id: null, cook2_id: null, servings_override: null, status: "geplant", note: null, ...extra,
});
const three = ["a", "b", "c"].map(member);
const guests = (date: string, n: number): Attendance[] => [{ id: "g", member_id: "a", date, meal: "abend", status: "da", guests: n }];

// 4 Portionen: 600 g Gnocchi, 400 g Tomaten, Basilikum ohne Menge
const gnocchi = recipe("gn", "Tomaten-Gnocchi", [ing("Gnocchi", "600 g"), ing("Tomaten", "400 g", 1), ing("Basilikum", null, 2)]);
const salat = recipe("sa", "Tomatensalat", [ing("Tomaten", "800 g"), ing("Olivenöl", "2 EL", 1)]);
const recipes = new Map([gnocchi, salat].map((r) => [r.id, r]));

let seq = 0;
const newId = () => `c${++seq}`;
/** Käufe so in die „Datenbank“ legen, wie die App es tut */
const store = (rows: NewPurchase[], at = NOW): Purchase[] => rows.map((r) => ({ ...r, id: `p-${r.client_id}`, bought_at: at }));

function state(plan: MealPlanEntry[], purchases: Purchase[], attendance: Attendance[] = [], opts: { now?: string; include?: (e: MealPlanEntry) => boolean } = {}) {
  return shoppingState({ plan, recipes, members: three, attendance, purchases, today: TODAY, now: opts.now ?? NOW, include: opts.include });
}
/** Offene Zeilen, alphabetisch (die Liste selbst ist nach Ladenbereich sortiert) */
const texts = (s: ReturnType<typeof state>) => s.open.map((i) => i.text).sort();
/** Alles Offene abhaken */
const buyAll = (s: ReturnType<typeof state>) => store(s.open.flatMap((i) => purchasesFor(i, "h", "a", newId)));

describe("Offener Bedarf", () => {
  const friday = entry("fr", "2026-11-13", "gn");

  it("ohne Käufe steht alles auf der Liste, skaliert auf die Esser", () => {
    expect(texts(state([friday], []))).toEqual(["450 g Gnocchi", "300 g Tomaten", "Basilikum"].sort());
  });

  it("abgehakt verschwindet – das Gericht gilt als eingekauft", () => {
    const s = state([friday], []);
    const after = state([friday], buyAll(s));
    expect(after.open).toEqual([]);
    expect(after.covered.has("fr")).toBe(true);
    expect(after.bought.map((b) => b.text).sort()).toEqual(["300 g Tomaten", "450 g Gnocchi", "Basilikum"]);
  });

  it("für drei gekauft, jetzt essen fünf mit: nur die Differenz ist offen", () => {
    const bought = buyAll(state([friday], []));
    const five = state([friday], bought, guests("2026-11-13", 2));
    expect(texts(five)).toEqual(["300 g Gnocchi", "200 g Tomaten"].sort()); // 750 − 450, 500 − 300; Basilikum ist da
    expect(five.covered.has("fr")).toBe(false);
    // Differenz nachkaufen → wieder alles da
    expect(state([friday], [...bought, ...buyAll(five)], guests("2026-11-13", 2)).open).toEqual([]);
  });

  it("weniger Esser als gekauft: nichts offen, der Rest ist noch da", () => {
    const bought = buyAll(state([friday], [], guests("2026-11-13", 2)));
    const s = state([friday], bought);
    expect(s.open).toEqual([]);
    expect(s.stock.map((x) => x.text)).toEqual(["300 g Gnocchi", "200 g Tomaten"]);
  });

  it("einzelne Zeile abgehakt: der Rest bleibt offen", () => {
    const s = state([friday], []);
    const onlyGnocchi = store(purchasesFor(s.open.find((i) => i.name === "Gnocchi")!, "h", "a", newId));
    expect(texts(state([friday], onlyGnocchi))).toEqual(["300 g Tomaten", "Basilikum"].sort());
  });
});

describe("Plan ändert sich nach dem Einkauf", () => {
  const friday = entry("fr", "2026-11-13", "gn");
  const saturday = entry("sa", "2026-11-14", "sa");

  it("Gericht fällt aus: der Kauf bleibt und steht unter „Ist noch da“", () => {
    const bought = buyAll(state([friday], []));
    const s = state([{ ...friday, status: "ausgefallen" }], bought);
    expect(s.open).toEqual([]);
    expect(s.stock.map((x) => x.text)).toEqual(["Basilikum", "450 g Gnocchi", "300 g Tomaten"]);
  });

  it("was noch da ist, zählt beim nächsten Gericht mit derselben Zutat", () => {
    const bought = buyAll(state([friday], []));
    const s = state([{ ...friday, status: "ausgefallen" }, saturday], bought);
    // Salat braucht 600 g Tomaten, 300 g sind noch da
    expect(texts(s)).toEqual(["300 g Tomaten", "1,5 EL Olivenöl"].sort());
    expect(s.open[0].usedStock).toBe(true);
    // Nur den Rest kaufen – danach ist nichts mehr offen und nichts doppelt
    const after = state([{ ...friday, status: "ausgefallen" }, saturday], [...bought, ...buyAll(s)]);
    expect(after.open).toEqual([]);
    expect(after.covered.has("sa")).toBe(true);
  });

  it("Gericht aus dem Plan genommen (Rezept entfernt): wie ausgefallen", () => {
    const bought = buyAll(state([friday], []));
    expect(state([{ ...friday, recipe_id: null }], bought).stock).toHaveLength(3);
  });

  it("Rezept im selben Slot getauscht: alte Zutaten sind noch da, neue offen", () => {
    const bought = buyAll(state([friday], []));
    const s = state([{ ...friday, recipe_id: "sa" }], bought);
    expect(texts(s)).toEqual(["300 g Tomaten", "1,5 EL Olivenöl"].sort()); // 600 gebraucht, 300 gekauft
    expect(s.stock.map((x) => x.name)).toEqual(["Basilikum", "Gnocchi"]);
  });

  it("gekocht ist verbraucht – kein Vorrat mehr", () => {
    const bought = buyAll(state([friday], []));
    expect(state([{ ...friday, status: "gekocht" }], bought).stock).toEqual([]);
    // Vergangene Gerichte werden nicht mehr geladen: ihre Käufe zählen nicht
    expect(state([], bought).stock).toEqual([]);
  });

  it("was drei Wochen liegt, gilt nicht mehr als noch da", () => {
    const bought = buyAll(state([friday], []));
    expect(state([{ ...friday, status: "ausgefallen" }], bought, [], { now: "2026-12-05T10:00:00Z" }).stock).toEqual([]);
  });
});

describe("Mehrere Gerichte", () => {
  const friday = entry("fr", "2026-11-13", "gn");
  const saturday = entry("sa", "2026-11-14", "sa");

  it("dieselbe Zutat wird eine Zeile; der Kauf verteilt sich auf die Gerichte", () => {
    const s = state([friday, saturday], []);
    const tomaten = s.open.find((i) => i.name === "Tomaten")!;
    expect(tomaten.text).toBe("900 g Tomaten");
    expect(tomaten.recipes).toEqual(["Tomaten-Gnocchi", "Tomatensalat"]);
    const rows = purchasesFor(tomaten, "h", "a", newId);
    expect(rows.map((r) => [r.meal_plan_id, r.amount])).toEqual([["fr", 300], ["sa", 600]]);
  });

  it("nur für ausgewählte Gerichte einkaufen", () => {
    const s = state([friday, saturday], [], [], { include: (e) => e.id === "fr" });
    expect(texts(s)).toEqual(["450 g Gnocchi", "300 g Tomaten", "Basilikum"].sort());
  });

  it("fällt später ein Gericht weg, bleibt das andere eingekauft", () => {
    const bought = buyAll(state([friday, saturday], []));
    const s = state([friday, { ...saturday, status: "ausgefallen" }], bought);
    expect(s.open).toEqual([]);
    expect(s.covered.has("fr")).toBe(true);
    expect(s.stock.map((x) => x.text)).toEqual(["1,5 EL Olivenöl", "600 g Tomaten"]);
  });
});

describe("Übergang und Sonderfälle", () => {
  const friday = entry("fr", "2026-11-13", "gn");

  it("mit der alten App als eingekauft markiert: bleibt erledigt", () => {
    const s = state([{ ...friday, shopped_at: "2026-11-10T10:00:00Z" }], []);
    expect(s.open).toEqual([]);
    expect(s.covered.has("fr")).toBe(true);
  });

  it("„Noch offen“-Posten sind Käufe ohne Gericht und zählen nicht als Vorrat", () => {
    const milk: Purchase = { id: "p1", client_id: "c", household_id: "h", meal_plan_id: null, item_key: extraKey("x1"), name: "Milch", amount: null, unit: null, bought_by: "a", bought_at: NOW };
    const s = state([friday], [milk]);
    expect(s.stock).toEqual([]);
    expect(s.bought).toEqual([]);
    expect(s.open).toHaveLength(3);
  });

  it("Abgehaktes bleibt zwölf Stunden durchgestrichen sichtbar", () => {
    const bought = buyAll(state([friday], []));
    expect(state([friday], bought).bought).toHaveLength(3);
    expect(state([friday], bought, [], { now: "2026-11-12T08:00:00Z" }).bought).toEqual([]);
  });

  it("Reste und Vergangenes brauchen keinen Einkauf", () => {
    const s = state([entry("gestern", "2026-11-10", "gn"), entry("rest", "2026-11-14", null, { leftover_of: "fr" })], []);
    expect(s.open).toEqual([]);
  });
});

describe("Vorrat: ist noch da", () => {
  const friday = entry("fr", "2026-11-13", "gn"); // 450 g Gnocchi, 300 g Tomaten, Basilikum
  const stockOf = (...texts: string[]) => store(texts.map((t) => stockEntryFromText(t, "h", "a", newId)!), "2026-11-09T08:00:00Z");

  it("liest Einträge von Hand und rechnet in die Einheit der Liste um", () => {
    expect(stockEntryFromText("1,5 kg Tomaten", "h", "a", newId)).toMatchObject({ name: "Tomaten", amount: 1500, unit: "g", meal_plan_id: null, source: "vorrat" });
    expect(stockEntryFromText("0,5 l Milch", "h", "a", newId)).toMatchObject({ name: "Milch", amount: 500, unit: "ml" });
    expect(stockEntryFromText("Eier", "h", "a", newId)).toMatchObject({ name: "Eier", amount: null, unit: null });
    expect(stockEntryFromText("3 Eier", "h", "a", newId)).toMatchObject({ name: "Eier", amount: 3, unit: null });
    expect(stockEntryFromText("   ", "h", "a", newId)).toBeNull();
  });

  it("eingetragener Vorrat wird vom Bedarf abgezogen", () => {
    const s = state([friday], stockOf("200 g Tomaten"));
    expect(texts(s)).toEqual(["100 g Tomaten", "450 g Gnocchi", "Basilikum"].sort());
    expect(s.open.find((i) => i.name === "Tomaten")!.usedStock).toBe(true);
  });

  it("ohne Menge heißt: genug da, in jeder Einheit", () => {
    const s = state([friday], stockOf("Tomaten", "Basilikum"));
    expect(texts(s)).toEqual(["450 g Gnocchi"]);
  });

  it("was nichts mit dem Plan zu tun hat, steht einfach im Vorrat – mit Datum", () => {
    const s = state([friday], stockOf("500 g Reis"));
    expect(s.stock).toEqual([expect.objectContaining({ name: "Reis", text: "500 g Reis", since: "2026-11-09T08:00:00Z" })]);
    expect(s.open).toHaveLength(3);
  });

  it("von Hand eingetragener Vorrat erscheint nicht als abgehakte Zeile", () => {
    const s = state([friday], store([stockEntryFromText("500 g Reis", "h", "a", newId)!], NOW));
    expect(s.bought).toEqual([]);
    expect(s.stock).toHaveLength(1);
  });

  it("mehrere Einträge derselben Zutat zählen zusammen, der älteste gibt das Datum", () => {
    const s = state([], [...stockOf("200 g Reis"), ...store([stockEntryFromText("300 g Reis", "h", "a", newId)!], NOW)]);
    expect(s.stock).toEqual([expect.objectContaining({ text: "500 g Reis", since: "2026-11-09T08:00:00Z" })]);
  });

  it("auf der Liste als „noch da“ markiert: deckt den Bedarf, wird aber nicht als Kauf gezählt", () => {
    const s = state([friday], []);
    const rows = store(purchasesFor(s.open.find((i) => i.name === "Tomaten")!, "h", "a", newId, "vorrat"));
    const after = state([friday], rows);
    expect(texts(after)).toEqual(["450 g Gnocchi", "Basilikum"]);
    expect(after.bought).toEqual([expect.objectContaining({ name: "Tomaten", fromStock: true })]);
    expect(after.stock).toEqual([]); // ist dem Gericht zugeordnet, also nicht „übrig“
  });
});
