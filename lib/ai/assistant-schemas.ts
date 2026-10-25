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

export const MehrereEinplanenInput = z.object({
  eintraege: z
    .array(
      z.object({
        datum: date,
        mahlzeit: meal,
        rezept_id: z.string(),
        rezept_titel: z.string(),
        begruendung: z.string().nullable().describe("ein kurzer Satz, warum es passt"),
      }),
    )
    .min(1)
    .max(14),
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

export const GerichteEntfernenInput = z.object({
  eintraege: z
    .array(z.object({ datum: date, mahlzeit: meal }))
    .min(1)
    .max(14)
    .describe("die Mahlzeiten, deren Gericht aus dem Plan soll"),
});

export const BuchInput = z.object({
  titel: z.string().trim().min(1).max(200).describe("Titel des Kochbuchs, ohne Untertitel"),
  autoren: z.array(z.string()).max(6).describe("Autorinnen und Autoren; leer, wenn unbekannt"),
  isbn: z.string().nullable().describe("ISBN-10 oder ISBN-13, z. B. vom Foto der Rückseite; sonst null"),
  verlag: z.string().nullable(),
  jahr: z.number().int().min(1800).max(2100).nullable(),
});

export type EinplanenInput = z.infer<typeof EinplanenInput>;
export type MehrereEinplanenInput = z.infer<typeof MehrereEinplanenInput>;
export type AnwesenheitInput = z.infer<typeof AnwesenheitInput>;
export type NotizInput = z.infer<typeof NotizInput>;
export type EntwurfInput = z.infer<typeof EntwurfInput>;
export type BuchInput = z.infer<typeof BuchInput>;
export type GerichteEntfernenInput = z.infer<typeof GerichteEntfernenInput>;

/** Namen der Werkzeuge, die erst nach „Übernehmen“ im Browser schreiben */
export const WRITE_TOOLS = ["einplanen", "mehrere_einplanen", "anwesenheit_setzen", "notiz_hinzufuegen", "rezept_entwurf_oeffnen", "buch_hinzufuegen", "gerichte_entfernen"] as const;
export type WriteTool = (typeof WRITE_TOOLS)[number];

/** Kontext der Seite, von der aus der Assistent geöffnet wurde */
export interface AssistantContext {
  rezept_id?: string;
  rezept_titel?: string;
}
