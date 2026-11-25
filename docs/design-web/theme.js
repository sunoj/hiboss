// Theme toggle for the static mockups: system -> the opposite of system -> system.
// Sets data-theme on <html>; tokens.css does the rest.
(function () {
  var root = document.documentElement;
  var saved = null;
  try { saved = localStorage.getItem('hb-mock-theme'); } catch (e) { /* storage blocked */ }
  if (saved) root.setAttribute('data-theme', saved);
  document.addEventListener('click', function (event) {
    if (!event.target.closest('[data-theme-toggle]')) return;
    var systemDark = matchMedia('(prefers-color-scheme: dark)').matches;
    var current = root.getAttribute('data-theme');
    var next = current ? null : (systemDark ? 'light' : 'dark');
    if (next) root.setAttribute('data-theme', next); else root.removeAttribute('data-theme');
    try { next ? localStorage.setItem('hb-mock-theme', next) : localStorage.removeItem('hb-mock-theme'); } catch (e) { /* ignore */ }
  });
})();
