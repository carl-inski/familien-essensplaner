import { describe, expect, it, vi } from "vitest";
import { inBackground } from "../lib/background";

// Nachbildung eines Supabase-Builders: läuft erst, wenn .then() aufgerufen wird
type Result = { error: { message: string } | null };

function lazyQuery(result: Result) {
  const run = vi.fn(async () => result);
  const query: PromiseLike<Result> = {
    then: (ok, err) => run().then(ok, err),
  };
  return { run, query };
}

describe("inBackground", () => {
  it("schickt eine lazy Abfrage wirklich ab", async () => {
    const { run, query } = lazyQuery({ error: null });
    inBackground(query);
    await Promise.resolve();
    expect(run).toHaveBeenCalledOnce();
  });
  it("meldet Fehler, ohne zu werfen", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { query } = lazyQuery({ error: { message: "kaputt" } });
    inBackground(query, "Test");
    await new Promise((r) => setTimeout(r, 0));
    expect(warn).toHaveBeenCalledWith("[Test]", "kaputt");
    warn.mockRestore();
  });
});
