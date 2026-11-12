import { convertToModelMessages, createUIMessageStreamResponse, stepCountIs, streamText, toUIMessageStream, type UIMessage } from "ai";
import type { NextRequest } from "next/server";
import { WEEKDAY_LONG, todayBerlin, weekdayIndex } from "@/lib/dates";
import type { AssistantContext } from "@/lib/ai/assistant-schemas";
import { assistantTools, calendarHint } from "@/lib/ai/assistant-tools";
import { aiErrorResponse, aiGuard, logUsage } from "@/lib/ai/guard";
import { system } from "@/lib/ai/prompts";
import { aiModel, aiProviderOptions } from "@/lib/ai/provider";
import { toTokenUsage } from "@/lib/ai/run";
import type { Member } from "@/lib/types";

// Der Assistent im KI-Tab: liest selbst (Werkzeuge mit execute), schlägt
// Änderungen nur vor – geschrieben wird erst nach „Übernehmen“ im Browser.

export const maxDuration = 60;

const MAX_MESSAGES = 24;

function assistantPrompt(today: string, me: Member, members: string[], kontext: AssistantContext | undefined) {
  return system(`Du bist der Küchenassistent der Familie im Essensplaner. Du sprichst mit ${me.name}.
Haushalt: ${members.join(", ")}.
Heute ist ${WEEKDAY_LONG[weekdayIndex(today)]}, ${today}. Kalender: ${calendarHint(today)}.
Pro Tag gibt es Mittag- und Abendessen.

So arbeitest du:
- Nutze die Werkzeuge, statt zu raten: rezepte_suchen, rezept_lesen, woche_lesen, lange_nicht_gegessen, regal, einkaufsliste.
- Woche füllen oder „was kochen wir die nächsten Tage?“: erst vorschlaege_finden, dann alle Vorschläge zusammen mit mehrere_einplanen (eine Karte). Begründe jeden in wenigen Worten (z. B. „lange nicht gegessen“, „schnell, nur 2 essen mit“).
- „Was koche ich mit …?“ oder Reste: erst rezepte_mit_zutaten, dann die besten 2–3 Treffer nennen (Sammlung vor Regal). Passt nichts, schlag eine eigene Idee vor und biete rezept_entwurf_oeffnen an.
- Lehnt der Nutzer Vorschläge ab, frag kurz nach dem Grund und berücksichtige ihn.
- Ändern kannst du nur über einplanen, mehrere_einplanen, anwesenheit_setzen, notiz_hinzufuegen, gerichte_entfernen, plan_aendern, rezept_entwurf_oeffnen und buch_hinzufuegen. Der Nutzer sieht dann eine Karte mit „Übernehmen“. Schreib dazu höchstens einen kurzen Satz und behaupte nicht, es sei schon erledigt. Ob er übernommen oder abgelehnt hat, siehst du später im Ergebnis des Werkzeugs.
- Hausregeln beim Planen: höchstens 1 Fleischgericht unter 3 aufeinanderfolgenden Gerichten; ein Rezept frühestens 14 Tage nach dem letzten Kochen wieder; abends keine Snacks oder Süßspeisen als Hauptgericht. Prüfe vorher mit woche_lesen, was schon geplant ist.
- Geplantes ändern: Ein anderes Gericht für eine Mahlzeit einfach mit einplanen bzw. mehrere_einplanen vorschlagen – das bisherige wird ersetzt. Gerichte löschen mit gerichte_entfernen. Ein Gericht auf einen anderen Tag legen oder wegen Auswärtsessen ausfallen lassen: plan_aendern – nicht löschen und neu einplanen, sonst gehen die schon gekauften Zutaten verloren. Vorher mit woche_lesen nachsehen, was dort steht.
- Kochbuch ins Regal („füg … hinzu“, Foto eines Buchs): erst regal prüfen, dann buch_hinzufuegen. Eine ISBN vom Foto abschreiben, wenn sie lesbar ist; nichts erfinden.
- Bevorzuge Rezepte aus der Sammlung. Neue Rezeptideen nur auf Nachfrage oder wenn nichts passt – dann als rezept_entwurf_oeffnen.
- Verweise auf Rezepte als Markdown-Link [Titel](/rezepte/<id>).
- Antworte kurz: 1–4 Sätze oder eine knappe Liste. Keine Überschriften.${kontext?.rezept_id ? `\n\nDer Nutzer kommt von der Rezeptseite „${kontext.rezept_titel ?? ""}“ (id ${kontext.rezept_id}). „Das“ oder „dieses Rezept“ meint dieses Rezept.` : ""}`);
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await aiGuard();
    const body = (await request.json()) as { messages: UIMessage[]; kontext?: AssistantContext };
    const messages = (body.messages ?? []).slice(-MAX_MESSAGES);
    const hasImage = messages.some((m) => m.role === "user" && m.parts.some((p) => p.type === "file"));
    const kind = hasImage ? "vision" : "text";
    const today = todayBerlin();
    const { data: members } = await ctx.sb.from("ep_members").select("name").order("position");

    const result = streamText({
      model: aiModel(ctx.cfg, kind, (q) => `Testmodus: Du hast „${q.slice(0, 80)}“ gefragt. Im Testmodus gibt es keine echten Antworten.`),
      system: assistantPrompt(today, ctx.member, ((members ?? []) as { name: string }[]).map((m) => m.name), body.kontext),
      messages: await convertToModelMessages(messages),
      tools: assistantTools(ctx, today),
      stopWhen: stepCountIs(6),
      providerOptions: aiProviderOptions(ctx.cfg, "low"),
      maxRetries: 1,
      onEnd: async ({ usage }) => {
        await logUsage(ctx, { feature: "assistent", model: ctx.cfg.models[kind], usage: toTokenUsage(usage) });
      },
    });

    return createUIMessageStreamResponse({
      stream: toUIMessageStream({
        stream: result.stream,
        onError: (e) => {
          console.error("[ai] chat", e);
          return "Die KI hat gerade nicht geantwortet. Bitte nochmal versuchen.";
        },
      }),
    });
  } catch (e) {
    return aiErrorResponse(e);
  }
}
