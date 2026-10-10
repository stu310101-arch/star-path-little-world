// Read-only public deployment smoke. Inputs enter the existing game normally.
const {chromium}=require('playwright');
const fs=require('node:fs'),assert=require('node:assert/strict');
const base=process.argv[2],expected=JSON.parse(fs.readFileSync(process.argv[3]||'_site/index.release.json','utf8'));
if(!base||!/^https?:/.test(base))throw Error('Pass a game URL and expected release manifest');
const report={url:base,build_id:expected.build_id,variants:[],errors:[]};
const delay=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
  for(const mobile of [false,true]){
    const row={variant:mobile?'mobile ETC2 (SwiftShader emulation)':'desktop',errors:[]};report.variants.push(row);
    const browser=await chromium.launch({channel:'chrome',headless:true,args:mobile?['--use-angle=swiftshader','--enable-unsafe-swiftshader']:[]});
    try{
      const context=await browser.newContext({viewport:mobile?{width:844,height:390}:{width:1200,height:800},hasTouch:mobile,isMobile:mobile,
        ...(mobile?{userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1'}:{})});
      const page=await context.newPage();
      page.on('pageerror',e=>row.errors.push(String(e)));
      page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|SHADER ERROR|INVALID_ENUM|INVALID_OPERATION|RuntimeError|unreachable/.test(m.text()))row.errors.push(m.text());});
      await page.goto(new URL('?performance',base).href,{waitUntil:'domcontentloaded'});
      await page.waitForFunction(()=>window.planetWorldReady&&window.planetPerformance?.packs?.all_ready,null,{timeout:300000});
      assert.equal(await page.locator('meta[name="little-world-build"]').getAttribute('content'),expected.build_id);
      assert.equal(new URL(page.url()).pathname.includes('/mobile/'),mobile);
      const live=await (await page.request.get(new URL('index.release.json',base).href)).json();
      assert.equal(live.build_id,expected.build_id);assert.deepEqual(live.files,expected.files);
      await delay(2200);
      const b=await page.evaluate(()=>window.planetPerformance.buttons.find(b=>b.visible&&/開始漫遊/.test(b.text)));
      assert.ok(b,'Start button is visible');
      const box=await page.locator('#canvas').boundingBox(),scale=Math.min(box.width/1440,box.height/900);
      const x=box.x+(box.width-1440*scale)/2+b.center[0]*1440*scale,y=box.y+(box.height-900*scale)/2+b.center[1]*900*scale;
      if(mobile)await page.touchscreen.tap(x,y);else await page.mouse.click(x,y);
      await page.waitForFunction(()=>{const s=window.planetPerformance;return s.avatar.ready&&!s.preparing_roam&&!s.player.overview&&!s.player.entering&&!s.player.paused;},null,{timeout:180000});
      const before=await page.evaluate(()=>window.planetPerformance.player.position);
      if(mobile){
        const box=await page.locator('.lw-stick').boundingBox(),cdp=await context.newCDPSession(page);
        const p={x:box.x+box.width/2,y:box.y+box.height/2,id:1};
        await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[p]});
        await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{...p,y:p.y-40}]});
        await delay(2500);await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
      }else{await page.keyboard.down('w');await delay(2500);await page.keyboard.up('w');}
      await delay(1500);
      const state=await page.evaluate(()=>window.planetPerformance);
      row.movement=Math.hypot(...state.player.position.map((n,i)=>n-before[i]));
      assert.ok(row.movement>1,'Published game accepts actual movement input');
      assert.deepEqual(row.errors,[]);row.cache_controlled=await page.evaluate(()=>Boolean(navigator.serviceWorker.controller));
      row.passed=true;console.log('PASS',row.variant,row.movement);
    }finally{await browser.close();}
  }
  report.passed=true;
})().catch(e=>{report.errors.push(String(e.stack));console.error(e);process.exitCode=1;}).finally(()=>{
  fs.mkdirSync('deliverables/mobile-web',{recursive:true});fs.writeFileSync('deliverables/mobile-web/published-smoke.json',JSON.stringify(report,null,2));
});
