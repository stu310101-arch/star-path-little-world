// Identical-input localhost benchmark. No engine state mutation through JS.
const {chromium}=require('playwright');
const fs=require('node:fs'), path=require('node:path'), {spawn}=require('node:child_process');
const [target,label='low-end',profile='current',minutes='0']=process.argv.slice(2);
const url=new URL(target);
if(!['localhost','127.0.0.1'].includes(url.hostname))throw Error('Localhost only');
url.searchParams.set('performance','');
const out=path.resolve('deliverables/low-end');fs.mkdirSync(out,{recursive:true});
const file=path.join(out,label+'.json');
const report={url:url.href,label,profile,started:new Date().toISOString(),viewport:{width:1280,height:800},
  samples:[],phases:[],requests:[],errors:[],method:'Real keyboard/mouse; WebGL clear-marked requestAnimationFrame submission intervals (CPU cadence, not GPU presentation); Windows owned process-tree memory.'};
const save=()=>fs.writeFileSync(file,JSON.stringify(report,null,2));
const delay=ms=>new Promise(r=>setTimeout(r,ms));
let server,browser,page,memory;
const watchdog=setTimeout(()=>{report.errors.push('40 minute timeout');save();server?.kill();process.exitCode=1;},2400000);
async function state(){return page.evaluate(()=>({metrics:window.planetPerformance,room:window.trainingRoomState,
  marks:window.__lowProbe?.marks,heap:performance.memory?{used:performance.memory.usedJSHeapSize,total:performance.memory.totalJSHeapSize}:null}));}
async function until(name,predicate,timeout=240000){let last;const end=Date.now()+timeout;report.pending=name;save();do{last=await state();if(predicate(last)){report.pending=null;save();return last;}await delay(400);}while(Date.now()<end);report.timeout_state=last;throw Error(`Timeout ${name}: ${JSON.stringify(last)}`);}
async function box(){const b=await page.locator('#canvas').boundingBox();const s=Math.min(b.width/1440,b.height/900);return{x:b.x+(b.width-1440*s)/2,y:b.y+(b.height-900*s)/2,width:1440*s,height:900*s};}
async function click(name,rx){for(let i=0;i<20;i++){const s=await state(),buttons=s.metrics?.buttons||[],matches=v=>name?v.name===name:rx.test(v.text),b=buttons.find(v=>v.visible&&matches(v)),c=await box();if(b){await page.mouse.click(c.x+b.center[0]*c.width,c.y+b.center[1]*c.height);await until('fresh button response',v=>v.metrics?.ticks_ms>s.metrics.ticks_ms,30000);return;}const rows=buttons.filter(b=>b.visible&&/^\d{2}\s/.test(b.text));const anchor=rows[Math.floor(rows.length/2)]?.center||[.15,.72],target=buttons.find(matches);await page.mouse.move(c.x+c.width*anchor[0],c.y+c.height*anchor[1]);await page.mouse.wheel(0,target&&target.center[1]<anchor[1]?-150:150);await delay(1200);await until('fresh scroll position',v=>v.metrics?.ticks_ms>s.metrics.ticks_ms,30000);}throw Error('Button missing '+(name||rx));}
const roaming=s=>!s.room&&s.metrics?.avatar?.ready&&!s.metrics.preparing_roam&&s.metrics.player&&!s.metrics.player.overview&&!s.metrics.player.entering&&!s.metrics.player.paused;
async function hold(keys,ms){try{for(const k of keys)await page.keyboard.down(k);await delay(ms);}finally{for(const k of keys.reverse())await page.keyboard.up(k);}}
async function drag(dx,dy){const c=await box();await page.mouse.move(c.x+c.width*.7,c.y+c.height*.43);await page.mouse.down({button:'right'});try{await page.mouse.move(c.x+c.width*.7+dx,c.y+c.height*.43+dy,{steps:12});}finally{await page.mouse.up({button:'right'});}}
async function sample(name,action=()=>delay(8000)){
  await page.evaluate(()=>{window.__lowProbe.frames=[];window.__lowProbe.longTasks=[];window.__lowProbe.since=performance.now();});
  const begin=Date.now();await action();
  const data=await page.evaluate(()=>{const p=window.__lowProbe,sorted=[...p.frames].sort((a,b)=>a-b);return{elapsed:performance.now()-p.since,count:sorted.length,
    frame_ms_mean:sorted.length?sorted.reduce((a,b)=>a+b,0)/sorted.length:null,p95_ms:sorted.length?sorted[Math.min(sorted.length-1,Math.ceil(sorted.length*.95)-1)]:null,
    max_ms:sorted.at(-1)||null,over_100_ms:sorted.filter(v=>v>100).length,longTasks:p.longTasks,observed_gl_viewports:[...p.viewportSizes]};});
  data.average_submission_fps=data.frame_ms_mean?1000/data.frame_ms_mean:null;
  report.samples.push({name,epoch_start:begin,...data,...await state()});save();
  await page.screenshot({path:path.join(out,`${label}-${name}.png`),timeout:60000});
}
async function destination(station){const s=await state();if(!s.metrics.destinations_open)await click(null,/選擇目的地/);await click(null,new RegExp('^\\d{2}\\s+'+station.label));await until('destination '+station.id,s=>roaming(s)&&s.metrics.nearest_id===station.id);await until('detail settles',s=>roaming(s)&&s.metrics.streaming.pending_regions===0);const after=await state();if(after.metrics.destinations_open)await click(null,/收起目的地/);}
async function approachPortal(station){
  await delay(1200);if((await state()).metrics?.nearest_id===station.id)return;
  await hold(['a'],350);await hold(['w'],400);
  for(let i=0;i<5;i++){await delay(1200);if((await state()).metrics?.nearest_id===station.id)return;await hold(['w'],150);}
  throw Error('Cannot reach portal '+station.id+' using real movement');
}
async function leaveRoom(){const s=await state();if(!s.room)return;for(let i=0;i<12;i++){const v=await state();if(!v.room)return;if(v.room.near_exit){await page.keyboard.press('e');break;}await hold(['s'],180);await delay(500);}await until('return from room',roaming);}
async function enterRoom(){await approachPortal({id:'wordking'});await page.keyboard.press('e');const s=await until('room ready',s=>s.room?.ready);report.phases.push({phase:'room-light-ready',epoch_ms:Date.now(),...s});save();if(s.room.detail_state)await until('room detail',s=>s.room?.detail_state==='ready'||s.room?.detail_ready===true,240000);}
(async()=>{try{
  server=await chromium.launchServer({channel:'chrome',headless:true});browser=await chromium.connect(server.wsEndpoint());report.browser=browser.version();
  report.browser_pid=server.process().pid;memory=spawn('python',[path.resolve('tools/observe_process_memory.py'),'--pid',String(report.browser_pid),'--output',path.join(out,label+'-memory.json')],{windowsHide:true,stdio:['ignore','ignore','pipe']});
  memory.stderr.on('data',d=>{report.errors.push('Memory sampler: '+d.toString());save();});
  const context=await browser.newContext({viewport:report.viewport});
  await context.addInitScript(()=>{
    const p=window.__lowProbe={marks:{},frames:[],longTasks:[],since:0,viewportSizes:new Set()};let id=0,current=0,drawn=-1,last;
    const raf=window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame=callback=>raf(t=>{const before=current;current=++id;callback(t);if(drawn===current){const now=performance.now();if(last!==undefined)p.frames.push(now-last);last=now;}current=before;});
    for(const cls of [window.WebGLRenderingContext,window.WebGL2RenderingContext])for(const name of ['clear','clearBufferfv']){
      const original=cls?.prototype[name];if(original)cls.prototype[name]=function(...args){drawn=current;return original.apply(this,args);};
    }
    for(const cls of [window.WebGLRenderingContext,window.WebGL2RenderingContext]){
      const original=cls?.prototype.viewport;if(original)cls.prototype.viewport=function(x,y,w,h){p.viewportSizes.add(`${w}x${h}`);return original.call(this,x,y,w,h);};
    }
    addEventListener('planet-world-ready',()=>p.marks.worldReady=performance.now());
    addEventListener('planet-content-ready',()=>p.marks.contentReady=performance.now());
    const observe=()=>{if(window.planetWorldReady&&p.marks.firstRaf===undefined)p.marks.firstRaf=performance.now();raf(observe);};raf(observe);
    try{new PerformanceObserver(list=>{for(const e of list.getEntries())p.longTasks.push({start:e.startTime,duration:e.duration});}).observe({type:'longtask',buffered:true});}catch{}
  });
  page=await context.newPage();page.on('pageerror',e=>report.errors.push(String(e)));
  page.on('console',m=>{if(m.type()==='error'&&!m.text().includes('404 (File not found)'))report.errors.push(m.text());});
  page.on('request',r=>{if(/\.pck(?:\?|$)/.test(r.url()))report.requests.push({url:r.url(),epoch_ms:Date.now()});});
  const start=Date.now();await page.goto(url.href,{waitUntil:'domcontentloaded',timeout:180000});
  await until('world',s=>s.metrics?.buttons?.length);
  report.build_id=await page.locator('meta[name="little-world-build"]').getAttribute('content');
  report.gpu=await page.evaluate(()=>{const g=document.getElementById('canvas').getContext('webgl2'),e=g.getExtension('WEBGL_debug_renderer_info');return e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):g.getParameter(g.RENDERER);});
  if(profile!=='current'){await click('GraphicsSettingsButton');await click(profile==='low'?'QualityLow':'QualityStandard');await click('CloseGraphicsSettings');}
  // Verify input response separately from ready/rAF: open and close the settings.
  await click('GraphicsSettingsButton');await until('input response',s=>s.metrics?.settings_open);report.first_verified_input_ms=Date.now()-start;await click('CloseGraphicsSettings');
  await sample('first-roam-transition',async()=>{await page.keyboard.press('Tab');await until('first roam',roaming);report.first_roam_ms=Date.now()-start;});
  await page.keyboard.press('Tab');await until('overview after first roam',s=>s.metrics?.overview);
  await sample('overview');await sample('overview-rotate',async()=>{for(const [x,y]of[[90,20],[-100,-20],[10,0]]){await drag(x,y);await delay(1000);}await page.mouse.wheel(0,-120);await delay(3000);});
  await page.keyboard.press('Tab');await until('resume roam',roaming);
  await sample('near-moving',()=>hold(['w'],2500));
  const layout=JSON.parse(fs.readFileSync('game/data/world_layout.json','utf8')),stations=layout.stations;
  for(const station of stations){
    await sample('transition-'+station.id,()=>destination(station));await sample('district-'+station.id);
    await approachPortal(station);
    if(station.id==='wordking'){await sample('indoor-enter',enterRoom);await sample('indoor');await sample('indoor-exit',leaveRoom);}
    else {
      await page.keyboard.press('e');await until('interaction '+station.id,s=>s.metrics?.player?.paused&&!s.metrics?.player?.entering,60000);
      await page.screenshot({path:path.join(out,`${label}-interaction-${station.id}.png`),timeout:60000});
      await page.keyboard.press('Escape');await until('resume '+station.id,roaming);
    }
  }
  // Same authored bridge route as existing functional QA, using real inputs.
  await destination(stations[0]);await sample('crosswalk',async()=>{
    for(let n=0;n<35;n++){const s=await state(),p=s.metrics.player.position,localX=layout.radius*p[0]/p[1];
      if(Math.abs(localX)>.4)await hold([localX>0?'a':'d'],Math.min(450,Math.max(70,(Math.abs(localX)-.2)/3.8*1000)));
      else await hold(['Shift','s'],1300);
      await delay(600);const v=await state();if(Math.hypot(...v.metrics.player.position)<layout.radius-1)throw Error('Player fell below surface');
      const pos=v.metrics.player.position;const best=[...stations].sort((a,b)=>b.normal.reduce((s,n,i)=>s+n*pos[i],0)-a.normal.reduce((s,n,i)=>s+n*pos[i],0))[0];if(best.id!=='counseling'){report.crossed=best.id;break;}
    }
  });
  const soakEnd=start+report.first_roam_ms+Number(minutes)*60000;let cycle=0;
  while(Date.now()<soakEnd){for(const station of stations){await destination(station);await sample(`soak-${cycle}-${station.id}`,async()=>{await drag(65,10);await delay(1800);await drag(-65,-10);await delay(1800);});if(station.id==='wordking'){await enterRoom();await delay(6000);await leaveRoom();}if(Date.now()>=soakEnd)break;}cycle++;}
  report.soak_cycles=cycle;
  for(let i=0;i<3;i++){await destination(stations[0]);await page.keyboard.press('Tab');await until('unload',s=>s.metrics?.overview&&s.metrics.streaming.loaded_chunks===0);await sample('unloaded-'+i,()=>delay(2500));}
  report.final_state=await state();report.playthrough_duration_ms=Date.now()-start-report.first_roam_ms;report.finished=new Date().toISOString();
}catch(e){report.errors.push(String(e.stack||e));}finally{save();await browser?.close().catch(()=>{});await server?.close().catch(()=>{});clearTimeout(watchdog);console.log(JSON.stringify({file,errors:report.errors,samples:report.samples.length}));process.exitCode=report.errors.length?1:0;}})();
