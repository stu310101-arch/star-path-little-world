// Mobile Chromium emulation checks functionality, delivery and cache behavior;
// it is explicitly not a real iPhone Safari/GPU/thermal benchmark.
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const root=path.resolve('_site'),out=path.resolve('deliverables/mobile-web');fs.mkdirSync(out,{recursive:true});
const report={checks:[],errors:[],requests:[],console:[],scope:'Chromium mobile input emulation; not real Safari hardware'};
let browser,page,server,failDistrict=true,offline=false;
const check=(name,value)=>{assert.ok(value,name);report.checks.push(name);console.log('PASS',name);};
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const state=()=>page.evaluate(()=>window.planetPerformance);
async function button(expression){
  await page.waitForFunction(source=>window.planetPerformance?.buttons?.some(b=>b.visible&&new RegExp(source).test(b.text)),expression.source,{timeout:20000});
  const b=(await state()).buttons.find(b=>b.visible&&expression.test(b.text));
  const canvas=await page.locator('#canvas').boundingBox(),scale=Math.min(canvas.width/1440,canvas.height/900);
  await page.touchscreen.tap(canvas.x+(canvas.width-1440*scale)/2+b.center[0]*1440*scale,canvas.y+(canvas.height-900*scale)/2+b.center[1]*900*scale);
  await pause(1200);
}
async function playable(){await page.waitForFunction(()=>{const s=window.planetPerformance;return s?.avatar?.ready&&!s.preparing_roam&&!s.player.overview&&!s.player.paused&&!s.player.entering;},null,{timeout:180000});}
(async()=>{
  server=http.createServer((req,res)=>{
    const url=new URL(req.url,'http://localhost');let name=decodeURIComponent(url.pathname);if(name.endsWith('/'))name+='index.html';
    const file=path.resolve(root,'.'+name);
    if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
    const row={path:name,at:Date.now(),status:200,bytes:0};report.requests.push(row);
    if(offline){row.status=0;res.destroy();return;}
    if(failDistrict&&name.includes('district_counseling')&&name.endsWith('.pck')){row.status=503;res.writeHead(503).end('intentional fixture outage');return;}
    if(!fs.existsSync(file)){row.status=404;res.writeHead(404).end();return;}
    row.bytes=fs.statSync(file).size;
    const type=name.endsWith('.js')?'application/javascript':name.endsWith('.html')?'text/html':name.endsWith('.wasm')?'application/wasm':name.endsWith('.json')?'application/json':'application/octet-stream';
    res.writeHead(200,{'Content-Type':type,'Content-Length':row.bytes,'Cache-Control':'no-store'});fs.createReadStream(file).pipe(res);
  });
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const base='http://127.0.0.1:'+server.address().port+'/';report.url=base;
  browser=await chromium.launch({channel:'chrome',headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  const context=await browser.newContext({viewport:{width:844,height:390},deviceScaleFactor:1,isMobile:true,hasTouch:true,userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'});
  page=await context.newPage();page.on('pageerror',e=>report.errors.push(String(e)));
  page.on('console',m=>{if(['warning','error'].includes(m.type()))report.console.push(m.text());if(/SCRIPT ERROR|Parse Error|SHADER ERROR|RuntimeError|unreachable/.test(m.text()))report.errors.push(m.text());});
  await page.goto(base+'?performance',{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>window.planetWorldReady&&window.planetPerformance?.packs?.all_ready,null,{timeout:240000});
  check('Phone selects the separate mobile texture export',new URL(page.url()).pathname==='/mobile/index.html');
  check('Mobile redirect never downloads desktop WASM or packs',!report.requests.some(r=>/^\/(index\.boot\.|packs\/)/.test(r.path)));
  check('Mobile uses one stream and a 2 MiB high-water limit',(await state()).packs.background.concurrency===1&&(await state()).packs.background.stream_high_water_bytes===2097152);
  check('Far districts, interior and full fallback font stay deferred',!report.requests.some(r=>/district_life|training_room-|font_fallback-/.test(r.path)));
  await button(/開始漫遊/);
  await page.waitForFunction(()=>window.planetPerformance?.packs?.errors?.district_counseling,null,{timeout:120000});
  check('Missing initial district holds entry safely',(await state()).preparing_roam&&(await state()).player.overview);
  failDistrict=false;await button(/重新下載/);await playable();
  check('Retry mounts the initial district and restores play',true);
  report.first_play_requests=report.requests.slice();report.first_play_loaded=await state();
  const before=(await state()).player.position;
  const stick=await page.locator('.lw-stick').boundingBox();const cdp=await context.newCDPSession(page);
  const point={x:stick.x+stick.width/2,y:stick.y+stick.height/2,id:1};
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point]});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{...point,y:point.y-43}]});
  await pause(2500);await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await pause(1200);
  const after=(await state()).player.position;report.walk_distance=Math.hypot(...after.map((x,i)=>x-before[i]));
  check('Real touch joystick walks on the existing terrain',report.walk_distance>1&&Math.hypot(...after)>=47);
  const released=(await state()).player.position;await pause(1400);const still=(await state()).player.position;
  check('Releasing touch stops movement',Math.hypot(...still.map((x,i)=>x-released[i]))<.15);
  const heading=(await state()).player.heading;const look=await page.locator('.lw-look').boundingBox();
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:look.x+30,y:look.y+30,id:2}]});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:look.x+100,y:look.y+40,id:2}]});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await pause(1200);
  check('Real touch drag rotates the camera/player heading',Math.hypot(...(await state()).player.heading.map((x,i)=>x-heading[i]))>.05);
  const jumpBefore=(await state()).player;
  await page.locator('[data-action="jump"]').tap();await pause(3500);
  const jumpAfter=(await state()).player;
  check('Touch jump launches once and lands',jumpAfter.jump_count===jumpBefore.jump_count+1&&jumpAfter.landing_count===jumpBefore.landing_count+1&&Math.hypot(...jumpAfter.position)>=47);
  await button(/畫面設定/);await button(/^手機省電$/);
  check('540p option applies without changing selected frame cap',(await state()).graphics.quality_profile==='mobile'&&(await state()).graphics.internal_3d_pixels[1]<=540&&(await state()).graphics.frame_limit===60);
  await button(/^完成$/);
  report.first_play_state=await state();
  const transport=report.first_play_state.packs.background;
  check('Mobile transport stays within high-water plus one browser chunk',transport.peak_buffered_bytes<=2097152+transport.max_chunk_bytes);
  await page.screenshot({path:path.join(out,'mobile-play.png')});
  check('Service worker controls the game',await page.evaluate(()=>Boolean(navigator.serviceWorker.controller)));
  await pause(2000);
  const beforeOffline=report.requests.length;offline=true;await context.setOffline(true);
  await page.reload({waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>window.planetWorldReady&&window.planetPerformance?.packs?.all_ready,null,{timeout:180000});
  await button(/開始漫遊/);await playable();
  check('Previously played starting area reopens offline',!report.requests.slice(beforeOffline).some(r=>r.status===200));
  check('Phone graphics preference survives reload',(await state()).graphics.quality_profile==='mobile');
  check('No engine script, shader, texture or browser exceptions',report.errors.length===0&&!report.console.some(x=>/INVALID_ENUM|INVALID_OPERATION/.test(x)));
  report.passed=true;
})().catch(async e=>{report.errors.push(String(e.stack||e));console.error(e);if(page){report.last_state=await state().catch(()=>null);await page.screenshot({path:path.join(out,'mobile-failure.png')}).catch(()=>{});}process.exitCode=1;}).finally(async()=>{
  fs.writeFileSync(path.join(out,'mobile-functional.json'),JSON.stringify(report,null,2));
  if(browser)await browser.close();if(server)server.close();
});
