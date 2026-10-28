# Exercise the static build's public file set, navigation and local resource references.
# Uses only unittest, a temporary output directory and the repository's actual build command.
import hashlib
from html.parser import HTMLParser
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
NAVIGATION = (
    ('index.html', '/zh/', 'zh-Hans', None),
    ('404.html', '/zh/', 'zh-Hans', None),
    ('download/index.html', '/zh/download/', 'zh-Hans', '/download/'),
    ('changelog/index.html', '/zh/', 'zh-Hans', '/changelog/'),
    ('privacy/index.html', '/zh/', 'zh-Hans', '/privacy/'),
    ('support/index.html', '/zh/', 'zh-Hans', '/support/'),
    ('docs/self-host/index.html', '/zh/docs/self-host/', 'zh-Hans', '/docs/self-host/'),
    ('docs/agents/index.html', '/zh/', 'zh-Hans', '/docs/agents/'),
    ('zh/index.html', '/', 'en', None),
    ('zh/download/index.html', '/download/', 'en', '/zh/download/'),
    ('zh/docs/self-host/index.html', '/docs/self-host/', 'en', '/zh/docs/self-host/'),
)
PAGES = [page for page, _, _, _ in NAVIGATION]


class References(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[dict[str, str | None]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.links.append(dict(attrs))


class SiteBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix='hiboss-site-test-')
        cls.output = Path(cls.temporary.name) / 'public'
        subprocess.run(['bash', str(ROOT / 'build.sh'), str(cls.output)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_build_contains_exactly_the_public_pages_and_assets(self) -> None:
        assets = {'install.sh', 'robots.txt', 'sitemap.xml', 'updates/macos/appcast.xml',
                  'assets/site.css', 'assets/island-demo.css', 'assets/island-demo.js',
                  'assets/icon.png', 'assets/apple-touch-icon.png', 'assets/og.jpg'}
        assets.update(f'assets/shots/{screen}-{theme}.jpg'
                      for screen in ['home', 'session', 'panels', 'progress', 'box', 'mac-island']
                      for theme in ['light', 'dark'])
        actual = {str(path.relative_to(self.output)) for path in self.output.rglob('*') if path.is_file()}
        self.assertEqual(actual, set(PAGES) | assets)

    def test_navigation_preserves_current_pages_and_language_counterparts(self) -> None:
        for page, target, language, current in NAVIGATION:
            with self.subTest(page=page):
                parser = References()
                text = (self.output / page).read_text(encoding='utf-8')
                parser.feed(text)
                self.assertNotIn('<!-- include ', text)
                self.assertNotIn('{{language}}', text)
                switch = [link for link in parser.links if link.get('class') == 'lang']
                self.assertEqual([(a.get('href'), a.get('hreflang'), a.get('lang')) for a in switch],
                                 [(target, language, language)])
                active = [link.get('href') for link in parser.links if link.get('aria-current') == 'page']
                self.assertEqual(active, [] if current is None else [current])

    def test_all_local_links_and_images_exist_in_the_output(self) -> None:
        for page in PAGES:
            parser = References()
            parser.feed((self.output / page).read_text(encoding='utf-8'))
            for attrs in parser.links:
                for name in ['href', 'src', 'srcset']:
                    reference = attrs.get(name) or ''
                    if reference.startswith('/') and not reference.startswith('//'):
                        path = urlsplit(reference).path.lstrip('/')
                        target = self.output / (
                            path + 'index.html' if path.endswith('/') or not path else path)
                        self.assertTrue(target.is_file(), f'{page}: missing {reference}')

    def test_public_pages_use_product_identity(self) -> None:
        for page in PAGES:
            with self.subTest(page=page):
                text = (self.output / page).read_text(encoding='utf-8')
                self.assertIn('© 2026 HiBoss', text)
        privacy = (self.output / 'privacy/index.html').read_text(encoding='utf-8')
        self.assertNotIn('Published by', privacy)

    def test_home_pages_show_mac_decisions_in_both_appearances(self) -> None:
        for page in ['index.html', 'zh/index.html']:
            with self.subTest(page=page):
                parser = References()
                parser.feed((self.output / page).read_text(encoding='utf-8'))
                images = [attrs for attrs in parser.links if attrs.get('class') == 'island-shot']
                self.assertEqual(len(images), 1)
                self.assertEqual(images[0].get('src'), '/assets/shots/mac-island-light.jpg')
                self.assertTrue(images[0].get('alt'))
                self.assertTrue(any(attrs.get('srcset') == '/assets/shots/mac-island-dark.jpg'
                                    for attrs in parser.links))

    def test_home_pages_include_local_interactive_demo_with_screenshot_fallback(self) -> None:
        for page in ['index.html', 'zh/index.html']:
            with self.subTest(page=page):
                parser = References()
                parser.feed((self.output / page).read_text(encoding='utf-8'))
                scripts = [a for a in parser.links
                           if urlsplit(a.get('src') or '').path == '/assets/island-demo.js']
                self.assertEqual(len(scripts), 1)
                self.assertEqual(scripts[0].get('type'), 'module')
                for name in ['island-demo.js', 'island-demo.css']:
                    digest = hashlib.sha256((self.output / 'assets' / name).read_bytes()).hexdigest()[:12]
                    text = (self.output / page).read_text(encoding='utf-8')
                    self.assertIn(f'/assets/{name}?v={digest}', text)
                choices = [a for a in parser.links if 'data-choice' in a]
                self.assertEqual(len(choices), 2)
                self.assertEqual(sum('data-default' in a for a in choices), 1)
                self.assertTrue(any(a.get('role') == 'status' for a in parser.links))
                self.assertTrue(any(a.get('class') == 'island-fallback' for a in parser.links))

    def test_build_rejects_missing_relative_and_existing_outputs(self) -> None:
        before = sorted(path.relative_to(self.output) for path in self.output.rglob('*'))
        for args in [[], ['relative-output'], [str(self.output)]]:
            with self.subTest(args=args):
                result = subprocess.run(['bash', str(ROOT / 'build.sh'), *args], capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn(b'usage:', result.stderr)
        self.assertEqual(sorted(path.relative_to(self.output) for path in self.output.rglob('*')), before)


if __name__ == '__main__':
    unittest.main()
