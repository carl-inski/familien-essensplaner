import { beforeEach, describe, expect, it, vi } from "vitest";
import { EventEmitter } from "node:events";
import type { IncomingMessage } from "node:http";
import { Readable } from "node:stream";

vi.mock("server-only", () => ({}));
vi.mock("../lib/ai/guard", () => ({ AiError: class extends Error { constructor(message: string, public status: number, public code: string) { super(message); } } }));
vi.mock("node:dns/promises", () => ({ lookup: vi.fn() }));
vi.mock("node:https", () => ({ request: vi.fn() }));
vi.mock("node:http", () => ({ request: vi.fn() }));
import { lookup } from "node:dns/promises";
import { request } from "node:https";
import { fetchPage, isPrivateAddress, parseUserUrl } from "../lib/ai/fetch-page";

beforeEach(() => { vi.resetAllMocks(); vi.mocked(lookup).mockResolvedValue([{ address: "93.184.216.34", family: 4 }] as never); });

describe("Sichere Linkabrufe", () => {
  it.each(["127.0.0.1", "10.1.2.3", "169.254.169.254", "100.64.0.1", "192.168.0.1", "::1", "::ffff:7f00:1", "::ffff:127.0.0.1", "fd00::1", "fe80::1", "2001:db8::1"])("sperrt %s", (ip) => expect(isPrivateAddress(ip)).toBe(true));
  it.each(["1.1.1.1", "93.184.216.34", "2606:4700:4700::1111"])("erlaubt öffentliche IP %s", (ip) => expect(isPrivateAddress(ip)).toBe(false));
  it("prüft alle DNS-Antworten vor dem Abruf", async () => {
    vi.mocked(lookup).mockResolvedValue([{ address: "1.1.1.1", family: 4 }, { address: "127.0.0.1", family: 4 }] as never);
    await expect(fetchPage(new URL("https://example.org"))).rejects.toThrow("nicht erreichbar");
    expect(request).not.toHaveBeenCalled();
  });
  it("bindet die Verbindung an die geprüfte IP und prüft auch Weiterleitungen", async () => {
    vi.mocked(request).mockImplementation(((_url: unknown, options: { lookup: (host: string, options: object, callback: (error: unknown, address: string) => void) => void }, callback: (response: IncomingMessage) => void) => {
      options.lookup("example.org", {}, (_error: unknown, address: string) => expect(address).toBe("93.184.216.34"));
      const req = new EventEmitter();
      Object.assign(req, { end() { const res = Readable.from([]); Object.assign(res, { statusCode: 302, headers: { location: "https://127.0.0.1/admin" } }); callback(res as IncomingMessage); }, destroy() {} });
      return req;
    }) as never);
    await expect(fetchPage(new URL("https://example.org"))).rejects.toThrow("nicht erreichbar");
    expect(request).toHaveBeenCalledTimes(1);
  });
  it("lehnt übergroße Seiten ab, statt abgeschnittene Rezepte zu importieren", async () => {
    vi.mocked(request).mockImplementation(((_url: unknown, _options: unknown, callback: (response: IncomingMessage) => void) => {
      const req = new EventEmitter();
      Object.assign(req, { end() { const res = Readable.from([Buffer.alloc(3_000_001)]); Object.assign(res, { statusCode: 200, headers: { "content-type": "text/html" } }); callback(res as IncomingMessage); }, destroy() {} });
      return req;
    }) as never);
    await expect(fetchPage(new URL("https://example.org"))).rejects.toThrow("zu groß");
  });
  it("verarbeitet mobile Teilen-Texte", () => expect(parseUserUrl("Rezept https://vm.tiktok.com/ABC").hostname).toBe("vm.tiktok.com"));
});
