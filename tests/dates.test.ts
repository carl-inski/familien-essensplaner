import { describe, expect, it } from "vitest";
import { daysFrom, formatStampDE, startLabel } from "../lib/dates";

describe("Planansicht ab heute", () => {
  const today = "2026-10-25"; // Sonntag
  it("zeigt sieben Tage ab dem Starttag, über Monats- und Jahresgrenzen", () => {
    expect(daysFrom(today)).toEqual(["2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31"]);
    expect(daysFrom("2026-12-29").slice(2, 5)).toEqual(["2026-12-31", "2027-01-01", "2027-01-02"]);
  });
  it("benennt den Start relativ zu heute", () => {
    expect(startLabel(today, today)).toBe("Ab heute");
    expect(startLabel("2026-10-26", today)).toBe("Ab morgen");
    expect(startLabel("2026-11-01", today)).toBe("Ab Sonntag, 1. November");
    expect(startLabel("2026-10-18", today)).toBe("Ab Sonntag, 18. Oktober");
  });
});

describe("Zeitpunkte", () => {
  it("zeigt den Tag nach deutscher Zeit, auch kurz nach Mitternacht", () => {
    // 23:15 UTC am 12. ist in Berlin schon der 13.
    expect(formatStampDE("2026-11-12T23:15:00Z")).toBe("13. Nov.");
    expect(formatStampDE("2026-11-12T12:00:00Z")).toBe("12. Nov.");
  });
});
