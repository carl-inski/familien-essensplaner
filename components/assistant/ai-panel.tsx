"use client";

// KI am Computer: Seitenpanel rechts (⌘J), Knopf für die obere Leiste und eine
// Eingabezeile mit passenden Vorschlägen für einzelne Seiten.

import { useChat } from "@ai-sdk/react";
import { useState } from "react";
import { IconArrowUp, IconClose, IconEdit, IconSparkles } from "@/components/icons";
import type { AssistantContext } from "@/lib/ai/assistant-schemas";
import { AssistantChat } from "./assistant-chat";
import { useAssistant } from "./assistant-provider";

export function AiPanel() {
  const { panelOpen, panelAvailable, setPanelOpen, kontext, setKontext, reset, chat } = useAssistant();
  const { messages } = useChat({ chat });
  if (!panelAvailable) return null;
  return (
    <aside className="ai-panel fixed inset-y-0 right-0 z-40 flex flex-col" data-open={panelOpen} aria-label="KI-Assistent" inert={!panelOpen}>
      <header className="flex h-12 shrink-0 items-center gap-2.5 pr-2 pl-4">
        <span className="ai-orb flex h-7 w-7 shrink-0 items-center justify-center rounded-full"><IconSparkles size={15} /></span>
        <div className="min-w-0 flex-1 leading-tight">
          <p className="t-sub font-semibold">KI-Assistent</p>
          {kontext.rezept_titel && (
            <p className="t-caption flex items-center gap-1" style={{ color: "var(--label-2)" }}>
              <span className="truncate">Zum Rezept „{kontext.rezept_titel}“</span>
              <button className="pressable shrink-0 rounded" aria-label="Rezept-Bezug entfernen" title="Rezept-Bezug entfernen" onClick={() => setKontext({})}>
                <IconClose size={12} />
              </button>
            </p>
          )}
        </div>
        {messages.length > 0 && (
          <button className="icon-button pressable flex h-8 w-8 items-center justify-center rounded-md" aria-label="Neues Gespräch" title="Neues Gespräch" onClick={reset} style={{ color: "var(--label-2)" }}>
            <IconEdit size={18} />
          </button>
        )}
        <button className="icon-button pressable flex h-8 w-8 items-center justify-center rounded-md" aria-label="KI ausblenden" title="KI ausblenden (⌘J)" onClick={() => setPanelOpen(false)} style={{ color: "var(--label-2)" }}>
          <IconClose size={18} />
        </button>
      </header>
      <AssistantChat variant="panel" />
    </aside>
  );
}

/** Knopf oben rechts: öffnet und schließt das Panel – auf einer Rezeptseite mit Bezug zum Rezept */
export function AiButton({ kontext }: { kontext?: AssistantContext }) {
  const { panelOpen, panelAvailable, setPanelOpen, aiEnabled, ask } = useAssistant();
  if (!panelAvailable || aiEnabled === false) return null;
  return (
    <button className="ai-button pressable" aria-pressed={panelOpen} onClick={() => (panelOpen ? setPanelOpen(false) : ask(undefined, kontext))} title="KI ein- und ausblenden (⌘J)">
      <IconSparkles size={15} />
      <span>KI fragen</span>
      <kbd>⌘J</kbd>
    </button>
  );
}

/** Eingabezeile „Frag die KI …“ mit Vorschlägen, passend zur Seite */
export function AiPromptBar({ placeholder, suggestions, kontext, className = "" }: { placeholder: string; suggestions: string[]; kontext?: AssistantContext; className?: string }) {
  const { ask, aiEnabled } = useAssistant();
  const [q, setQ] = useState("");
  if (aiEnabled === false) return null;
  return (
    <div className={`ai-bar relative ${className}`}>
      <form
        className="ai-bar-field flex items-center gap-2.5"
        onSubmit={(e) => {
          e.preventDefault();
          (document.activeElement as HTMLElement | null)?.blur();
          if (!q.trim()) return ask(undefined, kontext);
          ask(q, kontext);
          setQ("");
        }}
      >
        <span className="ai-orb flex h-7 w-7 shrink-0 items-center justify-center rounded-full"><IconSparkles size={15} /></span>
        <input className="min-w-0 flex-1 bg-transparent outline-none" value={q} onChange={(e) => setQ(e.target.value)} placeholder={placeholder} aria-label="Frage an die KI" />
        <button type="submit" className="pressable flex h-7 w-7 shrink-0 items-center justify-center rounded-full disabled:opacity-30" style={{ background: "var(--accent)", color: "var(--on-accent)" }} aria-label="Fragen" disabled={!q.trim()}>
          <IconArrowUp size={16} strokeWidth={2.4} />
        </button>
      </form>
      {/* Handy: Vorschläge als Zeile darunter. Computer: Menü unter dem Feld, sobald es den Fokus hat (wie Notion AI) */}
      {suggestions.length > 0 && (
        <div className="ai-suggestions scroll-x mt-2 flex gap-1.5" role="group" aria-label="Vorschläge für die KI">
          <p className="ai-suggestions-title hidden">Vorschläge</p>
          {suggestions.map((s) => (
            <button
              key={s}
              className="ai-chip pressable"
              onMouseDown={(e) => e.preventDefault()}
              onClick={() => {
                (document.activeElement as HTMLElement | null)?.blur();
                ask(s, kontext);
              }}
            >
              <IconSparkles size={12} /> {s}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
