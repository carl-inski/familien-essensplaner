// Beispielbilder und geprüfte Kochbuch-Angaben.
// ISBN nur, wenn eine Quelle das Buch eindeutig zuordnet. Sonst null und ein Hinweis.
// Cover mehrdeutiger Bücher zeigen die jüngste deutsche Ausgabe, ohne die ISBN zu setzen.
// Die SQL-Datei supabase/manual/20261024_bilder_und_kochbuecher.sql spiegelt dieselben Werte
// für eine bereits befüllte Datenbank und wird nicht automatisch ausgeführt.

import type { Cookbook } from "./types";

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

const BEISPIEL = "Beispielbild";

export const DISH_PHOTOS: DishPhoto[] = [
  {
    title: "Spinatquiche mit Feta",
    src: "/images/rezepte/spinatquiche.jpg",
    author: "Chatelaine",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.chatelaine.com/",
    hinweis: null,
  },
  {
    title: "Pasta Räucherlachs",
    src: "/images/rezepte/pasta-raeucherlachs.jpg",
    author: "Nourish and Fête",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.nourish-and-fete.com/creamy-smoked-salmon-pasta/",
    hinweis: null,
  },
  {
    title: "Teriyaki Hähnchen",
    src: "/images/rezepte/teriyaki-haehnchen.jpg",
    author: "Wholesome Made Easy",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://wholesomemadeeasy.com/teriyaki-chicken-and-rice-bowls/",
    hinweis: null,
  },
  {
    title: "Shakshuka mit Kichererbsen & Kokosmilch",
    src: "/images/rezepte/shakshuka.jpg",
    author: "Live Eat Learn",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.liveeatlearn.com/chickpea-shakshuka/",
    hinweis: "Kichererbsen-Shakshuka. Die Kokosmilch aus dem Rezept ist auf dem Foto nicht eigens zu sehen.",
  },
  {
    title: "Pizza (Rucola & Schinken)",
    src: "/images/rezepte/pizza-rucola-schinken.jpg",
    author: "With Spice",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.withspice.com/arugula-prosciutto-pizza/",
    hinweis: null,
  },
  {
    title: "Sommernudeln (Caprese-Style)",
    src: "/images/rezepte/sommernudeln.jpg",
    author: "12 Onions",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://12onions.com/tomato-mozzarella-basil-pasta-caprese/",
    hinweis: null,
  },
  {
    title: "Cajun Chicken Pasta",
    src: "/images/rezepte/cajun-chicken-pasta.jpg",
    author: "Cooking Classy",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.cookingclassy.com/one-pot-cajun-chicken-pasta/",
    hinweis: null,
  },
  {
    title: "Buffalo Chicken Wraps mit Ranch-Sauce",
    src: "/images/rezepte/buffalo-chicken-wraps.jpg",
    author: "SideChef",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.sidechef.com/",
    hinweis: null,
  },
  {
    title: "Kartoffelknödel mit Schweinegeschnetzeltem",
    src: "/images/rezepte/kartoffelknoedel.jpg",
    author: "Katha kocht",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "http://katha-kocht.de/",
    hinweis: null,
  },
  {
    title: "One-Pot Räucherlachs-Pasta (Jamie Oliver)",
    src: "/images/rezepte/one-pot-raeucherlachs.jpg",
    author: "Happy Kitchen",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://happykitchen.rocks/smoked-salmon-pasta/",
    hinweis: null,
  },
  {
    title: "Ananascurry (nach Leon: Fast Vegetarian)",
    src: "/images/rezepte/ananascurry.jpg",
    author: "Simmering Starfruit",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://simmeringstarfruit.com/pineapple-coconut-curry/",
    hinweis: "Ananas-Kokoscurry. Kichererbsen sind nicht das Hauptmotiv.",
  },
  {
    title: "Asiatische Reisbandnudel-Suppe",
    src: "/images/rezepte/reisbandnudel-suppe.jpg",
    author: "Cilantro and Citronella",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.cilantroandcitronella.com/vegetarian-thai-soup/",
    hinweis: null,
  },
  {
    title: "Sommerrollen (Vietnamesisch)",
    src: "/images/rezepte/sommerrollen.jpg",
    author: "RecipeTin Eats",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.recipetineats.com/vietnamese-rice-paper-rolls-spring-rolls/",
    hinweis: null,
  },
  {
    title: "Wraps Louisa",
    src: "/images/rezepte/wraps-louisa.jpg",
    author: "Bake to the roots",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://baketotheroots.de/",
    hinweis: "Hähnchen-Wraps mit Avocado, nah an Guacamole und Rucola.",
  },
  {
    title: "Tomaten-Gnocchi",
    src: "/images/rezepte/tomaten-gnocchi.jpg",
    author: "Lil Vienna",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.lilvienna.com/quick-gnocchi-with-tomato-sauce/",
    hinweis: null,
  },
  {
    title: "Brathähnchen mit Miso",
    src: "/images/rezepte/brathaehnchen-miso.jpg",
    author: "Bakersbeans",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.bakersbeans.ca/miso-roasted-chicken-thighs/",
    hinweis: "Miso-Hähnchen. Die Süßkartoffeln aus dem Rezept sind nicht zu sehen.",
  },
  {
    title: "Chili con Carne",
    src: "/images/rezepte/chili-con-carne.jpg",
    author: "BBC Food",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.bbc.co.uk/food/recipes/chilliconcarne_67875",
    hinweis: null,
  },
  {
    title: "Fitness-Reisriegel (PB&J & Banane-Schoko)",
    src: "/images/rezepte/fitness-reisriegel.jpg",
    author: "Crazy for Crust",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://www.crazyforcrust.com/peanut-butter-rice-krispie-treats/",
    hinweis: "Erdnussbutter-Reisriegel als Beispiel. Das Rezept nutzt Milchreis, nicht Puffreis.",
  },
  {
    title: "Honighähnchen",
    src: "/images/rezepte/honighaehnchen.jpg",
    author: "Recipe Runner",
    license: BEISPIEL,
    licenseUrl: null,
    sourceUrl: "https://reciperunner.com/chicken-with-feta-and-tomatoes/",
    hinweis: "Hähnchen mit Feta und Tomaten. Honig, Pistazien und Zwiebeln sind nicht das Hauptmotiv.",
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
    coverUrl: "/images/kochbuecher/die-echte-italienische-kueche.jpg",
    quelle: null,
    hinweis: "Cover: Gräfe und Unzer, Ausgabe 2025. ISBN bleibt leer, bis die Ausgabe bestätigt ist.",
    coverQuelle: "Amazon-Katalogbild zur DNB-Ausgabe 2025 (978-3-8338-9924-9), ISBN nicht gespeichert",
  },
  {
    title: "Jerusalem",
    isbn: "978-3-8310-2333-2",
    authors: ["Yotam Ottolenghi", "Sami Tamimi"],
    publisher: "Dorling Kindersley",
    year: 2013,
    coverUrl: "/images/kochbuecher/jerusalem.jpg",
    quelle: DNB,
    hinweis: null,
    coverQuelle: "Cover zur ISBN 978-3-8310-2333-2, lesehits.de",
  },
  {
    title: "Schlau kochen",
    isbn: "978-3-86528-608-6",
    authors: ["Sigrid Krekel", "Angela Francisca Endress"],
    publisher: "Umschau",
    year: 2009,
    coverUrl: "/images/kochbuecher/schlau-kochen.jpg",
    quelle: DNB,
    hinweis: null,
    coverQuelle: "Amazon-Produktbild zur ISBN 978-3-86528-608-6",
  },
  {
    title: "Das neue bayrische Kochbuch",
    isbn: null,
    authors: ["Alfons Schuhbeck"],
    publisher: "Zabert Sandmann",
    year: null,
    coverUrl: "/images/kochbuecher/das-neue-bayrische-kochbuch.jpg",
    quelle: null,
    hinweis: "Cover: Zabert Sandmann, jüngste Ausgabe 2001. ISBN bleibt leer, bis die Ausgabe bestätigt ist.",
    coverQuelle: "Amazon-Produktbild der Ausgabe Zabert Sandmann; DNB-Jahr 2001, ISBN nicht gespeichert",
  },
  {
    title: "Leon Fast Food Vegetarisch",
    isbn: "978-3-8321-9476-5",
    authors: ["Jane Baxter", "Henry Dimbleby"],
    publisher: "DuMont",
    year: 2014,
    coverUrl: "/images/kochbuecher/leon-fast-food-vegetarisch.jpg",
    quelle: DNB,
    hinweis: null,
    coverQuelle: "Cover des DuMont Verlags zur ISBN 978-3-8321-9476-5",
  },
  {
    title: "Das große Buch vom Backen und Bauen",
    isbn: null,
    authors: ["Ruth Kreider-Stempfle", "Bettina Frensemeier"],
    publisher: "Gerstenberg",
    year: null,
    coverUrl: "/images/kochbuecher/backen-und-bauen.jpg",
    quelle: null,
    hinweis: "Cover: Gerstenberg, Ausgabe 2022. ISBN bleibt leer, bis die Ausgabe bestätigt ist.",
    coverQuelle: "Amazon-Katalogbild zur DNB-Ausgabe 2022 (978-3-8369-6198-1), ISBN nicht gespeichert",
  },
  {
    title: "Harry's Bar Kochbuch",
    isbn: "978-3-89910-010-5",
    authors: ["Arrigo Cipriani"],
    publisher: "Collection Rolf Heyne",
    year: null,
    coverUrl: "/images/kochbuecher/harrys-bar.jpg",
    quelle: "ISBN-Verzeichnis und Buchhandel (Collection Rolf Heyne)",
    hinweis: null,
    coverQuelle: "Amazon-Produktbild zur ISBN 978-3-89910-010-5",
  },
  {
    title: "Meine Klassiker",
    isbn: "978-3-8338-2126-4",
    authors: ["Alfons Schuhbeck"],
    publisher: "Gräfe und Unzer",
    year: 2010,
    coverUrl: "/images/kochbuecher/meine-klassiker.jpg",
    quelle: DNB,
    hinweis: null,
    coverQuelle: "medimops-Cover zur ISBN 978-3-8338-2126-4",
  },
  {
    title: "Bayrisches Kochbuch",
    isbn: null,
    authors: ["Maria Hofmann", "Helmut Lydtin"],
    publisher: null,
    year: null,
    coverUrl: "/images/kochbuecher/bayerisches-kochbuch.jpg",
    quelle: null,
    hinweis: "Cover der langen Standardausgabe (Verlagsseite). DNB nennt 2026 den Verlag Friedrich Pustet. ISBN bleibt leer, bis die Ausgabe bestätigt ist.",
    coverQuelle: "bayerisches-kochbuch.de; DNB-Ausgabe 2026, ISBN nicht gespeichert",
  },
  {
    title: "Licence to Cook",
    isbn: null,
    authors: ["Sam Stern", "Susan Stern"],
    publisher: "Oetinger",
    year: null,
    coverUrl: "/images/kochbuecher/licence-to-cook.jpg",
    quelle: null,
    hinweis: "Cover: Oetinger, Ausgabe 2014. ISBN bleibt leer, bis die Ausgabe bestätigt ist.",
    coverQuelle: "Amazon-Produktbild der deutschen Oetinger-Ausgabe; DNB-Jahr 2014, ISBN nicht gespeichert",
  },
  {
    title: "Anniks göttliche Desserts",
    isbn: "978-3-8310-1965-6",
    authors: ["Annik Wecker"],
    publisher: "Dorling Kindersley",
    year: 2011,
    coverUrl: "/images/kochbuecher/anniks-goettliche-desserts.jpg",
    quelle: DNB,
    hinweis: null,
    coverQuelle: "Amazon-Produktbild zur ISBN 978-3-8310-1965-6",
  },
  {
    title: "Ottolenghi Test Kitchen",
    isbn: null,
    authors: ["Yotam Ottolenghi", "Noor Murad"],
    publisher: "Dorling Kindersley",
    year: null,
    coverUrl: "/images/kochbuecher/ottolenghi-test-kitchen.jpg",
    quelle: null,
    hinweis: "Cover: deutsche Ausgabe „OTK – Extra Good Things“, DK 2022, nicht Shelf Love von 2021. ISBN bleibt leer, bis der Band bestätigt ist.",
    coverQuelle: "Cover zur DNB-Ausgabe 2022 (978-3-8310-4596-9), lesehits.de, ISBN nicht gespeichert",
  },
  {
    title: "Ottolenghi Simple",
    isbn: null,
    authors: ["Yotam Ottolenghi"],
    publisher: "Dorling Kindersley",
    year: null,
    coverUrl: "/images/kochbuecher/ottolenghi-simple.jpg",
    quelle: null,
    hinweis: "Cover: deutsche Ausgabe „Ottolenghi Simple“, DK 2023, nicht „Simple Too“ von 2026. ISBN bleibt leer, bis die Ausgabe bestätigt ist.",
    coverQuelle: "Amazon-Katalogbild zur DNB-Ausgabe 2023 (978-3-8310-4863-2), ISBN nicht gespeichert",
  },
  {
    title: "ONE",
    isbn: "978-3-8310-4579-2",
    authors: ["Jamie Oliver"],
    publisher: "Dorling Kindersley",
    year: 2022,
    coverUrl: "/images/kochbuecher/jamie-oliver-one.jpg",
    quelle: DNB,
    hinweis: null,
    coverQuelle: "Cover zur ISBN 978-3-8310-4579-2, lesehits.de",
  },
  {
    title: "Das neue Grand Tour Kochbuch",
    isbn: "978-3-95726-080-2",
    authors: ["Hannah Grant"],
    publisher: "Covadonga",
    year: 2023,
    coverUrl: "/images/kochbuecher/grand-tour.jpg",
    quelle: DNB,
    hinweis: null,
    coverQuelle: "Cover zur ISBN 978-3-95726-080-2, lesehits.de",
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
