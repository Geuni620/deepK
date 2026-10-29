export type DemoState = 'intro' | 'selected' | 'result' | 'input';
export interface Sample {
  id: string;
  label: string;
  context: string;
  title: string;
  intro: string;
  outro: string;
  source: string;
  result: string;
}

export const samples: Sample[] = [
  {
    id: 'career',
    label: '채용 공고',
    context: 'NORTHSTAR / CAREERS',
    title: 'Product Engineer',
    intro: 'At Northstar, we build tools that help people focus on their work.',
    outro: 'Join us in making everyday work feel a little more natural.',
    source:
      "We're looking for an engineer who cares deeply about the craft of building tools people love.",
    result: '사람들이 사랑하는 도구를 만드는 일에 깊이 마음을 쓰는 엔지니어를 찾고 있습니다.',
  },
  {
    id: 'docs',
    label: '기술 문서',
    context: 'DOCUMENTATION / JAVASCRIPT',
    title: 'Cancelling tasks',
    intro: 'Cancellation gives callers a way to stop work they no longer need.',
    outro: 'Keep cleanup close to the operation that owns the resource.',
    source: 'Returns a Promise that resolves when idle.',
    result: '유휴 상태가 되면 이행되는 Promise를 반환합니다.',
  },
  {
    id: 'mail',
    label: '메일',
    context: 'WORK / EMAIL',
    title: 'A quick check-in',
    intro: 'Hi team,',
    outro: 'Thanks for keeping everything on track.',
    source:
      "Could you share the updated timeline?\nI'd like to confirm the launch date with our team.",
    result: '업데이트된 일정을 공유해 주실 수 있나요?\n팀과 출시일을 확인하고 싶습니다.',
  },
];

export function exampleTranslation(input: string): string | undefined {
  const normalized = input.trim().replace(/\s+/g, ' ');
  return samples.find((sample) => sample.source.replace(/\s+/g, ' ') === normalized)?.result;
}
