import { examples, getExample, parseCandidates, type Example } from '../data/examples';
import { required } from '../lib/dom';

const storageKey = 'deepk:landing:candidates:v1';
const dialog = required<HTMLDialogElement>(document, '#preview-dialog');
const stage = required<HTMLElement>(dialog, '#preview-stage');
const canvas = required<HTMLElement>(dialog, '#preview-canvas');
const frame = required<HTMLIFrameElement>(dialog, '#live-frame');
const reference = required<HTMLImageElement>(dialog, '#reference-frame');
const zoom = required<HTMLSelectElement>(dialog, '#preview-zoom');
const candidateButton = required<HTMLButtonElement>(dialog, '#preview-candidate');
const cards = [...document.querySelectorAll<HTMLElement>('[data-example-card]')];
const checks = [...document.querySelectorAll<HTMLInputElement>('[data-candidate]')];
let active: Example | undefined;
let mode: 'live' | 'reference' = 'live';
let filter = 'all';
let candidates: string[] = [];
try {
  candidates = parseCandidates(localStorage.getItem(storageKey));
} catch {
  /* Keep choices in memory when storage is unavailable. */
}

function renderFilter() {
  let count = 0;
  for (const card of cards) {
    card.hidden =
      filter === 'selected'
        ? !candidates.includes(card.dataset.slug!)
        : filter !== 'all' && card.dataset.kind !== filter;
    if (!card.hidden) count++;
  }
  required(document, '#visible-count').textContent = `${count} EXAMPLES`;
  required<HTMLElement>(document, '#empty-state').hidden = count !== 0;
  document
    .querySelectorAll<HTMLElement>('[data-filter]')
    .forEach((button) =>
      button.setAttribute('aria-pressed', String(button.dataset.filter === filter)),
    );
}

function renderSelection() {
  for (const checkbox of checks) {
    checkbox.checked = candidates.includes(checkbox.dataset.candidate!);
    required(checkbox.parentElement!, '[data-candidate-label]').textContent = checkbox.checked
      ? '선택됨'
      : '후보 선택';
  }
  required<HTMLElement>(document, '#selection-tray').hidden = candidates.length === 0;
  required(document, '#selection-count').textContent = String(candidates.length);
  const pills = candidates.map((slug) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.removeCandidate = slug;
    button.className = 'rounded-full border border-line px-3 py-1 text-xs';
    button.textContent = `${getExample(slug)!.title} ×`;
    button.setAttribute('aria-label', `${getExample(slug)!.title} 후보에서 제거`);
    return button;
  });
  required(document, '#selection-list').replaceChildren(...pills);
  if (active)
    candidateButton.textContent = candidates.includes(active.slug)
      ? '후보에서 제외'
      : '후보로 저장';
  document.documentElement.dataset.candidates = JSON.stringify(candidates);
  renderFilter();
}

function saveSelection() {
  try {
    localStorage.setItem(storageKey, JSON.stringify(candidates));
  } catch {
    /* The current page still retains the choices. */
  }
  renderSelection();
}

function toggleCandidate(slug: string) {
  if (!getExample(slug)) return;
  candidates = candidates.includes(slug)
    ? candidates.filter((item) => item !== slug)
    : [...candidates, slug];
  saveSelection();
}

function resizePreview() {
  if (!active || !dialog.open) return;
  const available = Math.max(120, stage.clientWidth - 48);
  const scale = zoom.value === 'fit' ? Math.min(1, available / active.width) : Number(zoom.value);
  canvas.style.width = `${active.width * scale}px`;
  frame.style.width = `${active.width}px`;
  frame.style.transform = `scale(${scale})`;
  reference.style.width = `${active.width}px`;
  reference.style.transform = `scale(${scale})`;
  if (mode === 'live') {
    const height = Math.max(260, stage.clientHeight - 48);
    frame.style.height = `${Math.round(height / scale)}px`;
    canvas.style.height = `${height}px`;
  } else {
    const ratio = reference.naturalWidth ? reference.naturalHeight / reference.naturalWidth : 1;
    canvas.style.height = `${active.width * ratio * scale}px`;
  }
}

function setMode(next: 'live' | 'reference') {
  mode = next;
  frame.hidden = mode !== 'live';
  reference.hidden = mode !== 'reference';
  dialog
    .querySelectorAll<HTMLElement>('[data-preview-mode]')
    .forEach((button) =>
      button.setAttribute('aria-pressed', String(button.dataset.previewMode === mode)),
    );
  stage.scrollTop = 0;
  stage.scrollLeft = 0;
  resizePreview();
}

function openPreview(slug: string) {
  const example = getExample(slug);
  if (!example) return;
  active = example;
  required(dialog, '#preview-title').textContent = example.title;
  required(dialog, '#preview-category').textContent =
    `${String(examples.indexOf(example) + 1).padStart(2, '0')} / 18 · ${example.width}px`;
  required(dialog, '#preview-description').textContent = example.summary;
  required<HTMLAnchorElement>(dialog, '#open-standalone').href = `/examples/${example.slug}/`;
  frame.src = `/examples/${example.slug}/?embed=1`;
  reference.src = `/thumbnails/${example.nodeId}.webp`;
  reference.alt = `${example.title} 원본 디자인`;
  if (!dialog.open) dialog.showModal();
  setMode('live');
  renderSelection();
  const url = new URL(location.href);
  url.searchParams.set('case', slug);
  history.replaceState(null, '', url);
}

function movePreview(delta: number) {
  if (!active) return;
  const index = (examples.indexOf(active) + delta + examples.length) % examples.length;
  openPreview(examples[index].slug);
}

document.addEventListener('click', (event) => {
  if (!(event.target instanceof Element)) return;
  const target = event.target;
  const link = target.closest<HTMLElement>('[data-open-case]');
  if (link && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey) {
    event.preventDefault();
    openPreview(link.dataset.openCase!);
  }
  const category = target.closest<HTMLElement>('[data-filter]');
  if (category) {
    filter = category.dataset.filter!;
    renderFilter();
  }
  const remove = target.closest<HTMLElement>('[data-remove-candidate]');
  if (remove) toggleCandidate(remove.dataset.removeCandidate!);
  if (target.closest('[data-only-selected]')) {
    filter = 'selected';
    renderFilter();
  }
  if (target.closest('[data-clear-selection]')) {
    candidates = [];
    saveSelection();
  }
  if (target.closest('[data-preview-close]')) dialog.close();
  if (target.closest('[data-preview-previous]')) movePreview(-1);
  if (target.closest('[data-preview-next]')) movePreview(1);
  const view = target.closest<HTMLElement>('[data-preview-mode]')?.dataset.previewMode;
  if (view === 'live' || view === 'reference') setMode(view);
});
checks.forEach((checkbox) =>
  checkbox.addEventListener('change', () => toggleCandidate(checkbox.dataset.candidate!)),
);
candidateButton.addEventListener('click', () => {
  if (active) toggleCandidate(active.slug);
});
zoom.addEventListener('change', resizePreview);
reference.addEventListener('load', resizePreview);
new ResizeObserver(resizePreview).observe(stage);
dialog.addEventListener('close', () => {
  const url = new URL(location.href);
  url.searchParams.delete('case');
  history.replaceState(null, '', url);
});

renderSelection();
const requested = new URLSearchParams(location.search).get('case');
if (requested) openPreview(requested);
