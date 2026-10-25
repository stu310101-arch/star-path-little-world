// Real exported Godot/CacheStorage/ordinary input. The account endpoint is a
// local protocol fixture; this does not authenticate a production account.
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const root=path.resolve(process.argv[2]||'_site'),out=path.resolve('deliverables/resource-packs/browser');fs.mkdirSync(out,{recursive:true});
const report={checks:[],errors:[],requests:[],scope:'Local exported Web game, real CacheStorage and inputs; account-host protocol fixture, mobile Chromium emulation (not physical iOS installation).'};
let server,browser,page;
const save=()=>fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
const check=(name,value)=>{report.checks.push({name,passed:!!value});save();assert.ok(value,name);console.log('PASS',name);};
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const host=`<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><button id="login">登入測試帳號</button><script>
const channel='starpath-account';let generation=Date.now();
function send(type,extra={}){parent.postMessage({channel,version:1,type,...extra},location.origin);}
function auth(){send('auth-state',{resolving:false,sessionGeneration:++generation,user:localStorage.getItem('qa-auth')==='yes'?{signedIn:true,profileReady:true,identity:'university',displayName:'測試使用者',sessionGeneration:generation}:null});}
document.querySelector('#login').onclick=()=>{localStorage.setItem('qa-auth','yes');auth();};
addEventListener('message',event=>{if(event.origin!==location.origin||event.source!==parent)return;if(event.data.type==='sign-out'){localStorage.removeItem('qa-auth');auth();}});
send('ready');auth();</script></html>`;
async function click(name,manager=false){
  const state=manager?'resourcePackState':'planetPerformance';
  await page.waitForFunction(({state,name})=>window[state]?.buttons?.some(b=>b.name===name&&!b.disabled&&b.visible!==false),{state,name},{timeout:30000});
  const button=await page.evaluate(({state,name})=>window[state].buttons.find(b=>b.name===name),{state,name});
  const canvas=await page.locator('#canvas').boundingBox();
  await page.mouse.click(canvas.x+button.center[0]*canvas.width,canvas.y+button.center[1]*canvas.height);
  await pause(450);
}
async function world(){await page.waitForFunction(()=>window.planetWorldReady&&window.planetPerformance?.packs?.all_ready,null,{timeout:240000});}
async function openManager(){
  await click('GraphicsSettingsButton');
  await page.waitForFunction(()=>window.planetPerformance?.buttons?.some(b=>b.text.includes('切換材質包')&&b.visible),null,{timeout:30000});
  const button=await page.evaluate(()=>window.planetPerformance.buttons.find(b=>b.text.includes('切換材質包')&&b.visible));
  const canvas=await page.locator('#canvas').boundingBox();
  await page.mouse.click(canvas.x+button.center[0]*canvas.width,canvas.y+button.center[1]*canvas.height);
}
async function store(action,profile){return page.evaluate(async({action,profile})=>{const s=window.LittleWorldResourceStore;s.run(action,profile);while(s.busy)await new Promise(r=>setTimeout(r,20));return {ok:s.ok,installed:s.installed,error:s.error};},{action,profile});}
(async()=>{try{
  server=http.createServer((req,res)=>{
    const url=new URL(req.url,'http://localhost');let name=decodeURIComponent(url.pathname);if(name.endsWith('/'))name+='index.html';
    const row={name,at:Date.now()};report.requests.push(row);
    if(name.startsWith('/admissions/host/')){res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'}).end(host);return;}
    const file=path.resolve(root,'.'+name);if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){res.writeHead(404).end();return;}
    const type=name.endsWith('.html')?'text/html':name.endsWith('.js')?'application/javascript':name.endsWith('.wasm')?'application/wasm':name.endsWith('.json')?'application/json':name.endsWith('.webmanifest')?'application/manifest+json':name.endsWith('.png')?'image/png':'application/octet-stream';
    res.writeHead(200,{'Content-Type':type,'Content-Length':fs.statSync(file).size,'Cache-Control':'no-store'});fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base='http://127.0.0.1:'+server.address().port+'/';report.base=base;
  browser=await chromium.launch({channel:'chrome',headless:true});
  const context=await browser.newContext({viewport:{width:1280,height:800}});page=await context.newPage();
  page.on('pageerror',error=>{report.errors.push(String(error));save();});
  page.on('console',message=>{if(/SCRIPT ERROR|Parse Error|SHADER ERROR|RuntimeError|^ERROR:/.test(message.text())){report.errors.push(message.text());save();}});
  await page.goto(base+'?performance');await page.locator('#resource-choice').waitFor();await pause(1200);
  check('first visit waits for resource choice before WASM/boot downloads',!report.requests.some(r=>r.name.includes('.boot.')||r.name.endsWith('.wasm')));
  await page.screenshot({path:path.join(out,'first-choice.png')});
  await page.locator('[data-pack=low]').click();
  await page.waitForFunction(()=>window.resourcePackState?.profile==='low'&&window.resourcePackState?.buttons?.length===0,null,{timeout:240000});
  await page.frameLocator('.lw-account iframe').locator('#login').click();await world();
  check('low profile reaches the playable world',await page.evaluate(()=>window.LittleWorldResourceProfile==='low'&&window.planetPerformance.streaming.constrained_runtime));
  const firstStore=await store('status','low');check('low resource files really exist in CacheStorage',firstStore.installed.low);
  const manifest=JSON.parse(fs.readFileSync(path.join(root,'index.packs.json'),'utf8'));
  const fullOnly=new Set(manifest.profiles.full.filter(k=>!manifest.profiles.low.includes(k)).flatMap(k=>[manifest.packs[k].url]));
  check('low startup never requests full-only raw PCK files',!report.requests.some(r=>fullOnly.has(r.name.slice(1))));
  await page.screenshot({path:path.join(out,'low-world.png')});
  await page.reload();await world();
  check('saved account resumes without reopening login modal',await page.locator('.lw-account').evaluate(node=>node.hidden));
  check('saved pack selection skips the first-visit chooser',await page.locator('#resource-choice').count()===0);
  await openManager();
  await click('ManageResources_full',true);
  await page.waitForURL(url=>url.searchParams.get('pack')==='full',{timeout:240000});await world();
  check('download and switch to full succeeds',await page.evaluate(()=>window.LittleWorldResourceProfile==='full'));
  const both=await store('status','full');check('keeping the old pack retains both actual caches',both.installed.full&&both.installed.low);
  await openManager();
  await click('KeepPreviousResourcePack',true);await click('ManageResources_low',true);
  await page.waitForURL(url=>url.searchParams.get('pack')==='low',{timeout:240000});await world();
  const lowOnly=await store('status','low');check('switch back can delete full while preserving low and shared files',lowOnly.installed.low&&!lowOnly.installed.full);
  await page.screenshot({path:path.join(out,'low-switched-back.png')});
  await click('GraphicsSettingsButton');
  await page.waitForFunction(()=>window.planetPerformance?.buttons?.some(b=>b.name==='SettingsSignOut'),null,{timeout:30000});
  check('settings retains logout and account-switch actions',await page.evaluate(()=>['SettingsSignOut','SettingsSwitchAccount'].every(name=>window.planetPerformance.buttons.some(b=>b.name===name))));
  await click('SettingsSignOut');await page.waitForFunction(()=>localStorage.getItem('qa-auth')===null);
  check('explicit logout clears the restored account',await page.evaluate(()=>JSON.parse(window.LittleWorldAccountBridge.stateJSON()).user===null));
  check('no script, shader or browser runtime errors',report.errors.length===0);
  await context.close();
  const mobile=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1'});
  page=await mobile.newPage();await page.goto(base+'?performance');await page.locator('#resource-choice').waitFor();
  const manifestURL=await page.locator('link[rel=manifest]').getAttribute('href');const app=await(await page.request.get(new URL(manifestURL,page.url()).href)).json();
  check('mobile PWA manifest has standalone launch and proper icon sizes',app.display==='standalone'&&app.icons.some(i=>i.sizes==='192x192')&&app.icons.some(i=>i.sizes==='512x512'));
  check('mobile exposes Add to Home Screen guidance',await page.locator('#pwa-install').isVisible());
  await page.screenshot({path:path.join(out,'mobile-first-choice.png')});
  await page.locator('[data-pack=low]').click();
  await page.waitForFunction(()=>window.resourcePackState?.profile==='low'&&window.resourcePackState?.buttons?.length===0,null,{timeout:240000});
  await page.frameLocator('.lw-account iframe').locator('#login').click();await world();
  check('mobile exported low pack also enters the world',await page.evaluate(()=>window.LittleWorldResourceProfile==='low'&&window.planetPerformance.streaming.constrained_runtime));
  await page.screenshot({path:path.join(out,'mobile-low-world.png')});
  await click('CompactMenuButton');await openManager();
  await page.waitForFunction(()=>window.resourcePackState?.buttons?.some(b=>b.name==='ManageResources_full'),null,{timeout:30000});
  check('mobile resource manager keeps switch and return controls on screen',await page.evaluate(()=>['ManageResources_full','CloseResourceManager'].every(name=>{const b=window.resourcePackState.buttons.find(b=>b.name===name);return b&&b.center.every(v=>v>0&&v<1);})));
  await page.screenshot({path:path.join(out,'mobile-resource-settings.png')});
  report.passed=true;save();console.log('RESOURCE_BROWSER_QA_PASSED');
}catch(error){report.failure=String(error);save();await page?.screenshot({path:path.join(out,'failure.png')}).catch(()=>{});console.error(error);process.exitCode=1;}finally{await browser?.close();server?.close();}})();
