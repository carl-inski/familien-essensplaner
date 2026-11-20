// Angaben zum Betreiber für Impressum und Datenschutz. Bewusst aus Umgebungsvariablen,
// damit keine Adresse im Code steht. Fehlt etwas, zeigen die Seiten „[bitte ergänzen]“ –
// vor dem öffentlichen Start müssen alle Felder gesetzt sein (siehe docs/LAUNCH.md).

const MISSING = "[bitte ergänzen]";

export interface Operator {
  name: string;
  address: string[];
  email: string;
  complete: boolean;
}

export function operator(): Operator {
  const name = process.env.NEXT_PUBLIC_LEGAL_NAME?.trim();
  const address = process.env.NEXT_PUBLIC_LEGAL_ADDRESS?.trim();
  const email = process.env.NEXT_PUBLIC_LEGAL_EMAIL?.trim();
  return {
    name: name || MISSING,
    // Zeilen mit „|“ getrennt, z. B. "Musterstraße 1|12345 Musterstadt"
    address: address ? address.split("|").map((l) => l.trim()).filter(Boolean) : [MISSING],
    email: email || MISSING,
    complete: !!(name && address && email),
  };
}
