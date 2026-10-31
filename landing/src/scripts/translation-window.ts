interface Sample {
  source: string;
  result: string;
}

const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

// Plays prepared samples as if typed into the app window. No text is translated or sent anywhere.
export function mountTranslationWindow(root: HTMLElement) {
  const samples = JSON.parse(root.dataset.samples ?? '[]') as Sample[];
  const source = root.querySelector<HTMLElement>('[data-live-source]');
  const result = root.querySelector<HTMLElement>('[data-live-result]');
  const status = root.querySelector<HTMLElement>('[data-live-status]');
  const copy = root.querySelector<HTMLElement>('[data-live-copy]');
  const parts = root.querySelectorAll<HTMLElement>('[data-window-part]');
  if (!source || !result || !status || !copy || samples.length === 0) return;

  let generation = 0;
  let index = 0;

  const wait = (ms: number, run: number) =>
    new Promise<boolean>((resolve) => setTimeout(() => resolve(run === generation), ms));

  const setCopied = (copied: boolean) => {
    copy.textContent = copied ? (root.dataset.copied ?? '') : (root.dataset.copy ?? '');
    copy.classList.toggle('bg-[#2a2118]', copied);
    copy.classList.toggle('text-white', copied);
    copy.classList.toggle('bg-[#f1eee9]', !copied);
  };

  const play = async (run: number) => {
    root.dataset.animating = '';
    while (run === generation) {
      const sample = samples[index];
      parts.forEach((part) => part.setAttribute('data-hidden', ''));
      setCopied(false);
      status.textContent = '';
      if (!(await wait(320, run))) return;

      source.textContent = '';
      result.textContent = '';
      parts[0].removeAttribute('data-hidden');
      root.dataset.typing = '';
      for (const char of Array.from(sample.source)) {
        source.textContent += char;
        if (!(await wait(32 + Math.random() * 46, run))) return;
      }
      delete root.dataset.typing;

      if (!(await wait(500, run))) return;
      status.textContent = root.dataset.translating ?? '';
      if (!(await wait(900, run))) return;
      status.textContent = '';
      result.textContent = sample.result;
      parts[1].removeAttribute('data-hidden');

      if (!(await wait(1600, run))) return;
      setCopied(true);
      if (!(await wait(1300, run))) return;
      setCopied(false);
      if (!(await wait(1800, run))) return;
      index = (index + 1) % samples.length;
    }
  };

  function start() {
    if (reducedMotion.matches) return;
    generation += 1;
    void play(generation);
  }

  function stop() {
    generation += 1;
    delete root.dataset.typing;
  }

  let visible = false;
  const sync = () => (visible && !document.hidden ? start() : stop());
  new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting === visible) return;
    visible = entry.isIntersecting;
    sync();
  }).observe(root);
  document.addEventListener('visibilitychange', sync);
  reducedMotion.addEventListener('change', () => {
    if (!reducedMotion.matches) return sync();
    stop();
    delete root.dataset.animating;
    const sample = samples[index];
    source.textContent = sample.source;
    result.textContent = sample.result;
    status.textContent = '';
    setCopied(false);
    parts.forEach((part) => part.removeAttribute('data-hidden'));
  });
}
