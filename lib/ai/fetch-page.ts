import "server-only";
import { lookup } from "node:dns/promises";
import { request as httpRequest, type IncomingHttpHeaders } from "node:http";
import { request as httpsRequest } from "node:https";
import { isIP } from "node:net";
import { createBrotliDecompress, createUnzip } from "node:zlib";
import { parseImportUrl } from "../recipe-source";
import { AiError } from "./guard";
import { importImages } from "./import-input";
import { socialCoverUrl, type SocialPlatform } from "../recipe-source";

const MAX_BYTES = 3_000_000;

export function isPrivateAddress(ip: string): boolean {
  if (isIP(ip) === 6) {
    const v = new URL(`http://[${ip}]/`).hostname.slice(1, -1).toLowerCase();
    const mapped = v.match(/^::ffff:([\da-f]+):([\da-f]+)$/);
    if (mapped) {
      const n = Number.parseInt(mapped[1], 16) * 65536 + Number.parseInt(mapped[2], 16);
      return isPrivateAddress([n >>> 24, (n >>> 16) & 255, (n >>> 8) & 255, n & 255].join("."));
    }
    return !/^[23]/.test(v) || /^2001:(?:db8|0):|^2001::|^2002:/.test(v);
  }
  if (isIP(ip) !== 4) return true;
  const [a, b, c] = ip.split(".").map(Number);
  return a === 0 || a === 10 || a === 127 || a >= 224 || (a === 169 && b === 254)
    || (a === 172 && b >= 16 && b <= 31) || (a === 192 && (b === 168 || b === 0 || b === 88 && c === 99))
    || (a === 100 && b >= 64 && b <= 127) || (a === 198 && (b === 18 || b === 19 || b === 51 && c === 100))
    || (a === 203 && b === 0 && c === 113);
}

async function publicAddress(url: URL, signal: AbortSignal) {
  if (!["https:", "http:"].includes(url.protocol) || url.username || url.password || url.port && !["80", "443"].includes(url.port)) {
    throw new AiError("Bitte einen öffentlichen http- oder https-Link ohne Zugangsdaten verwenden.", 400, "bad-request");
  }
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (host === "localhost" || /\.(?:localhost|local|internal)$/.test(host)) throw new AiError("Diese Adresse ist nicht erreichbar.", 400, "bad-request");
  const addresses = isIP(host) ? [{ address: host, family: isIP(host) }] : await new Promise<{ address: string; family: number }[]>((resolve, reject) => {
    const abort = () => reject(new AiError("Die Seite hat nicht rechtzeitig geantwortet.", 504, "failed"));
    signal.addEventListener("abort", abort, { once: true });
    lookup(host, { all: true }).then(resolve, () => resolve([])).finally(() => signal.removeEventListener("abort", abort));
    if (signal.aborted) abort();
  });
  if (!addresses.length) throw new AiError("Die Seite wurde nicht gefunden.", 422, "bad-request");
  if (addresses.some((entry) => isPrivateAddress(entry.address))) throw new AiError("Diese Adresse ist nicht erreichbar.", 400, "bad-request");
  return addresses[0];
}

export function parseUserUrl(raw: unknown): URL {
  try { return parseImportUrl(raw); }
  catch (error) { throw new AiError((error as Error).message, 400, "bad-request"); }
}

async function readRemote(url: URL, signal: AbortSignal, image = false): Promise<{ bytes: Buffer; status: number; headers: IncomingHttpHeaders }> {
  const address = await publicAddress(url, signal);
  return new Promise((resolve, reject) => {
    const request = url.protocol === "https:" ? httpsRequest : httpRequest;
    const req = request(url, {
      signal,
      // Pin the checked IP; preserve the original Host and TLS SNI.
      lookup: (_hostname, options, callback) => {
        if (options.all) callback(null, [address]);
        else callback(null, address.address, address.family);
      },
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; Gnocchi/1.0; Recipe-Import)",
        Accept: image ? "image/jpeg,image/png,image/webp" : "text/html,application/xhtml+xml,application/json;q=0.9,text/plain;q=0.8",
        "Accept-Language": "de-DE,de;q=0.9,en;q=0.5",
        "Accept-Encoding": "identity",
      },
    }, (res) => {
      const status = res.statusCode ?? 502;
      if (status >= 300) {
        res.resume();
        resolve({ bytes: Buffer.alloc(0), status, headers: res.headers });
        return;
      }
      const encoding = res.headers["content-encoding"];
      const stream = encoding === "br" ? res.pipe(createBrotliDecompress()) : /gzip|deflate/.test(encoding ?? "") ? res.pipe(createUnzip()) : res;
      const chunks: Buffer[] = [];
      let size = 0;
      res.on("error", reject);
      stream.on("error", reject);
      stream.on("data", (chunk: Buffer) => {
        size += chunk.length;
        if (size > (image ? 1_500_000 : MAX_BYTES)) {
          reject(new AiError("Die Seite ist zu groß. Bitte Rezepttext oder Fotos ergänzen.", 413, "bad-request"));
          stream.destroy(); res.destroy(); req.destroy();
        } else chunks.push(chunk);
      });
      stream.on("end", () => resolve({ bytes: Buffer.concat(chunks), status, headers: res.headers }));
    });
    req.on("error", (error) => reject(error instanceof AiError ? error : new AiError("Die Seite hat nicht geantwortet. Bitte erneut versuchen oder Rezepttext ergänzen.", 502, "failed")));
    req.end();
  });
}

/** Redirects, DNS, decompressed size and total time are bounded for both HTML and oEmbed. */
export async function fetchPage(start: URL, options: { json?: boolean; captions?: boolean; timeoutMs?: number } = {}): Promise<{ html: string; url: URL }> {
  let url = start;
  const signal = AbortSignal.timeout(options.timeoutMs ?? 12_000);
  for (let hop = 0; hop < 6; hop++) {
    const res = await readRemote(url, signal);
    if (res.status >= 300 && res.status < 400 && res.headers.location) {
      url = new URL(res.headers.location, url);
      continue;
    }
    if ([401, 403, 429].includes(res.status)) throw new AiError("Die Seite blockiert den Abruf. Bitte Beschreibung kopieren oder Screenshots ergänzen.", 422, "bad-request");
    if (res.status < 200 || res.status >= 300) throw new AiError(`Die Seite antwortet mit Fehler ${res.status}.`, 422, "bad-request");
    const type = String(res.headers["content-type"] ?? "");
    if (!/html|xml|text\/plain/i.test(type) && !(options.json && /application\/json/i.test(type)) && !(options.captions && /vtt|subrip|srt|octet-stream/i.test(type))) throw new AiError("Unter dem Link liegt keine lesbare Webseite.", 422, "bad-request");
    const charset = /charset=["']?([^;\s"']+)/i.exec(type)?.[1] ?? "utf-8";
    let decoder: TextDecoder;
    try { decoder = new TextDecoder(charset); } catch { decoder = new TextDecoder(); }
    return { html: decoder.decode(res.bytes), url };
  }
  throw new AiError("Zu viele Weiterleitungen. Bitte den direkten Beitragslink verwenden.", 422, "bad-request");
}


/** Copy a small, publicly available cover into the draft before its URL expires. */
export async function fetchRecipeCover(start: URL, platform: SocialPlatform, timeoutMs: number) {
  const signal = AbortSignal.timeout(timeoutMs);
  let url = start;
  for (let hop = 0; hop < 3; hop++) {
    if (!socialCoverUrl(url.href, platform)) return undefined;
    const res = await readRemote(url, signal, true);
    if (res.status >= 300 && res.status < 400 && res.headers.location) {
      url = new URL(res.headers.location, url);
      continue;
    }
    const mediaType = String(res.headers["content-type"] ?? "").split(";")[0].trim().toLowerCase();
    if (res.status !== 200 || !["image/jpeg", "image/png", "image/webp"].includes(mediaType)) return undefined;
    return importImages([{ data: res.bytes.toString("base64"), mediaType }])[0];
  }
}
