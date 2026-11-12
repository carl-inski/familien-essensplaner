"use client";

// Einkauf über Wochengrenzen: was für die kommenden Gerichte noch fehlt.
// Jeder Haken ist ein Kauf in der Datenbank (ep_purchases) – alle im Laden sehen
// denselben Stand, und ändert sich der Plan, bleibt nur die Differenz offen
// (Rechnung in lib/shopping.ts).

import { useEffect, useMemo, useState } from "react";
import { useApp } from "@/components/app-data";
import { BringLogo, KnusprLogo } from "@/components/brand-icons";
import { IconCheck, IconCopy, IconHome, IconPlus, IconTrash } from "@/components/icons";
import { PageHeader } from "@/components/nav";
import { usePantry } from "@/components/pantry";
import { Sheet } from "@/components/sheet";
import { SwipeRow } from "@/components/shopping/swipe-row";
import { useShopping, type ShoppingExtra } from "@/components/shopping/use-shopping";
import { useToast } from "@/components/toast";
import { Empty, Section } from "@/components/ui";
import { aisleFor } from "@/lib/aisles";
import { bringDeeplink, shoppingPublicUrl } from "@/lib/bring";
import { knusprLinks, knusprPrompt } from "@/lib/knuspr";
import { WEEKDAY_SHORT, formatDateDE, formatStampDE, isoWeekString, weekdayIndex } from "@/lib/dates";
import { MEAL_LABEL, slotKey } from "@/lib/meals";
import { pantryEntriesFor, pantryEntriesToAdd, pantryLabel } from "@/lib/pantry";
import { buildShoppingList, servingsFor } from "@/lib/planning";
import { extraKey, isShoppable, purchasesFor, shoppingState, type BoughtItem, type NewPurchase, type OpenItem, type StockItem } from "@/lib/shopping";
import type { ShoppingItem } from "@/lib/types";
import { inBackground } from "@/lib/background";
import { keepCompoundTogether } from "@/lib/text";
import { useIsDesktop } from "@/components/use-media";
import { haptic } from "@/lib/haptics";

// „Einkauf erledigt“ räumt die durchgestrichenen Zeilen weg – gemerkt je Gerät
function readCleared(key: string): string {
  try {
    return localStorage.getItem(key) ?? "";
  } catch {
    return "";
  }
}
function writeCleared(key: string, at: string) {
  try {
    localStorage.setItem(key, at);
  } catch {
    // privater Modus – gilt dann nur bis zum Neuladen
  }
}

// Kurzer Fingerabdruck der Liste: neue Bring!-URL, sobald sich etwas ändert (Bring! merkt sich Links)
function listVersion(texts: string[]): string {
  let h = 5381;
  for (const ch of texts.join("\n")) h = ((h * 33) ^ ch.charCodeAt(0)) >>> 0;
  return h.toString(36);
}
const dayShort = (d: string) => `${WEEKDAY_SHORT[weekdayIndex(d)]} ${formatDateDE(d, { day: "numeric", month: "numeric" })}`;

export default function ShoppingPage() {
  const { today, sb, household, me, recipesById, members } = useApp();
  const toast = useToast();
  const { plan, attendance, extras, purchases, sync, loaded, reload, buy, undo } = useShopping();
  const pantry = usePantry();
  const storageKey = `einkauf-erledigt-${household.id}`;
  const [clearedAt, setClearedAt] = useState(() => readCleared(storageKey));
  // „Jetzt“ für „vor Kurzem abgehakt“ – jede Minute frisch
  const [now, setNow] = useState(() => new Date().toISOString());
  useEffect(() => {
    const t = setInterval(() => setNow(new Date().toISOString()), 60000);
    return () => clearInterval(t);
  }, []);
  // Bis zu welchem Tag eingekauft wird (null = alle) und einzeln abgewählte Gerichte
  const [until, setUntil] = useState<string | null>(null);
  const [excluded, setExcluded] = useState<Set<string>>(new Set());
  const [finishOpen, setFinishOpen] = useState(false);
  const [knusprOpen, setKnusprOpen] = useState(false);
  const desktop = useIsDesktop();
  const [busy, setBusy] = useState(false);
  const [extraText, setExtraText] = useState("");
  const [slug, setSlug] = useState<string | null>(null);
  // Welcher Listenstand gerade öffentlich für Bring! bereitliegt
  const [savedVersion, setSavedVersion] = useState<string | null>(null);

  const dishes = useMemo(
    () => plan.filter((p) => isShoppable(p, today) && recipesById.has(p.recipe_id!)).sort((a, b) => slotKey(a.date, a.meal).localeCompare(slotKey(b.date, b.meal))),
    [plan, today, recipesById],
  );
  // Erst ohne Auswahl rechnen: welche Gerichte sind schon ganz eingekauft?
  const overall = useMemo(
    () => shoppingState({ plan, recipes: recipesById, members, attendance, pantry: pantry.set, purchases, today, now }),
    [plan, recipesById, members, attendance, pantry.set, purchases, today, now],
  );
  const open = useMemo(() => dishes.filter((p) => !overall.covered.has(p.id)), [dishes, overall]);
  const shopped = useMemo(() => dishes.filter((p) => overall.covered.has(p.id)), [dishes, overall]);
  const days = useMemo(() => [...new Set(open.map((p) => p.date))], [open]);
  const included = useMemo(() => open.filter((p) => !excluded.has(p.id) && (!until || p.date <= until)), [open, excluded, until]);
  const includedIds = useMemo(() => new Set(included.map((p) => p.id)), [included]);

  const state = useMemo(
    () => shoppingState({ plan, recipes: recipesById, members, attendance, pantry: pantry.set, purchases, today, now, include: (e) => includedIds.has(e.id) }),
    [plan, recipesById, members, attendance, pantry.set, purchases, today, now, includedIds],
  );
  const items = state.open;
  const clientIdsOf = (ids: string[]) => purchases.filter((p) => ids.includes(p.id)).map((p) => p.client_id);
  // Durchgestrichen bleibt, was seit dem letzten „Einkauf erledigt“ abgehakt wurde
  const bought = useMemo(
    () => state.bought.filter((b) => purchases.some((p) => b.purchaseIds.includes(p.id) && p.bought_at > clearedAt)),
    [state.bought, purchases, clearedAt],
  );
  const groups = useMemo(() => {
    const byAisle = new Map<string, { open: OpenItem[]; done: BoughtItem[] }>();
    const slot = (aisle: string) => byAisle.get(aisle) ?? byAisle.set(aisle, { open: [], done: [] }).get(aisle)!;
    for (const i of items) slot(i.aisle).open.push(i);
    for (const b of bought) slot(b.aisle).done.push(b);
    return [...byAisle.entries()];
  }, [items, bought]);
  const all = useMemo(
    () => buildShoppingList(plan, recipesById, members, attendance, pantry.set, (e) => includedIds.has(e.id)),
    [plan, recipesById, members, attendance, pantry.set, includedIds],
  );
  const atHome = useMemo(() => [...new Set(all.filter((i) => i.pantry).flatMap((i) => pantryEntriesFor(i.name, pantry.set)))].sort((a, b) => a.localeCompare(b, "de")), [all, pantry.set]);
  const missingIngredients = included.filter((p) => !(recipesById.get(p.recipe_id!)?.ep_recipe_ingredients ?? []).length);

  const extraDone = useMemo(() => new Map(purchases.filter((p) => p.item_key.startsWith("x:")).map((p) => [p.item_key, p.client_id])), [purchases]);
  const uncheckedExtras = extras.filter((x) => !extraDone.has(extraKey(x.id)));

  // Für Bring!, Knuspr und „Text“: was noch fehlt, plus „Noch offen“ – ohne das schon Abgehakte
  const exportItems: ShoppingItem[] = useMemo(
    () => [
      ...extras
        .filter((x) => !extraDone.has(extraKey(x.id)))
        .map((x) => ({ name: x.text, amount: null, unit: null, text: x.text, aisle: x.aisle ?? aisleFor(x.text), recipes: [] })),
      ...items.map(({ name, amount, unit, text, aisle, recipes }) => ({ name, amount, unit, text, aisle, recipes })),
    ],
    [extras, items, extraDone],
  );
  const total = exportItems.length;
  const version = useMemo(() => listVersion(exportItems.map((i) => i.text)), [exportItems]);
  const bringReady = !!slug && !!total && savedVersion === version;

  const newId = () => crypto.randomUUID();

  /** Zeile abhaken: als Kauf für die beteiligten Gerichte sichern */
  function check(item: OpenItem) {
    haptic("light");
    const ids = buy(purchasesFor(item, household.id, me.id, newId));
    toast({ text: `${item.name} abgehakt`, action: { label: "Rückgängig", run: () => undo(ids) } });
  }

  function toggleExtra(x: ShoppingExtra) {
    const key = extraKey(x.id);
    const done = extraDone.get(key);
    if (done) return undo([done]);
    haptic("light");
    buy([{ client_id: newId(), household_id: household.id, meal_plan_id: null, item_key: key, name: x.text, amount: null, unit: null, bought_by: me.id }]);
  }

  /** Nicht kaufen, weil es zu Hause noch da ist – deckt den Bedarf wie ein Kauf */
  function stillThere(item: OpenItem) {
    const ids = buy(purchasesFor(item, household.id, me.id, newId, "vorrat"));
    toast({ text: `${item.name}: ist noch da`, action: { label: "Rückgängig", run: () => undo(ids) } });
  }

  /** „Ist noch da“ stimmt nicht mehr: Käufe verwerfen, damit die Zutat wieder auf der Liste landet */
  function usedUp(item: StockItem) {
    const rows = purchases.filter((p) => item.purchaseIds.includes(p.id));
    undo(rows.map((p) => p.client_id));
    const again: NewPurchase[] = rows.map(({ household_id, meal_plan_id, item_key, name, amount, unit, bought_by }) => ({ client_id: newId(), household_id, meal_plan_id, item_key, name, amount, unit, bought_by }));
    toast({ text: `${item.name}: nicht mehr da`, action: { label: "Rückgängig", run: () => void buy(again) } });
  }

  // Snapshot für die öffentliche Bring!-Seite aktuell halten
  useEffect(() => {
    if (!loaded) return;
    const t = setTimeout(async () => {
      const { data, error } = await sb
        .from("ep_shopping_lists")
        .upsert({ household_id: household.id, iso_week: isoWeekString(today), items: exportItems }, { onConflict: "household_id,iso_week" })
        .select("public_slug")
        .single();
      if (error) return;
      setSlug((data as { public_slug: string }).public_slug);
      setSavedVersion(version);
    }, 300);
    return () => clearTimeout(t);
  }, [loaded, exportItems, version, today, household.id, sb]);

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

  const uncheckedItems = items;

  /**
   * Einkauf abschließen. keepMissing: Was nicht abgehakt ist, bleibt einfach offen.
   * Sonst gilt alles als gekauft („habe alles, nur nicht abgehakt“).
   */
  async function finish(keepMissing: boolean) {
    setBusy(true);
    const boughtIds = keepMissing ? [] : buy(items.flatMap((i) => purchasesFor(i, household.id, me.id, newId)));
    const doneExtras = keepMissing ? extras.filter((x) => extraDone.has(extraKey(x.id))) : extras;
    const extraPurchases = doneExtras.map((x) => extraDone.get(extraKey(x.id))).filter((id): id is string => !!id);
    // Für die bisherige App-Version: ganz eingekaufte Gerichte auch dort als erledigt markieren
    const ids = (keepMissing ? dishes.filter((p) => state.covered.has(p.id)) : [...included, ...shopped]).filter((p) => !p.shopped_at).map((p) => p.id);
    const stamp = new Date().toISOString();

    undo(extraPurchases);
    const [upd, del] = await Promise.all([
      ids.length ? sb.from("ep_meal_plan").update({ shopped_at: stamp }).in("id", ids) : Promise.resolve({ error: null }),
      doneExtras.length ? sb.from("ep_shopping_extra").delete().in("id", doneExtras.map((x) => x.id)) : Promise.resolve({ error: null }),
    ]);
    setBusy(false);
    setFinishOpen(false);
    const error = upd.error ?? del.error;
    if (error) {
      toast({ text: error.message, tone: "error" });
      await reload();
      return;
    }
    haptic("success");
    const before = clearedAt;
    const left = keepMissing ? items.length : 0;
    setClearedAt(stamp);
    writeCleared(storageKey, stamp);
    setUntil(null);
    setExcluded(new Set());
    await reload();
    toast({
      text: left ? `Erledigt – ${left} ${left === 1 ? "Posten bleibt" : "Posten bleiben"} offen` : "Einkauf erledigt",
      action: {
        label: "Rückgängig",
        run: async () => {
          undo(boughtIds);
          setClearedAt(before);
          writeCleared(storageKey, before);
          await Promise.all([
            ids.length ? sb.from("ep_meal_plan").update({ shopped_at: null }).in("id", ids) : null,
            doneExtras.length
              ? sb.from("ep_shopping_extra").insert(doneExtras.map((x) => ({ household_id: household.id, member_id: me.id, text: x.text, aisle: x.aisle, carried: x.carried })))
              : null,
          ]);
          await reload();
        },
      },
    });
  }

  /** Gericht zurück auf die Liste: seine Käufe verwerfen */
  async function backOnList(id: string) {
    undo(purchases.filter((p) => p.meal_plan_id === id).map((p) => p.client_id));
    const { error } = await sb.from("ep_meal_plan").update({ shopped_at: null }).eq("id", id);
    if (error) toast({ text: error.message, tone: "error" });
    await reload();
  }

  const text = exportItems.map((i) => i.text).join("\n");
  const knuspr = knusprPrompt(exportItems.map((i) => i.text));
  const subtitle = !loaded
    ? "Lädt …"
    : sync === "offline"
      ? "Offline – deine Haken werden nachgeholt"
    : open.length
      ? `${included.length} von ${open.length} Gerichten · ${total} Posten`
      : extras.length
        ? `${extras.length} offene Posten`
        : "Alles eingekauft";

  return (
    <>
      <PageHeader
        title="Einkauf"
        width="wide"
        tabRoot
        subtitle={subtitle}
      >
        <div className="mt-4 grid grid-cols-3 gap-2 lg:max-w-lg">
          <a
            className="btn btn-brand pressable"
            style={{ background: "#333e44", color: "#fff", ...(!bringReady ? { opacity: 0.4, pointerEvents: "none" } : {}) }}
            href={bringReady ? bringDeeplink(`${shoppingPublicUrl(slug)}?v=${version}`) : undefined}
            aria-disabled={!bringReady}
            aria-label="In Bring! übernehmen"
            target="_blank"
            rel="noopener"
            onClick={() => inBackground(sb.from("ep_shopping_lists").update({ exported_at: new Date().toISOString() }).eq("household_id", household.id).eq("iso_week", isoWeekString(today)), "Bring-Export")}
          >
            <BringLogo size={23} /> Bring!
          </a>
          <button
            className="btn btn-brand pressable"
            style={{ background: "#ff7400", color: "#fff" }}
            disabled={!total}
            aria-label="Bei Knuspr bestellen"
            onClick={() => setKnusprOpen(true)}
          >
            <KnusprLogo size={22} /> Knuspr
          </button>
          <button
            className="btn btn-gray btn-brand pressable"
            disabled={!total}
            aria-label="Liste als Text kopieren"
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(text);
                toast({ text: "Liste kopiert – eine Zutat pro Zeile" });
              } catch {
                toast({ text: "Kopieren nicht möglich", tone: "error" });
              }
            }}
          >
            <IconCopy size={18} /> Text
          </button>
        </div>
      </PageHeader>

      <div className="page-wide">
        {loaded && !open.length && !extras.length && !shopped.length && !state.stock.length ? (
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
                <Section title="Schon eingekauft" footer="Für diese Gerichte ist alles da. Kommen Esser dazu, steht nur die Differenz wieder auf der Liste.">
                  <ul className="group">
                    {shopped.map((p) => (
                      <li key={p.id} className="row">
                        <span className="min-w-0 flex-1">
                          <span className="t-caption block font-semibold" style={{ color: "var(--label-2)" }}>{p.date === today ? "Heute" : dayShort(p.date)} · {MEAL_LABEL[p.meal]}</span>
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
                    const done = extraDone.has(extraKey(x.id));
                    return (
                      <li key={x.id} className="flex items-stretch">
                        <button className="row pressable min-w-0 flex-1" onClick={() => toggleExtra(x)} aria-pressed={done}>
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

              {groups.map(([aisle, list], gi) => (
                <Section
                  key={aisle}
                  title={aisle}
                  footer={gi === 0 && !desktop ? "Tipp: Nach links wischen oder lange drücken – „Noch da“, wenn ihr es gerade zu Hause habt, „Immer da“, wenn es nie auf die Liste soll." : undefined}
                >
                  <ul className="group">
                    {list.open.map((i) => (
                      <SwipeRow
                        key={i.key}
                        desktop={desktop}
                        actionLabel={`${i.name}: immer zu Hause`}
                        actionIcon={<IconHome size={19} />}
                        onAction={() => void keepAtHome(i.name)}
                        secondary={{ label: `${i.name}: ist noch da`, short: "Noch da", icon: <IconCheck size={19} />, run: () => stillThere(i) }}
                      >
                        {({ onClick }) => (
                          <button className="row pressable min-w-0 flex-1" onClick={onClick(() => check(i))} aria-pressed={false}>
                            <CheckDot done={false} />
                            <span className="min-w-0 flex-1">
                              <span className="t-sub block">{keepCompoundTogether(i.text)}</span>
                              <span className="t-caption block truncate" style={{ color: "var(--label-2)" }}>
                                {i.usedStock ? "Rest ist noch da · " : ""}{i.recipes.join(", ")}
                              </span>
                            </span>
                          </button>
                        )}
                      </SwipeRow>
                    ))}
                    {list.done.map((b) => (
                      <li key={`done-${b.key}`}>
                        <button className="row pressable w-full" onClick={() => undo(clientIdsOf(b.purchaseIds))} aria-pressed aria-label={`${b.text} – abgehakt, antippen zum Zurücknehmen`}>
                          <CheckDot done />
                          <span className="min-w-0 flex-1 text-left" style={{ opacity: 0.45 }}>
                            <span className="t-sub block" style={{ textDecoration: "line-through" }}>{keepCompoundTogether(b.text)}</span>
                            {(b.fromStock || (b.by && b.by !== me.id)) && (
                              <span className="t-caption block truncate" style={{ color: "var(--label-2)" }}>
                                {[b.fromStock ? "war noch da" : null, b.by && b.by !== me.id ? `von ${members.find((m) => m.id === b.by)?.name ?? "jemandem"}` : null].filter(Boolean).join(" · ")}
                              </span>
                            )}
                          </span>
                        </button>
                      </li>
                    ))}
                  </ul>
                </Section>
              ))}

              {state.stock.length > 0 && (
                <Section title="Ist noch da" footer="Zu Hause, aber gerade für kein Gericht gebraucht. Zählt beim nächsten passenden Gericht mit. Mehr eintragen: Haushalt → Vorrat.">
                  <ul className="group">
                    {state.stock.map((x) => (
                      <li key={x.key} className="row">
                        <span className="min-w-0 flex-1">
                          <span className="t-sub block">{keepCompoundTogether(x.text)}</span>
                          <span className="t-caption block" style={{ color: "var(--label-2)" }}>seit {formatStampDE(x.since)}</span>
                        </span>
                        <button className="btn-plain t-footnote pressable font-semibold" onClick={() => usedUp(x)} aria-label={`${x.name} ist nicht mehr da`}>Nicht mehr da</button>
                      </li>
                    ))}
                  </ul>
                </Section>
              )}

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
                <p className="t-footnote mt-2 px-4 text-center" style={{ color: "var(--label-2)" }}>
                  {included.length
                    ? "Räumt Abgehaktes weg. Jeder Haken ist sofort für alle gesichert – auch ohne diesen Knopf."
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
          <button className="btn btn-primary pressable" disabled={busy} onClick={() => finish(true)}>Fehlendes bleibt auf der Liste</button>
          <button className="btn btn-gray pressable" disabled={busy} onClick={() => finish(false)}>Habe alles, nur nicht abgehakt</button>
        </div>
      </Sheet>

      <Sheet open={knusprOpen} onClose={() => setKnusprOpen(false)} title="Bei Knuspr bestellen">
        <p className="t-sub" style={{ color: "var(--label-2)" }}>
          Die KI legt die {uncheckedItems.length + uncheckedExtras.length} offenen Posten in deinen Knuspr-Warenkorb. Bestellen und Liefertermin wählst du danach selbst in der Knuspr-App.
        </p>
        <div className="mt-5 flex flex-col gap-2">
          <a className="btn btn-primary pressable" href={knusprLinks(knuspr).claude} target="_blank" rel="noopener" onClick={() => setKnusprOpen(false)}>In Claude öffnen</a>
          <a className="btn btn-gray pressable" href={knusprLinks(knuspr).chatgpt} target="_blank" rel="noopener" onClick={() => setKnusprOpen(false)}>In ChatGPT öffnen</a>
          <button
            className="btn-plain t-sub pressable mt-1 font-semibold"
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(knuspr);
                toast({ text: "Auftrag kopiert – in Claude oder ChatGPT einfügen" });
              } catch {
                toast({ text: "Kopieren nicht möglich", tone: "error" });
              }
            }}
          >
            Auftrag kopieren
          </button>
        </div>
        <p className="t-footnote mt-4" style={{ color: "var(--label-2)" }}>
          Einmalig nötig: in Claude unter Einstellungen → Konnektoren bzw. in ChatGPT unter Apps „Knuspr“ hinzufügen und mit deinem Knuspr-Konto anmelden.
        </p>
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
