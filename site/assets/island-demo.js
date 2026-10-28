// Dock the interactive preview to the viewport top and briefly show accepted choices.
// Exports no globals; depends on DOM events, IntersectionObserver and a cancellable one-second timer.
// @ts-check

/** @typedef {{root: HTMLElement, card: HTMLElement, form: HTMLFormElement,
 * input: HTMLInputElement, close: HTMLButtonElement, replay: HTMLButtonElement,
 * feedback: HTMLElement, choices: HTMLButtonElement[], inView: boolean, timer?: number}} IslandControls */
const ANSWER_HOLD_MS = 1000;

/** @param {HTMLElement} stage @returns {IslandControls | null} */
function controlsFor(stage) {
  const root = stage.querySelector('[data-island-demo]');
  if (!(root instanceof HTMLElement)) return null;
  const card = root.querySelector('.island-card');
  const form = root.querySelector('form');
  const input = root.querySelector('input');
  const close = root.querySelector('.island-close');
  const replay = stage.querySelector('.island-replay');
  const feedback = root.querySelector('.island-feedback');
  if (!(card instanceof HTMLElement) || !(form instanceof HTMLFormElement)
      || !(input instanceof HTMLInputElement) || !(close instanceof HTMLButtonElement)
      || !(replay instanceof HTMLButtonElement) || !(feedback instanceof HTMLElement)) return null;
  const choices = [...root.querySelectorAll('[data-choice]')]
    .filter(choice => choice instanceof HTMLButtonElement);
  return { root, card, form, input, close, replay, feedback, choices, inView: false };
}

/** @param {IslandControls} ui @param {boolean} visible */
function reveal(ui, visible) {
  ui.root.classList.toggle('is-visible', visible);
  ui.root.inert = !visible;
  ui.root.setAttribute('aria-hidden', String(!visible));
  ui.replay.setAttribute('aria-expanded', String(visible));
}

/** @param {IslandControls} ui */
function cancelDismissal(ui) {
  if (ui.timer !== undefined) window.clearTimeout(ui.timer);
  ui.timer = undefined;
}

/** @param {IslandControls} ui @param {boolean} [restoreFocus] */
function dismiss(ui, restoreFocus = true) {
  const hadFocus = ui.root.contains(document.activeElement);
  cancelDismissal(ui);
  ui.root.dataset.state = 'closed';
  reveal(ui, false);
  if (restoreFocus && hadFocus) ui.replay.focus({ preventScroll: true });
}

/** @param {IslandControls} ui @param {string} value */
function answer(ui, value) {
  if (!value || ui.root.dataset.state !== 'open') return;
  cancelDismissal(ui);
  ui.root.dataset.state = 'answered';
  for (const choice of ui.choices) {
    choice.setAttribute('aria-pressed', String(choice.dataset.choice === value));
    choice.disabled = true;
  }
  ui.input.disabled = true;
  const send = ui.form.querySelector('button');
  if (send instanceof HTMLButtonElement) send.disabled = true;
  const listed = ui.choices.some(choice => choice.dataset.choice === value);
  ui.feedback.classList.toggle('is-custom-answer', !listed);
  ui.feedback.textContent = `${ui.root.dataset.replyPrefix ?? ''}${value}`;
  ui.card.focus({ preventScroll: true });
  ui.timer = window.setTimeout(() => dismiss(ui), ANSWER_HOLD_MS);
}

/** @param {IslandControls} ui @param {boolean} [focus] */
function restart(ui, focus = true) {
  cancelDismissal(ui);
  ui.root.dataset.state = 'open';
  ui.root.scrollTop = 0;
  ui.feedback.textContent = '';
  ui.feedback.classList.remove('is-custom-answer');
  ui.form.reset();
  for (const control of ui.root.querySelectorAll('button, input')) {
    if (control instanceof HTMLButtonElement || control instanceof HTMLInputElement) control.disabled = false;
    if (control.hasAttribute('aria-pressed')) control.setAttribute('aria-pressed', 'false');
  }
  ui.replay.textContent = ui.replay.dataset.replayLabel ?? ui.replay.textContent;
  reveal(ui, true);
  for (const animation of ui.card.getAnimations()) {
    animation.currentTime = 0;
    animation.play();
  }
  if (focus) ui.choices[0]?.focus({ preventScroll: true });
}

/** @param {IslandControls} ui */
function bindControls(ui) {
  for (const choice of ui.choices) {
    choice.addEventListener('click', () => answer(ui, choice.dataset.choice ?? ''));
  }
  ui.form.addEventListener('submit', event => {
    event.preventDefault();
    const fallback = ui.choices.find(choice => choice.hasAttribute('data-default'))?.dataset.choice;
    answer(ui, ui.input.value.trim() || fallback || '');
  });
  ui.close.addEventListener('click', () => dismiss(ui));
  document.addEventListener('keydown', event => {
    if (event.key !== 'Escape' || !ui.root.classList.contains('is-visible')) return;
    event.preventDefault();
    dismiss(ui);
  });
  ui.replay.addEventListener('click', () => restart(ui));
}

/** @param {HTMLElement} stage @param {IslandControls} ui */
function observeStage(stage, ui) {
  if (!('IntersectionObserver' in window)) return;
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (entry.intersectionRatio >= 0.35 && !ui.inView) {
        ui.inView = true;
        if (!ui.root.classList.contains('is-visible')) restart(ui, false);
      } else if (!entry.isIntersecting && ui.inView) {
        ui.inView = false;
        if (ui.root.dataset.state !== 'answered') dismiss(ui, false);
      }
    }
  }, { threshold: [0, 0.35] });
  observer.observe(stage);
}

/** @param {HTMLElement} stage */
function initialize(stage) {
  const ui = controlsFor(stage);
  if (!ui || ui.choices.length === 0) return;
  bindControls(ui);
  ui.root.hidden = false;
  ui.replay.hidden = false;
  stage.classList.add('island-enhanced');
  reveal(ui, false);
  observeStage(stage, ui);
}

const stage = document.querySelector('[data-island-stage]');
if (stage instanceof HTMLElement) initialize(stage);
