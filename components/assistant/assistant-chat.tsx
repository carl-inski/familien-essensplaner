"use client";

// Der Chat mit dem Assistenten – als ganze Seite (Handy, /assistent) oder als Seitenpanel am Computer.

import { useChat } from "@ai-sdk/react";
import type { FileUIPart, UIMessage } from "ai";
import { useEffect, useRef, useState } from "react";
import { useAiStatus } from "@/components/ai-status";
import { IconArrowUp, IconCamera, IconClose, IconSparkles } from "@/components/icons";
import { useToast } from "@/components/toast";
import { Empty } from "@/components/ui";
import { WRITE_TOOLS, type WriteTool } from "@/lib/ai/assistant-schemas";
import { shrinkImage } from "@/lib/image";
import { useAssistant } from "./assistant-provider";
import { ConfirmCard, type ToolPart } from "./confirm-card";
import { RichText } from "./rich-text";

export const SUGGESTIONS = [
  "Füll die offenen Abende dieser Woche",
  "Was steht diese Woche an?",
  "Was koche ich mit Zucchini und Feta?",
  "Was haben wir lange nicht gegessen?",
];

const READ_LABEL: Record<string, [string, string]> = {
  rezepte_suchen: ["Sucht in den Rezepten …", "Rezepte durchsucht"],
  rezept_lesen: ["Liest das Rezept …", "Rezept gelesen"],
  woche_lesen: ["Schaut in die Woche …", "Woche angesehen"],
  lange_nicht_gegessen: ["Sucht lange nicht Gegessenes …", "Kochhistorie angesehen"],
  regal: ["Schaut ins Regal …", "Regal angesehen"],
  einkaufsliste: ["Stellt die Einkaufsliste zusammen …", "Einkaufsliste angesehen"],
  vorschlaege_finden: ["Sucht passende Gerichte …", "Passende Gerichte gesucht"],
  rezepte_mit_zutaten: ["Sucht Rezepte mit deinen Zutaten …", "Rezepte mit deinen Zutaten gesucht"],
};

function errorText(e: Error | undefined): string | null {
  if (!e) return null;
  try {
    return (JSON.parse(e.message) as { error?: string }).error ?? e.message;
  } catch {
    return e.message || "Die KI hat gerade nicht geantwortet.";
  }
}

export function AssistantChat({ variant }: { variant: "page" | "panel" }) {
  const { chat, panelOpen } = useAssistant();
  const { messages, sendMessage, addToolOutput, status, error, stop, clearError } = useChat({ chat });
  const { status: ai } = useAiStatus();
  const toast = useToast();
  const [input, setInput] = useState("");
  const [files, setFiles] = useState<FileUIPart[]>([]);
  const fileRef = useRef<HTMLInputElement>(null);
  const bottom = useRef<HTMLDivElement>(null);
  const textRef = useRef<HTMLTextAreaElement>(null);
  const panel = variant === "panel";

  const busy = status === "submitted" || status === "streaming";
  const pendingConfirm = messages.some((m) =>
    m.parts.some((p) => WRITE_TOOLS.some((t) => p.type === `tool-${t}`) && (p as ToolPart).state === "input-available"),
  );

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end", behavior: "smooth" });
  }, [messages, status]);

  // Im Panel gleich lostippen können, sobald es aufgeht
  useEffect(() => {
    if (panel && panelOpen) textRef.current?.focus({ preventScroll: true });
  }, [panel, panelOpen]);

  async function attach(list: FileList | null) {
    if (!list?.length) return;
    try {
      const shrunk = await Promise.all([...list].slice(0, 3).map((f) => shrinkImage(f)));
      setFiles((cur) => [...cur, ...shrunk.map((s) => ({ type: "file" as const, mediaType: s.mediaType, url: s.dataUrl }))].slice(0, 3));
    } catch {
      toast({ text: "Das Foto konnte nicht gelesen werden.", tone: "error" });
    }
    if (fileRef.current) fileRef.current.value = "";
  }

  function send(text: string) {
    const t = text.trim();
    if ((!t && !files.length) || busy || pendingConfirm) return;
    if (error) clearError();
    void sendMessage({ text: t || "Was siehst du auf dem Foto?", files: files.length ? files : undefined });
    setInput("");
    setFiles([]);
    if (textRef.current) textRef.current.style.height = "";
  }

  const err = errorText(error);
  const notReady = ai && !ai.enabled;

  const thread = (
    <>
      {notReady && <Empty title="KI noch nicht eingerichtet" text={ai.reason ?? undefined} />}

      {!notReady && messages.length === 0 && (
        <div className={panel ? "mt-2" : "mt-6"}>
          <div className="flex items-center gap-3">
            <span className="ai-orb flex h-11 w-11 shrink-0 items-center justify-center rounded-full"><IconSparkles size={22} /></span>
            <p className="t-sub" style={{ color: "var(--label-2)" }}>Ich kenne eure Rezepte, die Woche und das Regal. Änderungen schlage ich vor – du bestätigst.</p>
          </div>
          <div className="mt-5 flex flex-col items-start gap-2">
            {SUGGESTIONS.map((s) => (
              <button key={s} className="chip pressable text-left" onClick={() => send(s)}>{s}</button>
            ))}
            <button className="chip pressable" onClick={() => fileRef.current?.click()}><IconCamera size={15} /> Rezept aus Foto</button>
          </div>
        </div>
      )}

      <div className="mt-4 flex flex-col gap-3" aria-live="polite">
        {messages.map((m) => (
          <Message key={m.id} message={m} respond={(id, tool, output) => addToolOutput({ tool, toolCallId: id, output })} />
        ))}
        {status === "submitted" && (
          <div className="t-sub flex items-center gap-2 px-1" style={{ color: "var(--label-2)" }}>
            <span className="typing" aria-hidden><i /><i /><i /></span> denkt nach …
          </div>
        )}
        {err && (
          <div className="card t-sub px-4 py-3" role="alert" style={{ background: "var(--red-soft)" }}>
            {err}
            <button className="btn-plain t-sub ml-1 font-semibold" onClick={() => { clearError(); void chat.regenerate(); }}>Nochmal</button>
          </div>
        )}
        <div ref={bottom} />
      </div>
    </>
  );

  const composer = !notReady && (
    <form
      className={panel ? "px-3 pt-2 pb-3" : "page py-2 max-lg:px-3 lg:[&>*]:max-w-3xl"}
      onSubmit={(e) => {
        e.preventDefault();
        send(input);
      }}
    >
      {files.length > 0 && (
        <div className="mb-2 flex gap-2">
          {files.map((f, i) => (
            <span key={i} className="relative">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={f.url} alt="" className="h-14 w-14 rounded-lg object-cover" />
              <button type="button" aria-label="Foto entfernen" className="absolute -top-1.5 -right-1.5 flex h-5 w-5 items-center justify-center rounded-full" style={{ background: "var(--label)", color: "var(--bg)" }} onClick={() => setFiles((c) => c.filter((_, j) => j !== i))}>
                <IconClose size={12} />
              </button>
            </span>
          ))}
        </div>
      )}
      <div className="ai-composer flex items-end gap-2">
        <button type="button" className="pressable flex h-9 w-9 shrink-0 items-center justify-center rounded-full" style={{ color: "var(--ai)" }} aria-label="Foto anhängen" title="Foto anhängen" onClick={() => fileRef.current?.click()}>
          <IconCamera size={22} />
        </button>
        <input ref={fileRef} type="file" accept="image/*" multiple className="hidden" onChange={(e) => attach(e.target.files)} aria-label="Foto für die KI" />
        <textarea
          ref={textRef}
          className="input max-h-32 flex-1 resize-none !rounded-[18px] !py-1.5"
          style={{ minHeight: 36, height: input ? undefined : 36 }}
          rows={1}
          placeholder={pendingConfirm ? "Erst Vorschlag bestätigen" : "Frag etwas …"}
          value={input}
          disabled={pendingConfirm}
          onChange={(e) => {
            setInput(e.target.value);
            e.target.style.height = "auto";
            e.target.style.height = `${e.target.scrollHeight}px`;
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault();
              send(input);
            }
          }}
          aria-label="Nachricht an die KI"
        />
        {busy ? (
          <button type="button" className="pressable flex h-9 w-9 shrink-0 items-center justify-center rounded-full" style={{ background: "var(--fill-strong)" }} aria-label="Stoppen" onClick={() => void stop()}>
            <span className="h-3 w-3 rounded-[3px]" style={{ background: "var(--label)" }} />
          </button>
        ) : (
          <button type="submit" className="pressable flex h-9 w-9 shrink-0 items-center justify-center rounded-full disabled:opacity-40" style={{ background: "var(--ai)", color: "var(--on-ai)" }} aria-label="Senden" disabled={(!input.trim() && !files.length) || pendingConfirm}>
            <IconArrowUp size={20} strokeWidth={2.4} />
          </button>
        )}
      </div>
    </form>
  );

  if (panel)
    return (
      <>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pb-4">{thread}</div>
        <div className="shrink-0">{composer}</div>
      </>
    );

  return (
    <>
      <div className="page pb-24"><div className="measure">{thread}</div></div>
      {composer && (
        <div className="composer-dock fixed z-30">
          {composer}
        </div>
      )}
    </>
  );
}

function Message({ message, respond }: { message: UIMessage; respond: (toolCallId: string, tool: string, output: unknown) => void }) {
  if (message.role === "user") {
    const text = message.parts.filter((p) => p.type === "text").map((p) => p.text).join("\n");
    const images = message.parts.filter((p): p is FileUIPart => p.type === "file");
    return (
      <div className="flex flex-col items-end gap-1">
        {images.length > 0 && (
          <div className="flex gap-1.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {images.map((f, i) => <img key={i} src={f.url} alt="Angehängtes Foto" className="h-24 w-24 rounded-2xl object-cover" />)}
          </div>
        )}
        {text && (
          <p className="t-sub max-w-[85%] rounded-[20px] px-3.5 py-2 whitespace-pre-wrap" style={{ background: "var(--ai)", color: "var(--on-ai)" }}>{text}</p>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      {message.parts.map((p, i) => {
        if (p.type === "text") return p.text.trim() ? <div key={i} className="t-sub max-w-[92%]"><RichText text={p.text} /></div> : null;
        if (!p.type.startsWith("tool-")) return null;
        const part = p as unknown as ToolPart;
        const name = p.type.slice(5);
        if ((WRITE_TOOLS as readonly string[]).includes(name)) {
          return <ConfirmCard key={part.toolCallId} tool={name as WriteTool} part={part} respond={(r) => respond(part.toolCallId, name, r)} />;
        }
        const label = READ_LABEL[name];
        if (!label) return null;
        const done = part.state === "output-available" || part.state === "output-error";
        return (
          <p key={part.toolCallId} className="t-caption flex items-center gap-1.5 px-1" style={{ color: "var(--label-2)" }}>
            <IconSparkles size={12} /> {done ? label[1] : label[0]}
          </p>
        );
      })}
    </div>
  );
}
