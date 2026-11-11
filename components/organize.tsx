"use client";

// Sammlung ordnen: Ordner (ein Rezept liegt in höchstens einem) und frei kombinierbare Tags.

import { useMemo, useState } from "react";
import { useApp } from "./app-data";
import { IconClose, IconEdit, IconPlus, IconTrash } from "./icons";
import { Sheet } from "./sheet";
import { useToast } from "./toast";
import { slugifyTag } from "@/lib/markdown";
import type { Recipe, RecipeFolder } from "@/lib/types";

export const folderLabel = (f: Pick<RecipeFolder, "name" | "emoji">) => `${f.emoji ? `${f.emoji} ` : ""}${f.name}`;

const FOLDER_EMOJIS = ["📁", "⭐️", "⚡️", "🍝", "🥗", "🍲", "🥘", "🍕", "🐟", "🥩", "🌱", "🧁", "🥞", "🎉", "👶", "🔥", "❄️", "🏕️"];

/** Alle Tags der Sammlung, häufigste zuerst */
export function useAllTags(): string[] {
  const { recipes } = useApp();
  return useMemo(() => {
    const count = new Map<string, number>();
    for (const r of recipes) for (const t of r.tags) count.set(t, (count.get(t) ?? 0) + 1);
    return [...count.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], "de")).map(([t]) => t);
  }, [recipes]);
}

/** Tags als Chips: tippen und mit Enter oder Komma bestätigen, Vorschläge aus der Sammlung antippen */
export function TagInput({ value, onChange, placeholder = "Tag hinzufügen …" }: { value: string[]; onChange: (tags: string[]) => void; placeholder?: string }) {
  const all = useAllTags();
  const [text, setText] = useState("");

  function add(raw: string) {
    const tags = raw.split(",").map(slugifyTag).filter(Boolean);
    if (tags.length) onChange([...new Set([...value, ...tags])]);
    setText("");
  }

  const needle = slugifyTag(text);
  const suggestions = all.filter((t) => !value.includes(t) && (!needle || t.includes(needle))).slice(0, needle ? 8 : 10);

  return (
    <div>
      <div className="input flex flex-wrap items-center gap-1.5 !py-2">
        {value.map((t) => (
          <span key={t} className="chip !min-h-0 !py-1" data-on="true">
            #{t}
            <button type="button" className="pressable -mr-1" aria-label={`Tag ${t} entfernen`} onClick={() => onChange(value.filter((x) => x !== t))}>
              <IconClose size={14} />
            </button>
          </span>
        ))}
        <input
          className="min-w-24 flex-1 bg-transparent py-1 outline-none"
          value={text}
          placeholder={value.length ? "" : placeholder}
          aria-label="Tag hinzufügen"
          autoCapitalize="none"
          autoCorrect="off"
          enterKeyHint="done"
          onChange={(e) => (e.target.value.includes(",") ? add(e.target.value) : setText(e.target.value))}
          onKeyDown={(e) => {
            if (e.key === "Enter" && text.trim()) {
              e.preventDefault();
              add(text);
            } else if (e.key === "Backspace" && !text && value.length) {
              onChange(value.slice(0, -1));
            }
          }}
          onBlur={() => text.trim() && add(text)}
        />
      </div>
      {suggestions.length > 0 && (
        <div className="scroll-x mt-2 flex gap-1.5">
          {suggestions.map((t) => (
            // onMouseDown: das Feld soll den Fokus nicht verlieren (sonst würde der halbe Text als Tag gesichert)
            <button key={t} type="button" className="chip pressable shrink-0 !min-h-0 !py-1" onMouseDown={(e) => e.preventDefault()} onClick={() => add(t)}>
              #{t}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** Ordner wählen als Chips; „+ Ordner“ legt direkt einen neuen an */
export function FolderPicker({ value, onChange }: { value: string | null; onChange: (id: string | null) => void }) {
  const { folders } = useApp();
  const [creating, setCreating] = useState(false);
  return (
    <>
      <div className="flex flex-wrap gap-2">
        <button type="button" className="chip pressable" data-on={value === null} onClick={() => onChange(null)}>Kein Ordner</button>
        {folders.map((f) => (
          <button key={f.id} type="button" className="chip pressable" data-on={value === f.id} onClick={() => onChange(f.id)}>{folderLabel(f)}</button>
        ))}
        <button type="button" className="chip pressable" onClick={() => setCreating(true)}><IconPlus size={15} /> Ordner</button>
      </div>
      <Sheet open={creating} onClose={() => setCreating(false)} title="Neuer Ordner">
        {creating && <FolderForm folder={null} onDone={(id) => { setCreating(false); if (id) onChange(id); }} />}
      </Sheet>
    </>
  );
}

export function FolderForm({ folder, onDone }: { folder: RecipeFolder | null; onDone: (id?: string) => void }) {
  const { sb, household, folders, reloadFolders, reloadRecipes } = useApp();
  const toast = useToast();
  const [name, setName] = useState(folder?.name ?? "");
  const [emoji, setEmoji] = useState<string | null>(folder?.emoji ?? "📁");
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    const row = { name: name.trim(), emoji };
    const res = folder
      ? await sb.from("ep_recipe_folders").update(row).eq("id", folder.id).select("id").single()
      : await sb.from("ep_recipe_folders").insert({ ...row, household_id: household.id, position: folders.length }).select("id").single();
    setBusy(false);
    if (res.error) return toast({ text: res.error.code === "23505" ? "Einen Ordner mit diesem Namen gibt es schon" : res.error.message, tone: "error" });
    await reloadFolders();
    onDone((res.data as { id: string }).id);
  }

  async function remove() {
    if (!folder || !confirm(`Ordner „${folder.name}“ löschen? Die Rezepte bleiben in der Sammlung.`)) return;
    const { error } = await sb.from("ep_recipe_folders").delete().eq("id", folder.id);
    if (error) return toast({ text: error.message, tone: "error" });
    await Promise.all([reloadFolders(), reloadRecipes()]);
    onDone();
  }

  return (
    <div className="flex flex-col gap-3 pb-4">
      <input className="input" placeholder="Name, z. B. Schnell unter der Woche" value={name} maxLength={40} onChange={(e) => setName(e.target.value)} aria-label="Name des Ordners" />
      <div className="flex flex-wrap gap-1.5" role="radiogroup" aria-label="Symbol">
        {FOLDER_EMOJIS.map((e) => (
          <button key={e} type="button" role="radio" aria-checked={emoji === e} className="pressable flex h-10 w-10 items-center justify-center rounded-xl text-xl" style={{ background: emoji === e ? "var(--accent-soft)" : "var(--fill)", boxShadow: emoji === e ? "inset 0 0 0 1.5px var(--accent)" : undefined }} onClick={() => setEmoji(e)}>
            {e}
          </button>
        ))}
      </div>
      <button className="btn btn-primary pressable mt-1" disabled={busy || !name.trim()} onClick={save}>{busy ? "Speichert …" : folder ? "Sichern" : "Ordner anlegen"}</button>
      {folder && (
        <button className="btn btn-gray pressable" style={{ color: "var(--red)" }} onClick={remove}><IconTrash size={18} /> Ordner löschen</button>
      )}
    </div>
  );
}

/** Rezeptansicht: zeigt Ordner und Tags; antippen öffnet das Ordnen-Fenster */
export function OrganizeBar({ recipe }: { recipe: Recipe }) {
  const { folders } = useApp();
  const [open, setOpen] = useState(false);
  const folder = folders.find((f) => f.id === recipe.folder_id);
  return (
    <>
      <div className="mt-2 flex flex-wrap items-center gap-2">
        {folder && <button className="chip pressable" data-on="true" onClick={() => setOpen(true)}>{folderLabel(folder)}</button>}
        {recipe.tags.map((t) => <button key={t} className="chip pressable" onClick={() => setOpen(true)}>#{t}</button>)}
        <button className="chip pressable" onClick={() => setOpen(true)} style={{ color: "var(--accent)" }}>
          <IconEdit size={15} /> {folder || recipe.tags.length ? "Ordnen" : "Ordner & Tags"}
        </button>
      </div>
      <Sheet open={open} onClose={() => setOpen(false)} title="Ordner & Tags">
        {open && <OrganizeForm recipe={recipe} onDone={() => setOpen(false)} />}
      </Sheet>
    </>
  );
}

function OrganizeForm({ recipe, onDone }: { recipe: Recipe; onDone: () => void }) {
  const { sb, reloadRecipes } = useApp();
  const toast = useToast();
  const [folderId, setFolderId] = useState<string | null>(recipe.folder_id ?? null);
  const [tags, setTags] = useState(recipe.tags);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    const { error } = await sb.from("ep_recipes").update({ folder_id: folderId, tags }).eq("id", recipe.id);
    if (error) {
      setBusy(false);
      return toast({ text: error.message, tone: "error" });
    }
    await reloadRecipes();
    onDone();
  }

  return (
    <div className="flex flex-col gap-2 pb-4">
      <p className="t-section mt-1">Ordner</p>
      <FolderPicker value={folderId} onChange={setFolderId} />
      <p className="t-section mt-4">Tags</p>
      <TagInput value={tags} onChange={setTags} />
      <button className="btn btn-primary pressable mt-4" disabled={busy} onClick={save}>{busy ? "Speichert …" : "Sichern"}</button>
    </div>
  );
}
