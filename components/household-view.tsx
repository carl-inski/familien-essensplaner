"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { AiUsageSection } from "@/components/ai-status";
import { useApp } from "@/components/app-data";
import { PantrySection } from "@/components/pantry";
import { IconCheck, IconChevronRight, IconCopy, IconEdit, IconHistory, IconLogout, IconPlus, IconShare, IconUpload } from "@/components/icons";
import { AvatarPicker } from "@/components/avatar-picker";
import { CreateFamilyForm, JoinFamilyForm, enterFamily, inviteUrl, prettyCode } from "@/components/family-forms";
import { haptic, hapticsEnabled, setHapticsEnabled } from "@/lib/haptics";
import { Sheet } from "@/components/sheet";
import { useToast } from "@/components/toast";
import { Avatar, Section, Segmented } from "@/components/ui";
import { MEALS, MEAL_LABEL } from "@/lib/meals";
import { WEEKDAY_KEYS, WEEKDAY_SHORT, addDays } from "@/lib/dates";
import type { DefaultWeek, Meal, Member } from "@/lib/types";

/** Haushalt & Konto: als Seite (Computer) oder als Fenster hinter dem Avatar oben rechts (Handy) */
export function HouseholdView({ inSheet = false }: { inSheet?: boolean }) {
  const { members, me, history, today, sb, reloadMembers, household, memberships, reloadHousehold } = useApp();
  const toast = useToast();
  const router = useRouter();
  const [editing, setEditing] = useState<Member | null>(null);
  const [adding, setAdding] = useState(false);
  const [pwOpen, setPwOpen] = useState(false);
  const [familyOpen, setFamilyOpen] = useState<"neu" | "code" | "name" | null>(null);
  const [vibrate, setVibrate] = useState(hapticsEnabled);
  const [defaultMeal, setDefaultMeal] = useState<Meal>("abend");
  const isAdmin = me.role === "admin";

  // Kochdienst-Zähler: letzte 4 Wochen
  const since = addDays(today, -28);
  const cookCounts = useMemo(() => {
    const c = new Map<string, number>();
    for (const h of history) if (h.cook_id && h.cooked_on >= since) c.set(h.cook_id, (c.get(h.cook_id) ?? 0) + 1);
    return c;
  }, [history, since]);
  const maxCount = Math.max(1, ...cookCounts.values());

  async function toggleDefault(m: Member, dayIdx: number) {
    const key = WEEKDAY_KEYS[dayIdx];
    const current = m.default_week?.[key]?.[defaultMeal] ?? "da";
    const day = { ...(m.default_week?.[key] ?? {}), [defaultMeal]: current === "da" ? "weg" : "da" };
    if (day[defaultMeal] === "da") delete day[defaultMeal];
    const next: DefaultWeek = { ...m.default_week, [key]: day };
    if (!Object.keys(day).length) delete next[key];
    const { error } = await sb.from("ep_members").update({ default_week: next }).eq("id", m.id);
    if (error) toast({ text: error.message, tone: "error" });
    await reloadMembers();
  }

  const code = household.invite_code ?? "";

  async function shareInvite() {
    const text = `Komm in unsere Familie „${household.name}“ im Essensplaner. Code: ${prettyCode(code)}`;
    try {
      if (navigator.share) await navigator.share({ title: "Essensplaner", text, url: inviteUrl(code) });
      else {
        await navigator.clipboard.writeText(`${text}\n${inviteUrl(code)}`);
        toast({ text: "Einladung kopiert" });
      }
    } catch {
      // Teilen abgebrochen
    }
  }

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(code);
      toast({ text: "Code kopiert" });
    } catch {
      toast({ text: "Kopieren nicht möglich – bitte abtippen", tone: "warning" });
    }
  }

  async function newCode() {
    if (!confirm("Neuen Code erzeugen? Der alte Code und alte Einladungslinks gelten dann nicht mehr.")) return;
    const { error } = await sb.rpc("ep_regenerate_invite", { p_household: household.id });
    if (error) return toast({ text: error.message, tone: "error" });
    await reloadHousehold();
    toast({ text: "Neuer Code erzeugt" });
  }

  async function switchTo(id: string) {
    const { error } = await sb.rpc("ep_switch_household", { p_household: id });
    if (error) return toast({ text: error.message, tone: "error" });
    enterFamily();
  }

  async function leave() {
    if (!confirm(`„${household.name}“ wirklich verlassen? Rezepte und Plan bleiben bei der Familie; zurück kommst du nur mit einem Einladungscode.`)) return;
    const { error } = await sb.rpc("ep_leave_household", { p_household: household.id });
    if (error) return toast({ text: error.message, tone: "error" });
    enterFamily();
  }

  return (
    <>
      <div className={inSheet ? "[&>section:first-child]:mt-0" : "page-medium lg:columns-2 lg:gap-8 min-[96rem]:columns-3 [&>section]:break-inside-avoid lg:[&>section]:mt-0 lg:[&>section]:pt-6"}>
        <Section title="Familie" footer="Wer den Code hat, kann beitreten: Konto erstellen, Code eingeben, fertig.">
          <div className="group">
            <button className="row pressable" disabled={!isAdmin} onClick={() => setFamilyOpen("name")}>
              <span className="min-w-0 flex-1">
                <span className="t-headline block truncate">{household.name}</span>
                <span className="t-footnote block" style={{ color: "var(--label-2)" }}>{members.length} {members.length === 1 ? "Person" : "Personen"}</span>
              </span>
              {isAdmin && <IconEdit size={18} style={{ color: "var(--label-3)" }} />}
            </button>
            {code && (
              <div className="row">
                <span className="min-w-0 flex-1">
                  <span className="t-footnote block" style={{ color: "var(--label-2)" }}>Einladungscode</span>
                  <span className="block font-mono text-lg font-semibold tracking-[0.14em]">{prettyCode(code)}</span>
                </span>
                <button className="icon-button pressable flex h-9 w-9 items-center justify-center rounded-full" aria-label="Code kopieren" title="Code kopieren" onClick={copyCode}><IconCopy size={18} /></button>
                <button className="btn btn-tinted btn-sm pressable" onClick={shareInvite}><IconShare size={16} /> Einladen</button>
              </div>
            )}
          </div>
          {isAdmin && code && <button className="btn-plain t-footnote pressable mt-2 px-4" onClick={newCode}>Neuen Code erzeugen</button>}
        </Section>

        <Section title="Meine Familien">
          <ul className="group">
            {memberships.map((f) => (
              <li key={f.household_id}>
                <button className="row pressable" disabled={f.household_id === household.id} onClick={() => switchTo(f.household_id)}>
                  <span className="min-w-0 flex-1">
                    <span className="t-sub block truncate font-medium">{f.household_name}</span>
                    <span className="t-footnote block" style={{ color: "var(--label-2)" }}>{f.member_count} {f.member_count === 1 ? "Person" : "Personen"}{f.role === "admin" ? " · Admin" : ""}</span>
                  </span>
                  {f.household_id === household.id ? <IconCheck size={20} style={{ color: "var(--accent)" }} aria-label="aktiv" /> : <span className="t-footnote font-semibold" style={{ color: "var(--accent)" }}>Wechseln</span>}
                </button>
              </li>
            ))}
          </ul>
          <div className="mt-2 flex flex-wrap gap-2">
            <button className="btn btn-tinted btn-sm pressable" onClick={() => setFamilyOpen("code")}>Mit Code beitreten</button>
            <button className="btn btn-gray btn-sm pressable" onClick={() => setFamilyOpen("neu")}><IconPlus size={16} /> Neue Familie</button>
          </div>
        </Section>

        <Section title="Kochdienst · letzte 4 Wochen">
          <div className="card flex flex-col gap-2.5 px-4 py-3">
            {members.map((m) => {
              const n = cookCounts.get(m.id) ?? 0;
              return (
                <div key={m.id} className="flex items-center gap-3">
                  <span className="t-sub w-20 truncate">{m.name}</span>
                  <div className="h-2 flex-1 overflow-hidden rounded-full" style={{ background: "var(--fill)" }}>
                    <div className="h-full rounded-full" style={{ width: `${(n / maxCount) * 100}%`, background: "var(--accent)", minWidth: n ? 8 : 0 }} />
                  </div>
                  <span className="t-sub w-6 text-right font-semibold tabular-nums">{n}</span>
                </div>
              );
            })}
          </div>
        </Section>

        <Section title="Standardwoche" footer="Tippe einen Tag an, an dem jemand normalerweise nicht da ist. Neue Wochen werden damit vorbefüllt.">
          <div className="mb-2">
            <Segmented<Meal> label="Mahlzeit" value={defaultMeal} onChange={setDefaultMeal} options={MEALS.map((m) => ({ value: m, label: MEAL_LABEL[m] }))} />
          </div>
          <div className="card overflow-x-auto px-3 py-2">
            <table className="w-full border-separate" style={{ borderSpacing: "0 6px" }}>
              <thead>
                <tr>
                  <th className="sr-only">Person</th>
                  {WEEKDAY_SHORT.map((d) => <th key={d} className="t-caption font-semibold" style={{ color: "var(--label-2)" }}>{d}</th>)}
                </tr>
              </thead>
              <tbody>
                {members.map((m) => (
                  <tr key={m.id}>
                    <th scope="row" className="t-footnote pr-2 text-left font-medium">{m.name}</th>
                    {WEEKDAY_KEYS.map((k, i) => {
                      const away = m.default_week?.[k]?.[defaultMeal] === "weg";
                      return (
                        <td key={k} className="text-center">
                          <button
                            className="pressable t-caption h-8 w-8 rounded-full font-semibold"
                            style={{ background: away ? "transparent" : "var(--accent-soft)", color: away ? "var(--label-3)" : "var(--accent)", boxShadow: away ? "inset 0 0 0 1px var(--separator)" : undefined }}
                            aria-label={`${m.name} ${WEEKDAY_SHORT[i]} ${MEAL_LABEL[defaultMeal]}: ${away ? "weg" : "da"}`}
                            onClick={() => toggleDefault(m, i)}
                          >
                            {away ? "–" : "✓"}
                          </button>
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>

        <Section title="Mitglieder" footer={isAdmin ? "Tippe ein Mitglied an, um Foto und Rolle festzulegen. Für Kinder ohne eigene E-Mail kannst du hier auch ein Passwort vergeben." : undefined}>
          <ul className="group">
            {members.map((m) => (
              <li key={m.id}>
                <button className="row pressable" disabled={!isAdmin} onClick={() => setEditing(m)}>
                  <Avatar member={m} size={34} />
                  <span className="min-w-0 flex-1">
                    <span className="t-sub block font-medium">{m.name}{m.id === me.id ? " (du)" : ""}</span>
                    <span className="t-footnote block truncate" style={{ color: "var(--label-2)" }}>
                      {m.user_id ? `Login: ${m.email ?? "aktiv"}` : m.email ? `${m.email} · noch nicht beigetreten` : "noch kein Login"}
                    </span>
                  </span>
                  {m.role === "admin" && <span className="badge" style={{ background: "var(--accent-soft)", color: "var(--accent)" }}>Admin</span>}
                </button>
              </li>
            ))}
          </ul>
          {isAdmin && <button className="btn btn-tinted btn-sm pressable mt-2" onClick={() => setAdding(true)}><IconPlus size={16} /> Mitglied</button>}
        </Section>

        <Section title="Sammlung">
          <div className="group">
            <Link className="row pressable" href="/rezepte/lange-nicht">
              <IconHistory size={20} /> <span className="t-sub flex-1">Rückblick: lange nicht gegessen</span>
              <IconChevronRight size={18} style={{ color: "var(--label-3)" }} />
            </Link>
            <Link className="row pressable" href="/rezepte/import">
              <IconUpload size={20} /> <span className="t-sub flex-1">Rezepte importieren und exportieren</span>
              <IconChevronRight size={18} style={{ color: "var(--label-3)" }} />
            </Link>
          </div>
        </Section>

        <PantrySection />

        <AiUsageSection />

        <Section title="Mein Konto">
          <div className="card mb-2 px-4 py-3">
            <AvatarPicker member={members.find((m) => m.id === me.id) ?? me} />
          </div>
          <label className="row card mb-2 cursor-pointer lg:hidden">
            <span className="t-sub flex-1">Leichte Vibration beim Tippen</span>
            <input
              type="checkbox"
              role="switch"
              // natives iOS-Schalterelement: vibriert beim Umschalten selbst
              {...{ switch: "" }}
              className="toggle"
              checked={vibrate}
              onChange={(e) => {
                setHapticsEnabled(e.target.checked);
                setVibrate(e.target.checked);
                if (e.target.checked) haptic("medium");
              }}
            />
          </label>
          <button className="row card pressable" onClick={() => setPwOpen(true)}>
            <IconEdit size={20} /> <span className="t-sub">Passwort ändern</span>
          </button>
        </Section>

        <Section>
          <button className="row card pressable mb-2" style={{ color: "var(--red)" }} onClick={leave}>
            <span className="t-sub">Familie verlassen</span>
          </button>
          <button
            className="row card pressable"
            onClick={async () => {
              await sb.auth.signOut();
              router.replace("/login");
            }}
          >
            <IconLogout size={20} /> <span className="t-sub">Abmelden</span>
          </button>
        </Section>
      </div>

      <Sheet open={pwOpen} onClose={() => setPwOpen(false)} title="Passwort ändern">
        {pwOpen && <PasswordForm onDone={() => setPwOpen(false)} />}
      </Sheet>
      <Sheet open={familyOpen === "neu"} onClose={() => setFamilyOpen(null)} title="Neue Familie">
        {familyOpen === "neu" && <div className="pb-4"><CreateFamilyForm defaultName={me.name} /></div>}
      </Sheet>
      <Sheet open={familyOpen === "code"} onClose={() => setFamilyOpen(null)} title="Familie beitreten">
        {familyOpen === "code" && <div className="pb-4"><JoinFamilyForm defaultName={me.name} /></div>}
      </Sheet>
      <Sheet open={familyOpen === "name"} onClose={() => setFamilyOpen(null)} title="Name der Familie">
        {familyOpen === "name" && <FamilyNameForm onDone={() => setFamilyOpen(null)} />}
      </Sheet>
      <MemberSheet member={editing} open={!!editing || adding} onClose={() => { setEditing(null); setAdding(false); }} />
    </>
  );
}

function MemberSheet({ member, open, onClose }: { member: Member | null; open: boolean; onClose: () => void }) {
  return (
    <Sheet open={open} onClose={onClose} title={member ? member.name : "Neues Mitglied"}>
      {open && <MemberForm member={member} onDone={onClose} />}
    </Sheet>
  );
}

function MemberForm({ member, onDone }: { member: Member | null; onDone: () => void }) {
  const { sb, household, members, reloadMembers } = useApp();
  const toast = useToast();
  const [name, setName] = useState(member?.name ?? "");
  const [email, setEmail] = useState(member?.email ?? "");
  const [admin, setAdmin] = useState(member?.role === "admin");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);

  async function save() {
    if (password && password.length < 8) return toast({ text: "Das Passwort braucht mindestens 8 Zeichen", tone: "error" });
    if (password && !email.trim()) return toast({ text: "Für ein Passwort braucht es eine E-Mail-Adresse", tone: "error" });
    setBusy(true);
    const row = { name: name.trim(), email: email.trim().toLowerCase() || null, role: admin ? "admin" : "member" };
    const res = member
      ? await sb.from("ep_members").update(row).eq("id", member.id).select("id").single()
      : await sb.from("ep_members").insert({ ...row, household_id: household.id, position: members.length }).select("id").single();
    if (res.error) {
      setBusy(false);
      return toast({ text: res.error.message, tone: "error" });
    }
    if (password) {
      const { error } = await sb.rpc("ep_admin_set_password", { p_member: (res.data as { id: string }).id, p_password: password });
      if (error) {
        setBusy(false);
        await reloadMembers();
        return toast({ text: error.message, tone: "error" });
      }
    }
    await reloadMembers();
    setBusy(false);
    toast({ text: password ? `${name} kann sich jetzt mit ${email.trim()} und dem Passwort anmelden` : "Gespeichert" });
    onDone();
  }

  return (
    <div className="flex flex-col gap-2 pb-4">
      {member && (
        <div className="mb-2">
          <AvatarPicker member={members.find((m) => m.id === member.id) ?? member} />
        </div>
      )}
      <input className="input" placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} aria-label="Name" />
      <input className="input" type="email" placeholder="E-Mail (optional)" value={email} onChange={(e) => setEmail(e.target.value)} aria-label="E-Mail" />
      <label className="t-sub mt-1 flex items-center gap-2 px-1"><input type="checkbox" checked={admin} onChange={(e) => setAdmin(e.target.checked)} /> Admin (darf Mitglieder verwalten)</label>
      <p className="t-section mt-3">{member?.user_id ? "Neues Passwort (optional)" : "Passwort für den Login"}</p>
      <input className="input" type="text" autoComplete="new-password" placeholder="mind. 8 Zeichen" value={password} onChange={(e) => setPassword(e.target.value)} aria-label="Passwort" />
      <p className="t-footnote px-1" style={{ color: "var(--label-2)" }}>
        {member?.user_id ? "Leer lassen, um das Passwort nicht zu ändern. Geht nur bei Konten, die ihr selbst angelegt habt." : "Normalerweise unnötig: Gib der Person den Einladungscode, sie erstellt ihr Konto selbst. Ein Passwort hier legt ein Konto für sie an."}
      </p>
      <button className="btn btn-primary pressable mt-3" disabled={!name.trim() || busy} onClick={save}>{busy ? "Speichert …" : "Sichern"}</button>
    </div>
  );
}

function FamilyNameForm({ onDone }: { onDone: () => void }) {
  const { sb, household, reloadHousehold } = useApp();
  const toast = useToast();
  const [name, setName] = useState(household.name);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    const { error } = await sb.from("ep_households").update({ name: name.trim() }).eq("id", household.id);
    setBusy(false);
    if (error) return toast({ text: error.message, tone: "error" });
    await reloadHousehold();
    onDone();
  }

  return (
    <div className="flex flex-col gap-2 pb-4">
      <input className="input" value={name} maxLength={60} onChange={(e) => setName(e.target.value)} aria-label="Name der Familie" />
      <button className="btn btn-primary pressable mt-3" disabled={busy || !name.trim() || name.trim() === household.name} onClick={save}>{busy ? "Speichert …" : "Sichern"}</button>
    </div>
  );
}

function PasswordForm({ onDone }: { onDone: () => void }) {
  const { sb } = useApp();
  const toast = useToast();
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [busy, setBusy] = useState(false);

  async function save() {
    if (pw.length < 8) return toast({ text: "Mindestens 8 Zeichen", tone: "error" });
    if (pw !== pw2) return toast({ text: "Die Passwörter stimmen nicht überein", tone: "error" });
    setBusy(true);
    const { error } = await sb.auth.updateUser({ password: pw });
    setBusy(false);
    if (error) return toast({ text: error.message, tone: "error" });
    toast({ text: "Passwort geändert" });
    onDone();
  }

  return (
    <div className="flex flex-col gap-2 pb-4">
      <input className="input" type="password" autoComplete="new-password" placeholder="Neues Passwort" value={pw} onChange={(e) => setPw(e.target.value)} aria-label="Neues Passwort" />
      <input className="input" type="password" autoComplete="new-password" placeholder="Wiederholen" value={pw2} onChange={(e) => setPw2(e.target.value)} aria-label="Passwort wiederholen" />
      <button className="btn btn-primary pressable mt-3" disabled={busy || !pw} onClick={save}>{busy ? "Speichert …" : "Passwort ändern"}</button>
    </div>
  );
}
