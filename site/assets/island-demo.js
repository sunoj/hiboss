// Enhance the native Island showcase with a scroll reveal and local demo replies.
// Exports no globals; depends only on DOM events, IntersectionObserver and the demo markup.
// @ts-check

/** @typedef {{root: HTMLElement, card: HTMLElement, form: HTMLFormElement,
 * input: HTMLInputElement, close: HTMLButtonElement, replay: HTMLButtonElement,
 * feedback: HTMLElement, choices: HTMLButtonElement[]}} IslandControls */

/** @param {HTMLElement} stage @returns {IslandControls | null} */
function controlsFor(stage) {
  const root = stage.querySelector('[data-island-demo]');
  if (!(root instanceof HTMLElement)) return null;
  const card = root.querySelector('.island-card');
  const form = root.querySelector('form');
  const input = root.querySelector('input');
  const close = root.querySelector('.island-close');
  const replay = root.querySelector('.island-replay');
  const feedback = root.querySelector('.island-feedback');
  if (!(card instanceof HTMLElement) || !(form instanceof HTMLFormElement)
      || !(input instanceof HTMLInputElement) || !(close instanceof HTMLButtonElement)
      || !(replay instanceof HTMLButtonElement) || !(feedback instanceof HTMLElement)) return null;
  const choices = [...root.querySelectorAll('[data-choice]')]
    .filter((choice) => choice instanceof HTMLButtonElement);
  return { root, card, form, input, close, replay, feedback, choices };
}

/** @param {IslandControls} ui @param {boolean} visible */
function reveal(ui, visible) {
  ui.root.classList.toggle('is-visible', visible);
}

/** @param {IslandControls} ui @param {string} value */
function answer(ui, value) {
  if (!value || ui.root.dataset.state !== 'open') return;
  ui.root.dataset.state = 'answered';
  for (const choice of ui.choices) {
    choice.setAttribute('aria-pressed', String(choice.dataset.choice === value));
    choice.disabled = true;
  }
  ui.input.disabled = true;
  const send = ui.form.querySelector('button');
  if (send instanceof HTMLButtonElement) send.disabled = true;
  ui.feedback.textContent = `${ui.root.dataset.replyPrefix ?? ''}${value}`;
  ui.replay.hidden = false;
  ui.replay.focus({ preventScroll: true });
}

/** @param {IslandControls} ui */
function dismiss(ui) {
  ui.root.dataset.state = 'closed';
  ui.card.inert = true;
  ui.feedback.textContent = ui.root.dataset.closedMessage ?? '';
  ui.replay.hidden = false;
  ui.replay.focus({ preventScroll: true });
}

/** @param {IslandControls} ui */
function restart(ui) {
  ui.root.dataset.state = 'open';
  ui.card.inert = false;
  ui.feedback.textContent = '';
  ui.replay.hidden = true;
  ui.form.reset();
  for (const control of ui.root.querySelectorAll('button, input')) {
    if (control instanceof HTMLButtonElement || control instanceof HTMLInputElement) control.disabled = false;
    if (control.hasAttribute('aria-pressed')) control.setAttribute('aria-pressed', 'false');
  }
  reveal(ui, false);
  requestAnimationFrame(() => requestAnimationFrame(() => {
    if (ui.root.dataset.state !== 'open') return;
    reveal(ui, true);
    if (document.activeElement === ui.replay || document.activeElement === document.body) {
      ui.choices[0]?.focus({ preventScroll: true });
    }
  }));
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
  ui.root.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    event.preventDefault();
    dismiss(ui);
  });
  ui.replay.addEventListener('click', () => restart(ui));
}

/** @param {HTMLElement} stage */
function initialize(stage) {
  const ui = controlsFor(stage);
  if (!ui || ui.choices.length === 0) return;
  bindControls(ui);
  ui.root.hidden = false;
  ui.root.dataset.state = 'open';
  stage.classList.add('island-enhanced');
  stage.addEventListener('focusin', () => reveal(ui, true));
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) reveal(ui, entry.isIntersecting || stage.contains(document.activeElement));
    }, { threshold: 0.35 });
    observer.observe(stage);
  } else {
    reveal(ui, true);
  }
}

const stage = document.querySelector('[data-island-stage]');
if (stage instanceof HTMLElement) initialize(stage);
