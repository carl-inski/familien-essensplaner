"use client";

import { useState } from "react";
import { catalogBook } from "@/lib/medien";
import { useApp } from "./app-data";
import { Sheet } from "./sheet";
import { useToast } from "./toast";
import type { Cookbook } from "@/lib/types";

/** Cover-Foto oder ein ruhiger Buchrücken mit Titel */
export function BookCover({ book, className = "" }: { book: Pick<Cookbook, "title" | "cover_url" | "authors">; className?: string }) {
  const catalog = catalogBook(book.title);
  const cover = book.cover_url || catalog?.coverUrl;
  const authors = book.authors.length ? book.authors : catalog?.authors ?? [];
  if (cover) {
    // eslint-disable-next-line @next/next/no-img-element
    return (
      <span className={`flex items-center justify-center overflow-hidden ${className}`} style={{ borderRadius: 6, background: "#f4efe6", boxShadow: "0 1px 2px rgba(0,0,0,.2), 0 6px 16px rgba(0,0,0,.12)" }}>
        <img src={cover} alt="" loading="lazy" className="h-full w-full object-contain" />
      </span>
    );
  }
  let h = 0;
  for (const c of book.title) h = (h * 31 + c.charCodeAt(0)) % 360;
  return (
    <div
      className={`flex flex-col justify-between p-2.5 ${className}`}
      style={{
        borderRadius: 6,
        background: `linear-gradient(160deg, hsl(${h} 45% 42%), hsl(${(h + 20) % 360} 50% 28%))`,
        boxShadow: "inset 6px 0 0 rgba(0,0,0,.18), 0 1px 2px rgba(0,0,0,.2), 0 6px 16px rgba(0,0,0,.12)",
        color: "rgba(255,255,255,.95)",
      }}
      aria-hidden
    >
      <span className="line-clamp-4 pl-1.5 text-[13px] leading-tight font-semibold" style={{ letterSpacing: "-0.01em" }}>{book.title}</span>
      {authors[0] && <span className="truncate pl-1.5 text-[10px] opacity-80">{authors[0]}</span>}
    </div>
  );
}

interface FormState { title: string; authors: string; publisher: string; year: string; isbn: string; cover_url: string; notes: string }

const toForm = (b?: Partial<Cookbook>): FormState => ({
  title: b?.title ?? "",
  authors: (b?.authors ?? []).join(", "),
  publisher: b?.publisher ?? "",
  year: b?.year?.toString() ?? "",
  isbn: b?.isbn ?? "",
  cover_url: b?.cover_url ?? "",
  notes: b?.notes ?? "",
});

/** Anlegen oder Bearbeiten eines Kochbuchs, ISBN füllt Felder vor */
export function BookSheet({ open, onClose, book, onSaved }: { open: boolean; onClose: () => void; book?: Cookbook; onSaved?: (id: string) => void }) {
  return (
    <Sheet open={open} onClose={onClose} title={book ? "Buch bearbeiten" : "Buch hinzufügen"}>
      {open && <BookForm book={book} onDone={(id) => { onClose(); if (id) onSaved?.(id); }} />}
    </Sheet>
  );
}

function BookForm({ book, onDone }: { book?: Cookbook; onDone: (id?: string) => void }) {
  const { sb, household, reloadCookbooks } = useApp();
  const toast = useToast();
  const [f, setF] = useState<FormState>(toForm(book));
  const [looking, setLooking] = useState(false);
  const [saving, setSaving] = useState(false);
  const set = (patch: Partial<FormState>) => setF((s) => ({ ...s, ...patch }));

  async function lookup() {
    setLooking(true);
    const res = await fetch(`/api/isbn?isbn=${encodeURIComponent(f.isbn)}`);
    const data = await res.json();
    setLooking(false);
    if (!res.ok) return toast({ text: data.error ?? "Nichts gefunden", tone: "error" });
    // Vorbefüllen; vorhandene Eingaben bleiben, wenn der Dienst nichts liefert
    set({
      title: data.title ?? f.title,
      authors: data.authors?.length ? data.authors.join(", ") : f.authors,
      publisher: data.publisher ?? f.publisher,
      year: data.year?.toString() ?? f.year,
      cover_url: data.cover_url ?? f.cover_url,
      isbn: data.isbn,
    });
    toast({ text: `Gefunden über ${data.source === "openlibrary" ? "Open Library" : "Google Books"} – bitte prüfen` });
  }

  async function save() {
    if (!f.title.trim()) return toast({ text: "Titel fehlt", tone: "error" });
    setSaving(true);
    const row = {
      household_id: household.id,
      title: f.title.trim(),
      authors: f.authors.split(",").map((a) => a.trim()).filter(Boolean),
      publisher: f.publisher.trim() || null,
      year: f.year.trim() ? Number.parseInt(f.year, 10) : null,
      isbn: f.isbn.trim() || null,
      cover_url: f.cover_url.trim() || null,
      notes: f.notes.trim() || null,
    };
    const res = book
      ? await sb.from("ep_cookbooks").update(row).eq("id", book.id).select("id").single()
      : await sb.from("ep_cookbooks").insert(row).select("id").single();
    setSaving(false);
    if (res.error) return toast({ text: res.error.message.includes("duplicate") ? "Diese ISBN steht schon im Regal." : res.error.message, tone: "error" });
    await reloadCookbooks();
    onDone((res.data as { id: string }).id);
  }

  return (
    <div className="flex flex-col gap-2 pb-4">
      <p className="t-section mt-1">ISBN</p>
      <div className="flex gap-2">
        <input className="input flex-1" inputMode="numeric" placeholder="978…" value={f.isbn} onChange={(e) => set({ isbn: e.target.value })} aria-label="ISBN" />
        <button className="btn btn-tinted pressable" disabled={looking || f.isbn.replace(/\D/g, "").length < 10} onClick={lookup}>{looking ? "Sucht …" : "Abfragen"}</button>
      </div>
      <p className="t-footnote px-1" style={{ color: "var(--label-2)" }}>Steht auf der Rückseite über dem Barcode.</p>

      {f.cover_url && (
        <div className="mt-2 flex justify-center">
          <BookCover book={{ title: f.title, cover_url: f.cover_url, authors: [] }} className="h-40 w-28" />
        </div>
      )}

      <p className="t-section mt-3">Angaben</p>
      <input className="input" placeholder="Titel" value={f.title} onChange={(e) => set({ title: e.target.value })} aria-label="Titel" />
      <input className="input" placeholder="Autor(en), mit Komma getrennt" value={f.authors} onChange={(e) => set({ authors: e.target.value })} aria-label="Autoren" />
      <div className="grid grid-cols-3 gap-2">
        <input className="input col-span-2" placeholder="Verlag" value={f.publisher} onChange={(e) => set({ publisher: e.target.value })} aria-label="Verlag" />
        <input className="input" inputMode="numeric" placeholder="Jahr" value={f.year} onChange={(e) => set({ year: e.target.value.replace(/\D/g, "").slice(0, 4) })} aria-label="Erscheinungsjahr" />
      </div>
      <input className="input" placeholder="Cover-URL (optional)" value={f.cover_url} onChange={(e) => set({ cover_url: e.target.value })} aria-label="Cover-URL" />
      <textarea className="input" placeholder="Notizen" value={f.notes} onChange={(e) => set({ notes: e.target.value })} aria-label="Notizen" />
      <button className="btn btn-primary pressable mt-3" disabled={saving} onClick={save}>{saving ? "Speichert …" : book ? "Sichern" : "Ins Regal stellen"}</button>
    </div>
  );
}
