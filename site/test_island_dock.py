# Browser assertions for viewport docking, short windows and the one-second resolved state.
# Consumed by the real Chrome runner in test_island.py; no production imports.
DOCK = r'''async (page) => {
  await page.setViewportSize({width: WIDTH, height: HEIGHT});
  await page.emulateMedia({reducedMotion: 'reduce'});
  await page.goto(URL);
  await page.locator('.island-stage').scrollIntoViewIfNeeded();
  await page.waitForFunction(() => document.querySelector('.island-demo.is-visible'));
  const root = page.locator('[data-island-demo]');
  const frame = await root.boundingBox();
  const position = await root.evaluate(el => getComputedStyle(el).position);
  if (position !== 'fixed' || Math.abs(frame.y) > 1) throw Error('Card is not attached to viewport top');
  if (Math.abs(frame.x + frame.width / 2 - WIDTH / 2) > 2) throw Error('Dock is not centered');
  const before = await page.evaluate(() => scrollY);
  await page.evaluate(() => scrollBy(0, 80));
  const after = await root.boundingBox();
  if (Math.abs(after.y) > 1) throw Error('Dock moves with document scrolling');
  if (await page.evaluate(() => scrollY) === before) throw Error('Page scrolling is locked');
  await page.locator('.island-reply input').scrollIntoViewIfNeeded();
  const font = await page.locator('.island-reply input').evaluate(el => getComputedStyle(el).fontSize);
  if (parseFloat(font) < 16) throw Error('Input text is too small');
  const input = await page.locator('.island-reply input').boundingBox();
  if (input.y < 0 || input.y + input.height > HEIGHT) throw Error('Reply field cannot be reached');
  const close = await page.locator('.island-close').boundingBox();
  if (close.y < 0 || close.y + close.height > HEIGHT) throw Error('Close is unreachable');
  if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) throw Error('Overflow');
  await page.screenshot({path: OUTPUT + '/dock-LANG-WIDTH-HEIGHT.png'});
  return {passed: 1};
}'''

COMPLETION = r'''async (page) => {
  const context = await page.context().browser().newContext({reducedMotion: 'reduce'});
  try {
    const test = await context.newPage();
    await test.setViewportSize({width: 1440, height: 1000});
    await test.clock.install({time: new Date('2026-10-01T00:00:00Z')});
    await test.goto(URL);
    await test.locator('.island-stage').scrollIntoViewIfNeeded();
    await test.waitForFunction(() => document.querySelector('.island-demo.is-visible'));
    await test.clock.pauseAt(new Date('2026-10-01T01:00:00Z'));
    const root = test.locator('[data-island-demo]');
    const chosen = test.locator('[data-choice]').nth(1);
    const value = await chosen.getAttribute('data-choice');
    await chosen.click();
    if (await chosen.getAttribute('aria-pressed') !== 'true') throw Error('Chosen option is not shown');
    if (!(await test.locator('.island-feedback').innerText()).endsWith(value)) throw Error('Wrong result');
    if (await test.locator('.island-reply').isVisible()) throw Error('Reply editor remains in resolved card');
    await test.clock.runFor(999);
    if (!(await root.isVisible())) throw Error('Card disappears before one second');
    await test.screenshot({path: OUTPUT + '/selected-LANG-999ms.png'});
    await test.clock.runFor(1);
    if (await root.isVisible()) throw Error('Card remains after one second');
    await test.locator('.island-replay').click();
    await test.locator('.island-reply input').fill('Use a compact sidebar');
    await test.keyboard.press('Enter');
    if (!(await test.locator('.island-feedback').innerText()).includes('Use a compact sidebar')) {
      throw Error('Custom answer is missing');
    }
    await test.clock.runFor(500);
    await test.locator('.island-replay').click();
    await test.clock.runFor(500);
    if (await root.getAttribute('data-state') !== 'open') throw Error('Old timer closes new card');
    await test.keyboard.press('Escape');
    await test.clock.runFor(5000);
    if (await root.isVisible()) throw Error('Dismissed card reopens without a new entry');
  } finally { await context.close(); }
  return {passed: 1};
}'''
