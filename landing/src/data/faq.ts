export const faqItems = [
  {
    id: 'permissions',
    question: '어떤 권한이 필요한가요?',
    answer:
      '두 번 복사 감지에는 입력 모니터링, 원래 위치에 삽입하려면 손쉬운 사용 권한이 필요합니다.',
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
      '번역 결과는 메모리에 최대 32개·5분간 보관하고 앱을 재시작하면 비워집니다. 원문은 선택한 AI 제공자에게 전송됩니다. Codex는 전역 지침이 있으면 함께 전송할 수 있습니다. 자세한 내용은 개인정보 안내에서 확인하세요.',
  },
  {
    id: 'availability',
    question: '지금 다운로드할 수 있나요?',
    answer:
      '네. Homebrew 또는 공증된 ZIP으로 0.1.0을 설치할 수 있습니다. Apple Silicon과 macOS 15 이상을 지원하는 초기 배포본입니다. Intel Mac용 파일은 아직 제공하지 않습니다.',
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
      'Homebrew로 설치했다면 앱을 종료한 뒤 brew update와 brew upgrade --cask Geuni620/tap/deepk를 실행하세요. ZIP으로 설치했다면 새 파일의 앱으로 교체하면 됩니다.',
  },
] as const;
