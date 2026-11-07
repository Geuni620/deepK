export const siteOrigin = 'https://deepk.geuni.me';

// Keep experimental designs and editable demos out of both indexing and analytics.
export const publicPaths = [
  '/',
  '/en/',
  '/guide/',
  '/en/guide/',
  '/privacy/',
  '/en/privacy/',
] as const;

export type PublicPath = (typeof publicPaths)[number];

export function publicPath(pathname: string): PublicPath | undefined {
  return publicPaths.find((path) => path === pathname);
}

export function sitemap(origin: string): string {
  const base = new URL(origin);
  const pairs = [
    ['/', '/en/'],
    ['/guide/', '/en/guide/'],
    ['/privacy/', '/en/privacy/'],
  ];
  const entries = pairs.flatMap(([ko, en]) =>
    [ko, en].map(
      (path) => `  <url>
    <loc>${new URL(path, base).href}</loc>
    <xhtml:link rel="alternate" hreflang="ko" href="${new URL(ko, base).href}" />
    <xhtml:link rel="alternate" hreflang="en" href="${new URL(en, base).href}" />
    <xhtml:link rel="alternate" hreflang="x-default" href="${new URL(ko, base).href}" />
  </url>`,
    ),
  );
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${entries.join('\n')}
</urlset>\n`;
}
