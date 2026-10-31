import { ko } from './ko';
import { en } from './en';

export type Locale = 'ko' | 'en';
export type Messages = typeof ko;

export const locales: Locale[] = ['ko', 'en'];
export const defaultLocale: Locale = 'ko';

const messages: Record<Locale, Messages> = { ko, en };

export function useMessages(locale: Locale = defaultLocale): Messages {
  return messages[locale];
}

export const routes = {
  home: { ko: '/', en: '/en/' },
  guide: { ko: '/guide/', en: '/en/guide/' },
  privacy: { ko: '/privacy/', en: '/en/privacy/' },
} satisfies Record<string, Record<Locale, string>>;

export type RouteName = keyof typeof routes;
