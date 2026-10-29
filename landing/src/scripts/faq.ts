import { required } from '../lib/dom';

const motion = { duration: 220, easing: 'cubic-bezier(0.23, 1, 0.32, 1)', fill: 'both' } as const;

function mountFaq(item: HTMLDetailsElement): () => void {
  const trigger = required<HTMLElement>(item, '[data-faq-trigger]');
  const content = required<HTMLElement>(item, '.faq-answer');
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  let expanded = item.open;
  let animations: Animation[] = [];
  let targetHeight = 0;

  function cancelAnimations() {
    for (const animation of animations) {
      animation.onfinish = null;
      animation.cancel();
    }
    animations = [];
  }

  function settle() {
    item.open = expanded;
    item.style.height = '';
    item.style.overflow = '';
    cancelAnimations();
    trigger.removeAttribute('aria-expanded');
    content.removeAttribute('aria-hidden');
    content.inert = false;
  }

  function measureTarget() {
    const style = getComputedStyle(item);
    const borders = parseFloat(style.borderTopWidth) + parseFloat(style.borderBottomWidth);
    return (
      trigger.getBoundingClientRect().height +
      (expanded ? content.getBoundingClientRect().height : 0) +
      borders
    );
  }

  function setExpanded(next: boolean, pointer: boolean) {
    const height = item.getBoundingClientRect().height;
    const opacity = item.open ? Number(getComputedStyle(content).opacity) : 0;
    expanded = next;
    const animate = pointer && !reducedMotion.matches && typeof item.animate === 'function';
    item.dataset.faqMotion = animate ? 'animated' : 'instant';
    item.dataset.faqExpanded = String(next);
    if (!animate) {
      settle();
      return;
    }

    // Freeze the current frame before cancelling an interrupted transition.
    item.style.height = `${height}px`;
    cancelAnimations();
    // Keep native content rendered during collapse; settle restores its native state.
    item.open = true;
    item.style.overflow = 'hidden';
    trigger.setAttribute('aria-expanded', String(next));
    content.setAttribute('aria-hidden', String(!next));
    content.inert = !next;
    if (!next && content.contains(document.activeElement)) trigger.focus({ preventScroll: true });
    targetHeight = measureTarget();
    const heightAnimation = item.animate(
      [{ height: `${height}px` }, { height: `${targetHeight}px` }],
      motion,
    );
    const fade = content.animate([{ opacity }, { opacity: next ? 1 : 0 }], motion);
    animations = [heightAnimation, fade];
    heightAnimation.onfinish = settle;
  }

  const onClick = (event: MouseEvent) => {
    event.preventDefault();
    // Keyboard and assistive-technology clicks have no pointer click count.
    setExpanded(!expanded, event.detail > 0);
  };
  const onToggle = () => {
    if (!animations.length) {
      expanded = item.open;
      item.dataset.faqExpanded = String(expanded);
    }
  };
  const onMotionChange = () => {
    if (reducedMotion.matches) {
      item.dataset.faqMotion = 'instant';
      settle();
    }
  };
  const resize = new ResizeObserver(() => {
    if (animations.length && Math.abs(measureTarget() - targetHeight) > 0.5)
      setExpanded(expanded, true);
  });
  resize.observe(trigger);
  resize.observe(content);
  trigger.addEventListener('click', onClick);
  item.addEventListener('toggle', onToggle);
  reducedMotion.addEventListener('change', onMotionChange);
  return () => {
    settle();
    resize.disconnect();
    trigger.removeEventListener('click', onClick);
    item.removeEventListener('toggle', onToggle);
    reducedMotion.removeEventListener('change', onMotionChange);
  };
}

const cleanup = [...document.querySelectorAll<HTMLDetailsElement>('[data-faq] details')].map(
  mountFaq,
);
import.meta.hot?.dispose(() => cleanup.forEach((remove) => remove()));
