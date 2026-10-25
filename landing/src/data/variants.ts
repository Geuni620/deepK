export type HeroKind =
  'warm' | 'keyboard' | 'editorial' | 'workspace' | 'bento' | 'menubar' | 'scenes' | 'playful';
export type SectionKind =
  | 'how'
  | 'features'
  | 'subscription'
  | 'faq'
  | 'code'
  | 'comparison'
  | 'story'
  | 'settings'
  | 'privacy'
  | 'principles'
  | 'promises';
export type Theme = 'warm' | 'dark' | 'editorial' | 'white' | 'cool' | 'playful';

export interface Variant {
  id: string;
  name: string;
  hero: HeroKind;
  theme: Theme;
  headline: string[];
  description: string;
  sections: SectionKind[];
}

const defaultDescription = '문장을 고르고 ⌘C를 두 번. 작은 번역 창에서 읽고, 하던 일로 돌아가세요.';
export const selectedVariantId = 'playful-bear';

export const variants = [
  {
    id: 'warm-sand',
    name: 'Warm Sand',
    hero: 'warm',
    theme: 'warm',
    headline: ['읽던 자리에서,', '그대로 이해하세요.'],
    description: defaultDescription,
    sections: ['how', 'subscription'],
  },
  {
    id: 'keystroke',
    name: 'Keystroke',
    hero: 'keyboard',
    theme: 'dark',
    headline: ['두 번 누르면, 번역입니다.'],
    description:
      '선택하고 ⌘C ⌘C. 메뉴 막대에 상주하는 deepK가 번역을 붙여 주고, 원래 읽던 화면은 떠나지 않게 합니다.',
    sections: ['how', 'code'],
  },
  {
    id: 'bilingual-editorial',
    name: 'Bilingual Editorial',
    hero: 'editorial',
    theme: 'editorial',
    headline: ['원문은 그대로 두고,', '이해만 곁에 놓습니다.'],
    description:
      '읽다 막힌 문장을 고르고 복사를 한 번 더. 작은 창에 번역이 나란히 놓이고, 문맥의 끝을 잃지 않습니다.',
    sections: ['principles'],
  },
  {
    id: 'in-context-demo',
    name: 'In-Context Demo',
    hero: 'workspace',
    theme: 'white',
    headline: ['DeepL 탭을 찾는 대신, ⌘C ⌘C.'],
    description: '기술 문서와 README를 읽던 그 자리에서. 코드는 남겨 두고 문장을 이해하세요.',
    sections: ['features'],
  },
  {
    id: 'bento-features',
    name: 'Bento Features',
    hero: 'bento',
    theme: 'cool',
    headline: ['번역에 필요한 것만,', 'Mac 메뉴 막대에.'],
    description: defaultDescription,
    sections: ['features'],
  },
  {
    id: 'warm-demo',
    name: 'Warm Demo',
    hero: 'workspace',
    theme: 'warm',
    headline: ['읽던 페이지를', '떠나지 마세요.'],
    description: '번역 탭을 열고, 붙여넣고, 다시 돌아오는 일. 두 번의 키로 줄여 보세요.',
    sections: ['comparison', 'features'],
  },
  {
    id: 'menu-bar-story',
    name: 'Menu Bar Story',
    hero: 'menubar',
    theme: 'white',
    headline: ['메뉴 막대에 한 칸.', '번역은 거기서 끝납니다.'],
    description: '창을 띄워 둘 필요 없이 조용히 기다리다가, ⌘C를 두 번 누르면 나타납니다.',
    sections: ['story', 'settings'],
  },
  {
    id: 'warm-bento',
    name: 'Warm Bento',
    hero: 'warm',
    theme: 'warm',
    headline: ['한 번 복사는 복사,', '두 번 복사는 번역.'],
    description: '읽던 화면 위, 작은 창 하나. 번역이 끝나면 그대로 이어 가세요.',
    sections: ['features', 'faq'],
  },
  {
    id: 'scene-tabs',
    name: 'Scene Tabs',
    hero: 'scenes',
    theme: 'cool',
    headline: ['영어 문서 앞에서', '멈추지 않게.'],
    description: '기술 문서, 채용 공고, 메일. 읽고 쓰는 장면마다 필요한 번역만 곁에 둡니다.',
    sections: ['privacy'],
  },
  {
    id: 'playful-bear',
    name: 'Playful Bear',
    hero: 'playful',
    theme: 'playful',
    headline: ['모르는 문장? ⌘C ⌘C 하면', '곰이 읽어 줘요.'],
    description: '영어든 한국어든, 고른 문장만 작은 창에 번역해 주는 Mac 메뉴 막대 친구.',
    sections: ['promises', 'how', 'faq'],
  },
  {
    id: 'final',
    name: '기준 시안',
    hero: 'warm',
    theme: 'warm',
    headline: ['읽던 자리에서,', '그대로 이해하세요.'],
    description: defaultDescription,
    sections: ['how', 'features', 'subscription', 'faq'],
  },
] satisfies Variant[];

export function getVariant(id: string): Variant {
  const variant = variants.find((candidate) => candidate.id === id);
  if (!variant) throw new Error(`Unknown landing variant: ${id}`);
  return variant;
}
