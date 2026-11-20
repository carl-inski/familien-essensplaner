import "server-only";
import { fetchPage, parseUserUrl } from "./fetch-page";
import { AiError } from "./guard";
import { pageLanguage, pageText, recipeFromHtml } from "../recipe-jsonld";
import { captionText, oembedEndpoint, publicPostEmbed, readSocialSource, socialCoverUrl, socialPlatform, socialSourceText } from "../recipe-source";

function validateSocialPost(url: URL) {
  const platform = socialPlatform(url);
  const path = url.pathname;
  const valid = platform === "instagram" ? /^\/(?:[\w.]+\/)?(?:p|reel|reels|tv)\/[\w-]+(?:\/|$)/.test(path) || /^\/share\/[\w-]+\/?$/.test(path)
    : platform === "youtube" ? /^[\w-]{11}$/.test(url.searchParams.get("v") ?? "")
    : platform === "tiktok" ? /^(?:vm|vt)\.tiktok\.com$/.test(url.hostname) || /^\/(?:t\/[\w-]+|@[\w.-]+\/(?:video|photo)\/\d+|v\/\d+\.html|embed\/v2\/\d+)(?:\/|$)/.test(path)
    : platform === "facebook" ? url.hostname === "fb.watch" && path.length > 1 || /\/(?:reels?|videos|posts|share|watch|permalink\.php|story\.php|photo(?:\.php)?|groups)\b/.test(path)
    : platform === "pinterest" ? url.hostname === "pin.it" && path.length > 1 || /^\/pin\/(?:[^/]+--)?\d+\/?$/.test(path)
    : false;
  if (!valid) throw new AiError("Bitte den Link zu einem einzelnen Beitrag, Reel oder Short einfügen, keinen Profil-Link.", 400, "bad-request");
}

export async function readRecipeSource(url: URL, mode: unknown, supplemented = false) {
  let platform = socialPlatform(url);
  if (platform) validateSocialPost(url);
  let source = url.href;
  let html = "";
  let sourceFailure: string | null = null;
  const warnings: string[] = [];
  try {
    const page = await fetchPage(url);
    const resolvedPlatform = socialPlatform(page.url);
    // Do not import a login page or an unrelated recipe after a social redirect.
    if (platform && resolvedPlatform !== platform) throw new AiError("Der Beitrag leitet auf eine andere Seite weiter. Bitte den direkten Beitragslink verwenden.", 422, "bad-request");
    if (mode === "social" && !resolvedPlatform) throw new AiError("Bitte einen Link zu einem Social-Media-Beitrag einfügen.", 400, "bad-request");
    const resolved = parseUserUrl(page.url.href);
    if (resolvedPlatform) {
      try { validateSocialPost(resolved); }
      catch { throw new AiError("Der Beitrag ist öffentlich nicht abrufbar. Bitte kopiere die Beschreibung oder ergänze Screenshots.", 422, "failed"); }
    }
    platform = resolvedPlatform;
    html = page.html;
    source = resolved.href;
  } catch (error) {
    if (error instanceof AiError && error.status === 400) throw error;
    sourceFailure = error instanceof AiError ? error.message : "Die Seite konnte nicht gelesen werden.";
  }

  let social = platform ? readSocialSource(html, new URL(source)) : null;
  if (social && social.text.length < 20 && !social.captions && !supplemented) {
    const embed = publicPostEmbed(new URL(source));
    if (embed) {
      try {
        const page = await fetchPage(embed, { timeoutMs: 4000 });
        if (socialPlatform(page.url) === platform) {
          const extracted = readSocialSource(page.html, new URL(source));
          if (extracted.text.length >= 20 || extracted.captions || extracted.video) {
            social = {
              text: extracted.text || social.text,
              captions: extracted.captions ?? social.captions,
              video: extracted.video ?? social.video,
              cover: extracted.cover ?? social.cover,
              partialDraft: extracted.partialDraft ?? social.partialDraft,
              images: extracted.images.length ? extracted.images : social.images,
              destinations: extracted.destinations.length ? extracted.destinations : social.destinations,
            };
            warnings.push("Aus der öffentlichen Beitrags-Einbettung übernommen.");
          }
        }
      } catch { /* Missing public embeds can still be supplemented. */ }
    }
  }
  let cover = social?.cover;
  let recipeHtml = html;
  let linkedText = "";
  let fromLd = recipeFromHtml(html, source);
  if (social && !supplemented && (!fromLd?.ingredients.length || !fromLd.steps.length)) {
    // Confirm the outbound page contains a concrete recipe before changing provenance.
    const linked = await Promise.all(social.destinations.map(async (destination) => {
      try {
        const page = await fetchPage(destination, { timeoutMs: 5_000 });
        if (socialPlatform(page.url)) return null;
        const draft = recipeFromHtml(page.html, page.url.href);
        const text = pageText(page.html);
        if (draft?.ingredients.length && draft.steps.length) return { page, draft, text: "" };
        // Editorial recipes sometimes have visible ingredients and instructions only.
        if (/^zutaten(?:liste|\s+für|\s*:|$)|^ingredients(?:\s*:|$)/im.test(text) && /\b(?:kochen|backen|braten|mischen|cook|bake|stir|mix)\b/i.test(text)) {
          return { page, draft: null, text };
        }
        return null;
      } catch { return null; }
    }));
    const match = linked.find((candidate) => candidate?.draft) ?? linked.find((candidate) => candidate !== null);
    if (match) {
      fromLd = match.draft;
      linkedText = match.text;
      recipeHtml = match.page.html;
      source = match.page.url.href;
      warnings.push("Das Rezept stammt von der im Beitrag verlinkten Seite.");
    }
  }
  let text = fromLd ? JSON.stringify(fromLd) : linkedText || (social?.text ?? pageText(html));
  if (platform && text.length < 20 && !supplemented) {
    const endpoint = oembedEndpoint(new URL(source));
    if (endpoint) {
      try {
        const embed = JSON.parse((await fetchPage(endpoint, { json: true, timeoutMs: 5_000 })).html);
        cover ??= socialCoverUrl(embed.thumbnail_url, platform);
        // Treat all returned markup as data, never execute or render the embed script.
        text = [socialSourceText(String(embed.html ?? ""), url), pageText(String(embed.html ?? "")), typeof embed.title === "string" ? embed.title : ""].filter(Boolean).join("\n").slice(0, 24000);
        if (text.length >= 20) {
          sourceFailure = null;
          warnings.push("Aus der öffentlichen Beitrags-Einbettung übernommen.");
        }
      } catch { /* The supplement path remains available when embedding is blocked. */ }
    }
  }
  let transcript = "";
  if (social?.captions && !supplemented) {
    try {
      const track = await fetchPage(social.captions, { captions: true, timeoutMs: 4_000 });
      transcript = captionText(track.html);
    } catch { /* The video or description may still contain the recipe. */ }
  }
  return { source, text, transcript, draft: fromLd, language: pageLanguage(recipeHtml),
           sourceFailure, warnings, cover, video: social?.video, images: social?.images ?? [], partialDraft: social?.partialDraft, platform };
}
