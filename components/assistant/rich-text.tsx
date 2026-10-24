// Kleiner Markdown-Renderer für Antworten des Assistenten: Absätze, Listen,
// **fett** und interne Links wie [Shakshuka](/rezepte/<id>). Kein HTML.

import Link from "next/link";
import type { ReactNode } from "react";

function inline(text: string, key: string): ReactNode[] {
  const out: ReactNode[] = [];
  const re = /\*\*(.+?)\*\*|\[([^\]]+)\]\((\/[^)\s]*)\)/g;
  let last = 0;
  let i = 0;
  for (const m of text.matchAll(re)) {
    if (m.index > last) out.push(text.slice(last, m.index));
    if (m[1]) out.push(<strong key={`${key}-${i++}`}>{m[1]}</strong>);
    else if (/^\/(rezepte|woche|regal|einkaufsliste)(\/|$|\?)/.test(m[3])) {
      out.push(<Link key={`${key}-${i++}`} href={m[3]} className="font-medium underline decoration-1 underline-offset-2" style={{ color: "var(--accent)" }}>{m[2]}</Link>);
    } else out.push(m[2]);
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

export function RichText({ text }: { text: string }) {
  const blocks: ReactNode[] = [];
  const lines = text.replace(/\r/g, "").split("\n");
  let list: { ordered: boolean; items: string[] } | null = null;
  const flush = () => {
    if (!list) return;
    const k = `l${blocks.length}`;
    const items = list.items.map((it, j) => <li key={j}>{inline(it, `${k}-${j}`)}</li>);
    blocks.push(list.ordered ? <ol key={k} className="list-decimal space-y-0.5 pl-5">{items}</ol> : <ul key={k} className="list-disc space-y-0.5 pl-5">{items}</ul>);
    list = null;
  };
  for (const raw of lines) {
    const line = raw.trim();
    const bullet = line.match(/^[-*•]\s+(.*)$/);
    const num = line.match(/^\d+[.)]\s+(.*)$/);
    if (bullet || num) {
      const ordered = !!num;
      if (list && list.ordered !== ordered) flush();
      list ??= { ordered, items: [] };
      list.items.push((bullet ?? num)![1]);
      continue;
    }
    flush();
    if (!line) continue;
    const k = `p${blocks.length}`;
    blocks.push(<p key={k}>{inline(line.replace(/^#+\s*/, ""), k)}</p>);
  }
  flush();
  return <div className="flex flex-col gap-2">{blocks}</div>;
}
