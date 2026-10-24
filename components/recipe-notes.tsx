"use client";

// Notizen zu einem Rezept: alle im Haushalt lesen, jede Person schreibt unter eigenem Namen

import { useCallback, useEffect, useState } from "react";
import { useApp } from "./app-data";
import { IconEdit, IconTrash } from "./icons";
import { useToast } from "./toast";
import { Avatar, Section } from "./ui";

interface Note {
  id: string;
  recipe_id: string;
  member_id: string | null;
  body: string;
  created_at: string;
  updated_at: string;
}

function when(iso: string): string {
  const d = new Date(iso);
  const days = Math.floor((Date.now() - d.getTime()) / 86400000);
  if (days < 1) return "heute";
  if (days < 2) return "gestern";
  if (days < 7) return `vor ${days} Tagen`;
  return d.toLocaleDateString("de-DE", { day: "numeric", month: "short", year: days > 300 ? "numeric" : undefined });
}

export function RecipeNotes({ recipeId }: { recipeId: string }) {
  const { sb, me, members, reloadRecipes } = useApp();
  const toast = useToast();
  const [notes, setNotes] = useState<Note[] | null>(null);
  const [draft, setDraft] = useState("");
  const [editing, setEditing] = useState<{ id: string; body: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const isAdmin = me.role === "admin";

  const fetchNotes = useCallback(
    () => sb.from("ep_recipe_notes").select("*").eq("recipe_id", recipeId).order("created_at", { ascending: false }),
    [sb, recipeId],
  );

  useEffect(() => {
    let cancelled = false;
    const refresh = () => fetchNotes().then(({ data }) => !cancelled && setNotes((data ?? []) as Note[]));
    void refresh();
    // Live: Notizen anderer erscheinen sofort
    const channel = sb
      .channel(`ep-notes-${recipeId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_recipe_notes", filter: `recipe_id=eq.${recipeId}` }, () => void refresh())
      .subscribe();
    return () => {
      cancelled = true;
      void sb.removeChannel(channel);
    };
  }, [sb, recipeId, fetchNotes]);

  async function reload() {
    const { data } = await fetchNotes();
    setNotes((data ?? []) as Note[]);
  }

  async function add() {
    const body = draft.trim();
    if (!body) return;
    setBusy(true);
    const { error } = await sb.from("ep_recipe_notes").insert({ recipe_id: recipeId, member_id: me.id, body });
    setBusy(false);
    if (error) return toast({ text: error.message, tone: "error" });
    setDraft("");
    await reload();
    void reloadRecipes(); // Notiz-Zähler auf den Karten
  }

  async function saveEdit() {
    if (!editing) return;
    const body = editing.body.trim();
    if (!body) return;
    const { error } = await sb.from("ep_recipe_notes").update({ body }).eq("id", editing.id);
    if (error) return toast({ text: error.message, tone: "error" });
    setEditing(null);
    await reload();
  }

  async function remove(n: Note) {
    const { error } = await sb.from("ep_recipe_notes").delete().eq("id", n.id);
    if (error) return toast({ text: error.message, tone: "error" });
    await reload();
    void reloadRecipes();
    toast({
      text: "Notiz gelöscht",
      action: {
        label: "Rückgängig",
        run: async () => {
          await sb.from("ep_recipe_notes").insert({ recipe_id: recipeId, member_id: me.id, body: n.body });
          await reload();
          void reloadRecipes();
        },
      },
    });
  }

  return (
    <Section title={`Notizen${notes?.length ? ` · ${notes.length}` : ""}`}>
      <div className="card flex flex-col gap-2 p-3">
        <textarea
          className="input"
          rows={2}
          placeholder="z. B. „Weniger Chili“, „Doppelte Menge reicht für 2 Tage“ …"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          aria-label="Neue Notiz"
          maxLength={4000}
        />
        <div className="flex items-center justify-between">
          <span className="t-caption" style={{ color: "var(--label-3)" }}>als {me.name}</span>
          <button className="btn btn-tinted btn-sm pressable" disabled={busy || !draft.trim()} onClick={add}>
            {busy ? "Speichert …" : "Notiz hinzufügen"}
          </button>
        </div>
      </div>

      {notes && notes.length > 0 && (
        <ul className="mt-2 flex flex-col gap-2">
          {notes.map((n) => {
            const author = members.find((m) => m.id === n.member_id);
            const mine = n.member_id === me.id;
            const canEdit = mine || isAdmin;
            const isEditing = editing?.id === n.id;
            return (
              <li key={n.id} className="card px-4 py-3">
                <div className="mb-1.5 flex items-center gap-2">
                  {author && <Avatar member={author} size={22} />}
                  <span className="t-footnote font-semibold">{author?.name ?? "Ehemaliges Mitglied"}</span>
                  <span className="t-caption" style={{ color: "var(--label-3)" }}>
                    {when(n.created_at)}
                    {n.updated_at.slice(0, 16) !== n.created_at.slice(0, 16) ? " · bearbeitet" : ""}
                  </span>
                  {canEdit && !isEditing && (
                    <span className="ml-auto flex gap-0.5">
                      <button className="pressable p-1.5" style={{ color: "var(--label-3)" }} aria-label="Notiz bearbeiten" onClick={() => setEditing({ id: n.id, body: n.body })}>
                        <IconEdit size={17} />
                      </button>
                      <button className="pressable p-1.5" style={{ color: "var(--label-3)" }} aria-label="Notiz löschen" onClick={() => remove(n)}>
                        <IconTrash size={17} />
                      </button>
                    </span>
                  )}
                </div>
                {isEditing ? (
                  <div className="flex flex-col gap-2">
                    <textarea className="input" rows={3} value={editing.body} onChange={(e) => setEditing({ id: n.id, body: e.target.value })} aria-label="Notiz bearbeiten" maxLength={4000} />
                    <div className="flex justify-end gap-2">
                      <button className="btn btn-gray btn-sm pressable" onClick={() => setEditing(null)}>Abbrechen</button>
                      <button className="btn btn-primary btn-sm pressable" disabled={!editing.body.trim()} onClick={saveEdit}>Sichern</button>
                    </div>
                  </div>
                ) : (
                  <p className="t-sub whitespace-pre-wrap">{n.body}</p>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </Section>
  );
}
