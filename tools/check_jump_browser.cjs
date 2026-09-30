const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

// All gameplay uses real keyboard/mouse input. The debug state is read-only.
const output = path.resolve(__dirname, '../deliverables/jump');
const url = process.env.WORLD_PREVIEW_URL || 'http://127.0.0.1:8765/index.html?v=20260925-jump';
const report = { url, started_at: new Date().toISOString(), passed: false, checks: [], errors: [], screenshots: [] };
const distance = (a, b) => Math.hypot(...a.map((v, i) => v - b[i]));
const radius = v => Math.hypot(...v);
const check = (name, passed, evidence) => {
  report.checks.push({ name, passed: Boolean(passed), evidence });
  if (!passed) console.error('CHECK_FAILED', name, JSON.stringify(evidence));
};

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 800 } });
    page.setDefaultTimeout(30000);
    page.on('pageerror', e => report.errors.push(String(e)));
    page.on('console', m => {
      if (m.type() === 'error' && !m.text().startsWith('Failed to load resource:')) report.errors.push(m.text());
    });
    page.on('response', r => {
      if (r.status() >= 400 && !r.url().endsWith('/favicon.ico')) report.errors.push(`${r.status()} ${r.url()}`);
    });
    await page.addInitScript(() => {
      window.jumpBrowserHistory = [];
      setInterval(() => {
        const s = window.planetWorldState;
        if (s && window.jumpBrowserHistory.at(-1)?.state !== s) {
          window.jumpBrowserHistory.push({ at: performance.now(), state: s });
          if (window.jumpBrowserHistory.length > 1200) window.jumpBrowserHistory.shift();
        }
      }, 40);
    });
    const state = () => page.evaluate(() => window.planetWorldState);
    const history = () => page.evaluate(() => window.jumpBrowserHistory.map(r => r.state));
    const shot = async name => {
      const filename = path.join(output, `${name}.png`);
      await page.screenshot({ path: filename, timeout: 60000 });
      report.screenshots.push(filename);
    };
    const settle = async () => {
      await page.waitForFunction(() => window.planetWorldState.grounded && window.planetWorldState.jump_state === 'grounded', null, { timeout: 30000 });
    };
    await page.goto(url);
    await page.waitForFunction(() => window.planetWorldState?.jump_state !== undefined, null, { timeout: 240000 });
    let before = await state();
    await page.keyboard.press('Space');
    await page.waitForTimeout(900);
    check('Space in world overview does not launch player', (await state()).jump_count === before.jump_count);
    await page.keyboard.press('Tab');
    await page.waitForFunction(() => !window.planetWorldState.overview);
    await settle();
    before = await state();
    await shot('web-ready');
    await page.keyboard.down('Space');
    await page.waitForFunction(n => window.planetWorldState.jump_count > n, before.jump_count);
    await page.waitForFunction(r => Math.hypot(...window.planetWorldState.position) > r + 1.15, radius(before.position));
    const airborne = await state();
    await shot('web-airborne');
    await page.waitForTimeout(2300);
    await settle();
    let after = await state();
    check('Holding Space performs exactly one physical jump', after.jump_count === before.jump_count + 1, { before, airborne, after });
    check('Jump lifts real player capsule above a low railing', radius(airborne.position) - radius(before.position) > 1.15, { rise: radius(airborne.position) - radius(before.position) });
    check('Normal jump keeps character visible and does not enter portal', airborne.visible && after.visible && !airborne.entering && !after.entering);
    check('Jump returns to grounded feet height', Math.abs(radius(after.position) - radius(before.position)) < .08, { before: radius(before.position), after: radius(after.position) });
    check('Jump preserves chosen camera distance and FOV', Math.abs(airborne.camera_distance - before.camera_distance) < .03 && airborne.camera_fov === before.camera_fov);
    await page.keyboard.up('Space');
    await page.waitForTimeout(300);

    before = await state();
    await page.keyboard.down('Space');
    await page.waitForFunction(n => window.planetWorldState.jump_count > n, before.jump_count);
    await page.keyboard.up('Space');
    await page.waitForTimeout(100);
    await page.keyboard.press('Space');
    await settle();
    after = await state();
    check('A second airborne Space press cannot create a double jump', after.jump_count === before.jump_count + 1, { before: before.jump_count, after: after.jump_count });

    await page.keyboard.press('Home');
    await page.waitForTimeout(500);
    await settle();
    before = await state();
    await page.keyboard.down('w');
    await page.keyboard.down('Space');
    await page.waitForFunction(n => window.planetWorldState.jump_count > n, before.jump_count);
    await page.keyboard.up('Space');
    await page.waitForTimeout(800);
    await page.keyboard.up('w');
    await settle();
    after = await state();
    check('W plus Space retains horizontal movement while jumping', distance(after.position, before.position) > .4, { travel: distance(after.position, before.position) });
    await shot('web-landed');
    const samples = await history();
    const jumpClips = [...new Set(samples.map(s => s.animation).filter(s => /^Jump(Start|Air|Land)/.test(s)))];
    check('Imported authored jump animation is played in Web build', jumpClips.includes('JumpAir') && jumpClips.includes('JumpLand'), { observed: jumpClips });
    check('Mouse remains visible and unlocked during jumping', await page.evaluate(() => !document.pointerLockElement && window.planetWorldState.mouse_mode === 0));
    report.history = samples;
    report.passed = report.errors.length === 0 && report.checks.every(c => c.passed);
  } catch (e) {
    report.errors.push(String(e.stack || e));
  } finally {
    report.finished_at = new Date().toISOString();
    fs.writeFileSync(path.join(output, 'browser-review.json'), JSON.stringify(report, null, 2));
    await browser.close();
  }
  console.log('JUMP_BROWSER_REVIEW', JSON.stringify({ passed: report.passed, checks: report.checks.length, errors: report.errors, failed: report.checks.filter(c => !c.passed).map(c => c.name) }));
  if (!report.passed) process.exitCode = 1;
})().catch(e => { console.error(e); process.exitCode = 1; });
