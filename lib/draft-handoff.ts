// Übergibt einen Rezeptentwurf an /rezepte/neu (z. B. vom Assistenten).
// sessionStorage: bleibt im Tab, verschwindet beim Schließen.

import type { RecipeDraft } from "./markdown";

const KEY = "ep-recipe-draft";

export interface PendingDraft {
  draft: RecipeDraft;
  notice: string;
}

export function stashDraft(p: PendingDraft) {
  try {
    sessionStorage.setItem(KEY, JSON.stringify(p));
  } catch {
    // privater Modus o. Ä. – dann eben ohne Vorbefüllung
  }
}

export function peekDraft(): PendingDraft | null {
  try {
    const raw = sessionStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as PendingDraft) : null;
  } catch {
    return null;
  }
}

export function clearDraft() {
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    // egal
  }
}
