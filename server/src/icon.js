// Serves the installable dashboard icon as inline SVG markup.
// Exports a compact SVG string for the /icon.svg route.
// Deps: none.

const iconSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96" fill="none">
  <rect width="96" height="96" rx="24" fill="#161b22"/>
  <rect x="10" y="10" width="76" height="76" rx="18" fill="#0d1117" stroke="#30363d" stroke-width="4"/>
  <path d="M48 22v14m0 24v14M22 48h14m24 0h14m-9.9-16.1-9.9 9.9m0 12.4 9.9 9.9m-32.4 0 9.9-9.9m0-12.4-9.9-9.9" stroke="#58a6ff" stroke-width="6" stroke-linecap="round"/>
  <circle cx="48" cy="48" r="11" fill="#58a6ff"/>
</svg>`;

export default iconSvg;
