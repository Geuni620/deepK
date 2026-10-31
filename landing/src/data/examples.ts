import type { DemoState } from './samples';

interface BaseExample {
  slug: string;
  nodeId: string;
  title: string;
  summary: string;
  width: number;
}
export type Example = BaseExample &
  (
    | { kind: 'design'; variant: string }
    | { kind: 'responsive'; variant: 'final' }
    | { kind: 'flow'; initialState: DemoState }
    | { kind: 'guide' }
  );

export const examples: Example[] = [
  {
    slug: 'warm-sand',
    nodeId: 'S7wmDG',
    title: 'Warm Sand',
    summary: '따뜻한 색감과 제품 창을 중심에',
    width: 1440,
    kind: 'design',
    variant: 'warm-sand',
  },
  {
    slug: 'keystroke',
    nodeId: 'fpJiT',
    title: 'Keystroke',
    summary: '두 번의 키 입력을 가장 선명하게',
    width: 1440,
    kind: 'design',
    variant: 'keystroke',
  },
  {
    slug: 'bilingual-editorial',
    nodeId: 'A4Bdm',
    title: 'Bilingual Editorial',
    summary: '원문과 번역을 나란히 읽는 편집형',
    width: 1440,
    kind: 'design',
    variant: 'bilingual-editorial',
  },
  {
    slug: 'in-context-demo',
    nodeId: 'FJV7P',
    title: 'In-Context Demo',
    summary: '문서 안에서 이해하는 개발자 장면',
    width: 1440,
    kind: 'design',
    variant: 'in-context-demo',
  },
  {
    slug: 'bento-features',
    nodeId: 'X3Qzu',
    title: 'Bento Features',
    summary: '기능을 짧고 명확한 카드로',
    width: 1440,
    kind: 'design',
    variant: 'bento-features',
  },
  {
    slug: 'warm-demo',
    nodeId: 'm6SVH',
    title: 'Warm Demo',
    summary: '문서와 번역을 연결하는 따뜻한 체험형',
    width: 1440,
    kind: 'design',
    variant: 'warm-demo',
  },
  {
    slug: 'menu-bar-story',
    nodeId: 'DJTfM',
    title: 'Menu Bar Story',
    summary: '메뉴 막대에서 시작하는 사용 이야기',
    width: 1440,
    kind: 'design',
    variant: 'menu-bar-story',
  },
  {
    slug: 'warm-bento',
    nodeId: 'ybUDM',
    title: 'Warm Bento',
    summary: '친근한 소개와 기능 카드를 함께',
    width: 1440,
    kind: 'design',
    variant: 'warm-bento',
  },
  {
    slug: 'scene-tabs',
    nodeId: 'ZhjQf',
    title: 'Scene Tabs',
    summary: '기술 문서·공고·메일을 오가는 구성',
    width: 1440,
    kind: 'design',
    variant: 'scene-tabs',
  },
  {
    slug: 'playful-bear',
    nodeId: 'LI9te',
    title: 'Playful Bear',
    summary: '쿼카 아이콘과 가벼운 말투가 전면에',
    width: 1440,
    kind: 'design',
    variant: 'playful-bear',
  },
  {
    slug: 'desktop',
    nodeId: 'cw9VP',
    title: '기준안 · Desktop',
    summary: '앞서 확인한 기준 디자인의 넓은 화면',
    width: 1440,
    kind: 'responsive',
    variant: 'final',
  },
  {
    slug: 'tablet',
    nodeId: 'kX1RX',
    title: '기준안 · Tablet',
    summary: '같은 컴포넌트를 768px에서 확인',
    width: 768,
    kind: 'responsive',
    variant: 'final',
  },
  {
    slug: 'mobile',
    nodeId: 'vgY2V',
    title: '기준안 · Mobile',
    summary: '같은 컴포넌트를 390px에서 확인',
    width: 390,
    kind: 'responsive',
    variant: 'final',
  },
  {
    slug: 'demo-start',
    nodeId: 'mNu6p',
    title: '체험 01 · 첫 방문',
    summary: '예시 문서에서 바로 시작하는 상태',
    width: 1280,
    kind: 'flow',
    initialState: 'intro',
  },
  {
    slug: 'demo-selected',
    nodeId: 'qvd1Z',
    title: '체험 02 · 문단 선택',
    summary: '선택한 문장을 번역할 준비가 된 상태',
    width: 1280,
    kind: 'flow',
    initialState: 'selected',
  },
  {
    slug: 'demo-result',
    nodeId: 'h8bwSA',
    title: '체험 03 · 번역 결과',
    summary: '결과를 읽고 원문으로 돌아가는 상태',
    width: 1280,
    kind: 'flow',
    initialState: 'result',
  },
  {
    slug: 'demo-input',
    nodeId: 'K6vGz',
    title: '체험 04 · 직접 입력',
    summary: '자신의 문장을 넣어 보는 입력 상태',
    width: 1280,
    kind: 'flow',
    initialState: 'input',
  },
  {
    slug: 'demo-guide',
    nodeId: 'kiGM2',
    title: '체험 흐름 안내',
    summary: '네 상태의 연결과 동작을 한눈에',
    width: 1280,
    kind: 'guide',
  },
];

export const categories = [
  { id: 'all', label: '전체' },
  { id: 'design', label: '디자인' },
  { id: 'responsive', label: '반응형' },
  { id: 'flow', label: '체험 상태' },
  { id: 'guide', label: '안내' },
] as const;

export function getExample(slug: string): Example | undefined {
  return examples.find((example) => example.slug === slug);
}

export function parseCandidates(value: string | null): string[] {
  try {
    const parsed: unknown = JSON.parse(value ?? '[]');
    if (!Array.isArray(parsed)) return [];
    return [
      ...new Set(
        parsed.filter((slug): slug is string => typeof slug === 'string' && !!getExample(slug)),
      ),
    ];
  } catch {
    return [];
  }
}
