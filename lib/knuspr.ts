// Knuspr-Bestellung über die offizielle Knuspr-KI-Anbindung in Claude oder ChatGPT.
// Knuspr lässt seinen MCP-Server nur von freigegebenen Apps nutzen, nicht von
// dieser Website. Deshalb öffnen wir dort einen vorbereiteten Auftrag; die KI
// legt die Liste in den Warenkorb, bestellt wird selbst in der Knuspr-App.

export function knusprPrompt(lines: string[]): string {
  return [
    "Bitte lege über Knuspr diese Einkaufsliste in meinen Warenkorb.",
    "Wähle für jede Zeile ein passendes Produkt in ausreichender Menge (lieber die nächstgrößere Packung als zu wenig).",
    "Nicht bestellen und nichts aus dem Warenkorb entfernen. Sag mir am Ende kurz, was du nicht gefunden hast.",
    "",
    ...lines.map((l) => `- ${l}`),
  ].join("\n");
}

export const knusprLinks = (prompt: string) => ({
  claude: `https://claude.ai/new?q=${encodeURIComponent(prompt)}`,
  chatgpt: `https://chatgpt.com/?q=${encodeURIComponent(prompt)}`,
});
