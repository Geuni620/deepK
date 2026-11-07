import assert from 'node:assert/strict';
import test from 'node:test';
import { publicPaths, sitemap } from '../src/data/site.ts';
import {
  consentLifetime,
  storedConsent,
  websiteEvent,
  websitePage,
} from '../src/scripts/analytics-policy.ts';

test('only the six official production routes can be measured', () => {
  for (const path of publicPaths) assert.ok(websitePage(`https://deepk.geuni.me${path}`));
  for (const url of [
    'http://localhost:4321/',
    'https://deepk-preview.vercel.app/',
    'https://geuni.me/',
    'http://deepk.geuni.me/',
    'https://deepk.geuni.me/designs/',
    'https://deepk.geuni.me/examples/playful-bear/',
    'https://deepk.geuni.me/arbitrary-user-text',
    'https://deepk.geuni.me/?embed=1',
  ])
    assert.equal(websitePage(url), undefined, url);
});

test('page and action payloads discard query, fragment, referrer path, and arbitrary campaign text', () => {
  const marker = 'SYNTHETIC_PRIVATE_MARKER';
  const page = websitePage(
    `https://deepk.geuni.me/en/guide/?email=${marker}&utm_source=${marker}#${marker}`,
    `https://github.com/example/${marker}?q=${marker}#${marker}`,
  );
  assert.equal(page.page_location, 'https://deepk.geuni.me/en/guide/');
  assert.equal(page.page_referrer, 'https://github.com');
  assert.equal(page.referral_source, 'github');
  assert.equal(page.site_locale, 'en');
  for (const name of [
    'page_view',
    'install_guide_open',
    'install_command_copy',
    'download_click',
  ]) {
    assert.equal(JSON.stringify(websiteEvent(name, page)).includes(marker), false);
  }
});

test('events accept a fixed vocabulary without taking content parameters', () => {
  const page = websitePage('https://deepk.geuni.me/');
  assert.equal(websiteEvent('arbitrary-user-text', page), undefined);
  assert.equal(websiteEvent('download_click', page).params.install_method, 'zip');
  assert.equal(websiteEvent('install_command_copy', page).params.install_method, 'homebrew');
  assert.equal('install_method' in websiteEvent('page_view', page).params, false);
});

test('invalid referrers do not become event data', () => {
  for (const referrer of ['not a URL', 'data:text/plain,PRIVATE', 'javascript:PRIVATE']) {
    const page = websitePage('https://deepk.geuni.me/', referrer);
    assert.equal(page.page_referrer, '');
    assert.equal(page.referral_source, 'direct');
  }
});

test('internal navigation and reload keep the source without promoting deepK to a new referral', () => {
  const first = websitePage('https://deepk.geuni.me/', 'https://github.com/Geuni620/deepK');
  const guide = websitePage(
    'https://deepk.geuni.me/guide/',
    'https://deepk.geuni.me/',
    first.referral_source,
  );
  assert.equal(guide.campaign_source, 'github');
  assert.equal(
    websitePage('https://deepk.geuni.me/guide/', '', guide.referral_source).campaign_source,
    'github',
  );
  assert.equal(
    websitePage('https://deepk.geuni.me/', 'https://www.google.com/', guide.referral_source)
      .campaign_source,
    'google',
  );
  const invalid = websitePage(
    'https://deepk.geuni.me/guide/',
    'https://deepk.geuni.me/',
    'SYNTHETIC_PRIVATE_MARKER',
  );
  assert.equal(invalid.campaign_source, '(direct)');
  assert.equal(JSON.stringify(invalid).includes('SYNTHETIC_PRIVATE_MARKER'), false);
});

test('consent expires and rejects invalid, future, or unrelated records', () => {
  const now = 1800000000000;
  for (const choice of ['granted', 'denied']) {
    assert.equal(storedConsent(JSON.stringify({ choice, at: now - 1 }), now), choice);
    assert.equal(
      storedConsent(JSON.stringify({ choice, at: now - consentLifetime }), now),
      undefined,
    );
  }
  for (const value of [
    null,
    '',
    '{}',
    'false',
    '{broken',
    JSON.stringify({ choice: 'granted', at: now + 1 }),
    JSON.stringify({ choice: 'other', at: now }),
  ]) {
    assert.equal(storedConsent(value, now), undefined);
  }
});

test('sitemap includes official pages and reciprocal language alternatives only', () => {
  const xml = sitemap('https://deepk.geuni.me');
  const urls = [...xml.matchAll(/<loc>(.*?)<\/loc>/g)].map((match) => match[1]);
  assert.deepEqual(urls.sort(), publicPaths.map((path) => `https://deepk.geuni.me${path}`).sort());
  assert.equal((xml.match(/hreflang="ko"/g) ?? []).length, 6);
  assert.equal((xml.match(/hreflang="en"/g) ?? []).length, 6);
  assert.equal((xml.match(/hreflang="x-default"/g) ?? []).length, 6);
  assert.equal(xml.includes('/examples/'), false);
  assert.equal(xml.includes('/designs/'), false);
});
