import { samples, exampleTranslation, type DemoState } from '../data/samples';
import { required } from '../lib/dom';

function mountDemo(root: HTMLElement) {
  const sourcePanel = required<HTMLElement>(root, '[data-source-panel]');
  const inputPanel = required<HTMLElement>(root, '[data-input-panel]');
  const resultPanel = required<HTMLElement>(root, '[data-result-panel]');
  const sourceText = required<HTMLElement>(root, '[data-source-text]');
  const sourceTitle = required<HTMLElement>(root, '[data-source-title]');
  const sourceContext = required<HTMLElement>(root, '[data-source-context]');
  const sourceIntro = required<HTMLElement>(root, '[data-source-intro]');
  const sourceOutro = required<HTMLElement>(root, '[data-source-outro]');
  const input = required<HTMLTextAreaElement>(root, '[data-demo-input]');
  const inputCount = required<HTMLElement>(root, '[data-input-count]');
  const feedback = required<HTMLElement>(root, '[data-demo-feedback]');
  const resultSource = required<HTMLElement>(resultPanel, '[data-window-source]');
  const resultText = required<HTMLElement>(resultPanel, '[data-window-result]');
  const copyButton = required<HTMLButtonElement>(resultPanel, '[data-copy-result]');
  let sample = root.dataset.initialState === 'input' ? samples[2] : samples[0];
  let state = (root.dataset.initialState ?? 'intro') as DemoState;
  let mode: 'sample' | 'input' = state === 'input' ? 'input' : 'sample';
  let selected = sample.source;
  let lastCopy = 0;

  function show(next: DemoState) {
    state = next;
    root.dataset.state = next;
    sourcePanel.hidden = mode === 'input';
    inputPanel.hidden = mode !== 'input';
    resultPanel.hidden = next !== 'result';
    sourceText.classList.toggle('bg-[#ffe574]', next !== 'intro');
  }

  function translate() {
    const text = mode === 'input' ? input.value : selected;
    const result = exampleTranslation(text);
    if (!result) {
      show(mode === 'input' ? 'input' : 'selected');
      feedback.textContent =
        '이 화면은 예시 문장의 결과만 제공합니다. 예시 탭에서 문단을 선택해 보세요.';
      return;
    }
    resultSource.textContent = text;
    resultText.textContent = result;
    copyButton.dataset.copyResult = result;
    copyButton.textContent = '복사';
    show('result');
    feedback.textContent = '준비된 예시 번역입니다. 결과를 닫으면 원문을 이어 읽을 수 있습니다.';
  }

  root.addEventListener('click', (event) => {
    if (!(event.target instanceof Element)) return;
    const tab = event.target.closest<HTMLButtonElement>('[data-sample]');
    if (tab) {
      const nextSample = samples.find((item) => item.id === tab.dataset.sample);
      if (!nextSample) return;
      sample = nextSample;
      mode = 'sample';
      lastCopy = 0;
      selected = sample.source;
      sourceText.textContent = sample.source;
      sourceTitle.textContent = sample.title;
      sourceContext.textContent = sample.context;
      sourceIntro.textContent = sample.intro;
      sourceOutro.textContent = sample.outro;
      root
        .querySelectorAll<HTMLButtonElement>('[data-sample], [data-input-tab]')
        .forEach((button) => button.setAttribute('aria-pressed', String(button === tab)));
      show('intro');
      feedback.textContent = '예시 문단을 고른 뒤 번역 결과를 확인하세요.';
    }
    if (event.target.closest('[data-input-tab]')) {
      mode = 'input';
      lastCopy = 0;
      root
        .querySelectorAll<HTMLButtonElement>('[data-sample], [data-input-tab]')
        .forEach((button) =>
          button.setAttribute('aria-pressed', String(button.hasAttribute('data-input-tab'))),
        );
      show('input');
      input.focus();
    }
    if (event.target.closest('[data-select-paragraph]')) {
      selected = sample.source;
      show('selected');
      feedback.textContent = '문단을 선택했습니다. 예시 번역 보기를 누르세요.';
    }
    if (event.target.closest('[data-translate-example]')) translate();
    if (event.target.closest('[data-close-result]')) show(mode === 'input' ? 'input' : 'selected');
  });

  sourceText.addEventListener('mouseup', () => {
    const selection = window.getSelection();
    if (
      selection?.rangeCount &&
      sourceText.contains(selection.getRangeAt(0).commonAncestorContainer) &&
      selection.toString().trim()
    ) {
      selected = selection.toString();
      show('selected');
    }
  });
  input.addEventListener('input', () => {
    inputCount.textContent = `${input.value.length}/500`;
    lastCopy = 0;
    show('input');
    feedback.textContent = '예시 문장의 결과만 제공합니다. 새 문장은 API 연결 후 지원합니다.';
  });
  document.addEventListener('keydown', (event) => {
    if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== 'c') return;
    const selection = window.getSelection();
    const selectedHere =
      selection?.rangeCount && sourceText.contains(selection.getRangeAt(0).commonAncestorContainer);
    if (!selectedHere && !root.contains(document.activeElement)) return;
    const now = performance.now();
    if (lastCopy && now - lastCopy < 450) translate();
    lastCopy = now;
  });
  show(state);
}

document.querySelectorAll<HTMLElement>('[data-translation-demo]').forEach(mountDemo);
