const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

// Real browser inputs only. Telemetry is read-only and exported by debug builds.
const output = path.resolve(__dirname, '../deliverables');
const reportPath = path.join(output, 'world-polish-browser-review.json');
const url = process.env.WORLD_PREVIEW_URL || 'http://127.0.0.1:8765/index.html?world-polish';
const report = { started_at: new Date().toISOString(), url, passed: false, errors: [], checks: [], screenshots: [] };
const dot = (a, b) => a.reduce((sum, value, i) => sum + value * b[i], 0);
const subtract = (a, b) => a.map((value, i) => value - b[i]);
const length = a => Math.hypot(...a);
const unit = a => a.map(value => value / Math.max(length(a), 1e-9));
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const difference = (a, b) => length(subtract(a, b));
const check = (test, passed, evidence) => {
  report.checks.push({ test, passed: Boolean(passed), evidence });
  if (!passed) console.error('CHECK_FAILED', test, JSON.stringify(evidence));
};

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 800 } });
    page.setDefaultTimeout(30000);
    page.on('pageerror', error => report.errors.push(String(error)));
    page.on('console', message => {
      if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) report.errors.push(message.text());
    });
    page.on('response', response => {
      if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) report.errors.push(`${response.status()} ${response.url()}`);
    });
    const state = () => page.evaluate(() => window.planetWorldState);
    const screenshot = async name => {
      const filename = path.join(output, `world-polish-web-${name}.png`);
      await page.screenshot({ path: filename, timeout: 60000 });
      report.screenshots.push(filename);
    };
    const canvasBox = async () => {
      const box = await page.locator('#canvas').boundingBox();
      if (!box || !box.width || !box.height) throw new Error('Game canvas is not visible');
      return box;
    };
    const leftDrag = async (distanceX = 125, distanceY = 18) => {
      const box = await canvasBox();
      const x = box.x + box.width * .68;
      const y = box.y + box.height * .47;
      await page.mouse.move(x, y);
      await page.mouse.down({ button: 'left' });
      await page.waitForFunction(() => window.planetWorldState.dragging);
      await page.mouse.move(x + distanceX, y + distanceY, { steps: 10 });
      await page.waitForTimeout(550);
      const during = await state();
      await page.mouse.up({ button: 'left' });
      await page.waitForFunction(() => !window.planetWorldState.dragging);
      await page.waitForTimeout(400);
      return during;
    };
    const clickDestinationToggle = async () => {
      const status = await state();
      const box = await canvasBox();
      await page.mouse.click(box.x + status.destination_button[0] * box.width, box.y + status.destination_button[1] * box.height);
      await page.waitForFunction(previous => window.planetWorldState.destinations_open !== previous, status.destinations_open);
    };
    await page.goto(url);
    await page.waitForFunction(() => window.planetWorldState?.minimap_arrow && window.planetWorldState?.minimap_frame, null, { timeout: 240000 });
    await page.waitForTimeout(1300);

    let before = await state();
    check('Starts with the full world overview', before.overview, before);
    const duringOverview = await leftDrag();
    let after = await state();
    check('Real left hold rotates overview', duringOverview.dragging && Math.abs(after.yaw - before.yaw) > .08, { before: before.yaw, after: after.yaw });
    before = after;
    await page.mouse.move(1050, 450, { steps: 5 });
    await page.waitForTimeout(900);
    after = await state();
    check('Overview release stops rotation', !after.dragging && Math.abs(after.yaw - before.yaw) < .001, { before: before.yaw, after: after.yaw });
    await screenshot('overview-1200');

    await page.keyboard.press('Tab');
    await page.waitForFunction(() => !window.planetWorldState.overview);
    await page.waitForTimeout(700);
    check('Tab enters roaming', !(await state()).overview);
    before = await state();
    await screenshot('bearing-before-1200');
    const duringRoam = await leftDrag(150, 0);
    after = await state();
    check('Real left hold rotates roaming camera', duringRoam.dragging && difference(before.heading, after.heading) > .1, { before: before.heading, after: after.heading });
    check('Fixed-position turn keeps cartography orientation', difference(before.position, after.position) < .06 && difference(before.minimap_frame, after.minimap_frame) < .002, { position_delta: difference(before.position, after.position), frame_delta: difference(before.minimap_frame, after.minimap_frame) });
    check('Player arrow turns independently of cartography', dot(before.minimap_arrow, after.minimap_arrow) < .95, { before: before.minimap_arrow, after: after.minimap_arrow });
    await screenshot('bearing-after-1200');
    before = after;
    await page.mouse.move(1030, 510, { steps: 5 });
    await page.waitForTimeout(900);
    after = await state();
    check('Roaming release stops heading changes', !after.dragging && difference(before.heading, after.heading) < .001, { before: before.heading, after: after.heading });

    // A model turns into its movement direction for strafing/backtracking;
    // compare the arrow to observed world displacement, not camera heading.
    for (const key of ['w', 'a', 's', 'd']) {
      await page.keyboard.press('Home');
      await page.waitForTimeout(950);
      before = await state();
      await page.keyboard.down(key);
      await page.waitForTimeout(1050);
      await page.keyboard.up(key);
      await page.waitForTimeout(650);
      after = await state();
      const radial = unit(after.position);
      const motion = subtract(after.position, before.position);
      const tangent = unit(motion.map((value, i) => value - radial[i] * dot(motion, radial)));
      const mapRight = unit(cross(after.minimap_frame, radial));
      const expected = unit([dot(tangent, mapRight), -dot(tangent, after.minimap_frame)]);
      const agreement = dot(expected, after.minimap_arrow);
      check(`Real ${key.toUpperCase()} movement arrow matches model travel`, length(motion) > .12 && agreement > .9, { travel: length(motion), expected, arrow: after.minimap_arrow, agreement, camera_heading: after.heading });
      if (key === 'd') {
        const cameraOnMap = unit([dot(after.heading, mapRight), -dot(after.heading, after.minimap_frame)]);
        check('Sideways movement does not force arrow to camera heading', Math.abs(dot(after.minimap_arrow, cameraOnMap)) < .3, { arrow: after.minimap_arrow, camera_bearing: cameraOnMap });
        await screenshot('sidewalk-1200');
      }
    }

    before = await state();
    await clickDestinationToggle();
    after = await state();
    check('Destination UI opens without camera drag', after.destinations_open && !after.dragging && difference(before.heading, after.heading) < .001, { before_heading: before.heading, after_heading: after.heading, dragging: after.dragging });
    await screenshot('destinations-1200');
    await clickDestinationToggle();

    await page.setViewportSize({ width: 960, height: 640 });
    await page.waitForTimeout(1500);
    const narrowBox = await canvasBox();
    after = await state();
    check('Narrow desktop canvas remains visible', narrowBox.x >= 0 && narrowBox.y >= 0 && narrowBox.width <= 961 && narrowBox.height <= 641, narrowBox);
    check('Narrow desktop destination control remains onscreen', after.destination_button.every(value => value > 0 && value < 1), after.destination_button);
    await screenshot('roaming-960');
    before = after;
    await clickDestinationToggle();
    after = await state();
    check('Narrow desktop destination UI is usable without dragging', after.destinations_open && !after.dragging && difference(before.heading, after.heading) < .001, after);
    await screenshot('destinations-960');
    await clickDestinationToggle();
    await page.keyboard.press('Tab');
    await page.waitForFunction(() => window.planetWorldState.overview);
    await page.waitForTimeout(1000);
    check('Tab returns to overview at narrow desktop width', (await state()).overview);
    await screenshot('overview-960');
    report.passed = report.errors.length === 0 && report.checks.every(item => item.passed);
  } catch (error) {
    report.errors.push(String(error.stack || error));
  } finally {
    report.finished_at = new Date().toISOString();
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    await browser.close();
  }
  console.log('WORLD_POLISH_BROWSER_REVIEW', JSON.stringify({ passed: report.passed, checks: report.checks.length, failed: report.checks.filter(item => !item.passed).map(item => item.test), errors: report.errors, report: reportPath }));
  if (!report.passed) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
