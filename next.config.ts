import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Nur Entwicklung: Startseite ohne Anmeldung unter 127.0.0.1 testen (eigene Cookies)
  allowedDevOrigins: ["127.0.0.1"],
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "*.supabase.co" },
      { protocol: "https", hostname: "covers.openlibrary.org" },
      { protocol: "https", hostname: "books.google.com" },
    ],
  },
};

export default nextConfig;
