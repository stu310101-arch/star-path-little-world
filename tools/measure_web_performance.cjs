// Fixed-route browser benchmark. Telemetry is read-only; actions are real input.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const url = process.argv[2] || 'http://127.0.0.1:8765/build/performance-before/index.html';
const label = process.argv[3] || 'before';
const out = path.resolve('deliverables/performance');
fs.mkdirSync(out, { recursive: true });
const report = { label, url, started: new Date().toISOString(), viewport: { width: 1200, height: 800 }, runs: [], errors: [] };
let activeBrowser;
const watchdog = setTimeout(async () => {
  report.errors.push('Outer 12-minute benchmark timeout; browser did not complete the fixed route.');
  fs.writeFileSync(path.join(out,`${label}.json`),JSON.stringify(report,null,2));
  if (activeBrowser) await activeBrowser.close().catch(()=>{});
  process.exit(1);
}, 720000);
const percentile = (values, p) => values.length ? [...values].sort((a,b)=>a-b)[Math.min(values.length-1, Math.floor(values.length*p))] : null;
(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
  activeBrowser=browser;
  report.browser = browser.version();
  const context = await browser.newContext({ viewport: report.viewport });
  const page = await context.newPage();
  page.on('pageerror', e => report.errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error' && !m.text().includes('404 (File not found)')) report.errors.push(m.text()); });
  await page.addInitScript(() => {
    window.__perf = { ready: null, firstResponsiveFrame: null, frames: [], samples: [], longTasks: [] };
    window.addEventListener('planet-world-ready', () => { window.__perf.ready = performance.now(); });
    try { new PerformanceObserver(list => { for (const e of list.getEntries()) window.__perf.longTasks.push({start:e.startTime, duration:e.duration}); }).observe({type:'longtask', buffered:true}); } catch {}
    let last;
    function tick(t) { if (last && window.__perf.ready) { if(window.__perf.firstResponsiveFrame===null) window.__perf.firstResponsiveFrame=performance.now(); window.__perf.frames.push(t-last); } last=t; requestAnimationFrame(tick); }
    requestAnimationFrame(tick);
    setInterval(() => { if (window.planetWorldState || window.planetPerformance) window.__perf.samples.push({at:performance.now(), state:window.planetWorldState, metrics:window.planetPerformance}); }, 500);
  });
  const snapshot = () => page.evaluate(() => ({...window.__perf, resources:performance.getEntriesByType('resource').filter(e=>/index\.(pck|wasm|js)(\?|$)/.test(e.name)).map(e=>({name:e.name,start:e.startTime,end:e.responseEnd,duration:e.duration,transfer:e.transferSize,encoded:e.encodedBodySize,decoded:e.decodedBodySize})), heap:performance.memory?{used:performance.memory.usedJSHeapSize,total:performance.memory.totalJSHeapSize}:null, state:window.planetWorldState, metrics:window.planetPerformance}));
  const startTransition = () => page.evaluate(() => { window.__perf.frames=[]; window.__perf.samples=[]; window.__perf.longTasks=[]; });
  const transition = async () => {
    const s=await snapshot();
    s.raf_ms={median:percentile(s.frames,.5),p95:percentile(s.frames,.95),max:s.frames.length?Math.max(...s.frames):null};
    delete s.frames;
    return s;
  };
  const sample = async name => {
    await page.evaluate(() => { window.__perf.frames=[]; window.__perf.samples=[]; window.__perf.longTasks=[]; });
    await page.waitForTimeout(8000);
    const s=await snapshot();
    s.name=name;
    s.raf_ms={median:percentile(s.frames,.5),p95:percentile(s.frames,.95),max:Math.max(...s.frames)};
    delete s.frames;
    await page.screenshot({path:path.join(out, `${label}-${name}.png`),timeout:60000});
    return s;
  };
  for (const cache of ['cold','warm']) {
    console.log('START',label,cache);
    await page.goto(url,{waitUntil:'domcontentloaded',timeout:180000});
    await page.waitForFunction(()=>window.planetWorldReady===true,null,{timeout:300000});
    await page.waitForFunction(()=>window.__perf.firstResponsiveFrame!==null,null,{timeout:300000});
    report.build_id=await page.evaluate(()=>document.querySelector('meta[name="little-world-build"]')?.content || null);
    const startup=await snapshot();
    const ends=startup.resources.filter(r=>/\.(pck|wasm)/.test(r.name)).map(r=>r.end);
    report.runs.push({cache,ready_ms:startup.ready,first_responsive_frame_ms:startup.firstResponsiveFrame,after_download_ms:ends.length?startup.ready-Math.max(...ends):null,after_download_responsive_frame_ms:ends.length?startup.firstResponsiveFrame-Math.max(...ends):null,resources:startup.resources});
    console.log('READY',label,cache,startup.ready);
    fs.writeFileSync(path.join(out,`${label}.json`),JSON.stringify(report,null,2));
    if(cache==='cold') await page.goto('about:blank');
  }
  report.gpu=await page.evaluate(()=>{const c=document.createElement('canvas'); const g=c.getContext('webgl2');if(!g)return null;const e=g.getExtension('WEBGL_debug_renderer_info');return e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):g.getParameter(g.RENDERER);});
  if(process.argv.includes('--startup-only')) {
    report.finished=new Date().toISOString();
    fs.writeFileSync(path.join(out,`${label}.json`),JSON.stringify(report,null,2));
    await browser.close(); clearTimeout(watchdog);
    console.log(JSON.stringify({label,runs:report.runs,errors:report.errors}));
    return;
  }
  report.overview=await sample('overview');
  await page.mouse.move(900,400); await page.mouse.down(); await page.mouse.move(1080,445,{steps:15}); await page.mouse.up();
  await page.mouse.wheel(0,-250);
  report.rotate_zoom=await sample('rotate-zoom');
  await startTransition();
  await page.keyboard.press('Tab');
  await page.waitForTimeout(9000);
  report.near_transition=await transition();
  report.near=await sample('near');
  await page.mouse.move(850,420); await page.mouse.down(); await page.mouse.move(1100,460,{steps:12}); await page.mouse.up();
  report.fast_turn=await sample('fast-turn');
  await startTransition();
  await page.keyboard.press('Home'); await page.waitForTimeout(9000);
  report.teleport_transition=await transition();
  report.teleport=await sample('teleport');
  report.finished=new Date().toISOString();
  fs.writeFileSync(path.join(out,`${label}.json`),JSON.stringify(report,null,2));
  await browser.close();
  clearTimeout(watchdog);
  console.log(JSON.stringify({label,runs:report.runs,gpu:report.gpu,overview:report.overview.raf_ms,near:report.near.raf_ms,errors:report.errors}));
})().catch(async e=>{report.errors.push(String(e.stack));fs.writeFileSync(path.join(out,`${label}.json`),JSON.stringify(report,null,2));console.error(e);if(activeBrowser)await activeBrowser.close().catch(()=>{});clearTimeout(watchdog);process.exit(1);});
