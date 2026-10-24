import { describe, expect, it } from "vitest";
import { readAiConfig } from "../lib/ai/config";
import { estimateCostEur, limitMessage } from "../lib/ai/cost";

describe("readAiConfig", () => {
  it("ist ohne Schlüssel nicht eingerichtet", () => {
    const cfg = readAiConfig({});
    expect(cfg.provider).toBe("anthropic");
    expect(cfg.enabled).toBe(false);
    expect(cfg.reason).toMatch(/API-Schlüssel/);
  });

  it("nimmt Haiku 5.5 als Standard für alle Modelle", () => {
    const cfg = readAiConfig({ LLM_API_KEY: "sk-test" });
    expect(cfg.enabled).toBe(true);
    expect(cfg.models).toEqual({ text: "claude-haiku-5-5", vision: "claude-haiku-5-5", strong: "claude-haiku-5-5" });
  });

  it("Bild- und Stark-Modell fallen zurück", () => {
    const cfg = readAiConfig({ LLM_API_KEY: "k", LLM_MODEL: "a", LLM_VISION_MODEL: "b" });
    expect(cfg.models).toEqual({ text: "a", vision: "b", strong: "b" });
  });

  it("OpenAI-kompatibel braucht Basis-URL und Modell", () => {
    expect(readAiConfig({ LLM_PROVIDER: "openai-compatible", LLM_API_KEY: "k" }).enabled).toBe(false);
    const ok = readAiConfig({ LLM_PROVIDER: "openai-compatible", LLM_BASE_URL: "https://api.groq.com/openai/v1", LLM_MODEL: "llama" });
    expect(ok.enabled).toBe(true);
    expect(ok.models.text).toBe("llama");
  });

  it("OpenRouter: Basis-URL vorbelegt, Modell und Schlüssel nötig", () => {
    expect(readAiConfig({ LLM_PROVIDER: "openrouter", LLM_API_KEY: "k" }).reason).toMatch(/LLM_MODEL/);
    expect(readAiConfig({ LLM_PROVIDER: "openrouter", LLM_MODEL: "x/y" }).enabled).toBe(false);
    const ok = readAiConfig({ LLM_PROVIDER: "openrouter", LLM_API_KEY: "k", LLM_MODEL: "x/y" });
    expect(ok.enabled).toBe(true);
    expect(ok.baseURL).toBe("https://openrouter.ai/api/v1");
  });

  it("Mock braucht keinen Schlüssel, off schaltet ab", () => {
    expect(readAiConfig({ LLM_PROVIDER: "mock" }).enabled).toBe(true);
    expect(readAiConfig({ LLM_PROVIDER: "off", LLM_API_KEY: "k" }).enabled).toBe(false);
  });

  it("liest Limits und ignoriert Unsinn", () => {
    const cfg = readAiConfig({ AI_DAILY_CALL_LIMIT: "10", AI_MONTHLY_BUDGET_EUR: "abc" });
    expect(cfg.limits).toEqual({ dailyCallsPerMember: 10, monthlyBudgetEur: 5 });
  });
});

describe("estimateCostEur", () => {
  const prices = { inUsdPerM: 0.1, outUsdPerM: 0.5, usdToEur: 1 };

  it("rechnet Ein- und Ausgabe", () => {
    expect(estimateCostEur({ inputTokens: 1_000_000, outputTokens: 1_000_000 }, prices)).toBeCloseTo(0.6);
  });

  it("Cache-Lesen kostet ein Zehntel, Cache-Schreiben 1,25-fach", () => {
    const c = estimateCostEur({ inputTokens: 1_000_000, cacheReadTokens: 500_000, cacheWriteTokens: 500_000 }, prices);
    expect(c).toBeCloseTo(0.05 * 0.1 + 0.05 * 1.25);
  });

  it("ein typischer Aufruf kostet Bruchteile eines Cents", () => {
    expect(estimateCostEur({ inputTokens: 3000, outputTokens: 600 }, { ...prices, usdToEur: 0.92 })).toBeLessThan(0.001);
  });
});

describe("limitMessage", () => {
  const limits = { dailyCallsPerMember: 50, monthlyBudgetEur: 5 };
  it("lässt durch, solange beides frei ist", () => {
    expect(limitMessage({ callsToday: 49, costMonthEur: 4.99 }, limits)).toBeNull();
  });
  it("stoppt beim Tageslimit", () => {
    expect(limitMessage({ callsToday: 50, costMonthEur: 0 }, limits)).toMatch(/heute/);
  });
  it("stoppt beim Monatsbudget", () => {
    expect(limitMessage({ callsToday: 0, costMonthEur: 5 }, limits)).toMatch(/Budget/);
  });
});
