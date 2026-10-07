// Real hidden-tab QA against an owned, throttled localhost HTTP server.
// Usage: NODE_PATH=<Playwright packages> node tools/check_background_downloads.cjs [_site] [label]
// No production commands are injected. Page evaluations only read telemetry;
// every game action uses mouse/keyboard, and visibility comes from real tabs.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const { once } = require('node:events');
const { spawn, execFileSync } = require('node:child_process');

const repo = path.resolve(__dirname, '..');
const source = path.resolve(repo, process.argv[2] || '_site');
const label = (process.argv[3] || 'background-downloads').replace(/[^a-zA-Z0-9_-]/g, '-');
const output = path.join(repo, 'deliverables', 'startup-packs');
fs.mkdirSync(output, { recursive: true });
const reportPath = path.join(output, `${label}.json`);
const manifest = JSON.parse(fs.readFileSync(path.join(source, 'index.packs.json'), 'utf8'));
const release = JSON.parse(fs.readFileSync(path.join(source, 'index.release.json'), 'utf8'));
const expected = new Map(Object.entries(manifest.packs).map(([id, pack]) => [`/${pack.url}`, { id, ...pack }]));
const totalPackBytes = [...expected.values()].reduce((sum, pack) => sum + pack.bytes, 0);
const layout = JSON.parse(fs.readFileSync(path.join(repo, 'game/data/world_layout.json'), 'utf8'));
const project = fs.readFileSync(path.join(repo, 'game/project.godot'), 'utf8');
const viewport = { width: 1200, height: 800 };
const base = { width: Number(project.match(/^window\/size\/viewport_width=(\d+)/m)?.[1]),
  height: Number(project.match(/^window\/size\/viewport_height=(\d+)/m)?.[1]) };
const stretchAspect = project.match(/^window\/stretch\/aspect="([^"]+)"/m)?.[1] || 'keep';
if (!base.width || !base.height || stretchAspect !== 'keep') throw Error('Unsupported viewport mapping');

const report = { label, source, started: new Date().toISOString(), expected_build: release.build_id,
  viewport, pack_count: expected.size, pack_bytes: totalPackBytes, checks: [], snapshots: [], diagnostics: [], errors: [],
  server_requests: [], network: [], screenshots: [],
  fixture: { pack_chunk_bytes: 65536, delay_per_chunk_ms: 20, cache_control: 'no-store',
    avatar_body_gate: 'Real HTTP response pauses after first chunk until Tab/Esc and confirmed hidden-tab settling.' },
  method: 'Ordinary headed Chrome with an ephemeral profile, Playwright CDP attachment with noDefaults (no forced-focus emulation), real same-window tab activation, ordinary keyboard/mouse, read-only game/downloader telemetry and CDP network events.',
  limitations: ['Tests an open hidden browser tab, not a frozen/discarded tab, closed browser, or suspended operating system.',
    'Throttled localhost establishes correctness; it is not a public CDN or real-network speed benchmark.',
    'Fresh ephemeral browser context and no-store fixture; no persistent cache is added.'] };
const network = new Map();
let server, chromeProcess, browserControl, browser, context, page, otherPage, profile, closing, aborted = false;
let releaseAvatarBody;
const avatarBodyGate = new Promise(resolve => { releaseAvatarBody = resolve; });
let avatarGateReleased = false;
function openAvatarBodyGate(reason) {
  if (avatarGateReleased) return;
  avatarGateReleased = true;
  report.fixture.avatar_gate_released_epoch_ms = Date.now();
  report.fixture.avatar_gate_release_reason = reason;
  releaseAvatarBody(); save();
}
const held = new Set();
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const save = () => { report.network = [...network.values()]; fs.writeFileSync(reportPath, JSON.stringify(report, null, 2)); };
function check(name, passed, evidence = null) {
  report.checks.push({ name, passed: Boolean(passed), evidence: structuredClone(evidence), at: new Date().toISOString() });
  save(); console.log(passed ? 'PASS' : 'FAIL', name);
  return passed;
}
async function close() {
  if (!closing) closing = (async () => {
    openAvatarBodyGate('cleanup');
    const killer = setTimeout(() => chromeProcess?.kill(), 10000);
    try {
      await browserControl?.send('Browser.close').catch(() => {});
      await browser?.close().catch(() => {});
    } finally {
      if (chromeProcess?.exitCode === null) await Promise.race([once(chromeProcess, 'exit'), delay(3000)]);
      if (chromeProcess?.exitCode === null) {
        chromeProcess.kill();
        await Promise.race([once(chromeProcess, 'exit'), delay(3000)]);
      }
      clearTimeout(killer);
      if (server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
      if (profile) {
        // Delete only this runner's verified fresh profile, never a normal
        // browser profile or a path inferred from Chrome's process arguments.
        const parent = path.resolve(repo, 'build', 'background-browser-profiles');
        if (path.dirname(profile) !== parent || !path.basename(profile).startsWith('qa-')) throw Error('Unsafe profile cleanup path');
        try {
          if (process.platform === 'win32') {
            // Use native literal-path deletion: recursive fs.rmSync crashes
            // this Windows Node runtime on Chrome's profile directory.
            execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
              '$target=[IO.Path]::GetFullPath($env:LW_QA_PROFILE); $parent=[IO.Path]::GetFullPath($env:LW_QA_PROFILE_PARENT); ' +
              'if ((Split-Path -Parent $target) -ne $parent -or (Split-Path -Leaf $target) -notlike "qa-*") { throw "Unsafe profile cleanup path" }; ' +
              'Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop'],
            { windowsHide: true, timeout: 15000, stdio: 'pipe', env: { ...process.env, LW_QA_PROFILE: profile, LW_QA_PROFILE_PARENT: parent } });
          } else fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
        }
        catch (error) { report.cleanup_warning = String(error); save(); }
      }
    }
  })();
  return closing;
}
const watchdog = setTimeout(() => {
  aborted = true; report.errors.push('Outer 15-minute background QA watchdog expired.'); report.passed = false; save();
  const force = setTimeout(() => process.exit(1), 15000);
  close().finally(() => { clearTimeout(force); process.exit(1); });
}, 15 * 60 * 1000);

async function serve(req, res) {
  const pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
  if (pathname === '/__background_other_tab') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end('<!doctype html><title>背景下載測試</title><body><h1>另一個分頁</h1><p>遊戲分頁維持開啟，驗證背景下載。</p></body>'); return;
  }
  const filename = path.resolve(source, '.' + (pathname === '/' ? '/index.html' : pathname));
  if (!filename.startsWith(source + path.sep)) { res.writeHead(403); res.end(); return; }
  let stat;
  try { stat = await fs.promises.stat(filename); } catch { res.writeHead(404); res.end(); return; }
  if (!stat.isFile()) { res.writeHead(404); res.end(); return; }
  const pack = expected.get(pathname);
  const record = { path: pathname, pack: pack?.id || null, start_epoch_ms: Date.now(), bytes_sent: 0 };
  report.server_requests.push(record);
  const contentTypes = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml' };
  res.writeHead(200, { 'Content-Type': contentTypes[path.extname(filename)] || 'application/octet-stream',
    'Content-Length': stat.size, 'Cache-Control': 'no-store' });
  const hash = crypto.createHash('sha256');
  const stream = fs.createReadStream(filename, { highWaterMark: 65536 });
  try {
    for await (const chunk of stream) {
      if (res.destroyed) throw Error('Client closed before fixture finished');
      hash.update(chunk); record.bytes_sent += chunk.length;
      if (!res.write(chunk)) await once(res, 'drain');
      if (pack?.id === 'avatar' && record.bytes_sent === chunk.length) {
        // Keep a genuine response in flight even if shader compilation takes
        // longer than the normal throttle. Never intercept engine functions,
        // fabricate browser visibility, or replace the pack's actual bytes.
        record.body_gate_wait_epoch_ms = Date.now(); save();
        await avatarBodyGate;
        record.body_gate_resume_epoch_ms = Date.now();
      }
      if (pack) await delay(20);
    }
    record.sha256 = hash.digest('hex'); record.end_epoch_ms = Date.now(); res.end(); save();
  } catch (error) { record.error = String(error.message); stream.destroy(); res.destroy(); save(); }
}
async function launchNaturalVisibilityBrowser() {
  const candidates = [process.env.CHROME_PATH,
    process.env.PROGRAMFILES && path.join(process.env.PROGRAMFILES, 'Google', 'Chrome', 'Application', 'chrome.exe'),
    process.env['PROGRAMFILES(X86)'] && path.join(process.env['PROGRAMFILES(X86)'], 'Google', 'Chrome', 'Application', 'chrome.exe'),
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/usr/bin/google-chrome'];
  const executable = candidates.find(candidate => candidate && fs.existsSync(candidate));
  if (!executable) throw Error('Google Chrome not found; set CHROME_PATH to its executable');
  const parent = path.resolve(repo, 'build', 'background-browser-profiles');
  fs.mkdirSync(parent, { recursive: true }); profile = fs.mkdtempSync(path.join(parent, 'qa-'));
  const args = ['--remote-debugging-port=0', `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', 'about:blank'];
  chromeProcess = spawn(executable, args, { windowsHide: true, stdio: 'ignore' });
  let launchError;
  chromeProcess.on('error', error => { launchError = error; });
  const deadline = Date.now() + 30000;
  let port;
  while (!port && Date.now() < deadline) {
    if (launchError) throw launchError;
    if (chromeProcess.exitCode !== null) throw Error(`Chrome exited before CDP became available: ${chromeProcess.exitCode}`);
    try { port = fs.readFileSync(path.join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0].trim(); } catch {}
    if (!port) await delay(100);
  }
  if (!/^\d+$/.test(port || '')) throw Error('Chrome did not publish a CDP port');
  // Playwright's normal page setup enables focus emulation on its internal
  // CDP session. That makes both tabs document.visibilityState === "visible".
  // Attaching without default overrides preserves real browser visibility;
  // no visibility property, lifecycle state, or page API is mocked here.
  browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, { noDefaults: true });
  browserControl = await browser.newBrowserCDPSession();
  context = browser.contexts()[0]; page = context.pages()[0] || await context.newPage();
  await page.setViewportSize(viewport); page.setDefaultTimeout(30000);
  report.browser = browser.version(); report.browser_launch = { executable, args, no_defaults: true };
}
async function checkNaturalTabVisibility(otherURL) {
  otherPage = await context.newPage(); await otherPage.goto(otherURL);
  const firstCDP = await context.newCDPSession(page), secondCDP = await context.newCDPSession(otherPage);
  const firstWindow = await firstCDP.send('Browser.getWindowForTarget');
  const secondWindow = await secondCDP.send('Browser.getWindowForTarget');
  const visibility = tab => tab.evaluate(() => ({ hidden: document.hidden, visibility: document.visibilityState, focus: document.hasFocus() }));
  await otherPage.bringToFront(); await delay(300);
  const otherFront = { game: await visibility(page), other: await visibility(otherPage) };
  await page.bringToFront(); await delay(300);
  const gameFront = { game: await visibility(page), other: await visibility(otherPage) };
  await firstCDP.detach(); await secondCDP.detach();
  const passed = firstWindow.windowId === secondWindow.windowId && otherFront.game.hidden && !otherFront.other.hidden &&
    !gameFront.game.hidden && gameFront.other.hidden;
  check('Tiny browser fixture preserves natural same-window tab visibility', passed, { firstWindow, secondWindow, otherFront, gameFront });
  if (!passed) throw Error('Real tab visibility fixture failed before loading Godot');
}
async function snapshot(name) {
  const state = await page.evaluate(() => ({ ready: window.planetWorldReady === true,
    metrics: window.planetPerformance || null, room: window.trainingRoomState || null,
    background: window.LittleWorldBackgroundPacks?.snapshot() || null,
    hidden: document.hidden, visibility: document.visibilityState,
    build_id: document.querySelector('meta[name="little-world-build"]')?.content || null }));
  if (name) { report.snapshots.push({ name, at: new Date().toISOString(), ...state }); save(); }
  return state;
}
async function waitFor(name, predicate, timeout = 30000, afterTicks = -1, { allowHidden = false } = {}) {
  const started = Date.now(), deadline = started + timeout;
  let lastDiagnostic = started;
  while (Date.now() < deadline) {
    if (aborted) throw Error('QA aborted');
    const state = await snapshot();
    if (!allowHidden && state.hidden) {
      // Foreground route checks need actual foreground frames. A natural
      // browser may lose focus/visibility during this long suite; reactivate
      // its real tab rather than mistaking paused frames for a gameplay bug.
      report.foreground_focus_recoveries ||= [];
      report.foreground_focus_recoveries.push({ wait: name, at: new Date().toISOString(), ticks_ms: state.metrics?.ticks_ms });
      save(); await page.bringToFront(); await delay(400); continue;
    }
    if ((afterTicks < 0 || state.metrics?.ticks_ms > afterTicks) && predicate(state)) return state;
    if (Date.now() - lastDiagnostic >= 10000) {
      lastDiagnostic = Date.now();
      const diagnostic = { wait: name, at: new Date().toISOString(), elapsed_ms: lastDiagnostic - started,
        ready: state.ready, hidden: state.hidden, visibility: state.visibility, build_id: state.build_id,
        metrics_present: Boolean(state.metrics), ticks_ms: state.metrics?.ticks_ms,
        overview: state.metrics?.overview, preparing_roam: state.metrics?.preparing_roam,
        packs: state.metrics?.packs && { ready: state.metrics.packs.ready_packs, total: state.metrics.packs.total_packs,
          current: state.metrics.packs.current, state: state.metrics.packs.state, mounted_bytes: state.metrics.packs.mounted_bytes,
          errors: state.metrics.packs.errors },
        background: state.background && { active: state.background.active, buffered_bytes: state.background.buffered_bytes,
          jobs: state.background.jobs.map(job => ({ id: job.id, state: job.state, received: job.received, expected: job.expected })) } };
      report.diagnostics.push(diagnostic); save(); console.log('WAIT', JSON.stringify(diagnostic));
    }
    await delay(400);
  }
  await snapshot(`timeout-${name}`); throw Error(`Timed out: ${name}`);
}
async function capture(name) {
  const filename = path.join(output, `${label}-${name}.png`);
  await page.screenshot({ path: filename, timeout: 60000 }); report.screenshots.push(filename); await snapshot(name);
}
async function hold(keys, ms) {
  await page.bringToFront();
  try { for (const key of keys) { await page.keyboard.down(key); held.add(key); } await delay(ms); }
  finally { for (const key of keys.toReversed()) { await page.keyboard.up(key).catch(() => {}); held.delete(key); } }
}
const key = name => hold([name], 80);
const roaming = state => !state.room && state.metrics?.avatar?.ready && !state.metrics?.preparing_roam &&
  !state.metrics?.overview && !state.metrics?.player?.paused && !state.metrics?.player?.entering;
const allMounted = state => state.metrics?.packs?.ready_packs === expected.size &&
  state.metrics.packs.mounted_bytes === totalPackBytes && Object.keys(state.metrics.packs.errors || {}).length === 0;
const packRequests = () => [...network.values()].filter(row => expected.has(new URL(row.url).pathname));
function packCompletionEvidence(state) {
  const jobs = state?.background?.jobs || [];
  return [...expected].map(([pathname, pack]) => {
    const matchingJobs = jobs.filter(job => job.id === pack.id);
    const matchingResponses = report.server_requests.filter(row => row.path === pathname);
    const job = matchingJobs.length === 1 ? matchingJobs[0] : null;
    const response = matchingResponses.length === 1 ? matchingResponses[0] : null;
    return { id: pack.id, bytes: pack.bytes, server_response_count: matchingResponses.length,
      client_job_count: matchingJobs.length,
      server_complete: Boolean(response && response.end_epoch_ms && !response.error &&
        response.bytes_sent === pack.bytes && response.sha256 === pack.sha256),
      server_end_epoch_ms: response?.end_epoch_ms || null,
      // Production marks downloaded only after reader.read() returns done and
      // the received length matches. Server writes alone cannot prove receipt.
      client_complete: Boolean(job && job.state === 'downloaded' && !job.error && job.finished > 0 &&
        job.received === pack.bytes && job.expected === pack.bytes),
      client_state: job?.state || 'missing', client_received: job?.received ?? null,
      client_finished_ms: job?.finished || null };
  });
}
const packBodiesComplete = state => packCompletionEvidence(state).every(row => row.server_complete && row.client_complete);
const districtAt = position => layout.stations.map(station => ({ id: station.id,
  dot: station.normal.reduce((sum, value, index) => sum + value * position[index], 0) }))
  .sort((a, b) => b.dot - a.dot)[0].id;
async function clickButton(matches, scroll = false) {
  await page.bringToFront();
  for (let attempt = 0; attempt < (scroll ? 18 : 5); attempt++) {
    const state = await snapshot();
    const buttons = state.metrics?.buttons || [];
    const button = buttons.find(item => item.visible && matches(item));
    const box = await page.locator('#canvas').boundingBox();
    if (!box?.width || !box?.height) throw Error('Canvas has no visible bounds');
    const scale = Math.min(box.width / base.width, box.height / base.height);
    const width = base.width * scale, height = base.height * scale;
    const origin = { x: box.x + (box.width - width) / 2, y: box.y + (box.height - height) / 2 };
    if (button && button.center.every(value => value >= 0 && value <= 1)) {
      await page.mouse.click(origin.x + button.center[0] * width, origin.y + button.center[1] * height);
      await waitFor('fresh UI result', state => Boolean(state.metrics), 45000, state.metrics.ticks_ms); return;
    }
    if (!scroll) { await delay(700); continue; }
    const target = buttons.find(matches);
    const rows = buttons.filter(item => item.visible && /^\d{2}\s/.test(item.text));
    const anchor = rows[Math.floor(rows.length / 2)]?.center || [.13, .76];
    await page.mouse.move(origin.x + anchor[0] * width, origin.y + anchor[1] * height);
    await page.mouse.wheel(0, target && target.center[1] < anchor[1] ? -180 : 180); await delay(900);
  }
  throw Error('Destination button not reachable using real input');
}
async function teleport(station) {
  const before = await snapshot();
  if (!before.metrics?.destinations_open) await clickButton(button => /選擇目的地/.test(button.text));
  await waitFor('destination list', state => state.metrics?.destinations_open);
  await clickButton(button => new RegExp(`^\\d{2}\\s+${station.label}`).test(button.text), true);
  // Nearby seating may legitimately win the interaction prompt after detail
  // loads. Verify the actual region position, not that prompt's station ID.
  const arrived = await waitFor(`teleport ${station.id}`, state => roaming(state) && districtAt(state.metrics.player.position) === station.id &&
    state.metrics.streaming.pending_regions === 0, 180000);
  if (arrived.metrics.destinations_open) await clickButton(button => /收起目的地/.test(button.text));
  check(`Teleport ${station.id} uses mounted packs`, allMounted(arrived) && packRequests().length === expected.size,
    { position: arrived.metrics.player.position, streaming: arrived.metrics.streaming, pack_requests: packRequests().length });
}

(async () => {
  try {
    save();
    server = http.createServer((req, res) => serve(req, res).catch(error => { report.errors.push(String(error)); save(); res.destroy(); }));
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    const url = `http://127.0.0.1:${server.address().port}/index.html?performance`;
    report.url = url; console.log('START', label, url);
    await launchNaturalVisibilityBrowser();
    await checkNaturalTabVisibility(new URL('/__background_other_tab', url).href);
    if (process.argv.includes('--visibility-fixture')) return;
    page.on('pageerror', error => { report.errors.push(String(error)); save(); });
    page.on('console', message => {
      if ((message.type() === 'error' || /SCRIPT ERROR:|Parse Error:|SHADER ERROR:/.test(message.text())) &&
          !/favicon\.ico/.test(message.location().url || '')) { report.errors.push(message.text()); save(); }
    });
    const cdp = await context.newCDPSession(page); await cdp.send('Network.enable');
    cdp.on('Network.requestWillBeSent', event => network.set(event.requestId, { id: event.requestId, url: event.request.url,
      start_epoch_ms: event.wallTime * 1000, decoded_bytes: 0, encoded_bytes: 0 }));
    cdp.on('Network.responseReceived', event => {
      const row = network.get(event.requestId); if (row) Object.assign(row, { status: event.response.status,
        disk_cache: Boolean(event.response.fromDiskCache), service_worker: Boolean(event.response.fromServiceWorker) });
    });
    cdp.on('Network.dataReceived', event => {
      const row = network.get(event.requestId); if (row) { row.decoded_bytes += event.dataLength; row.encoded_bytes += event.encodedDataLength; }
    });
    cdp.on('Network.loadingFinished', event => {
      const row = network.get(event.requestId); if (row) Object.assign(row, { finished_epoch_ms: Date.now(), transferred_bytes: event.encodedDataLength });
    });
    cdp.on('Network.loadingFailed', event => {
      const row = network.get(event.requestId); if (row) row.error = event.errorText;
    });
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 180000 });
    await page.bringToFront();
    const initial = await waitFor('overview with startup background queue', state => state.ready && state.metrics?.overview &&
      state.background?.jobs?.length > 0 && state.metrics.packs.ready_packs < expected.size &&
      state.background.jobs.length + state.metrics.packs.ready_packs === expected.size, 300000);
    check('Loaded expected release with all startup packs scheduled', initial.build_id === release.build_id && expected.size === 16 &&
      initial.background.jobs.length + initial.metrics.packs.ready_packs === expected.size,
      { build_id: initial.build_id, background: initial.background, packs: initial.metrics.packs });
    await key('Tab');
    const preparing = await waitFor('play remains gated before every pack mounts', state => state.metrics?.preparing_roam &&
      state.metrics.overview && state.metrics.packs.ready_packs < expected.size);
    const oldPosition = preparing.metrics.player.position;
    await hold(['w', 'Space'], 400);
    const blocked = await waitFor('blocked player input sample', state => state.metrics?.preparing_roam, 30000, preparing.metrics.ticks_ms);
    check('Play and movement remain blocked before all packs are ready', Math.hypot(...oldPosition.map((v, i) => v - blocked.metrics.player.position[i])) < .0001);
    await key('Escape');
    const cancelled = await waitFor('cancel returns to overview while downloads continue', state => state.metrics?.overview &&
      !state.metrics.preparing_roam && !state.room && !packBodiesComplete(state));
    check('Cancelling to overview retains the startup download queue', cancelled.background.jobs.length > 0 && !allMounted(cancelled), cancelled.background);
    await capture('cancelled-overview');

    await otherPage.bringToFront();
    const hidden = await waitFor('real game tab becomes hidden', state => state.hidden && state.visibility === 'hidden',
      30000, -1, { allowHidden: true });
    check('Real second-tab activation hides the game', hidden.hidden && hidden.visibility === 'hidden');
    await delay(1200); // Let the final foreground frame settle before comparing engine counters.
    const hiddenStart = await snapshot('hidden-start');
    if (!hiddenStart.hidden || packBodiesComplete(hiddenStart)) throw Error('Fixture did not retain an in-flight hidden download window');
    const hiddenEpoch = Date.now();
    const bytesBefore = packRequests().reduce((sum, row) => sum + row.decoded_bytes, 0);
    check('Avatar HTTP body stays in flight through real cancellation and hiding', report.server_requests.some(row =>
      row.pack === 'avatar' && row.body_gate_wait_epoch_ms && !row.end_epoch_ms && row.bytes_sent === 65536) &&
      !avatarGateReleased, report.server_requests.filter(row => row.pack === 'avatar'));
    openAvatarBodyGate('Tab/Esc completed and real hidden state confirmed after settling');
    // CDP may report ERR_ABORTED after the fetch reader consumed its full body
    // (observed for all packs and boot gzip on this Chrome build). Keep those
    // events below; require independent client EOF and server SHA evidence.
    await waitFor('hidden downloads reach client EOF with verified server bytes', state =>
      state.hidden && state.visibility === 'hidden' && packBodiesComplete(state), 180000, -1, { allowHidden: true });
    const hiddenEnd = await snapshot('hidden-downloads-complete');
    const completion = packCompletionEvidence(hiddenEnd);
    report.network_completion_observations = packRequests().map(row => ({ path: new URL(row.url).pathname,
      status: row.status, decoded_bytes: row.decoded_bytes, loading_finished: Boolean(row.finished_epoch_ms),
      loading_failed: row.error || null }));
    const bytesAfter = packRequests().reduce((sum, row) => sum + row.decoded_bytes, 0);
    check('All pack bodies reach client EOF while the game stays hidden', packBodiesComplete(hiddenEnd) && hiddenEnd.hidden &&
      completion.some(row => row.server_end_epoch_ms >= hiddenEpoch) && bytesAfter > bytesBefore,
      { before: bytesBefore, after: bytesAfter, hidden_started_epoch_ms: hiddenEpoch,
        completion_method: 'Exact client reader EOF/length plus exact server SHA/length, independent of CDP terminal event.',
        packs: completion });
    check('Engine telemetry stops while independent downloads finish', hiddenEnd.metrics.ticks_ms === hiddenStart.metrics.ticks_ms,
      { before_ticks: hiddenStart.metrics.ticks_ms, after_ticks: hiddenEnd.metrics.ticks_ms });
    check('Hidden page has fully downloaded buffers within its declared cap', hiddenEnd.background.jobs.length > 0 &&
      hiddenEnd.background.jobs.every(job => job.state === 'downloaded' && job.received === job.expected) &&
      hiddenEnd.background.peak_buffered_bytes <= hiddenEnd.background.buffer_limit_bytes,
      hiddenEnd.background);
    check('Every throttled response preserves exact packaged bytes', [...expected].every(([pathname, pack]) =>
      report.server_requests.some(row => row.path === pathname && row.bytes_sent === pack.bytes && row.sha256 === pack.sha256)), report.server_requests.filter(row => row.pack));

    await page.bringToFront();
    const mounted = await waitFor('all verified packs mount after returning to game', state => !state.hidden && allMounted(state), 180000);
    check('Returning mounts every pack without automatically entering play', mounted.metrics.overview && !mounted.metrics.preparing_roam && !mounted.room,
      { packs: mounted.metrics.packs, background: mounted.background });
    await capture('all-mounted-overview');
    const countBeforePlay = packRequests().length;
    await key('Tab'); await waitFor('real Tab enters play after complete startup', roaming, 180000);
    const walkStart = await snapshot(); await hold(['w'], 650);
    const walked = await waitFor('real walking update', roaming, 30000, walkStart.metrics.ticks_ms);
    const distance = Math.hypot(...walkStart.metrics.player.position.map((v, i) => v - walked.metrics.player.position[i]));
    check('Prepared world supports real walking on terrain', distance > .05 && Math.hypot(...walked.metrics.player.position) >= 47, { distance, position: walked.metrics.player.position });
    for (const station of layout.stations) await teleport(station);
    await delay(1000);
    check('Walking and all six teleports create no additional pack requests', countBeforePlay === expected.size && packRequests().length === countBeforePlay,
      { requests_before_play: countBeforePlay, requests_after_teleports: packRequests().length });
    await capture('six-teleports-mounted');
  } catch (error) {
    report.errors.push(String(error.stack || error));
    if (page && !page.isClosed()) { await page.bringToFront().catch(() => {}); await capture('failure').catch(() => {}); }
  } finally {
    if (page && !page.isClosed()) for (const name of held) await page.keyboard.up(name).catch(() => {});
    report.finished = new Date().toISOString(); report.passed = report.errors.length === 0 && report.checks.length > 0 && report.checks.every(row => row.passed);
    save(); await close(); clearTimeout(watchdog);
  }
  console.log(JSON.stringify({ report: reportPath, passed: report.passed, checks: report.checks.length, errors: report.errors }, null, 2));
  process.exitCode = report.passed ? 0 : 1;
})().catch(async error => { report.errors.push(String(error.stack || error)); save(); await close(); clearTimeout(watchdog); process.exitCode = 1; });
