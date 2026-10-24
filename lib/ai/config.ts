// KI-Konfiguration aus Umgebungsvariablen (nur serverseitig ausgewertet).
// Anbieter und Modelle lassen sich ohne Codeänderung tauschen.

export type AiProvider = "anthropic" | "openai-compatible" | "mock" | "off";
export type ModelKind = "text" | "vision" | "strong";

export interface AiPrices {
  /** USD pro Million Eingabe-Tokens */
  inUsdPerM: number;
  /** USD pro Million Ausgabe-Tokens */
  outUsdPerM: number;
  usdToEur: number;
}

export interface AiConfig {
  provider: AiProvider;
  enabled: boolean;
  /** Grund, warum die KI aus ist (für die Oberfläche) */
  reason: string | null;
  models: Record<ModelKind, string>;
  apiKey: string | null;
  baseURL: string | null;
  limits: { dailyCallsPerMember: number; monthlyBudgetEur: number };
  prices: AiPrices;
}

export const DEFAULT_MODEL = "claude-haiku-5-5";

type Env = Record<string, string | undefined>;

const str = (v: string | undefined) => (v && v.trim() ? v.trim() : null);
const num = (v: string | undefined, fallback: number) => {
  const n = Number(v);
  return v !== undefined && v.trim() !== "" && Number.isFinite(n) && n >= 0 ? n : fallback;
};

export function readAiConfig(env: Env = process.env): AiConfig {
  const apiKey = str(env.LLM_API_KEY);
  const baseURL = str(env.LLM_BASE_URL);
  const raw = str(env.LLM_PROVIDER)?.toLowerCase();
  const provider: AiProvider =
    raw === "anthropic" || raw === "openai-compatible" || raw === "mock" || raw === "off" ? raw : "anthropic";

  const text = str(env.LLM_MODEL) ?? (provider === "anthropic" || provider === "mock" ? DEFAULT_MODEL : "");
  const vision = str(env.LLM_VISION_MODEL) ?? text;
  const strong = str(env.LLM_MODEL_STRONG) ?? vision;

  let reason: string | null = null;
  if (provider === "off") reason = "Die KI ist ausgeschaltet.";
  else if (provider === "anthropic" && !apiKey) reason = "Es ist noch kein API-Schlüssel hinterlegt.";
  else if (provider === "openai-compatible" && (!baseURL || !text)) reason = "Für den OpenAI-kompatiblen Anbieter fehlen LLM_BASE_URL oder LLM_MODEL.";

  return {
    provider,
    enabled: reason === null,
    reason,
    models: { text, vision, strong },
    apiKey,
    baseURL,
    limits: {
      dailyCallsPerMember: num(env.AI_DAILY_CALL_LIMIT, 50),
      monthlyBudgetEur: num(env.AI_MONTHLY_BUDGET_EUR, 5),
    },
    prices: {
      // Standard: Claude Haiku 5.5 (Prompts bis 100K Tokens)
      inUsdPerM: num(env.AI_PRICE_IN_USD_PER_M, 0.1),
      outUsdPerM: num(env.AI_PRICE_OUT_USD_PER_M, 0.5),
      usdToEur: num(env.AI_USD_EUR, 0.92),
    },
  };
}
