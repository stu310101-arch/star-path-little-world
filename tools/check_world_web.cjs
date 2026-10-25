// Outdoor acceptance through the shipped UI. No teleport hooks, review hashes,
// JavaScript game-state assignments, engine calls, or synthetic telemetry.
// Run AFTER the coordinated export, e.g. node tools/check_world_web.cjs _site.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : fallback;
};
const site = path.resolve(args[0] && !args[0].startsWith('--') ? args[0] : '_site');
const output = path.resolve(option('--output', 'deliverables/world-redesign/web'));
const profile = option('--profile', 'standard');
const layouts = JSON.parse(fs.readFileSync(path.join(__dirname, '../game/data/world_layout.json'), 'utf8'));
const districts = JSON.parse(fs.readFileSync(path.join(__dirname, '../game/data/districts.json'), 'utf8'));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const dot = (a, b) => a.reduce((sum, value, index) => sum + value * b[index], 0);
const add = (a, b) => a.map((value, index) => value + b[index]);
const sub = (a, b) => a.map((value, index) => value - b[index]);
const mul = (a, scale) => a.map(value => value * scale);
const length = value => Math.hypot(...value);
const distance = (a, b) => length(sub(a, b));
const unit = value => mul(value, 1 / length(value));
const cross = (a, b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
const tangent = (value, normal) => sub(value, mul(normal, dot(value, normal)));
function frame(up) {
  let back = tangent([0, 0, 1], up);
  if (dot(back, back) < .01) back = tangent([0, 1, 0], up);
  back = unit(back);
  return {x:unit(cross(up, back)), z:back};
}
function positionAt(index, point) {
  const up = layouts.stations[index].normal, axes = frame(up);
  return mul(unit(add(mul(up, layouts.radius), add(mul(axes.x, point[0]), mul(axes.z, point[1])))), layouts.radius);
}
function localPoint(index, position) {
  const up = layouts.stations[index].normal, axes = frame(up), normal = unit(position);
  return [dot(normal, axes.x), dot(normal, axes.z)].map(value => value * layouts.radius / dot(normal, up));
}
function pondDistance(point, pond) {
  const local = sub(point, pond.center).map((value, index) => value / pond.size[index]);
  const angle = Math.atan2(local[1], local[0]);
  return (length(local) - 1 - .10*Math.sin(angle*3) - .055*Math.cos(angle*5)) * Math.min(...pond.size);
}

const report = {
  started_utc:new Date().toISOString(), site, requested_profile:profile, water_requested:!args.includes('--skip-water'),
  method:'Installed desktop Chrome, ordinary mouse/keyboard input, read-only window.planetPerformance. No state injection, review URL, direct engine call, or hidden teleport. UI destination buttons are the normal player fast-travel feature.',
  scope:'Six outdoor station arrivals, actual movement, overview toggling and drag evidence, pond-side UI visit and a real keyboard approach. Separate native tests cover every 4 m of bridge floor and 72 representative 15 m controller sections; this browser smoke does not walk every complete bridge.',
  limitations:['Desktop browser evidence is not physical-phone/Safari/thermal performance.', 'Release telemetry does not expose camera yaw or floor contacts. Overview drag uses before/after screenshots for visual review; water results report position and input rather than claiming complete collision coverage.'],
  checks:[], actions:[], samples:[], screenshots:[], requests:[], errors:[], warnings:[],
};
fs.mkdirSync(output, {recursive:true});
let server, browser, context, page;
let stage = 'startup';
const save = () => fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
const state = () => page.evaluate(() => window.planetPerformance || null);
function check(label, passed, evidence) {
  report.checks.push({stage, label, passed:Boolean(passed), ...(evidence === undefined ? {} : {evidence})});
  save();
  assert.ok(passed, `${stage}: ${label}`);
  console.log('PASS', stage, label);
}
async function until(predicate, label, timeout=180000) {
  const end = Date.now() + timeout;
  let latest;
  do {
    latest = await state();
    if (predicate(latest)) return latest;
    await pause(200);
  } while (Date.now() < end);
  throw Error(`Timed out: ${label}; last=${JSON.stringify(latest).slice(0,1600)}`);
}
async function fresh(after) {
  return until(value => value?.ticks_ms > after, 'new read-only telemetry sample', 15000);
}
async function contentBox() {
  const canvas = await page.locator('#canvas').boundingBox();
  assert.ok(canvas && canvas.width && canvas.height, 'Visible game canvas');
  const viewport = (await state())?.viewport || [1440,900];
  const scale = Math.min(canvas.width / viewport[0], canvas.height / viewport[1]);
  return {x:canvas.x+(canvas.width-viewport[0]*scale)/2, y:canvas.y+(canvas.height-viewport[1]*scale)/2,
    width:viewport[0]*scale, height:viewport[1]*scale, scale};
}
async function click(selector) {
  for (let attempt=0; attempt<24; attempt++) {
    const before = await state(), box = await contentBox();
    const found = before?.buttons?.find(value => typeof selector === 'string' ? value.name === selector : selector.test(value.text));
    if (found?.visible) {
      await page.mouse.click(box.x+found.center[0]*box.width, box.y+found.center[1]*box.height);
      await fresh(before.ticks_ms);
      report.actions.push({stage, type:'button', text:found.text, name:found.name});
      save();
      return;
    }
    if (found) {
      const rows = before.buttons.filter(value => value.visible && /^\d{2}\s/.test(value.text));
      const centreY = rows.length ? rows.reduce((sum, value) => sum+value.center[1],0)/rows.length : .73;
      const top = rows.length ? Math.min(...rows.map(value => value.center[1])) : .73;
      await page.mouse.move(box.x+Math.max(.05,Math.min(.95,found.center[0]))*box.width, box.y+centreY*box.height);
      await page.mouse.wheel(0, found.center[1]<top ? -130 : 130);
      await fresh(before.ticks_ms);
    } else await pause(250);
  }
  throw Error('World button unavailable: '+selector);
}
async function settle() {
  const ready = await until(value => value?.avatar?.ready && !value.overview && !value.preparing_roam && !value.player?.paused && !value.player?.entering && value.streaming?.pending_regions===0, 'outdoor playable and streamed', 240000);
  return fresh(ready.ticks_ms);
}
async function menu() {
  const current = await state();
  if (current.settings_open) await click('CloseGraphicsSettings');
  if (!(await state()).destinations_open) await click(/選擇目的地/);
  await until(value => value?.destinations_open, 'destination chooser opens', 15000);
}
async function closeMenu() {
  if ((await state()).destinations_open) await click(/收起目的地/);
  await until(value => !value?.destinations_open, 'destination chooser closes', 15000);
}
async function destination(index) {
  await menu();
  await click(new RegExp('^'+String(index+1).padStart(2,'0')+'\\s'));
  await settle();
  await closeMenu();
  return until(value => value?.nearest_id===layouts.stations[index].id && !value.overview, 'arrival at '+layouts.stations[index].id, 15000);
}
async function capture(name) {
  const filename = name+'.png';
  const pixels = await page.screenshot({path:path.join(output, filename)});
  const row = {stage, filename, sha256:crypto.createHash('sha256').update(pixels).digest('hex'), telemetry:await state()};
  report.screenshots.push(row);
  save();
  return row;
}
async function sample(name, seconds=3) {
  const values = [], end = Date.now()+seconds*1000;
  let ticks = -1;
  while (Date.now()<end) {
    const value = await state();
    if (value?.ticks_ms!==ticks && value?.frame_sample_valid) {values.push(value); ticks=value.ticks_ms;}
    await pause(250);
  }
  const times=values.map(value=>value.frame_ms_mean).filter(Number.isFinite);
  report.samples.push({stage, name, samples:values, delivered_fps_mean:times.length?1000/(times.reduce((a,b)=>a+b,0)/times.length):null});
  save();
}
async function keyMove(key, milliseconds, minimum=.15) {
  const before = await fresh((await state()).ticks_ms);
  await page.keyboard.down(key);
  try {await pause(milliseconds);} finally {await page.keyboard.up(key);}
  await pause(200);
  const after = await fresh((await state()).ticks_ms);
  const moved = distance(before.player.position, after.player.position);
  report.actions.push({stage, type:'held-key', key, milliseconds, from:before.player.position, to:after.player.position, metres:moved});
  check('Keyboard '+key.toUpperCase()+' changes the real player position', moved>minimum, {metres:moved});
  return after;
}
async function drag(dxWorld, dyWorld=0) {
  const box = await contentBox();
  const start = {x:box.x+box.width*.69, y:box.y+box.height*.48};
  await page.mouse.move(start.x,start.y);
  await page.mouse.down({button:'right'});
  try {await page.mouse.move(start.x+dxWorld*box.scale,start.y+dyWorld*box.scale,{steps:12});}
  finally {await page.mouse.up({button:'right'});}
  report.actions.push({stage,type:'right-mouse-drag',delta_game_pixels:[dxWorld,dyWorld]});
  await fresh((await state()).ticks_ms);
}
async function face(target) {
  for(let attempt=0;attempt<5;attempt++) {
    const current=await state(), up=unit(current.player.position);
    const desired=unit(tangent(sub(target,current.player.position),up));
    const heading=unit(tangent(current.player.heading,up));
    const angle=Math.atan2(dot(up,cross(heading,desired)),dot(heading,desired));
    if(Math.abs(angle)<.04) return;
    await drag(Math.max(-330,Math.min(330,-angle/.005)));
  }
  throw Error('Ordinary mouse drags did not face the water approach');
}
async function waterEvidence() {
  stage='pond-bank';
  await menu();
  await click(/自然景點/);
  // Godot PopupMenu initially has no keyboard-highlighted row. The first
  // ordinary Down selects its first item, as in the existing hall UI runner.
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await settle();
  await closeMenu();
  const before = await fresh((await state()).ticks_ms);
  const local = localPoint(0,before.player.position);
  check('Nature menu reaches the authored pond-side visit', distance(local,districts[0].visit)<2, {local, expected:districts[0].visit});
  await capture('08-pond-before-approach');
  await face(positionAt(0,districts[0].water[0].center));
  const samples=[];
  await page.keyboard.down('w');
  try {
    for(let i=0;i<8;i++) {await pause(1000); samples.push(await state());}
  } finally {await page.keyboard.up('w');}
  const final=await fresh((await state()).ticks_ms), last=localPoint(0,final.player.position);
  const shoreline=pondDistance(last,districts[0].water[0]);
  const travel=distance(before.player.position,final.player.position);
  const finalMotion=distance(samples.at(-3).player.position,final.player.position);
  report.water_approach={samples, final_local:last, authored_pond_distance_m:shoreline, travelled_m:travel, final_two_seconds_motion_m:finalMotion,
    reached_bank:shoreline>=-.25&&shoreline<1.3, note:'A distant obstacle can stop this natural approach before the shoreline. Position evidence is reported explicitly; native ray/capsule/controller tests independently verify water and rails.'};
  check('Eight seconds of forward input never place the character inside the unbridged pond', samples.every(value=>pondDistance(localPoint(0,value.player.position),districts[0].water[0])>=-.25), {final_pond_distance_m:shoreline,travelled_m:travel});
  check('Waterfront visit retains outdoor controls and a surface-scale radial position', !final.player.paused&&!final.player.entering&&!final.overview&&length(final.player.position)>layouts.radius, final.player);
  if(!report.water_approach.reached_bank) report.warnings.push({stage,message:'Approach stopped before the exact bank; inspect screenshots. This run does not claim a browser shoreline collision pass.'});
  await capture('09-pond-after-approach');
  await sample('pond-side-stationary',3);
}

(async()=>{try{
  assert.ok(fs.existsSync(path.join(site,'index.html')), 'Run this harness after the coordinated web export');
  server=http.createServer((req,res)=>{
    let name;
    try {name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch{res.writeHead(400).end();return;}
    if(name.endsWith('/'))name+='index.html';
    const file=path.resolve(site,'.'+name);
    if(!file.startsWith(site+path.sep)){res.writeHead(403).end();return;}
    const row={path:name,status:200,bytes:0};report.requests.push(row);
    if(!fs.existsSync(file)||!fs.statSync(file).isFile()){row.status=404;res.writeHead(404).end();return;}
    row.bytes=fs.statSync(file).size;
    const type=name.endsWith('.js')?'application/javascript':name.endsWith('.html')?'text/html':name.endsWith('.wasm')?'application/wasm':name.endsWith('.json')?'application/json':'application/octet-stream';
    res.writeHead(200,{'Content-Type':type,'Content-Length':row.bytes,'Cache-Control':'no-store'});
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  browser=await chromium.launch({channel:'chrome',headless:!args.includes('--headed')});
  report.browser=browser.version();
  context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1});
  page=await context.newPage();
  page.on('pageerror',error=>report.errors.push(String(error)));
  page.on('console',message=>{
    if(['warning','error'].includes(message.type()))report.warnings.push({stage,message:message.text()});
    if(/SCRIPT ERROR|Parse Error|SHADER ERROR|RuntimeError|INVALID_ENUM|INVALID_OPERATION|^ERROR:/.test(message.text()))report.errors.push(message.text());
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/?performance`,{waitUntil:'domcontentloaded'});
  await until(value=>Boolean(value?.buttons?.length),'initial world UI',240000);
  report.build_id=await page.locator('meta[name="little-world-build"]').getAttribute('content');
  await click('GraphicsSettingsButton');
  await click({standard:'QualityStandard',low:'QualityLow',balanced:'QualityBalanced',mobile:'QualityMobile'}[profile]||'QualityStandard');
  await click('FPS60');
  await click('CloseGraphicsSettings');
  await until(value=>value?.packs?.all_ready,'startup asset delivery',240000);
  check('Initial scene is the complete-world overview',(await state()).overview);
  const beforeOverview=await capture('00-overview-before-drag');
  await drag(-250,45);
  const afterOverview=await capture('01-overview-after-drag');
  check('Overview drag leaves the player in overview at the same real location',(await state()).overview&&distance(beforeOverview.telemetry.player.position,afterOverview.telemetry.player.position)<.1);
  report.overview_drag_review={before:beforeOverview.filename,after:afterOverview.filename,visually_review_required:true};
  for(let index=0;index<layouts.stations.length;index++) {
    stage=layouts.stations[index].id;
    const arrival=await destination(index);
    check('Normal destination button reaches its matching entrance',arrival.nearest_id===stage&&dot(unit(arrival.player.position),layouts.stations[index].normal)>.999,arrival.player);
    await capture(String(index+2).padStart(2,'0')+'-'+stage);
    // Back away from the entry before turning or strafing toward its walls.
    await keyMove('s',850);
    if(index===0) {
      await keyMove('d',550);
      await keyMove('a',550);
      await keyMove('w',650);
      const stopped=(await state()).player.position;
      await pause(1500);
      const still=await fresh((await state()).ticks_ms);
      check('Releasing all movement keys stops walking',distance(stopped,still.player.position)<.2);
      const heading=still.player.heading;
      await drag(100,0);
      check('Ordinary walking-view drag changes heading',distance(heading,(await state()).player.heading)>.1);
    } else await keyMove('w',600);
    await sample(stage+'-outdoor',2);
  }
  if(!args.includes('--skip-water'))await waterEvidence();
  stage='return-overview';
  await page.keyboard.press('Tab');
  await until(value=>value?.overview,'Tab returns to overview',15000);
  await capture('10-final-complete-world');
  check('Tab returns to complete-world overview',(await state()).overview);
  check('No browser, engine script, or shader errors',report.errors.length===0,report.errors);
  report.passed=true;
}catch(error){
  report.errors.push(String(error.stack||error));
  report.passed=false;
  process.exitCode=1;
  console.error(error);
  if(page){report.last_state=await state().catch(()=>null);await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});}
}finally{
  report.finished_utc=new Date().toISOString();save();
  if(context)await context.close();
  if(browser)await browser.close();
  if(server)await new Promise(resolve=>server.close(resolve));
}})();
