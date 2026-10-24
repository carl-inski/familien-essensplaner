"use client";

// „Aus Link“ und „Aus Foto“ über dem Formular für neue Rezepte.

import { useRef, useState } from "react";
import { useAiStatus } from "./ai-status";
import { useApp } from "./app-data";
import { IconCamera, IconLink } from "./icons";
import { Sheet } from "./sheet";
import { useToast } from "./toast";
import type { PendingDraft } from "@/lib/draft-handoff";
import { shrinkImage } from "@/lib/image";
import type { RecipeDraft } from "@/lib/markdown";

interface ImportResponse {
  draft?: RecipeDraft;
  via?: "jsonld" | "jsonld-ki" | "ki";
  error?: string;
}

export function RecipeImport({ onDraft }: { onDraft: (p: PendingDraft) => void }) {
  const { cookbooks } = useApp();
  const { status } = useAiStatus();
  const toast = useToast();
  const [linkOpen, setLinkOpen] = useState(false);
  const [url, setUrl] = useState("");
  const [book, setBook] = useState("");
  const [busy, setBusy] = useState<null | "link" | "foto">(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const aiReady = status?.enabled ?? false;

  async function run(kind: "link" | "foto", path: string, body: unknown) {
    setBusy(kind);
    try {
      const res = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      const data = (await res.json().catch(() => ({}))) as ImportResponse;
      if (!res.ok || !data.draft) throw new Error(data.error ?? "Das hat nicht geklappt.");
      onDraft({
        draft: data.draft,
        notice:
          data.via === "jsonld"
            ? "Von der Webseite übernommen – bitte kurz prüfen und sichern."
            : data.via === "jsonld-ki"
              ? "Von der Webseite übernommen und von der KI übersetzt – bitte Mengen prüfen."
              : "KI-Entwurf – bitte prüfen, vor allem Mengen und Zutaten.",
      });
      setLinkOpen(false);
      setUrl("");
    } catch (e) {
      toast({ text: (e as Error).message, tone: "error" });
    } finally {
      setBusy(null);
    }
  }

  async function photos(files: FileList | null) {
    if (!files?.length) return;
    if (files.length > 3) return toast({ text: "Höchstens 3 Fotos auf einmal.", tone: "error" });
    setBusy("foto");
    let images;
    try {
      images = (await Promise.all([...files].map((f) => shrinkImage(f)))).map(({ data, mediaType }) => ({ data, mediaType }));
    } catch {
      setBusy(null);
      return toast({ text: "Das Foto konnte nicht gelesen werden.", tone: "error" });
    }
    await run("foto", "/api/ai/recipe-from-photo", { images, cookbook: book || undefined });
    if (fileRef.current) fileRef.current.value = "";
  }

  return (
    <div className="mt-4">
      <div className="grid grid-cols-2 gap-2">
        <button className="btn btn-tinted pressable" disabled={!!busy} onClick={() => setLinkOpen(true)}>
          <IconLink size={18} /> {busy === "link" ? "Liest …" : "Aus Link"}
        </button>
        <label className="btn btn-tinted pressable" aria-disabled={!aiReady || !!busy} style={!aiReady || busy ? { opacity: 0.5, pointerEvents: "none" } : undefined}>
          <IconCamera size={18} /> {busy === "foto" ? "KI liest …" : "Aus Foto"}
          <input ref={fileRef} type="file" accept="image/*" multiple className="hidden" disabled={!aiReady || !!busy} onChange={(e) => photos(e.target.files)} aria-label="Rezeptfotos wählen" />
        </label>
      </div>
      {aiReady && cookbooks.length > 0 && (
        <select className="input t-footnote mt-2" value={book} onChange={(e) => setBook(e.target.value)} aria-label="Foto stammt aus Kochbuch">
          <option value="">Foto aus einem Kochbuch? (optional)</option>
          {cookbooks.map((c) => <option key={c.id} value={c.title}>{c.title}</option>)}
        </select>
      )}
      <p className="t-footnote mt-1.5 px-1" style={{ color: "var(--label-2)" }}>
        {status && !aiReady ? "Links von Rezeptseiten funktionieren schon. Fotos lesen geht, sobald die KI eingerichtet ist." : "Link einfügen oder Kochbuchseite fotografieren – du prüfst alles vor dem Sichern."}
      </p>

      <Sheet open={linkOpen} onClose={() => !busy && setLinkOpen(false)} title="Rezept aus Link">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (url.trim()) void run("link", "/api/ai/recipe-from-url", { url });
          }}
        >
          <input className="input" type="url" inputMode="url" autoFocus placeholder="https://www.chefkoch.de/rezepte/…" value={url} onChange={(e) => setUrl(e.target.value)} aria-label="Link zum Rezept" />
          <p className="t-footnote mt-2 px-1" style={{ color: "var(--label-2)" }}>Die meisten Rezeptseiten liefern ihre Daten direkt mit, dann braucht es keine KI.</p>
          <button className="btn btn-primary pressable mt-4 w-full" type="submit" disabled={!url.trim() || !!busy}>{busy === "link" ? "Liest Rezept …" : "Übernehmen"}</button>
        </form>
      </Sheet>
    </div>
  );
}
