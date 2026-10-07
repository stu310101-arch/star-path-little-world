/* Background transport contract: no browser, rendering, RAF or Godot needed. */
const test = require('node:test');
const assert = require('node:assert/strict');
const {createBackgroundPacks} = require('./web_background_packs.js');

const turn = () => new Promise(resolve => setImmediate(resolve));
async function until(check, message = 'condition') {
  const started = performance.now();
  while (!check()) {
    if (performance.now() - started > 2000) throw new Error('Timed out: ' + message);
    await turn();
  }
}
function responseChunks(values, options = {}) {
  let index = 0;
  const body = new ReadableStream({pull(controller) {
    if (index < values.length) {
      controller.enqueue(Uint8Array.from(values[index++]));
    } else if (options.error) controller.error(new Error('fixture interrupted body'));
    else controller.close();
  }});
  return new Response(body, {status:options.status || 200});
}
function fixture(t, limit = 128) {
  const routes = new Map(), calls = [], held = new Map();
  const fetch = async (url, options) => {
    const name = new URL(url).pathname.split('/').pop();
    calls.push({name, url, options});
    const route = routes.get(name);
    if (route === 'hold') {
      let control;
      const stream = new ReadableStream({start(controller) {control=controller;}});
      const hold = {push(bytes) {control.enqueue(Uint8Array.from(bytes));}, finish() {control.close();}};
      held.set(name,hold);
      options.signal.addEventListener('abort', () => control.error(new DOMException('aborted','AbortError')), {once:true});
      return new Response(stream);
    }
    return typeof route === 'function' ? route() : responseChunks(route || [[1,2,3,4]]);
  };
  const api=createBackgroundPacks(fetch,limit);
  api.configure('http://localhost/game/');
  t.after(()=>api.close());
  return {api,routes,calls,held};
}

function readRange(api,id,offset,count) {
  const bytes=[];
  while(bytes.length<count){const part=api.read(id,offset+bytes.length,count-bytes.length);if(!part.length)break;bytes.push(...part);}
  return bytes;
}

test('network drains every chunk to EOF without RAF or game-frame polling', async t => {
  const f=fixture(t);
  f.routes.set('all.pck',[[1,2],[3],[4,5],[6,7,8]]);
  const previous=globalThis.requestAnimationFrame;
  globalThis.requestAnimationFrame=()=>{throw new Error('RAF must not be needed');};
  try {
    f.api.enqueue('all','packs/all.pck',8,0);
    await until(()=>f.api.status('all').state==='downloaded');
    assert.equal(f.api.status('all').received,8);
    assert.deepEqual(readRange(f.api,'all',2,3),[3,4,5]);
    assert.equal(f.api.read('all',20,2).length,0);
    assert.equal(f.calls.length,1);
    assert.equal(f.api.snapshot().buffered_bytes,8);
    f.api.release('all');
    assert.equal(f.api.snapshot().buffered_bytes,0);
  } finally {
    if(previous===undefined)delete globalThis.requestAnimationFrame;
    else globalThis.requestAnimationFrame=previous;
  }
});

test('queued priorities can rise without duplicate requests or active preemption', async t => {
  const f=fixture(t);
  f.routes.set('hold.pck','hold');
  f.api.enqueue('hold','packs/hold.pck',4,0);
  f.api.enqueue('low','packs/low.pck',4,1);
  f.api.enqueue('medium','packs/medium.pck',4,2);
  f.api.enqueue('high','packs/high.pck',4,9);
  f.api.enqueue('low','packs/low.pck',4,20);
  f.api.enqueue('hold','packs/hold.pck',4,30);
  assert.deepEqual(f.calls.map(c=>c.name),['hold.pck']);
  f.held.get('hold.pck').push([1,2,3,4]);f.held.get('hold.pck').finish();
  await until(()=>f.api.status('medium').state==='downloaded');
  assert.deepEqual(f.calls.map(c=>c.name),['hold.pck','low.pck','high.pck','medium.pck']);
  f.api.enqueue('low','packs/low.pck',4,100);
  assert.equal(f.calls.length,4);
  assert.throws(()=>f.api.enqueue('low','packs/other.pck',4,0),/identity changed/);
  assert.throws(()=>f.api.enqueue('low','packs/low.pck',5,0),/identity changed/);
});

test('memory reservations bound buffering and resume once consumer releases data', async t => {
  const f=fixture(t,8);
  f.routes.set('a.pck',[[1,2,3,4,5,6]]);f.routes.set('b.pck',[[1,2,3,4,5,6]]);
  f.routes.set('c.pck',[[7,8]]);
  f.api.enqueue('a','packs/a.pck',6,1);
  f.api.enqueue('b','packs/b.pck',6,2);
  f.api.enqueue('c','packs/c.pck',2,1);
  await until(()=>f.api.status('a').state==='downloaded');
  await turn();
  assert.equal(f.api.status('b').state,'queued');
  assert.equal(f.calls.length,1);
  assert.equal(f.api.snapshot().buffered_bytes,6);
  f.api.release('a');
  await until(()=>f.api.status('c').state==='downloaded');
  assert.deepEqual(f.calls.map(c=>c.name),['a.pck','b.pck','c.pck']);
  assert.equal(f.api.snapshot().buffered_bytes,8);
  assert.equal(f.api.snapshot().peak_buffered_bytes,8);
  assert.throws(()=>f.api.enqueue('huge','packs/huge.pck',9,0),/budget/);
  f.api.release('b');f.api.release('c');
  assert.equal(f.api.snapshot().buffered_bytes,0);
});

const failures = {
  'HTTP 404':()=>new Response('missing',{status:404}),
  'HTTP 503':()=>new Response('try later',{status:503}),
  'truncated EOF':()=>responseChunks([[1,2]]),
  'oversized body':()=>responseChunks([[1,2,3,4,5]]),
  'interrupted body':()=>responseChunks([[1,2]],{error:true}),
  'network error':()=>{throw new Error('fixture fetch failed');},
  'missing body':()=>new Response(null),
  'cross-origin redirect':()=>{const r=responseChunks([[1,2,3,4]]);Object.defineProperty(r,'url',{value:'https://other.test/file'});return r;},
};
for(const [name,route] of Object.entries(failures)) {
  test(name+' records failure, frees buffer, and supports explicit release/retry',async t=>{
    const f=fixture(t);
    f.routes.set('broken.pck',route);
    f.api.enqueue('job','packs/broken.pck',4,0);
    await until(()=>f.api.status('job').state==='failed',name);
    assert.ok(f.api.status('job').error);
    assert.equal(f.api.snapshot().buffered_bytes,0);
    f.api.enqueue('job','packs/broken.pck',4,5);
    await turn();assert.equal(f.calls.length,1); // enqueue alone is not retry.
    f.api.release('job');
    f.routes.set('broken.pck',[[1,2],[3,4]]);
    f.api.enqueue('job','packs/broken.pck',4,5);
    await until(()=>f.api.status('job').state==='downloaded','retry');
    assert.equal(f.calls.length,2);
    assert.deepEqual(readRange(f.api,'job',0,10),[1,2,3,4]);
  });
}

test('failed earlier job cannot prevent remaining queued downloads',async t=>{
  const f=fixture(t);
  f.routes.set('fail.pck',()=>new Response('bad',{status:503}));
  f.api.enqueue('bad','packs/fail.pck',4,1);
  f.api.enqueue('good','packs/good.pck',4,1);
  await until(()=>f.api.status('good').state==='downloaded');
  assert.equal(f.api.status('bad').state,'failed');
  assert.equal(f.api.snapshot().buffered_bytes,4);
});

test('releasing active download aborts it and advances queue without stale writes',async t=>{
  const f=fixture(t);
  f.routes.set('old.pck','hold');
  f.api.enqueue('old','packs/old.pck',4,1);
  f.api.enqueue('next','packs/next.pck',4,1);
  await until(()=>f.held.has('old.pck'));
  f.held.get('old.pck').push([1,2]);
  await until(()=>f.api.status('old').received===2);
  f.api.release('old');
  await until(()=>f.api.status('next').state==='downloaded');
  assert.equal(f.api.status('old').state,'missing');
  assert.ok(f.calls[0].options.signal.aborted);
  assert.equal(f.api.snapshot().buffered_bytes,4);
});

test('close aborts active job, releases all buffers and never starts queued work',async t=>{
  const f=fixture(t);
  f.routes.set('active.pck','hold');
  f.api.enqueue('active','packs/active.pck',4,1);
  f.api.enqueue('queued','packs/queued.pck',4,1);
  await until(()=>f.held.has('active.pck'));
  f.api.close();
  await until(()=>f.api.snapshot().active==='');
  assert.equal(f.calls.length,1);
  assert.ok(f.calls[0].options.signal.aborted);
  assert.equal(f.api.snapshot().buffered_bytes,0);
  assert.equal(f.api.snapshot().jobs.length,0);
  f.api.close(); // idempotent cleanup.
});

test('URL and numeric bounds fail before network or allocation',t=>{
  const f=fixture(t,8);
  for(const path of ['https://other.test/game/a.pck','../a.pck','packs/a.pck?v=1','packs/a.pck#fragment']) {
    assert.throws(()=>f.api.enqueue('x',path,4,0),/URL/);
  }
  for(const bytes of [0,-1,1.1,NaN,9])assert.throws(()=>f.api.enqueue('x','packs/a.pck',bytes,0),/budget/);
  assert.equal(f.calls.length,0);
  assert.equal(f.api.snapshot().buffered_bytes,0);
  assert.equal(f.api.read('missing',0,4).length,0);
});

test('acknowledged segments release incrementally before full download or mounting',async t=>{
  const f=fixture(t,12);f.routes.set('stream.pck','hold');
  f.api.enqueue('s','packs/stream.pck',12,1);
  f.held.get('stream.pck').push([1,2,3,4]);
  await until(()=>f.api.status('s').received===4);
  assert.deepEqual(readRange(f.api,'s',0,4),[1,2,3,4]);
  f.api.consume('s',4);
  assert.equal(f.api.snapshot().buffered_bytes,0);
  assert.equal(f.api.status('s').state,'downloading');
  assert.equal(f.api.read('s',0,4).length,0);
  assert.throws(()=>f.api.consume('s',5),/offset/);
  f.held.get('stream.pck').push([5,6,7,8]);f.held.get('stream.pck').push([9,10,11,12]);f.held.get('stream.pck').finish();
  await until(()=>f.api.status('s').state==='downloaded');
  assert.deepEqual(readRange(f.api,'s',4,8),[5,6,7,8,9,10,11,12]);
  f.api.consume('s',12);assert.equal(f.api.snapshot().buffered_bytes,0);
  assert.equal(f.api.status('s').received,12);
  f.api.release('s');assert.equal(f.api.snapshot().reserved_bytes,0);
});
