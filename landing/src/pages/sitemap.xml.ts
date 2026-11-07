import type { APIRoute } from 'astro';
import { sitemap, siteOrigin } from '../data/site';

export const GET: APIRoute = ({ site }) =>
  new Response(sitemap(site?.origin ?? siteOrigin), {
    headers: { 'Content-Type': 'application/xml; charset=utf-8' },
  });
