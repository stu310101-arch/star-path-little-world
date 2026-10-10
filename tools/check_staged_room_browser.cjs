// Actual exported Web room lifecycle on an owned localhost HTTP server.
// Every game action is keyboard/mouse; page evaluation reads telemetry and
// resets only this runner's passive WebGL viewport observation buffer.
// Usage: NODE_PATH=<Playwright modules> node tools/check_staged_room_browser.cjs [_site] [label]
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const {once} = require('node:events');
const repo = path.resolve(__dirname, '..');
const source = path.resolve(repo, process.argv[2] || '_site');
const label = (process.argv[3] || 'staged-room-web').replace(/[^a-zA-Z0-9_-]/g, '-');
const output = path.join(repo, 'deliverables/low-memory');
fs.mkdirSync(output, {recursive: true});
const reportFile = path.join(output, label + '.json');
const release = JSON.parse(fs.readFileSync(path.join(source, 'index.release.json'), 'utf8'));
const manifest = JSON.parse(fs.readFileSync(path.join(source, 'index.packs.json'), 'utf8'));
const pack = manifest.packs.training_room;
if (!pack || pack.startup !== false) throw Error('Expected a non-startup training_room pack');
const roomPath = new URL(pack.url, 'http://localhost/').pathname;
const config = fs.readFileSync(path.join(repo, 'game/project.godot'), 'utf8');
const base = {width: Number(config.match(/^window\/size\/viewport_width=(\d+)/m)?.[1]),
  height: Number(config.match(/^window\/size\/viewport_height=(\d+)/m)?.[1])};
if (!base.width || !base.height || (config.match(/^window\/stretch\/aspect="([^"]+)"/m)?.[1] || 'keep') !== 'keep') throw Error('Unsupported viewport mapping');
const station = JSON.parse(fs.readFileSync(path.join(repo, 'game/data/world_layout.json'), 'utf8')).stations.find(row => row.id === 'wordking');
const report = {label, source, build_id: release.build_id, started: new Date().toISOString(),
  viewport: {width: 1200, height: 800}, checks: [], snapshots: [], requests: [], console: [], errors: [], screenshots: [],
  method: 'Fresh headed Chrome context, actual localhost HTTP 503 followed by a byte-gated room pack; ordinary game inputs, read-only opt-in telemetry, passive WebGL viewport observation with fresh samples after each resize.',
  limitations: ['No public deployment checked.', 'No persistent cache; HTTP no-store test fixture is a lifecycle test, not a network speed benchmark.',
    'Node/resource counters are not browser RSS or GPU memory. Mounted PCK is intentionally retained for page lifetime.']};
let server, browserServer, browser, page, closed, aborted = false, roomAttempts = 0;
let releaseBody;
const bodyGate = new Promise(resolve => {releaseBody = resolve;});
let gateOpened = false;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const held = new Set();
const save = () => fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));
function check(name, passed, evidence = null) {
  report.checks.push({name, passed: Boolean(passed), evidence, at: new Date().toISOString()});
  save(); console.log(passed ? 'PASS' : 'FAIL', name);
  if (!passed) throw Error(name);
}
function openGate(reason) {
  if (gateOpened) return;
  gateOpened = true; report.gate_released = {reason, epoch_ms: Date.now()}; releaseBody(); save();
}
async function close() {
  if (!closed) closed = (async () => {
    openGate('cleanup');
    const kill = setTimeout(() => browserServer?.kill().catch(() => {}), 10000);
    try {await browser?.close().catch(() => {}); await browserServer?.close().catch(() => {});}
    finally {clearTimeout(kill); if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}}
  })();
  return closed;
}
const watchdog = setTimeout(() => {
  aborted = true; report.errors.push('15 minute staged-room watchdog expired'); save();
  const force = setTimeout(() => process.exit(1), 15000);
  close().finally(() => {clearTimeout(force); process.exit(1);});
}, 15 * 60000);

async function startServer() {
  server = http.createServer(async (req, res) => {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    const target = path.resolve(source, '.' + decodeURIComponent(pathname));
    if (!target.startsWith(source + path.sep) || !fs.existsSync(target) || !fs.statSync(target).isFile()) {res.writeHead(404); res.end(); return;}
    const training = pathname === roomPath;
    const record = {path: pathname, training, started_epoch_ms: Date.now(), bytes: 0};
    report.requests.push(record); save();
    if (training && ++roomAttempts === 1) {
      record.status = 503; record.completed_epoch_ms = Date.now();
      res.writeHead(503, {'Content-Type': 'text/plain', 'Cache-Control': 'no-store'});
      res.end('Intentional room-pack retry test'); save(); return;
    }
    const types = {'.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.json': 'application/json',
      '.wasm': 'application/wasm', '.svg': 'image/svg+xml', '.png': 'image/png'};
    record.status = 200;
    res.writeHead(200, {'Content-Type': types[path.extname(target)] || 'application/octet-stream',
      'Content-Length': fs.statSync(target).size, 'Cache-Control': 'no-store'});
    const hash = crypto.createHash('sha256');
    let gateUsed = false;
    try {
      for await (const chunk of fs.createReadStream(target, {highWaterMark: 65536})) {
        if (res.destroyed) {record.aborted = true; break;}
        if (training && !gateUsed && record.bytes >= 65536) {
          gateUsed = true; record.gated_epoch_ms = Date.now(); save(); await bodyGate;
        }
        if (res.destroyed) {record.aborted = true; break;}
        hash.update(chunk); record.bytes += chunk.length;
        await new Promise((resolve, reject) => res.write(chunk, error => error ? reject(error) : resolve()));
      }
      if (!record.aborted) {record.sha256 = hash.digest('hex'); record.completed_epoch_ms = Date.now(); res.end();}
    } catch (error) {record.error = String(error); res.destroy();}
    save();
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  return `http://127.0.0.1:${server.address().port}/index.html?performance`;
}
async function state(name) {
  const value = await page.evaluate(() => ({metrics: window.planetPerformance || null, room: window.trainingRoomState || null,
    ready: window.planetWorldReady === true, all_ready: window.planetAllResourcesReady === true,
    gl: window.__stagedRoomGL?.snapshot() || null,
    build_id: document.querySelector('meta[name="little-world-build"]')?.content || null}));
  if (name) {report.snapshots.push({name, ...value, epoch_ms: Date.now()}); save();}
  return value;
}
async function until(name, predicate, timeout = 120000) {
  const deadline = Date.now() + timeout; let last;
  while (Date.now() < deadline) {
    if (aborted) throw Error('Aborted');
    last = await state(); if (predicate(last)) return last; await delay(400);
  }
  await state('timeout-' + name); throw Error(`Timed out: ${name}; ${JSON.stringify(last)}`);
}
async function screenshot(name) {
  const target = path.join(output, label + '-' + name + '.png');
  await page.screenshot({path: target, timeout: 60000}); report.screenshots.push(target); await state(name);
}
async function bounds() {
  const b = await page.locator('#canvas').boundingBox();
  if (!b?.width || !b?.height) throw Error('Canvas bounds missing');
  const scale = Math.min(b.width / base.width, b.height / base.height), width = base.width * scale, height = base.height * scale;
  return {x: b.x + (b.width - width) / 2, y: b.y + (b.height - height) / 2, width, height};
}
async function click(selector, {room = false, scroll = false} = {}) {
  const matches = button => typeof selector === 'string' ? button.name === selector : selector.test(button.text || '');
  for (let attempt = 0; attempt < (scroll ? 24 : 6); attempt++) {
    const s = await state(), buttons = (room ? s.room?.buttons : s.metrics?.buttons) || [], b = await bounds();
    const target = buttons.find(button => matches(button) && button.visible && button.center.every(n => n >= 0 && n <= 1));
    if (target) {
      const priorTick = room ? (s.room?.ticks_ms || 0) : (s.metrics?.ticks_ms || 0);
      await page.mouse.click(b.x + target.center[0] * b.width, b.y + target.center[1] * b.height);
      await delay(1200);
      await until('fresh UI result', value => (value.room?.ticks_ms || value.metrics?.ticks_ms || 0) > priorTick, 30000);
      return;
    }
    if (scroll) {
      const raw = buttons.find(matches), rows = buttons.filter(button => button.visible && /^\d{2}\s/.test(button.text));
      const anchor = rows[Math.floor(rows.length / 2)]?.center || [.13, .76];
      const direction = raw && raw.center[1] < anchor[1] ? -1 : 1;
      await page.mouse.move(b.x + b.width * anchor[0], b.y + b.height * anchor[1]); await page.mouse.wheel(0, direction * 170);
      await delay(1200);
      await until('fresh scroll geometry', value => (value.metrics?.ticks_ms || 0) > (s.metrics?.ticks_ms || 0), 30000);
    } else {
      await delay(1200);
    }
  }
  throw Error('UI control unavailable: ' + selector);
}
async function resizeRoom(stage, viewport) {
  const before = await state();
  const errorCount = report.errors.length;
  await page.setViewportSize(viewport);
  await delay(1200);
  let after = await until('room responds after resize ' + stage,
    value => value.room?.ready && value.room.ticks_ms > before.room.ticks_ms, 30000);
  const displacement = Math.hypot(...after.room.player.map((value, index) => value - before.room.player[index]));
  check('Room resize preserves position, low quality and live controls: ' + stage,
    after.room.room_instance_id === before.room.room_instance_id && after.room.low_quality &&
    displacement < .05 && after.room.player[1] > -.2 && report.errors.length === errorCount,
    {viewport, displacement, before: before.room, after: after.room});
  // Discard all GL dimensions from before/while the window was resizing.
  // This resets only the QA observer, never an engine rendering property.
  await page.evaluate(() => window.__stagedRoomGL.reset());
  const freshTick = after.room.ticks_ms;
  await delay(1200);
  after = await until('fresh GL viewport observations ' + stage,
    value => value.room?.ticks_ms > freshTick && value.gl?.sizes?.length >= 2, 30000);
  const backing = await page.locator('#canvas').evaluate(canvas => [canvas.width, canvas.height]);
  const graphics = after.room.graphics || {};
  const closeSize = (a, b) => Array.isArray(a) && Array.isArray(b) && a.length === 2 && b.length === 2 &&
    a.every((value, index) => Math.abs(value - b[index]) <= 1);
  const glSizes = after.gl.sizes.map(value => [value.width, value.height]);
  // Canvas CSS bounds include the focus border. Godot renders into the physical
  // backing store, with the authored aspect ratio preserved inside that store.
  const uiScale = Math.min(backing[0] / base.width, backing[1] / base.height);
  const uiSize = [Math.round(base.width * uiScale), Math.round(base.height * uiScale)];
  check('Room UI retains physical canvas resolution after resize: ' + stage,
    closeSize(graphics.ui_pixels, uiSize) && glSizes.some(size => closeSize(size, uiSize)),
    {viewport, canvas_backing_pixels: backing, expected_ui_pixels: uiSize, graphics, gl: after.gl});
  const internal = graphics.internal_3d_pixels;
  // Existing low-profile policy avoids a scaling pass when the reduction is
  // smaller than 20% per axis. The two actual fixture windows straddle it.
  const expected = {
    '1440x900': {scale:.8, pixels:[1152,720]},
    '1200x800': {scale:1, pixels:[1200,750]},
  }[`${viewport.width}x${viewport.height}`];
  if (!expected) throw Error('Add an explicit expected size for this resize fixture');
  check('Room actually renders the expected low 3D buffer after resize: ' + stage,
    graphics.quality_profile === 'low' && Math.abs(graphics.scaling_3d_scale-expected.scale)<.00001 &&
    closeSize(internal, expected.pixels) && glSizes.some(size => closeSize(size, expected.pixels)),
    {viewport, expected, graphics, gl: after.gl});
  await screenshot('resize-' + stage);
}
const roaming = s => !s.room && s.metrics?.avatar?.ready && !s.metrics.preparing_roam && s.metrics.player &&
  !s.metrics.player.overview && !s.metrics.player.entering && !s.metrics.player.paused;
async function hold(key, ms) {held.add(key); await page.keyboard.down(key); try {await delay(ms);} finally {await page.keyboard.up(key); held.delete(key);}}
async function destination() {
  let s = await state();
  if (!s.metrics?.destinations_open) await click(/選擇目的地/);
  await until('destinations open', s => s.metrics?.destinations_open);
  await click(new RegExp(`^\\d{2}\\s+${station.label}`), {scroll: true});
  await until('WordKing arrival', s => roaming(s) && s.metrics.nearest_id === 'wordking', 240000);
  s = await state(); if (s.metrics.destinations_open) await click(/收起目的地/);
  await until('destination detail settles', s => roaming(s) && s.metrics?.streaming?.pending_regions === 0, 180000);
}
async function enter() {
  await destination();
  for (let step = 0; step < 6; step++) {
    if ((await state()).metrics?.nearest_id === 'wordking') break;
    if (!step) await hold('a', 350); await hold('w', step ? 150 : 400); await delay(600);
  }
  check('Portal interaction remains available', (await state()).metrics?.nearest_id === 'wordking');
  await page.keyboard.press('e');
  return until('playable lightweight room', s => s.room?.ready, 180000);
}
async function leave() {
  const before = (await state()).metrics?.ticks_ms || 0;
  await click('ReturnToWorld', {room: true});
  return until('return to world', s => roaming(s) && s.metrics.ticks_ms > before, 180000);
}
async function releaseFence(stage) {
  const expectedFiles = ['index.html', 'index.js', 'index.wasm', 'index.pck'];
  for (const name of expectedFiles) {
    const bytes = fs.readFileSync(path.join(source, name)), expected = release.files[name];
    if (bytes.length !== expected.bytes || crypto.createHash('sha256').update(bytes).digest('hex') !== expected.sha256) throw Error('Local release changed: ' + name);
  }
  const served = await (await page.request.get(new URL('index.release.json', report.url).href)).json();
  const current = await state();
  check('Release identity ' + stage, served.build_id === release.build_id && current.build_id === release.build_id &&
    expectedFiles.every(name => served.files[name].sha256 === release.files[name].sha256));
}

(async () => {
  try {
    report.url = await startServer();
    browserServer = await chromium.launchServer({channel: 'chrome', headless: false, args: ['--disable-backgrounding-occluded-windows']});
    browser = await chromium.connect(browserServer.wsEndpoint());
    report.browser = browser.version();
    const context = await browser.newContext({viewport: report.viewport, deviceScaleFactor: 1});
    await context.addInitScript(() => {
      let observations = new Map();
      let since = performance.now();
      window.__stagedRoomGL = {
        reset() {observations = new Map(); since = performance.now();},
        snapshot() {return {since_ms: since, sizes: [...observations.values()]};},
      };
      for (const type of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
        if (!type || !Object.prototype.hasOwnProperty.call(type.prototype, 'viewport')) continue;
        const original = type.prototype.viewport;
        type.prototype.viewport = function(x, y, width, height) {
          const result = original.apply(this, arguments);
          if (this.canvas?.id === 'canvas') {
            const key = `${x},${y},${width},${height}`;
            if (observations.has(key)) observations.get(key).calls++;
            else if (observations.size < 64) observations.set(key, {x, y, width, height, calls: 1,
              drawing_buffer: [this.drawingBufferWidth, this.drawingBufferHeight]});
          }
          return result;
        };
      }
    });
    page = await context.newPage(); page.setDefaultTimeout(30000);
    page.on('pageerror', error => {report.errors.push(String(error)); save();});
    page.on('console', message => {
      report.console.push({type: message.type(), text: message.text(), location: message.location()});
      let errorPath = '';
      try {errorPath = new URL(message.location().url).pathname;} catch {}
      const expected = errorPath === roomPath && /503/.test(message.text());
      const favicon = errorPath.endsWith('/favicon.ico') && /404/.test(message.text());
      if (message.type() === 'error' && !expected && !favicon) report.errors.push(message.text());
    });
    await page.goto(report.url, {waitUntil: 'domcontentloaded', timeout: 180000});
    await until('outdoor startup complete', s => s.ready && s.all_ready && s.metrics?.buttons?.length, 300000);
    await releaseFence('before');
    check('Startup never requests the complete indoor pack', roomAttempts === 0);
    // The first post-startup sample can precede the final HUD layout. Wait for
    // fresh geometry, then verify the panel actually opened before its controls.
    await page.bringToFront();
    const startupTick = (await state()).metrics.ticks_ms;
    await delay(1200);
    await until('settled startup HUD', s => s.metrics?.ticks_ms > startupTick);
    report.settings_open_attempts = 0;
    for (let attempt = 0; attempt < 3 && !(await state()).metrics?.settings_open; attempt++) {
      report.settings_open_attempts++;
      await click('GraphicsSettingsButton');
    }
    await until('graphics settings panel open', s => s.metrics?.settings_open, 10000);
    await click('QualityLow'); await click('CloseGraphicsSettings');
    const first = await enter();
    check('First entry alone requests room pack and leaves safe light scene on HTTP 503', roomAttempts === 1 && first.room.detail_state !== 'ready');
    const failed = await until('room download failure', s => s.room?.detail_state === 'error');
    check('Failed room is playable with all original mesh identities', failed.room.ready && failed.room.mesh_contract.count === 152 && failed.room.low_quality, failed.room);
    await screenshot('light-failure');
    await click('RetryRoomDetails', {room: true});
    await until('retry starts real byte-gated HTTP response', s => s.room?.detail_state === 'waiting' && report.requests.some(r => r.training && r.gated_epoch_ms));
    await resizeRoom('light-waiting', {width: 1440, height: 900});
    await resizeRoom('light-restored', report.viewport);
    const heldRoom = await state('held-room');
    const beforeMove = heldRoom.room.player;
    await hold('w', 250); await delay(600);
    const moved = await state();
    check('Lightweight room movement remains supported during download', Math.hypot(...moved.room.player.map((n, i) => n - beforeMove[i])) > .15 && moved.room.player[1] > -.2, {before: beforeMove, after: moved.room.player});
    await leave();
    check('Return works while room bytes are held', !gateOpened && !(await state()).room && roomAttempts === 2);
    openGate('player returned outdoors');
    await until('late pack mounts outdoors', s => s.metrics?.packs?.pack_timings?.training_room?.ready_ms > 0, 180000);
    const outside = await state('late-complete-outdoors');
    check('Late completion never recreates an indoor scene outdoors', !outside.room && roaming(outside));
    const transferred = report.requests.find(r => r.training && r.status === 200 && r.completed_epoch_ms);
    check('Complete room body preserves exact byte count and SHA-256', transferred?.bytes === pack.bytes && transferred?.sha256 === pack.sha256, transferred);
    const second = await enter();
    check('Reentry is a new safe scene and reuses the mounted pack', roomAttempts === 2 && second.room.room_instance_id !== heldRoom.room.room_instance_id);
    const contract = second.room.mesh_contract;
    const full = await until('full room ready', s => s.room?.detail_state === 'ready', 180000);
    check('Detail replacement preserves live mesh IDs and transforms', full.room.mesh_contract.ids === contract.ids && full.room.mesh_contract.transforms === contract.transforms, {before: contract, after: full.room.mesh_contract});
    check('Full room inherits low quality', full.room.low_quality && full.room.detail_index === 152, full.room);
    await resizeRoom('full-ready', {width: 1440, height: 900});
    await resizeRoom('full-restored', report.viewport);
    await screenshot('detail-ready');
    await leave();
    const cycles = [];
    for (let cycle = 0; cycle < 2; cycle++) {
      const value = await enter(); await leave(); const result = await state('quick-cycle-' + cycle);
      cycles.push({room_id: value.room.room_instance_id, nodes: result.metrics.nodes, resources: result.metrics.resources, packs: result.metrics.packs});
    }
    check('Rapid reentry adds no download jobs or extra room requests', roomAttempts === 2 &&
      !(await state()).room && cycles.every(c => c.packs.queued_packs === 0), cycles);
    await releaseFence('after');
  } catch (error) {
    report.errors.push(String(error.stack || error));
    if (page && !page.isClosed()) await screenshot('failure').catch(() => {});
  } finally {
    for (const key of held) await page?.keyboard.up(key).catch(() => {});
    report.finished = new Date().toISOString(); report.passed = report.errors.length === 0 && report.checks.every(item => item.passed); save();
    await close(); clearTimeout(watchdog);
    console.log(JSON.stringify({report: reportFile, passed: report.passed, checks: report.checks.length, errors: report.errors}, null, 2));
    process.exitCode = report.passed ? 0 : 1;
  }
})().catch(async error => {report.errors.push(String(error.stack || error)); save(); await close(); clearTimeout(watchdog); process.exitCode = 1;});
