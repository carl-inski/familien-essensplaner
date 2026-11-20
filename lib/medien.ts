// Beispielbilder und geprüfte Kochbuch-Angaben.
// ISBN nur, wenn eine Quelle das Buch eindeutig zuordnet. Sonst null und ein Hinweis.
// Cover mehrdeutiger Bücher zeigen die jüngste deutsche Ausgabe, ohne die ISBN zu setzen.
// Die SQL-Datei supabase/manual/20261024_bilder_und_kochbuecher.sql spiegelt dieselben Werte
// für eine bereits befüllte Datenbank und wird nicht automatisch ausgeführt.

import type { Cookbook } from "./types";
import dishPhotos from "./dish-photos.json";
import cookbookCatalog from "./cookbook-catalog.json";

export interface DishPhoto {
  title: string;
  /** Pfad unter public/ */
  src: string | null;
  author: string | null;
  /** Kurzer Hinweis zur Nutzung, keine Lizenz-Abkürzung */
  license: string | null;
  licenseUrl: string | null;
  sourceUrl: string | null;
  /** Wenn das Foto das Rezept nur annähert */
  hinweis: string | null;
}

export interface CatalogBook {
  title: string;
  isbn: string | null;
  authors: string[];
  publisher: string | null;
  year: number | null;
  coverUrl: string | null;
  /** Kurze Quellenangabe, wenn eine ISBN gesetzt ist */
  quelle: string | null;
  /** Sichtbarer Hinweis, wenn die Ausgabe nicht eindeutig ist */
  hinweis: string | null;
  /** Wo das lokale Cover herkommt */
  coverQuelle: string | null;
}

const PLACEHOLDER_NOTE = "Autor/Verlag per ISBN ergänzen";

export const DISH_PHOTOS: DishPhoto[] = dishPhotos;

export const CATALOG_BOOKS: CatalogBook[] = cookbookCatalog;

function norm(title: string): string {
  return title.trim().toLocaleLowerCase("de").replace(/\s+&\s+/g, " und ").replace(/\s+/g, " ");
}

const dishesByTitle = new Map(DISH_PHOTOS.map((d) => [norm(d.title), d]));
const dishesByPath = new Map(DISH_PHOTOS.flatMap((d) => d.src ? [[d.src, d] as const] : []));
const booksByTitle = new Map(CATALOG_BOOKS.map((b) => [norm(b.title), b]));

export function dishPhoto(title: string): DishPhoto | null {
  const found = dishesByTitle.get(norm(title));
  return found?.src ? found : null;
}

/** Bildnachweis, wenn das angezeigte Foto das Beispielbild ist (kein eigenes Upload) */
export function dishCredit(title: string, imageUrl: string | null | undefined): DishPhoto | null {
  return imageUrl ? dishesByPath.get(imageUrl) ?? null : dishPhoto(title);
}

export function catalogBook(title: string): CatalogBook | undefined {
  return booksByTitle.get(norm(title));
}

function authorsLookPlaceholder(authors: string[], catalog: CatalogBook): boolean {
  if (authors.length === 0) return true;
  return catalog.title === "Leon Fast Food Vegetarisch" && authors.length === 1 && authors[0] === "Leon";
}

/** Füllt leere Felder aus dem Katalog. Gespeicherte Werte bleiben. */
export function presentCookbook<T extends Cookbook>(book: T): T {
  const catalog = catalogBook(book.title);
  if (!catalog) return book;
  const noteIsPlaceholder = !book.notes || book.notes === PLACEHOLDER_NOTE;
  return {
    ...book,
    isbn: book.isbn?.trim() || catalog.isbn,
    authors: authorsLookPlaceholder(book.authors, catalog) ? catalog.authors : book.authors,
    publisher: book.publisher?.trim() && book.publisher !== "GU" ? book.publisher : catalog.publisher ?? book.publisher,
    year: book.year ?? catalog.year,
    cover_url: book.cover_url?.trim() || catalog.coverUrl,
    notes: noteIsPlaceholder ? catalog.hinweis : book.notes,
  };
}

export function bookQuelle(book: Pick<Cookbook, "title" | "isbn">): string | null {
  const catalog = catalogBook(book.title);
  if (!catalog?.isbn || !catalog.quelle) return null;
  const shown = (book.isbn ?? "").replace(/[^0-9Xx]/g, "");
  const known = catalog.isbn.replace(/[^0-9Xx]/g, "");
  return shown === known ? catalog.quelle : null;
}
