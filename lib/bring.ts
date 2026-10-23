// Bring!-Import per Deeplink (Briefing Abschnitt 5) – keine inoffizielle API.

export function siteOrigin(): string {
  if (process.env.NEXT_PUBLIC_SITE_URL) return process.env.NEXT_PUBLIC_SITE_URL.replace(/\/$/, "");
  if (typeof window !== "undefined") return window.location.origin;
  return "";
}

export function bringDeeplink(publicUrl: string): string {
  return `https://api.getbring.com/rest/bringrecipes/deeplink?url=${encodeURIComponent(publicUrl)}&source=web`;
}

export function recipePublicUrl(slug: string, servings?: number | null): string {
  return `${siteOrigin()}/r/${slug}${servings ? `?p=${servings}` : ""}`;
}

export function shoppingPublicUrl(slug: string): string {
  return `${siteOrigin()}/einkauf/${slug}`;
}
