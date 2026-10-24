import "server-only";
import { lookup } from "node:dns/promises";
import { isIP } from "node:net";
import { AiError } from "./guard";

// Lädt eine fremde Webseite für den Rezept-Import. Nur http(s), keine internen
// Adressen (auch nicht über Weiterleitungen), Zeit- und Größenlimit.

const MAX_BYTES = 3_000_000;

function isPrivate(ip: string): boolean {
  if (isIP(ip) === 6) {
    const v = ip.toLowerCase();
    if (v.startsWith("::ffff:")) return isPrivate(v.slice(7));
    return v === "::1" || v === "::" || v.startsWith("fc") || v.startsWith("fd") || v.startsWith("fe8") || v.startsWith("fe9") || v.startsWith("fea") || v.startsWith("feb");
  }
  const [a, b] = ip.split(".").map(Number);
  return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127) || a >= 224;
}

async function assertPublic(url: URL) {
  if (url.protocol !== "https:" && url.protocol !== "http:") throw new AiError("Bitte einen http- oder https-Link angeben.", 400, "bad-request");
  if (url.username || url.password) throw new AiError("Links mit Zugangsdaten werden nicht geladen.", 400, "bad-request");
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".local") || host.endsWith(".internal")) throw new AiError("Diese Adresse ist nicht erreichbar.", 400, "bad-request");
  const ips = isIP(host) ? [host] : (await lookup(host, { all: true }).catch(() => [])).map((r) => r.address);
  if (!ips.length) throw new AiError("Die Seite wurde nicht gefunden.", 400, "bad-request");
  if (ips.some(isPrivate)) throw new AiError("Diese Adresse ist nicht erreichbar.", 400, "bad-request");
}

export function parseUserUrl(raw: unknown): URL {
  const s = typeof raw === "string" ? raw.trim() : "";
  try {
    return new URL(/^https?:\/\//i.test(s) ? s : `https://${s}`);
  } catch {
    throw new AiError("Das sieht nicht nach einem Link aus.", 400, "bad-request");
  }
}

export async function fetchPage(start: URL): Promise<{ html: string; url: URL }> {
  let url = start;
  for (let hop = 0; hop < 4; hop++) {
    await assertPublic(url);
    const get = () =>
      fetch(url, {
        redirect: "manual",
        signal: AbortSignal.timeout(10_000),
        headers: {
          "User-Agent": "Mozilla/5.0 (compatible; Familien-Essensplaner/1.0; Rezept-Import)",
          Accept: "text/html,application/xhtml+xml",
          "Accept-Language": "de-DE,de;q=0.9,en;q=0.5",
        },
      });
    // Ein Netzfehler darf einmal passieren (z. B. abgebrochene Verbindung)
    const res = await get()
      .catch(get)
      .catch(() => {
        throw new AiError("Die Seite hat nicht geantwortet.", 502, "failed");
      });
    if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
      url = new URL(res.headers.get("location")!, url);
      continue;
    }
    if (res.status === 401 || res.status === 403) throw new AiError("Die Seite lässt keine automatischen Abrufe zu. Rezept dort kopieren oder ein Foto machen.", 422, "bad-request");
    if (!res.ok) throw new AiError(`Die Seite antwortet mit Fehler ${res.status}.`, 502, "failed");
    const type = res.headers.get("content-type") ?? "";
    if (!/html|xml|text\/plain/i.test(type)) throw new AiError("Unter dem Link liegt keine Webseite.", 400, "bad-request");
    const reader = res.body?.getReader();
    if (!reader) return { html: "", url };
    const chunks: Uint8Array[] = [];
    let size = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BYTES) {
        await reader.cancel();
        break;
      }
      chunks.push(value);
    }
    return { html: new TextDecoder().decode(Buffer.concat(chunks)), url };
  }
  throw new AiError("Zu viele Weiterleitungen.", 400, "bad-request");
}
