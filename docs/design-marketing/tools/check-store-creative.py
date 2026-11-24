# Verify the App Store creative assets and the custom product page manifest.
# Usage: python3 docs/design-marketing/tools/check-store-creative.py   (run from the repository root)
# Checks: PNG, exactly 5244x2950, no alpha; crop previews exist; promo text within 170 characters;
# 3-6 existing frames per device; no keywords; no third-party product name in any text.
import json
import re
import struct
import sys
from pathlib import Path

STORE = Path('docs/design-marketing/app-store')
SIZE = (5244, 2950)
CROPS = ['21x9-wide', '21x9-tight', '3x2-wide', '3x2-tight']
THIRD_PARTY = re.compile(r'claude|codex|anthropic|openai|cloudflare|telegram|discord|github|stripe', re.I)
failures: list[str] = []


def png_facts(path: Path) -> tuple[int, int, bool]:
    """Width, height and whether the PNG stores alpha, read from its header and chunk list."""
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('not a PNG file')
    width, height, _, colour = struct.unpack('>IIBB', data[16:26])
    return width, height, colour in (4, 6) or b'tRNS' in data[:4096]


def check_asset(path: Path) -> None:
    if not path.is_file():
        failures.append(f'missing asset {path}')
        return
    try:
        width, height, alpha = png_facts(path)
    except ValueError as error:
        failures.append(f'{path}: {error}')
        return
    if (width, height) != SIZE:
        failures.append(f'{path}: {width}x{height}, expected {SIZE[0]}x{SIZE[1]}')
    if alpha:
        failures.append(f'{path}: has an alpha channel')
    for crop in CROPS:
        preview = STORE / 'creative' / 'previews' / f'{path.parent.name}-{path.stem}-{crop}.jpg'
        if not preview.is_file():
            failures.append(f'missing preview {preview}')


def main() -> None:
    assets = sorted((STORE / 'creative').glob('*/*.png'))
    if len(assets) < 2:
        failures.append('expected at least one creative asset per locale')
    for asset in assets:
        check_asset(asset)
    raw = (STORE / 'custom-pages.json').read_text(encoding='utf-8')
    if '"keywords"' in raw:
        failures.append('custom-pages.json must not carry keywords')
    manifest = json.loads(raw)
    pages = manifest['pages']
    if len(pages) != 2:
        failures.append('expected two custom product pages')
    for locale, asset in manifest['default_page']['creative_asset'].items():
        check_asset(Path(asset))
    for page in pages:
        for locale, entry in page['locales'].items():
            where = f"{page['name']} / {locale}"
            text = entry['promotional_text']
            if len(text) > 170:
                failures.append(f'{where}: promotional text is {len(text)} characters')
            if THIRD_PARTY.search(text) or THIRD_PARTY.search(page['name'] + page['purpose']):
                failures.append(f'{where}: names a third-party product')
            check_asset(Path(entry['creative_asset']))
            for device, frames in entry['frames'].items():
                if not 3 <= len(frames) <= 6 or len(set(frames)) != len(frames):
                    failures.append(f'{where} {device}: needs 3-6 distinct frames')
                for frame in frames:
                    if f'/{locale}/{device}/' not in frame or not Path(frame).is_file():
                        failures.append(f'{where}: bad frame {frame}')
    for failure in failures:
        print('FAIL:', failure)
    print(f'creative: {len(assets)} assets, {len(pages)} custom pages, {len(failures)} failures')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
