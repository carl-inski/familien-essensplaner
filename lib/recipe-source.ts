import { cleanText, decodeEntities, recipeFromJsonLd } from "./recipe-jsonld";
import { splitIngredientLine } from "./quantity";

function ingredientsFromLabeledCaption(title: unknown, description: unknown, source: string) {
  if (typeof title !== "string" || typeof description !== "string") return null;
  const section = description.match(/^(?:zutaten(?:übersicht|liste)?|ingredients)\s*:?\s*\n([\s\S]+)/im)?.[1];
  if (!section) return null;
  const lines: string[] = [];
  let measured = 0;
  for (const line of section.split(/\r?\n/)) {
    const text = line.trim().replace(/^[-•*]\s+/, "");
    if (!text) {
      if (lines.length) break;
      continue;
    }
    const { amount_text, name } = splitIngredientLine(text);
    if (!amount_text && !/^(?:nach Geschmack|to taste|optional)\s+\S/i.test(text)) break;
    if (amount_text && name !== text) measured++;
    lines.push(text);
    if (lines.length === 60) break;
  }
  return measured >= 2 ? recipeFromJsonLd({ "@type": "Recipe", name: title, recipeIngredient: lines }, source) : null;
}

export type SocialPlatform = "instagram" | "facebook" | "tiktok" | "youtube" | "pinterest";

const matchesHost = (host: string, domain: string) => host === domain || host.endsWith(`.${domain}`);

export function socialPlatform(url: URL): SocialPlatform | null {
  const host = url.hostname.toLowerCase();
  if (matchesHost(host, "instagram.com")) return "instagram";
  if (matchesHost(host, "facebook.com") || host === "fb.watch" || host === "fb.com") return "facebook";
  if (matchesHost(host, "tiktok.com")) return "tiktok";
  if (matchesHost(host, "youtube.com") || host === "youtu.be") return "youtube";
  if (matchesHost(host, "pinterest.com") || host === "pin.it") return "pinterest";
  return null;
}

/** Accept the text produced by mobile share sheets, but never guess between links. */
export function parseImportUrl(raw: unknown): URL {
  const value = typeof raw === "string" ? raw.trim() : "";
  if (!value || value.length > 4096) throw new Error("Bitte einen gültigen Link einfügen.");
  const links = value.match(/https?:\/\/[^\s<>"“”]+/gi);
  if (links && links.length !== 1) throw new Error("Bitte genau einen Link einfügen.");
  const input = links?.[0].replace(/[.,!?;]+$/, "").replace(/\)+$/, (closing, offset, link: string) => {
    const prefix = link.slice(0, offset);
    const unmatched = (prefix.match(/\(/g)?.length ?? 0) - (prefix.match(/\)/g)?.length ?? 0);
    return closing.slice(0, Math.max(0, unmatched));
  }) ?? value;
  if (/^[a-z][a-z\d+.-]*:/i.test(input) && !/^https?:\/\//i.test(input)) throw new Error("Bitte einen http- oder https-Link einfügen.");
  let url: URL;
  try { url = new URL(/^https?:\/\//i.test(input) ? input : `https://${input}`); }
  catch { throw new Error("Das sieht nicht nach einem Link aus."); }
  if (url.username || url.password || !url.hostname.includes(".") && !url.hostname.includes(":")) throw new Error("Bitte einen öffentlichen Link ohne Zugangsdaten einfügen.");
  url.hash = "";
  for (const key of [...url.searchParams.keys()]) {
    if (/^(utm_.+|igsh|igshid|fbclid|gclid|si|feature|_r|_t)$/i.test(key)) url.searchParams.delete(key);
  }
  if (socialPlatform(url) === "youtube") {
    const id = url.hostname === "youtu.be" ? url.pathname.split("/")[1]
      : url.pathname.match(/^\/(?:shorts|embed)\/([^/]+)/)?.[1] ?? url.searchParams.get("v");
    if (id && /^[\w-]{11}$/.test(id)) url = new URL(`https://www.youtube.com/watch?v=${id}`);
  }
  if (socialPlatform(url) === "instagram") {
    const post = url.pathname.match(/^\/(?:[\w.]+\/)?(p|reel|reels|tv)\/([\w-]+)(?:\/(?:embed(?:\/captioned)?\/?)?)?$/);
    if (post && !url.pathname.startsWith("/share/")) {
      url.pathname = `/${post[1] === "reels" ? "reel" : post[1]}/${post[2]}/`;
    }
  }
  return url;
}

function attributes(tag: string): Record<string, string> {
  return Object.fromEntries([...tag.matchAll(/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)]
    .map((m) => [m[1].toLowerCase(), decodeEntities(m[2] ?? m[3] ?? m[4])]));
}

const obj = (value: unknown): Record<string, unknown> | null => value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
const at = (value: unknown, ...keys: string[]): unknown => keys.reduce<unknown>((current, key) => obj(current)?.[key], value);

function* objects(root: unknown): Generator<Record<string, unknown>> {
  const pending = [root];
  while (pending.length) {
    const value = pending.pop();
    if (Array.isArray(value)) { for (const item of value) pending.push(item); continue; }
    const node = obj(value);
    if (!node) continue;
    yield node;
    for (const child of Object.values(node)) if (typeof child === "object" && child !== null) pending.push(child);
  }
}

/** Read a JSON object assigned in a script without executing JavaScript. */
function assignedJson(script: string, marker: string): unknown {
  const index = script.indexOf(marker);
  if (index < 0) return null;
  const start = script.indexOf("{", index + marker.length);
  if (start < 0) return null;
  let depth = 0, inString = false, escaped = false;
  for (let i = start; i < script.length; i++) {
    const c = script[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') inString = false;
    } else if (c === '"') inString = true;
    else if (c === "{") depth++;
    else if (c === "}" && --depth === 0) {
      try { return JSON.parse(script.slice(start, i + 1)); } catch { return null; }
    }
  }
  return null;
}

const LOGIN_TEXT = /^(?:log\s?in|sign (?:up|in)|anmelden|melde dich|bei facebook anmelden|instagram (?:photos|fotos)|watch .* videos? on tiktok|enjoy the videos and music)/i;

/** Only read the requested post, never comments, feeds or recommended videos. */
export function readSocialSource(html: string, url: URL) {
  const platform = socialPlatform(url);
  const chunks: string[] = [];
  let video: URL | undefined;
  let captions: URL | undefined;
  let cover: URL | undefined;
  let partialDraft: ReturnType<typeof ingredientsFromLabeledCaption> = null;
  const images = new Map<string, URL>();
  const addCover = (value: unknown) => { cover ??= socialCoverUrl(value, platform); };
  const addImage = (value: unknown) => {
    const image = socialCoverUrl(value, platform);
    if (image && images.size < 3) images.set(image.href, image);
  };
  const destinations = new Set<string>();
  const originalVideo = (value: unknown, domains: string[]) => {
    const candidate = publicMediaUrl(value, domains);
    if (candidate) video ??= candidate;
  };
  const captionTrack = (value: unknown, domains: string[]) => {
    const candidate = publicMediaUrl(value, domains);
    if (candidate) captions ??= candidate;
  };
  const facebookId = url.pathname.match(/\/(\d+)\/?$/)?.[1] ?? url.searchParams.get("v");
  const tiktokId = url.pathname.match(/\/(?:video|photo|v|embed\/v2)\/(\d+)/)?.[1];
  const instagramCode = url.pathname.match(/\/(?:p|reel|reels|tv)\/([^/]+)/)?.[1];

  const add = (value: unknown) => {
    if (typeof value !== "string") return;
    const text = cleanText(value);
    if (text && !LOGIN_TEXT.test(text) && !chunks.includes(text)) chunks.push(text);
  };
  // Full descriptions first; OG descriptions are frequently truncated.
  for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
    const attrs = attributes(match[1]);
    const script = match[2];
    if (platform === "youtube" && script.includes("ytInitialPlayerResponse")) {
      const player = assignedJson(script, "ytInitialPlayerResponse");
      if (at(player, "videoDetails", "videoId") === url.searchParams.get("v")) {
        const title = at(player, "videoDetails", "title");
        const description = at(player, "videoDetails", "shortDescription");
        add(title);
        add(description);
        partialDraft ??= ingredientsFromLabeledCaption(title, description, url.href);
        video = url;
        const thumbnails = at(player, "videoDetails", "thumbnail", "thumbnails");
        if (Array.isArray(thumbnails)) {
          for (const thumbnail of thumbnails.slice().reverse()) addCover(at(thumbnail, "url"));
        }
        const tracks = at(player, "captions", "playerCaptionsTracklistRenderer", "captionTracks");
        if (Array.isArray(tracks)) captionTrack(at(tracks[0], "baseUrl"), ["youtube.com"]);
      }
    }
    if (attrs.type !== "application/json" && attrs.type !== "application/ld+json" && !["SIGI_STATE", "__UNIVERSAL_DATA_FOR_REHYDRATION__"].includes(attrs.id)) continue;
    let data: unknown;
    try { data = JSON.parse(script); } catch { continue; }
    if (platform === "tiktok") {
      const item = at(data, "__DEFAULT_SCOPE__", "webapp.video-detail", "itemInfo", "itemStruct");
      const current = tiktokId && String(at(item, "id")) === tiktokId ? item : tiktokId ? at(data, "ItemModule", tiktokId) : null;
      const meta = at(current, "video");
      add(at(current, "desc"));
      addCover(at(meta, "originCover") || at(meta, "cover"));
      originalVideo(at(meta, "downloadAddr") || at(meta, "playAddr"), TIKTOK_MEDIA);
      const tracks = at(meta, "subtitleInfos");
      if (Array.isArray(tracks)) {
        const preferred = tracks.find((track) => /^(de|en)(?:[-_]|$)/i.test(String(at(track, "LanguageCode") ?? at(track, "languageCode") ?? "")));
        for (const track of [preferred, ...tracks]) captionTrack(at(track, "Url") ?? at(track, "url"), TIKTOK_MEDIA);
      }
      const slides = at(current, "imagePost", "images");
      if (Array.isArray(slides)) {
        for (const slide of slides) {
          const urls = at(slide, "displayImage", "urlList");
          if (Array.isArray(urls)) addImage(urls[0]);
        }
      }
    }
    if (platform === "facebook" && facebookId) {
      for (const node of objects(data)) {
        if (String(node.id) === facebookId) {
          const story = node.creation_story;
          add(at(story, "message", "text"));
          add(at(story, "comet_sections", "message", "story", "message", "text"));
          add(at(node.savable_description, "text"));
          originalVideo(node.browser_native_sd_url, ["fbcdn.net"]);
          addCover(at(node.preferred_thumbnail, "image", "uri"));
          captionTrack(node.captions_url, ["fbcdn.net"]);
          const tracks = node.video_available_captions_locales;
          if (Array.isArray(tracks)) {
            const original = tracks.find((track) => /^(en|de)(?:[_-]|$)/i.test(String(at(track, "locale") ?? at(track, "locale_code") ?? ""))) ?? tracks[0];
            captionTrack(at(original, "captions_url"), ["fbcdn.net"]);
          }
        }
      }
    }
    if (platform === "instagram") {
      const media = at(data, "graphql", "shortcode_media") ?? at(data, "data", "xdt_shortcode_media");
      if (instagramCode && at(media, "shortcode") === instagramCode) {
        originalVideo(at(media, "video_url"), ["cdninstagram.com", "fbcdn.net"]);
        addCover(at(media, "display_url"));
        const edges = at(media, "edge_media_to_caption", "edges");
        if (Array.isArray(edges)) for (const edge of edges) add(at(edge, "node", "text"));
      }
      // Public Instagram posts also publish the current media inside Polaris data.
      if (instagramCode && script.includes('"if_not_gated_logged_out"')) {
        for (const node of objects(data)) {
          const current = obj(node.if_not_gated_logged_out);
          if (current?.code !== instagramCode) continue;
          add(at(current, "caption", "text"));
          addCover(current.display_uri);
          if (Array.isArray(current.video_versions)) {
            for (const version of current.video_versions) originalVideo(at(version, "url"), ["cdninstagram.com", "fbcdn.net"]);
          }
          if (Array.isArray(current.carousel_media)) {
            for (const slide of current.carousel_media) {
              const candidates = at(slide, "image_versions2", "candidates");
              addImage(at(slide, "display_uri") ?? (Array.isArray(candidates) ? at(candidates[0], "url") : undefined));
            }
          } else if (current.media_type === 1) {
            addImage(current.display_uri);
          }
        }
      }
    }
    if (attrs.type === "application/ld+json") {
      const nodes = Array.isArray(data) ? data : [data, ...(Array.isArray(at(data, "@graph")) ? at(data, "@graph") as unknown[] : [])];
      for (const node of nodes) {
        if (["VideoObject", "SocialMediaPosting"].includes(String(at(node, "@type")))) add(at(node, "description"));
      }
    }
  }
  for (const match of html.matchAll(/<meta\b(?:[^>"']|"[^"]*"|'[^']*')*>/gi)) {
    const attrs = attributes(match[0]);
    const key = attrs.property ?? attrs.name;
    if (["og:description", "twitter:description", "description"].includes(key)) add(attrs.content);
    if (["og:image", "og:image:secure_url", "twitter:image"].includes(key)) addCover(attrs.content);
    if (platform === "pinterest" && ["og:see_also", "pinterestapp:source"].includes(key)) destinations.add(attrs.content);
    if (platform === "instagram" && ["og:video", "og:video:secure_url"].includes(key)) originalVideo(attrs.content, ["cdninstagram.com", "fbcdn.net"]);
  }
  if (platform === "instagram" && instagramCode) {
    for (const match of html.matchAll(/<(div|span)\b[^>]*\bclass=(["'])[^"']*\bCaption\b[^"']*\2[^>]*>([\s\S]*?)<\/\1>/gi)) {
      add(match[3]);
    }
  }
  const text = chunks.join("\n\n").slice(0, 24000);
  for (const match of text.matchAll(/https?:\/\/[^\s<>"“”]+/gi)) destinations.add(match[0].replace(/[.,;!?)]*$/, ""));
  return { text, video, captions, cover, partialDraft, images: [...images.values()], destinations: recipeDestinations(destinations) };
}

export function socialSourceText(html: string, url: URL): string {
  return readSocialSource(html, url).text;
}

const TIKTOK_MEDIA = ["tiktokcdn.com", "tiktokcdn-us.com", "tiktokcdn-eu.com", "tiktok.com"];

const COVER_DOMAINS: Record<SocialPlatform, string[]> = {
  instagram: ["cdninstagram.com", "fbcdn.net"],
  facebook: ["fbcdn.net"],
  tiktok: [...TIKTOK_MEDIA.filter((domain) => domain !== "tiktok.com"), "tiktokcdn-eu.net", "tiktokcdn-us.net"],
  youtube: ["ytimg.com"],
  pinterest: ["pinimg.com"],
};

export function socialCoverUrl(value: unknown, platform: SocialPlatform | null): URL | undefined {
  return platform ? publicMediaUrl(value, COVER_DOMAINS[platform]) : undefined;
}

function publicMediaUrl(value: unknown, domains: string[]): URL | undefined {
  if (typeof value !== "string") return;
  try {
    const url = new URL(value);
    if (url.protocol === "https:" && !url.username && !url.password && !url.port &&
        domains.some((domain) => matchesHost(url.hostname, domain))) return url;
  } catch { /* Missing or malformed platform media URL. */ }
}

function recipeDestinations(values: Set<string>): URL[] {
  const candidates = new Map<string, URL>();
  for (const value of values) {
    try {
      let url = parseImportUrl(value);
      if (socialPlatform(url) === "youtube" && url.pathname === "/redirect") url = parseImportUrl(url.searchParams.get("q"));
      if (socialPlatform(url) || url.pathname === "/" || /(?:^|[.])(?:bit\.ly|liketk\.it)$/.test(url.hostname)) continue;
      candidates.set(url.href, url);
    } catch { /* Ignore malformed links in captions. */ }
  }
  const recipePath = (url: URL) => Number(/recipe|rezept/i.test(url.pathname));
  return [...candidates.values()].sort((a, b) => recipePath(b) - recipePath(a)).slice(0, 3);
}

export function captionText(raw: string): string {
  const body = raw.trim();
  if (!body || /^<(?:!doctype html|html|script)\b/i.test(body)) return "";
  if (/^<\?xml|^<(?:transcript|timedtext)\b/i.test(body)) {
    return [...body.matchAll(/<(text|p)\b[^>]*>([\s\S]*?)<\/\1>/gi)]
      .map((match) => cleanText(match[2])).join("\n").slice(0, 16000);
  }
  if (!/-->/m.test(body)) return "";
  const cues = body.split(/\r?\n\s*\r?\n/).flatMap((block) => {
    const lines = block.split(/\r?\n/);
    const index = lines.findIndex((line) => line.includes("-->"));
    return index < 0 ? [] : lines.slice(index + 1).map(cleanText).filter(Boolean);
  });
  return [...new Set(cues)].join("\n").slice(0, 16000);
}

/** Never trust a remote oEmbed discovery URL supplied by the page. */
export function oembedEndpoint(url: URL): URL | null {
  const platform = socialPlatform(url);
  const endpoint = platform === "tiktok" ? "https://www.tiktok.com/oembed"
    : platform === "instagram" ? "https://graph.facebook.com/v27.0/instagram_oembed"
    : platform === "facebook" ? `https://graph.facebook.com/v27.0/oembed_${/\/(?:reel|reels|videos|watch)\b|fb\.watch/.test(url.href) ? "video" : "post"}` : null;
  if (!endpoint) return null;
  const result = new URL(endpoint);
  result.searchParams.set("url", url.href);
  result.searchParams.set("omitscript", "true");
  return result;
}

export function publicPostEmbed(url: URL): URL | null {
  const platform = socialPlatform(url);
  const post = url.pathname.match(/^\/(p|reel|tv)\/([\w-]+)\/?$/);
  if (platform === "instagram" && post) return new URL(`https://www.instagram.com/${post[1]}/${post[2]}/embed/captioned/`);
  const video = url.pathname.match(/\/(?:video|v|embed\/v2)\/(\d+)/);
  if (platform === "tiktok" && video) return new URL(`https://www.tiktok.com/embed/v2/${video[1]}`);
  return null;
}

export function recipeImportWarnings(draft: { ingredients: { amount_text: string | null }[]; steps: string[] }): string[] {
  const warnings: string[] = [];
  if (!draft.ingredients.length) warnings.push("In der Quelle wurden keine Zutaten gefunden. Bitte ergänzen.");
  else if (draft.ingredients.some((i) => !i.amount_text)) warnings.push("Bei einigen Zutaten fehlt die Menge.");
  if (!draft.steps.length) warnings.push("In der Quelle wurde keine Zubereitung gefunden. Bitte ergänzen.");
  return warnings;
}
