// Exercise the real service worker lifecycle, without starting the game/GPU.
const {chromium}=require('playwright');
const fs=require('node:fs'),http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const worker=fs.readFileSync('tools/web_service_worker.js','utf8');
let revision=1,offline=false,badShell=false;
const pack='pack.0123456789abcdef.pck', bytes=Buffer.from('fixture pack');
const file=b=>({bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex')});
const report={checks:[]};
function check(name,ok){assert.ok(ok,name);report.checks.push(name);console.log('PASS',name);}
let server,browser;
(async()=>{
  server=http.createServer((req,res)=>{
    if(offline){res.destroy();return;}
    const html=Buffer.from('<!doctype html><title>fixture '+revision+'</title>');
    if(req.url==='/index.service-worker.js'){
      const config={build_id:'fixture'+revision,files:{'index.html':file(html),[pack]:file(bytes)},shell:['index.html']};
      res.writeHead(200,{'Content-Type':'application/javascript','Cache-Control':'no-store'}).end('const RELEASE='+JSON.stringify(config)+';\n'+worker);
    }else if(req.url==='/'+pack)res.end(bytes);
    else res.writeHead(200,{'Content-Type':'text/html'}).end(badShell?Buffer.from('incomplete deploy'):html);
  });
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const url='http://127.0.0.1:'+server.address().port;
  browser=await chromium.launch({channel:'chrome',headless:true});
  const context=await browser.newContext();let page=await context.newPage();
  await page.goto(url+'/index.html');
  await page.evaluate(async()=>{await navigator.serviceWorker.register('/index.service-worker.js');await navigator.serviceWorker.ready;});
  await page.waitForFunction(()=>navigator.serviceWorker.controller);
  check('Initial worker activates and controls its scope',true);
  check('Network pack reaches the caller',await page.evaluate(async p=>(await fetch(p)).text(),pack)==='fixture pack');
  await page.waitForFunction(async sha=>{const cache=await caches.open('little-world-%2F-fixture1');return Boolean(await cache.match(location.origin+'/__content/'+sha));},file(bytes).sha256);
  await page.evaluate(p=>navigator.serviceWorker.controller.postMessage({type:'little-world-invalidate',url:p}),pack);
  await page.waitForFunction(async sha=>{const cache=await caches.open('little-world-%2F-fixture1');return !await cache.match(location.origin+'/__content/'+sha);},file(bytes).sha256);
  check('Client validation failure removes the cached response',true);
  await page.evaluate(async p=>(await fetch(p)).arrayBuffer(),pack);
  await page.waitForFunction(async sha=>{const cache=await caches.open('little-world-%2F-fixture1');return Boolean(await cache.match(location.origin+'/__content/'+sha));},file(bytes).sha256);
  offline=true;
  check('Requested pack remains usable with network unavailable',await page.evaluate(async p=>(await fetch(p)).text(),pack)==='fixture pack');
  await page.reload();check('Verified shell reopens offline',await page.title()==='fixture 1');
  offline=false;revision=2;badShell=true;
  await page.evaluate(async()=>{const r=await navigator.serviceWorker.getRegistration();await r.update();});
  await page.waitForFunction(async()=>!(await navigator.serviceWorker.getRegistration()).installing);
  check('Incomplete new shell cannot replace the active release',await page.evaluate(async()=>!(await navigator.serviceWorker.getRegistration()).waiting));
  badShell=false;revision=3;
  await page.evaluate(async()=>{const r=await navigator.serviceWorker.getRegistration();await r.update();});
  await page.waitForFunction(async()=>Boolean((await navigator.serviceWorker.getRegistration()).waiting));
  check('Valid update waits while the current game tab remains open',await page.title()==='fixture 1');
  await page.close();page=await context.newPage();await page.goto(url+'/index.html');
  await page.waitForFunction(async()=>{const r=await navigator.serviceWorker.getRegistration();return !r.waiting&&(await caches.keys()).includes('little-world-%2F-fixture3');});
  check('After old clients close the new release activates',await page.title()==='fixture 3');
  check('Activation cleans old release caches',await page.evaluate(async()=>!(await caches.keys()).includes('little-world-%2F-fixture1')));
  report.passed=true;
})().catch(e=>{report.error=String(e.stack);console.error(e);process.exitCode=1;}).finally(async()=>{
  fs.mkdirSync('deliverables/mobile-web',{recursive:true});fs.writeFileSync('deliverables/mobile-web/cache-lifecycle.json',JSON.stringify(report,null,2));
  if(browser)await browser.close();if(server)server.close();
});
