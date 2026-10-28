# Exercises the interactive Island in real Chrome through the Playwright CLI.
# Run on a remote browser test host; saves screenshots and uses the real static build.
import functools
import http.server
import json
from pathlib import Path
import shutil
import subprocess
import threading

ROOT = Path(__file__).resolve().parent
CLI = ['npx', '--yes', '--package', '@playwright/cli', 'playwright-cli', '--session', 'hiboss-island']
SCENARIO = r'''async (page) => {
  await page.setViewportSize({width: WIDTH, height: 1000});
  await page.emulateMedia({colorScheme: THEME, reducedMotion: 'no-preference'});
  await page.goto(URL);
  const demo = page.locator('[data-island-demo]');
  await page.waitForFunction(() => document.querySelector('.island-enhanced'));
  if (await demo.evaluate(el => el.classList.contains('is-visible'))) throw Error('Premature reveal');
  const pointer = await page.locator('.island-card').evaluate(el => getComputedStyle(el).pointerEvents);
  if (pointer !== 'none') throw Error('Hidden card accepts pointer input');
  await page.locator('.island-stage').scrollIntoViewIfNeeded();
  await page.waitForFunction(() => document.querySelector('.island-demo.is-visible'));
  await page.locator('.island-card').evaluate(async el => {
    await Promise.all(el.getAnimations().map(animation => animation.finished));
  });
  const frame = await page.locator('.island-card').boundingBox();
  if (Math.abs(frame.x + frame.width / 2 - WIDTH / 2) > 2) throw Error('Card is not centered');
  if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) throw Error('Overflow');
  await page.screenshot({path: OUTPUT + '/LANG-WIDTH-THEME.png'});
  const choices = page.locator('[data-choice]');
  const first = await choices.nth(0).getAttribute('data-choice');
  const second = await choices.nth(1).getAttribute('data-choice');
  await choices.nth(1).click();
  if (await demo.getAttribute('data-state') !== 'answered') throw Error('Choice was not accepted');
  if (!(await page.locator('.island-feedback').innerText()).endsWith(second)) throw Error('Wrong reply');
  if (await choices.nth(1).getAttribute('aria-pressed') !== 'true') throw Error('Missing selection');
  if (!(await choices.nth(0).isDisabled())) throw Error('Duplicate replies remain enabled');
  await page.locator('.island-replay').click();
  await page.locator('.island-reply input').focus();
  await page.keyboard.press('Enter');
  if (!(await page.locator('.island-feedback').innerText()).endsWith(first)) throw Error('Wrong default');
  await page.locator('.island-replay').click();
  await page.locator('.island-reply input').fill('<img src=x onerror=alert(1)>');
  await page.keyboard.press('Enter');
  if (!(await page.locator('.island-feedback').innerText()).includes('<img')) throw Error('Reply lost');
  if (await page.locator('.island-feedback img').count()) throw Error('Reply interpreted as HTML');
  await page.locator('.island-replay').click();
  await page.keyboard.press('Escape');
  if (await demo.getAttribute('data-state') !== 'closed') throw Error('Escape did not close');
  if (!(await page.locator('.island-replay').evaluate(el => el === document.activeElement))) {
    throw Error('Close lost keyboard focus');
  }
  await page.locator('.island-replay').click();
  if (await demo.getAttribute('data-state') !== 'open') throw Error('Replay did not reopen');
  await page.locator('.island-close').click();
  if (await demo.getAttribute('data-state') !== 'closed') throw Error('Close button failed');
  return {passed: 1};
}'''


def cli(*args: str) -> str:
    result = subprocess.run([*CLI, *args], capture_output=True, text=True)
    if result.returncode or '### Error' in result.stdout:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def run_code(code: str) -> None:
    result = cli('run-code', code)
    summary = json.loads(result.split('### Result\n', 1)[1].splitlines()[0])
    assert summary == {'passed': 1}, summary


def check_variants(base: str, output: Path) -> int:
    count = 0
    for language in ['en', 'zh']:
        url = base + ('/zh/' if language == 'zh' else '/')
        for width in [1440, 375]:
            for theme in ['light', 'dark']:
                code = SCENARIO.replace('LANG', language).replace('WIDTH', str(width))
                code = code.replace('THEME', theme)
                code = code.replace('colorScheme: ' + theme, 'colorScheme: ' + json.dumps(theme))
                code = code.replace('URL', json.dumps(url)).replace('OUTPUT', json.dumps(str(output)))
                run_code(code)
                count += 1
                print(f'PASS {language} {width} {theme}', flush=True)
        check_reduced_motion(url)
        check_without_javascript(url)
        count += 2
    return count


def check_reduced_motion(url: str) -> None:
    code = '''async (page) => {
      await page.emulateMedia({reducedMotion: 'reduce'});
      await page.goto(URL);
      await page.locator('.island-stage').scrollIntoViewIfNeeded();
      await page.waitForFunction(() => document.querySelector('.island-demo.is-visible'));
      const animation = await page.locator('.island-card').evaluate(el => getComputedStyle(el).animationName);
      if (animation !== 'none') throw Error('Reduced motion still animates');
      await page.locator('[data-default]').click();
      if (await page.locator('[data-island-demo]').getAttribute('data-state') !== 'answered') {
        throw Error('Reduced-motion interaction failed');
      }
      return {passed: 1};
    }'''
    run_code(code.replace('URL', json.dumps(url)))


def check_without_javascript(url: str) -> None:
    code = '''async (page) => {
      const context = await page.context().browser().newContext({javaScriptEnabled: false});
      try {
        const fallback = await context.newPage();
        await fallback.goto(URL);
        if (!(await fallback.locator('.island-shot').isVisible())) throw Error('No screenshot fallback');
        if (await fallback.locator('[data-island-demo]').isVisible()) {
          throw Error('Inactive controls exposed');
        }
      } finally { await context.close(); }
      return {passed: 1};
    }'''
    run_code(code.replace('URL', json.dumps(url)))


def main() -> None:
    assert shutil.which('npx'), 'npx is required on the browser test host'
    output = Path.cwd() / 'output/playwright/island-demo'
    output.mkdir(parents=True, exist_ok=True)
    public = output / 'public'
    subprocess.run(['bash', str(ROOT / 'build.sh'), str(public)], check=True)
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(public))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        cli('open', f'http://127.0.0.1:{server.server_port}', '--browser', 'chrome')
        cli('snapshot')
        count = check_variants(f'http://127.0.0.1:{server.server_port}', output)
        print(f'BROWSER_RESULT passed={count} failed=0', flush=True)
        print('SCREENSHOTS=' + str(output), flush=True)
    finally:
        cli('close')
        server.shutdown()


if __name__ == '__main__':
    main()
