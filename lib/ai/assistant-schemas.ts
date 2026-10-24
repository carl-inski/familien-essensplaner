// Eingaben der Schreib-Werkzeuge des Assistenten. Geteilt zwischen Server
// (Werkzeugdefinition) und Browser (Bestätigungskarte, Ausführung).

import { z } from "zod";
import { RecipeExtractSchema } from "./schemas";

const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe("Datum YYYY-MM-DD");
const meal = z.enum(["mittag", "abend"]).describe("mittag oder abend");

export const EinplanenInput = z.object({
  datum: date,
  mahlzeit: meal,
  rezept_id: z.string().describe("id aus rezepte_suchen oder rezept_lesen"),
  rezept_titel: z.string(),
  begruendung: z.string().nullable().describe("kurz, warum dieses Gericht passt; sonst null"),
});

export const AnwesenheitInput = z.object({
  datum: date,
  mahlzeit: meal,
  person: z.string().describe("Vorname eines Haushaltsmitglieds"),
  status: z.enum(["da", "weg"]),
});

export const NotizInput = z.object({
  rezept_id: z.string(),
  rezept_titel: z.string(),
  text: z.string().min(1).max(2000).describe("Notiz in der Ich-Form des Nutzers, z. B. 'Mit Zitrone noch besser'"),
});

export const EntwurfInput = z.object({
  rezept: RecipeExtractSchema.omit({ is_recipe: true, cookbook_title: true, cookbook_page: true }),
});

export type EinplanenInput = z.infer<typeof EinplanenInput>;
export type AnwesenheitInput = z.infer<typeof AnwesenheitInput>;
export type NotizInput = z.infer<typeof NotizInput>;
export type EntwurfInput = z.infer<typeof EntwurfInput>;

/** Namen der Werkzeuge, die erst nach „Übernehmen“ im Browser schreiben */
export const WRITE_TOOLS = ["einplanen", "anwesenheit_setzen", "notiz_hinzufuegen", "rezept_entwurf_oeffnen"] as const;
export type WriteTool = (typeof WRITE_TOOLS)[number];

/** Kontext der Seite, von der aus der Assistent geöffnet wurde */
export interface AssistantContext {
  rezept_id?: string;
  rezept_titel?: string;
}
