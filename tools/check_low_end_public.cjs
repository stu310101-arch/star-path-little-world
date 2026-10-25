// Public deployment smoke test. Real game inputs; no login or account access.
// Five-minute overall deadline. HTTP success alone never counts as gameplay.
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const url=new URL(process.argv[2]||'https://star-path-little-world.star-path-little-world.workers.dev/');
url.searchParams.set('performance','');
const expected=process.argv[3]||'cf-128fa286e43bff69';
const out=path.resolve('deliverables/low-end-20261021');fs.mkdirSync(out,{recursive:true});
const file=path.join(out,'public-gameplay.json');
const report={url:url.href,expected_build_id:expected,started:new Date().toISOString(),checks:[],progress:[],snapshots:[],screenshots:[],runtime_errors:[],http_errors:[],request_failures:[],console:[],errors:[],
  method:'Fresh Chrome context on the real public URL, actual mouse/keyboard gameplay and full-map actions, read-only opt-in telemetry. No login or personal-data operations.',
  scope:'Functional public smoke test on desktop Chrome; not iPhone/old-hardware performance or thermal evidence.'};
let browser,page,phase='starting',lastProgress=0,deadline=Date.now()+300000,timedOut=false;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const save=()=>fs.writeFileSync(file,JSON.stringify(report,null,2));
const check=(name,passed,evidence=null)=>{report.checks.push({name,passed:Boolean(passed),evidence});save();console.log(passed?'PASS':'FAIL',name);assert.ok(passed,name);};
const read=()=>page.evaluate(()=>({build:document.querySelector('meta[name="little-world-build"]')?.content,
  ready:window.planetWorldReady===true,boot:window.planetBootDelivery||null,metrics:window.planetPerformance||null,
  status:document.querySelector('#status')?.innerText,visible:document.visibilityState==='visible',focused:document.hasFocus()}));
function progress(s){
  if(Date.now()-lastProgress<10000)return;lastProgress=Date.now();
  const row={at:new Date().toISOString(),phase,ready:s.ready,build:s.build,boot:s.boot,status:s.status,
    packs:s.metrics?.packs,avatar:s.metrics?.avatar};report.progress.push(row);save();
  console.log('PROGRESS',JSON.stringify({phase,ready:s.ready,status:s.status,boot:s.boot}));
}
async function waitFor(predicate,label){
  phase=label;let s;
  while(Date.now()<deadline&&!timedOut){s=await read();progress(s);if(predicate(s))return s;await delay(600);}
  throw Error('Five-minute deadline reached during '+label);
}
async function box(s){const c=await page.locator('#canvas').boundingBox();const [w,h]=s.metrics.viewport;const scale=Math.min(c.width/w,c.height/h);return{x:c.x+(c.width-w*scale)/2,y:c.y+(c.height-h*scale)/2,width:w*scale,height:h*scale};}
async function click(name){
  phase='click '+name;
  for(let i=0;i<20&&Date.now()<deadline;i++){
    const s=await read(),b=s.metrics.buttons.find(b=>b.name===name),c=await box(s);
    if(b?.visible&&b.center.every(n=>n>=0&&n<=1)){await page.mouse.click(c.x+b.center[0]*c.width,c.y+b.center[1]*c.height);await waitFor(n=>n.metrics?.ticks_ms>s.metrics.ticks_ms,'fresh '+name);return;}
    await page.mouse.move(c.x+c.width*.5,c.y+c.height*.5);await page.mouse.wheel(0,b&&b.center[1]<.5?-180:180);await delay(700);
  }throw Error('UI button unavailable: '+name);
}
async function snapshot(name){const s=await read();report.snapshots.push({name,...s});save();return s;}
async function screenshot(name){const nameWithExt='public-'+name+'.png';await page.screenshot({path:path.join(out,nameWithExt),timeout:10000});report.screenshots.push(nameWithExt);save();}
const distance=(a,b)=>Math.hypot(...a.map((v,i)=>v-b[i]));
const watchdog=setTimeout(()=>{timedOut=true;report.timed_out=true;report.errors.push('Five-minute overall public gameplay deadline reached.');save();browser?.close().catch(()=>{});},300000);
(async()=>{try{
  browser=await chromium.launch({channel:'chrome',headless:true});report.browser=browser.version();
  const context=await browser.newContext({viewport:{width:1280,height:800},deviceScaleFactor:1});page=await context.newPage();
  page.on('pageerror',e=>report.runtime_errors.push(String(e)));
  page.on('console',m=>{const text=m.text();if(/SCRIPT ERROR|Parse Error|SHADER ERROR|RuntimeError|INVALID_ENUM|INVALID_OPERATION|ERROR:/.test(text))report.runtime_errors.push(text);if(m.type()==='error'||m.type()==='warning')report.console.push({type:m.type(),text,location:m.location()});});
  page.on('response',r=>{if(r.status()>=400)report.http_errors.push({url:r.url(),status:r.status()});});
  page.on('requestfailed',r=>report.request_failures.push({url:r.url(),failure:r.failure()}));
  await page.goto(url.href,{waitUntil:'domcontentloaded',timeout:45000});await page.bringToFront();
  const shell=await read();check('Public HTML identifies the intended build',shell.build===expected,{actual:shell.build,expected});
  await screenshot('loading');
  await waitFor(s=>s.metrics?.buttons?.length>0,'public game startup/download');
  await screenshot('startup');
  await click('GraphicsSettingsButton');await click('QualityMobile');await click('CloseGraphicsSettings');
  await page.keyboard.press('Tab');
  await waitFor(s=>s.metrics?.avatar?.ready&&!s.metrics.overview&&!s.metrics.preparing_roam&&!s.metrics.player.entering&&!s.metrics.player.paused,'public playable avatar/download');
  const before=await snapshot('before-walking');
  check('Public gameplay applies constrained mode',before.metrics.graphics.constrained_runtime&&before.metrics.graphics.applied_max_fps===30);
  const positions=[before.metrics.player.position];
  for(const key of ['w','s','w','s']){await page.keyboard.down(key);try{await delay(1500);}finally{await page.keyboard.up(key);}const s=await snapshot('walk-'+positions.length);positions.push(s.metrics.player.position);}
  const segments=positions.slice(1).map((p,i)=>distance(p,positions[i]));
  check('Real public W/S inputs move the playable character repeatedly',segments.filter(d=>d>.05).length>=3&&segments.reduce((a,b)=>a+b,0)>.5,segments);
  await screenshot('roaming');
  const mapState=await read(),canvas=await box(mapState),center=mapState.metrics.minimap_button;
  await page.mouse.click(canvas.x+center[0]*canvas.width,canvas.y+center[1]*canvas.height);
  await waitFor(s=>s.metrics?.full_map_open,'public full map opens');await screenshot('full-map');
  await click('CloseWorldMap');await waitFor(s=>!s.metrics?.full_map_open&&!s.metrics?.player.paused,'public map closes and resumes');
  const returned=await snapshot('after-map-close');
  check('Closing public map restores unpaused roaming',!returned.metrics.player.paused&&!returned.metrics.full_map_open&&!returned.metrics.overview);
  check('Public constrained runtime keeps full-detail blocks unloaded',returned.metrics.streaming.loaded_chunks===0&&returned.metrics.streaming.detail_nodes===0&&returned.metrics.streaming.constrained_runtime,returned.metrics.streaming);
  check('Public gameplay remains visible and focused',returned.visible&&returned.focused);
  check('No public script/shader/browser runtime errors',report.runtime_errors.length===0,report.runtime_errors);
  await screenshot('after-map-close');report.passed=true;
}catch(e){report.passed=false;report.errors.push(String(e.stack||e));console.error(e);process.exitCode=1;
  if(page&&!page.isClosed()){report.last_state=await read().catch(()=>null);await screenshot('incomplete').catch(()=>{});}
}finally{clearTimeout(watchdog);report.finished=new Date().toISOString();report.last_phase=phase;save();if(browser)await browser.close().catch(()=>{});}})();
