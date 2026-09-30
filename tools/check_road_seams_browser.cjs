const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const browser = await chromium.launch({channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader']});
  const errors = [];
  const captures = [];
  try {
    const page = await browser.newPage({viewport: {width: 1200, height: 800}});
    page.on('pageerror', error => errors.push(String(error)));
    page.on('console', message => { if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) errors.push(message.text()); });
    page.on('response', response => { if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) errors.push(`${response.status()} ${response.url()}`); });
    await page.goto('http://127.0.0.1:8765/index.html#review-ecology-4');
    await page.waitForFunction(() => window.planetWorldReady === true, null, {timeout: 240000});
    for (const index of [4, 0, 5]) {
      await page.evaluate(index => { location.hash = `review-ecology-${index}`; }, index);
      await page.waitForTimeout(2500);
      const output = path.resolve(__dirname, `../deliverables/seam-web-${index}.png`);
      await page.screenshot({path: output, timeout: 60000});
      captures.push(output);
      console.log('CAPTURED', index);
    }
    await page.evaluate(() => { location.hash = ''; });
    await page.waitForTimeout(1000);
    await page.locator('#canvas').focus();
    await page.keyboard.press('Home');
    await page.waitForFunction(() => window.planetWorldState?.overview === false, null, {timeout: 30000});
    const before = await page.evaluate(() => window.planetWorldState.position);
    await page.keyboard.down('w');
    await page.waitForTimeout(1400);
    await page.keyboard.up('w');
    await page.waitForTimeout(700);
    const after = await page.evaluate(() => window.planetWorldState.position);
    const moved = Math.hypot(...after.map((value, i) => value - before[i]));
    if (moved < .3) errors.push(`Web walking failed: ${moved}`);
    fs.writeFileSync(path.resolve(__dirname, '../deliverables/seam-browser-review.json'), JSON.stringify({checked_at: new Date().toISOString(), errors, captures, walked_distance: moved}, null, 2));
    if (errors.length) throw new Error(JSON.stringify(errors));
    console.log('SEAM_WEB_CHECK_OK', moved);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
