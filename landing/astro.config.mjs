import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: process.env.SITE_URL,
  output: 'static',
  vite: { plugins: [tailwindcss()] },
  devToolbar: { enabled: false },
});
