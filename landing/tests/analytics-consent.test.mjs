import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import ts from 'typescript';
import * as policy from '../src/scripts/analytics-policy.ts';

const code = ts.transpileModule(
  readFileSync(new URL('../src/scripts/website-analytics.ts', import.meta.url), 'utf8'),
  { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } },
).outputText;

function browser({ choice, url = 'https://deepk.geuni.me/', dnt, gpc, noStorage = false } = {}) {
  class Element extends EventTarget {
    dataset = {};
    hidden = true;
    textContent = '';
    selectors = new Map();
    querySelector(selector) {
      return this.selectors.get(selector);
    }
    closest(selector) {
      return this.selectors.has(selector) ? this : null;
    }
  }
  const root = new Element();
  root.hidden = false;
  const banner = new Element();
  const status = new Element();
  root.dataset.measurementId = 'G-SYNTHETIC';
  root.selectors.set('[data-analytics-banner]', banner);
  root.selectors.set('[data-analytics-status]', status);
  const document = new EventTarget();
  const window = new EventTarget();
  const scripts = [];
  const cookies = new Map([
    ['_ga', 'unrelated'],
    ['deepk_ga', 'synthetic'],
    ['deepk_ga_SYNTHETIC', 'synthetic'],
    ['deepk__ga_SYNTHETIC', 'synthetic'],
    ['_ga_SYNTHETIC', 'synthetic-legacy-session'],
  ]);
  Object.defineProperty(document, 'cookie', {
    get: () => [...cookies].map(([name, value]) => `${name}=${value}`).join('; '),
    set: (value) => {
      if (value.includes('Max-Age=0')) cookies.delete(value.split('=')[0]);
    },
  });
  document.querySelector = () => root;
  document.documentElement = { lang: 'ko' };
  document.referrer = 'https://github.com/example/SYNTHETIC_PRIVATE?token=SYNTHETIC_PRIVATE';
  document.head = { append: (element) => scripts.push(element) };
  document.createElement = () => ({});
  const storage = new Map(
    choice ? [[policy.consentKey, JSON.stringify({ choice, at: Date.now() })]] : [],
  );
  const localStorage = {
    getItem(key) {
      if (noStorage) throw Error('blocked');
      return storage.get(key) ?? null;
    },
    setItem(key, value) {
      if (noStorage) throw Error('blocked');
      storage.set(key, value);
    },
  };
  const sourceStorage = new Map();
  const sessionStorage = {
    getItem: (key) => sourceStorage.get(key) ?? null,
    setItem: (key, value) => sourceStorage.set(key, value),
    removeItem: (key) => sourceStorage.delete(key),
  };
  vm.runInNewContext(code, {
    exports: {},
    require: () => policy,
    document,
    window,
    location: { href: url },
    navigator: { doNotTrack: dnt, globalPrivacyControl: gpc },
    Element,
    CustomEvent,
    URL,
    localStorage,
    sessionStorage,
  });
  const click = (selector, dataset = {}) => {
    const target = new Element();
    target.selectors.set(selector, true);
    target.dataset = dataset;
    const event = new Event('click');
    Object.defineProperty(event, 'target', { value: target });
    root.dispatchEvent(event);
  };
  const choose = (choice) => click('[data-analytics-choice]', { analyticsChoice: choice });
  const actions = () => Array.from(window.dataLayer ?? [], (args) => Array.from(args));
  const events = () => actions().filter(([action]) => action === 'event');
  const action = (name) =>
    document.dispatchEvent(new CustomEvent('deepk:website-action', { detail: name }));
  return {
    window,
    root,
    document,
    scripts,
    cookies,
    banner,
    storage,
    choose,
    click,
    actions,
    events,
    action,
  };
}

test('fresh and declined visits do not load Google or queue measurement', () => {
  for (const choice of [undefined, 'denied']) {
    const b = browser({ choice });
    b.action('download_click');
    assert.equal(b.scripts.length, 0);
    assert.equal(b.actions().length, 0);
    assert.equal(b.window['ga-disable-G-SYNTHETIC'], true);
    assert.equal(b.banner.hidden, choice === 'denied');
  }
});

test('granting consent loads one tag, disables advertising and automatic page views, and sends safe events', () => {
  const b = browser();
  b.choose('granted');
  b.action('download_click');
  b.action('PRIVATE_CONTENT');
  b.choose('granted');
  assert.equal(b.scripts.length, 1);
  assert.equal(b.scripts[0].src, 'https://www.googletagmanager.com/gtag/js?id=G-SYNTHETIC');
  assert.deepEqual(
    b.events().map(([, name]) => name),
    ['page_view', 'download_click'],
  );
  const config = b.actions().find(([action]) => action === 'config')[2];
  assert.equal(config.send_page_view, false);
  assert.equal(config.allow_google_signals, false);
  assert.equal(config.allow_ad_personalization_signals, false);
  assert.equal(config.cookie_domain, 'deepk.geuni.me');
  assert.equal(config.cookie_prefix, 'deepk');
  const globalSettings = b.actions().find(([action]) => action === 'set')[1];
  assert.equal(globalSettings.cookie_prefix, 'deepk');
  assert.equal(globalSettings.cookie_domain, 'deepk.geuni.me');
  assert.equal(JSON.stringify(b.actions()).includes('SYNTHETIC_PRIVATE'), false);
  const initialConsent = b
    .actions()
    .find(([action, phase]) => action === 'consent' && phase === 'default')[2];
  assert.equal(initialConsent.ad_storage, 'denied');
  assert.equal(initialConsent.ad_user_data, 'denied');
  assert.equal(initialConsent.ad_personalization, 'denied');
});

test('revoking consent stops own events and clears only deepK cookies', () => {
  const b = browser({ choice: 'granted' });
  const before = b.events().length;
  b.choose('denied');
  b.action('download_click');
  assert.equal(b.events().length, before);
  assert.equal(b.window['ga-disable-G-SYNTHETIC'], true);
  assert.deepEqual([...b.cookies.keys()], ['_ga']);
  assert.equal(JSON.parse(b.storage.get(policy.consentKey)).choice, 'denied');
});

test('DNT and GPC override a previously granted choice', () => {
  for (const preference of [{ dnt: '1' }, { gpc: true }]) {
    const b = browser({ choice: 'granted', ...preference });
    b.action('download_click');
    assert.equal(b.scripts.length, 0);
    assert.equal(b.events().length, 0);
    assert.equal(b.window['ga-disable-G-SYNTHETIC'], true);
  }
});

test('preview and editable demo routes remain unmeasured even with stored consent', () => {
  for (const url of [
    'http://localhost:4321/',
    'https://preview.vercel.app/',
    'https://deepk.geuni.me/examples/demo-input/',
    'https://deepk.geuni.me/?embed=1',
  ]) {
    const b = browser({ choice: 'granted', url });
    b.action('download_click');
    assert.equal(b.scripts.length, 0, url);
    assert.equal(b.events().length, 0, url);
    assert.equal(b.root.hidden, true, url);
  }
});

test('blocked local storage still permits a choice for the current page', () => {
  const b = browser({ noStorage: true });
  assert.equal(b.banner.hidden, false);
  b.choose('granted');
  assert.equal(b.scripts.length, 1);
  b.choose('denied');
  assert.equal(b.window['ga-disable-G-SYNTHETIC'], true);
});

test('another tab revoking consent stops current-page measurement', () => {
  const b = browser({ choice: 'granted' });
  const event = new Event('storage');
  Object.defineProperties(event, {
    key: { value: policy.consentKey },
    newValue: { value: JSON.stringify({ choice: 'denied', at: Date.now() }) },
  });
  b.window.dispatchEvent(event);
  const before = b.events().length;
  b.action('download_click');
  assert.equal(b.events().length, before);
  assert.equal(b.window['ga-disable-G-SYNTHETIC'], true);
});
