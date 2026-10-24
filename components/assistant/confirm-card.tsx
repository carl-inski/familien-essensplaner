"use client";

// Bestätigungskarten für die Schreib-Werkzeuge des Assistenten.
// Erst „Übernehmen“ schreibt in die Datenbank; das Ergebnis geht an die KI zurück.

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { useApp } from "@/components/app-data";
import { IconCalendar, IconCheck, IconEdit, IconNote, IconPeople } from "@/components/icons";
import { DietIcon } from "@/components/ui";
import { AnwesenheitInput, EinplanenInput, EntwurfInput, NotizInput, type WriteTool } from "@/lib/ai/assistant-schemas";
import { extractToDraft } from "@/lib/ai/schemas";
import { WEEKDAY_LONG, addDays, formatDateDE, weekdayIndex } from "@/lib/dates";
import { stashDraft } from "@/lib/draft-handoff";
import { MEAL_LABEL } from "@/lib/meals";
import { meatRuleHint } from "@/lib/suggest";
import type { MealPlanEntry } from "@/lib/types";

export interface ToolPart {
  type: string;
  toolCallId: string;
  state: string;
  input?: unknown;
  output?: unknown;
  errorText?: string;
}

type Result = { ok: true; meldung: string } | { ok: false; meldung: string };
type Respond = (r: Result) => void;

const dayText = (d: string) => `${WEEKDAY_LONG[weekdayIndex(d)]}, ${formatDateDE(d, { day: "numeric", month: "long" })}`;

export function ConfirmCard({ tool, part, respond }: { tool: WriteTool; part: ToolPart; respond: Respond }) {
  if (part.state === "input-streaming") return <Shell icon={<IconEdit size={18} />} title="Vorschlag kommt …"><div className="skeleton h-5 w-2/3" /></Shell>;
  const done = part.state === "output-available" || part.state === "output-error";
  const result = (part.output ?? null) as Result | null;
  if (done) {
    const ok = part.state === "output-available" && result?.ok;
    return (
      <p className="t-footnote flex items-center gap-1.5 px-1" style={{ color: ok ? "var(--green)" : "var(--label-2)" }}>
        {ok && <IconCheck size={15} />} {result?.meldung ?? part.errorText ?? "Erledigt"}
      </p>
    );
  }
  switch (tool) {
    case "einplanen":
      return <PlanCard input={part.input} respond={respond} />;
    case "anwesenheit_setzen":
      return <AttendanceCard input={part.input} respond={respond} />;
    case "notiz_hinzufuegen":
      return <NoteCard input={part.input} respond={respond} />;
    case "rezept_entwurf_oeffnen":
      return <DraftCard input={part.input} respond={respond} />;
  }
}

function Shell({ icon, title, children, actions }: { icon: ReactNode; title: string; children: ReactNode; actions?: ReactNode }) {
  return (
    <div className="card overflow-hidden" role="group" aria-label={title}>
      <div className="px-4 pt-3 pb-3">
        <p className="t-footnote mb-1 flex items-center gap-1.5 font-semibold" style={{ color: "var(--accent)" }}>{icon} {title}</p>
        {children}
      </div>
      {actions && <div className="grid grid-cols-2 gap-2 px-3 pb-3">{actions}</div>}
    </div>
  );
}

function Actions({ busy, label, onYes, onNo }: { busy: boolean; label: string; onYes: () => void; onNo: () => void }) {
  return (
    <>
      <button className="btn btn-gray btn-sm pressable" disabled={busy} onClick={onNo}>Nein danke</button>
      <button className="btn btn-primary btn-sm pressable" disabled={busy} onClick={onYes}>{busy ? "Speichert …" : label}</button>
    </>
  );
}

function Invalid({ text, respond }: { text: string; respond: Respond }) {
  return (
    <Shell icon={<IconEdit size={18} />} title="Vorschlag nicht möglich" actions={<button className="btn btn-gray btn-sm pressable col-span-2" onClick={() => respond({ ok: false, meldung: text })}>Verstanden</button>}>
      <p className="t-sub">{text}</p>
    </Shell>
  );
}

function useAction(respond: Respond) {
  const [busy, setBusy] = useState(false);
  const run = async (fn: () => Promise<Result>) => {
    setBusy(true);
    try {
      respond(await fn());
    } catch (e) {
      respond({ ok: false, meldung: `Fehler: ${(e as Error).message}` });
    } finally {
      setBusy(false);
    }
  };
  return { busy, run };
}

function PlanCard({ input, respond }: { input: unknown; respond: Respond }) {
  const { sb, household, recipesById } = useApp();
  const parsed = EinplanenInput.safeParse(input);
  const data = parsed.success ? parsed.data : null;
  const recipe = data ? recipesById.get(data.rezept_id) : undefined;
  const [around, setAround] = useState<MealPlanEntry[] | null>(null);
  const { busy, run } = useAction(respond);

  useEffect(() => {
    if (!data) return;
    let alive = true;
    sb.from("ep_meal_plan")
      .select("*")
      .gte("date", addDays(data.datum, -3))
      .lte("date", addDays(data.datum, 3))
      .then(({ data: rows }) => alive && setAround((rows ?? []) as MealPlanEntry[]));
    return () => {
      alive = false;
    };
  }, [sb, data?.datum]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!data) return <Invalid text="Der Vorschlag war unvollständig." respond={respond} />;
  if (!recipe) return <Invalid text={`Das Rezept „${data.rezept_titel}“ gibt es nicht in der Sammlung.`} respond={respond} />;

  const current = around?.find((p) => p.date === data.datum && p.meal === data.mahlzeit);
  const currentTitle = current?.recipe_id && current.recipe_id !== recipe.id ? recipesById.get(current.recipe_id)?.title : null;
  const planned = (around ?? [])
    .filter((p) => p.recipe_id && !(p.date === data.datum && p.meal === data.mahlzeit))
    .map((p) => ({ date: p.date, recipe_id: p.recipe_id, diet: recipesById.get(p.recipe_id!)?.diet ?? null }));
  const hint = around ? meatRuleHint(planned, data.datum, recipe.diet) : null;

  return (
    <Shell
      icon={<IconCalendar size={16} />}
      title="Einplanen"
      actions={
        <Actions
          busy={busy}
          label="Übernehmen"
          onNo={() => respond({ ok: false, meldung: "Nicht eingeplant" })}
          onYes={() =>
            run(async () => {
              const { error } = await sb
                .from("ep_meal_plan")
                .upsert({ household_id: household.id, date: data.datum, meal: data.mahlzeit, recipe_id: recipe.id, leftover_of: null, status: "geplant" }, { onConflict: "household_id,date,meal" });
              if (error) throw error;
              return { ok: true, meldung: `${recipe.title} eingeplant: ${dayText(data.datum)}, ${MEAL_LABEL[data.mahlzeit]}` };
            })
          }
        />
      }
    >
      <Link href={`/rezepte/${recipe.id}`} className="t-headline flex items-center gap-1.5"><DietIcon diet={recipe.diet} size={16} /> {recipe.title}</Link>
      <p className="t-sub" style={{ color: "var(--label-2)" }}>{dayText(data.datum)} · {MEAL_LABEL[data.mahlzeit]}essen</p>
      {data.begruendung && <p className="t-footnote mt-1" style={{ color: "var(--label-2)" }}>{data.begruendung}</p>}
      {currentTitle && <p className="t-footnote mt-1" style={{ color: "var(--orange, var(--accent))" }}>Ersetzt „{currentTitle}“</p>}
      {hint && <p className="t-footnote mt-1" style={{ color: "var(--red)" }}>⚠︎ {hint}</p>}
    </Shell>
  );
}

function AttendanceCard({ input, respond }: { input: unknown; respond: Respond }) {
  const { sb, members } = useApp();
  const parsed = AnwesenheitInput.safeParse(input);
  const { busy, run } = useAction(respond);
  if (!parsed.success) return <Invalid text="Der Vorschlag war unvollständig." respond={respond} />;
  const data = parsed.data;
  const name = data.person.trim().toLowerCase();
  const member = members.find((m) => m.name.toLowerCase() === name) ?? members.find((m) => m.name.toLowerCase().startsWith(name));
  if (!member) return <Invalid text={`„${data.person}“ gehört nicht zum Haushalt.`} respond={respond} />;
  return (
    <Shell
      icon={<IconPeople size={16} />}
      title="Anwesenheit"
      actions={
        <Actions
          busy={busy}
          label="Übernehmen"
          onNo={() => respond({ ok: false, meldung: "Anwesenheit nicht geändert" })}
          onYes={() =>
            run(async () => {
              const { error } = await sb.from("ep_attendance").upsert({ member_id: member.id, date: data.datum, meal: data.mahlzeit, status: data.status, guests: 0 }, { onConflict: "member_id,date,meal" });
              if (error) throw error;
              return { ok: true, meldung: `${member.name} ist ${dayText(data.datum)} ${MEAL_LABEL[data.mahlzeit].toLowerCase()}s ${data.status === "da" ? "da" : "nicht da"}` };
            })
          }
        />
      }
    >
      <p className="t-headline">{member.name} {data.status === "da" ? "ist da" : "ist nicht da"}</p>
      <p className="t-sub" style={{ color: "var(--label-2)" }}>{dayText(data.datum)} · {MEAL_LABEL[data.mahlzeit]}essen</p>
    </Shell>
  );
}

function NoteCard({ input, respond }: { input: unknown; respond: Respond }) {
  const { sb, me, recipesById } = useApp();
  const parsed = NotizInput.safeParse(input);
  const { busy, run } = useAction(respond);
  if (!parsed.success) return <Invalid text="Der Vorschlag war unvollständig." respond={respond} />;
  const data = parsed.data;
  const recipe = recipesById.get(data.rezept_id);
  if (!recipe) return <Invalid text={`Das Rezept „${data.rezept_titel}“ gibt es nicht in der Sammlung.`} respond={respond} />;
  return (
    <Shell
      icon={<IconNote size={16} />}
      title={`Notiz zu ${recipe.title}`}
      actions={
        <Actions
          busy={busy}
          label="Speichern"
          onNo={() => respond({ ok: false, meldung: "Notiz nicht gespeichert" })}
          onYes={() =>
            run(async () => {
              const { error } = await sb.from("ep_recipe_notes").insert({ recipe_id: recipe.id, member_id: me.id, body: data.text.trim() });
              if (error) throw error;
              return { ok: true, meldung: `Notiz zu ${recipe.title} gespeichert` };
            })
          }
        />
      }
    >
      <blockquote className="t-sub border-l-2 pl-3" style={{ borderColor: "var(--accent)" }}>{data.text}</blockquote>
    </Shell>
  );
}

function DraftCard({ input, respond }: { input: unknown; respond: Respond }) {
  const router = useRouter();
  const parsed = EntwurfInput.safeParse(input);
  if (!parsed.success) return <Invalid text="Der Rezeptentwurf war unvollständig." respond={respond} />;
  const r = parsed.data.rezept;
  return (
    <Shell
      icon={<IconEdit size={16} />}
      title="Neues Rezept"
      actions={
        <>
          <button className="btn btn-gray btn-sm pressable" onClick={() => respond({ ok: false, meldung: "Entwurf verworfen" })}>Verwerfen</button>
          <button
            className="btn btn-primary btn-sm pressable"
            onClick={() => {
              const draft = extractToDraft({ ...r, is_recipe: true, cookbook_title: null, cookbook_page: null }, null);
              stashDraft({ draft, notice: "Entwurf vom Assistenten – bitte prüfen und sichern." });
              respond({ ok: true, meldung: `„${r.title}“ im Formular geöffnet` });
              router.push("/rezepte/neu");
            }}
          >
            Im Formular öffnen
          </button>
        </>
      }
    >
      <p className="t-headline">{r.title}</p>
      <p className="t-sub" style={{ color: "var(--label-2)" }}>
        {r.ingredients.length} Zutaten · {r.steps.length} Schritte{r.time_min ? ` · ${r.time_min} Min.` : ""}
      </p>
    </Shell>
  );
}
