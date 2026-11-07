import { publicPath, siteOrigin } from '../data/site.ts';

export const consentKey = 'deepk.website-analytics.v1';
export const sourceKey = 'deepk.website-source.v1';
export const consentLifetime = 180 * 24 * 60 * 60 * 1000;
export type Consent = 'granted' | 'denied';
export type WebsiteEvent =
  'page_view' | 'install_guide_open' | 'install_command_copy' | 'download_click';

const titles = {
  '/': 'deepK — Mac translation',
  '/en/': 'deepK — Mac translation (English)',
  '/guide/': 'deepK — Setup',
  '/en/guide/': 'deepK — Setup (English)',
  '/privacy/': 'deepK — Privacy',
  '/en/privacy/': 'deepK — Privacy (English)',
} as const;

const referralSources = [
  'direct',
  'github',
  'x',
  'bluesky',
  'google',
  'naver',
  'tistory',
  'geuni',
  'other',
] as const;
type ReferralSource = (typeof referralSources)[number];

function sourceFor(host: string): ReferralSource {
  if (host === 'github.com') return 'github';
  if (host === 'x.com' || host === 't.co' || host === 'twitter.com') return 'x';
  if (host === 'bsky.app') return 'bluesky';
  if (host === 'google.com' || host.endsWith('.google.com') || host === 'google.co.kr')
    return 'google';
  if (host === 'naver.com' || host.endsWith('.naver.com')) return 'naver';
  if (host.endsWith('.tistory.com')) return 'tistory';
  if (host === 'geuni.me' || host.endsWith('.geuni.me')) return 'geuni';
  return 'other';
}

export function websitePage(location: string, referrer = '', previousSource?: string) {
  const url = new URL(location);
  const path = publicPath(url.pathname);
  if (url.origin !== siteOrigin || !path || url.searchParams.has('embed')) return undefined;
  let origin = '';
  let source: ReferralSource =
    referralSources.find((value) => value === previousSource) ?? 'direct';
  try {
    const from = new URL(referrer);
    if (from.protocol === 'https:' || from.protocol === 'http:') {
      origin = from.origin;
      if (from.origin !== siteOrigin) source = sourceFor(from.hostname);
    }
  } catch {
    /* No referrer. */
  }
  return {
    page_location: `${siteOrigin}${path}`,
    page_referrer: origin,
    page_title: titles[path],
    site_locale: path.startsWith('/en/') ? 'en' : 'ko',
    referral_source: source,
    // Override campaign extraction so arbitrary UTM values cannot become event data.
    campaign_source: source === 'direct' ? '(direct)' : source,
    campaign_medium:
      source === 'direct'
        ? '(none)'
        : source === 'google' || source === 'naver'
          ? 'organic'
          : 'referral',
    campaign_name: 'deepk-website',
    campaign_id: 'deepk-website',
    campaign_term: '(not set)',
    campaign_content: '(not set)',
  };
}

export function storedConsent(value: string | null, now = Date.now()): Consent | undefined {
  try {
    const record = JSON.parse(value ?? 'null');
    if (
      (record?.choice === 'granted' || record?.choice === 'denied') &&
      typeof record.at === 'number' &&
      Number.isFinite(record.at) &&
      record.at <= now &&
      now - record.at < consentLifetime
    )
      return record.choice;
  } catch {
    /* Storage is optional. */
  }
  return undefined;
}

export function websiteEvent(name: string, page: NonNullable<ReturnType<typeof websitePage>>) {
  if (!['page_view', 'install_guide_open', 'install_command_copy', 'download_click'].includes(name))
    return undefined;
  return {
    name: name as WebsiteEvent,
    params: {
      ...page,
      ...(name === 'install_command_copy' ? { install_method: 'homebrew' } : {}),
      ...(name === 'download_click' ? { install_method: 'zip' } : {}),
    },
  };
}
