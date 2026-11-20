"use client";

import { useRef, useState } from "react";
import { useAiStatus } from "./ai-status";
import { useApp } from "./app-data";
import { IconCamera, IconLink, IconPlus, IconUpload } from "./icons";
import { Sheet } from "./sheet";
import type { PendingDraft } from "@/lib/draft-handoff";
import { shrinkImage } from "@/lib/image";
import type { RecipeDraft } from "@/lib/markdown";
import { parseImportUrl } from "@/lib/recipe-source";

interface ImportResponse {
  draft?: RecipeDraft;
  via?: "jsonld" | "jsonld-ki" | "ki" | "video";
  error?: string;
  warnings?: string[];
}
type Mode = "camera" | "photos" | "web" | "social";
type Photo = Awaited<ReturnType<typeof shrinkImage>> & { id: string };
const titles: Record<Mode, string> = { camera: "Foto(s) aufnehmen", photos: "Foto(s) hochladen", web: "Web-Link importieren", social: "Social-Link importieren" };

export function RecipeImport({ onDraft, onManual }: { onDraft: (p: PendingDraft) => void; onManual: () => void }) {
  const { cookbooks } = useApp();
  const { status } = useAiStatus();
  const [mode, setMode] = useState<Mode | null>(null);
  const [url, setUrl] = useState("");
  const [description, setDescription] = useState("");
  const [book, setBook] = useState("");
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [busy, setBusy] = useState(false);
  const [preparing, setPreparing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inFlight = useRef(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const aiReady = status?.enabled ?? false;
  const isLink = mode === "web" || mode === "social";
  const locked = busy || preparing;

  function open(next: Mode) {
    setError(null);
    setPhotos([]);
    setDescription("");
    setUrl("");
    setMode(next);
  }

  async function addPhotos(files: FileList | null) {
    if (!files?.length || locked) return;
    const chosen = [...files];
    if (photos.length + chosen.length > 3) {
      setError("Bitte insgesamt höchstens 3 Fotos desselben Rezepts auswählen.");
      if (fileRef.current) fileRef.current.value = "";
      return;
    }
    setPreparing(true);
    setError(null);
    try {
      const images = await Promise.all(chosen.map(async (file) => ({ ...await shrinkImage(file, 1400), id: crypto.randomUUID() })));
      setPhotos((current) => [...current, ...images]);
    } catch {
      setError("Ein Foto konnte nicht gelesen werden. Bitte ein JPEG, PNG oder WebP auswählen.");
    } finally {
      setPreparing(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  async function run() {
    if (inFlight.current || locked || !mode) return;
    inFlight.current = true;
    setBusy(true);
    setError(null);
    try {
      const images = photos.map(({ data, mediaType }) => ({ data, mediaType }));
      const body = JSON.stringify(isLink ? { url: parseImportUrl(url).href, mode, text: description, images } : { images, cookbook: book || undefined });
      if (new TextEncoder().encode(body).byteLength > 4_300_000) throw new Error("Die Fotos sind zusammen zu groß. Bitte weniger Fotos auswählen.");
      const response = await fetch(isLink ? "/api/ai/recipe-from-url" : "/api/ai/recipe-from-photo", {
        method: "POST", headers: { "Content-Type": "application/json" }, body, signal: AbortSignal.timeout(65_000),
      });
      const data = await response.json().catch(() => ({})) as ImportResponse;
      if (!response.ok || !data.draft) throw new Error(data.error ?? "Der Import hat nicht geklappt. Bitte erneut versuchen.");
      const notice = data.via === "jsonld" ? "Von der Webseite übernommen – bitte prüfen und sichern."
        : data.via === "jsonld-ki" ? "Von der Webseite übernommen und übersetzt – bitte Mengen prüfen."
        : "Rezeptentwurf – bitte Zutaten, Mengen und Zubereitung prüfen.";
      onDraft({ draft: data.draft, notice: [notice, ...(data.warnings ?? [])].join(" ") });
      setMode(null);
      setPhotos([]);
    } catch (failure) {
      setError(failure instanceof Error && failure.name !== "TimeoutError" ? failure.message : "Der Import dauert zu lange. Bitte erneut versuchen.");
    } finally {
      inFlight.current = false;
      setBusy(false);
    }
  }

  return (
    <div className="mt-4">
      <div className="grid gap-2 sm:grid-cols-2">
        <button type="button" className="btn btn-tinted pressable" disabled={!aiReady} onClick={() => open("camera")}><IconCamera size={18} /> Foto(s) aufnehmen</button>
        <button type="button" className="btn btn-tinted pressable" disabled={!aiReady} onClick={() => open("photos")}><IconUpload size={18} /> Foto(s) hochladen</button>
        <button type="button" className="btn btn-tinted pressable" onClick={() => open("web")}><IconLink size={18} /> Web-Link importieren</button>
        <button type="button" className="btn btn-tinted pressable" onClick={() => open("social")}><IconLink size={18} /> Social-Link importieren</button>
        <button type="button" className="btn btn-gray pressable sm:col-span-2" onClick={onManual}><IconPlus size={18} /> Manuell erstellen</button>
      </div>
      <p className="t-footnote mt-3 px-1" style={{ color: "var(--label-2)" }}>
        {status && !aiReady ? "Rezeptseiten mit Rezeptdaten und manuelles Erstellen sind verfügbar. Für Fotos und Beitragsbeschreibungen muss die KI eingerichtet sein." : "Du prüfst und bearbeitest den Entwurf vor dem Sichern."}
      </p>
      <Sheet open={mode !== null} onClose={() => !locked && setMode(null)} title={mode ? titles[mode] : "Rezept importieren"}>
        <form onSubmit={(event) => { event.preventDefault(); void run(); }} className="space-y-4">
          {isLink && <>
            <label className="block t-sub">{mode === "social" ? "Link zum Beitrag" : "Link zum Rezept"}
              <textarea className="input mt-1" inputMode="url" autoFocus placeholder="https://… oder Teilen-Text" value={url} onChange={(event) => setUrl(event.target.value)} disabled={locked} rows={2} />
            </label>
            {mode === "social" && <p className="t-footnote" style={{ color: "var(--label-2)" }}>Instagram, Facebook, TikTok, YouTube und Pinterest. Füge den Link zum Beitrag oder Pin ein.</p>}
            <label className="block t-sub">Beschreibung ergänzen (optional)
              <textarea className="input mt-1" rows={4} maxLength={24000} placeholder="Rezepttext oder Beitragsbeschreibung einfügen" value={description} onChange={(event) => setDescription(event.target.value)} disabled={locked} />
            </label>
            <p className="t-footnote" style={{ color: "var(--label-2)" }}>Bei gesperrten Links oder fehlenden Angaben Beschreibung oder Screenshots ergänzen.</p>
          </>}
          {(!isLink || aiReady) && <>
            <label className="btn btn-tinted pressable" aria-disabled={locked || photos.length >= 3} style={locked || photos.length >= 3 ? { opacity: 0.5, pointerEvents: "none" } : undefined}>
              <IconCamera size={18} /> {preparing ? "Fotos werden geladen …" : mode === "camera" ? photos.length ? "Weiteres Foto aufnehmen" : "Kamera öffnen" : isLink ? "Screenshots ergänzen" : "Fotos auswählen"}
              <input ref={fileRef} type="file" accept="image/*" capture={mode === "camera" ? "environment" : undefined} multiple={mode !== "camera"} className="hidden" disabled={locked || photos.length >= 3} onChange={(event) => void addPhotos(event.target.files)} aria-label={mode === "camera" ? "Rezeptseite fotografieren" : "Rezeptfotos wählen"} />
            </label>
            {photos.map((photo, index) => <div key={photo.id} className="flex items-center gap-3">
              {/* Local, already resized image data; no remote image loader needed. */}
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={photo.dataUrl} alt={`Rezeptfoto ${index + 1}`} className="h-20 w-16 rounded-lg object-contain" />
              <span className="t-sub">Seite {index + 1}</span>
              <button type="button" className="btn-plain ml-auto t-sub" disabled={locked} onClick={() => setPhotos((current) => current.filter((item) => item.id !== photo.id))} aria-label={`Foto ${index + 1} entfernen`}>Entfernen</button>
            </div>)}
            <p className="t-footnote" style={{ color: "var(--label-2)" }}>Bis zu 3 Fotos desselben Rezepts in Lesereihenfolge. Die Fotos werden zum Ablesen an den KI-Dienst übertragen.</p>
          </>}
          {!isLink && cookbooks.length > 0 && <label className="block t-sub">Kochbuch (optional)
            <select className="input mt-1" value={book} onChange={(event) => setBook(event.target.value)} disabled={locked}>
              <option value="">Kein Kochbuch zuordnen</option>
              {cookbooks.map((cookbook) => <option key={cookbook.id} value={cookbook.title}>{cookbook.title}</option>)}
            </select>
          </label>}
          {error && <p role="alert" className="t-sub">{error}</p>}
          <button className="btn btn-primary pressable w-full" type="submit" disabled={locked || (isLink ? !url.trim() : !photos.length)}>{busy ? "Rezept wird gelesen …" : "Entwurf erstellen"}</button>
          {busy && <p role="status" className="t-footnote">Das kann einen Moment dauern. Deine Angaben bleiben erhalten.</p>}
        </form>
      </Sheet>
    </div>
  );
}
