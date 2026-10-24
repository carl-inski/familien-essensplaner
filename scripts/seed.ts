// Erzeugt supabase/seed.sql aus data/rezeptsammlung.md (Briefing Abschnitt 11).
// Aufruf: npx tsx scripts/seed.ts > supabase/seed.sql
// Danach im Supabase-SQL-Editor ausführen und die Admin-E-Mail setzen:
//   update ep_members set email = '<mail>' where name = 'Carl';

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parseRecipeCollection } from "../lib/markdown";
import { CATALOG_BOOKS, dishPhoto } from "../lib/medien";

const HOUSEHOLD = "Familie Dobmeier";
const MEMBERS = ["Carl", "Paul", "Anton", "Vroni", "Christian"];

// Verknüpfungen aus Briefing 4.6: [Rezepttitel, Buch, bestätigt]
const LINKS: [string, string, boolean][] = [
  ["One-Pot Räucherlachs-Pasta (Jamie Oliver)", "ONE", true],
  ["Ananascurry (nach Leon: Fast Vegetarian)", "Leon Fast Food Vegetarisch", true],
  ["Honighähnchen", "ONE", false],
  ["Brathähnchen mit Miso", "ONE", false],
];

const q = (v: string | null | undefined) => (v === null || v === undefined ? "null" : `'${v.replace(/'/g, "''")}'`);
const arr = (v: string[]) => `array[${v.map(q).join(", ")}]::text[]`;
const json = (v: unknown) => (v === null || v === undefined ? "null" : `${q(JSON.stringify(v))}::jsonb`);
const num = (v: number | null) => (v === null ? "null" : String(v));

const recipes = parseRecipeCollection(readFileSync(join(__dirname, "..", "data", "rezeptsammlung.md"), "utf8"));
const out: string[] = [];

out.push("-- Generiert von scripts/seed.ts – nicht von Hand bearbeiten.", "begin;", "");
out.push(`insert into public.ep_households (name) values (${q(HOUSEHOLD)});`);
out.push("");
const HH = `public.ep_households where name = ${q(HOUSEHOLD)}`;

MEMBERS.forEach((name, i) => {
  out.push(`insert into public.ep_members (household_id, name, role, position) select id, ${q(name)}, ${q(i === 0 ? "admin" : "member")}, ${i} from ${HH};`);
});
out.push("");

for (const b of CATALOG_BOOKS) {
  out.push(
    `insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, ${q(b.title)}, ${arr(b.authors)}, ${q(b.publisher)}, ${b.year ?? "null"}, ${q(b.isbn)}, ${q(b.coverUrl)}, ${q(b.hinweis)} from ${HH};`,
  );
}
out.push("");

for (const r of recipes) {
  const link = LINKS.find(([t]) => t === r.title);
  const cookbookExpr = link
    ? `(select c.id from public.ep_cookbooks c where c.household_id = (select id from ${HH}) and c.title = ${q(link[1])})`
    : "null";
  const image = dishPhoto(r.title)?.src ?? null;
  out.push(
    `with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)`,
    `  select id, ${q(r.title)}, ${q(r.subtitle)}, ${q(r.source)}, ${arr(r.categories)}, ${arr(r.tags)}, ${q(r.diet)}, ${q(r.time_text)}, ${num(r.time_min)}, ${num(r.servings)}, ${q(r.servings_text)}, ${arr(r.steps)}, ${q(r.tip)}, ${json(r.nutrition)}, ${json(r.extra_meta)}, ${cookbookExpr}, null, ${link ? String(link[2]) : "true"}, ${q(image)} from ${HH} returning id)`,
    // aisle bleibt leer: der Supermarkt-Bereich wird zur Laufzeit per Schlagwort-Tabelle (lib/aisles.ts) bestimmt
    `insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values`,
    r.ingredients
      .map((i, idx) => `  (${idx}, ${q(i.group_name)}, ${q(i.name)}, ${num(i.amount)}::numeric, ${q(i.unit)}, ${q(i.amount_text)})`)
      .join(",\n") + `) as v(position, group_name, name, amount, unit, amount_text);`,
    "",
  );
}

out.push("commit;");
console.log(out.join("\n"));
