// Release-build functional QA. Every game action is a mouse/key input.
// The browser only reads opt-in ?performance telemetry; no engine JS commands.
// NODE_PATH must contain Playwright. Usage: node tools/check_performance_browser.cjs URL [label] [local-release-json]
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const repo = path.resolve(__dirname, '..');
const url = new URL(process.argv[2] || 'http://127.0.0.1:8947/build/web/index.html');
if (!['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) {
  throw new Error('This QA runner is restricted to localhost; it does not verify the public deployment.');
}
url.searchParams.set('performance', '');
const label = (process.argv[3] || 'release-functional').replace(/[^a-zA-Z0-9_-]/g, '-');
const out = path.join(repo, 'deliverables', 'performance');
const localReleasePath = path.resolve(repo, process.argv[4] || '_site/index.release.json');
const localRelease = JSON.parse(fs.readFileSync(localReleasePath, 'utf8'));
if (typeof localRelease.build_id !== 'string' || !localRelease.build_id) throw new Error('Local release manifest has no build_id');
const projectConfig = fs.readFileSync(path.join(repo, 'game', 'project.godot'), 'utf8');
const baseViewport = {
  width: Number(projectConfig.match(/^window\/size\/viewport_width=(\d+)/m)?.[1]),
  height: Number(projectConfig.match(/^window\/size\/viewport_height=(\d+)/m)?.[1]),
};
const stretchAspect = projectConfig.match(/^window\/stretch\/aspect="([^"]+)"/m)?.[1] || 'keep';
if (!baseViewport.width || !baseViewport.height || stretchAspect !== 'keep') {
  throw new Error('QA input mapping expects the project\'s existing fixed-aspect Godot viewport');
}
const stations = JSON.parse(fs.readFileSync(path.join(repo, 'game', 'data', 'world_layout.json'), 'utf8')).stations;
fs.mkdirSync(out, { recursive: true });
const reportPath = path.join(out, `${label}.json`);
const report = {
  label, url: url.href, started: new Date().toISOString(), viewport: { width: 1200, height: 800 },
  checks: [], events: [], snapshots: [], errors: [], unmeasured: [],
  expected_release: {path:localReleasePath,build_id:localRelease.build_id,source_sha256:localRelease.source_sha256,pck:localRelease.files?.['index.pck']},
  godot_viewport: {...baseViewport,stretch_aspect:stretchAspect},
  method: 'Real Playwright mouse/keyboard inputs; read-only planetPerformance/trainingRoomState snapshots.',
};
let browser;
let browserServer;
let page;
let closing;
let requestedAbort = false;
let graphicsTouched = false;
const pressed = new Set();
const save = () => fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const closeBrowser = () => {
  if (!closing) closing = (async () => {
    // Own the launched browser server as well as its connection. This lets us
    // stop only this runner's browser if a page/renderer blocks normal closing.
    const killTimer = setTimeout(() => {
      if (browserServer) browserServer.kill().catch(() => {});
    }, 10000);
    try {
      if (browser) await browser.close().catch(() => {});
      if (browserServer) await browserServer.close().catch(() => {});
    } finally { clearTimeout(killTimer); }
  })();
  return closing;
};
const watchdog = setTimeout(() => {
  requestedAbort = true;
  report.errors.push('Outer 20-minute QA timeout. Partial evidence retained.');
  save();
  const forceExit = setTimeout(() => process.exit(1), 15000);
  closeBrowser().finally(() => { clearTimeout(forceExit); process.exit(1); });
}, 20 * 60 * 1000);

function check(name, passed, evidence = null) {
  report.checks.push({ name, passed: Boolean(passed), evidence, at: new Date().toISOString() });
  save();
  console.log(passed ? 'PASS' : 'FAIL', name);
  return passed;
}

async function snapshot(name = null) {
  const data = await page.evaluate(() => ({
    ready: window.planetWorldReady === true,
    metrics: window.planetPerformance || null,
    room: window.trainingRoomState || null,
    heap: performance.memory ? { used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize } : null,
  }));
  if (name) {
    report.snapshots.push({ name, ...data, at: new Date().toISOString() });
    save();
  }
  return data;
}

async function waitFor(description, predicate, timeout = 45000, afterTicks = -1) {
  const deadline = Date.now() + timeout;
  let last;
  do {
    if (requestedAbort) throw new Error('QA aborted');
    last = await snapshot();
    if ((afterTicks < 0 || (last.metrics?.ticks_ms ?? -1) > afterTicks) && predicate(last)) return last;
    await delay(700);
  } while (Date.now() < deadline);
  await snapshot(`timeout-${description}`);
  throw new Error(`Timed out waiting for ${description}; last state: ${JSON.stringify({metrics:last?.metrics,room:last?.room})}`);
}

const matches = (button, selector) => selector.name ? button.name === selector.name : selector.text.test(button.text || '');
const visibleButton = (state, selector) => (state.metrics?.buttons || []).find(b => matches(b, selector) && b.visible);
async function canvasBox() {
  const box = await page.locator('#canvas').boundingBox();
  if (!box?.width || !box?.height) throw new Error('Game canvas has no visible bounds');
  // Godot preserves the 1440:900 game content inside the CSS canvas. The
  // canvas itself still fills a tall phone browser; its black letterbox bars
  // are not part of the normalized viewport coordinates in telemetry.
  const scale = Math.min(box.width / baseViewport.width, box.height / baseViewport.height);
  const width = baseViewport.width * scale;
  const height = baseViewport.height * scale;
  return {x:box.x+(box.width-width)/2,y:box.y+(box.height-height)/2,width,height};
}

async function clickButton(selector, { scroll = false } = {}) {
  // The telemetry visibility flag includes ancestor clipping, so a scroll-list
  // row below the viewport is never mistaken for a real clickable button.
  for (let attempt = 0; attempt < (scroll ? 18 : 4); attempt++) {
    const state = await snapshot();
    const button = visibleButton(state, selector);
    const box = await canvasBox();
    if (button && button.center.every(n => n >= 0 && n <= 1)) {
      await page.mouse.click(box.x + button.center[0] * box.width, box.y + button.center[1] * box.height);
      await waitFor('fresh button result', s => Boolean(s.metrics), 30000, state.metrics.ticks_ms);
      return button;
    }
    if (!scroll) { await delay(1000); continue; }
    const target = (state.metrics?.buttons || []).find(b => matches(b, selector));
    const visibleRows = (state.metrics?.buttons || []).filter(b => b.visible && /^\d{2}\s/.test(b.text));
    const anchor = visibleRows[Math.floor(visibleRows.length / 2)]?.center || [0.13, 0.76];
    const direction = target && target.center[1] < anchor[1] ? -1 : 1;
    await page.mouse.move(box.x + box.width * anchor[0], box.y + box.height * anchor[1]);
    await page.mouse.wheel(0, direction * 180);
    await delay(1200);
  }
  throw new Error(`No clickable UI button: ${selector.name || selector.text}`);
}

async function screenshot(name) {
  await page.screenshot({ path: path.join(out, `${label}-${name}.png`), timeout: 60000 });
  await snapshot(name);
}

async function hold(keys, ms) {
  try {
    for (const key of keys) { await page.keyboard.down(key); pressed.add(key); }
    await delay(ms);
  } finally {
    for (const key of [...keys].reverse()) { await page.keyboard.up(key).catch(() => {}); pressed.delete(key); }
  }
}

async function waitWorld() {
  return waitFor('world ready with opt-in telemetry', s => s.ready && s.metrics?.buttons?.length && s.metrics?.player && !s.room, 300000);
}

async function verifyRelease(phase) {
  const metaBuild = await page.locator('meta[name="little-world-build"]').getAttribute('content');
  const releaseUrl = new URL('index.release.json', url);
  const response = await page.request.get(releaseUrl.href, {timeout:30000});
  if (!response.ok()) throw new Error(`Served release manifest failed: HTTP ${response.status()}`);
  const served = await response.json();
  const filesMatch = ['index.html','index.js','index.wasm','index.pck'].every(name =>
    served.files?.[name]?.bytes === localRelease.files?.[name]?.bytes &&
    served.files?.[name]?.sha256 === localRelease.files?.[name]?.sha256);
  const matchesExpected = metaBuild === localRelease.build_id && served.build_id === localRelease.build_id && filesMatch;
  check(`Current release identity (${phase})`, matchesExpected, {meta_build_id:metaBuild,served_build_id:served.build_id,manifest_files_match:filesMatch});
  if (!matchesExpected) throw new Error(`Release identity mismatch; expected ${localRelease.build_id}`);
}

async function openSettings() {
  const s = await snapshot();
  if (!s.metrics?.settings_open) await clickButton({ name: 'GraphicsSettingsButton' });
  return waitFor('settings open', s => s.metrics?.settings_open);
}

async function graphicsChoice(name, predicate) {
  graphicsTouched = true;
  await clickButton({ name });
  const s = await waitFor(name, s => predicate(s.metrics?.graphics || {}));
  check(name, true, s.metrics.graphics);
}

async function closeSettings() {
  await clickButton({ name: 'CloseGraphicsSettings' });
  await waitFor('settings closed', s => !s.metrics?.settings_open);
}

async function settingsRoute() {
  await openSettings();
  await graphicsChoice('RestoreGraphicsDefaults', g => g.msaa_enabled && g.applied_msaa === 1 && g.frame_limit === 60 && g.applied_max_fps === 60);
  await graphicsChoice('MSAAToggle', g => !g.msaa_enabled && g.applied_msaa === 0);
  await graphicsChoice('MSAAToggle', g => g.msaa_enabled && g.applied_msaa === 1);
  for (const fps of [30, 60, 90]) await graphicsChoice(`FPS${fps}`, g => g.frame_limit === fps && g.applied_max_fps === fps);
  await graphicsChoice('MSAAToggle', g => !g.msaa_enabled && g.applied_msaa === 0);
  await screenshot('settings-90-msaa-off');
  await closeSettings();
  await delay(2500); // Allow the Web user filesystem to finish its normal persistence work.
  await page.reload({ waitUntil: 'domcontentloaded', timeout: 180000 });
  await verifyRelease('persistence reload');
  const persisted = await waitWorld();
  check('Web reload persists 90 FPS / MSAA off', persisted.metrics.graphics.frame_limit === 90 && !persisted.metrics.graphics.msaa_enabled, persisted.metrics.graphics);
  await openSettings();
  await graphicsChoice('RestoreGraphicsDefaults', g => g.msaa_enabled && g.frame_limit === 60 && g.applied_msaa === 1 && g.applied_max_fps === 60);
  await closeSettings();
  await page.setViewportSize({ width: 390, height: 844 });
  await delay(2000);
  await openSettings();
  const mobile = await snapshot();
  check('390 px viewport exposes settings toggle and fixed close action', Boolean(visibleButton(mobile, {name:'MSAAToggle'})) && Boolean(visibleButton(mobile, {name:'CloseGraphicsSettings'})), mobile.metrics.buttons);
  await screenshot('settings-mobile-390');
  await closeSettings();
  await page.setViewportSize(report.viewport);
  await delay(2000);
}

async function destination(station) {
  let state = await snapshot();
  if (state.metrics?.settings_open) await closeSettings();
  if (!state.metrics?.destinations_open) await clickButton({ text: /選擇目的地/ });
  await waitFor('destination list open', s => s.metrics?.destinations_open);
  await clickButton({ text: new RegExp(`^\\d{2}\\s+${station.label}`) }, { scroll: true });
  state = await waitFor(`arrival at ${station.id}`, s => !s.metrics?.player?.overview && !s.metrics?.player?.entering && !s.metrics?.player?.paused && s.metrics?.nearest_id === station.id, 60000);
  if (state.metrics.destinations_open) {
    await clickButton({ text: /收起目的地/ });
    await waitFor('destination list closed', s => !s.metrics?.destinations_open);
  }
  return waitFor(`detail ready near ${station.id}`, s => s.metrics?.streaming?.active_regions > 0 && s.metrics?.streaming?.pending_regions === 0, 120000);
}

async function leaveTrainingRoom() {
  let state = await snapshot();
  if (!state.room?.ready) return;
  // Actual room controls: the spawn is at z=6.2, the exit at z=8.48.
  // S walks backwards toward the entrance; E returns when near the door.
  for (let i = 0; i < 8 && !state.room?.near_exit; i++) {
    await hold(['s'], 180);
    await delay(500);
    state = await snapshot();
  }
  if (!state.room?.near_exit) throw new Error('Room exit was not reached by real backwards movement');
  const before = state.metrics?.ticks_ms ?? -1;
  await page.keyboard.press('e');
  await waitFor('training room return', s => !s.room && !s.metrics?.player?.paused && !s.metrics?.player?.entering, 120000, before);
}

async function approachPortal(station) {
  // Streamed benches can become the nearest interaction after teleport.
  // Wait for the final detail state, then use the same small sidestep/forward
  // movement a player would use to reach the portal instead of pressing E
  // against whichever object happened to finish loading last. Source review:
  // refine_civic_plazas.gd keeps the portal's 1.5m center clear; civic benches
  // are 1.58m wide at side offsets >=2.55m. teleport_to() faces the portal.
  // At the authored 3.8m/s walk speed, A 350ms clears about 1.33m sideways and
  // W 400ms approaches about 1.52m. Telemetry must confirm the portal before E.
  await delay(1200);
  let state = await snapshot();
  if (state.metrics?.nearest_id === station.id) return state;
  await hold(['a'], 350);
  await hold(['w'], 400);
  for (let attempt = 0; attempt < 5; attempt++) {
    await delay(1200);
    state = await snapshot();
    if (state.metrics?.nearest_id === station.id) {
      check(`Walk around nearby seating to ${station.id} portal`, true, state.metrics.player);
      await screenshot(`portal-${station.id}`);
      return state;
    }
    await hold(['w'], 150);
  }
  throw new Error(`Could not reach ${station.id} portal using real movement; nearest=${state.metrics?.nearest_id}`);
}

async function stationRoute(station) {
  const arrived = await destination(station);
  check(`Teleport and load ${station.id}`, true, {player:arrived.metrics.player,streaming:arrived.metrics.streaming});
  await screenshot(`district-${station.id}`);
  await approachPortal(station);
  await page.keyboard.press('e');
  if (station.id === 'wordking') {
    const room = await waitFor('training room ready', s => s.room?.ready, 120000);
    check('Training room entry with E', true, room.room);
    await screenshot('training-room');
    await leaveTrainingRoom();
    check('Training room return with real movement and E', true, (await snapshot()).metrics.player);
  } else {
    const interaction = await waitFor(`${station.id} interaction`, s => s.metrics?.player?.paused && !s.metrics?.player?.entering, 60000);
    check(`${station.id} interaction opens`, true, interaction.metrics.player);
    await page.keyboard.press('Escape');
    const resumed = await waitFor(`${station.id} interaction closes`, s => !s.metrics?.player?.paused && !s.metrics?.player?.entering);
    check(`${station.id} interaction returns to outdoor world`, true, resumed.metrics.player);
  }
}

async function drag(dx, dy, steps = 3) {
  const box = await canvasBox();
  const x = box.x + box.width * .65;
  const y = box.y + box.height * .43;
  await page.mouse.move(x, y);
  await page.mouse.down({ button: 'right' });
  try { await page.mouse.move(x + dx, y + dy, { steps }); }
  finally { await page.mouse.up({ button: 'right' }); }
}

function dominantDistrict(position) {
  return stations.map(station => ({id:station.id,dot:station.normal.reduce((sum,n,i)=>sum+n*position[i],0)})).sort((a,b)=>b.dot-a.dot)[0].id;
}

async function cameraAndWalkingRoute() {
  await destination(stations[0]);
  for (const [dx, dy] of [[260, 70], [-290, -100], [220, 25], [-190, 5]]) await drag(dx, dy);
  await delay(2200);
  const turn = await snapshot();
  check('Fast camera turns retain a live near scene and obstruction telemetry', !turn.metrics.player.overview && Boolean(turn.metrics.obstruction), turn.metrics.obstruction);
  await screenshot('fast-camera');
  await destination(stations[0]); // Restore authored heading before the walking route.
  const start = await snapshot();
  const samples = [];
  for (let i = 0; i < 6; i++) {
    await hold(['Shift', 's'], 2000);
    samples.push(await snapshot());
  }
  const end = samples.at(-1);
  const a = start.metrics.player.position;
  const b = end.metrics.player.position;
  const distance = Math.hypot(...b.map((value, i) => value - a[i]));
  check('Real walking changes player position without falling below terrain', distance > 1 && samples.every(s => Math.hypot(...s.metrics.player.position) >= 47), {distance,start:a,end:b});
  const crossed = dominantDistrict(a) !== dominantDistrict(b);
  report.crosswalk = {crossed,from:dominantDistrict(a),to:dominantDistrict(b),samples};
  if (crossed) check('Walking crosses the nearest-district boundary', true, {from:dominantDistrict(a),to:dominantDistrict(b)});
  else report.unmeasured.push('Attempted 12-second real-input walking route did not cross a district boundary; do not count it as cross-district walking coverage.');
  await screenshot('walking-route');
  await page.keyboard.press('Home');
  await waitFor('Home teleport returns to counseling', s => s.metrics?.nearest_id === 'counseling' && !s.metrics?.player?.entering);
  await page.keyboard.press('Tab');
  await waitFor('overview after Tab', s => s.metrics?.player?.overview);
  await drag(160, 50, 12);
  await page.mouse.wheel(0, -250);
  await delay(3000);
  await screenshot('overview-rotate-zoom');
  check('Overview rotate/zoom stays active', (await snapshot()).metrics.player.overview);
}

async function repetitionRoute() {
  const samples = [];
  for (let iteration = 0; iteration < 3; iteration++) {
    await destination(stations[0]);
    const near = await snapshot(`repeat-${iteration}-near`);
    await page.keyboard.press('Tab');
    await waitFor('repeat overview', s => s.metrics?.player?.overview);
    const empty = await waitFor('overview detail unload', s => s.metrics?.streaming?.loaded_chunks === 0, 120000);
    samples.push({iteration,near:near.metrics,unloaded:empty.metrics,heap:empty.heap});
  }
  report.repeatedEntry = samples;
  check('Three repeated entries unload all detail chunks', samples.every(s => s.unloaded.streaming.loaded_chunks === 0), samples.map(s => ({iteration:s.iteration,nodes:s.unloaded.nodes,static_memory_bytes:s.unloaded.static_memory_bytes,heap:s.heap})));
  // Raw memory/node samples are evidence, not a promise of flat allocator/RSS.
  // Heap collection timing and native memory residency differ from live nodes.
  await screenshot('repeated-entry-unloaded');
}

(async () => {
  try {
    save();
    console.log('START', label, url.href);
    browserServer = await chromium.launchServer({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
    browser = await chromium.connect(browserServer.wsEndpoint());
    report.browser = browser.version();
    const context = await browser.newContext({viewport:report.viewport});
    page = await context.newPage();
    page.setDefaultTimeout(30000);
    page.on('pageerror', error => {report.errors.push(String(error));save();});
    page.on('console', message => {
      const text = message.text();
      if (/TRAINING_ROOM_(READY|ENTERED|RETURNED)/.test(text)) {report.events.push({text,at:new Date().toISOString()});save();}
      if ((message.type() === 'error' || /SCRIPT ERROR:|Parse Error:|SHADER ERROR:/.test(text)) && !text.includes('404 (File not found)')) {report.errors.push(text);save();}
    });
    await page.goto(url.href, {waitUntil:'domcontentloaded',timeout:180000});
    await verifyRelease('initial navigation');
    await waitWorld();
    console.log('READY', label);
    await screenshot('initial-overview');
    await settingsRoute();
    for (const station of stations) await stationRoute(station);
    await cameraAndWalkingRoute();
    await repetitionRoute();
  } catch (error) {
    report.errors.push(String(error.stack || error));
    if (page && !page.isClosed()) await screenshot('failure').catch(() => {});
  } finally {
    if (page && !page.isClosed() && !requestedAbort && graphicsTouched) {
      for (const key of pressed) await page.keyboard.up(key).catch(() => {});
      await page.mouse.up({button:'right'}).catch(() => {});
      try {
        await leaveTrainingRoom();
        const s = await snapshot();
        if (s.metrics?.player?.paused) await page.keyboard.press('Escape');
        await openSettings();
        await graphicsChoice('RestoreGraphicsDefaults', g => g.msaa_enabled && g.frame_limit === 60 && g.applied_msaa === 1 && g.applied_max_fps === 60);
        check('QA restores original graphics defaults', true, (await snapshot()).metrics.graphics);
      } catch (error) { report.errors.push(`Default restoration incomplete: ${error.message}`); }
    }
    report.finished = new Date().toISOString();
    report.passed = report.errors.length === 0 && report.checks.every(item => item.passed);
    save();
    await closeBrowser();
    clearTimeout(watchdog);
  }
  console.log(JSON.stringify({report:reportPath,passed:report.passed,checks:report.checks.length,errors:report.errors,unmeasured:report.unmeasured},null,2));
  process.exitCode = report.passed ? 0 : 1;
})().catch(async error => {
  report.errors.push(String(error.stack || error));
  save();
  await closeBrowser();
  clearTimeout(watchdog);
  process.exitCode = 1;
});
