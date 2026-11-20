// Lasttest für den Launch (k6: https://k6.io). Simuliert, was viele Familien gleichzeitig tun:
// Startseite, Health-Check und – mit Testkonto – die Lese-Abfragen von Woche und Einkauf.
//
//   brew install k6
//   SITE=https://<preview-url> SUPABASE_URL=https://<ref>.supabase.co SUPABASE_KEY=sb_publishable_… \
//   TEST_TOKEN=<access_token eines Testkontos> k6 run scripts/loadtest.k6.js
//
// Nie gegen Produktion mit echten Familien laufen lassen, sondern gegen eine Preview-Umgebung
// mit eigenem Supabase-Projekt (siehe docs/LAUNCH.md). Nur lesend.

import http from "k6/http";
import { check, sleep } from "k6";

const SITE = __ENV.SITE;
const SB = __ENV.SUPABASE_URL;
const KEY = __ENV.SUPABASE_KEY;
const TOKEN = __ENV.TEST_TOKEN;

export const options = {
  // 10.000 Nutzer ≈ 1.000 gleichzeitig am Abend; mit Reserve bis 1.500
  stages: [
    { duration: "2m", target: 300 },
    { duration: "5m", target: 1000 },
    { duration: "3m", target: 1500 },
    { duration: "2m", target: 0 },
  ],
  thresholds: {
    http_req_failed: ["rate<0.01"],
    "http_req_duration{kind:page}": ["p(95)<1200"],
    "http_req_duration{kind:api}": ["p(95)<400"],
  },
};

function day(offset) {
  const d = new Date(Date.now() + offset * 86400000);
  return d.toISOString().slice(0, 10);
}

export default function familyEvening() {
  check(http.get(`${SITE}/`, { tags: { kind: "page" } }), { "Startseite 200": (r) => r.status === 200 });
  check(http.get(`${SITE}/api/health`, { tags: { kind: "api" } }), { "Health 200": (r) => r.status === 200 });

  if (SB && KEY && TOKEN) {
    const headers = { apikey: KEY, Authorization: `Bearer ${TOKEN}` };
    const from = day(0);
    const to = day(6);
    const res = http.batch([
      ["GET", `${SB}/rest/v1/ep_meal_plan?select=*&date=gte.${from}&date=lte.${to}`, null, { headers, tags: { kind: "api" } }],
      ["GET", `${SB}/rest/v1/ep_recipes?select=id,title,tags&limit=200`, null, { headers, tags: { kind: "api" } }],
      ["GET", `${SB}/rest/v1/ep_shopping_extra?select=id,text&order=created_at`, null, { headers, tags: { kind: "api" } }],
    ]);
    res.forEach((r) => check(r, { "REST 200": (x) => x.status === 200 }));
  }
  sleep(3 + Math.random() * 4);
}
