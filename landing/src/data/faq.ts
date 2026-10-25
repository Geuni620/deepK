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
      '앱에는 짧은 메모리 캐시가 있습니다. 제공자 정책과 Codex 전역 지침 전송은 별도로 확인해야 합니다.',
  },
  {
    id: 'availability',
    question: '지금 다운로드할 수 있나요?',
    answer:
      '공개 설치 파일은 아직 준비 중입니다. 현재 페이지는 디자인과 예시 흐름을 확인하는 미리보기입니다.',
  },
] as const;
