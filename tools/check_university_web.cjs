// Campus hall browser acceptance using only ordinary keyboard/mouse/touch input.
// Telemetry is read-only. Mobile Chromium emulation is not a physical-phone
// Safari, GPU, memory-pressure or thermal performance measurement.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');

const site = path.resolve(process.argv[2] || '_site');
const artSmoke=process.argv.includes('--art-smoke');
const outputIndex=process.argv.indexOf('--output');
const out = path.resolve(outputIndex>=0 ? process.argv[outputIndex+1] : 'deliverables/university-hall/'+(artSmoke?'web-r4':'web'));
const smokeDesktop=process.argv.includes('--smoke-desktop');
const resumeCycles=process.argv.includes('--resume-mobile-cycles');
const platforms = smokeDesktop || process.argv.includes('--desktop-only') ? ['desktop'] : process.argv.includes('--mobile-only') ? ['mobile'] : ['desktop', 'mobile'];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const distance = (a, b) => Math.hypot(...a.map((value, index) => value - b[index]));
const report = resumeCycles ? JSON.parse(fs.readFileSync(path.join(out,'report.json'),'utf8')) : {
  started_utc: new Date().toISOString(), site,
  scope: artSmoke ? 'R4 exhibit-kit update: desktop/mobile name and reader UI, two school exhibits, live-model inspection/zoom/close, source links, favorites, return state and reload persistence. This is a scoped smoke test, not a rerun of the prior 162-check full regression.' : 'Original university hall interaction and transition acceptance.',
  method: 'Headless installed Chrome with hardware WebGL, real keyboard/mouse and emulated touch; game state is observed, never injected.',
  mobile_scope: '844x390 landscape desktop Chromium touch emulation. These FPS samples are not physical phone or Safari performance.',
  checks: [], samples: [], requests: [], errors: [], warnings: [], scenarios: {}, actions: [],
};
fs.mkdirSync(out, {recursive:true});
let browser, server, page, context, cdp, scenario = '', failHall = false, holdHallFailure = false;
const delayedFailures=[];
function releaseHeldFailures(){holdHallFailure=false;for(const send of delayedFailures.splice(0))send();}
const save = () => fs.writeFileSync(path.join(out, smokeDesktop?'report-desktop-final-smoke.json':'report.json'), JSON.stringify(report, null, 2));
function check(label, value, evidence) {
  report.checks.push({scenario, label, passed:Boolean(value), ...(evidence === undefined ? {} : {evidence})});
  save();
  assert.ok(value, `${scenario}: ${label}`);
  console.log('PASS', scenario, label);
}
const hall = () => page.evaluate(() => window.universityHallState || null);
const training = () => page.evaluate(() => window.trainingRoomState || null);
const world = () => page.evaluate(() => window.planetPerformance || null);
async function until(read, predicate, label, timeout=180000) {
  const deadline = Date.now() + timeout;
  let value;
  do {
    value = await read();
    if (predicate(value)) return value;
    await pause(200);
  } while (Date.now() < deadline);
  throw new Error(`Timed out: ${label}; last=${JSON.stringify(value).slice(0,1800)}`);
}
async function contentBox(viewport) {
  const canvas = await page.locator('#canvas').boundingBox();
  assert.ok(canvas && canvas.width && canvas.height, 'Canvas has a visible input area');
  const [width, height] = viewport || [1440, 900];
  const scale = Math.min(canvas.width/width, canvas.height/height);
  return {x:canvas.x+(canvas.width-width*scale)/2, y:canvas.y+(canvas.height-height*scale)/2,
    width:width*scale, height:height*scale, scale};
}
async function tap(x, y) {
  if (scenario === 'mobile') {
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y,id:0}]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  }
  else await page.mouse.click(x,y);
  await pause(450);
}
async function tapLocator(selector){const box=await page.locator(selector).boundingBox();await tap(box.x+box.width/2,box.y+box.height/2);}
async function scrollAt(x, y, direction=1, amount=230) {
  if (scenario === 'mobile') {
    const start = {x, y, id:3};
    const travel=Math.min(40,amount*.22);
    await cdp.send('Input.dispatchTouchEvent', {type:'touchStart', touchPoints:[start]});
    for (let step=1; step<=5; step++) {
      await cdp.send('Input.dispatchTouchEvent', {type:'touchMove', touchPoints:[{...start,y:y-direction*step*travel/5}]});
      await pause(70);
    }
    await pause(150);
    await cdp.send('Input.dispatchTouchEvent', {type:'touchEnd',touchPoints:[]});
  } else {
    await page.mouse.move(x,y);
    await page.mouse.wheel(0,direction*amount);
  }
  await pause(450);
}
function matchButton(key, value, selector) {
  return typeof selector === 'string' ? key === selector : selector.test(value.text || '');
}
async function clickHall(selector) {
  for (let attempt=0; attempt<20; attempt++) {
    const state = await hall();
    const found = Object.entries(state?.buttons || {}).find(([key,value])=>matchButton(key,value,selector));
    const box = await contentBox(state?.viewport);
    if (found) {
      const [x,y,width,height] = found[1].rect;
      const cx = x+width/2, cy = y+height/2;
      const point = {x:box.x+cx*box.scale,y:box.y+cy*box.scale};
      const visible = found[1].visible !== false && !found[1].clipped &&
        point.x > box.x && point.x < box.x+box.width && point.y > box.y && point.y < box.y+box.height;
      if (visible && !found[1].disabled) {
        await tap(point.x,point.y);
        return found[0];
      }
      await scrollAt(box.x+box.width*.55,box.y+box.height*.72,cy<0 ? -1:1);
    } else await pause(300);
  }
  throw new Error('Hall control unavailable: '+selector);
}
async function clickWorld(selector) {
  for (let attempt=0; attempt<20; attempt++) {
    const state = await world();
    const found = state?.buttons?.find(value=>typeof selector === 'string' ? value.name === selector : selector.test(value.text));
    const box = await contentBox(state?.viewport);
    if (found?.visible) {
      await tap(box.x+found.center[0]*box.width,box.y+found.center[1]*box.height);
      const after=await until(world,s=>s?.ticks_ms>state.ticks_ms,'fresh telemetry after world click',20000);
      report.actions.push({scenario,button:found.text,before_ticks:state.ticks_ms,after_ticks:after.ticks_ms,
        before_menu:state.destinations_open,after_menu:after.destinations_open,after_settings:after.settings_open});
      await pause(200);
      return;
    }
    if (found) {
      const x = box.x+Math.max(.05,Math.min(.95,found.center[0]))*box.width;
      if (state.settings_open) {
        await scrollAt(box.x+box.width*.5,box.y+box.height*.5,found.center[1]<.5?-1:1,120);
        await pause(750);
        continue;
      }
      const visibleRows=state.buttons.filter(value=>value.visible &&
        /^\d{2}\s/.test(value.text) && Math.abs(value.center[0]-found.center[0])<.05);
      const top=visibleRows.length ? Math.min(...visibleRows.map(value=>value.center[1])) : .73;
      const scrollY=visibleRows.length ? visibleRows.reduce((sum,value)=>sum+value.center[1],0)/visibleRows.length : .73;
      if(scenario==='mobile'){
        // The rendered DestinationScroll track is at x=279, y=600..780 in
        // the observed 1440x900 UI. Tap its track to page with real touch.
        await tap(box.x+box.width*(279/1440),box.y+box.height*(found.center[1]<top?610/900:765/900));
      }else await scrollAt(x,box.y+box.height*scrollY,found.center[1]<top ? -1:1,90);
      // Performance telemetry is sampled, so do not steer from the pre-scroll row positions.
      await pause(750);
    } else await pause(400);
  }
  throw new Error('World control unavailable: '+selector);
}
async function clickTrainingReturn() {
  const state = await until(training,s=>s?.buttons?.some(button=>button.name==='ReturnToWorld'&&button.visible),'training room return control',15000);
  const button=state.buttons.find(value=>value.name==='ReturnToWorld');
  const box=await contentBox(state.viewport || (await world()).viewport);
  await tap(box.x+button.center[0]*box.width,box.y+button.center[1]*box.height);
}
async function chooseDestination(selector) {
  for (let attempt=0;attempt<3;attempt++) {
    const state=await world();
    if(state.settings_open) await clickWorld('CloseGraphicsSettings');
    if(!(await world()).destinations_open) await clickWorld(/選擇目的地/);
    const opened=await until(world,s=>s?.destinations_open||s?.settings_open,'destination menu opens',10000);
    if(opened.settings_open) continue; // First resumed layout may precede the next telemetry sample.
    const before=await world();
    await clickWorld(selector);
    await until(world,s=>s?.ticks_ms>before.ticks_ms+1000&&!s.overview&&!s.preparing_roam&&s.avatar?.ready,
      'destination transition and menu layout settle',180000);
    if((await world()).destinations_open) await clickWorld(/收起目的地/);
    await until(world,s=>!s?.destinations_open,'destination chooser closed before interacting',10000);
    return;
  }
  throw new Error('Destination menu did not settle');
}
async function setSearch(text) {
  const state = await until(hall,s=>Boolean(s?.controls?.SchoolSearch),'school search input');
  const box = await contentBox(state.viewport);
  const [x,y,w,h] = state.controls.SchoolSearch.rect;
  await tap(box.x+(x+w/2)*box.scale,box.y+(y+h/2)*box.scale);
  await page.keyboard.press(scenario==='mobile'?'Meta+A':'Control+A');
  await page.keyboard.press('Backspace');
  // Godot's canvas editor consumes key events (not DOM beforeinput). Dispatch
  // ordinary Unicode key events so both English and Chinese reach that editor.
  for (const character of text) {
    await cdp.send('Input.dispatchKeyEvent',{type:'keyDown',key:character,text:character,unmodifiedText:character});
    await cdp.send('Input.dispatchKeyEvent',{type:'keyUp',key:character});
  }
  await until(hall,s=>s?.controls?.SchoolSearch?.text===text,'typed search '+text,20000);
  await pause(400);
}
async function setRegion(index) {
  const state = await hall(), control = state.controls.RegionFilter;
  const box = await contentBox(state.viewport), [x,y,w,h] = control.rect;
  await tap(box.x+(x+w/2)*box.scale,box.y+(y+h/2)*box.scale);
  // A pointer-opened Godot popup starts with no keyboard-highlighted row.
  // The first Down highlights row zero; subsequent Down keys advance it.
  for (let count=0; count<=index; count++) await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await until(hall,s=>s?.controls?.RegionFilter?.selected===index,'region filter selection',10000);
}
async function openDirectory(mode='all') {
  if (scenario === 'desktop') await page.keyboard.press(mode==='favorites'?'j':'m');
  else await clickHall(mode==='favorites'?'OpenJournal':'OpenMap');
  await until(hall,s=>s?.panel==='directory','directory opens',15000);
}
async function closeReader() {
  if (scenario === 'desktop') await page.keyboard.press('Escape');
  else await clickHall('ClosePanel');
  await until(hall,s=>s?.panel==='','reader closes',15000);
}
async function screenshot(name) {
  const filename = `${scenario}-${name}.png`;
  await page.screenshot({path:path.join(out,filename)});
  report.scenarios[scenario].screenshots.push(filename);
  save();
}
async function sample(name,seconds=6) {
  const values=[];
  const deadline=Date.now()+seconds*1000;
  while (Date.now()<deadline) {values.push(await hall());await pause(500);}
  const fps=values.map(value=>value.fps).filter(Number.isFinite);
  report.samples.push({scenario,name,seconds,engine_fps_mean:fps.reduce((a,b)=>a+b,0)/fps.length,
    engine_fps_min:Math.min(...fps),engine_fps_max:Math.max(...fps),target_30fps_met:fps.every(v=>v>=27),
    samples:values.map(value=>({fps:value.fps,nodes:value.nodes,resources:value.resources,graphics:value.graphics,
      ready_ms:value.ready_ms,max_load_operation_ms:value.max_load_operation_ms}))});
  save();
}
async function moveTest() {
  const before=(await hall()).player;
  if (scenario==='desktop') {
    for (const [key,milliseconds] of [['w',750],['d',350],['s',750],['a',350]]) {
      const start=(await hall()).player;
      await page.keyboard.down(key);await pause(milliseconds);await page.keyboard.up(key);await pause(400);
      check('WASD moves the hall player: '+key,distance((await hall()).player,start)>.25);
    }
  } else {
    const stick=await page.locator('.lw-stick').boundingBox();
    const point={x:stick.x+stick.width/2,y:stick.y+stick.height/2,id:1};
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{...point,y:point.y-40}]});
    await pause(1100);
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await pause(450);
    check('Real touch joystick walks inside the hall',distance((await hall()).player,before)>.5);
  }
  const released=(await hall()).player;await pause(700);
  check('Released input stops hall movement',distance((await hall()).player,released)<.12);
}
async function enterHall() {
  await until(world,s=>Boolean(s?.buttons?.length && s.packs?.all_ready),'world overview',240000);
  const hallRequests=report.requests.filter(row=>row.scenario===scenario&&row.path.includes('university_hall-'));
  if (!report.scenarios[scenario].entered) check('Outdoor startup requests no university hall pack',hallRequests.length===0);
  await chooseDestination(/大學館/);
  await until(world,s=>s?.avatar?.ready&&!s.overview&&!s.preparing_roam&&s.nearest_id==='universities'&&!s.player?.entering,'university outdoor destination',240000);
  await pause(800);
  const before=await world();
  report.scenarios[scenario].return_expected={position:before.player.position,heading:before.player.heading,
    world_instance:before.world_instance,music_instance:before.music_instance};
  const previous=(await hall())?.instance;
  if (scenario==='mobile') await tapLocator('[data-action="interact"]');
  else await page.keyboard.press('e');
  await until(hall,s=>s&&s.instance!==previous,'independent university room',120000);
  report.scenarios[scenario].entered=true;
}
function resourceSnapshot(state,kind) {
  return {kind,ticks_ms:state.ticks_ms,nodes:state.nodes,resources:state.resources,
    room_instance:state.instance ?? state.room_instance_id ?? null,
    world_instance:state.world_instance ?? null,music_instance:state.music_instance ?? null,
    ready_ms:state.ready_ms ?? state.detail_ready_ms ?? null,
    ready_ms_scope:kind==='university_hall'?'Room creation to all hall models/avatar playable':kind==='training_room'?'Room creation to full training details ready':null,
    detail_state:state.detail_state ?? null,detail_ready_ms:state.detail_ready_ms ?? null,
    max_load_operation_ms:state.max_load_operation_ms ?? state.detail_max_operation_ms ?? null,
    fps:state.fps,graphics:state.graphics,streaming:state.streaming ?? null,
    packs:state.packs?{ready_packs:state.packs.ready_packs,mounted_bytes:state.packs.mounted_bytes,all_pack_bytes:state.packs.all_pack_bytes}:null,
    player:state.player};
}
function graphicsPolicy(state) {
  const graphics=state.graphics || {};
  return {quality_profile:graphics.quality_profile,frame_limit:graphics.frame_limit,msaa_enabled:graphics.msaa_enabled};
}
async function settleReturnedWorld(station) {
  const result=await until(world,s=>s&&!s.overview&&!s.preparing_roam&&!s.player.paused&&!s.player.entering&&(!station||s.nearest_id===station),
    'outdoor control restored after room exit',60000);
  // Permit normal district streaming and end-of-frame freeing to settle before
  // comparing counts; no global cache clearing or scene-state mutation is used.
  await until(world,s=>s?.ticks_ms>result.ticks_ms&&s.streaming?.pending_regions===0,'outdoor resource settling',90000);
  await pause(2000);
  return world();
}
async function repeatIndoorCycles(resume=false) {
  let baseline,records;
  if(resume){baseline=report.scenarios[scenario].repeat_baseline;records=report.scenarios[scenario].repeated_entries;}
  else{
    await closeReader();await clickHall('ReturnWorld');
    baseline=await settleReturnedWorld('universities');
    records=report.scenarios[scenario].repeated_entries=[];
    report.scenarios[scenario].repeat_baseline=resourceSnapshot(baseline,'world');save();
  }
  // Three complete rounds in one running world, alternating room types. The
  // first training pack may grow intentional page-lifetime caches; report that
  // separately from the warmed second-to-third-round resource-count changes.
  for(let round=1;round<=3;round++) {
    for(const station of ['universities','wordking']) {
      if(records.some(row=>row.round===round&&row.station===station&&row.world_after))continue;
      const university=station==='universities';
      const read=university?hall:training;
      await chooseDestination(university?/大學館/:/練功區/);
      await until(world,s=>s?.avatar?.ready&&!s.overview&&!s.preparing_roam&&!s.player?.paused&&!s.player?.entering&&s.nearest_id===station,
        'repeat destination '+station,180000);
      await pause(1200);
      const before=await world();
      const prior=await read();
      const priorId=prior?.instance ?? prior?.room_instance_id;
      const entryAt=Date.now();
      if(scenario==='mobile')await tapLocator('[data-action="interact"]');else await page.keyboard.press('e');
      const playable=await until(read,s=>s?.ready&&(s.instance??s.room_instance_id)!==priorId,'repeat playable '+station,240000);
      const observedPlayableMs=Date.now()-entryAt;
      await until(read,s=>s?.ready&&s.detail_state==='ready','repeat full details '+station,240000);
      await pause(2000);
      const room=await read();
      const row={round,station,world_before:resourceSnapshot(before,'world'),
        observed_input_to_playable_ms:observedPlayableMs,first_playable:resourceSnapshot(playable,university?'university_hall':'training_room'),
        room:resourceSnapshot(room,university?'university_hall':'training_room')};
      records.push(row);save();
      check(`Round ${round} ${station}: full indoor content is ready`,room.detail_state==='ready'&&Number.isFinite(row.room.ready_ms));
      check(`Round ${round} ${station}: node and resource counters are available`,Number.isFinite(room.nodes)&&Number.isFinite(room.resources));
      check(`Round ${round} ${station}: graphics policy is preserved indoors`,JSON.stringify(graphicsPolicy(room))===JSON.stringify(graphicsPolicy(before)));
      if(round===1)await screenshot(university?'university-repeat-ready':'training-repeat-ready');
      if(university)await clickHall('ReturnWorld');else await clickTrainingReturn();
      const restored=await settleReturnedWorld(station);
      row.world_after=resourceSnapshot(restored,'world');
      row.return_node_delta=restored.nodes-before.nodes;
      row.return_resource_delta=restored.resources-before.resources;save();
      check(`Round ${round} ${station}: same world survives`,restored.world_instance===baseline.world_instance&&restored.world_instance===before.world_instance);
      check(`Round ${round} ${station}: same music controller survives`,restored.music_instance===baseline.music_instance&&restored.music_instance===before.music_instance);
      check(`Round ${round} ${station}: position and heading return`,distance(restored.player.position,before.player.position)<.35&&distance(restored.player.heading,before.player.heading)<.05);
      check(`Round ${round} ${station}: graphics policy is preserved on return`,JSON.stringify(graphicsPolicy(restored))===JSON.stringify(graphicsPolicy(before)));
    }
  }
  const trends={};
  for(const station of ['universities','wordking']) {
    const series=records.filter(row=>row.station===station);
    trends[station]={rounds:series.length,
      indoor_nodes:series.map(row=>row.room.nodes),indoor_resources:series.map(row=>row.room.resources),
      ready_ms:series.map(row=>row.room.ready_ms),outdoor_nodes:series.map(row=>row.world_after.nodes),outdoor_resources:series.map(row=>row.world_after.resources),
      warmed_last_round_node_change:series[2].world_after.nodes-series[1].world_after.nodes,
      warmed_last_round_resource_change:series[2].world_after.resources-series[1].world_after.resources};
  }
  report.scenarios[scenario].repeat_resource_trends=trends;
  report.scenarios[scenario].repeat_resource_scope='Godot node/resource object counts; page-lifetime mounted pack/cache growth is retained. These are not browser-process RAM bytes. Warmed round 2→3 deltas are reported without inventing a zero-growth pass threshold.';
  check('Three complete university and training round trips recorded',records.length===6&&Object.values(trends).every(value=>value.rounds===3));
  report.scenarios[scenario].final_world=resourceSnapshot(await world(),'world');save();
}

async function reopenNtuReader(mobile) {
  if(mobile)await tapLocator('[data-action="interact"]');else await page.keyboard.press('e');
  await until(hall,s=>s?.panel==='school'&&s.school==='001','NTU reader reopens from the exhibit',15000);
  await clickHall('Section_0');
}

async function inspectModelSmoke(mobile) {
  await clickHall('InspectSchool');
  const initial=await until(hall,s=>s?.panel==='model'&&s.inspection_id==='001','live NTU model inspection opens',15000);
  check('Model inspection disables player movement',initial.player_controls_enabled===false);
  check('Model inspection hides the avatar',initial.player_visible===false);
  check('All model inspection buttons are visible and enabled',
    ['InspectZoomIn','InspectZoomOut','InspectReset','InspectClose'].every(key=>initial.buttons[key]?.visible&&!initial.buttons[key].disabled));
  if(mobile)check('Mobile joystick stays hidden in model inspection',!await page.locator('#little-world-touch').isVisible());
  await page.keyboard.down('w');await pause(750);await page.keyboard.up('w');await pause(350);
  check('Movement input leaves the inspected exhibit position unchanged',distance((await hall()).player,initial.player)<.1);
  await clickHall('InspectZoomIn');
  const zoomed=await until(hall,s=>s?.inspection_distance<initial.inspection_distance-.1,'inspection zooms in',10000);
  check('Zoom-in button brings the actual model camera closer',true,{before:initial.inspection_distance,after:zoomed.inspection_distance});
  await screenshot('001-model-close');
  await clickHall('InspectZoomOut');
  await until(hall,s=>s?.inspection_distance>zoomed.inspection_distance+.1,'inspection zooms out',10000);
  check('Zoom-out button increases model camera distance',true);
  const beforeDrag=await hall(),box=await contentBox(beforeDrag.viewport);
  const start={x:box.x+box.width*.50,y:box.y+box.height*.43};
  if(mobile){
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{...start,id:7}]});
    for(let i=1;i<=8;i++){
      await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:start.x+70*i/8,y:start.y+15*i/8,id:7}]});
      await pause(50);
    }
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  }else{
    await page.mouse.move(start.x,start.y);await page.mouse.down();
    await page.mouse.move(start.x+100,start.y+20,{steps:10});await page.mouse.up();
  }
  await pause(800);
  const dragged=await hall();
  report.scenarios[scenario].inspection={initial,zoomed,dragged};save();
  check(mobile?'Touch drag rotates the model camera':'Mouse drag rotates the model camera',
    Number.isFinite(beforeDrag.inspection_angle)&&Number.isFinite(dragged.inspection_angle)&&
    Math.abs(dragged.inspection_angle-beforeDrag.inspection_angle)>.02);
  await screenshot('001-model-rotated');
  await clickHall('InspectReset');
  await until(hall,s=>Math.abs(s?.inspection_distance-initial.inspection_distance)<.01&&
    Math.abs(s.inspection_angle-initial.inspection_angle)<.01&&Math.abs(s.inspection_pitch-initial.inspection_pitch)<.01,'model camera reset',10000);
  check('Reset restores the initial model zoom and angle',true);
  await clickHall('InspectClose');
  const closed=await until(hall,s=>s?.panel===''&&s.inspection_id===''&&s.player_controls_enabled,'model close restores gallery',15000);
  check('Return-to-gallery button restores normal controls',distance(closed.player,initial.player)<.1);
  check('Closing model inspection restores the avatar',closed.player_visible===true);
  if(mobile)check('Mobile joystick returns after closing model inspection',await page.locator('#little-world-touch').isVisible());
  if(!mobile){
    await reopenNtuReader(false);await clickHall('InspectSchool');
    await until(hall,s=>s?.panel==='model'&&s.inspection_id==='001','second desktop inspection opens',15000);
    await page.keyboard.press('Escape');
    await until(hall,s=>s?.panel===''&&s.inspection_id===''&&s.player_controls_enabled,'Escape closes model inspection',15000);
    check('Escape closes desktop inspection and restores gallery controls',true);
    await reopenNtuReader(false);await clickHall('InspectSchool');
    await until(hall,s=>s?.panel==='model'&&s.inspection_id==='001','inspection opens before directory shortcut',15000);
    await page.keyboard.press('m');
    const directory=await until(hall,s=>s?.panel==='directory'&&s.inspection_id==='','map shortcut leaves inspection for directory',15000);
    check('Map shortcut closes inspection without stacking reader layers',directory.player_visible&&!directory.player_controls_enabled&&!directory.buttons.InspectClose);
    await closeReader();
  }
  await reopenNtuReader(mobile);
}

async function runArtSmoke(mobile) {
  const entryData=JSON.parse(fs.readFileSync(path.resolve('game/data/universities.json'),'utf8'));
  const ntu=entryData.entries.find(entry=>entry.id==='001');
  await until(hall,s=>s?.ready,'new exhibit kit is playable',180000);
  let state=await hall();
  const expected=report.scenarios[scenario].return_expected;
  report.scenarios[scenario].build_id=await page.locator('meta[name="little-world-build"]').getAttribute('content');
  report.scenarios[scenario].gpu=await page.evaluate(()=>{
    const gl=document.getElementById('canvas').getContext('webgl2');
    const ext=gl.getExtension('WEBGL_debug_renderer_info');
    return ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER);
  });
  check('Hardware WebGL renderer is active',!/SwiftShader|llvmpipe|softpipe/i.test(report.scenarios[scenario].gpu),report.scenarios[scenario].gpu);
  check('New hall contains all 138 entries and loads without error',state.entries===138&&state.detail_state==='ready'&&!state.detail_error);
  check('Hall HUD uses the formal atrium name',state.buttons.ReturnAtrium.text==='中庭');
  check(mobile?'Compact touch HUD is enabled':'Desktop keyboard hints remain available',
    mobile?state.buttons.OpenMap.text==='導覽':state.buttons.OpenMap.text.includes('M'));
  check('Low quality and 30 FPS persist in new hall',state.graphics.quality_profile==='low'&&state.graphics.frame_limit===30);
  await pause(1000);await screenshot('atrium');
  await openDirectory();await setSearch('NTU');
  check('NTU alias finds its exhibit',Boolean((await hall()).buttons.Travel_001));
  await clickHall('Travel_001');
  await until(hall,s=>s?.panel===''&&s.region==='north'&&s.nearest.startsWith('001_'),'NTU new exhibit arrival',20000);
  await screenshot('001-exhibit');await sample('001-exhibit',4);
  if(mobile)await tapLocator('[data-action="interact"]');else await page.keyboard.press('e');
  await until(hall,s=>s?.panel==='school'&&s.school==='001','NTU physical exhibit interaction',15000);
  check('Opening exhibit records exploration',(await hall()).visited.includes('001'));
  check('Reader keeps its close control visible',(await hall()).buttons.ClosePanel?.visible===true);
  if(mobile)check('Touch movement overlay hides during reading',!await page.locator('#little-world-touch').isVisible());
  await clickHall('Section_0');await screenshot('overview');
  await inspectModelSmoke(mobile);
  await clickHall('Section_2');
  await until(hall,s=>s?.selected_section===2,'nearby scenery page opens',10000);
  check('Nearby scenery page remains accessible',true);
  await screenshot('nearby');
  await clickHall('Section_4');
  await until(hall,s=>s?.selected_section===4,'student experience page opens',10000);
  const studentSources=ntu.sources.filter(source=>/^https:\/\/www\.(dcard\.tw|ptt\.cc)\//.test(source.url));
  const studentButtons=Object.values((await hall()).buttons).map(button=>button.text);
  check('Student experience page offers original discussion sources',studentSources.length>0&&studentSources.every(source=>studentButtons.includes(source.title+'  ↗')),studentSources);
  await screenshot('student-experience');
  await clickHall('Section_6');
  await until(hall,s=>s?.selected_section===6,'sources page opens',10000);
  const sourceButtons=Object.values((await hall()).buttons).map(button=>button.text);
  const officialSources=ntu.research_update.sources;
  check('Sources page includes current official supplements',officialSources.length>0&&officialSources.every(source=>sourceButtons.includes(source.title+'  ↗')),officialSources);
  check('Sources page retains original document links',ntu.sources.every(source=>sourceButtons.includes(source.title+'  ↗')));
  await screenshot('sources');
  if(!(await hall()).favorites.includes('001'))await clickHall('CollectSchool');
  await until(hall,s=>s?.favorites.includes('001'),'favorite saved from new reader',10000);
  check('New reader can collect a school',true);
  await closeReader();
  check(mobile?'Touch close button restores hall controls':'Escape restores hall controls',(await hall()).player_controls_enabled);
  if(mobile)check('Touch movement overlay returns after close',await page.locator('#little-world-touch').isVisible());
  await openDirectory('favorites');
  check('Journal lists the collected school',Boolean((await hall()).buttons.Travel_001));
  await closeReader();await openDirectory();await setSearch('中興');await clickHall('Travel_003');
  await until(hall,s=>s?.region==='central'&&s.nearest.startsWith('003_'),'Chung Hsing new exhibit arrival',20000);
  check('A second distinct school exhibit is reachable by Chinese search',true);
  await screenshot('003-exhibit');await sample('003-exhibit',4);
  report.scenarios[scenario].final_hall=await hall();
  await clickHall('ReturnWorld');
  const restored=await settleReturnedWorld('universities');
  check('Return preserves the same world instance',restored.world_instance===expected.world_instance);
  check('Return restores the outdoor position and heading',distance(restored.player.position,expected.position)<.35&&distance(restored.player.heading,expected.heading)<.05);
  check('Return preserves music and graphics policy',restored.music_instance===expected.music_instance&&restored.graphics.quality_profile==='low'&&restored.graphics.frame_limit===30);
  await page.reload({waitUntil:'domcontentloaded'});
  await until(world,s=>s?.ticks_ms>7000&&s?.buttons?.length,'reload layout settles',180000);
  await enterHall();await until(hall,s=>s?.ready,'new hall reopens after reload',180000);
  state=await hall();
  check('Exploration and favorite persist across browser reload',state.visited.includes('001')&&state.favorites.includes('001'));
  await openDirectory('favorites');
  check('Persisted journal can return to the school',Boolean((await hall()).buttons.Travel_001));
  await screenshot('persisted-journal');await closeReader();await clickHall('ReturnWorld');
  report.scenarios[scenario].final_world=resourceSnapshot(await settleReturnedWorld('universities'),'world');
  report.scenarios[scenario].passed=true;save();
  await context.close();context=null;page=null;
}

async function runScenario(name) {
  scenario=name;failHall=!smokeDesktop&&!artSmoke;holdHallFailure=name==='desktop'&&!smokeDesktop&&!artSmoke;
  report.scenarios[name]={screenshots:[],entered:false};save();
  const mobile=name==='mobile';
  context=await browser.newContext({viewport:mobile?{width:844,height:390}:{width:1280,height:800},deviceScaleFactor:1,
    ...(mobile?{isMobile:true,hasTouch:true,userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'}:{})});
  page=await context.newPage();cdp=await context.newCDPSession(page);
  page.on('pageerror',error=>report.errors.push({scenario,message:String(error)}));
  page.on('console',message=>{
    if (['warning','error'].includes(message.type())) report.warnings.push({scenario,type:message.type(),message:message.text()});
    if (/SCRIPT ERROR|Parse Error|SHADER ERROR|RuntimeError|INVALID_ENUM|INVALID_OPERATION|^ERROR:/.test(message.text()))
      report.errors.push({scenario,message:message.text()});
  });
  const url=`http://127.0.0.1:${server.address().port}/${mobile?'mobile/index.html':''}?performance`;
  report.scenarios[name].requested_url=url;
  await page.goto(url,{waitUntil:'domcontentloaded'});
  await until(world,s=>Boolean(s?.buttons?.length),'initial world UI',180000);
  await clickWorld('GraphicsSettingsButton');
  await clickWorld('QualityLow');
  await clickWorld('FPS30');
  await clickWorld('CloseGraphicsSettings');
  await until(world,s=>s?.graphics?.quality_profile==='low'&&s.graphics.frame_limit===30,'low profile at 30 FPS',15000);
  check('Low quality and 30 FPS selected using ordinary UI',true);
  await enterHall();
  report.scenarios[name].resolved_url=page.url();
  report.scenarios[name].texture_route=page.url().includes('/mobile/')?'mobile_ETC2':'desktop_texture_fallback_or_native_desktop';
  if(artSmoke){await runArtSmoke(mobile);return;}
  if(smokeDesktop){
    await until(hall,s=>s?.ready,'final-build desktop hall ready',180000);
    const state=await hall(),expected=report.scenarios[name].return_expected;
    report.scenarios[name].build_id=await page.locator('meta[name="little-world-build"]').getAttribute('content');
    report.scenarios[name].final_hall=state;
    check('Final build desktop hall retains 138 entries and desktop HUD',state.entries===138&&state.buttons.OpenMap.text.includes('M'));
    check('Final build desktop retains low quality and 30 FPS',state.graphics.quality_profile==='low'&&state.graphics.frame_limit===30);
    await screenshot('final-build-atrium');await clickHall('ReturnWorld');
    const restored=await settleReturnedWorld('universities');
    check('Final build desktop returns to same world and position',restored.world_instance===expected.world_instance&&distance(restored.player.position,expected.position)<.35);
    check('Final build desktop preserves music and low graphics policy',restored.music_instance===expected.music_instance&&restored.graphics.quality_profile==='low');
    report.scenarios[name].passed=true;save();await context.close();context=null;page=null;return;
  }
  if(name==='desktop'){
    check('Late model download keeps a usable loading room',(await hall()).detail_state==='waiting'&&!(await hall()).ready);
    await screenshot('loading-return');
    await clickHall('ReturnWorld');
    const expected=report.scenarios[name].return_expected;
    const restored=await until(world,s=>!s?.player?.paused&&!s?.player?.entering&&!s?.overview,'return while hall pack remains pending',30000);
    check('Returning during a pending download preserves the world',restored.world_instance===expected.world_instance&&distance(restored.player.position,expected.position)<.35);
    releaseHeldFailures();
    await enterHall();
  }
  await until(hall,s=>s?.detail_state==='error'&&s.buttons.RetryHall?.visible,'controlled pack outage reaches retry UI',120000);
  check('Controlled first hall download fails safely with retry UI',Object.values((await hall()).buttons).some(b=>/重試載入/.test(b.text)));
  await screenshot('download-retry');
  failHall=false;
  await clickHall('RetryHall');
  await until(hall,s=>s?.ready,'retry restores playable hall',180000);
  check('The complete 138-entry hall is playable after retry',(await hall()).entries===138);
  check('Hall pack was requested only after entering',report.requests.some(row=>row.scenario===name&&row.path.includes('university_hall-')&&row.status===503));
  report.scenarios[name].build_id=await page.locator('meta[name="little-world-build"]').getAttribute('content');
  report.scenarios[name].gpu=await page.evaluate(()=>{
    const gl=document.getElementById('canvas').getContext('webgl2');
    const ext=gl.getExtension('WEBGL_debug_renderer_info');
    return ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER);
  });
  check('Hardware WebGL renderer is active',!/SwiftShader|llvmpipe|softpipe/i.test(report.scenarios[name].gpu),report.scenarios[name].gpu);
  await pause(1500);await screenshot('atrium');await sample('atrium');await moveTest();
  await openDirectory();await setSearch('NTU');
  check('English alias NTU finds the Taiwan University entry',Boolean((await hall()).buttons.Travel_001));
  await setRegion(4);
  check('Region filter limits search results',!(await hall()).buttons.Travel_001);
  await setRegion(0);
  await setSearch('中興');
  check('Chinese alias finds Chung Hsing University',Boolean((await hall()).buttons.Travel_003));
  await setSearch('不存在的大學xyz');
  check('Unknown search returns an empty result list',Object.keys((await hall()).buttons).every(key=>!key.startsWith('Travel_')));
  await screenshot('empty-search');
  await setSearch('NTU');await clickHall('Travel_001');
  await until(hall,s=>s?.panel===''&&s.region==='north'&&s.nearest.startsWith('001_'),'NTU exhibit arrival',20000);
  await screenshot('ntu-gallery');await sample('ntu-gallery');
  if (mobile) await tapLocator('[data-action="interact"]');else await page.keyboard.press('e');
  await until(hall,s=>s?.panel==='school'&&s.school==='001','physical exhibit interaction opens its article',15000);
  await clickHall('Section_0');await screenshot(mobile?'compact-reader':'reading-overview');
  check('Reader close control remains within the visible viewport',(await hall()).buttons.ClosePanel?.visible===true);
  if(mobile) check('Mobile movement overlay hides while reading',!await page.locator('#little-world-touch').isVisible());
  check('Opening the NTU exhibit records exploration',(await hall()).visited.includes('001'));
  const frozen=(await hall()).player;
  await page.keyboard.down('w');await pause(800);await page.keyboard.up('w');
  check('Reading suspends movement',distance((await hall()).player,frozen)<.1);
  for (let index=1;index<=6;index++) {
    await clickHall('Section_'+index);
    await until(hall,s=>s?.selected_section===index,'reader section '+index,10000);
    check('Reader switches to section '+index,true);
  }
  await screenshot('reading-sources');
  if (!(await hall()).favorites.includes('001')) await clickHall('CollectSchool');
  await until(hall,s=>s?.favorites.includes('001'),'favorite recorded',10000);
  check('CollectSchool adds the school to the local journal',true);
  await closeReader();
  if(mobile) check('Mobile movement overlay returns after closing',await page.locator('#little-world-touch').isVisible());
  const closed=(await hall()).player;
  if(mobile){
    const stick=await page.locator('.lw-stick').boundingBox();
    const point={x:stick.x+stick.width/2,y:stick.y+stick.height/2,id:2};
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{...point,y:point.y+35}]});
    await pause(750);await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  }else{await page.keyboard.down('s');await pause(600);await page.keyboard.up('s');}
  await pause(450);
  check('Closing reader restores movement',distance((await hall()).player,closed)>.3);
  await openDirectory('favorites');
  check('Journal lists the collected school',Boolean((await hall()).buttons.Travel_001));
  await closeReader();await openDirectory();await setSearch('中興');await clickHall('Travel_003');
  await until(hall,s=>s?.region==='central'&&s.nearest.startsWith('003_'),'NCHU exhibit arrival',20000);
  await screenshot('nchu-gallery');
  await clickHall('ReturnWorld');
  const expected=report.scenarios[name].return_expected;
  const restored=await until(world,s=>!s?.player?.paused&&!s?.player?.entering&&!s?.overview&&s?.nearest_id==='universities','world restored',30000);
  check('Return restores the outdoor position',distance(restored.player.position,expected.position)<.35);
  check('Return restores the outdoor heading',distance(restored.player.heading,expected.heading)<.05);
  check('Return preserves the original world instance',restored.world_instance===expected.world_instance&&Number.isFinite(expected.world_instance));
  check('Return preserves the original music controller',restored.music_instance===expected.music_instance&&Number.isFinite(expected.music_instance));
  await pause(1800);await page.reload({waitUntil:'domcontentloaded'});
  await until(world,s=>s?.ticks_ms>7000&&s?.buttons?.length,'reloaded world layout settles',180000);
  await enterHall();
  await until(hall,s=>s?.ready,'hall reopens after browser reload',180000);
  check('Exploration survives same-browser reload',(await hall()).visited.includes('001'));
  check('Favorites survive same-browser reload',(await hall()).favorites.includes('001'));
  await openDirectory('favorites');check('Persisted journal can revisit NTU',Boolean((await hall()).buttons.Travel_001));
  await screenshot('persisted-journal');
  report.scenarios[name].final_hall=await hall();
  await repeatIndoorCycles();
  report.scenarios[name].passed=true;save();
  await context.close();context=null;page=null;
}

(async()=>{try{
  if(resumeCycles){
    browser=await chromium.connectOverCDP('http://127.0.0.1:9494');context=browser.contexts()[0];page=context.pages()[0];cdp=await context.newCDPSession(page);scenario='mobile';
    page.on('pageerror',error=>report.errors.push({scenario,message:String(error)}));
    page.on('console',message=>{if(/SCRIPT ERROR|Parse Error|SHADER ERROR|RuntimeError|INVALID_ENUM|INVALID_OPERATION|^ERROR:/.test(message.text()))report.errors.push({scenario,message:message.text()});});
    const interruptions=report.errors.filter(error=>error.message.includes('World control unavailable:'));
    report.runner_interruptions=[...(report.runner_interruptions||[]),...interruptions];
    report.errors=report.errors.filter(error=>!interruptions.includes(error));
    report.scenarios.mobile.continuation='Continued in the same live browser page after repairing the runner destination scrolling; completed rows retained, no game state injected or reset.';
    await repeatIndoorCycles(true);
    check('Continued browser and engine script errors absent',report.errors.length===0);
    report.scenarios.mobile.passed=true;report.passed=true;save();return;
  }
  assert.ok(fs.existsSync(path.join(site,'index.html')),'Exported site must exist; run after the coordinated local-only export');
  for(const name of platforms){
    const manifest=JSON.parse(fs.readFileSync(path.join(site,name==='mobile'?'mobile/index.packs.json':'index.packs.json'),'utf8'));
    assert.equal(manifest.resources['res://assets/university_hall/atrium.glb'],'university_hall','Export must include the new hall pack');
    assert.equal(manifest.packs.university_hall.startup,false,'Hall pack is on-demand in the delivered manifest');
    if(artSmoke){
      for(const model of ['atrium','gallery','exhibit_kit','feature_book'])
        assert.equal(manifest.resources[`res://assets/university_hall/${model}.glb`],'university_hall',model+' belongs to the deferred hall pack');
      assert.ok(!Object.keys(manifest.resources).some(resource=>/university_hall\/(booth|theme_[^/]+|feature_(palm|dairy|tea))\.glb$/.test(resource)),'Unused legacy university models are omitted');
    }
  }
  server=http.createServer((req,res)=>{
    let name;
    try {name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch {res.writeHead(400).end();return;}
    if(name.endsWith('/'))name+='index.html';
    const file=path.resolve(site,'.'+name);
    if(!file.startsWith(site+path.sep)){res.writeHead(403).end();return;}
    const row={scenario,path:name,at:Date.now(),status:200,bytes:0};report.requests.push(row);
    if(failHall&&name.includes('university_hall-')){
      row.status=503;
      const send=()=>{row.responded_at=Date.now();if(!res.destroyed)res.writeHead(503,{'Cache-Control':'no-store'}).end('Intentional university hall test outage');};
      if(holdHallFailure)delayedFailures.push(send);else send();
      return;
    }
    if(!fs.existsSync(file)||!fs.statSync(file).isFile()){row.status=404;res.writeHead(404).end();return;}
    row.bytes=fs.statSync(file).size;
    const type=name.endsWith('.js')?'application/javascript':name.endsWith('.html')?'text/html':name.endsWith('.wasm')?'application/wasm':name.endsWith('.json')?'application/json':'application/octet-stream';
    res.writeHead(200,{'Content-Type':type,'Content-Length':row.bytes,'Cache-Control':'no-store'});
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  browser=await chromium.launch({channel:'chrome',headless:true,
    ...(process.argv.includes('--debug-hold')?{args:['--remote-debugging-port=9494']}:{})});
  report.browser=browser.version();
  for(const name of platforms) await runScenario(name);
  check('Browser and engine script errors absent',report.errors.length===0);
  report.passed=true;
}catch(error){
  report.errors.push({scenario,message:String(error.stack||error)});console.error(error);process.exitCode=1;
  if(page){report.last_hall=await hall().catch(()=>null);report.last_training=await training().catch(()=>null);report.last_world=await world().catch(()=>null);await page.screenshot({path:path.join(out,scenario+'-failure.png')}).catch(()=>{});}
  if(process.argv.includes('--debug-hold')){
    save();console.log('DEBUG_HOLD: browser CDP at http://127.0.0.1:9494; send a newline to finish after inspection.');
    await new Promise(resolve=>{process.stdin.resume();process.stdin.once('data',resolve);});
  }
}finally{releaseHeldFailures();save();if(context)await context.close();if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));}})();
