import { describe, expect, it } from "vitest";
import { relativeWeekLabel } from "../lib/dates";

describe("relativeWeekLabel", () => {
  const today = "2026-10-25"; // Sonntag, KW 43
  it("benennt aktuelle, nächste und letzte Woche", () => {
    expect(relativeWeekLabel("2026-W43", today)).toBe("Aktuelle Woche");
    expect(relativeWeekLabel("2026-W44", today)).toBe("Nächste Woche");
    expect(relativeWeekLabel("2026-W42", today)).toBe("Letzte Woche");
  });
  it("zeigt sonst die Kalenderwoche", () => {
    expect(relativeWeekLabel("2026-W46", today)).toBe("KW 46");
    expect(relativeWeekLabel("2026-W40", today)).toBe("KW 40");
  });
  it("funktioniert über den Jahreswechsel", () => {
    expect(relativeWeekLabel("2027-W01", "2026-12-30")).toBe("Nächste Woche");
    expect(relativeWeekLabel("2026-W53", "2027-01-05")).toBe("Letzte Woche");
  });
});
