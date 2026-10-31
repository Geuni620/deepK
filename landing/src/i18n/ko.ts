export const ko = {
  htmlLang: 'ko',
  ogLocale: 'ko_KR',
  languageName: '한국어',
  meta: {
    homeTitle: '복사 두 번으로 이어가는 Mac 번역',
    homeDescription:
      '읽던 문장을 선택하고 ⌘C를 두 번. deepK는 기존 AI 구독으로 한국어와 영어를 번역하는 Mac 메뉴 막대 앱입니다. Homebrew 또는 공증된 ZIP으로 설치하세요.',
  },
  layout: {
    skipLink: '본문으로 바로가기',
    footerNav: '추가 안내',
    backToMain: '← 메인으로',
    switchLanguage: '언어 선택',
  },
  nav: {
    label: '페이지 탐색',
    brand: 'deepK 처음으로',
    how: '사용법',
    subscription: '쓰던 구독으로',
    faq: '궁금한 점',
    getMac: 'Mac용 받기',
  },
  hero: {
    badge: '⌘ macOS 메뉴 막대 번역기',
    headline: ['모르는 문장? ⌘C ⌘C 하면', '쿼카가 읽어 줘요.'],
    description: '영어든 한국어든, 고른 문장만 작은 창에 번역해 주는 Mac 메뉴 막대 친구.',
    cta: 'Mac용 deepK 받기',
    requirement: (macOS: string, version: string) =>
      `Apple Silicon · macOS ${macOS} 이상 · v${version}`,
    iconAlt: 'deepK 쿼카 아이콘',
    cards: [
      { source: 'Keep the original window open.', result: '원래 창은 열어 두세요.' },
      { source: 'Could you confirm the launch date?', result: '출시일을 확인해 주실 수 있나요?' },
    ],
  },
  promises: {
    title: '쿼카가 지키는 세 가지 약속',
    items: [
      ['⌘', '쓰던 구독 그대로', 'Codex 또는 Claude Code의 구독 로그인을 사용해요.'],
      ['↗', '필요한 번역만 곁에', '작은 창에서 확인하고 원문을 이어 읽어요.'],
      ['↩', '제자리로 돌려 줘요', '다 읽으면 원래 작업으로 돌아가고, 삽입은 직접 선택해요.'],
    ],
  },
  how: {
    eyebrow: '/ how it works',
    title: '창을 오가지 않아도 됩니다.',
    steps: [
      { n: '01', title: '선택', copy: '읽다가 막힌 문장을 고릅니다.' },
      { n: '02', title: '⌘C, 그리고 한 번 더', copy: '평소처럼 복사하고, 한 번 더 누릅니다.' },
      { n: '03', title: '읽기 계속', copy: '작은 창에서 읽고 원래 문서로 돌아갑니다.' },
    ],
  },
  app: {
    eyebrow: '작은 창, 이어지는 생각',
    title: ['번역은 잠깐,', '하던 일은 그대로.'],
    body: '읽던 문장을 작은 창에서 확인하세요. 번역문을 복사하거나, 직접 선택해 원래 입력 위치에 넣을 수 있어요.',
    guideLink: '처음 설치하는 분을 위한 안내',
    caption: 'Mac 앱의 번역 창을 재현한 예시 화면입니다.',
    window: {
      label: 'deepK 번역 창 예시: 영어 원문이 입력되면 아래에 한국어 번역이 나타납니다.',
      direction: '자동 · 한국어 ↔ English',
      translating: '번역 중…',
      copy: '복사',
      copied: '복사됨',
    },
    samples: [
      {
        source: 'Please keep the original window open.',
        result: '원래 창을 열어 둔 채로 유지해 주세요.',
      },
      {
        source: 'Could you confirm the launch date by Friday?',
        result: '금요일까지 출시일을 확인해 주실 수 있나요?',
      },
      {
        source: 'Returns a Promise that resolves when idle.',
        result: '유휴 상태가 되면 이행되는 Promise를 반환합니다.',
      },
    ],
  },
  subscription: {
    eyebrow: '/ your subscription, your choice',
    title: ['쓰던 구독 그대로,', '필요한 번역만.'],
    body: 'Codex CLI 또는 Claude Code에 로그인한 계정을 사용합니다. 제공자와 모델은 직접 선택하고, 다른 유료 API로 자동 전환하지 않습니다.',
    login: '직접 로그인',
    note: '구독과 제공자의 사용량 제한은 별도로 적용됩니다.',
  },
  install: {
    badge: (version: string) => `v${version} · 초기 배포`,
    title: ['쿼카를 Mac으로', '데려오세요.'],
    requirement: (macOS: string) => `Apple Silicon · macOS ${macOS} 이상`,
    notarized: 'Developer ID 서명과 Apple 공증을 거친 앱입니다.',
  },
  installOptions: {
    brew: 'Homebrew로 설치',
    copy: '복사',
    copied: '복사됨',
    copyLabel: 'Homebrew 설치 명령 복사',
    copySuccess: '터미널에 붙여넣어 실행하세요.',
    copyFailure: '명령어를 직접 선택해 복사해 주세요.',
    or: '또는',
    zip: 'Mac 앱 ZIP 다운로드',
    cliNote: '번역용 Codex CLI 또는 Claude Code의 설치·구독 로그인이 필요해요.',
    guideLink: 'CLI 로그인과 권한 설정이 처음이라면 ↗',
  },
  installDialog: {
    badge: (version: string) => `deepK ${version} · 초기 배포`,
    close: '설치 안내 닫기',
    title: 'Mac에 deepK 설치하기',
    body: '편한 방법으로 설치하고, 쓰던 AI 계정을 연결하세요.',
  },
  faq: {
    playfulTitle: '궁금한 거 있어요?',
    plainTitle: '자주 묻는 질문',
  },
  footer: {
    guide: '설치 안내',
    privacy: '개인정보 안내',
    notes: '릴리스 노트 ↗',
    issues: '문제 제보 ↗',
  },
};
