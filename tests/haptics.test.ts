import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { haptic, hapticsEnabled, setHapticsEnabled } from "../lib/haptics";

describe("Haptik", () => {
  const vibrate = vi.fn();
  let store: Record<string, string>;
  let coarse = true;
  beforeEach(() => {
    store = {};
    coarse = true;
    vibrate.mockReset();
    vi.stubGlobal("window", { matchMedia: () => ({ matches: coarse }) });
    vi.stubGlobal("navigator", { vibrate, userAgent: "Android", platform: "Linux", maxTouchPoints: 5 });
    vi.stubGlobal("localStorage", { getItem: (k: string) => store[k] ?? null, setItem: (k: string, v: string) => (store[k] = v) });
  });
  afterEach(() => vi.unstubAllGlobals());

  it("vibriert kurz auf Android, Erfolg als Doppelimpuls", () => {
    haptic("light");
    haptic("success");
    expect(vibrate).toHaveBeenNthCalledWith(1, 8);
    expect(vibrate).toHaveBeenNthCalledWith(2, [10, 70, 14]);
  });
  it("lässt sich im Profil abschalten", () => {
    expect(hapticsEnabled()).toBe(true);
    setHapticsEnabled(false);
    haptic("light");
    expect(vibrate).not.toHaveBeenCalled();
  });
  it("bleibt am Computer still", () => {
    coarse = false;
    haptic("error");
    expect(vibrate).not.toHaveBeenCalled();
  });
});
