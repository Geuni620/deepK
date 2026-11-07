import type { Locale } from '../i18n';
import { release } from './release';

export interface FaqItem {
  id: string;
  question: string;
  answer: string;
}

const ko: FaqItem[] = [
  {
    id: 'permissions',
    question: '어떤 권한이 필요한가요?',
    answer:
      '두 번 복사 감지에는 입력 모니터링, 원래 위치에 삽입하려면 손쉬운 사용 권한이 필요합니다. 화면에서 직접 영역을 가져올 때만 화면 기록 권한을 추가로 사용합니다.',
  },
  {
    id: 'screen-recording',
    question: '번역 앱에 왜 화면 기록 권한이 필요한가요?',
    answer:
      '복사할 수 없는 이미지나 게임 속 글자를 읽기 위해, 사용자가 직접 고른 사각형을 한 번 캡처합니다. 동영상을 녹화하거나 화면을 계속 감시하지 않습니다. 글자 인식(OCR)은 Mac에서 처리하고 인식한 글자만 선택한 AI 제공자에게 보냅니다. 일반 텍스트·클립보드 이미지 번역에는 이 권한이 필요하지 않습니다.',
  },
  {
    id: 'provider',
    question: '어디서 번역하나요?',
    answer:
      '사용자가 로그인한 Codex CLI 또는 Claude Code를 통해 선택한 제공자에게 원문을 보냅니다.',
  },
  {
    id: 'privacy',
    question: '입력한 내용이 남나요?',
    answer:
      'deepK 운영자는 원문·이미지·인식한 글자·번역문을 수집하지 않습니다. 일반 텍스트 번역 캐시는 메모리에 최대 32개·5분간 유지하고, 이미지와 결과는 현재 창에서 처리하는 동안 메모리에 둡니다. 번역할 글자는 선택한 AI 제공자에게 전송되며 제공자의 보관 정책은 별도로 적용됩니다. 자세한 내용은 개인정보 안내에서 확인하세요.',
  },
  {
    id: 'availability',
    question: '지금 다운로드할 수 있나요?',
    answer: `네. Homebrew 또는 공증된 ZIP으로 ${release.version}을 설치할 수 있습니다. Apple Silicon과 macOS ${release.minimumMacOS} 이상을 지원합니다. Intel Mac용 파일은 아직 제공하지 않습니다.`,
  },
  {
    id: 'subscription',
    question: '앱을 설치하면 바로 번역할 수 있나요?',
    answer:
      'Codex CLI 또는 Claude Code를 별도로 설치하고, 사용할 Mac에서 구독 계정으로 로그인해야 합니다. deepK 설정에서 제공자를 선택하고 연결을 확인하세요. 제공자의 구독 조건과 사용량 제한은 별도로 적용됩니다.',
  },
  {
    id: 'update',
    question: '다음 버전은 어떻게 업데이트하나요?',
    answer:
      'Homebrew로 설치했다면 앱을 종료한 뒤 brew update와 brew upgrade --cask Geuni620/tap/deepk를 실행하세요. ZIP으로 설치했다면 새 파일의 deepK.app으로 교체하세요. 이전 이름의 DeepK.app은 함께 실행하지 말고 삭제하세요.',
  },
];

const en: FaqItem[] = [
  {
    id: 'permissions',
    question: 'Which permissions does it need?',
    answer:
      'Input Monitoring to detect the double copy, and Accessibility to insert text back where you were typing. Screen Recording is only needed when you capture a region directly from the screen.',
  },
  {
    id: 'screen-recording',
    question: 'Why does a translation app need Screen Recording?',
    answer:
      'To read text in images or games that cannot be copied, deepK takes one screenshot of the rectangle you explicitly select. It does not record video or continuously monitor your screen. OCR runs on your Mac; only the recognized text goes to your chosen AI provider. Ordinary text and clipboard-image translation do not need this permission.',
  },
  {
    id: 'provider',
    question: 'Where does the translation happen?',
    answer:
      'deepK sends the text to the provider you chose, through the Codex CLI or Claude Code you are signed in to.',
  },
  {
    id: 'privacy',
    question: 'Does it keep what I translate?',
    answer:
      'The deepK operator does not collect source text, images, recognized text, or translations. The ordinary text cache holds up to 32 results for 5 minutes in memory; images and their results stay in memory while the current window processes them. Text goes to your chosen AI provider, whose retention policy applies separately. See the privacy page for details.',
  },
  {
    id: 'availability',
    question: 'Can I download it now?',
    answer: `Yes. You can install ${release.version} with Homebrew or a notarized ZIP. It supports Apple Silicon and macOS ${release.minimumMacOS} or later. There is no Intel Mac build yet.`,
  },
  {
    id: 'subscription',
    question: 'Can I translate right after installing?',
    answer:
      'You also need to install Codex CLI or Claude Code and sign in with your subscription on that Mac. Then choose a provider in deepK settings and check the connection. The provider subscription terms and usage limits still apply.',
  },
  {
    id: 'update',
    question: 'How do I update to the next version?',
    answer:
      'If you installed with Homebrew, quit the app and run brew update, then brew upgrade --cask Geuni620/tap/deepk. If you used the ZIP, replace it with deepK.app from the new file. Do not run the older DeepK.app alongside it; delete it.',
  },
];

export const faqItemsByLocale: Record<Locale, FaqItem[]> = { ko, en };
export const faqItems = ko;
