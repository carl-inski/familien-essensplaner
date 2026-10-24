// Feste Antworten für LLM_PROVIDER=mock (Tests und Browsertest ohne Kosten).

import type { RecipeExtract } from "./schemas";

export function mockRecipeExtract(title = "Mock-Linsensuppe"): string {
  const x: RecipeExtract = {
    is_recipe: true,
    title,
    subtitle: null,
    servings: 4,
    servings_text: "4",
    time_text: "35 Min.",
    time_min: 35,
    diet: "vegetarisch",
    categories: ["Suppe"],
    ingredients: [
      { group: null, amount: "250 g", name: "rote Linsen" },
      { group: null, amount: "1", name: "Zwiebel, gewürfelt" },
      { group: null, amount: "1 l", name: "Gemüsebrühe" },
    ],
    steps: ["Zwiebel andünsten.", "Linsen und Brühe zugeben, 20 Minuten köcheln."],
    tip: null,
    nutrition_text: null,
    cookbook_title: "Ottolenghi Simple",
    cookbook_page: 42,
  };
  return JSON.stringify(x);
}
