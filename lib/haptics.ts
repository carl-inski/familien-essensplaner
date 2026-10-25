// Leichte Haptik auf dem Handy.
// Android: Vibration API. iPhone: Safari kennt sie nicht – ein versteckter
// iOS-Schalter (<input type="checkbox" switch>, ab iOS 18) gibt beim Umschalten
// dasselbe kurze Feedback wie native Schalter.

export type HapticKind = "light" | "medium" | "success" | "warning" | "error";

const PATTERN: Record<HapticKind, number | number[]> = {
  light: 8,
  medium: 16,
  success: [10, 70, 14],
  warning: [18, 90, 18],
  error: [24, 60, 24, 60, 24],
};

const STORAGE_KEY = "ep-haptics";

export function hapticsEnabled(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) !== "off";
  } catch {
    return true;
  }
}

export function setHapticsEnabled(on: boolean) {
  try {
    localStorage.setItem(STORAGE_KEY, on ? "on" : "off");
  } catch {
    // privater Modus – gilt dann nur bis zum Neuladen nicht
  }
}

const isIOS = () =>
  typeof navigator !== "undefined" && (/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1));

let iosSwitch: HTMLLabelElement | null = null;

/** Der versteckte Schalter; Klicks darauf sind keine Nutzer-Klicks */
export function isHapticSwitch(el: EventTarget | null): boolean {
  return !!iosSwitch && el instanceof Node && iosSwitch.contains(el);
}

function iosTap() {
  if (!iosSwitch) {
    iosSwitch = document.createElement("label");
    iosSwitch.setAttribute("aria-hidden", "true");
    iosSwitch.style.cssText = "position:fixed;left:-100px;top:0;width:1px;height:1px;opacity:0;pointer-events:none;overflow:hidden";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.setAttribute("switch", "");
    input.tabIndex = -1;
    iosSwitch.appendChild(input);
    document.body.appendChild(iosSwitch);
  }
  iosSwitch.click();
}

export function haptic(kind: HapticKind = "light") {
  if (typeof window === "undefined" || !hapticsEnabled()) return;
  // Nur auf Touch-Geräten – am Computer gibt es nichts zu spüren
  if (!window.matchMedia?.("(pointer: coarse)").matches) return;
  if (typeof navigator.vibrate === "function") {
    navigator.vibrate(PATTERN[kind]);
    return;
  }
  if (isIOS()) {
    iosTap();
    // Erfolg und Fehler: zweiter, kurz versetzter Impuls
    if (kind === "success" || kind === "warning" || kind === "error") setTimeout(iosTap, 90);
  }
}
