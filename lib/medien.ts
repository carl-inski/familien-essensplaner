// Beispielbilder und geprüfte Kochbuch-Angaben.
// ISBN nur, wenn eine Quelle das Buch eindeutig zuordnet. Sonst null und ein Hinweis.
// Die SQL-Datei supabase/manual/20261024_bilder_und_kochbuecher.sql spiegelt dieselben Werte
// für eine bereits befüllte Datenbank und wird nicht automatisch ausgeführt.

import type { Cookbook } from "./types";

export interface DishPhoto {
  title: string;
  /** Pfad unter public/, oder null wenn kein passendes Foto gefunden wurde */
  src: string | null;
  author: string | null;
  license: string | null;
  licenseUrl: string | null;
  sourceUrl: string | null;
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
}

const PLACEHOLDER_NOTE = "Autor/Verlag per ISBN ergänzen";

export const DISH_PHOTOS: DishPhoto[] = [
  {
    title: "Spinatquiche mit Feta",
    src: "/images/rezepte/spinatquiche.jpg",
    author: "Andy Li",
    license: "CC0",
    licenseUrl: "https://creativecommons.org/publicdomain/zero/1.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Spinach_Quiche_-_Julien_Plumart_2025-10-14.jpg",
  },
  {
    title: "Pasta Räucherlachs",
    src: "/images/rezepte/pasta-raeucherlachs.jpg",
    author: "CK Golf",
    license: "CC BY-SA 2.0",
    licenseUrl: "https://creativecommons.org/licenses/by-sa/2.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Dinner_at_21_Steps_-_Smoked_Salmon_Penne_(6351631126).jpg",
  },
  {
    title: "Teriyaki Hähnchen",
    src: "/images/rezepte/teriyaki-haehnchen.jpg",
    author: "Blue Lotus",
    license: "CC BY 2.0",
    licenseUrl: "https://creativecommons.org/licenses/by/2.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Chicken_teriyaki.jpg",
  },
  { title: "Shakshuka mit Kichererbsen & Kokosmilch", src: null, author: null, license: null, licenseUrl: null, sourceUrl: null },
  {
    title: "Pizza (Rucola & Schinken)",
    src: "/images/rezepte/pizza-rucola-schinken.jpg",
    author: "Arnold Gatilao",
    license: "CC BY 2.0",
    licenseUrl: "https://creativecommons.org/licenses/by/2.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Prosciutto_Rucola_-_tomato,_mozzarella,_arugula,_prosciutto_di_Parma,_pecorino_(16103892980).jpg",
  },
  {
    title: "Sommernudeln (Caprese-Style)",
    src: "/images/rezepte/sommernudeln.jpg",
    author: "최광모",
    license: "CC BY-SA 4.0",
    licenseUrl: "https://creativecommons.org/licenses/by-sa/4.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:%EC%A3%BC%EC%8B%9D%ED%9A%8C%EC%82%AC_%EC%97%94%EC%95%84%EC%9D%B4%EC%97%90%ED%94%84%EC%95%A4%EC%94%A8_%EB%8B%90%EB%A6%AC_%ED%8C%8C%EC%8A%A4%ED%83%80_%EC%9D%8C%EC%8B%9D_%EC%82%AC%EC%A7%841-Caprese.jpg",
  },
  {
    title: "Cajun Chicken Pasta",
    src: "/images/rezepte/cajun-chicken-pasta.jpg",
    author: "Ginny",
    license: "CC BY-SA 2.0",
    licenseUrl: "https://creativecommons.org/licenses/by-sa/2.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Tomato_cream_sauce_on_pasta_and_chicken.jpg",
  },
  {
    title: "Buffalo Chicken Wraps mit Ranch-Sauce",
    src: "/images/rezepte/buffalo-chicken-wraps.jpg",
    author: "Daderot",
    license: "CC0",
    licenseUrl: "https://creativecommons.org/publicdomain/zero/1.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Buffalo_chicken_wrap_-_Dunedin,_New_Zealand.jpg",
  },
  { title: "Kartoffelknödel mit Schweinegeschnetzeltem", src: null, author: null, license: null, licenseUrl: null, sourceUrl: null },
  {
    title: "One-Pot Räucherlachs-Pasta (Jamie Oliver)",
    src: "/images/rezepte/one-pot-raeucherlachs.jpg",
    author: "FotoosVanRobin",
    license: "CC BY-SA 2.0",
    licenseUrl: "https://creativecommons.org/licenses/by-sa/2.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Tagliatelle_with_Smoked_Salmon.jpg",
  },
  { title: "Ananascurry (nach Leon: Fast Vegetarian)", src: null, author: null, license: null, licenseUrl: null, sourceUrl: null },
  {
    title: "Asiatische Reisbandnudel-Suppe",
    src: "/images/rezepte/reisbandnudel-suppe.jpg",
    author: "FASTILY",
    license: "CC BY-SA 4.0",
    licenseUrl: "https://creativecommons.org/licenses/by-sa/4.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Vegetable_Ph%E1%BB%9F_1_2022-07-16.jpeg",
  },
  {
    title: "Sommerrollen (Vietnamesisch)",
    src: "/images/rezepte/sommerrollen.jpg",
    author: "Zoe Shuttleworth",
    license: "CC BY 2.0",
    licenseUrl: "https://creativecommons.org/licenses/by/2.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Vietnamese_summer_rolls_%26_peanut_sauce.jpg",
  },
  {
    title: "Wraps Louisa",
    src: "/images/rezepte/wraps-louisa.jpg",
    author: "Luca Nebuloni",
    license: "CC BY 2.0",
    licenseUrl: "https://creativecommons.org/licenses/by/2.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Chicken_roll_with_vegetables_%26_goat_cheese_(5742199145).jpg",
  },
  {
    title: "Tomaten-Gnocchi",
    src: "/images/rezepte/tomaten-gnocchi.jpg",
    author: "Ivan Vighetto",
    license: "CC BY-SA 3.0",
    licenseUrl: "https://creativecommons.org/licenses/by-sa/3.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Gnocchi_al_pomodoro.JPG",
  },
  { title: "Brathähnchen mit Miso", src: null, author: null, license: null, licenseUrl: null, sourceUrl: null },
  {
    title: "Chili con Carne",
    src: "/images/rezepte/chili-con-carne.jpg",
    author: "cyclonebill",
    license: "CC BY-SA 2.0",
    licenseUrl: "https://creativecommons.org/licenses/by-sa/2.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Chili_con_carne_(8085378954).jpg",
  },
  { title: "Fitness-Reisriegel (PB&J & Banane-Schoko)", src: null, author: null, license: null, licenseUrl: null, sourceUrl: null },
  {
    title: "Honighähnchen",
    src: "/images/rezepte/honighaehnchen.jpg",
    author: "Ewan Munro",
    license: "CC BY-SA 2.0",
    licenseUrl: "https://creativecommons.org/licenses/by-sa/2.0/",
    sourceUrl: "https://commons.wikimedia.org/wiki/File:Red_Lion_and_Sun,_Highgate,_London_(5560981816).jpg",
  },
];

const DNB = "Deutsche Nationalbibliografie";

export const CATALOG_BOOKS: CatalogBook[] = [
  {
    title: "Die echte italienische Küche",
    isbn: null,
    authors: ["Franco Benussi", "Reinhardt Hess", "Sabine Sälzer"],
    publisher: "Gräfe und Unzer",
    year: null,
    coverUrl: null,
    quelle: null,
    hinweis: "Mehrere Ausgaben (unter anderem 2012 und 2025). ISBN deshalb leer gelassen.",
  },
  {
    title: "Jerusalem",
    isbn: "978-3-8310-2333-2",
    authors: ["Yotam Ottolenghi", "Sami Tamimi"],
    publisher: "Dorling Kindersley",
    year: 2013,
    coverUrl: "https://covers.openlibrary.org/b/isbn/9783831023332-L.jpg",
    quelle: DNB,
    hinweis: null,
  },
  {
    title: "Schlau kochen",
    isbn: "978-3-86528-608-6",
    authors: ["Sigrid Krekel", "Angela Francisca Endress"],
    publisher: "Umschau",
    year: 2009,
    coverUrl: null,
    quelle: DNB,
    hinweis: null,
  },
  {
    title: "Das neue bayrische Kochbuch",
    isbn: null,
    authors: ["Alfons Schuhbeck"],
    publisher: "Zabert Sandmann",
    year: null,
    coverUrl: null,
    quelle: null,
    hinweis: "Mehrere Auflagen (unter anderem 1989, 1995, 2001). ISBN deshalb leer gelassen.",
  },
  {
    title: "Leon Fast Food Vegetarisch",
    isbn: "978-3-8321-9476-5",
    authors: ["Jane Baxter", "Henry Dimbleby"],
    publisher: "DuMont",
    year: 2014,
    coverUrl: null,
    quelle: DNB,
    hinweis: null,
  },
  {
    title: "Das große Buch vom Backen und Bauen",
    isbn: null,
    authors: ["Ruth Kreider-Stempfle", "Bettina Frensemeier"],
    publisher: "Gerstenberg",
    year: null,
    coverUrl: null,
    quelle: null,
    hinweis: "Zwei Ausgaben (2013 und 2022). ISBN deshalb leer gelassen.",
  },
  {
    title: "Harry's Bar Kochbuch",
    isbn: "978-3-89910-010-5",
    authors: ["Arrigo Cipriani"],
    publisher: "Collection Rolf Heyne",
    year: null,
    coverUrl: null,
    quelle: "ISBN-Verzeichnis und Buchhandel (Collection Rolf Heyne)",
    hinweis: null,
  },
  {
    title: "Meine Klassiker",
    isbn: "978-3-8338-2126-4",
    authors: ["Alfons Schuhbeck"],
    publisher: "Gräfe und Unzer",
    year: 2010,
    coverUrl: "https://covers.openlibrary.org/b/isbn/9783833821264-L.jpg",
    quelle: DNB,
    hinweis: null,
  },
  {
    title: "Bayrisches Kochbuch",
    isbn: null,
    authors: ["Maria Hofmann", "Helmut Lydtin"],
    publisher: null,
    year: null,
    coverUrl: null,
    quelle: null,
    hinweis: "Das Bayerische Kochbuch hat viele Auflagen mit eigenen ISBN. Deshalb leer gelassen.",
  },
  {
    title: "Licence to Cook",
    isbn: null,
    authors: ["Sam Stern", "Susan Stern"],
    publisher: "Oetinger",
    year: null,
    coverUrl: null,
    quelle: null,
    hinweis: "Zwei Ausgaben (2007 und 2014). ISBN deshalb leer gelassen.",
  },
  {
    title: "Anniks göttliche Desserts",
    isbn: "978-3-8310-1965-6",
    authors: ["Annik Wecker"],
    publisher: "Dorling Kindersley",
    year: 2011,
    coverUrl: null,
    quelle: DNB,
    hinweis: null,
  },
  {
    title: "Ottolenghi Test Kitchen",
    isbn: null,
    authors: ["Yotam Ottolenghi", "Noor Murad"],
    publisher: null,
    year: null,
    coverUrl: null,
    quelle: null,
    hinweis: "Zwei verschiedene Bände (Shelf Love und Extra Good Things). ISBN deshalb leer gelassen.",
  },
  {
    title: "Ottolenghi Simple",
    isbn: null,
    authors: ["Yotam Ottolenghi"],
    publisher: null,
    year: null,
    coverUrl: null,
    quelle: null,
    hinweis: "Englische Ausgabe und deutsche Ausgabe „Simple“ haben verschiedene ISBN. Deshalb leer gelassen.",
  },
  {
    title: "ONE",
    isbn: "978-3-8310-4579-2",
    authors: ["Jamie Oliver"],
    publisher: "Dorling Kindersley",
    year: 2022,
    coverUrl: null,
    quelle: DNB,
    hinweis: null,
  },
  {
    title: "Das neue Grand Tour Kochbuch",
    isbn: "978-3-95726-080-2",
    authors: ["Hannah Grant"],
    publisher: "Covadonga",
    year: 2023,
    coverUrl: null,
    quelle: DNB,
    hinweis: null,
  },
];

function norm(title: string): string {
  return title.trim().toLocaleLowerCase("de").replace(/\s+/g, " ");
}

const dishesByTitle = new Map(DISH_PHOTOS.map((d) => [norm(d.title), d]));
const booksByTitle = new Map(CATALOG_BOOKS.map((b) => [norm(b.title), b]));

export function dishPhoto(title: string): DishPhoto | null {
  const found = dishesByTitle.get(norm(title));
  return found?.src ? found : null;
}

/** Bildnachweis, wenn das angezeigte Foto das Beispielbild ist (kein eigenes Upload) */
export function dishCredit(title: string, imageUrl: string | null | undefined): DishPhoto | null {
  const photo = dishPhoto(title);
  if (!photo) return null;
  if (!imageUrl || imageUrl === photo.src) return photo;
  return null;
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
