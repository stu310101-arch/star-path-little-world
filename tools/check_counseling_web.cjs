// Shipped Godot Web acceptance: real login UI and mouse/keyboard/touch input.
// Telemetry is read-only geometry/status; no bridge commands or engine injection.
// Requires a fresh Web export and the local account emulator server on 4317.
const {chromium, devices} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name)+1] : fallback;
const site = path.resolve(args[0] && !args[0].startsWith('--') ? args[0] : '_site');
const roomSmoke = args.includes('--room-smoke');
const skipRetry = args.includes('--skip-retry') || roomSmoke;
const output = path.resolve(option('--output', roomSmoke?'deliverables/counseling-room/r6/web':'deliverables/counseling-room/web'));
const host = new URL(option('--account-host', 'http://127.0.0.1:4317'));
assert.ok(['127.0.0.1','localhost'].includes(host.hostname));
const catalog = JSON.parse(fs.readFileSync(path.join(root,'game/data/interest_catalog.json'),'utf8'));
const roomLayout = JSON.parse(fs.readFileSync(path.join(root,'game/assets/counseling_room/layout.json'),'utf8'));
const session = JSON.parse(fs.readFileSync(path.join(root,'build/counseling-qa-session.json'),'utf8'));
const password = 'Only-Local-Interest-QA-2026!';
const pause = ms => new Promise(resolve => setTimeout(resolve,ms));
const report = {started:new Date().toISOString(), method:'Actual exported Godot canvas, normal login, mouse/keyboard/touch input, read-only opt-in geometry and status telemetry. No engine calls, account bridge commands, game-state assignment or direct cloud writes.', limitations:['Chrome mobile emulation is not physical-phone, Safari, thermal or native virtual-keyboard evidence.','Cross-target cloud record contents, conflict semantics and account isolation are covered by the separate account acceptance reports. This run exercises visible gameplay and form controls.'],checks:[],screenshots:[],errors:[],warnings:[]};
report.preflight=args.includes('--preflight');
report.mode=roomSmoke?'room-smoke':'full-form-and-room';
if(roomSmoke)report.limitations.push('Room-only smoke: the 39-score input/save workflow is retained from the r4 full acceptance, gated by exact source fingerprints. Mobile emulation uses touch for public buttons and keyboard for room walking.');
if(roomSmoke)report.route_policy='Direct entrance-to-device, device-to-device and return corridors. Keyboard digital directions approximate the straight segment; no intermediate waypoint, collision-driven detour or teleport is used. Exact fixed-direction CharacterBody physics is covered by direct-routes.json.';
if(report.preflight)report.limitations.push('Preflight against an earlier export. This is not final acceptance of the revised greenhouse or grade labels.');
fs.mkdirSync(output,{recursive:true});
let server, browser, context, page, base, stage='startup', touch=false;
let releaseRoomDownload=false;
let contextRoomRequestStart=0;
report.room_pack_requests=[];
report.direct_routes=[];
report.room_layout_revision=roomLayout.revision;
const save = () => fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));
const read = channel => page.evaluate(name=>window[name]||null,channel);
const world = () => read('planetPerformance');
const form = () => read('interestDiagnostics');
const room = () => read('counselingDiagnostics');
function check(name,passed,evidence) {report.checks.push({stage,name,passed:!!passed,...(evidence===undefined?{}:{evidence})});save();assert.ok(passed,name);console.log('PASS',stage,name);}
async function until(readState,predicate,label,timeout=30000) {
  const end=Date.now()+timeout;let last;
  do {last=await readState();if(predicate(last))return last;await pause(180);} while(Date.now()<end);
  throw new Error('Timed out: '+label+'; state='+JSON.stringify(last).slice(0,1700));
}
async function box(snapshot) {
  const canvas=await page.locator('#canvas').boundingBox();assert.ok(canvas?.width,'Visible game canvas');
  const viewport=snapshot?.viewport||[1440,900], scale=Math.min(canvas.width/viewport[0],canvas.height/viewport[1]);
  return {x:canvas.x+(canvas.width-viewport[0]*scale)/2,y:canvas.y+(canvas.height-viewport[1]*scale)/2,width:viewport[0]*scale,height:viewport[1]*scale};
}
async function pointClick(point,snapshot) {
  const b=await box(snapshot),x=b.x+point[0]*b.width,y=b.y+point[1]*b.height;
  if(touch)await page.touchscreen.tap(x,y);else await page.mouse.click(x,y);
  await pause(500);
}
async function scrollToward(geometry,snapshot) {
  const b=await box(snapshot),x=b.x+Math.max(.1,Math.min(.9,geometry.center[0]))*b.width;
  await page.mouse.move(x,b.y+b.height*.55);
  await page.mouse.wheel(0,geometry.center[1]<.48?-75:75);
  await pause(500);
}
async function button(readState,selector,index=0) {
  for(let attempt=0;attempt<80;attempt++) {
    const s=await readState();const matches=s?.buttons?.filter(v=>typeof selector==='string'?v.name===selector:selector.test(v.text))||[];
    const found=matches[index];
    if(found?.visible&&!found.disabled){await pointClick(found.center,s);return;}
    if(found)await scrollToward(found,s);else await pause(200);
  }
  throw Error('Button unavailable: '+selector+' ['+index+']');
}
async function tab(index) {
  const s=await form();
  if(s.buttons.some(v=>v.name==='InterestHigh1')) {
    if(index===0)await button(form,'InterestHigh1');
    else if(index===3)await button(form,'InterestHistory');
    else {await button(form,'InterestHigh3');await button(form,index===1?'InterestKnowledge':'InterestFits');}
  } else {
    const item=s.tabs.find(v=>v.index===index);
    if(item?.visible)await pointClick(item.center,s);
    else {
      await pointClick(s.tabs.find(v=>v.index===s.tab_index).center,s);
      for(let i=s.tab_index;i<index;i++)await page.keyboard.press('ArrowRight');
      for(let i=s.tab_index;i>index;i--)await page.keyboard.press('ArrowLeft');
    }
  }
  await until(form,s=>s?.tab_index===index,'tab '+index);
  await until(form,s=>!s?.busy,'tab data ready');
}
async function fieldPoint(key) {
  for(let attempt=0;attempt<90;attempt++) {
    const s=await form(),field=s?.fields?.[key];assert.ok(field,'Field exists: '+key);
    if(field.visible){await pointClick(field.center,s);return;}
    await scrollToward(field,s);
  }
  throw Error('Cannot scroll to '+key);
}
async function fill(key,value) {
  await fieldPoint(key);const before=(await form()).ticks_ms;
  await page.keyboard.press('ControlOrMeta+A');await page.keyboard.type(value);
  await until(form,s=>s.ticks_ms>before,'fresh geometry after edit');
}
async function fillScoreGrid(section,items,valueFor) {
  await fieldPoint(section+'.'+items[0].id);
  for(let index=0;index<items.length;index++) {
    const before=(await form()).ticks_ms;
    await page.keyboard.press('ControlOrMeta+A');await page.keyboard.type(valueFor(items[index]));
    await until(form,s=>s.ticks_ms>before,'fresh score geometry after edit');
    if(index+1<items.length){await page.keyboard.press('Tab');await pause(150);}
  }
}
async function capture(name) {const file=name+'.png';await page.screenshot({path:path.join(output,file)});report.screenshots.push({stage,file});save();}
async function reviewedPointer(name) {
  await capture(name);
  const requestId=Date.now()+'-'+name;
  fs.writeFileSync(path.join(output,'pointer-request.json'),JSON.stringify({requestId,screenshot:name+'.png',action:'Select a visible menu item using screenshot coordinates.'},null,2));
  console.log('POINTER_REVIEW',name,requestId);
  const reply=await until(async()=>{try{return JSON.parse(fs.readFileSync(path.join(output,'pointer-response.json'),'utf8'));}catch{return null;}},value=>value?.requestId===requestId,'reviewed pointer coordinate',300000);
  assert.ok(Number.isFinite(reply.x)&&Number.isFinite(reply.y));
  if(touch)await page.touchscreen.tap(reply.x,reply.y);else await page.mouse.click(reply.x,reply.y);
  report.checks.push({stage,name:'Reviewed screenshot pointer interaction: '+name,passed:true});save();await pause(550);
}
async function hiddenAccount() {return page.locator('.lw-account').evaluateAll(nodes=>nodes.every(n=>n.hidden||getComputedStyle(n).display==='none'));}
async function formReady() {await until(form,s=>s?.present&&s.open&&!s.busy,'Godot interest form ready');await pause(500);}
async function openSettingsForm() {
  const current=await world();
  if(!current.buttons.some(v=>v.name==='GraphicsSettingsButton'&&v.visible)&&current.buttons.some(v=>v.name==='CompactMenuButton'&&v.visible))await button(world,'CompactMenuButton');
  await button(world,'GraphicsSettingsButton');await until(world,s=>s?.settings_open,'settings opens');
  await button(world,'SettingsInterestProfile');await formReady();
  check('Settings opens the Godot form while account host remains hidden',await hiddenAccount());
}
async function saveForm(complete) {
  const before=(await form()).save_acknowledgments;
  await button(form,complete?/^完成並儲存$/:/^儲存草稿$/);
  await until(form,s=>!s?.busy&&s?.save_acknowledgments>before,'cloud save acknowledgement',45000);
  check(complete?'Complete form receives cloud acknowledgement':'Raw draft receives cloud acknowledgement',true);
  check('Saving keeps account website hidden',await hiddenAccount());
}
async function closeForm() {await button(form,/^關閉$/);await until(form,s=>!s?.open,'form closes');}
async function walkRoomAxis(axis,target) {
  // The authored spawn faces -Z; ordinary strafing never changes that heading.
  // Feedback uses only the actual player position, not a teleport or test hook.
  let stuck=0;
  for(let attempt=0;attempt<18;attempt++) {
    const current=(await room()).player.position,delta=target-current[axis];
    if(Math.abs(delta)<.15)return;
    const key=axis===0?(delta>0?'d':'a'):(delta>0?'s':'w');
    await page.keyboard.down(key);
    try {await pause(Math.min(700,Math.max(65,Math.abs(delta)/3.8*1000)));}
    finally {await page.keyboard.up(key);}
    await pause(550);
    const next=(await room()).player.position;
    stuck=Math.abs(next[axis]-current[axis])<.04?stuck+1:0;
    assert.ok(stuck<3,'Unobstructed normal keyboard route to grade workbench');
  }
  throw Error('Could not reach the authored room approach using keyboard input');
}
async function walkRoomDirect(target,label) {
  const start=(await room()).player.position,dx=target[0]-start[0],dz=target[2]-start[2],length=Math.hypot(dx,dz);
  // Public keyboard strafing keeps the authored heading. Project the desired
  // segment onto that basis so a new room's entrance orientation is respected.
  const facing=roomLayout.spawn.facing||[0,0,-1],facingLength=Math.hypot(facing[0],facing[2]);
  assert.ok(facingLength>.01,'Authored entrance facing is usable');
  const fx=facing[0]/facingLength,fz=facing[2]/facingLength;
  let previous=start,travelled=0,maxDeviation=0,stuck=0;
  for(let attempt=0;attempt<55;attempt++) {
    const current=(await room()).player.position,x=target[0]-current[0],z=target[2]-current[2],remaining=Math.hypot(x,z);
    if(remaining<.18) {
      const evidence={label,start,target,end:current,distance:length,travelled,maxDeviation};report.direct_routes.push(evidence);
      check('Direct keyboard corridor: '+label,maxDeviation<.30&&travelled<=length+.55,evidence);return;
    }
    const axisX=-fz*x+fx*z,axisZ=-fx*x-fz*z,keys=[];
    if(Math.abs(axisX)>.07&&Math.abs(axisX)>Math.abs(axisZ)/2.414)keys.push(axisX>0?'d':'a');
    if(Math.abs(axisZ)>.07&&Math.abs(axisZ)>Math.abs(axisX)/2.414)keys.push(axisZ>0?'s':'w');
    assert.ok(keys.length,'A direct digital walking direction is available');
    for(const key of keys)await page.keyboard.down(key);
    try {await pause(Math.min(140,Math.max(35,remaining/3.8*850)));}
    finally {for(const key of keys)await page.keyboard.up(key);}
    await pause(450);
    const next=(await room()).player.position,step=Math.hypot(next[0]-previous[0],next[2]-previous[2]);
    travelled+=step;
    maxDeviation=Math.max(maxDeviation,Math.abs((next[0]-start[0])*dz-(next[2]-start[2])*dx)/Math.max(length,.001));
    stuck=step<.025?stuck+1:0;previous=next;
    assert.ok(stuck<3&&maxDeviation<.30,'Direct approach must not hit decor or require a sideways detour: '+label);
  }
  throw Error('Direct approach did not reach its destination: '+label);
}
async function visitGradeWorkbench(stageCode,prefix='06') {
  const station=roomLayout.stations.find(v=>v.view==='interest_'+stageCode);
  assert.ok(station,'Authored grade workbench '+stageCode);
  if(roomSmoke)await walkRoomDirect(station.approach,prefix+' to '+stageCode);
  else {await walkRoomAxis(2,station.approach[2]);await walkRoomAxis(0,station.approach[0]);}
  const position=(await room()).player.position;
  check('Keyboard route reaches '+stageCode+' workbench',Math.hypot(position[0]-station.approach[0],position[2]-station.approach[2])<station.radius);
  if(roomSmoke&&prefix.endsWith('-entrance'))await capture(prefix+'-'+stageCode+'-normal-camera');
  await page.keyboard.press('e');await formReady();
  check('Physical '+stageCode+' workbench opens its correct grade area',(await form()).tab_index===(stageCode==='high1'?0:1));
  await until(room,s=>!s.player.controls_enabled,'workbench freezes room controls');
  check('Physical workbench keeps account website hidden',await hiddenAccount());
  await capture(prefix+'-'+stageCode+'-physical-workbench');
  await closeForm();await until(room,s=>s.player.controls_enabled,'workbench close restores controls');
  check('Closing '+stageCode+' workbench preserves position',Math.hypot(...(await room()).player.position.map((v,i)=>v-position[i]))<.02);
}
async function login(mobile=false) {
  console.log('START',mobile?'mobile':'desktop','normal material selection and login');save();
  touch=mobile;
  contextRoomRequestStart=report.room_pack_requests.length;
  context=await browser.newContext(mobile?{...devices['Pixel 7'],viewport:{width:390,height:844},deviceScaleFactor:1}:{viewport:{width:1440,height:900},deviceScaleFactor:1});
  page=await context.newPage();
  page.on('pageerror',error=>report.errors.push({stage,error:String(error)}));
  page.on('console',message=>{
    if(/SCRIPT ERROR|Parse Error|SHADER ERROR|RuntimeError|INVALID_ENUM|INVALID_OPERATION|^ERROR:/.test(message.text()))report.errors.push({stage,error:message.text()});
    else if(message.type()==='warning')report.warnings.push({stage,message:message.text()});
  });
  // Prevent the local acceptance fixture from reaching any production service.
  await context.route('**/*',route=>{
    const url=new URL(route.request().url());
    return /^https?:$/.test(url.protocol)&&!['127.0.0.1','localhost'].includes(url.hostname)?route.abort():route.continue();
  });
  await page.goto(base+'/?performance',{waitUntil:'domcontentloaded'});
  const resourceChoice=page.locator('#resource-choice button[data-pack="full"]');
  await resourceChoice.waitFor({state:'visible',timeout:30000});
  await resourceChoice.click();
  await until(async()=>page.frames().map(f=>f.url()),urls=>urls.some(url=>{try{return new URL(url).pathname==='/admissions/account/';}catch{return false;}}),'normal login page',300000);
  const account=page.frameLocator('.lw-account iframe').frameLocator('iframe.host-content');
  await account.getByLabel('電子信箱',{exact:true}).fill(session.email);
  await account.locator('input[type="password"]').fill(password);
  await account.locator('form').getByRole('button',{name:'登入',exact:true}).click();
  await until(world,s=>s?.buttons?.length,'world after normal login',300000);
  await until(hiddenAccount,Boolean,'account login closes automatically');
  report.build_id=await page.locator('meta[name="little-world-build"]').getAttribute('content');
  check('Normal account login reaches the exported game',true);
}
async function desktop() {
  stage='desktop-settings';await login();await openSettingsForm();
  if(!report.preflight) {
    check('Two main grade areas separate high-one and high-three data',(await form()).buttons.some(v=>v.name==='InterestHigh1'&&v.text==='高一測驗資料')&&(await form()).buttons.some(v=>v.name==='InterestHigh3'&&v.text==='高三測驗資料')&&(await form()).tabs.every(v=>!v.visible));
    check('Form has no assessment-date inputs',!('riasecDate' in (await form()).fields)&&!('knowledgeDate' in (await form()).fields));
  }
  await tab(3);await button(form,/^＋ 新增紀錄$/);await until(form,s=>s.tab_index===0,'new record');
  const title='Browser acceptance '+new Date().toISOString().slice(0,16);
  await fill('title',title);
  await fillScoreGrid('riasec',catalog.riasec,item=>item.id==='R'?'90':'0');
  await capture('01-desktop-riasec');
  await saveForm(false);
  const previous=(await form()).save_acknowledgments;
  await button(form,/^完成並儲存$/);await pause(700);
  check('Incomplete completion focuses the missing knowledge page', (await form()).tab_index===1&&(await form()).save_acknowledgments===previous);
  await fillScoreGrid('knowledge',catalog.knowledge,item=>item.id==='k33'?'18':'0');
  await capture('02-desktop-knowledge');await tab(2);
  const initial=await form();
  check('Both suitability levels initially provide 25 rows',Object.keys(initial.fields).filter(k=>/^bestFits\.\d+\.z$/.test(k)).length===25&&Object.keys(initial.fields).filter(k=>/^suitableFits\.\d+\.z$/.test(k)).length===25);
  await button(form,/^＋ 新增一列$/,0);
  check('Real add-row button creates an editable 26th row',Boolean((await form()).fields['bestFits.25.z']));
  await fieldPoint('bestFits.0.groupId');
  if(args.includes('--review-popups'))await reviewedPointer('03a-desktop-group-popup');
  else {await page.keyboard.press('ArrowDown');await page.keyboard.press('ArrowDown');await page.keyboard.press('ArrowDown');await page.keyboard.press('Enter');await pause(350);}
  await fill('bestFits.0.category','Test category');await fill('bestFits.0.z','-0.25');
  await capture('03-desktop-suitability');await saveForm(true);
  await tab(3);await capture('04-desktop-history');
  await button(form,/^設為之後分析使用$/,0);await until(form,s=>!s.busy,'active selection saved');
  check('History offers completed record editing and active selection',(await form()).buttons.some(v=>v.text==='開啟／編輯'));
  await button(form,/^開啟／編輯$/,0);await formReady();
  await until(form,s=>s.tab_index===0,'history opens record');
  check('History opens the saved record in the Godot editor',await hiddenAccount());
  await closeForm();await button(world,'CloseGraphicsSettings');
  await roomJourney();
  await context.close();context=null;
}
async function roomJourney(prefix='') {
  stage=touch?'mobile-room':'desktop-room';
  const picture=(name,legacy)=>prefix?prefix+'-'+name:legacy;
  const requests=()=>report.room_pack_requests.slice(contextRoomRequestStart);
  const current=await world();
  if(!current.destinations_open&&!current.buttons.some(v=>v.visible&&/選擇目的地/.test(v.text))&&current.buttons.some(v=>v.name==='CompactMenuButton'&&v.visible))await button(world,'CompactMenuButton');
  if(!(await world()).destinations_open)await button(world,/選擇目的地/);
  await button(world,/^01\s/);
  await until(world,s=>s?.avatar?.ready&&!s.overview&&!s.preparing_roam&&!s.player?.paused&&!s.player?.entering,'first station arrival',300000);
  if((await world()).destinations_open)await button(world,/收起目的地/);
  check('Counseling interior pack is deferred until room entry',requests().length===0);
  await page.keyboard.press('e');
  if(!skipRetry) {
    await until(room,s=>s?.present&&!s.ready&&s.buttons.some(v=>v.visible&&v.text==='重試載入'),'room download failure offers retry',90000);
    check('Failed room download freezes movement and offers retry',!(await room()).player.controls_enabled&&requests().some(v=>v.status===503));
    await capture(picture('download-retry','05a-room-download-retry'));
    releaseRoomDownload=true;
    await button(room,/^重試載入$/);
  }
  await until(room,s=>s?.present&&s.ready&&s.player?.controls_enabled,'first station counseling room',300000);
  check('First station interaction enters the authored counseling room',true);
  if(!skipRetry)check('Room retry fetches the pack after the intentional failure',requests().some(v=>v.status===503)&&requests().some(v=>v.status===200));
  else check('Entering fetches the deferred room pack successfully',requests().some(v=>v.status===200));
  await capture(picture('room','05-desktop-room'));
  const entrance=(await room()).player.position;
  if(!roomSmoke) {
    await page.keyboard.down('w');await pause(650);await page.keyboard.up('w');await pause(600);
    const after=(await room()).player.position;
    check('Room movement responds to ordinary keyboard input',Math.hypot(...after.map((v,i)=>v-entrance[i]))>.15);
  }
  await button(room,/^我的興趣量表$/);await formReady();
  await until(room,s=>!s.player.controls_enabled,'room controls frozen during form');
  check('Room form freezes movement and keeps cloud host hidden',!(await room()).player.controls_enabled&&await hiddenAccount());
  await capture(picture('room-form','06-desktop-room-form'));const frozen=(await room()).player.position;
  await closeForm();await until(room,s=>s.player.controls_enabled,'room controls restored');
  check('Closing returns to the same room position',Math.hypot(...(await room()).player.position.map((v,i)=>v-frozen[i]))<.02);
  if(roomSmoke) {
    await visitGradeWorkbench('high1',prefix+'-entrance');
    await visitGradeWorkbench('high3',prefix+'-between');
    await walkRoomDirect(entrance,prefix+' high3 return to entrance');
    await visitGradeWorkbench('high3',prefix+'-entrance');
    await visitGradeWorkbench('high1',prefix+'-between');
    await walkRoomDirect(entrance,prefix+' high1 return to entrance');
  } else if(!report.preflight) {await visitGradeWorkbench('high1',prefix||'06');await visitGradeWorkbench('high3',prefix||'06');}
  await button(room,'ReturnToWorld');await until(room,s=>!s?.present,'room exits');
  await until(world,s=>s?.player&&!s.player.paused&&!s.player.entering,'world controls restored',120000);
  check('Return button restores the outdoor world',true);
}
async function focusedRoom(mobile=false) {
  stage=mobile?'mobile-room':'desktop-room';
  await login(mobile);
  await roomJourney(mobile?'mobile':'desktop');
  await context.close();context=null;
}
async function mobile() {
  stage='mobile-touch';await login(true);await openSettingsForm();
  let s=await form();
  const primary=s.buttons.filter(v=>v.visible&&['儲存草稿','完成並儲存','關閉'].includes(v.text));
  check('Mobile layout retains usable primary touch targets',primary.length===3&&primary.every(v=>v.size[1]>=44));
  await capture('07-mobile-riasec');await tab(1);await capture('08-mobile-knowledge');
  await tab(2);await capture('09-mobile-suitability');
  const visibleFields=Object.values((await form()).fields).filter(v=>v.visible);
  check('Mobile suitability controls remain within the visible width',visibleFields.length>0&&visibleFields.every(v=>v.center[0]>0&&v.center[0]<1));
  await fieldPoint('bestFits.0.groupId');
  if(args.includes('--review-popups'))await reviewedPointer('09a-mobile-group-popup');
  else {await capture('09a-mobile-group-popup');await page.keyboard.press('Escape');await pause(400);}
  await tab(3);await capture('10-mobile-history');
  check('Touch grade controls and record management keep the account website hidden',(await form()).tab_index===3&&await hiddenAccount());
  await closeForm();await button(world,'CloseGraphicsSettings');
  check('Mobile close restores settings then the game',!(await form()).open&&!(await world()).settings_open);
}
(async()=>{try {
  assert.ok(fs.existsSync(path.join(site,'index.html')),'Web export exists');
  if(roomSmoke) {
    const evidence=JSON.parse(fs.readFileSync(path.join(root,'deliverables/counseling-room/form-validation.json'),'utf8'));
    const mismatches=Object.entries(evidence.sourceFingerprints).filter(([file,hash])=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex')!==hash).map(([file])=>file);
    stage='source-equivalence';
    check('Form, catalog and account sources match the accepted r4 fingerprints',mismatches.length===0,{checkedFiles:Object.keys(evidence.sourceFingerprints),mismatches});
    report.retained_form_evidence={build:evidence.browserRunner.finalRun.buildId,report:'../../web/report.json',checks:evidence.browserRunner.finalRun.checks};save();
  }
  const config=await fetch(new URL('/admissions/firebase-config.json',host)).then(r=>r.json());
  assert.equal(config.useEmulators,true);assert.equal(config.projectId,'demo-starpath-tests');
  server=http.createServer((req,res)=>{
    const url=new URL(req.url,'http://localhost');
    if(url.pathname.startsWith('/admissions/')) {
      const upstream=http.request(new URL(req.url,host),{method:req.method,headers:{...req.headers,host:host.host}},incoming=>{res.writeHead(incoming.statusCode,incoming.headers);incoming.pipe(res);});
      upstream.on('error',()=>{res.writeHead(502).end();});req.pipe(upstream);return;
    }
    let name;try{name=decodeURIComponent(url.pathname);}catch{res.writeHead(400).end();return;}
    if(/\/packs\/counseling_room[.-].*\.pck(?:\.gz)?$/.test(name)) {
      const reject=!skipRetry&&!releaseRoomDownload;
      report.room_pack_requests.push({stage,path:name,status:reject?503:200});save();
      if(reject){res.writeHead(503,{'Content-Type':'text/plain','Cache-Control':'no-store'}).end('Intentional local acceptance failure; use room retry.');return;}
    }
    if(name.endsWith('/'))name+='index.html';const file=path.resolve(site,'.'+name);
    if(!file.startsWith(site+path.sep)){res.writeHead(403).end();return;}
    if(!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404).end();return;}
    const mime={'.js':'application/javascript','.html':'text/html','.wasm':'application/wasm','.json':'application/json','.css':'text/css','.svg':'image/svg+xml','.png':'image/png'}[path.extname(file)]||'application/octet-stream';
    res.writeHead(200,{'Content-Type':mime,'Content-Length':fs.statSync(file).size,'Cache-Control':'no-store'});fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));base='http://127.0.0.1:'+server.address().port;
  browser=await chromium.launch({channel:'chrome',headless:!args.includes('--headed')});report.browser=browser.version();
  if(!args.includes('--mobile-only'))await (roomSmoke?focusedRoom(false):desktop());
  if(!args.includes('--desktop-only'))await (roomSmoke?focusedRoom(true):mobile());
  check('No browser, engine script or shader errors',report.errors.length===0,report.errors);report.passed=true;
} catch(error) {
  report.passed=false;report.errors.push({stage,error:String(error.stack||error)});process.exitCode=1;console.error(error);
  if(page) {report.last={world:await world().catch(()=>null),form:await form().catch(()=>null),room:await room().catch(()=>null)};await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});}
} finally {
  report.finished=new Date().toISOString();save();if(context)await context.close();if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));
}})();
