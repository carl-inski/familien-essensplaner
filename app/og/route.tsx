import { ImageResponse } from "next/og";
import type { NextRequest } from "next/server";

// Platzhalterbild für schema.org "image" (Bring! empfiehlt ein Bild)
export function GET(request: NextRequest) {
  const title = (request.nextUrl.searchParams.get("t") ?? "Familien-Essensplaner").slice(0, 80);
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", justifyContent: "flex-end", padding: 72, background: "linear-gradient(140deg, #f97316, #c2410c)", color: "white" }}>
        <div style={{ fontSize: 30, opacity: 0.85 }}>Familien-Essensplaner</div>
        <div style={{ fontSize: 72, fontWeight: 700, letterSpacing: -2, lineHeight: 1.05, marginTop: 12 }}>{title}</div>
      </div>
    ),
    { width: 1200, height: 630, headers: { "Cache-Control": "public, max-age=86400, immutable" } },
  );
}
