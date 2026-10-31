import type { Messages } from './index';

export const en: Messages = {
  htmlLang: 'en',
  ogLocale: 'en_US',
  languageName: 'English',
  meta: {
    homeTitle: 'Mac translation with a double copy',
    homeDescription:
      'Select a sentence and press ⌘C twice. deepK is a Mac menu bar app that translates between Korean and English with the AI subscription you already have. Install it with Homebrew or a notarized ZIP.',
  },
  layout: {
    skipLink: 'Skip to content',
    footerNav: 'More information',
    backToMain: '← Back to home',
    switchLanguage: 'Language',
  },
  nav: {
    label: 'Page navigation',
    brand: 'deepK home',
    how: 'How it works',
    subscription: 'Your subscription',
    faq: 'FAQ',
    getMac: 'Get for Mac',
  },
  hero: {
    badge: '⌘ macOS menu bar translator',
    headline: ['Stuck on a sentence?', 'Press ⌘C ⌘C and the quokka reads it.'],
    description:
      'Korean or English, a little Mac menu bar friend that translates just the sentence you picked in a small window.',
    cta: 'Get deepK for Mac',
    requirement: (macOS: string, version: string) =>
      `Apple Silicon · macOS ${macOS} or later · v${version}`,
    iconAlt: 'deepK quokka icon',
    cards: [
      { source: '원래 창은 열어 두세요.', result: 'Keep the original window open.' },
      { source: '출시일을 확인해 주실 수 있나요?', result: 'Could you confirm the launch date?' },
    ],
  },
  promises: {
    title: 'Three promises from the quokka',
    items: [
      ['⌘', 'The subscription you have', 'Uses your Codex or Claude Code subscription login.'],
      ['↗', 'Only the translation you need', 'Check it in a small window and keep reading.'],
      [
        '↩',
        'Back where you were',
        'When you are done, you return to your work. Inserting text is always your call.',
      ],
    ],
  },
  how: {
    eyebrow: '/ how it works',
    title: 'No more switching windows.',
    steps: [
      { n: '01', title: 'Select', copy: 'Pick the sentence that stopped you.' },
      { n: '02', title: '⌘C, then once more', copy: 'Copy as usual, then press it again.' },
      {
        n: '03',
        title: 'Keep reading',
        copy: 'Read it in a small window and go back to your document.',
      },
    ],
  },
  app: {
    eyebrow: 'A small window, an unbroken thought',
    title: ['A quick translation,', 'and you carry on.'],
    body: 'Check the sentence you were reading in a small window. Copy the translation, or choose to insert it where you were typing.',
    guideLink: 'Setup guide for first-time users',
    caption: 'An illustration recreating the translation window of the Mac app.',
    window: {
      label:
        'Example of the deepK translation window: Korean text is entered and the English translation appears below.',
      direction: 'Auto · 한국어 ↔ English',
      translating: 'Translating…',
      copy: 'Copy',
      copied: 'Copied',
    },
    samples: [
      {
        source: '원래 창은 그대로 열어 두세요.',
        result: 'Please keep the original window open.',
      },
      {
        source: '금요일까지 출시일을 확인해 주실 수 있나요?',
        result: 'Could you confirm the launch date by Friday?',
      },
      {
        source: '회의록은 오늘 저녁에 공유드릴게요.',
        result: "I'll share the meeting notes this evening.",
      },
    ],
  },
  subscription: {
    eyebrow: '/ your subscription, your choice',
    title: ['The subscription you have,', 'only the translation you need.'],
    body: 'deepK uses the account you signed in to with Codex CLI or Claude Code. You choose the provider and model, and it never falls back to another paid API.',
    login: 'Your own login',
    note: 'Subscription terms and provider usage limits still apply.',
  },
  install: {
    badge: (version: string) => `v${version} · Early release`,
    title: ['Bring the quokka', 'to your Mac.'],
    requirement: (macOS: string) => `Apple Silicon · macOS ${macOS} or later`,
    notarized: 'Signed with Developer ID and notarized by Apple.',
  },
  installOptions: {
    brew: 'Install with Homebrew',
    copy: 'Copy',
    copied: 'Copied',
    copyLabel: 'Copy Homebrew install command',
    copySuccess: 'Paste it into Terminal and run it.',
    copyFailure: 'Please select the command and copy it yourself.',
    or: 'or',
    zip: 'Download the Mac app ZIP',
    cliNote:
      'Translation requires Codex CLI or Claude Code, installed and signed in to a subscription.',
    guideLink: 'New to CLI login or permissions? ↗',
  },
  installDialog: {
    badge: (version: string) => `deepK ${version} · Early release`,
    close: 'Close install information',
    title: 'Install deepK on your Mac',
    body: 'Install it the way you like, then connect the AI account you already use.',
  },
  faq: {
    playfulTitle: 'Got questions?',
    plainTitle: 'Frequently asked questions',
  },
  footer: {
    guide: 'Setup guide',
    privacy: 'Privacy',
    notes: 'Release notes ↗',
    issues: 'Report an issue ↗',
  },
};
