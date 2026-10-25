// Local release QA using actual mouse/key/touch inputs and read-only telemetry.
// Chrome CPU throttling is synthetic CPU stress, never an old GPU/iPhone test.
const {chromium} = require('playwright');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const assert = require('node:assert/strict');
const site = path.resolve(process.argv[2] || '_site');
const label = (process.argv[3] || 'web-constrained-20261021').replace(/[^a-zA-Z0-9_-]/g, '-');
const out = path.resolve('deliverables/low-end', label);
fs.mkdirSync(out, {recursive:true});
const release = JSON.parse(fs.readFileSync(path.join(site, 'index.release.json'), 'utf8'));
const report = {started:new Date().toISOString(), site, expected_build_id:release.build_id, checks:[], runs:[], errors:[],
  method:'Fresh desktop Chrome contexts, local release files, actual mouse/keyboard and CDP touch input. Read-only opt-in Godot telemetry. CPU throttling changes main-thread CPU throughput only.',
  limitations:['No iPhone Safari or old physical computer tested.', 'CPU throttle does not emulate GPU speed, memory limits, heat or power consumption.', 'Engine allocation counters are not browser RSS or device available memory.', 'Frame cadence comes from opt-in monotonic foreground telemetry; no GPU timing claim.']};
let server, browser, activePage;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const save = () => fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
function check(name, passed, evidence=null) {
  report.checks.push({name, passed:Boolean(passed), evidence}); save(); console.log(passed ? 'PASS' : 'FAIL', name);
  assert.ok(passed, name);
}
const read = page => page.evaluate(() => ({metrics:window.planetPerformance || null,
  visible:document.visibilityState === 'visible', focused:document.hasFocus(), url:location.href}));
async function waitFor(page, predicate, description, timeout=180000) {
  const deadline = Date.now()+timeout; let last;
  do { last=await read(page); if(predicate(last))return last; await delay(700); } while(Date.now()<deadline);
  throw Error('Timeout: '+description+' '+JSON.stringify(last?.metrics?.graphics || last));
}
async function inputBox(page, state) {
  const canvas=await page.locator('#canvas').boundingBox();
  const [width,height]=state.metrics.viewport;
  const scale=Math.min(canvas.width/width,canvas.height/height);
  return {x:canvas.x+(canvas.width-width*scale)/2,y:canvas.y+(canvas.height-height*scale)/2,width:width*scale,height:height*scale};
}
async function click(page, name) {
  for(let attempt=0;attempt<20;attempt++) {
    const state=await read(page), box=await inputBox(page,state);
    const button=state.metrics.buttons.find(button=>button.name===name);
    if(button?.visible && button.center.every(n=>n>=0&&n<=1)) {
      await page.mouse.click(box.x+box.width*button.center[0],box.y+box.height*button.center[1]);
      await waitFor(page,s=>s.metrics?.ticks_ms>state.metrics.ticks_ms,'button '+name,30000); return;
    }
    await page.mouse.move(box.x+box.width*.5,box.y+box.height*.5);
    await page.mouse.wheel(0,button&&button.center[1]<.5?-180:180); await delay(800);
  }
  throw Error('Button unavailable: '+name);
}
function compact(snapshot) {
  const s=snapshot.metrics;
  return {at:new Date().toISOString(),visible:snapshot.visible,focused:snapshot.focused,ticks_ms:s.ticks_ms,
    player:s.player,graphics:s.graphics,streaming:s.streaming,minimap:s.minimap,
    draw_calls:s.draw_calls,primitives:s.primitives,nodes:s.nodes,render_buffer_bytes:s.render_buffer_bytes,
    render_texture_bytes:s.render_texture_bytes,frame_sample_valid:s.frame_sample_valid,sampling_foreground:s.sampling_foreground,
    frame_intervals:s.frame_intervals,frame_sample_window_ms:s.frame_sample_window_ms,
    frame_ms_mean:s.frame_ms_mean,frame_ms_p95:s.frame_ms_p95,frame_ms_max:s.frame_ms_max,frames_over_100_ms:s.frames_over_100_ms};
}
const distance=(a,b)=>Math.hypot(...a.map((v,i)=>v-b[i]));
function summarize(samples) {
  const unique=[...new Map(samples.map(s=>[s.ticks_ms,s])).values()];
  const valid=unique.filter(s=>s.visible&&s.focused&&s.frame_sample_valid&&s.sampling_foreground);
  const intervals=valid.reduce((sum,s)=>sum+s.frame_intervals,0), ms=valid.reduce((sum,s)=>sum+s.frame_sample_window_ms,0);
  const median=values=>values.length?[...values].sort((a,b)=>a-b)[Math.floor(values.length/2)]:null;
  const segments=unique.slice(1).map((s,i)=>({from:unique[i].ticks_ms,to:s.ticks_ms,distance:distance(s.player.position,unique[i].player.position)}));
  return {unique_samples:unique.length,valid_foreground_samples:valid.length,all_visible_focused:unique.every(s=>s.visible&&s.focused),
    delivered_interval_fps:ms?intervals*1000/ms:null,frame_intervals:intervals,measured_window_ms:ms,
    max_frame_ms:valid.length?Math.max(...valid.map(s=>s.frame_ms_max)):null,
    frames_over_100_ms:valid.reduce((sum,s)=>sum+s.frames_over_100_ms,0),
    draw_calls_median:median(valid.map(s=>s.draw_calls)),primitives_median:median(valid.map(s=>s.primitives)),
    moving_segments:segments.filter(s=>s.distance>.05).length,path_world_units:segments.reduce((sum,s)=>sum+s.distance,0),segments};
}
async function capture(page, name) {
  const filename=name+'.png'; await page.screenshot({path:path.join(out,filename),timeout:30000}); return filename;
}
async function movement(page, name, seconds=12, cdp=null, touch=false) {
  const phase={name,duration_requested_seconds:seconds,input:touch?'CDP touch joystick forward/back every 2 seconds':'Real W/S key forward/back every 2 seconds',samples:[]};
  const started=Date.now(); let held=null;
  try {
    for(let second=0;second<seconds;second++) {
      if(second%2===0) {
        if(held && !touch)await page.keyboard.up(held);
        if(touch) {
          if(held)await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
          const box=await page.locator('.lw-stick').boundingBox(); assert.ok(box,'touch joystick visible');
          const x=box.x+box.width/2,y=box.y+box.height/2+(second%4===0?-1:1)*box.width*.30;
          await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y,id:1,radiusX:4,radiusY:4,force:1}]}); held='touch';
        } else {held=second%4===0?'w':'s';await page.keyboard.down(held);}
      }
      await delay(1000); phase.samples.push(compact(await read(page)));
    }
  } finally {
    if(held) {if(touch)await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});else await page.keyboard.up(held);}
  }
  phase.elapsed_wall_seconds=(Date.now()-started)/1000; phase.summary=summarize(phase.samples);
  phase.screenshot=await capture(page,name); return phase;
}
async function startRun(name, options={}, query='?performance') {
  const context=await browser.newContext({viewport:{width:1280,height:800},deviceScaleFactor:1,...options});
  const page=await context.newPage(); activePage=page;
  const run={name,options,phases:[],errors:[],console:[],requests_failed:[]};report.runs.push(run);save();
  page.on('pageerror',error=>run.errors.push(String(error)));
  page.on('console',message=>{const text=message.text();if(/SCRIPT ERROR|Parse Error|SHADER ERROR|RuntimeError|INVALID_ENUM|INVALID_OPERATION|ERROR:/.test(text))run.errors.push(text);if(message.type()==='error'||message.type()==='warning')run.console.push({type:message.type(),text});});
  page.on('requestfailed',request=>run.requests_failed.push({url:request.url(),failure:request.failure()}));
  await page.goto('http://127.0.0.1:'+server.address().port+'/'+query,{waitUntil:'domcontentloaded',timeout:180000});
  await page.bringToFront();
  await waitFor(page,s=>s.metrics?.buttons?.length>0,'world telemetry');
  run.url=page.url(); run.build_id=await page.locator('meta[name="little-world-build"]').getAttribute('content');
  run.renderer=(await read(page)).metrics.renderer;
  run.browser_environment=await page.evaluate(()=>({userAgent:navigator.userAgent,maxTouchPoints:navigator.maxTouchPoints,devicePixelRatio,
    mobilePolicy:window.LittleWorldMobileMode,gpu:(()=>{const g=document.getElementById('canvas').getContext('webgl2');const e=g?.getExtension('WEBGL_debug_renderer_info');return g?(e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):g.getParameter(g.RENDERER)):null;})()}));
  const actualRelease=JSON.parse(fs.readFileSync(path.join(site,run.url.includes('/mobile/')?'mobile/index.release.json':'index.release.json'),'utf8'));
  check(name+' loads the exact local release',run.build_id===actualRelease.build_id,{actual:run.build_id,expected:actualRelease.build_id});
  return {context,page,run,cdp:await context.newCDPSession(page)};
}
const roamReady=s=>s.metrics?.avatar?.ready&&!s.metrics.overview&&!s.metrics.preparing_roam&&!s.metrics.player.entering&&!s.metrics.player.paused&&s.metrics.streaming.pending_regions===0;
function validateMove(name, phase) {
  check(name+' remains visible and focused',phase.summary.all_visible_focused,phase.summary);
  check(name+' records >= 10 seconds of actual movement input',phase.elapsed_wall_seconds>=10,phase.elapsed_wall_seconds);
  check(name+' responds repeatedly to movement',phase.summary.moving_segments>=4&&phase.summary.path_world_units>.5,phase.summary);
}
function validateBudget(name, phase) {
  check(name+' keeps constrained 30 FPS budget and zero full-detail chunks',phase.samples.every(s=>s.graphics.constrained_runtime&&s.graphics.applied_max_fps===30&&s.streaming.constrained_runtime&&s.streaming.loaded_chunks===0&&s.streaming.detail_nodes===0));
  check(name+' has actual rendered geometry',phase.samples.every(s=>s.draw_calls>0&&s.primitives>0));
}
(async()=>{try {
  server=http.createServer((request,response)=>{
    let name=decodeURIComponent(new URL(request.url,'http://localhost').pathname);if(name.endsWith('/'))name+='index.html';
    const file=path.resolve(site,'.'+name);
    if(!file.startsWith(site+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){response.writeHead(404).end();return;}
    const extension=path.extname(file),types={'.js':'application/javascript','.html':'text/html','.wasm':'application/wasm','.json':'application/json','.png':'image/png','.svg':'image/svg+xml','.css':'text/css'};
    response.writeHead(200,{'Content-Type':types[extension]||'application/octet-stream','Content-Length':fs.statSync(file).size,'Cache-Control':'no-store'});fs.createReadStream(file).pipe(response);
  });await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  browser=await chromium.launch({channel:'chrome',headless:true});report.browser=browser.version();
  {
    const {context,page,run,cdp}=await startRun('desktop-constrained');
    await click(page,'GraphicsSettingsButton');await click(page,'QualityMobile');await click(page,'FPS90');await click(page,'CloseGraphicsSettings');
    await page.keyboard.press('Tab');await waitFor(page,roamReady,'desktop roam ready');await delay(2500);
    const normal=await movement(page,'desktop-mobile-walking',12);run.phases.push(normal);save();validateMove('Desktop constrained',normal);validateBudget('Desktop constrained',normal);
    check('90 FPS preference remains stored while 30 is applied',normal.samples.every(s=>s.graphics.frame_limit===90&&s.graphics.applied_max_fps===30));
    await cdp.send('Emulation.setCPUThrottlingRate',{rate:4});
    const throttled=await movement(page,'desktop-mobile-cpu4x-walking',12);throttled.synthetic_cpu_throttle=4;run.phases.push(throttled);save();validateMove('Desktop 4x CPU experiment',throttled);validateBudget('Desktop 4x CPU experiment',throttled);
    await cdp.send('Emulation.setCPUThrottlingRate',{rate:1});
    check('Desktop has no script, shader or browser runtime errors',run.errors.length===0,run.errors);
    await context.close();
  }
  {
    const {context,page,run,cdp}=await startRun('desktop-automatic-pressure');
    await click(page,'GraphicsSettingsButton');await click(page,'QualityStandard');await click(page,'FPS60');await click(page,'CloseGraphicsSettings');
    await page.keyboard.press('Tab');await waitFor(page,roamReady,'full-detail roam ready');await delay(2500);
    run.before=compact(await read(page));
    check('Automatic escape begins in full detail without runtime pressure',!run.before.graphics.runtime_pressure&&!run.before.graphics.constrained_runtime&&run.before.streaming.loaded_chunks>0,run.before);
    for(const rate of [12,20]) {
      await cdp.send('Emulation.setCPUThrottlingRate',{rate});
      const stress=await movement(page,'automatic-pressure-cpu'+rate+'x',16);stress.synthetic_cpu_throttle=rate;run.phases.push(stress);save();
      if((await read(page)).metrics.graphics.runtime_pressure)break;
    }
    await cdp.send('Emulation.setCPUThrottlingRate',{rate:1});
    await waitFor(page,s=>s.metrics?.graphics?.runtime_pressure&&s.metrics.streaming.loaded_chunks===0,'automatic relief and detail release',30000);
    const recovered=await movement(page,'automatic-pressure-recovery-cpu1x',12);recovered.synthetic_cpu_throttle=1;run.phases.push(recovered);save();validateMove('Automatic relief recovery',recovered);validateBudget('Automatic relief recovery',recovered);
    check('Pressure remains active after CPU throttle is removed',recovered.samples.every(s=>s.graphics.runtime_pressure&&s.graphics.quality_profile==='standard'&&s.graphics.frame_limit===60&&s.graphics.applied_max_fps===30));
    check('Automatic relief run has no runtime errors',run.errors.length===0,run.errors);
    await context.close();
  }
  {
    const {context,page,run,cdp}=await startRun('mobile-interface-touch',{viewport:{width:390,height:844},hasTouch:true,isMobile:true},'?performance&renderer=mobile&touch=1');
    await click(page,'CompactStartRoaming');await waitFor(page,roamReady,'mobile interface roam ready');
    await page.locator('.lw-stick').waitFor({state:'visible',timeout:30000});await delay(2500);
    const touch=await movement(page,'mobile-interface-touch-walking',12,cdp,true);run.phases.push(touch);save();validateMove('Mobile interface touch',touch);validateBudget('Mobile interface touch',touch);
    check('Mobile policy uses compact controls and mobile rendering budget',touch.samples.every(s=>s.graphics.mobile_web&&Math.min(...s.graphics.internal_3d_pixels)<=432),run.browser_environment);
    check('Mobile interface has no script, shader or browser runtime errors',run.errors.length===0,run.errors);
    await context.close();
  }
  report.passed=true;
}catch(error){report.errors.push(String(error.stack||error));console.error(error);report.passed=false;process.exitCode=1;
  if(activePage&&!activePage.isClosed()){report.failure_state=await read(activePage).catch(()=>null);await capture(activePage,'failure').catch(()=>{});}
}finally{report.finished=new Date().toISOString();save();if(browser)await browser.close();if(server){server.closeAllConnections();server.close();}}})();
