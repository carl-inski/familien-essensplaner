import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { supabaseEnv } from "./lib/supabase/env";

// Frischt die Supabase-Session auf und schickt nicht eingeloggte Besucher zum Login.
// Öffentlich bleiben nur Login, Auth-Callback und die Bring!-Seiten (/r/…, /einkauf/…).
const PUBLIC_PREFIXES = ["/login", "/auth", "/r/", "/einkauf/", "/og", "/bildnachweise"];

export async function proxy(request: NextRequest) {
  const path = request.nextUrl.pathname;
  // Statische Nachweiseite: kein Login und kein Supabase-Aufruf nötig.
  if (path === "/bildnachweise") return NextResponse.next({ request });
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
  const isPublic = PUBLIC_PREFIXES.some((p) => path.startsWith(p));

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
