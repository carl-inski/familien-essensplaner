"use client";

import { useChat } from "@ai-sdk/react";
import type { FileUIPart, UIMessage } from "ai";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useRef, useState } from "react";
import { AccountButton } from "@/components/account-button";
import { useAiStatus } from "@/components/ai-status";
import { useAssistant } from "@/components/assistant/assistant-provider";
import { ConfirmCard, type ToolPart } from "@/components/assistant/confirm-card";
import { RichText } from "@/components/assistant/rich-text";
import { useApp } from "@/components/app-data";
import { IconArrowUp, IconCamera, IconClose, IconEdit, IconSparkles } from "@/components/icons";
import { IconButton, PageHeader } from "@/components/nav";
import { useToast } from "@/components/toast";
import { Empty } from "@/components/ui";
import { WRITE_TOOLS, type WriteTool } from "@/lib/ai/assistant-schemas";
import { shrinkImage } from "@/lib/image";

const SUGGESTIONS = [
  "Was steht diese Woche an?",
  "Plan mir für morgen Abend etwas Schnelles",
  "Was haben wir lange nicht gegessen?",
  "Was koche ich mit Zucchini und Feta?",
];

const READ_LABEL: Record<string, [string, string]> = {
  rezepte_suchen: ["Sucht in den Rezepten …", "Rezepte durchsucht"],
  rezept_lesen: ["Liest das Rezept …", "Rezept gelesen"],
  woche_lesen: ["Schaut in die Woche …", "Woche angesehen"],
  lange_nicht_gegessen: ["Sucht lange nicht Gegessenes …", "Kochhistorie angesehen"],
  regal: ["Schaut ins Regal …", "Regal angesehen"],
  einkaufsliste: ["Stellt die Einkaufsliste zusammen …", "Einkaufsliste angesehen"],
};

export default function AssistantPage() {
  return (
    <Suspense>
      <Assistant />
    </Suspense>
  );
}

function errorText(e: Error | undefined): string | null {
  if (!e) return null;
  try {
    return (JSON.parse(e.message) as { error?: string }).error ?? e.message;
  } catch {
    return e.message || "Die KI hat gerade nicht geantwortet.";
  }
}

function Assistant() {
  const { chat, kontext, setKontext, reset } = useAssistant();
  const { messages, sendMessage, addToolOutput, status, error, stop, clearError } = useChat({ chat });
  const { recipesById } = useApp();
  const { status: ai } = useAiStatus();
  const params = useSearchParams();
  const router = useRouter();
  const toast = useToast();
  const [input, setInput] = useState("");
  const [files, setFiles] = useState<FileUIPart[]>([]);
  const fileRef = useRef<HTMLInputElement>(null);
  const bottom = useRef<HTMLDivElement>(null);
  const handled = useRef<string | null>(null);

  const busy = status === "submitted" || status === "streaming";
  const pendingConfirm = messages.some((m) =>
    m.parts.some((p) => WRITE_TOOLS.some((t) => p.type === `tool-${t}`) && (p as ToolPart).state === "input-available"),
  );

  // Einstieg mit Kontext: /assistent?rezept=<id>&frage=…
  useEffect(() => {
    const key = params.toString();
    if (!key || handled.current === key) return;
    handled.current = key;
    const rid = params.get("rezept");
    const recipe = rid ? recipesById.get(rid) : undefined;
    if (recipe) setKontext({ rezept_id: recipe.id, rezept_titel: recipe.title });
    const frage = params.get("frage");
    if (frage && ai?.enabled !== false) void sendMessage({ text: frage });
    router.replace("/assistent");
  }, [params, recipesById, setKontext, sendMessage, router, ai?.enabled]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end", behavior: "smooth" });
  }, [messages, status]);

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
  }

  const err = errorText(error);
  const notReady = ai && !ai.enabled;

  return (
    <>
      <PageHeader
        title="KI"
        subtitle={kontext.rezept_titel ? <>Zum Rezept <strong>{kontext.rezept_titel}</strong></> : "Fragt eure Rezepte, plant mit, schreibt Notizen"}
        trailing={
          <>
            {messages.length > 0 && (
              <IconButton label="Neues Gespräch" onClick={reset}><IconEdit /></IconButton>
            )}
            <AccountButton />
          </>
        }
      />

      <div className="mx-auto max-w-2xl px-4 pb-24">
        {notReady && <Empty title="KI noch nicht eingerichtet" text={ai.reason ?? undefined} />}

        {!notReady && messages.length === 0 && (
          <div className="mt-6">
            <div className="flex items-center gap-3">
              <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full" style={{ background: "var(--accent-soft)", color: "var(--accent)" }}><IconSparkles size={24} /></span>
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
      </div>

      {!notReady && (
        <div className="material fixed inset-x-0 z-30" style={{ bottom: "calc(56px + env(safe-area-inset-bottom))", boxShadow: "0 -0.5px 0 var(--material-edge)" }}>
          <form
            className="mx-auto max-w-2xl px-3 py-2"
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
            <div className="flex items-end gap-2">
              <button type="button" className="pressable flex h-9 w-9 shrink-0 items-center justify-center rounded-full" style={{ color: "var(--accent)" }} aria-label="Foto anhängen" onClick={() => fileRef.current?.click()}>
                <IconCamera size={22} />
              </button>
              <input ref={fileRef} type="file" accept="image/*" multiple className="hidden" onChange={(e) => attach(e.target.files)} aria-label="Foto für die KI" />
              <textarea
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
                <button type="submit" className="pressable flex h-9 w-9 shrink-0 items-center justify-center rounded-full disabled:opacity-40" style={{ background: "var(--accent)", color: "var(--on-accent)" }} aria-label="Senden" disabled={(!input.trim() && !files.length) || pendingConfirm}>
                  <IconArrowUp size={20} strokeWidth={2.4} />
                </button>
              )}
            </div>
          </form>
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
          <p className="t-sub max-w-[85%] rounded-[20px] px-3.5 py-2 whitespace-pre-wrap" style={{ background: "var(--accent)", color: "var(--on-accent)" }}>{text}</p>
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
          <p key={part.toolCallId} className="t-caption flex items-center gap-1.5 px-1" style={{ color: "var(--label-3)" }}>
            <IconSparkles size={12} /> {done ? label[1] : label[0]}
          </p>
        );
      })}
    </div>
  );
}
