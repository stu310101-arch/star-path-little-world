// Localhost startup probe: identical viewport/browser and first-frame GL API timings.
// Browser HTTP cache only; no new persistent cache feature. GPU time is not measured.
const {chromium}=require('playwright');
const fs=require('node:fs'); const path=require('node:path');
const url=process.argv[2], label=process.argv[3];
if (!url || !label || !['localhost','127.0.0.1'].includes(new URL(url).hostname)) throw Error('localhost URL and label required');
const out=path.resolve('deliverables/startup-packs');fs.mkdirSync(out,{recursive:true});
const report={url,label,started:new Date().toISOString(),runs:[],errors:[]};
let browser;
const save=()=>fs.writeFileSync(path.join(out,`${label}.json`),JSON.stringify(report,null,2));
const watchdog=setTimeout(async()=>{report.errors.push('8 minute watchdog');save();if(browser)await browser.close().catch(()=>{});process.exit(1);},480000);
(async()=>{
 browser=await chromium.launch({channel:'chrome',headless:true});
 report.browser=browser.version(); report.viewport={width:1200,height:800};
 const context=await browser.newContext({viewport:report.viewport});
 const page=await context.newPage(); const cdp=await context.newCDPSession(page);
 await cdp.send('Network.enable'); let net=new Map();
 const heartbeat=setInterval(()=>{report.pendingNetwork=[...net.values()];save();},10000);heartbeat.unref();
 cdp.on('Network.requestWillBeSent',e=>{if(/\.(pck|wasm|js|html)(\?|$)/.test(e.request.url)||e.type==='Document') net.set(e.requestId,{url:e.request.url,start:e.timestamp});});
 cdp.on('Network.responseReceived',e=>{const n=net.get(e.requestId);if(n)Object.assign(n,{status:e.response.status,mimeType:e.response.mimeType,headers:e.response.headers,timing:e.response.timing,fromDiskCache:e.response.fromDiskCache,fromServiceWorker:e.response.fromServiceWorker,response:e.timestamp});});
 cdp.on('Network.requestServedFromCache',e=>{const n=net.get(e.requestId);if(n)n.servedFromCache=true;});
 cdp.on('Network.loadingFinished',e=>{const n=net.get(e.requestId);if(n)Object.assign(n,{end:e.timestamp,encodedDataLength:e.encodedDataLength});});
 cdp.on('Network.loadingFailed',e=>{const n=net.get(e.requestId);if(n)n.failed=e.errorText;});
 page.on('pageerror',e=>{report.errors.push(String(e));save();});
 page.on('console',m=>{if(m.type()==='error'){report.errors.push(m.text());save();}});
 page.on('crash',()=>{report.errors.push('Page renderer crashed');save();});
 await page.addInitScript(({collectShaders})=>{
  const d=window.__startupProbe={marks:{start:performance.now()},wasm:[],gl:{},longTasks:[],progress:[]};
  const mark=(name)=>d.marks[name]??=performance.now();
  const shaderSources=new WeakMap(),programs=new WeakMap();d.programs=[];
  for(const cls of (collectShaders ? [window.WebGLRenderingContext,window.WebGL2RenderingContext] : [])){
   if(!cls)continue;
   const source=cls.prototype.shaderSource,attach=cls.prototype.attachShader;
   cls.prototype.shaderSource=function(shader,code){shaderSources.set(shader,code);return source.call(this,shader,code);};
   cls.prototype.attachShader=function(program,shader){let row=programs.get(program);if(!row){row={index:d.programs.length,sources:[],query_ms:0};programs.set(program,row);d.programs.push(row);}row.sources.push(shaderSources.get(shader));return attach.call(this,program,shader);};
  }
  for(const name of ['compile','compileStreaming','instantiate','instantiateStreaming']){
   const original=WebAssembly[name];if(!original)continue;
   WebAssembly[name]=function(...args){const entry={name,start:performance.now()};d.wasm.push(entry);try{return Promise.resolve(original.apply(this,args)).then(v=>{entry.end=performance.now();return v;},e=>{entry.end=performance.now();entry.error=String(e);throw e;});}catch(e){entry.error=String(e);throw e;}};
  }
  // API wall-clock is not GPU execution time. Observe only through first rAF.
  for(const cls of [window.WebGLRenderingContext,window.WebGL2RenderingContext]){
   if(!cls)continue;
   for(const name of ['compileShader','linkProgram','getProgramParameter','getShaderParameter','bufferData','bufferSubData','texImage2D','texImage3D','compressedTexImage2D','compressedTexImage3D','texStorage2D','getUniformLocation','drawElements','drawArrays','finish']){
    const original=cls.prototype[name];if(!original)continue;
    cls.prototype[name]=function(...args){if(d.marks.firstRafAfterReady!==undefined)return original.apply(this,args);const begin=performance.now();try{return original.apply(this,args);}finally{const elapsed=performance.now()-begin;if(name==='getProgramParameter'){const row=programs.get(args[0]);if(row)row.query_ms+=elapsed;}const s=d.gl[name]??={count:0,total_ms:0,max_ms:0};s.count++;s.total_ms+=elapsed;if(elapsed>s.max_ms){s.max_ms=elapsed;s.max_start=begin;}mark('firstGLCall');}};
   }
  }
  addEventListener('planet-world-ready',()=>mark('worldReady'));
  function frame(){if(window.planetWorldReady)mark('firstRafAfterReady');requestAnimationFrame(frame);}requestAnimationFrame(frame);
  try{new PerformanceObserver(l=>{for(const e of l.getEntries())if(d.longTasks.length<200)d.longTasks.push({start:e.startTime,duration:e.duration});}).observe({type:'longtask',buffered:true});}catch{}
  addEventListener('DOMContentLoaded',()=>{mark('domContentLoaded');const progress=document.getElementById('status-progress');if(progress)new MutationObserver(()=>{const p={at:performance.now(),value:progress.value,max:progress.max};d.progress.push(p);if(p.max>0&&p.value>=p.max)mark('progressComplete');}).observe(progress,{attributes:true});new MutationObserver(()=>{if(!document.getElementById('status'))mark('overlayRemoved');}).observe(document.body,{childList:true,subtree:true});});
 }, {collectShaders:process.argv.includes('--shader-sources')});
 for(const cache of (process.argv.includes('--single') ? ['fresh-context'] : ['fresh-context','same-context-revisit'])){
  console.log('START',cache);net=new Map();
  await page.goto(url,{waitUntil:'domcontentloaded',timeout:90000});
  await page.waitForFunction(()=>window.__startupProbe?.marks.firstRafAfterReady!==undefined,null,{timeout:180000});
  await page.waitForTimeout(2000);
  const snapshot=await page.evaluate(()=>({probe:window.__startupProbe,buildId:document.querySelector('meta[name="little-world-build"]')?.content,resources:performance.getEntriesByType('resource').filter(e=>/index\.(pck|wasm|js)(\?|$)/.test(e.name)).map(e=>({url:e.name,start:e.startTime,end:e.responseEnd,duration:e.duration,transfer:e.transferSize,encoded:e.encodedBodySize,decoded:e.decodedBodySize})),gpu:(()=>{const g=document.createElement('canvas').getContext('webgl2');if(!g)return null;const e=g.getExtension('WEBGL_debug_renderer_info');return e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):g.getParameter(g.RENDERER);})(),metrics:window.planetPerformance}));
  report.runs.push({cache,...snapshot,network:[...net.values()]});save();console.log('DONE',cache,JSON.stringify(snapshot.probe.marks));
  if(cache==='fresh-context'){await page.screenshot({path:path.join(out,`${label}.png`),timeout:30000});await page.goto('about:blank');}
 }
 report.finished=new Date().toISOString();save();await browser.close();clearTimeout(watchdog);console.log('COMPLETE');
})().catch(async e=>{report.errors.push(String(e.stack));save();console.error(e);if(browser)await browser.close().catch(()=>{});clearTimeout(watchdog);process.exit(1);});
