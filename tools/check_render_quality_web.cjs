// Local real-input render comparison. Desktop Chrome results do not predict
// iPhone Safari GPU throughput, memory limits or thermal behavior.
const {chromium}=require('playwright');
const fs=require('node:fs'), path=require('node:path'), http=require('node:http');
const assert=require('node:assert/strict');
const site=path.resolve(process.argv[2]||'_site');
const out=path.resolve('deliverables/render-quality/web');fs.mkdirSync(out,{recursive:true});
const report={checks:[],samples:[],errors:[],method:'Windows Chrome hardware rendering, 1280x800, same scene and real UI input. WebGL submission intervals are CPU submission cadence, not GPU presentation or iPhone performance.'};
let server,browser,page;
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const save=()=>fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
const check=(name,value)=>{assert.ok(value,name);report.checks.push(name);console.log('PASS',name);save();};
const state=()=>page.evaluate(()=>window.planetPerformance);
async function wait(predicate,timeout=180000){await page.waitForFunction(predicate,null,{timeout});}
async function click(name){
  for(let tries=0;tries<16;tries++){
    const s=await state(), b=s?.buttons?.find(x=>x.name===name), canvas=await page.locator('#canvas').boundingBox();
    const scale=Math.min(canvas.width/1440,canvas.height/900);
    const box={x:canvas.x+(canvas.width-1440*scale)/2,y:canvas.y+(canvas.height-900*scale)/2,w:1440*scale,h:900*scale};
    if(b?.visible){await page.mouse.click(box.x+b.center[0]*box.w,box.y+b.center[1]*box.h);await pause(1150);return;}
    await page.mouse.move(box.x+box.w*.5,box.y+box.h*.5);
    await page.mouse.wheel(0,b&&b.center[1]<.5?-180:180);await pause(1100);
  }
  throw Error('Button unavailable: '+name);
}
async function profile(name){await click('GraphicsSettingsButton');await click(name);await click('FPS30');await click('CloseGraphicsSettings');}
async function sample(name,seconds=6,move=false){
  await page.evaluate(()=>{window.__qualityProbe.frames=[];window.__qualityProbe.samples=[];window.__qualityProbe.last=undefined;});
  if(move)await page.keyboard.down('w');
  try{await pause(seconds*1000);}finally{if(move)await page.keyboard.up('w');}
  const raw=await page.evaluate(()=>({frames:window.__qualityProbe.frames,samples:window.__qualityProbe.samples}));
  const sorted=raw.frames.slice().sort((a,b)=>a-b),sum=sorted.reduce((a,b)=>a+b,0);
  report.samples.push({name,count:sorted.length,submission_fps:sorted.length*1000/sum,p95_ms:sorted[Math.ceil(sorted.length*.95)-1],max_ms:sorted.at(-1),over_100_ms:sorted.filter(x=>x>100).length,metrics:await state(),interval_samples:raw.samples});
  await page.screenshot({path:path.join(out,name+'.png')});save();
  console.log('SAMPLE',name,report.samples.at(-1).submission_fps);
}
(async()=>{try{
  server=http.createServer((req,res)=>{
    const url=new URL(req.url,'http://localhost');let name=decodeURIComponent(url.pathname);if(name.endsWith('/'))name+='index.html';
    const file=path.resolve(site,'.'+name);
    if(!file.startsWith(site+path.sep)||!fs.existsSync(file)){res.writeHead(404).end();return;}
    const type=name.endsWith('.js')?'application/javascript':name.endsWith('.html')?'text/html':name.endsWith('.wasm')?'application/wasm':name.endsWith('.json')?'application/json':'application/octet-stream';
    res.writeHead(200,{'Content-Type':type,'Content-Length':fs.statSync(file).size});fs.createReadStream(file).pipe(res);
  });await new Promise(r=>server.listen(0,'127.0.0.1',r));
  browser=await chromium.launch({channel:'chrome',headless:true});
  report.browser=browser.version();
  const context=await browser.newContext({viewport:{width:1280,height:800},deviceScaleFactor:1});
  await context.addInitScript(()=>{
    const p=window.__qualityProbe={frames:[],samples:[],last:undefined};
    const raf=window.requestAnimationFrame.bind(window);let current=0,id=0,drawn=0;
    window.requestAnimationFrame=cb=>raf(t=>{const before=current;current=++id;cb(t);if(drawn===current){const now=performance.now();if(p.last!==undefined)p.frames.push(now-p.last);p.last=now;}current=before;});
    for(const cls of [window.WebGLRenderingContext,window.WebGL2RenderingContext])for(const name of ['clear','clearBufferfv']){
      const original=cls?.prototype[name];if(original)cls.prototype[name]=function(...args){drawn=current;return original.apply(this,args);};
    }
    setInterval(()=>{const s=window.planetPerformance;if(s)p.samples.push({at:performance.now(),graphics:s.graphics,draw_calls:s.draw_calls,primitives:s.primitives,buffer_bytes:s.render_buffer_bytes,texture_bytes:s.render_texture_bytes,mounted_bytes:s.packs?.mounted_bytes});},1000);
  });
  page=await context.newPage();
  page.on('pageerror',e=>report.errors.push(String(e)));
  page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|SHADER ERROR|RuntimeError|INVALID_ENUM|INVALID_OPERATION/.test(m.text()))report.errors.push(m.text());});
  await page.goto('http://127.0.0.1:'+server.address().port+'/?performance',{waitUntil:'domcontentloaded'});
  await wait(()=>window.planetPerformance?.buttons?.length>0);
  report.build_id=await page.locator('meta[name="little-world-build"]').getAttribute('content');
  report.gpu=await page.evaluate(()=>{const gl=document.getElementById('canvas').getContext('webgl2'),ext=gl.getExtension('WEBGL_debug_renderer_info');return ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER);});
  await profile('QualityMobile');
  await page.keyboard.press('Tab');
  await wait(()=>{const s=window.planetPerformance;return s?.avatar?.ready&&!s.overview&&!s.preparing_roam&&s.streaming?.pending_regions===0;});
  await pause(3000);await sample('mobile-540');
  const oldPos=(await state()).player.position;
  await sample('mobile-walking',3,true);
  report.walk_distance=Math.hypot(...(await state()).player.position.map((v,i)=>v-oldPos[i]));
  check('Real keyboard movement works after quality upgrade',report.walk_distance>.5);
  await profile('QualityBalanced');
  check('Balanced retains 30 FPS and reduced scene policy',(await state()).graphics.frame_limit===30&&(await state()).streaming.low_quality);
  await sample('balanced-settle',42);
  const clear=await state();
  check('Balanced resolution stays within 720p cap',clear.graphics.internal_3d_pixels[0]<=1280&&clear.graphics.internal_3d_pixels[1]<=720);
  check('Stable desktop run promotes from initial 540p',clear.graphics.adaptive_height>540);
  await sample('balanced-clear');
  await click('GraphicsSettingsButton');
  const frozen=(await state()).graphics.adaptive_height;
  await pause(5000);
  check('Settings menu freezes adaptive resolution',(await state()).graphics.adaptive_height===frozen&&!(await state()).graphics.sampling_gameplay);
  await page.screenshot({path:path.join(out,'settings.png')});
  await click('CloseGraphicsSettings');
  // Profile comparisons use the identical final camera/position.
  await profile('QualityMobile');await pause(2000);await sample('mobile-same-view');
  await profile('QualityStandard');await pause(3000);await sample('standard-same-view');
  await profile('QualityBalanced');
  await page.reload({waitUntil:'domcontentloaded'});await wait(()=>window.planetPerformance?.graphics?.quality_profile==='balanced');
  check('Balanced profile and 30 FPS persist across reload',(await state()).graphics.frame_limit===30);
  check('Release memory reports availability instead of treating zero as safe',(await state()).static_memory_available===false);
  check('Shader, engine and browser errors absent',report.errors.length===0);
  report.passed=true;
}catch(e){report.errors.push(String(e.stack||e));console.error(e);if(page){report.last_state=await state().catch(()=>null);await page.screenshot({path:path.join(out,'failure.png')}).catch(()=>{});}process.exitCode=1;
}finally{save();if(browser)await browser.close();if(server)server.close();}})();
