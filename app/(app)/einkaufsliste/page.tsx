"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useMemo, useState } from "react";
import { useApp } from "@/components/app-data";
import { IconCart, IconCheck, IconChevronLeft, IconChevronRight, IconCopy } from "@/components/icons";
import { AccountButton } from "@/components/account-button";
import { IconButton, PageHeader } from "@/components/nav";
import { useToast } from "@/components/toast";
import { Empty, Section } from "@/components/ui";
import { useWeek } from "@/components/week/use-week";
import { bringDeeplink, shoppingPublicUrl } from "@/lib/bring";
import { WEEKDAY_SHORT, isoWeekString, shiftWeek, weekNumberLabel, weekdayIndex } from "@/lib/dates";
import { MEAL_LABEL, slotKey } from "@/lib/meals";
import { buildShoppingList, groupByAisle, servingsFor } from "@/lib/planning";

export default function ShoppingPage() {
  return (
    <Suspense>
      <Shopping />
    </Suspense>
  );
}

// Abhak-Status pro Woche nur auf diesem Gerät
function readChecked(key: string): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(key) ?? "[]"));
  } catch {
    return new Set();
  }
}

function Shopping() {
  const params = useSearchParams();
  const router = useRouter();
  const { today, sb, household, recipesById, members } = useApp();
  const toast = useToast();
  const isoWeek = params.get("w") ?? isoWeekString(today);
  const { plan, attendance, loaded } = useWeek(isoWeek);
  const [slug, setSlug] = useState<string | null>(null);
  const storageKey = `einkauf-${household.id}-${isoWeek}`;
  const [checked, setChecked] = useState<Set<string>>(() => readChecked(storageKey));
  const [checkedFor, setCheckedFor] = useState(storageKey);
  if (checkedFor !== storageKey) {
    // Woche gewechselt: Abhak-Status dieser Woche laden
    setCheckedFor(storageKey);
    setChecked(readChecked(storageKey));
  }

  const items = useMemo(() => buildShoppingList(plan, recipesById, members, attendance), [plan, recipesById, members, attendance]);
  const groups = useMemo(() => groupByAisle(items), [items]);
  const dishes = plan
    .filter((p) => p.recipe_id && !p.leftover_of && p.status !== "ausgefallen")
    .sort((a, b) => slotKey(a.date, a.meal).localeCompare(slotKey(b.date, b.meal)))
    .map((p) => ({ p, r: recipesById.get(p.recipe_id!)!, servings: servingsFor(p, plan, members, attendance) }))
    .filter((d) => d.r);
  const missingIngredients = dishes.filter((d) => !(d.r.ep_recipe_ingredients ?? []).length);

  const toggle = (key: string) =>
    setChecked((cur) => {
      const next = new Set(cur);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      try {
        localStorage.setItem(storageKey, JSON.stringify([...next]));
      } catch {}
      return next;
    });

  // Snapshot für die öffentliche Bring!-Seite aktuell halten
  useEffect(() => {
    if (!loaded) return;
    const t = setTimeout(async () => {
      const { data, error } = await sb
        .from("ep_shopping_lists")
        .upsert({ household_id: household.id, iso_week: isoWeek, items }, { onConflict: "household_id,iso_week" })
        .select("public_slug")
        .single();
      if (!error) setSlug((data as { public_slug: string }).public_slug);
    }, 400);
    return () => clearTimeout(t);
  }, [loaded, items, isoWeek, household.id, sb]);

  const text = items.map((i) => i.text).join("\n");
  const go = (w: string) => router.replace(`/einkaufsliste?w=${w}`, { scroll: false });

  return (
    <>
      <PageHeader
        title="Einkauf"
        width="wide"
        subtitle={`${weekNumberLabel(isoWeek)} · ${items.length} Zutaten aus ${dishes.length} Gerichten`}
        trailing={
          <>
            <IconButton label="Vorige Woche" onClick={() => go(shiftWeek(isoWeek, -1))}><IconChevronLeft /></IconButton>
            <IconButton label="Nächste Woche" onClick={() => go(shiftWeek(isoWeek, 1))}><IconChevronRight /></IconButton>
            <AccountButton />
          </>
        }
      >
        <div className="mt-4 grid grid-cols-2 gap-2 lg:max-w-md">
          <a
            className="btn btn-primary pressable"
            href={slug && items.length ? bringDeeplink(shoppingPublicUrl(slug)) : undefined}
            aria-disabled={!slug || !items.length}
            style={!slug || !items.length ? { opacity: 0.4, pointerEvents: "none" } : undefined}
            target="_blank"
            rel="noopener"
            onClick={() => void sb.from("ep_shopping_lists").update({ exported_at: new Date().toISOString() }).eq("household_id", household.id).eq("iso_week", isoWeek)}
          >
            <IconCart size={18} /> In Bring übernehmen
          </a>
          <button
            className="btn btn-gray pressable"
            disabled={!items.length}
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
      </PageHeader>

      <div className="page-wide">
        {loaded && !dishes.length ? (
          <Empty title="Noch nichts geplant" text="Plane Gerichte in der Woche – die Zutaten landen automatisch hier, passend zur Zahl der Esser." />
        ) : (
          <div className="lg:grid lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:items-start lg:gap-8">
            <Section title="Gerichte">
              <ul className="group">
                {dishes.map(({ p, r, servings }) => (
                  <li key={p.id} className="row">
                    <span className="t-footnote w-[4.5rem] shrink-0 font-semibold whitespace-nowrap" style={{ color: "var(--label-2)" }}>{WEEKDAY_SHORT[weekdayIndex(p.date)]} {MEAL_LABEL[p.meal]}</span>
                    <span className="t-sub flex-1 truncate">{r.title}</span>
                    <span className="t-footnote tabular-nums" style={{ color: "var(--label-2)" }}>{servings} Port.</span>
                  </li>
                ))}
              </ul>
              {missingIngredients.length > 0 && (
                <p className="t-footnote mt-1.5 px-4" style={{ color: "var(--red)" }}>
                  Ohne Zutaten (nur Verweis): {missingIngredients.map((d) => d.r.title).join(", ")}
                </p>
              )}
            </Section>

            {/* Computer: Bereiche fließen in Spalten, jede Gruppe bleibt zusammen */}
            <div className="lg:columns-2 lg:gap-6 2xl:columns-3 [&>section]:break-inside-avoid lg:[&>section]:mt-0 lg:[&>section]:pt-6">
            {groups.map(([aisle, list]) => (
              <Section key={aisle} title={aisle}>
                <ul className="group">
                  {list.map((i) => {
                    const key = `${i.name}|${i.unit ?? ""}`;
                    const done = checked.has(key);
                    return (
                      <li key={key}>
                        <button className="row pressable" onClick={() => toggle(key)} aria-pressed={done}>
                          <span
                            className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full transition-colors"
                            style={{ background: done ? "var(--accent)" : "transparent", boxShadow: done ? undefined : "inset 0 0 0 1.5px var(--label-3)", color: "var(--on-accent)" }}
                          >
                            {done && <IconCheck size={15} strokeWidth={2.6} />}
                          </span>
                          <span className="min-w-0 flex-1" style={{ opacity: done ? 0.45 : 1 }}>
                            <span className="t-sub block" style={{ textDecoration: done ? "line-through" : undefined }}>{i.text}</span>
                            <span className="t-caption block truncate" style={{ color: "var(--label-2)" }}>{i.recipes.join(", ")}</span>
                          </span>
                        </button>
                      </li>
                    );
                  })}
                </ul>
              </Section>
            ))}
            </div>
            <p className="t-footnote mt-6 px-4 text-center lg:col-span-2" style={{ color: "var(--label-3)" }}>
              Bring! öffnet die Liste als Rezept „Wocheneinkauf {weekNumberLabel(isoWeek)}“ – dort alle Zutaten übernehmen.
            </p>
          </div>
        )}
      </div>
    </>
  );
}
