/* Deterministic browser-API tests, no GPU/browser/engine run required. */
const test = require('node:test');
const assert = require('node:assert/strict');
const {gzipSync} = require('node:zlib');
const {createHash, webcrypto} = require('node:crypto');
const {install,attachStatusUI} = require('./web_boot_delivery.js');

const sha = b => createHash('sha256').update(b).digest('hex');
function fixture(options = {}) {
  const originals = {'index.pck': Buffer.from('GDPC boot '.repeat(1000)), 'index.wasm': Buffer.from('wasm engine '.repeat(1200))};
  const manifest = {version: 1, engine_version: '4.7.2', files: {}};
  const routes = new Map();
  for (const [name, bytes] of Object.entries(originals)) {
    const compressed = gzipSync(bytes);
    const url = `index.boot.${sha(compressed).slice(0,16)}.${name.split('.')[1]}.gz`;
    manifest.files[name] = {url, bytes: bytes.length, sha256: sha(bytes), compressed_bytes: compressed.length};
    routes.set(new URL(url, 'http://localhost/game/').href, compressed);
  }
  const calls = [], events = [];
  const env = {
    location: {href: 'http://localhost/game/'}, DecompressionStream, ReadableStream, Response,
    AbortController, crypto: webcrypto, performance, setTimeout, clearTimeout,
    CustomEvent: class {constructor(type, init) {this.type=type;this.detail=init.detail;}},
    dispatchEvent: event => events.push(event.type),
  };
  env.fetch = async (input, init) => {
    const url = new URL(typeof input === 'string' ? input : input.url, env.location.href);
    calls.push({url: url.href, init});
    if (routes.has(url.href)) {
      if (options.networkError) throw new Error('fixture connection interrupted');
      if (options.http404) return new Response('missing', {status:404});
      let body = Buffer.from(routes.get(url.href));
      if (options.truncated) body = body.subarray(0,body.length-6);
      if (options.corrupt) body[body.length-8] ^= 1; // CRC, not just a header byte.
      if (options.wrongContent) body = gzipSync(Buffer.from('different contents'));
      if (options.oversized) body = gzipSync(Buffer.alloc(manifest.files[url.pathname.endsWith('.wasm.gz')?'index.wasm':'index.pck'].bytes+1));
      if (options.delay) await new Promise(resolve => setTimeout(resolve, options.delay));
      if (options.bodyInterrupted) {
        return new Response(new ReadableStream({start(controller) {
          controller.enqueue(body.subarray(0,Math.floor(body.length/2)));
          setTimeout(()=>controller.error(new Error('fixture body interrupted')),2);
        }}));
      }
      return new Response(body);
    }
    const name = url.pathname.split('/').pop();
    return new Response(originals[name] || 'unrelated');
  };
  const originalFetch = env.fetch;
  const config = {fileSizes: Object.fromEntries(Object.entries(originals).map(([name,b])=>[name,b.length]))};
  return {env, config, manifest, originals, calls, events, originalFetch};
}

test('concurrent gzip PCK/WASM validate and restore fetch before body completion', async () => {
  const f = fixture({delay:5});
  assert.equal(install(f.config,f.manifest,f.env).enabled,true);
  const a = f.env.fetch('index.pck');
  const b = f.env.fetch('index.wasm');
  assert.equal(f.env.fetch,f.originalFetch);
  const result = await Promise.all([a,b]);
  for(let i=0;i<result.length;i++) {
    const name = ['index.pck','index.wasm'][i];
    assert.deepEqual(Buffer.from(await result[i].arrayBuffer()),f.originals[name]);
    assert.equal(f.env.planetBootDelivery.files[name].phase,'ready');
    assert.equal(result[i].headers.has('content-encoding'),false);
  }
  assert.equal(result[1].headers.get('content-type'),'application/wasm');
  assert.equal(f.calls.length,2);
  assert.ok(f.calls.every(c=>c.url.endsWith('.gz')));
});

test('unsupported decompressor or WebCrypto leaves original fetch untouched', () => {
  for(const feature of ['DecompressionStream','crypto']) {
    const f=fixture(); f.env[feature]=undefined;
    assert.equal(install(f.config,f.manifest,f.env).enabled,false);
    assert.equal(f.env.fetch,f.originalFetch);
    assert.equal(f.calls.length,0);
  }
});

for(const problem of ['http404','networkError','bodyInterrupted','truncated','corrupt','wrongContent','oversized']) {
  test(problem+' falls back to the exact original request', async () => {
    const f=fixture({[problem]:true});
    const adapter=install(f.config,f.manifest,f.env);
    const response=await f.env.fetch('index.pck');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()),f.originals['index.pck']);
    assert.equal(f.calls.length,2);
    assert.equal(f.calls[1].url,'http://localhost/game/index.pck');
    assert.equal(f.env.planetBootDelivery.files['index.pck'].phase,'fallback');
    assert.ok(f.env.planetBootDelivery.files['index.pck'].fallbackReason);
    adapter.restore();
    assert.equal(f.env.fetch,f.originalFetch);
  });
}

test('matching size with wrong SHA cannot reach Godot', async () => {
  const f=fixture(); f.manifest.files['index.pck'].sha256='0'.repeat(64);
  const adapter=install(f.config,f.manifest,f.env);
  await f.env.fetch('index.pck');
  assert.match(f.env.planetBootDelivery.files['index.pck'].fallbackReason,/hash differs/);
  assert.equal(f.calls.length,2);
  adapter.restore();
});

test('foreign origin, query, Request and option-bearing fetch remain untouched', async () => {
  const f=fixture();const adapter=install(f.config,f.manifest,f.env);
  await f.env.fetch('http://other.test/game/index.pck');
  await f.env.fetch('index.pck?v=other');
  await f.env.fetch(new Request('http://localhost/game/index.wasm'));
  await f.env.fetch('index.pck',{method:'POST'});
  await f.env.fetch('packs/avatar.pck');
  assert.equal(f.calls.length,5);
  assert.ok(f.calls.every(c=>!c.url.endsWith('.gz')));
  assert.equal(f.env.planetBootDelivery.files['index.pck'].phase,'waiting');
  adapter.restore();
});

test('invalid size, version or remote compressed URL disables optional delivery', () => {
  for(const mutate of [f=>f.manifest.files['index.pck'].bytes++, f=>f.manifest.version=2,
    f=>f.manifest.files['index.pck'].url='https://other.test/index.pck.gz']) {
    const f=fixture(); mutate(f);
    assert.equal(install(f.config,f.manifest,f.env).enabled,false);
    assert.equal(f.env.fetch,f.originalFetch);
  }
});

function uiFixture() {
  const element=()=>({style:{},children:[],textContent:'',isConnected:true,
    setAttribute(name,value){this[name]=value;},appendChild(child){this.children.push(child);}});
  const overlay=element(),progress={max:1,value:0},notice=element(),listeners=new Map();
  let tick,cleared=false;
  const env={
    planetBootDelivery:{enabled:true,files:{
      pck:{phase:'downloading',decodedBytes:10,expectedBytes:40},
      wasm:{phase:'downloading',decodedBytes:20,expectedBytes:60},
    }},
    document:{getElementById:id=>({'status':overlay,'status-progress':progress,'status-notice':notice}[id]),createElement:element},
    addEventListener:(name,callback)=>listeners.set(name,callback),
    removeEventListener:name=>listeners.delete(name),
    setInterval(callback,ms){assert.equal(ms,250);tick=callback;return 1;},
    clearInterval(id){assert.equal(id,1);cleared=true;},
  };
  const api=attachStatusUI(env);
  return {env,api,overlay,progress,notice,listeners,tick:()=>tick(),cleared:()=>cleared,
    phase:overlay.children[0].children[0],detail:overlay.children[0].children[1]};
}

test('boot UI labels decoded progress, verification and engine preparation then releases bar',()=>{
  const f=uiFixture();
  assert.equal(f.phase.textContent,'正在下載啟動檔…');
  assert.match(f.detail.textContent,/已解壓/);
  assert.equal(f.progress.max,100);assert.equal(f.progress.value,30);
  assert.equal(f.api.engineProgress(5,100),false);
  for(const row of Object.values(f.env.planetBootDelivery.files)) {row.phase='verifying';row.decodedBytes=row.expectedBytes;}
  f.tick();assert.equal(f.phase.textContent,'正在驗證啟動檔…');
  for(const row of Object.values(f.env.planetBootDelivery.files))row.phase='ready';
  f.tick();assert.equal(f.phase.textContent,'正在啟動引擎與準備畫面…');
  assert.equal(f.api.engineProgress(100,100),true);
  f.overlay.isConnected=false;f.tick();
  assert.equal(f.cleared(),true);assert.equal(f.listeners.size,0);
});

test('boot UI fallback and unsupported paths leave original engine progress in control',()=>{
  const f=uiFixture();
  f.env.planetBootDelivery.files.pck.phase='fallback';f.tick();
  f.progress.value=12;
  assert.equal(f.api.engineProgress(12,100),true);
  assert.equal(f.progress.value,12);
  assert.match(f.detail.textContent,/相容/);
  f.env.planetBootDelivery.enabled=false;
  assert.equal(f.api.engineProgress(100,100),true);
  assert.equal(f.phase.textContent,'正在啟動引擎與準備畫面…');
  f.api.dispose();assert.equal(f.cleared(),true);
});

test('boot UI stops when loader displays a real error',()=>{
  const f=uiFixture();f.notice.style.display='block';f.tick();
  assert.equal(f.overlay.children[0].style.display,'none');
  assert.equal(f.cleared(),true);
});
