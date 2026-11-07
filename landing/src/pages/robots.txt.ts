import type { APIRoute } from 'astro';
import { siteOrigin } from '../data/site';

export const GET: APIRoute = ({ site }) =>
  new Response(`User-agent: *\nAllow: /\n\nSitemap: ${site?.origin ?? siteOrigin}/sitemap.xml\n`, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
