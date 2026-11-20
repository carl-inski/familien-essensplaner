import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { supabaseEnv } from "./lib/supabase/env";

// Frischt die Supabase-Session auf und schickt nicht eingeloggte Besucher zum Login.
// Öffentlich bleiben nur Login, Auth-Callback und die Bring!-Seiten (/r/…, /einkauf/…).
const PUBLIC_PREFIXES = ["/login", "/auth", "/r/", "/einkauf/", "/og", "/bildnachweise", "/impressum", "/datenschutz"];

export async function proxy(request: NextRequest) {
  const path = request.nextUrl.pathname;
  // Diese Route Handler prüfen das native Supabase-Token mit auth.getUser.
  if ((path === "/api/ai/recipe-from-url" || path === "/api/ai/recipe-from-photo" || path === "/api/ai/recipe-assist" ||
       path === "/api/ai/chat" || path === "/api/ai/status" || path === "/api/ai/test" || path === "/api/isbn" ||
       path === "/api/recipe-source") &&
       request.headers.has("authorization")) return NextResponse.next({ request });
  // Erreichbarkeitsprüfung für Uptime-Monitor, ohne Login
  if (path === "/api/health") return NextResponse.next({ request });
  // Statische Nachweiseite: kein Login und kein Supabase-Aufruf nötig.
  if (path === "/bildnachweise" || path === "/impressum" || path === "/datenschutz") return NextResponse.next({ request });
  // Rezept-Schnittstelle für Assistenten: prüft ihren Bearer-Token selbst, keine Session
  if (path === "/api/rezepte" || path === "/api/rezepte/export") return NextResponse.next({ request });
  let response = NextResponse.next({ request });
  const { url, key } = supabaseEnv();
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (toSet, headers) => {
        toSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        toSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        Object.entries(headers ?? {}).forEach(([k, v]) => response.headers.set(k, v));
      },
    },
  });

  const { data } = await supabase.auth.getClaims();
  // Die Startseite ist öffentlich; angemeldet leitet sie selbst in die Woche weiter
  const isPublic = path === "/" || PUBLIC_PREFIXES.some((p) => path.startsWith(p));

  if (!data?.claims && !isPublic) {
    if (path.startsWith("/api/ai/")) return NextResponse.json({ error: "Bitte melde dich an.", code: "unauthorized" }, { status: 401 });
    const login = request.nextUrl.clone();
    login.pathname = "/login";
    login.search = path === "/" ? "" : `?next=${encodeURIComponent(path + request.nextUrl.search)}`;
    return NextResponse.redirect(login);
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|icon|apple-icon|manifest.webmanifest|.*\\.(?:svg|png|jpg|jpeg|webp)$).*)"],
};
