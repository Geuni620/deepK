import {
  consentKey,
  sourceKey,
  storedConsent,
  websiteEvent,
  websitePage,
  type Consent,
} from './analytics-policy';

declare global {
  interface Window {
    dataLayer?: unknown[];
    gtag?: (...args: unknown[]) => void;
  }
}

const root = document.querySelector<HTMLElement>('[data-website-analytics]');
const measurementId = root?.dataset.measurementId;
let previousSource: string | undefined;
try {
  previousSource = sessionStorage.getItem(sourceKey) ?? undefined;
} catch {
  /* Storage is optional. */
}
const page = websitePage(location.href, document.referrer, previousSource);
const banner = root?.querySelector<HTMLElement>('[data-analytics-banner]');
const status = root?.querySelector<HTMLElement>('[data-analytics-status]');
const en = document.documentElement.lang === 'en';
const privateBrowser =
  navigator.doNotTrack === '1' ||
  (navigator as Navigator & { globalPrivacyControl?: boolean }).globalPrivacyControl === true;

if (root && !page) root.hidden = true;

if (root && banner && measurementId && /^G-[A-Z0-9]+$/.test(measurementId) && page) {
  let consent: Consent | undefined;
  let initialized = false;
  let countedPage = false;

  const track = (name: string) => {
    if (consent !== 'granted' || privateBrowser) return;
    const event = websiteEvent(name, page);
    if (event) window.gtag?.('event', event.name, event.params);
  };

  const clearCookies = () => {
    for (const part of document.cookie.split(';')) {
      const name = part.split('=')[0].trim();
      if (!name.startsWith('deepk_ga')) continue;
      document.cookie = `${name}=; Max-Age=0; Path=/; SameSite=Lax; Secure`;
      document.cookie = `${name}=; Max-Age=0; Domain=deepk.geuni.me; Path=/; SameSite=Lax; Secure`;
    }
  };

  const applyConsent = (choice?: Consent) => {
    consent = privateBrowser ? 'denied' : choice;
    Reflect.set(window, `ga-disable-${measurementId}`, consent !== 'granted');
    banner.hidden = consent !== undefined || privateBrowser;
    if (status)
      status.textContent = privateBrowser
        ? en
          ? 'Browser privacy preference respected'
          : '브라우저 추적 거부 설정 적용 중'
        : consent === 'granted'
          ? en
            ? 'Allowed'
            : '허용됨'
          : consent === 'denied'
            ? en
              ? 'Off'
              : '꺼짐'
            : '';

    if (consent !== 'granted') {
      if (initialized) window.gtag?.('consent', 'update', { analytics_storage: 'denied' });
      clearCookies();
      try {
        sessionStorage.removeItem(sourceKey);
      } catch {
        /* Storage is optional. */
      }
      return;
    }
    try {
      sessionStorage.setItem(sourceKey, page.referral_source);
    } catch {
      /* Memory only. */
    }
    if (!initialized) {
      initialized = true;
      window.dataLayer = window.dataLayer ?? [];
      window.gtag = function () {
        window.dataLayer!.push(arguments);
      };
      window.gtag('consent', 'default', {
        analytics_storage: 'denied',
        ad_storage: 'denied',
        ad_user_data: 'denied',
        ad_personalization: 'denied',
      });
      window.gtag('set', {
        ...page,
        allow_google_signals: false,
        allow_ad_personalization_signals: false,
      });
      window.gtag('consent', 'update', { analytics_storage: 'granted' });
      window.gtag('js', new Date());
      window.gtag('config', measurementId, {
        ...page,
        send_page_view: false,
        allow_google_signals: false,
        allow_ad_personalization_signals: false,
        cookie_domain: 'deepk.geuni.me',
        cookie_prefix: 'deepk',
        cookie_expires: 90 * 24 * 60 * 60,
        cookie_flags: 'SameSite=Lax;Secure',
      });
      const script = document.createElement('script');
      script.async = true;
      script.src = `https://www.googletagmanager.com/gtag/js?id=${measurementId}`;
      document.head.append(script);
    } else {
      window.gtag?.('consent', 'update', { analytics_storage: 'granted' });
    }
    if (!countedPage) {
      countedPage = true;
      track('page_view');
    }
  };

  let initial: Consent | undefined;
  try {
    initial = storedConsent(localStorage.getItem(consentKey));
  } catch {
    /* No storage: ask each visit. */
  }
  applyConsent(initial);

  root.addEventListener('click', (event) => {
    if (!(event.target instanceof Element)) return;
    if (event.target.closest('[data-analytics-settings]')) {
      if (!privateBrowser) banner.hidden = false;
      return;
    }
    const choice =
      event.target.closest<HTMLElement>('[data-analytics-choice]')?.dataset.analyticsChoice;
    if (choice !== 'granted' && choice !== 'denied') return;
    try {
      localStorage.setItem(consentKey, JSON.stringify({ choice, at: Date.now() }));
    } catch {
      /* Memory only. */
    }
    applyConsent(choice);
  });

  document.addEventListener('deepk:website-action', (event) => {
    if (event instanceof CustomEvent && typeof event.detail === 'string') track(event.detail);
  });
  document.addEventListener('click', (event) => {
    if (!(event.target instanceof Element)) return;
    if (event.target.closest('[data-install-download]')) track('download_click');
    if (event.target.closest('[data-install-guide]')) track('install_guide_open');
  });
  window.addEventListener('storage', (event) => {
    if (event.key === consentKey || event.key === null) applyConsent(storedConsent(event.newValue));
  });
}
