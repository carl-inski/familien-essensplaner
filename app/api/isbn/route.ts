import { NextResponse, type NextRequest } from "next/server";

// ISBN-Abfrage: Open Library, Fallback Google Books (Briefing 4.6)

interface BookInfo {
  isbn: string;
  title: string | null;
  authors: string[];
  publisher: string | null;
  year: number | null;
  cover_url: string | null;
  source: "openlibrary" | "google";
}

const yearOf = (s: unknown) => {
  const m = typeof s === "string" ? s.match(/\d{4}/) : null;
  return m ? Number(m[0]) : null;
};

async function getJson(url: string) {
  const res = await fetch(url, { headers: { Accept: "application/json" }, next: { revalidate: 86400 } });
  return res.ok ? res.json() : null;
}

async function openLibrary(isbn: string): Promise<BookInfo | null> {
  const book = await getJson(`https://openlibrary.org/isbn/${isbn}.json`);
  if (!book?.title) return null;
  const authors: string[] = [];
  for (const a of (book.authors ?? []).slice(0, 4)) {
    const author = await getJson(`https://openlibrary.org${a.key}.json`);
    if (author?.name) authors.push(author.name);
  }
  return {
    isbn,
    title: book.title,
    authors,
    publisher: book.publishers?.[0] ?? null,
    year: yearOf(book.publish_date),
    cover_url: book.covers?.length ? `https://covers.openlibrary.org/b/id/${book.covers[0]}-L.jpg` : null,
    source: "openlibrary",
  };
}

async function google(isbn: string): Promise<BookInfo | null> {
  const data = await getJson(`https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}`);
  const v = data?.items?.[0]?.volumeInfo;
  if (!v?.title) return null;
  const thumb: string | undefined = v.imageLinks?.thumbnail ?? v.imageLinks?.smallThumbnail;
  return {
    isbn,
    title: v.subtitle ? `${v.title}` : v.title,
    authors: v.authors ?? [],
    publisher: v.publisher ?? null,
    year: yearOf(v.publishedDate),
    cover_url: thumb ? thumb.replace(/^http:/, "https:") : null,
    source: "google",
  };
}

export async function GET(request: NextRequest) {
  const isbn = (request.nextUrl.searchParams.get("isbn") ?? "").replace(/[^0-9Xx]/g, "").toUpperCase();
  if (!/^(\d{9}[\dX]|\d{13})$/.test(isbn)) {
    return NextResponse.json({ error: "Bitte eine gültige ISBN-10 oder ISBN-13 eingeben." }, { status: 400 });
  }
  try {
    const ol = await openLibrary(isbn);
    const g = !ol || !ol.authors.length || !ol.cover_url ? await google(isbn) : null;
    if (!ol && !g) return NextResponse.json({ error: "Zu dieser ISBN wurde nichts gefunden." }, { status: 404 });
    const merged: BookInfo = {
      isbn,
      title: ol?.title ?? g?.title ?? null,
      authors: ol?.authors.length ? ol.authors : g?.authors ?? [],
      publisher: ol?.publisher ?? g?.publisher ?? null,
      year: ol?.year ?? g?.year ?? null,
      cover_url: ol?.cover_url ?? g?.cover_url ?? null,
      source: ol ? "openlibrary" : "google",
    };
    return NextResponse.json(merged);
  } catch {
    return NextResponse.json({ error: "Buchdienste gerade nicht erreichbar." }, { status: 502 });
  }
}
