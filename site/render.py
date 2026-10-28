# Expand shared bilingual navigation in the explicitly listed static HTML pages.
# Exports render_page; depends only on Python's standard library and local HTML fragments.
import hashlib
from pathlib import Path, PurePosixPath
import sys

SOURCE = Path(__file__).resolve().parent
PAIRED = {'/': '/zh/', '/download/': '/zh/download/', '/docs/self-host/': '/zh/docs/self-host/'}
HEADER_ACTIVE = {'/download/', '/docs/self-host/', '/docs/agents/', '/changelog/',
                 '/zh/download/', '/zh/docs/self-host/'}


def fragment(kind: str, url: str) -> str:
    chinese = url.startswith('/zh/')
    language = 'zh' if chinese else 'en'
    source = (SOURCE / 'partials' / f'{kind}-{language}.html').read_text(encoding='utf-8')
    source = source.split('-->\n', 1)[1].removesuffix('\n')
    if kind == 'header':
        counterpart = url.removeprefix('/zh') if chinese else PAIRED.get(url, '/zh/')
        source = source.replace('{{language}}', counterpart)
    active = HEADER_ACTIVE if kind == 'header' else {'/privacy/', '/support/'}
    if url in active:
        source = source.replace(f'href="{url}"', f'href="{url}" aria-current="page"')
    return source


def render_page(relative: str) -> str:
    path = PurePosixPath(relative)
    if path.is_absolute() or '..' in path.parts or path.suffix != '.html':
        raise ValueError('expected a relative HTML page path')
    source = (SOURCE / path).read_text(encoding='utf-8')
    url = '/' + str(path).removesuffix('index.html')
    for kind in ['header', 'footer', 'island']:
        if kind == 'island' and url not in ('/', '/zh/'):
            continue
        marker = f'  <!-- include {kind} -->'
        if source.count(marker) != 1:
            raise ValueError(f'expected one {kind} include in {relative}')
        source = source.replace(marker, fragment(kind, url))
    if url in ('/', '/zh/'):
        for name in ('island-demo.css', 'island-demo.js'):
            digest = hashlib.sha256((SOURCE / 'assets' / name).read_bytes()).hexdigest()[:12]
            source = source.replace(f'/assets/{name}"', f'/assets/{name}?v={digest}"')
    if '<!-- include ' in source or '{{language}}' in source:
        raise ValueError(f'unresolved template marker in {relative}')
    return source


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('usage: render.py relative/page.html')
    sys.stdout.write(render_page(sys.argv[1]))
