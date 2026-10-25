"use client";

// Einkauf über Wochengrenzen: alle kommenden Gerichte, für die noch nicht
// eingekauft wurde. „Einkauf erledigt“ merkt sich das pro Gericht, damit beim
// nächsten Einkauf nichts doppelt gekauft wird.

import { useEffect, useMemo, useState } from "react";
import { useApp } from "@/components/app-data";
import { AiPromptBar } from "@/components/assistant/ai-panel";
import { IconCart, IconCheck, IconCopy, IconHome, IconPlus, IconTrash } from "@/components/icons";
import { PageHeader } from "@/components/nav";
import { usePantry } from "@/components/pantry";
import { Sheet } from "@/components/sheet";
import { useShopping, type ShoppingExtra } from "@/components/shopping/use-shopping";
import { useToast } from "@/components/toast";
import { Empty, Section } from "@/components/ui";
import { aisleFor } from "@/lib/aisles";
import { bringDeeplink, shoppingPublicUrl } from "@/lib/bring";
import { WEEKDAY_SHORT, formatDateDE, isoWeekString, weekdayIndex } from "@/lib/dates";
import { MEAL_LABEL, slotKey } from "@/lib/meals";
import { pantryEntriesFor, pantryEntriesToAdd, pantryLabel } from "@/lib/pantry";
import { buildShoppingList, groupByAisle, needsShopping, servingsFor } from "@/lib/planning";
import type { ShoppingItem } from "@/lib/types";
import { inBackground } from "@/lib/background";

// Abhak-Status während des Einkaufs nur auf diesem Gerät
function readChecked(key: string): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(key) ?? "[]"));
  } catch {
    return new Set();
  }
}
function writeChecked(key: string, set: Set<string>) {
  try {
    localStorage.setItem(key, JSON.stringify([...set]));
  } catch {
    // privater Modus – Abhaken gilt dann nur bis zum Neuladen
  }
}

const itemKey = (i: Pick<ShoppingItem, "name" | "unit">) => `${i.name}|${i.unit ?? ""}`;
const dayShort = (d: string) => `${WEEKDAY_SHORT[weekdayIndex(d)]} ${formatDateDE(d, { day: "numeric", month: "numeric" })}`;

export default function ShoppingPage() {
  const { today, sb, household, me, recipesById, members } = useApp();
  const toast = useToast();
  const { plan, attendance, extras, loaded, reload } = useShopping();
  const pantry = usePantry();
  const storageKey = `einkauf-${household.id}`;
  const [checked, setChecked] = useState<Set<string>>(() => readChecked(storageKey));
  // Bis zu welchem Tag eingekauft wird (null = alle) und einzeln abgewählte Gerichte
  const [until, setUntil] = useState<string | null>(null);
  const [excluded, setExcluded] = useState<Set<string>>(new Set());
  const [finishOpen, setFinishOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [extraText, setExtraText] = useState("");
  const [slug, setSlug] = useState<string | null>(null);

  const open = useMemo(
    () =>
      plan
        .filter((p) => needsShopping(p, today) && recipesById.has(p.recipe_id!))
        .sort((a, b) => slotKey(a.date, a.meal).localeCompare(slotKey(b.date, b.meal))),
    [plan, today, recipesById],
  );
  const shopped = useMemo(
    () =>
      plan
        .filter((p) => p.shopped_at && p.recipe_id && !p.leftover_of && p.status === "geplant" && recipesById.has(p.recipe_id))
        .sort((a, b) => slotKey(a.date, a.meal).localeCompare(slotKey(b.date, b.meal))),
    [plan, recipesById],
  );
  const days = useMemo(() => [...new Set(open.map((p) => p.date))], [open]);
  const included = useMemo(() => open.filter((p) => !excluded.has(p.id) && (!until || p.date <= until)), [open, excluded, until]);
  const includedIds = useMemo(() => new Set(included.map((p) => p.id)), [included]);

  const all = useMemo(
    () => buildShoppingList(plan, recipesById, members, attendance, pantry.set, (e) => includedIds.has(e.id)),
    [plan, recipesById, members, attendance, pantry.set, includedIds],
  );
  const items = useMemo(() => all.filter((i) => !i.pantry), [all]);
  const atHome = useMemo(() => [...new Set(all.filter((i) => i.pantry).flatMap((i) => pantryEntriesFor(i.name, pantry.set)))].sort((a, b) => a.localeCompare(b, "de")), [all, pantry.set]);
  const groups = useMemo(() => groupByAisle(items), [items]);
  const missingIngredients = included.filter((p) => !(recipesById.get(p.recipe_id!)?.ep_recipe_ingredients ?? []).length);

  // Für Bring! und „Als Text“: Zutaten plus „Noch offen“
  const exportItems: ShoppingItem[] = useMemo(
    () => [...extras.map((x) => ({ name: x.text, amount: null, unit: null, text: x.text, aisle: x.aisle ?? aisleFor(x.text), recipes: [] })), ...items],
    [extras, items],
  );
  const total = exportItems.length;

  const toggle = (key: string) =>
    setChecked((cur) => {
      const next = new Set(cur);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      writeChecked(storageKey, next);
      return next;
    });

  // Snapshot für die öffentliche Bring!-Seite aktuell halten
  useEffect(() => {
    if (!loaded) return;
    const t = setTimeout(async () => {
      const { data, error } = await sb
        .from("ep_shopping_lists")
        .upsert({ household_id: household.id, iso_week: isoWeekString(today), items: exportItems }, { onConflict: "household_id,iso_week" })
        .select("public_slug")
        .single();
      if (!error) setSlug((data as { public_slug: string }).public_slug);
    }, 400);
    return () => clearTimeout(t);
  }, [loaded, exportItems, today, household.id, sb]);

  async function keepAtHome(name: string) {
    const names = await pantry.add(pantryEntriesToAdd(name));
    if (names.length) toast({ text: `${names.map(pantryLabel).join(", ")}: ab jetzt immer zu Hause`, action: { label: "Widerrufen", run: () => void pantry.remove(names) } });
  }

  async function addExtra() {
    const text = extraText.trim();
    if (!text) return;
    setExtraText("");
    const { error } = await sb.from("ep_shopping_extra").insert({ household_id: household.id, member_id: me.id, text, aisle: aisleFor(text) });
    if (error) toast({ text: error.message, tone: "error" });
    await reload();
  }

  async function removeExtra(x: ShoppingExtra) {
    await sb.from("ep_shopping_extra").delete().eq("id", x.id);
    await reload();
  }

  const uncheckedItems = items.filter((i) => !checked.has(itemKey(i)));
  const uncheckedExtras = extras.filter((x) => !checked.has(`x:${x.id}`));

  /** Einkauf abschließen: Gerichte als eingekauft merken, Fehlendes ggf. auf „Noch offen“ */
  async function finish(keepMissing: boolean) {
    setBusy(true);
    const ids = included.map((p) => p.id);
    const stamp = new Date().toISOString();
    const keptExtras = keepMissing ? uncheckedExtras : [];
    const doneExtras = extras.filter((x) => !keptExtras.includes(x));
    const carry = keepMissing ? uncheckedItems.map((i) => ({ household_id: household.id, member_id: me.id, text: i.text, aisle: i.aisle, carried: true })) : [];

    const [upd, ins, del] = await Promise.all([
      ids.length ? sb.from("ep_meal_plan").update({ shopped_at: stamp }).in("id", ids) : Promise.resolve({ error: null }),
      carry.length ? sb.from("ep_shopping_extra").insert(carry).select("id") : Promise.resolve({ data: [], error: null }),
      doneExtras.length ? sb.from("ep_shopping_extra").delete().in("id", doneExtras.map((x) => x.id)) : Promise.resolve({ error: null }),
    ]);
    setBusy(false);
    setFinishOpen(false);
    const error = upd.error ?? ins.error ?? del.error;
    if (error) {
      toast({ text: error.message, tone: "error" });
      await reload();
      return;
    }
    const carriedIds = ((ins.data ?? []) as { id: string }[]).map((r) => r.id);
    setChecked(new Set());
    writeChecked(storageKey, new Set());
    setUntil(null);
    setExcluded(new Set());
    await reload();
    toast({
      text: ids.length ? `Eingekauft für ${ids.length} ${ids.length === 1 ? "Gericht" : "Gerichte"}` : "Einkauf erledigt",
      action: {
        label: "Rückgängig",
        run: async () => {
          await Promise.all([
            ids.length ? sb.from("ep_meal_plan").update({ shopped_at: null }).in("id", ids) : null,
            carriedIds.length ? sb.from("ep_shopping_extra").delete().in("id", carriedIds) : null,
            doneExtras.length
              ? sb.from("ep_shopping_extra").insert(doneExtras.map((x) => ({ household_id: household.id, member_id: me.id, text: x.text, aisle: x.aisle, carried: x.carried })))
              : null,
          ]);
          await reload();
        },
      },
    });
  }

  async function backOnList(id: string) {
    const { error } = await sb.from("ep_meal_plan").update({ shopped_at: null }).eq("id", id);
    if (error) toast({ text: error.message, tone: "error" });
    await reload();
  }

  const text = exportItems.map((i) => i.text).join("\n");
  const subtitle = !loaded
    ? "Lädt …"
    : open.length
      ? `${included.length} von ${open.length} Gerichten · ${total} Posten`
      : extras.length
        ? `${extras.length} offene Posten`
        : "Alles eingekauft";

  return (
    <>
      <PageHeader title="Einkauf" icon="🛒" width="wide" tabRoot subtitle={subtitle}>
        <div className="mt-4 grid grid-cols-2 gap-2 lg:max-w-md">
          <a
            className="btn btn-primary pressable"
            href={slug && total ? bringDeeplink(shoppingPublicUrl(slug)) : undefined}
            aria-disabled={!slug || !total}
            style={!slug || !total ? { opacity: 0.4, pointerEvents: "none" } : undefined}
            target="_blank"
            rel="noopener"
            onClick={() => inBackground(sb.from("ep_shopping_lists").update({ exported_at: new Date().toISOString() }).eq("household_id", household.id).eq("iso_week", isoWeekString(today)), "Bring-Export")}
          >
            <IconCart size={18} /> In Bring übernehmen
          </a>
          <button
            className="btn btn-gray pressable"
            disabled={!total}
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(text);
                toast({ text: "Liste kopiert – eine Zutat pro Zeile" });
              } catch {
                toast({ text: "Kopieren nicht möglich", tone: "error" });
              }
            }}
          >
            <IconCopy size={18} /> Als Text
          </button>
        </div>
        <AiPromptBar
          className="mt-4 lg:max-w-3xl"
          placeholder="Frag die KI zum Einkauf …"
          suggestions={["Fasse den Einkauf zusammen", "Was fehlt für die geplanten Gerichte?"]}
        />
      </PageHeader>

      <div className="page-wide">
        {loaded && !open.length && !extras.length && !shopped.length ? (
          <Empty title="Nichts einzukaufen" text="Plane Gerichte in der Woche – ihre Zutaten landen automatisch hier, passend zur Zahl der Esser. Auch Gerichte der nächsten Wochen." />
        ) : (
          <div className="lg:grid lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:items-start lg:gap-8">
            <div>
              {days.length > 1 && (
                <Section title="Für welche Tage kaufst du ein?">
                  <div className="scroll-x -mx-4 flex gap-2 px-4 lg:mx-0 lg:flex-wrap lg:px-0">
                    <button className="chip pressable" data-on={!until} onClick={() => setUntil(null)}>Alle</button>
                    {days.map((d) => (
                      <button key={d} className="chip pressable whitespace-nowrap" data-on={until === d} onClick={() => setUntil(d)}>
                        bis {d === today ? "heute" : dayShort(d)}
                      </button>
                    ))}
                  </div>
                </Section>
              )}

              {open.length > 0 && (
                <Section title="Gerichte" footer="Antippen, um ein Gericht diesmal nicht mit einzukaufen.">
                  <ul className="group">
                    {open.map((p) => {
                      const r = recipesById.get(p.recipe_id!)!;
                      const outOfRange = !!until && p.date > until;
                      const on = !outOfRange && !excluded.has(p.id);
                      return (
                        <li key={p.id}>
                          <button
                            className="row pressable"
                            aria-pressed={on}
                            disabled={outOfRange}
                            onClick={() =>
                              setExcluded((cur) => {
                                const next = new Set(cur);
                                if (next.has(p.id)) next.delete(p.id);
                                else next.add(p.id);
                                return next;
                              })
                            }
                          >
                            <span
                              className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full"
                              style={{ background: on ? "var(--accent)" : "transparent", boxShadow: on ? undefined : "inset 0 0 0 1.5px var(--label-3)", color: "var(--on-accent)" }}
                            >
                              {on && <IconCheck size={13} strokeWidth={2.8} />}
                            </span>
                            <span className="min-w-0 flex-1 text-left" style={{ opacity: on ? 1 : 0.5 }}>
                              <span className="t-caption block font-semibold" style={{ color: "var(--label-2)" }}>{p.date === today ? "Heute" : dayShort(p.date)} · {MEAL_LABEL[p.meal]}</span>
                              <span className="t-sub block truncate">{r.title}</span>
                            </span>
                            <span className="t-footnote tabular-nums" style={{ color: "var(--label-2)", opacity: on ? 1 : 0.5 }}>{servingsFor(p, plan, members, attendance)} Port.</span>
                          </button>
                        </li>
                      );
                    })}
                  </ul>
                  {missingIngredients.length > 0 && (
                    <p className="t-footnote mt-1.5 px-4" style={{ color: "var(--red)" }}>
                      Ohne Zutaten (nur Verweis): {missingIngredients.map((p) => recipesById.get(p.recipe_id!)!.title).join(", ")}
                    </p>
                  )}
                </Section>
              )}

              {shopped.length > 0 && (
                <Section title="Schon eingekauft" footer="Diese Gerichte stehen nicht mehr auf der Liste. Wird ein Gericht im Plan getauscht, kommt es von selbst zurück.">
                  <ul className="group">
                    {shopped.map((p) => (
                      <li key={p.id} className="row">
                        <span className="min-w-0 flex-1">
                          <span className="t-caption block font-semibold" style={{ color: "var(--label-3)" }}>{p.date === today ? "Heute" : dayShort(p.date)} · {MEAL_LABEL[p.meal]}</span>
                          <span className="t-sub block truncate" style={{ color: "var(--label-2)" }}>{recipesById.get(p.recipe_id!)!.title}</span>
                        </span>
                        <button className="btn-plain t-footnote pressable font-semibold" onClick={() => backOnList(p.id)} aria-label={`${recipesById.get(p.recipe_id!)!.title} wieder auf die Liste`}>
                          Zurückholen
                        </button>
                      </li>
                    ))}
                  </ul>
                </Section>
              )}
            </div>

            {/* Computer: Bereiche fließen in Spalten, jede Gruppe bleibt zusammen */}
            <div className="lg:columns-2 lg:gap-6 2xl:columns-3 [&>section]:break-inside-avoid lg:[&>section]:mt-0 lg:[&>section]:pt-6">
              <Section title="Noch offen" footer={extras.some((x) => x.carried) ? "Beim letzten Einkauf nicht abgehakt – oder von Hand dazugeschrieben." : undefined}>
                <ul className="group">
                  {extras.map((x) => {
                    const key = `x:${x.id}`;
                    const done = checked.has(key);
                    return (
                      <li key={x.id} className="flex items-stretch">
                        <button className="row pressable min-w-0 flex-1" onClick={() => toggle(key)} aria-pressed={done}>
                          <CheckDot done={done} />
                          <span className="t-sub min-w-0 flex-1 text-left" style={{ opacity: done ? 0.45 : 1, textDecoration: done ? "line-through" : undefined }}>{x.text}</span>
                        </button>
                        <button className="pressable flex w-12 shrink-0 items-center justify-center" style={{ color: "var(--label-3)" }} aria-label={`${x.text} löschen`} onClick={() => removeExtra(x)}>
                          <IconTrash size={18} />
                        </button>
                      </li>
                    );
                  })}
                  <li>
                    <form
                      className="row"
                      onSubmit={(e) => {
                        e.preventDefault();
                        void addExtra();
                      }}
                    >
                      <IconPlus size={20} style={{ color: "var(--accent)" }} />
                      <input className="t-sub min-w-0 flex-1 bg-transparent outline-none" placeholder="Etwas dazuschreiben, z. B. Milch" value={extraText} onChange={(e) => setExtraText(e.target.value)} aria-label="Etwas zur Einkaufsliste dazuschreiben" />
                      {extraText.trim() && <button className="btn-plain t-sub pressable font-semibold" type="submit">Hinzufügen</button>}
                    </form>
                  </li>
                </ul>
              </Section>

              {groups.map(([aisle, list]) => (
                <Section key={aisle} title={aisle}>
                  <ul className="group">
                    {list.map((i) => {
                      const key = itemKey(i);
                      const done = checked.has(key);
                      return (
                        <li key={key} className="flex items-stretch">
                          <button className="row pressable min-w-0 flex-1" onClick={() => toggle(key)} aria-pressed={done}>
                            <CheckDot done={done} />
                            <span className="min-w-0 flex-1" style={{ opacity: done ? 0.45 : 1 }}>
                              <span className="t-sub block" style={{ textDecoration: done ? "line-through" : undefined }}>{i.text}</span>
                              <span className="t-caption block truncate" style={{ color: "var(--label-2)" }}>{i.recipes.join(", ")}</span>
                            </span>
                          </button>
                          <button className="pressable flex w-12 shrink-0 items-center justify-center" style={{ color: "var(--label-3)" }} aria-label={`${i.name}: immer zu Hause`} title="Immer zu Hause – nicht mehr einkaufen" onClick={() => keepAtHome(i.name)}>
                            <IconHome size={19} />
                          </button>
                        </li>
                      );
                    })}
                  </ul>
                </Section>
              ))}

              {atHome.length > 0 && (
                <Section title="Immer zu Hause" footer="Steht nicht auf der Liste und geht nicht an Bring!. Antippen, um es wieder einzukaufen.">
                  <div className="flex flex-wrap gap-2">
                    {atHome.map((n) => {
                      const label = pantryLabel(n);
                      return (
                        <button key={n} className="chip pressable" aria-label={`${label} wieder einkaufen`} onClick={() => void pantry.remove([n])}>
                          <IconHome size={14} /> {label}
                        </button>
                      );
                    })}
                  </div>
                </Section>
              )}
            </div>

            {(included.length > 0 || extras.length > 0) && (
              <div className="mt-8 lg:col-span-2 lg:mx-auto lg:w-full lg:max-w-md">
                <button className="btn btn-primary pressable w-full" disabled={busy} onClick={() => (uncheckedItems.length || uncheckedExtras.length ? setFinishOpen(true) : void finish(false))}>
                  <IconCheck size={18} /> Einkauf erledigt
                </button>
                <p className="t-footnote mt-2 px-4 text-center" style={{ color: "var(--label-3)" }}>
                  {included.length
                    ? `${included.length === 1 ? "Das ausgewählte Gericht verschwindet" : `Die ${included.length} ausgewählten Gerichte verschwinden`} danach von der Liste – beim nächsten Einkauf kaufst du nichts doppelt.`
                    : "Abgehakte Posten verschwinden danach von der Liste."}
                </p>
              </div>
            )}
          </div>
        )}
      </div>

      <Sheet open={finishOpen} onClose={() => !busy && setFinishOpen(false)} title="Alles bekommen?">
        <p className="t-sub" style={{ color: "var(--label-2)" }}>
          {uncheckedItems.length + uncheckedExtras.length} {uncheckedItems.length + uncheckedExtras.length === 1 ? "Posten ist" : "Posten sind"} nicht abgehakt:
        </p>
        <p className="t-sub mt-2">{[...uncheckedExtras.map((x) => x.text), ...uncheckedItems.map((i) => i.text)].slice(0, 12).join(" · ")}{uncheckedItems.length + uncheckedExtras.length > 12 ? " …" : ""}</p>
        <div className="mt-5 flex flex-col gap-2">
          <button className="btn btn-primary pressable" disabled={busy} onClick={() => finish(true)}>Fehlendes auf der Liste lassen</button>
          <button className="btn btn-gray pressable" disabled={busy} onClick={() => finish(false)}>Habe alles, nur nicht abgehakt</button>
        </div>
      </Sheet>
    </>
  );
}

function CheckDot({ done }: { done: boolean }) {
  return (
    <span
      className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full transition-colors"
      style={{ background: done ? "var(--accent)" : "transparent", boxShadow: done ? undefined : "inset 0 0 0 1.5px var(--label-3)", color: "var(--on-accent)" }}
    >
      {done && <IconCheck size={15} strokeWidth={2.6} />}
    </span>
  );
}
