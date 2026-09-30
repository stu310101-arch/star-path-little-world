const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

// Additive regression suite: check_world_polish_browser.cjs retains its full
// minimap, WASD, destination UI, and responsive controls coverage unchanged.
const output = path.resolve(__dirname, '../deliverables');
const reportPath = path.join(output, 'visible-drag-browser-review.json');
const url = process.env.WORLD_PREVIEW_URL || 'http://127.0.0.1:8765/index.html?visible-drag';
const report = { started_at: new Date().toISOString(), url, passed: false, checks: [], errors: [], screenshots: [], drags: [] };
const difference = (a, b) => Math.hypot(...a.map((value, i) => value - b[i]));
const yawDelta = (after, before) => Math.atan2(Math.sin(after - before), Math.cos(after - before));
function check(test, passed, evidence) {
  report.checks.push({ test, passed: Boolean(passed), evidence });
  if (!passed) console.error('CHECK_FAILED', test, JSON.stringify(evidence));
}

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const inputSource = fs.readFileSync(path.resolve(__dirname, '../game/scripts/world.gd'), 'utf8').replace(/#.*$/gm, '');
  check('Input source has no cursor capture, confinement, hiding, or native warp', !/Input\.warp_mouse\s*\(|MOUSE_MODE_(?:CAPTURED|CONFINED(?:_HIDDEN)?|HIDDEN)\b/.test(inputSource));
  const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 800 } });
    page.setDefaultTimeout(30000);
    await page.addInitScript(() => {
      window.visibleDragAudit = { pointer_lock_requests: 0, pointer_lock_entries: 0, pointer_lock_changes: 0, moves: [], last_move: null };
      const original = Element.prototype.requestPointerLock;
      if (original) Element.prototype.requestPointerLock = function (...args) {
        window.visibleDragAudit.pointer_lock_requests += 1;
        return original.apply(this, args);
      };
      document.addEventListener('pointerlockchange', () => {
        window.visibleDragAudit.pointer_lock_changes += 1;
        if (document.pointerLockElement) window.visibleDragAudit.pointer_lock_entries += 1;
      });
      document.addEventListener('mousemove', event => {
        const point = { x: event.clientX, y: event.clientY, buttons: event.buttons, at: performance.now() };
        window.visibleDragAudit.last_move = point;
        window.visibleDragAudit.moves.push(point);
        if (window.visibleDragAudit.moves.length > 2000) window.visibleDragAudit.moves.shift();
      }, true);
    });
    page.on('pageerror', error => report.errors.push(String(error)));
    page.on('console', message => {
      if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) report.errors.push(message.text());
    });
    page.on('response', response => {
      if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) report.errors.push(`${response.status()} ${response.url()}`);
    });
    const state = () => page.evaluate(() => window.planetWorldState);
    const cursor = () => page.evaluate(() => {
      const audit = window.visibleDragAudit;
      const at = audit.last_move;
      const hit = at ? document.elementFromPoint(at.x, at.y) : document.querySelector('#canvas');
      return { locked: Boolean(document.pointerLockElement), requests: audit.pointer_lock_requests, entries: audit.pointer_lock_entries, last_move: at, css_cursor: hit ? getComputedStyle(hit).cursor : null };
    });
    const screenshot = async name => {
      const filename = path.join(output, `visible-drag-${name}.png`);
      await page.screenshot({ path: filename, timeout: 60000 });
      report.screenshots.push(filename);
    };
    await page.goto(url);
    await page.waitForFunction(() => window.planetWorldState, null, { timeout: 240000 });
    await page.waitForFunction(() => {
      const state = window.planetWorldState;
      return Number.isFinite(state.camera_distance) && Number.isFinite(state.camera_fov) && Number.isFinite(state.mouse_mode)
        && Array.isArray(state.globe_screen_center) && Array.isArray(state.globe_origin) && Array.isArray(state.globe_basis);
    });
    await page.waitForTimeout(1400);
    const canvas = await page.locator('#canvas').boundingBox();
    if (!canvas) throw new Error('Visible game canvas is missing');
    const start = { x: canvas.x + canvas.width * .44, y: canvas.y + canvas.height * .47 };
    const finish = { x: canvas.x + canvas.width * .82, y: start.y };
    const original = await state();
    check('Overview initially active', original.overview, original);

    function inspectOrbit(test, samples) {
      const maxDistanceChange = Math.max(...samples.map(sample => Math.abs(sample.camera_distance - original.camera_distance)));
      const maxFovChange = Math.max(...samples.map(sample => Math.abs(sample.camera_fov - original.camera_fov)));
      const maxCenterChange = Math.max(...samples.map(sample => difference(sample.globe_screen_center, original.globe_screen_center)));
      const maxOriginChange = Math.max(...samples.map(sample => difference(sample.globe_origin, original.globe_origin)));
      const maxBasisChange = Math.max(...samples.map(sample => difference(sample.globe_basis, original.globe_basis)));
      check(`${test}: orbit radius and FOV remain fixed`, maxDistanceChange < .02 && maxFovChange < .001, { max_distance_change: maxDistanceChange, max_fov_change: maxFovChange, distance: original.camera_distance, fov: original.camera_fov });
      check(`${test}: globe screen centre remains fixed`, maxCenterChange < .0015, { max_center_change: maxCenterChange, centre: original.globe_screen_center });
      check(`${test}: globe transform remains fixed`, maxOriginChange < .00001 && maxBasisChange < .00001, { max_origin_change: maxOriginChange, max_basis_change: maxBasisChange });
    }

    async function drag(button, ordinal, overview) {
      const resting = await state();
      await page.mouse.move(start.x, start.y, { steps: 6 });
      await page.waitForTimeout(450);
      const before = await state();
      check(`${button} ${ordinal}: pointer reposition alone does not rotate`, overview ? Math.abs(yawDelta(before.yaw, resting.yaw)) < .001 : difference(before.heading, resting.heading) < .001);
      await page.mouse.down({ button });
      await page.waitForFunction(() => window.planetWorldState.dragging);
      const samples = [await state()];
      const cursorSamples = [await cursor()];
      for (let step = 1; step <= 12; step += 1) {
        await page.mouse.move(start.x + (finish.x - start.x) * step / 12, finish.y);
        await page.waitForTimeout(65);
        if (step % 3 === 0) {
          samples.push(await state());
          cursorSamples.push(await cursor());
        }
      }
      await page.waitForTimeout(400);
      const held = await state();
      samples.push(held);
      cursorSamples.push(await cursor());
      check(`${button} ${ordinal}: only held drag rotates`, held.dragging && (overview ? Math.abs(yawDelta(held.yaw, before.yaw)) > .1 : difference(held.heading, before.heading) > .1), { before: overview ? before.yaw : before.heading, held: overview ? held.yaw : held.heading });
      check(`${button} ${ordinal}: cursor remains visible while held`, samples.every(sample => sample.mouse_mode === 0) && cursorSamples.every(sample => !sample.locked && sample.requests === 0 && sample.entries === 0 && sample.css_cursor !== 'none'), { mouse_modes: samples.map(sample => sample.mouse_mode), cursor_samples: cursorSamples });
      await page.mouse.up({ button });
      await page.waitForFunction(() => !window.planetWorldState.dragging);
      await page.waitForTimeout(500);
      const released = await state();
      const releasedCursor = await cursor();
      check(`${button} ${ordinal}: releasing does not warp cursor`, releasedCursor.last_move && Math.hypot(releasedCursor.last_move.x - finish.x, releasedCursor.last_move.y - finish.y) <= 1.5 && released.mouse_mode === 0, { expected: finish, actual: releasedCursor.last_move, mouse_mode: released.mouse_mode });
      await page.mouse.move(finish.x + 30, finish.y + 25, { steps: 5 });
      await page.waitForTimeout(550);
      const idle = await state();
      check(`${button} ${ordinal}: release stops rotation and unlocked motion`, !idle.dragging && (overview ? Math.abs(yawDelta(idle.yaw, released.yaw)) < .001 && Math.abs(idle.pitch - released.pitch) < .001 : difference(idle.heading, released.heading) < .001), { released: overview ? [released.yaw, released.pitch] : released.heading, idle: overview ? [idle.yaw, idle.pitch] : idle.heading });
      if (overview) inspectOrbit(`${button} ${ordinal}`, [...samples, released, idle]);
      else check(`${button} ${ordinal}: roaming rotation never zooms`, samples.every(sample => Math.abs(sample.camera_distance-before.camera_distance)<.02 && Math.abs(sample.camera_fov-before.camera_fov)<.001), { distance: before.camera_distance, samples: samples.map(sample => [sample.camera_distance,sample.camera_fov]) });
      const evidence = { button, ordinal, overview, yaw_delta: yawDelta(held.yaw, before.yaw), before, held, released, idle };
      report.drags.push(evidence);
      return evidence;
    }

    for (const button of ['left', 'right']) {
      let total = 0;
      let attempts = 0;
      while (Math.abs(total) < Math.PI * 2 && attempts < 8) {
        const evidence = await drag(button, attempts + 1, true);
        total += evidence.yaw_delta;
        attempts += 1;
      }
      check(`${button}: repeated visible drags complete a full 360 degree orbit`, Math.abs(total) >= Math.PI * 2, { accumulated_radians: total, accumulated_degrees: total * 180 / Math.PI, drags: attempts });
      await screenshot(`overview-${button}-360`);
    }
    const finalAudit = await cursor();
    check('No pointer lock was requested or entered during overview', finalAudit.requests === 0 && finalAudit.entries === 0 && !finalAudit.locked, finalAudit);
    await page.keyboard.press('Tab');
    await page.waitForFunction(() => !window.planetWorldState.overview);
    await page.waitForTimeout(700);
    await drag('left', 'roaming', false);
    await drag('right', 'roaming', false);
    await screenshot('roaming-visible-cursor');
    const finalState = await state();
    const endingAudit = await cursor();
    check('Cursor finishes visible, unlocked, and released', finalState.mouse_mode === 0 && !finalState.dragging && endingAudit.requests === 0 && endingAudit.entries === 0 && !endingAudit.locked && endingAudit.css_cursor !== 'none', endingAudit);
    report.passed = report.errors.length === 0 && report.checks.every(item => item.passed);
  } catch (error) {
    report.errors.push(String(error.stack || error));
  } finally {
    report.finished_at = new Date().toISOString();
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    await browser.close();
  }
  console.log('VISIBLE_DRAG_BROWSER_REVIEW', JSON.stringify({ passed: report.passed, checks: report.checks.length, failed: report.checks.filter(item => !item.passed).map(item => item.test), errors: report.errors, report: reportPath }));
  if (!report.passed) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
