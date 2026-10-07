// QA only: local release, real input, no production/engine state mutation.
// Run only when the other browser/native GPU measurement jobs have finished.
const fs = require('node:fs');
const path = require('node:path');
function bufferArgumentBytes(name,args) {
  const source=args[name==='bufferData'?1:2];
  if(typeof source==='number')return source;
  if(!source)return 0;
  const elementBytes=source.BYTES_PER_ELEMENT || 1;
  const available=Math.max(0,Math.floor(source.byteLength/elementBytes)-Number(args[3]||0));
  // WebGL2 srcOffset/length count elements of the provided typed array.
  // Omitted or zero length means the remainder, not the entire WASM heap view.
  const length=Number(args[4]||0);
  return Math.max(0,Math.min(available,length>0?length:available))*elementBytes;
}
if(process.argv[2]==='--self-test') {
  const assert=require('node:assert/strict');
  assert.equal(bufferArgumentBytes('bufferData',[0,64,0]),64);
  assert.equal(bufferArgumentBytes('bufferData',[0,new Uint8Array(1024),0,128,32]),32);
  assert.equal(bufferArgumentBytes('bufferData',[0,new Float32Array(256),0,16,4]),16);
  assert.equal(bufferArgumentBytes('bufferData',[0,new Float32Array(256),0,16,0]),960);
  assert.equal(bufferArgumentBytes('bufferSubData',[0,512,new Uint16Array(64),8,12]),24);
  assert.equal(bufferArgumentBytes('bufferSubData',[0,512,new Uint16Array(64),8]),112);
  assert.equal(bufferArgumentBytes('bufferSubData',[0,512,new DataView(new ArrayBuffer(64)),4,12]),12);
  assert.equal(bufferArgumentBytes('bufferData',[0,new ArrayBuffer(40),0]),40);
  assert.equal(bufferArgumentBytes('bufferData',[0,null,0]),0);
  console.log('9 WebGL buffer overload byte accounting checks passed');process.exit(0);
}
const {chromium} = require('playwright');
const [target, label = 'movement-profile', durationArgument = '4000'] = process.argv.slice(2);
if (!target) throw Error('Expected localhost URL, optional report label and phase duration in ms');
const url = new URL(target);
if (!['localhost', '127.0.0.1'].includes(url.hostname)) throw Error('Localhost only');
const duration = Number(durationArgument);
if (!Number.isFinite(duration) || duration < 1000 || duration > 15000) throw Error('Phase duration must be 1000..15000 ms');
url.searchParams.set('performance', '');
const directory = path.resolve('deliverables/low-end');
fs.mkdirSync(directory, {recursive:true});
const reportFile = path.join(directory, `${label}.json`);
const report = {url:url.href, started:new Date().toISOString(), viewport:{width:1280,height:800}, phases:[], errors:[],
  method:'Local actual release with real keyboard/mouse. Matched standing/walking phases repeated with instrumentation off, WebGL API wall timers only, and CDP sampling only. Warmup walking precedes measurements. Streaming must settle before each pair. rAF intervals measure CPU submission cadence, not GPU presentation; WebGL call wall times include synchronous driver waits and are not pure GPU times. CDP samples include JS/WASM/main-thread activity, not an exhaustive engine subsystem profiler.'};
report.route={destination:'counseling',alignment:'Real A/D input aligns district x to 0 +/- 0.4 world unit before each pair',moving_key:'s',reason:'Teleport faces civic building at (6,-7); directly walking backwards also approaches houses near (5,8). The central x=0 corridor follows the authored road/bridge approach used by crosswalk QA.'};
report.buffer_metric_note='declared_buffer_argument_bytes resolves WebGL2 typed-array srcOffset/length overloads. It counts requested allocation/upload byte spans, not observed GPU traffic or retained memory. Earlier probe revisions incorrectly counted the whole WASM view.';
const save = () => fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let server, browser, page, cdp;
const deadline = setTimeout(() => { report.errors.push('10 minute watchdog timeout'); save(); server?.kill(); }, 600000);

function installProbe(bufferArgumentBytes) {
  const probe = window.__movementProbe = {enabled:false, calls:{}, parameters:{}, frames:[], longTasks:[], viewports:[], sampleStart:0, lastFrame:null, frameSerial:0, currentFrame:0, drawnFrame:-1};
  const transformFeedback = new WeakMap();
  const enumNames={};
  for(const Type of [window.WebGLRenderingContext,window.WebGL2RenderingContext]) {
    if(!Type)continue;
    for(const [name,descriptor]of Object.entries(Object.getOwnPropertyDescriptors(Type.prototype))) {
      if(typeof descriptor.value==='number' && /^[A-Z0-9_]+$/.test(name)) {
        const names=enumNames[descriptor.value] ||= [];
        if(!names.includes(name))names.push(name);
      }
    }
  }
  const originalRaf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = callback => originalRaf(timestamp => {
    const previous = probe.currentFrame;
    probe.currentFrame = ++probe.frameSerial;
    try { return callback(timestamp); }
    finally {
      if (probe.drawnFrame === probe.currentFrame) {
        const now = performance.now();
        if (probe.lastFrame !== null) probe.frames.push(now - probe.lastFrame);
        probe.lastFrame = now;
      }
      probe.currentFrame = previous;
    }
  });
  // Each prototype owns different entry points; inherited functions are not
  // wrapped twice. Preserve receiver and arguments exactly.
  for (const Type of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
    if (!Type) continue;
    for (const name of Object.getOwnPropertyNames(Type.prototype)) {
      if (name === 'constructor') continue;
      const descriptor = Object.getOwnPropertyDescriptor(Type.prototype, name);
      if (typeof descriptor?.value !== 'function') continue;
      const original = descriptor.value;
      const isDraw = /^(drawArrays|drawElements)/.test(name);
      Object.defineProperty(Type.prototype, name, {...descriptor, value:function(...args) {
        if (name === 'clear' || name === 'clearBufferfv') probe.drawnFrame = probe.currentFrame;
        if (name === 'beginTransformFeedback') transformFeedback.set(this, true);
        if (name === 'viewport') {
          const dimensions = `${args[2]}x${args[3]}`;
          if (!probe.viewports.includes(dimensions)) probe.viewports.push(dimensions);
        }
        const enabled = probe.enabled;
        const key = enabled && isDraw ? `${name}:${transformFeedback.get(this) ? 'transform_feedback' : 'raster'}:mode_${args[0]}` : name;
        let parameter;
        if(enabled && name==='getParameter') {
          parameter=probe.parameters[args[0]];
          if(!parameter)parameter=probe.parameters[args[0]]={enum_value:args[0],enum_hex:'0x'+Number(args[0]).toString(16),enum_names:enumNames[args[0]]||[],calls:0,total_ms:0,max_ms:0,calls_over_1_ms:0,calls_over_10_ms:0,first_stack:new Error('First getParameter '+args[0]).stack};
        }
        const start = enabled ? performance.now() : 0;
        let returned;
        try { returned=original.apply(this,args); return returned; }
        finally {
          if (name === 'endTransformFeedback') transformFeedback.set(this, false);
          if (enabled) {
            const elapsed = performance.now() - start;
            const record = probe.calls[key] ||= {calls:0,total_ms:0,max_ms:0,calls_over_1_ms:0,calls_over_10_ms:0,declared_buffer_argument_bytes:0};
            record.calls++; record.total_ms += elapsed; record.max_ms = Math.max(record.max_ms, elapsed);
            if (elapsed > 1) record.calls_over_1_ms++;
            if (elapsed > 10) record.calls_over_10_ms++;
            if (name === 'bufferData' || name === 'bufferSubData') {
              record.declared_buffer_argument_bytes += bufferArgumentBytes(name,args);
            }
            if(parameter) {
              parameter.calls++;parameter.total_ms+=elapsed;parameter.max_ms=Math.max(parameter.max_ms,elapsed);
              if(elapsed>1)parameter.calls_over_1_ms++;
              if(elapsed>10)parameter.calls_over_10_ms++;
              if(parameter.calls===1)parameter.first_result=returned===null || ['boolean','number','string'].includes(typeof returned)?returned:Object.prototype.toString.call(returned);
            }
          }
        }
      }});
    }
  }
  try { new PerformanceObserver(list => {
    for (const entry of list.getEntries()) if (entry.startTime >= probe.sampleStart) probe.longTasks.push({start_ms:entry.startTime,duration_ms:entry.duration});
  }).observe({type:'longtask',buffered:true}); } catch {}
}

async function state() {
  return page.evaluate(() => ({metrics:window.planetPerformance, room:window.trainingRoomState}));
}
const roaming = value => !value.room && value.metrics?.avatar?.ready && !value.metrics?.preparing_roam && value.metrics?.player &&
  !value.metrics.player.overview && !value.metrics.player.entering && !value.metrics.player.paused;
async function until(name, predicate, timeout = 180000) {
  const end = Date.now() + timeout;
  report.pending = name; save();
  let value;
  while (Date.now() < end) {
    value = await state();
    if (predicate(value)) { report.pending = null; save(); return value; }
    await delay(400);
  }
  throw Error(`Timeout ${name}: ${JSON.stringify(value)}`);
}
async function canvasBox() {
  const bounds = await page.locator('#canvas').boundingBox();
  const scale = Math.min(bounds.width/1440, bounds.height/900);
  return {x:bounds.x+(bounds.width-1440*scale)/2,y:bounds.y+(bounds.height-900*scale)/2,width:1440*scale,height:900*scale};
}
async function click(name, expression) {
  for (let attempt=0; attempt<20; attempt++) {
    const before = await state();
    const matches = button => name ? button.name === name : expression.test(button.text);
    const buttons = before.metrics?.buttons || [];
    const button = buttons.find(row => row.visible && matches(row));
    const bounds = await canvasBox();
    if (button) {
      await page.mouse.click(bounds.x+button.center[0]*bounds.width,bounds.y+button.center[1]*bounds.height);
      await until('fresh button response', value => value.metrics?.ticks_ms > before.metrics.ticks_ms, 30000);
      return;
    }
    const visible = buttons.filter(row => row.visible && /^\d{2}\s/.test(row.text));
    const anchor = visible[Math.floor(visible.length/2)]?.center || [.15,.72];
    const targetButton = buttons.find(matches);
    await page.mouse.move(bounds.x+anchor[0]*bounds.width,bounds.y+anchor[1]*bounds.height);
    await page.mouse.wheel(0,targetButton && targetButton.center[1]<anchor[1] ? -150 : 150);
    await delay(1200);
  }
  throw Error(`Button missing: ${name || expression}`);
}
async function holdKey(key,milliseconds) {
  await page.keyboard.down(key);
  try { await delay(milliseconds); }
  finally { await page.keyboard.up(key); }
}
async function settled() {
  let stable = await until('roaming and detail ready', value => roaming(value) && value.metrics.streaming.pending_regions===0 && value.metrics.streaming.ready_districts>=1);
  // Require a later telemetry snapshot with the same operation counter so
  // chunk load/register/unload work is not confused with steady walking cost.
  await until('streaming operations stable', value => {
    if (!roaming(value) || value.metrics.streaming.pending_regions!==0 || value.metrics.streaming.operations!==stable.metrics.streaming.operations) {
      stable=value;
      return false;
    }
    return value.metrics.ticks_ms > stable.metrics.ticks_ms+1000;
  });
}
async function resetToCounseling() {
  const station = JSON.parse(fs.readFileSync('game/data/world_layout.json','utf8')).stations.find(row => row.id==='counseling');
  const before = await state();
  if (!before.metrics.destinations_open) await click(null,/選擇目的地/);
  await click(null,new RegExp('^\\d{2}\\s+'+station.label));
  await until('counseling destination',value => roaming(value) && value.metrics.nearest_id==='counseling');
  if ((await state()).metrics.destinations_open) await click(null,/收起目的地/);
  await settled();
  const radius=JSON.parse(fs.readFileSync('game/data/world_layout.json','utf8')).radius;
  for (let attempt=0;attempt<10;attempt++) {
    const before=await state(),position=before.metrics.player.position;
    const localX=radius*position[0]/position[1];
    if (Math.abs(localX)<=.4) { await settled(); return; }
    await holdKey(localX>0?'a':'d',Math.min(450,Math.max(70,(Math.abs(localX)-.2)/3.8*1000)));
    await until('fresh road alignment',value=>value.metrics?.ticks_ms>before.metrics.ticks_ms+1000,30000);
  }
  throw Error('Could not align to counseling central road with real movement');
}
function cpuSummary(profile) {
  const nodes = new Map(profile.nodes.map(node => [node.id,node]));
  const self = new Map();
  for (let i=0;i<(profile.samples || []).length;i++) {
    const id = profile.samples[i];
    self.set(id,(self.get(id)||0)+(profile.timeDeltas?.[i]||0));
  }
  return {duration_ms:(profile.endTime-profile.startTime)/1000,samples:profile.samples?.length||0,
    hottest_self_frames:[...self].sort((a,b)=>b[1]-a[1]).slice(0,50).map(([id,time])=>({self_sample_ms:time/1000,...nodes.get(id)?.callFrame}))};
}
async function phase(mode, moving) {
  const name = `${mode}-${moving?'moving':'standing'}`;
  const startState = await state();
  await page.evaluate(enabled => {
    const probe = window.__movementProbe;
    probe.enabled=enabled;probe.calls={};probe.parameters={};probe.frames=[];probe.longTasks=[];probe.viewports=[];probe.lastFrame=null;probe.sampleStart=performance.now();
  },mode==='webgl');
  if (mode==='cpu') await cdp.send('Profiler.start');
  const started=Date.now();
  const observations=[{epoch_ms:started,state:startState}];
  if (moving) await page.keyboard.down('s');
  try {
    const end=started+duration;
    while (Date.now()<end) {
      await delay(Math.min(1000,end-Date.now()));
      observations.push({epoch_ms:Date.now(),state:await state()});
    }
  } finally { if (moving) await page.keyboard.up('s'); }
  let profile;
  if (mode==='cpu') profile=(await cdp.send('Profiler.stop')).profile;
  const metrics=await page.evaluate(() => {
    const probe=window.__movementProbe;probe.enabled=false;
    const frames=[...probe.frames].sort((a,b)=>a-b);
    const mean=frames.length?frames.reduce((sum,value)=>sum+value,0)/frames.length:null;
    return {duration_ms:performance.now()-probe.sampleStart,submission_frames:frames.length,mean_frame_ms:mean,
      average_submission_fps:mean?1000/mean:null,p95_ms:frames[Math.min(frames.length-1,Math.ceil(frames.length*.95)-1)]||null,
      frames_over_100_ms:frames.filter(value=>value>100).length,long_tasks:probe.longTasks,
      webgl_calls:Object.entries(probe.calls).map(([name,data])=>({name,...data})).sort((a,b)=>b.total_ms-a.total_ms),get_parameters:Object.values(probe.parameters).sort((a,b)=>b.total_ms-a.total_ms),observed_viewports:probe.viewports};
  });
  const endState=await state();
  // Keep movement verification limited to snapshots while the key was held;
  // a later Profiler.stop response must not add a stationary tail segment.
  const fresh=observations.filter((row,index)=>index===0 || row.state.metrics?.ticks_ms!==observations[index-1].state.metrics?.ticks_ms);
  const segments=[];
  for(let index=1;index<fresh.length;index++) {
    const previous=fresh[index-1].state.metrics,current=fresh[index].state.metrics;
    segments.push({from_ticks_ms:previous.ticks_ms,to_ticks_ms:current.ticks_ms,
      displacement_world_units:Math.hypot(...current.player.position.map((value,axis)=>value-previous.player.position[axis]))});
  }
  const movement={fresh_samples:fresh.length,segments,measured_path_world_units:segments.reduce((sum,row)=>sum+row.displacement_world_units,0),
    continuously_moving:moving ? segments.length>=2 && segments.every(row=>row.displacement_world_units>.15) : null};
  const entry={name,epoch_start:started,start:startState,end:endState,observations,movement,...metrics};
  if(moving && !movement.continuously_moving)report.errors.push(`${name}: per-second positions did not confirm continuous movement; inspect motion before interpreting timing`);
  if (profile) {
    const file=path.join(directory,`${label}-${name}.cpuprofile`);
    fs.writeFileSync(file,JSON.stringify(profile));entry.cpu_profile=file;entry.cpu_summary=cpuSummary(profile);
  }
  report.phases.push(entry);save();
}

(async()=>{try {
  server=await chromium.launchServer({channel:'chrome',headless:true});
  browser=await chromium.connect(server.wsEndpoint());report.browser=browser.version();
  const context=await browser.newContext({viewport:report.viewport});
  await context.addInitScript({content:`(${installProbe.toString()})(${bufferArgumentBytes.toString()});`});
  page=await context.newPage();
  page.on('pageerror',error=>report.errors.push(String(error)));
  page.on('console',message=>{if(message.type()==='error'&&!message.text().includes('404 (File not found)'))report.errors.push(message.text());});
  cdp=await context.newCDPSession(page);
  await cdp.send('Profiler.enable');await cdp.send('Profiler.setSamplingInterval',{interval:1000});
  await page.goto(url.href,{waitUntil:'domcontentloaded',timeout:180000});
  await until('world input ready',value=>value.metrics?.buttons?.length);
  report.build_id=await page.locator('meta[name="little-world-build"]').getAttribute('content');
  report.gpu=await page.evaluate(()=>{
    const gl=document.getElementById('canvas').getContext('webgl2');
    const debug=gl.getExtension('WEBGL_debug_renderer_info');
    return {renderer:debug?gl.getParameter(debug.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER),vendor:debug?gl.getParameter(debug.UNMASKED_VENDOR_WEBGL):gl.getParameter(gl.VENDOR),version:gl.getParameter(gl.VERSION)};
  });
  await click('GraphicsSettingsButton');await click('QualityLow');await click('CloseGraphicsSettings');
  await page.keyboard.press('Tab');await until('first roam',roaming);await settled();
  await resetToCounseling();
  report.warmup_start=await state();await holdKey('s',1200);await delay(1500);report.warmup_end=await state();save();
  for (const mode of ['baseline','webgl','cpu']) {
    await resetToCounseling();
    await phase(mode,false);await phase(mode,true);
  }
  report.finished=new Date().toISOString();
} catch(error) {
  report.errors.push(String(error.stack||error));
} finally {
  save();await browser?.close().catch(()=>{});await server?.close().catch(()=>{});clearTimeout(deadline);
  console.log(JSON.stringify({file:reportFile,phases:report.phases.length,errors:report.errors}));
  process.exitCode=report.errors.length?1:0;
}})();
