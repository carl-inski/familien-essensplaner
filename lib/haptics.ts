// Leichte Haptik auf dem Handy.
// Android: Vibration API (navigator.vibrate) beim Tippen.
// iPhone: Safari kennt keine Vibration API. Ein nativer Schalter
// (<input type="checkbox" switch>, ab iOS 17.4/18) vibriert aber, wenn der Finger ihn
// wirklich umschaltet – ein Klick per Skript zählt nicht. Darum legen wir über jedes
// haptische Element ein unsichtbares <label>, das den echten Tipp an einen versteckten
// Schalter weitergibt (Vorgehen wie die Bibliothek „ios-haptics“). Deshalb gibt es auf
// dem iPhone nur Haptik direkt beim Tippen, nicht nachträglich (z. B. nach dem Speichern).

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
    // privater Modus – gilt dann nur bis zum Neuladen
  }
  if (typeof document !== "undefined") document.documentElement.dataset.haptics = on ? "on" : "off";
}

export const isIOS = () =>
  typeof navigator !== "undefined" && (/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1));

const coarse = () => typeof window !== "undefined" && !!window.matchMedia?.("(pointer: coarse)").matches;

/** Android: kurz vibrieren. iPhone: siehe attachIOSHaptic – hier nichts zu tun. */
export function haptic(kind: HapticKind = "light") {
  if (typeof window === "undefined" || !hapticsEnabled() || !coarse()) return;
  if (typeof navigator.vibrate === "function") navigator.vibrate(PATTERN[kind]);
}

/** Markiert die von uns eingefügten Etiketten (damit niemand sie doppelt einfügt) */
export const IOS_HAPTIC_ATTR = "data-haptic-trigger";

/**
 * iPhone: unsichtbares Etikett mit verstecktem Schalter über das Element legen.
 * Der echte Tipp landet auf dem Etikett, Safari schaltet den Schalter um und vibriert;
 * der Klick läuft wie gewohnt zum Element weiter.
 */
export function attachIOSHaptic(el: HTMLElement) {
  if (el.querySelector(`:scope > [${IOS_HAPTIC_ATTR}]`)) return;
  const label = document.createElement("label");
  label.setAttribute(IOS_HAPTIC_ATTR, "");
  label.setAttribute("aria-hidden", "true");
  label.className = "haptic-label";
  const sw = document.createElement("input");
  sw.type = "checkbox";
  sw.setAttribute("switch", "");
  sw.tabIndex = -1;
  sw.className = "haptic-switch";
  // Der Schalter-Klick soll nicht noch einmal bei den Klick-Handlern des Elements ankommen
  sw.addEventListener("click", (e) => e.stopPropagation());
  label.append(sw);
  // Links (Tabs): Next.js ruft beim Navigieren preventDefault() auf – das würde auch die
  // Weitergabe an den Schalter abbrechen. Darum endet der echte Klick am Etikett (Schalter
  // vibriert) und der Link bekommt einen eigenen Klick, mit dem Next.js navigiert.
  if (el instanceof HTMLAnchorElement) {
    label.addEventListener("click", (e) => {
      if (e.target !== label) return;
      e.stopPropagation();
      el.click();
    });
  }
  if (getComputedStyle(el).position === "static") el.style.position = "relative";
  el.append(label);
}

export const iosHapticsSupported = () => isIOS() && coarse();
