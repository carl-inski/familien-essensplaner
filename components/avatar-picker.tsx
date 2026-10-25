"use client";

// Profilbild für ein Mitglied wählen, ändern oder entfernen.

import { useRef, useState } from "react";
import { useApp } from "@/components/app-data";
import { IconCamera, IconTrash } from "@/components/icons";
import { useToast } from "@/components/toast";
import { Avatar } from "@/components/ui";
import { inBackground } from "@/lib/background";
import { avatarForUpload } from "@/lib/image";
import type { Member } from "@/lib/types";

const BUCKET = "ep-images";

/** Pfad im Bucket aus der öffentlichen URL – nur für eigene Bilder, um alte zu löschen */
function storagePath(url: string | null | undefined): string | null {
  const m = url?.match(/\/storage\/v1\/object\/public\/ep-images\/(.+)$/);
  return m ? decodeURIComponent(m[1]) : null;
}

export function AvatarPicker({ member }: { member: Member }) {
  const { sb, household, reloadMembers } = useApp();
  const toast = useToast();
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);

  async function setUrl(url: string | null) {
    const old = storagePath(member.avatar_url);
    const { error } = await sb.from("ep_members").update({ avatar_url: url }).eq("id", member.id);
    if (error) throw error;
    if (old) inBackground(sb.storage.from(BUCKET).remove([old]), "altes Profilbild");
    await reloadMembers();
  }

  async function choose(file: File) {
    setBusy(true);
    try {
      const jpeg = await avatarForUpload(file);
      if (!jpeg) return toast({ text: "Dieses Bildformat kann der Browser nicht lesen. Bitte als JPG oder PNG wählen.", tone: "error" });
      const path = `${household.id}/avatars/${member.id}-${crypto.randomUUID()}.jpg`;
      const up = await sb.storage.from(BUCKET).upload(path, jpeg, { contentType: "image/jpeg", upsert: false });
      if (up.error) throw up.error;
      await setUrl(sb.storage.from(BUCKET).getPublicUrl(path).data.publicUrl);
      toast({ text: "Profilbild gespeichert" });
    } catch (e) {
      toast({ text: `Hochladen fehlgeschlagen: ${(e as Error).message}`, tone: "error" });
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    setBusy(true);
    try {
      await setUrl(null);
    } catch (e) {
      toast({ text: (e as Error).message, tone: "error" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex items-center gap-4">
      <button className="pressable rounded-full" onClick={() => input.current?.click()} disabled={busy} aria-label={`Profilbild für ${member.name} wählen`}>
        <Avatar member={member} size={64} />
      </button>
      <div className="flex flex-col items-start gap-1">
        <button className="btn-plain t-sub pressable flex items-center gap-1.5 font-semibold" onClick={() => input.current?.click()} disabled={busy}>
          <IconCamera size={18} /> {busy ? "Lädt hoch …" : member.avatar_url ? "Foto ändern" : "Foto wählen"}
        </button>
        {member.avatar_url && (
          <button className="btn-plain t-footnote pressable flex items-center gap-1.5" style={{ color: "var(--label-2)" }} onClick={remove} disabled={busy}>
            <IconTrash size={15} /> Foto entfernen
          </button>
        )}
      </div>
      <input
        ref={input}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) void choose(f);
        }}
      />
    </div>
  );
}
