import "server-only";
import { AiError } from "./guard";
import type { RecipeDraft } from "../markdown";

export const MAX_IMPORT_BYTES = 4_300_000;
export interface ImportImage { data: string; mediaType: string }

/** Bound the JSON before parsing or allocating decoded image buffers. */
export async function readImportBody(request: Request, maxBytes = MAX_IMPORT_BYTES): Promise<Record<string, unknown>> {
  const tooLarge = () => new AiError(maxBytes === MAX_IMPORT_BYTES
    ? "Die Fotos sind zusammen zu groß. Bitte weniger Fotos auswählen."
    : "Die Importanfrage ist zu groß.", 413, "bad-request");
  if (Number(request.headers.get("content-length")) > maxBytes) throw tooLarge();
  const reader = request.body?.getReader();
  if (!reader) throw new AiError("Bitte Importdaten angeben.", 400, "bad-request");
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > maxBytes) {
      await reader.cancel();
      throw tooLarge();
    }
    chunks.push(value);
  }
  try {
    const body = JSON.parse(new TextDecoder().decode(Buffer.concat(chunks)));
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
    return body;
  } catch { throw new AiError("Die Importdaten konnten nicht gelesen werden.", 400, "bad-request"); }
}

export function importImages(value: unknown, required = false): ImportImage[] {
  if (value === undefined && !required) return [];
  if (!Array.isArray(value) || value.length > 3 || required && !value.length) throw new AiError("Bitte 1 bis 3 Fotos auswählen.", 400, "bad-request");
  let total = 0;
  return value.map((image: unknown) => {
    const i = image as Partial<ImportImage> | null;
    if (typeof i?.data !== "string" || typeof i.mediaType !== "string" || !i.data.length || i.data.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(i.data)) throw new AiError("Ein Foto enthält ungültige Bilddaten.", 400, "bad-request");
    total += i.data.length;
    if (i.data.length > 4_000_000 || total > MAX_IMPORT_BYTES - 40_000) throw new AiError("Die Fotos sind zusammen zu groß.", 413, "bad-request");
    const bytes = Buffer.from(i.data.slice(0, 32), "base64");
    const type = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff ? "image/jpeg"
      : bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ? "image/png"
      : bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP" ? "image/webp"
      : /^GIF8[79]a/.test(bytes.toString("ascii", 0, 6)) ? "image/gif" : null;
    if (!type || type !== i.mediaType) throw new AiError("Dieses Bildformat wird nicht unterstützt. Bitte JPEG, PNG oder WebP auswählen.", 400, "bad-request");
    return { data: i.data, mediaType: i.mediaType };
  });
}

export function assertRecipeDraft(draft: RecipeDraft): void {
  if (!draft.title || !draft.ingredients.length && !draft.steps.length) throw new AiError("Es wurde kein Rezept mit Zutaten oder Zubereitung erkannt. Bitte Beschreibung oder Fotos ergänzen.", 422, "bad-request");
}
