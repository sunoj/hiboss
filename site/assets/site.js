// Reveal sections as they enter the viewport; leave content visible without JS.
// Exports no public API. Depends only on IntersectionObserver.
const targets = document.querySelectorAll('.reveal');
if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    }
  }, { threshold: 0.12 });
  for (const target of targets) observer.observe(target);
} else {
  for (const target of targets) target.classList.add('is-visible');
}
