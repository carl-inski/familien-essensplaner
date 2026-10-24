import "server-only";
import { createAnthropic } from "@ai-sdk/anthropic";
import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import { simulateReadableStream, type LanguageModel } from "ai";
import { MockLanguageModelV4 } from "ai/test";
import type { AiConfig, ModelKind } from "./config";

/** Feste Antwort im Mock-Modus; bekommt den Text der letzten Nutzernachricht */
export type MockReply = (lastUserText: string) => string;

export type Effort = "low" | "medium" | "high";

export function aiModel(cfg: AiConfig, kind: ModelKind, mock?: MockReply): LanguageModel {
  const id = cfg.models[kind];
  switch (cfg.provider) {
    case "anthropic":
      return createAnthropic({ apiKey: cfg.apiKey ?? undefined })(id);
    case "openrouter":
      return createOpenAICompatible({
        name: "openrouter",
        baseURL: cfg.baseURL!,
        apiKey: cfg.apiKey ?? undefined,
        includeUsage: true,
        // OpenRouter ordnet Anfragen damit der App zu (optional)
        headers: { "HTTP-Referer": process.env.NEXT_PUBLIC_SITE_URL ?? "https://familien-essensplaner.vercel.app", "X-Title": "Familien-Essensplaner" },
      })(id);
    case "openai-compatible":
      return createOpenAICompatible({ name: "llm", baseURL: cfg.baseURL!, apiKey: cfg.apiKey ?? undefined, includeUsage: true })(id);
    case "mock":
      return mockModel(mock ?? (() => "Das ist eine Testantwort (Mock-Modus)."));
    case "off":
      throw new Error("KI ist ausgeschaltet");
  }
}

/**
 * Anbieterspezifische Optionen. Haiku 5.5 denkt standardmäßig mit;
 * für Extraktion und kurze Antworten reicht niedriger Aufwand.
 */
export function aiProviderOptions(cfg: AiConfig, effort: Effort = "low") {
  if (cfg.provider !== "anthropic") return undefined;
  return { anthropic: { effort } };
}

const USAGE = {
  inputTokens: { total: 120, noCache: 120, cacheRead: undefined, cacheWrite: undefined },
  outputTokens: { total: 40, text: 40, reasoning: undefined },
};

function lastUserText(prompt: { role: string; content: unknown }[]): string {
  for (let i = prompt.length - 1; i >= 0; i--) {
    const m = prompt[i];
    if (m.role !== "user") continue;
    if (typeof m.content === "string") return m.content;
    if (Array.isArray(m.content)) {
      return m.content
        .filter((p): p is { type: "text"; text: string } => p?.type === "text")
        .map((p) => p.text)
        .join("\n");
    }
  }
  return "";
}

function mockModel(reply: MockReply): LanguageModel {
  return new MockLanguageModelV4({
    provider: "mock",
    modelId: "mock",
    doGenerate: async ({ prompt }) => ({
      content: [{ type: "text", text: reply(lastUserText(prompt)) }],
      finishReason: { unified: "stop", raw: undefined },
      usage: USAGE,
      warnings: [],
    }),
    doStream: async ({ prompt }) => {
      const text = reply(lastUserText(prompt));
      return {
        stream: simulateReadableStream({
          chunks: [
            { type: "text-start", id: "t" },
            ...text.split(/(?<=\s)/).map((delta) => ({ type: "text-delta" as const, id: "t", delta })),
            { type: "text-end", id: "t" },
            { type: "finish", finishReason: { unified: "stop", raw: undefined }, usage: USAGE },
          ],
        }),
      };
    },
  });
}
