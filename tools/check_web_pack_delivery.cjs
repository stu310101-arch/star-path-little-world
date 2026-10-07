// Localhost delivery failure/retry QA. Production state is read-only telemetry;
// all gameplay actions are real mouse/keyboard input. No persistent cache added.
// NODE_PATH must include Playwright. Usage: node tools/check_web_pack_delivery.cjs URL [label]
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const localHosts = new Set(['localhost', '127.0.0.1', '[::1]']);
const url = new URL(process.argv[2] || 'http://127.0.0.1:8947/_site/index.html');
if (!localHosts.has(url.hostname)) throw new Error('Delivery QA is restricted to localhost.');
url.searchParams.set('performance', '');
const label = (process.argv[3] || 'web-delivery').replace(/[^a-zA-Z0-9_-]/g, '-');
const repo = path.resolve(__dirname, '..');
const out = path.join(repo, 'deliverables', 'startup-packs');
fs.mkdirSync(out, { recursive: true });
const reportPath = path.join(out, `${label}.json`);
const config = fs.readFileSync(path.join(repo, 'game', 'project.godot'), 'utf8');
const baseViewport = {
  width: Number(config.match(/^window\/size\/viewport_width=(\d+)/m)?.[1]),
  height: Number(config.match(/^window\/size\/viewport_height=(\d+)/m)?.[1]),
};
if (!baseViewport.width || !baseViewport.height ||
    (config.match(/^window\/stretch\/aspect="([^"]+)"/m)?.[1] || 'keep') !== 'keep') {
  throw new Error('QA mapping requires the project fixed-aspect viewport.');
}
const report = {
  url: url.href, label, started: new Date().toISOString(), viewport: { width: 1200, height: 800 },
  godot_viewport: baseViewport, checks: [], snapshots: [], requests: [], console: [],
  expected_failures: [], errors: [], screenshots: [],
  method: 'Fresh Chrome context; first avatar HTTP response replaced with 503; real keyboard/mouse; read-only planetPerformance.',
  limitations: [
    'The first rAF after world-ready is a browser callback, not a measured physical display presentation.',
    'Avatar readiness/stage and withheld pack bytes establish deferred resource construction; individual GPU texture origins are not instrumented.',
    'Request interception disables the browser HTTP cache for this failure fixture; it is not a cache or bandwidth benchmark.',
  ],
};
let browserServer, browser, page, closing, manifest, avatarUrl;
let avatarAttempts = 0;
let aborted = false;
const pressed = new Set();
const network = new Map();
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const save = () => {
  report.requests = [...network.values()];
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
};
const closeBrowser = () => {
  if (!closing) closing = (async () => {
    const force = setTimeout(() => browserServer?.kill().catch(() => {}), 10000);
    try {
      if (browser) await browser.close().catch(() => {});
      if (browserServer) await browserServer.close().catch(() => {});
    } finally { clearTimeout(force); }
  })();
  return closing;
};
const watchdog = setTimeout(() => {
  aborted = true;
  report.errors.push('Outer 8-minute delivery QA watchdog expired; partial evidence retained.');
  report.passed = false;
  save();
  const exit = setTimeout(() => process.exit(1), 15000);
  closeBrowser().finally(() => { clearTimeout(exit); process.exit(1); });
}, 8 * 60 * 1000);

function check(name, passed, evidence = null) {
  report.checks.push({ name, passed: Boolean(passed), evidence, at: new Date().toISOString() });
  save();
  console.log(passed ? 'PASS' : 'FAIL', name);
  return passed;
}
async function snapshot(name) {
  const value = await page.evaluate(() => ({
    ready: window.planetWorldReady === true,
    metrics: window.planetPerformance || null,
    room: window.trainingRoomState || null,
    clock: window.__deliveryClock || null,
    build_id: document.querySelector('meta[name="little-world-build"]')?.content || null,
    now: performance.now(), time_origin: performance.timeOrigin,
  }));
  if (name) { report.snapshots.push({ name, ...value }); save(); }
  return value;
}
async function waitFor(name, predicate, timeout = 30000, afterTicks = -1) {
  const deadline = Date.now() + timeout;
  let last;
  while (Date.now() <= deadline) {
    if (aborted) throw new Error('Delivery QA aborted.');
    last = await snapshot();
    if ((afterTicks < 0 || (last.metrics?.ticks_ms ?? -1) > afterTicks) && predicate(last)) return last;
    await sleep(400);
  }
  await snapshot(`timeout-${name}`);
  throw new Error(`Timed out: ${name}; last metrics: ${JSON.stringify(last?.metrics)}`);
}
async function capture(name) {
  const file = path.join(out, `${label}-${name}.png`);
  await page.screenshot({ path: file, timeout: 30000 });
  report.screenshots.push(file);
  await snapshot(name);
}
async function key(keyName) {
  try {
    pressed.add(keyName);
    await page.keyboard.down(keyName);
    await sleep(80);
  } finally {
    await page.keyboard.up(keyName).catch(() => {});
    pressed.delete(keyName);
  }
}
async function clickRetry() {
  const state = await waitFor('visible retry button', s => s.metrics?.buttons?.some(b => b.visible && b.text === '重新下載'));
  const button = state.metrics.buttons.find(b => b.visible && b.text === '重新下載');
  if (!button.center.every(n => Number.isFinite(n) && n >= 0 && n <= 1)) throw new Error('Retry telemetry has invalid coordinates.');
  const canvas = await page.locator('#canvas').boundingBox();
  if (!canvas?.width || !canvas?.height) throw new Error('Game canvas has no bounds.');
  const scale = Math.min(canvas.width / baseViewport.width, canvas.height / baseViewport.height);
  const width = baseViewport.width * scale, height = baseViewport.height * scale;
  await page.mouse.click(canvas.x + (canvas.width - width) / 2 + button.center[0] * width,
    canvas.y + (canvas.height - height) / 2 + button.center[1] * height);
  return state.metrics.ticks_ms;
}
function distance(a, b) { return Math.hypot(...a.map((value, index) => value - b[index])); }

(async () => {
  try {
    save();
    browserServer = await chromium.launchServer({ channel: 'chrome', headless: true });
    browser = await chromium.connect(browserServer.wsEndpoint());
    report.browser = browser.version();
    const context = await browser.newContext({ viewport: report.viewport });
    const manifestResponse = await context.request.get(new URL('index.packs.json', url).href, { timeout: 30000 });
    if (!manifestResponse.ok()) throw new Error(`Pack manifest returned HTTP ${manifestResponse.status()}`);
    manifest = await manifestResponse.json();
    if (!manifest.packs?.avatar?.url) throw new Error('Pack manifest has no avatar group.');
    avatarUrl = new URL(manifest.packs.avatar.url, url).href;
    report.pack_manifest = manifest;
    await context.route('**/*', async route => {
      const requestUrl = new URL(route.request().url());
      if (['http:', 'https:'].includes(requestUrl.protocol) && !localHosts.has(requestUrl.hostname)) {
        report.errors.push(`Unexpected external request blocked: ${requestUrl.href}`);
        save();
        await route.abort('blockedbyclient');
      } else if (requestUrl.href === avatarUrl && ++avatarAttempts === 1) {
        report.expected_failures.push({ url: requestUrl.href, status: 503, at: new Date().toISOString() });
        save();
        await route.fulfill({ status: 503, contentType: 'text/plain', body: 'Intentional localhost avatar-pack retry fixture.' });
      } else {
        await route.continue();
      }
    });
    page = await context.newPage();
    page.setDefaultTimeout(30000);
    page.on('pageerror', error => { report.errors.push(String(error)); save(); });
    page.on('console', message => {
      const text = message.text(), source = message.location().url || '';
      report.console.push({ type: message.type(), text, url: source });
      const expected = source === avatarUrl && /503/.test(text);
      const favicon = /favicon\.ico/.test(source) && /404/.test(text);
      if (!expected && !favicon && (message.type() === 'error' || /SCRIPT ERROR:|Parse Error:|SHADER ERROR:/.test(text))) report.errors.push(text);
      save();
    });
    const cdp = await context.newCDPSession(page);
    await cdp.send('Network.enable');
    cdp.on('Network.requestWillBeSent', event => {
      network.set(event.requestId, { id: event.requestId, url: event.request.url,
        kind: event.type, start_monotonic_seconds: event.timestamp, start_epoch_ms: event.wallTime * 1000,
        decoded_body_bytes: 0, encoded_body_bytes: 0 });
    });
    cdp.on('Network.responseReceived', event => {
      const item = network.get(event.requestId);
      if (item) Object.assign(item, { status: event.response.status, mime: event.response.mimeType,
        response_monotonic_seconds: event.timestamp, from_disk_cache: Boolean(event.response.fromDiskCache),
        from_service_worker: Boolean(event.response.fromServiceWorker),
        content_encoding: event.response.headers['Content-Encoding'] || event.response.headers['content-encoding'] || null });
    });
    cdp.on('Network.dataReceived', event => {
      const item = network.get(event.requestId);
      if (item) { item.decoded_body_bytes += event.dataLength; item.encoded_body_bytes += event.encodedDataLength; }
    });
    cdp.on('Network.loadingFinished', event => {
      const item = network.get(event.requestId);
      if (item) Object.assign(item, { end_monotonic_seconds: event.timestamp, transferred_bytes_with_headers: event.encodedDataLength });
    });
    cdp.on('Network.loadingFailed', event => {
      const item = network.get(event.requestId);
      if (item) Object.assign(item, { failed: event.errorText, cancelled: event.canceled });
    });
    await page.addInitScript(() => {
      const clock = window.__deliveryClock = { time_origin: performance.timeOrigin, world_ready_ms: null, first_raf_after_ready_ms: null };
      addEventListener('planet-world-ready', () => { clock.world_ready_ms ??= performance.now(); });
      const frame = () => {
        if (window.planetWorldReady && clock.first_raf_after_ready_ms === null) clock.first_raf_after_ready_ms = performance.now();
        if (clock.first_raf_after_ready_ms === null) requestAnimationFrame(frame);
      };
      requestAnimationFrame(frame);
    });
    console.log('START', label, url.href);
    await page.goto(url.href, { waitUntil: 'domcontentloaded', timeout: 120000 });
    const initial = await waitFor('overview despite failed avatar pack', s => s.ready && s.metrics?.overview &&
      s.metrics?.packs?.errors?.avatar && s.clock?.first_raf_after_ready_ms !== null, 180000);
    report.startup = initial.clock;
    report.build_id = initial.build_id;
    check('First avatar request deliberately failed without blocking overview', avatarAttempts === 1 && initial.metrics.packs.enabled && !initial.room,
      { attempts: avatarAttempts, avatar_error: initial.metrics.packs.errors.avatar, clock: initial.clock });
    check('Overview defers avatar construction and all full-detail chunks', initial.metrics.avatar.stage === 1 &&
      !initial.metrics.avatar.ready && initial.metrics.streaming.loaded_chunks === 0, { avatar: initial.metrics.avatar, streaming: initial.metrics.streaming });
    const firstRafEpoch = initial.clock.time_origin + initial.clock.first_raf_after_ready_ms;
    const deferredRequests = [...network.values()].filter(item => new URL(item.url).pathname.includes('/packs/') && /\.pck$/.test(new URL(item.url).pathname));
    check('Full resource download starts during boot before the first world frame', initial.metrics.packs.all_requested &&
      initial.metrics.packs.total_packs === Object.keys(manifest.packs).length && deferredRequests.some(item => item.start_epoch_ms < firstRafEpoch),
      deferredRequests.map(item => ({ url: item.url, after_first_raf_ms: item.start_epoch_ms - firstRafEpoch })));
    await capture('overview-avatar-failed');

    await key('Tab');
    const blocked = await waitFor('roam waits for failed avatar', s => s.metrics?.preparing_roam && s.metrics.overview &&
      !s.metrics.avatar.ready && s.metrics.avatar.error && s.metrics.buttons.some(b => b.visible && b.text === '重新下載'));
    check('Tab opens preparation while preserving the overview', blocked.metrics.preparing_roam && blocked.metrics.overview && !blocked.metrics.avatar.ready);
    const beforePosition = blocked.metrics.player.position;
    try {
      for (const keyName of ['KeyW', 'Space']) { pressed.add(keyName); await page.keyboard.down(keyName); }
      await sleep(1500);
    } finally {
      for (const keyName of ['Space', 'KeyW']) { await page.keyboard.up(keyName).catch(() => {}); pressed.delete(keyName); }
    }
    const afterInput = await waitFor('fresh blocked-input sample', s => s.metrics?.preparing_roam, 30000, blocked.metrics.ticks_ms);
    check('Movement and jump input cannot move an unprepared player', distance(beforePosition, afterInput.metrics.player.position) < 0.0001 &&
      afterInput.metrics.overview && !afterInput.metrics.avatar.ready, { before: beforePosition, after: afterInput.metrics.player.position });
    await capture('preparation-blocks-input');

    await key('Escape');
    const cancelled = await waitFor('Escape cancels preparation', s => s.metrics?.overview && !s.metrics.preparing_roam && !s.room);
    await sleep(1500);
    const stillCancelled = await waitFor('cancel remains in overview', s => s.metrics?.overview && !s.metrics.preparing_roam && !s.room,
      30000, cancelled.metrics.ticks_ms);
    check('Escape cancellation stays in the original world', stillCancelled.ready && stillCancelled.metrics.overview && !stillCancelled.room);
    await capture('cancelled-overview');

    await key('Tab');
    await waitFor('second attempt exposes retry action', s => s.metrics?.preparing_roam && s.metrics.buttons.some(b => b.visible && b.text === '重新下載'));
    const clickedAt = await clickRetry();
    const resumed = await waitFor('retry loads avatar and enters roaming', s => !s.metrics?.overview && !s.metrics?.preparing_roam &&
      s.metrics?.avatar?.ready && s.metrics?.packs?.ready_packs > 0, 120000, clickedAt);
    check('Real retry button resumes download and completes roaming preparation', resumed.metrics.avatar.ready &&
      resumed.metrics.streaming.loaded_chunks > 0 && !resumed.metrics.avatar.error, { avatar: resumed.metrics.avatar, packs: resumed.metrics.packs, streaming: resumed.metrics.streaming });
    const avatarRequests = [...network.values()].filter(item => item.url === avatarUrl);
    check('Avatar pack is requested exactly once again after the injected failure', avatarAttempts === 2 && avatarRequests.length === 2 &&
      avatarRequests[0].status === 503 && avatarRequests[1].status === 200, avatarRequests);
    const bootUrl = new URL('index.pck', url).href;
    check('Retry reuses the loaded boot package without another boot download', [...network.values()].filter(item => item.url === bootUrl || /index\.boot\.[a-f0-9]+\.pck\.gz$/.test(item.url)).length === 1);
    check('Successful recovery clears the avatar pack failure', !resumed.metrics.packs.errors.avatar, resumed.metrics.packs.errors);
    check('Web downloads use bounded streaming writes', resumed.metrics.packs.transport === 'background_fetch' &&
      resumed.metrics.packs.max_download_frame_bytes > 0 && resumed.metrics.packs.max_download_frame_bytes <= 4194304,
      { transport: resumed.metrics.packs.transport, max_download_frame_bytes: resumed.metrics.packs.max_download_frame_bytes });
    await capture('roaming-ready');
    report.request_summary = Object.fromEntries([...new Set([...network.values()].map(item => new URL(item.url).pathname))]
      .map(name => { const rows = [...network.values()].filter(item => new URL(item.url).pathname === name);
        return [name, { count: rows.length, statuses: rows.map(row => row.status ?? null),
          decoded_body_bytes: rows.reduce((sum, row) => sum + row.decoded_body_bytes, 0),
          transferred_bytes_with_headers: rows.reduce((sum, row) => sum + (row.transferred_bytes_with_headers || 0), 0) }]; }));
  } catch (error) {
    report.errors.push(String(error.stack || error));
    if (page && !page.isClosed()) await capture('failure').catch(() => {});
  } finally {
    if (page && !page.isClosed() && !aborted) {
      for (const keyName of pressed) await page.keyboard.up(keyName).catch(() => {});
    }
    report.finished = new Date().toISOString();
    report.avatar_attempts = avatarAttempts;
    report.passed = report.errors.length === 0 && report.checks.length > 0 && report.checks.every(item => item.passed);
    save();
    await closeBrowser();
    clearTimeout(watchdog);
  }
  console.log(JSON.stringify({ report: reportPath, passed: report.passed, checks: report.checks.length, errors: report.errors }, null, 2));
  process.exitCode = report.passed ? 0 : 1;
})().catch(async error => {
  report.errors.push(String(error.stack || error)); save();
  await closeBrowser(); clearTimeout(watchdog); process.exitCode = 1;
});
