// Local release benchmark: all game actions use actual mouse/key input.
// Usage: node tools/check_movement_smoothing.cjs URL LABEL [release.json] [--profile=both|low|standard] [--repeats=3] [--duration=6000] [--visual-smoke]
// --scale-diagnostic-only compares low at 1280x800 (0.9 scale) and 1152x720 (1.0 scale), standing/turn only.
// NODE_PATH must resolve Playwright. Run only one GPU benchmark at a time.
const fs = require('node:fs');
const path = require('node:path');

function summarize(intervals) {
  const sorted = [...intervals].sort((a, b) => a - b);
  const quantile = ratio => sorted.length ? sorted[Math.ceil(sorted.length * ratio) - 1] : null;
  const mean = sorted.length ? sorted.reduce((sum, value) => sum + value, 0) / sorted.length : null;
  return {interval_count: sorted.length, mean_ms: mean, submission_fps: mean ? 1000 / mean : null,
    p50_ms: quantile(.5), p95_ms: quantile(.95), p99_ms: quantile(.99), max_ms: sorted.at(-1) ?? null,
    over_100_ms: sorted.filter(value => value > 100).length};
}

function reviewMotion(observations) {
  const seen = new Set();
  const fresh = observations.filter(row => {
    const metrics = row.state?.metrics;
    if (!Number.isFinite(metrics?.ticks_ms) || !Array.isArray(metrics?.player?.position) || seen.has(metrics.ticks_ms)) return false;
    seen.add(metrics.ticks_ms); return true;
  });
  const segments = fresh.slice(1).map((row, index) => ({
    from_ticks_ms:fresh[index].state.metrics.ticks_ms, to_ticks_ms:row.state.metrics.ticks_ms,
    distance_world_units:Math.hypot(...row.state.metrics.player.position.map((value, axis) => value-fresh[index].state.metrics.player.position[axis])),
  }));
  const firstMoving = segments.findIndex(segment => segment.distance_world_units > .15);
  const movingTail = firstMoving < 0 ? [] : segments.slice(firstMoving);
  return {fresh_samples:fresh.length, segments,
    leading_stationary_segments:firstMoving < 0 ? segments.length : firstMoving,
    measured_path_world_units:segments.reduce((sum, segment) => sum+segment.distance_world_units, 0),
    sustained_motion_observed:movingTail.length >= 2 && movingTail.every(segment => segment.distance_world_units > .15),
    continuous_motion_observed:segments.length >= 2 && segments.every(segment => segment.distance_world_units > .15),
    note:firstMoving > 0 ? 'Initial unchanged positions precede observed motion; input/telemetry latency remains part of timing and is not discarded.' : null};
}

if (process.argv[2] === '--review-motion') {
  const file = path.resolve(process.argv[3] || '');
  const stored = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!stored.finished && !stored.runner_finished) throw Error('Motion review requires a finished report to avoid overwriting an active runner');
  stored.motion_review = {
    rule:'Deduplicate telemetry ticks globally. Require at least two positive (>0.15 world unit) fresh-timestamp segments after motion begins; reject stationary later segments. Leading unchanged positions are flagged as input/telemetry latency. No timing/input/route samples are changed and original validation errors are retained.',
    reviewed_at:new Date().toISOString(), original_errors_preserved:true,
    phases:stored.phases.filter(phase => phase.workload === 'walk').map(phase => ({
      profile:phase.profile, repetition:phase.repetition, original_movement:phase.movement,
      ...reviewMotion(phase.observations),
    })),
  };
  fs.writeFileSync(file, JSON.stringify(stored, null, 2));
  console.log(JSON.stringify({file, motion_review:stored.motion_review}));
  process.exit(0);
}

function installProbe() {
  const probe = window.__smoothingProbe = {active:false, intervals:[], longTasks:[], viewports:[], since:0, last:null};
  let serial = 0, current = 0, submitted = -1;
  const request = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = callback => request(timestamp => {
    const previous = current;
    current = ++serial;
    try { return callback(timestamp); }
    finally {
      if (probe.active && submitted === current) {
        const now = performance.now();
        if (probe.last !== null) probe.intervals.push(now - probe.last);
        probe.last = now;
      }
      current = previous;
    }
  });
  for (const Type of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
    if (!Type) continue;
    for (const name of ['clear', 'clearBufferfv', 'viewport']) {
      // Only wrap own methods, so an inherited entry point is not wrapped twice.
      const descriptor = Object.getOwnPropertyDescriptor(Type.prototype, name);
      if (typeof descriptor?.value !== 'function') continue;
      const original = descriptor.value;
      Object.defineProperty(Type.prototype, name, {...descriptor, value:function(...args) {
        if (name === 'viewport') {
          if (probe.active) {
            const size = `${args[2]}x${args[3]}`;
            if (!probe.viewports.includes(size)) probe.viewports.push(size);
          }
        } else submitted = current;
        return original.apply(this, args);
      }});
    }
  }
  try {
    new PerformanceObserver(list => {
      if (probe.active) for (const entry of list.getEntries()) {
        if (entry.startTime >= probe.since) probe.longTasks.push({start_ms:entry.startTime, duration_ms:entry.duration});
      }
    }).observe({type:'longtask', buffered:true});
  } catch {}
}

if (process.argv.includes('--self-test')) {
  const assert = require('node:assert/strict');
  assert.deepEqual(summarize([]), {interval_count:0, mean_ms:null, submission_fps:null, p50_ms:null,
    p95_ms:null, p99_ms:null, max_ms:null, over_100_ms:0});
  const sample = summarize(Array.from({length:100}, (_, index) => index + 1));
  assert.equal(sample.p50_ms, 50); assert.equal(sample.p95_ms, 95); assert.equal(sample.p99_ms, 99);
  assert.equal(sample.max_ms, 100); assert.equal(sample.over_100_ms, 0);
  assert.equal(summarize([100, 101]).over_100_ms, 1);
  const observation = (ticks, x) => ({state:{metrics:{ticks_ms:ticks, player:{position:[x,0,0]}}}});
  const latency = reviewMotion([observation(1,0), observation(2,0), observation(2,0), observation(3,3), observation(4,6)]);
  assert.equal(latency.leading_stationary_segments, 1); assert.equal(latency.sustained_motion_observed, true);
  assert.equal(latency.continuous_motion_observed, false);
  assert.equal(reviewMotion([observation(1,0), observation(2,3), observation(3,3), observation(4,6)]).sustained_motion_observed, false);
  const vm = require('node:vm');
  let time = 0;
  const callbacks = [];
  class FakeGL { clear() {} viewport() {} }
  const window = {WebGLRenderingContext:FakeGL, requestAnimationFrame:callback => callbacks.push(callback)};
  vm.runInNewContext(`(${installProbe.toString()})();`, {window, performance:{now:() => time}});
  const probe = window.__smoothingProbe, gl = new FakeGL();
  const frame = (timestamp, draw) => {
    window.requestAnimationFrame(() => { if (draw) gl.clear(); });
    time = timestamp; callbacks.shift()(timestamp);
  };
  frame(10, true); // Initialization before sampling must not leak into intervals.
  probe.active = true;
  frame(20, true); frame(30, false); frame(50, true); frame(70, false); frame(100, true);
  assert.deepEqual(Array.from(probe.intervals), [30, 50]);
  probe.active = false; frame(200, true);
  assert.equal(probe.intervals.length, 2);
  console.log('Quantile, telemetry motion, and draw-submission / idle-rAF isolation checks passed');
  process.exit(0);
}

const {chromium} = require('playwright');
const args = process.argv.slice(2);
const positional = args.filter(value => !value.startsWith('--'));
const options = Object.fromEntries(args.filter(value => value.startsWith('--')).map(value => value.slice(2).split('=')));
if (Object.keys(options).some(key => !['profile', 'repeats', 'duration', 'viewport', 'visual-smoke', 'scale-diagnostic-only'].includes(key))) throw Error('Unknown option');
const dimensions = (options.viewport || '1280x800').match(/^(\d+)x(\d+)$/);
if (!dimensions || dimensions.slice(1).some(value => Number(value) < 320 || Number(value) > 3840)) throw Error('Viewport must be WIDTHxHEIGHT within 320..3840');
const visualSmokeRequested = Object.hasOwn(options, 'visual-smoke');
const scaleDiagnostic = Object.hasOwn(options, 'scale-diagnostic-only');
if (!positional[0]) throw Error('Expected localhost URL and optional report label/release manifest');
const url = new URL(positional[0]);
if (!['http:', 'https:'].includes(url.protocol) || !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) throw Error('Localhost HTTP(S) only');
url.searchParams.set('performance', '');
const label = (positional[1] || 'movement-smoothing').replace(/[^a-zA-Z0-9_-]/g, '-');
const profileOption = options.profile || 'both';
if (!['both', 'low', 'standard'].includes(profileOption)) throw Error('Profile must be both, low, or standard');
const repeats = Number(options.repeats || 3), duration = Number(options.duration || 6000);
if (!Number.isInteger(repeats) || repeats < 3 || repeats > 10) throw Error('Repeats must be 3..10');
if (!Number.isFinite(duration) || duration < 4000 || duration > 12000) throw Error('Duration must be 4000..12000 ms');
const repo = path.resolve(__dirname, '..');
const out = path.join(repo, 'deliverables', 'movement-smoothing');
const layout = JSON.parse(fs.readFileSync(path.join(repo, 'game/data/world_layout.json'), 'utf8'));
const station = layout.stations.find(row => row.id === 'counseling');
const config = fs.readFileSync(path.join(repo, 'game/project.godot'), 'utf8');
const baseWidth = Number(config.match(/^window\/size\/viewport_width=(\d+)/m)?.[1]);
const baseHeight = Number(config.match(/^window\/size\/viewport_height=(\d+)/m)?.[1]);
const stretchAspect = config.match(/^window\/stretch\/aspect="([^"]+)"/m)?.[1] || 'keep';
if (!baseWidth || !baseHeight || stretchAspect !== 'keep') throw Error('Input mapping requires existing keep-aspect viewport');
fs.mkdirSync(out, {recursive:true});
const reportFile = path.join(out, `${label}.json`);
const expectedRelease = positional[2] ? JSON.parse(fs.readFileSync(path.resolve(repo, positional[2]), 'utf8')) : null;
const report = {label, url:url.href, started:new Date().toISOString(), viewport:{width:Number(dimensions[1]),height:Number(dimensions[2])},
  duration_ms:duration, repeats, visual_smoke_requested:visualSmokeRequested, scale_diagnostic_only:scaleDiagnostic,
  profile_order:[], phases:[], checks:[], errors:[], requests:[],
  expected_release:expectedRelease, requested_graphics:{frame_limit:60, msaa_enabled:false},
  method:'Real UI/keyboard/mouse on localhost release. Only clear-marked requestAnimationFrame callbacks contribute submission intervals; idle rAF callbacks are excluded. CPU submission cadence is not GPU presentation timing. No WebGL API wall timers or CPU profiler are enabled. Each workload starts at the same counseling road position after streaming settles. Profile order alternates per repetition. Raw intervals and telemetry are retained; phases with streaming work remain visibly flagged, not silently excluded.',
  route:{destination:'counseling', road_alignment:'x = radius * world_x / world_y, tolerance 0.4', walk_key:'s',
    turn:'Stationary right-button horizontal sine sweep, approximately 80 ms between input events, 130 CSS px amplitude plus 80 px net turn for final visual evidence'},
  limitations:['Repeated local tests do not control system background load, thermals, or GPU clocks.',
    'Pooled quantiles combine matching workloads; inspect each repetition and streaming flags before attributing causality.']};
if (scaleDiagnostic) {
  report.scale_diagnostic = {purpose:'Same low profile and internal 3D pixels, with and without render scaling.',
    internal_pixels:[1152,720], aspect_ratio:1.6, workloads:['standing','turn'],
    conditions:[{name:'low-scaled',viewport:{width:Number(dimensions[1]),height:Number(dimensions[2])},expected_scale:.9},
      {name:'low-native720',viewport:{width:1152,height:720},expected_scale:1}],
    limitation:'UI and final render target sizes also differ. This is suggestive evidence for the extra scaling/copy path, not an isolated GPU pass benchmark.'};
}
let browserServer, browser, page, closing, aborted = false;
const pressed = new Set();
const save = () => fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const closeBrowser = () => closing ||= (async () => {
  const killTimer = setTimeout(() => browserServer?.kill().catch(() => {}), 10000);
  try { await browser?.close().catch(() => {}); await browserServer?.close().catch(() => {}); }
  finally { clearTimeout(killTimer); }
})();
function abort(reason) {
  if (aborted) return;
  aborted = true; report.errors.push(reason); save();
  const timer = setTimeout(() => process.exit(1), 15000);
  closeBrowser().finally(() => { clearTimeout(timer); process.exit(1); });
}
const watchdog = setTimeout(() => abort('30 minute benchmark watchdog; partial report retained'), 30 * 60000);
process.once('SIGINT', () => abort('Interrupted by SIGINT'));
process.once('SIGTERM', () => abort('Interrupted by SIGTERM'));
function check(name, passed, evidence = null) {
  report.checks.push({name, passed:Boolean(passed), evidence});
  if (!passed) report.errors.push(name);
  save();
}
async function state() {
  return page.evaluate(() => ({metrics:window.planetPerformance || null, world:window.planetWorldState || null,
    room:window.trainingRoomState || null, visibility:document.visibilityState}));
}
const roaming = value => !value.room && value.metrics?.avatar?.ready && !value.metrics?.preparing_roam && value.metrics?.player &&
  !value.metrics.player.overview && !value.metrics.player.entering && !value.metrics.player.paused;
const downloadsIdle = value => value.metrics?.packs?.all_ready === true &&
  !(value.metrics.packs.background?.jobs?.length) && !(value.metrics.packs.background?.reserved_bytes);
async function until(name, predicate, timeout = 180000) {
  report.pending = name; save();
  const end = Date.now() + timeout;
  let last;
  do {
    if (aborted) throw Error('Benchmark aborted');
    last = await state();
    if (predicate(last)) { report.pending = null; return last; }
    await delay(400);
  } while (Date.now() < end);
  report.timeout_state = last;
  throw Error(`Timed out: ${name}`);
}
async function canvasBox() {
  const box = await page.locator('#canvas').boundingBox();
  if (!box?.width || !box?.height) throw Error('Canvas has no visible bounds');
  const scale = Math.min(box.width / baseWidth, box.height / baseHeight);
  return {x:box.x+(box.width-baseWidth*scale)/2, y:box.y+(box.height-baseHeight*scale)/2,
    width:baseWidth*scale, height:baseHeight*scale};
}
async function click(name, expression = null) {
  for (let attempt = 0; attempt < 20; attempt++) {
    const before = await state(), buttons = before.metrics?.buttons || [], bounds = await canvasBox();
    const matches = button => name ? button.name === name : expression.test(button.text);
    const button = buttons.find(row => row.visible && matches(row));
    if (button) {
      await page.mouse.click(bounds.x+button.center[0]*bounds.width, bounds.y+button.center[1]*bounds.height);
      await until('fresh button response', value => value.metrics?.ticks_ms > before.metrics.ticks_ms, 30000);
      return;
    }
    const rows = buttons.filter(row => row.visible && /^\d{2}\s/.test(row.text));
    const anchor = rows[Math.floor(rows.length/2)]?.center || [.15,.72], target = buttons.find(matches);
    await page.mouse.move(bounds.x+anchor[0]*bounds.width, bounds.y+anchor[1]*bounds.height);
    await page.mouse.wheel(0, target && target.center[1]<anchor[1] ? -150 : 150);
    await delay(1000);
  }
  report.button_failure = {requested:name || String(expression), state:await state(), bounds:await canvasBox()}; save();
  throw Error(`No clickable button: ${name || expression}`);
}
async function keyFor(key, milliseconds) {
  await page.keyboard.down(key); pressed.add(key);
  try { await delay(milliseconds); }
  finally { await page.keyboard.up(key); pressed.delete(key); }
}
async function settled() {
  let stable = await until('roaming / detail / downloads ready', value => roaming(value) && downloadsIdle(value) &&
    value.metrics.streaming.pending_regions === 0 && value.metrics.streaming.ready_districts >= 1);
  return until('streaming stable for two telemetry intervals', value => {
    if (!roaming(value) || !downloadsIdle(value) || value.metrics.streaming.pending_regions !== 0 ||
        value.metrics.streaming.operations !== stable.metrics.streaming.operations) { stable = value; return false; }
    return value.metrics.ticks_ms >= stable.metrics.ticks_ms + 2000;
  });
}
async function setProfile(profile) {
  const current = await state(), graphics = current.metrics?.graphics;
  if (!current.metrics?.settings_open && graphics?.quality_profile === profile && !graphics.msaa_enabled &&
      graphics.applied_msaa === 0 && graphics.frame_limit === 60 && graphics.applied_max_fps === 60) {
    check(`${profile}: matched graphics controls already applied`, true, graphics);
    return;
  }
  await click('GraphicsSettingsButton');
  // Re-clicking an already selected preset resets AA/FPS. Its old telemetry
  // can satisfy a profile-only predicate before those side effects arrive.
  if ((await state()).metrics.graphics.quality_profile !== profile) {
    await click(profile === 'low' ? 'QualityLow' : 'QualityStandard');
    await until('selected preset and preset AA applied', value => value.metrics?.graphics?.quality_profile === profile &&
      value.metrics.graphics.msaa_enabled === (profile === 'standard') && value.metrics.graphics.applied_msaa === (profile === 'standard' ? 1 : 0));
  }
  if ((await state()).metrics.graphics.msaa_enabled) {
    await click('MSAAToggle');
    await until('MSAA explicitly off', value => !value.metrics?.graphics?.msaa_enabled && value.metrics?.graphics?.applied_msaa === 0);
  }
  const beforeFrameChoice = (await state()).metrics.graphics;
  if (beforeFrameChoice.frame_limit !== 60 || beforeFrameChoice.applied_max_fps !== 60) await click('FPS60');
  const applied = await until('matched 60 FPS / MSAA off', value => value.metrics?.graphics?.quality_profile === profile &&
    value.metrics.graphics.frame_limit === 60 && value.metrics.graphics.applied_max_fps === 60 &&
    !value.metrics.graphics.msaa_enabled && value.metrics.graphics.applied_msaa === 0);
  check(`${profile}: matched graphics controls`, true, applied.metrics.graphics);
  await click('CloseGraphicsSettings');
}
async function resetRoad() {
  // Newly completed downloads remove the preparation panel and shift controls.
  // Wait for settled/fresh telemetry before using its on-screen coordinates.
  await settled();
  if (!(await state()).metrics.destinations_open) await click(null, /選擇目的地/);
  await click(null, new RegExp('^\\d{2}\\s+' + station.label));
  await until('counseling arrival', value => roaming(value) && value.metrics.nearest_id === 'counseling');
  if ((await state()).metrics.destinations_open) await click(null, /收起目的地/);
  await settled();
  for (let attempt = 0; attempt < 12; attempt++) {
    const before = await state(), position = before.metrics.player.position;
    const localX = layout.radius * position[0] / position[1];
    if (Math.abs(localX) <= .4) return settled();
    await keyFor(localX > 0 ? 'a' : 'd', Math.min(450, Math.max(70, (Math.abs(localX)-.2)/3.8*1000)));
    await until('fresh road alignment', value => value.metrics?.ticks_ms > before.metrics.ticks_ms+1000, 30000);
  }
  throw Error('Real movement did not align to counseling road');
}
async function sample(profile, repetition, workload, condition = profile) {
  const start = await state(), observations = [{epoch_ms:Date.now(), state:start}];
  const bounds = await canvasBox(), pointerX = bounds.x+bounds.width*.69, pointerY = bounds.y+bounds.height*.48;
  if (workload === 'turn') await page.mouse.move(pointerX, pointerY);
  await page.evaluate(() => {
    const probe = window.__smoothingProbe;
    probe.intervals=[]; probe.longTasks=[]; probe.viewports=[]; probe.last=null;
    probe.since=performance.now(); probe.active=true;
  });
  const begin = Date.now(), end = begin + duration;
  let nextObservation = begin + 1000, moves = 0;
  try {
    if (workload === 'walk') { await page.keyboard.down('s'); pressed.add('s'); }
    if (workload === 'turn') await page.mouse.down({button:'right'});
    while (Date.now() < end) {
      if (workload === 'turn') {
        const elapsed = Date.now()-begin;
        await page.mouse.move(pointerX+130*Math.sin(elapsed/1500*Math.PI)+80*elapsed/duration, pointerY); moves++;
      }
      await delay(Math.min(workload === 'turn' ? 80 : 250, Math.max(1, end-Date.now())));
      if (Date.now() >= nextObservation) {
        observations.push({epoch_ms:Date.now(), state:await state()}); nextObservation += 1000;
      }
    }
  } finally {
    if (workload === 'walk') { await page.keyboard.up('s'); pressed.delete('s'); }
    if (workload === 'turn') await page.mouse.up({button:'right'});
  }
  const measured = await page.evaluate(() => {
    const probe = window.__smoothingProbe; probe.active=false;
    return {duration_ms:performance.now()-probe.since, intervals_ms:probe.intervals,
      long_tasks:probe.longTasks, observed_gl_viewports:probe.viewports};
  });
  const finish = await state();
  const fresh = observations.filter((row, index) => index === 0 || row.state.metrics?.ticks_ms !== observations[index-1].state.metrics?.ticks_ms);
  const segments = fresh.slice(1).map((row, index) => Math.hypot(...row.state.metrics.player.position.map((value, axis) => value-fresh[index].state.metrics.player.position[axis])));
  const headings = observations.map(row => row.state.metrics?.player?.heading || row.state.world?.heading).filter(Boolean);
  const headingChange = headings.length > 1 ? Math.max(...headings.map(heading => Math.hypot(...heading.map((value, axis) => value-headings[0][axis])))) : null;
  const entry = {profile, condition, viewport:page.viewportSize(), repetition, workload, epoch_start:begin, start, end:finish, observations,
    ...measured, ...summarize(measured.intervals_ms),
    streaming_operations_delta:finish.metrics.streaming.operations-start.metrics.streaming.operations,
    downloads_idle_entire_sample:[start, ...observations.map(row => row.state), finish].every(downloadsIdle),
    visibility_entire_sample:[start, ...observations.map(row => row.state), finish].every(value => value.visibility === 'visible'),
    movement:{segments_world_units:segments, measured_path_world_units:segments.reduce((sum, value) => sum+value,0),
      continuously_moving:workload === 'walk' ? segments.length >= 3 && segments.every(value => value > .15) : null,
      max_heading_displacement:headingChange, mouse_move_events:moves,
      turn_verification:workload === 'turn' ? (headingChange === null ? 'Release telemetry does not expose heading; dispatched right-button mouse input and before/after screenshots require visual review' : 'Heading changes observed through read-only telemetry') : null}};
  report.phases.push(entry);
  check(`${profile}/${repetition}/${workload}: submitted frames observed`, entry.interval_count >= 10, entry.interval_count);
  check(`${profile}/${repetition}/${workload}: page remained visible`, entry.visibility_entire_sample);
  if (workload === 'walk') {
    entry.movement_review = reviewMotion(observations);
    check(`${profile}/${repetition}: sustained real walking observed`, entry.movement_review.sustained_motion_observed, entry.movement_review);
  }
  if (workload === 'turn') {
    check(`${profile}/${repetition}: sustained right-button input dispatched`, moves >= 10, moves);
    if (headingChange !== null) check(`${profile}/${repetition}: real heading changed`, headingChange > .2, entry.movement);
  }
  const image = path.join(out, `${label}-${condition}-${repetition}-${workload}.png`);
  await page.screenshot({path:image, timeout:60000}); entry.screenshot=image;
  save();
  console.log(JSON.stringify({profile, condition, repetition, workload, ...summarize(measured.intervals_ms), streaming_delta:entry.streaming_operations_delta}));
}

async function visualSmoke() {
  // This runs after timing and summary are final. Screenshot/extra input costs
  // cannot enter the interval arrays or change the measured workload order.
  await page.evaluate(() => { window.__smoothingProbe.active = false; });
  report.visual_smoke = {started:new Date().toISOString(), captures:[],
    method:'Post-benchmark real Shift+S run, Space jump, sequential screenshots, recovery walk. Actual screenshot timing is recorded because capture can miss short animation states. These samples require visual inspection and are not complete animation or cloth-intersection proof.',
    room_and_seats:'Not exercised by this harness; use the dedicated room/seat validation.'};
  const capture = async (name, origin, requestedElapsed = null) => {
    const image = path.join(out, `${label}-visual-${name}.png`);
    const captureStart = Date.now();
    await page.screenshot({path:image, timeout:60000});
    const captured = Date.now();
    report.visual_smoke.captures.push({name, requested_elapsed_ms:requestedElapsed,
      capture_start_elapsed_ms:captureStart-origin, capture_complete_elapsed_ms:captured-origin,
      image, state:await state()});
    save();
  };
  await setProfile('low'); await resetRoad();
  const readyTime = Date.now();
  await capture('road-ready', readyTime);
  const runTime = Date.now();
  try {
    for (const key of ['Shift','s']) { await page.keyboard.down(key); pressed.add(key); }
    await delay(550); await capture('run', runTime, 550);
  } finally {
    for (const key of ['s','Shift']) { await page.keyboard.up(key); pressed.delete(key); }
  }
  const jumpTime = Date.now();
  await page.keyboard.press('Space');
  for (const elapsed of [0,150,300,450,650,900,1200,1600,2200,3000]) {
    await delay(Math.max(1, jumpTime+elapsed-Date.now()));
    await capture(`jump-${String(elapsed).padStart(4,'0')}`, jumpTime, elapsed);
  }
  await delay(500);
  const recoveryTime = Date.now();
  await keyFor('s', 900); await capture('recovery-walk', recoveryTime, 900);
  await delay(1200);
  const recovered = await state();
  check('Visual smoke: resumed roaming after real run/jump inputs', roaming(recovered), recovered.metrics?.player);
  check('Visual smoke: actor remains above planet surface',
    Math.hypot(...recovered.metrics.player.position) >= layout.radius-1, recovered.metrics.player.position);
  await capture('recovered-standing', recoveryTime);
  report.visual_smoke.finished = new Date().toISOString(); save();
}

(async () => {
  try {
    browserServer = await chromium.launchServer({channel:'chrome', headless:true});
    browser = await chromium.connect(browserServer.wsEndpoint());
    report.browser = browser.version(); report.browser_pid = browserServer.process().pid;
    const context = await browser.newContext({viewport:report.viewport});
    await context.addInitScript(installProbe);
    page = await context.newPage(); page.setDefaultTimeout(30000);
    page.on('pageerror', error => report.errors.push(String(error)));
    page.on('console', message => {
      if (message.type() === 'error' && !message.text().includes('404 (File not found)')) report.errors.push(message.text());
    });
    page.on('request', request => {
      if (/\.pck(?:\?|$)/.test(request.url())) report.requests.push({url:request.url(), epoch_ms:Date.now()});
    });
    await page.goto(url.href, {waitUntil:'domcontentloaded', timeout:180000});
    await until('world telemetry and input', value => value.metrics?.buttons?.length);
    report.build_id = await page.locator('meta[name="little-world-build"]').getAttribute('content');
    const manifest = await context.request.get(new URL('index.release.json', url).href);
    if (!manifest.ok()) throw Error(`Release manifest HTTP ${manifest.status()}`);
    report.served_release = await manifest.json();
    check('HTML and release manifest identify the same build', report.build_id === report.served_release.build_id);
    if (expectedRelease) {
      check('Expected build and source fingerprint match served release', report.build_id === expectedRelease.build_id &&
        report.served_release.source_sha256 === expectedRelease.source_sha256);
    }
    if (report.errors.length) throw Error('Release identity validation failed');
    report.gpu = await page.evaluate(() => {
      const gl = document.getElementById('canvas').getContext('webgl2');
      const debug = gl.getExtension('WEBGL_debug_renderer_info');
      return {renderer:gl.getParameter(debug ? debug.UNMASKED_RENDERER_WEBGL : gl.RENDERER),
        vendor:gl.getParameter(debug ? debug.UNMASKED_VENDOR_WEBGL : gl.VENDOR), version:gl.getParameter(gl.VERSION)};
    });
    for (let repetition = 1; repetition <= repeats; repetition++) {
      const profiles = profileOption === 'both' ? (repetition % 2 ? ['low','standard'] : ['standard','low']) : [profileOption];
      const conditions = scaleDiagnostic ? [...report.scale_diagnostic.conditions] : profiles.map(profile => ({name:profile, profile}));
      if (scaleDiagnostic && repetition % 2 === 0) conditions.reverse();
      for (const condition of conditions) {
        const profile = scaleDiagnostic ? 'low' : condition.profile;
        report.profile_order.push({repetition, profile, condition:condition.name, viewport:condition.viewport || report.viewport});
        if (scaleDiagnostic) await page.setViewportSize(condition.viewport);
        await setProfile(profile);
        if (scaleDiagnostic) {
          const applied = await until('diagnostic matched 3D pixels and selected scale', value => {
            const graphics = value.metrics?.graphics;
            return graphics?.internal_3d_pixels?.[0] === 1152 && graphics?.internal_3d_pixels?.[1] === 720 &&
              Math.abs(graphics.scaling_3d_scale-condition.expected_scale) < .002;
          });
          check(`${condition.name}/${repetition}: matched internal 3D resolution`, true, applied.metrics.graphics);
        }
        if ((await state()).metrics.overview) { await page.keyboard.press('Tab'); await until('first roam', roaming); }
        if (repetition === 1 && !scaleDiagnostic) { await resetRoad(); await keyFor('s', 1200); await settled(); }
        for (const workload of scaleDiagnostic ? ['standing','turn'] : ['standing','walk','turn']) {
          // Standing and walking deliberately share the same starting position.
          if (workload !== 'walk') await resetRoad();
          if (workload === 'turn') await page.screenshot({path:path.join(out, `${label}-${condition.name}-${repetition}-turn-before.png`), timeout:60000});
          await sample(profile, repetition, workload, condition.name);
        }
      }
    }
    report.summary = [];
    for (const condition of [...new Set(report.phases.map(phase => phase.condition))]) for (const workload of ['standing','walk','turn']) {
      const phases = report.phases.filter(phase => phase.condition === condition && phase.workload === workload);
      if (phases.length) report.summary.push({profile:phases[0].profile, condition, workload, repetitions:phases.length,
        ...summarize(phases.flatMap(phase => phase.intervals_ms)),
        repetitions_with_streaming_work:phases.filter(phase => phase.streaming_operations_delta !== 0).length});
    }
    report.timing_finished = new Date().toISOString(); save();
    if (visualSmokeRequested) await visualSmoke();
    report.finished = new Date().toISOString();
  } catch (error) { report.errors.push(String(error.stack || error)); }
  finally {
    save();
    await closeBrowser(); clearTimeout(watchdog);
    report.runner_finished = new Date().toISOString(); save();
    console.log(JSON.stringify({file:reportFile, phases:report.phases.length, errors:report.errors}));
    process.exitCode = report.errors.length ? 1 : 0;
  }
})();
