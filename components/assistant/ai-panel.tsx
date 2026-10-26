"use client";

// KI am Computer: Seitenpanel rechts (⌘J) und Knopf für die obere Leiste.

import { useChat } from "@ai-sdk/react";
import { IconClose, IconEdit, IconSparkles } from "@/components/icons";
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
