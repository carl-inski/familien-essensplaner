// Kleine Helfer für die Anzeige von Text.

/**
 * Ergänzungsstrich am Wortanfang („und -unterschenkel“) nicht vom Wort trennen:
 * sonst bricht die Zeile hinter dem Strich um. U+2011 ist ein geschützter Bindestrich.
 */
export function keepCompoundTogether(text: string): string {
  return text.replace(/(^|\s)-(?=\p{L})/gu, "$1‑");
}
