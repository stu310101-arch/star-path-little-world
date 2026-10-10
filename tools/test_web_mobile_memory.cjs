const test = require('node:test');
const assert = require('node:assert/strict');
const {createBackgroundPacks} = require('./web_background_packs.js');
const {boundedTee} = require('./web_service_worker.js');
const turn = () => new Promise(resolve => setImmediate(resolve));
async function until(fn) {
  const end = performance.now() + 3000;
  while (!fn()) { if (performance.now() > end) throw Error('Timeout'); await turn(); }
}
test('mobile stream stops at its buffer budget and resumes in byte order', async t => {
  const data = Uint8Array.from({length:64},(_,i)=>i);
  let offset=0;
  const fetch = async()=>new Response(new ReadableStream({pull(c) {
    if(offset===data.length)c.close(); else {c.enqueue(data.slice(offset,offset+8));offset+=8;}
  }}));
  const api=createBackgroundPacks(fetch,128,1,16); t.after(()=>api.close());
  api.configure('https://example.com/game/');api.enqueue('a','packs/a.pck',64,0);
  await until(()=>api.status('a').received===16);
  for(let i=0;i<10;i++)await turn();
  assert.equal(api.status('a').received,16);
  let consumed=0;const output=[];
  while(consumed<64) {
    const part=api.read('a',consumed,8);
    if(part.length){output.push(...part);consumed+=part.length;api.consume('a',consumed);}
    else await turn();
  }
  await until(()=>api.status('a').state==='downloaded');
  assert.deepEqual(output,[...data]);assert.ok(api.snapshot().peak_buffered_bytes<=16);
});
test('cancelling a backpressured job frees its slot and starts the next job',async t=>{
  const api=createBackgroundPacks(async()=>new Response(new Uint8Array(32)),64,1,8);t.after(()=>api.close());
  api.configure('https://example.com/game/');api.enqueue('a','packs/a.pck',32,0);api.enqueue('b','packs/b.pck',32,0);
  await until(()=>api.status('a').received===32);
  api.release('a');await until(()=>api.status('b').state==='downloading' && api.status('b').received===32);
  assert.equal(api.snapshot().reserved_bytes,32);
});
test('cache fanout waits for the slow consumer instead of buffering the whole asset',async()=>{
  let count=0;
  const source=new ReadableStream({pull(c){if(count<20)c.enqueue(Uint8Array.of(count++));else c.close();}},{highWaterMark:0});
  const [a,b]=boundedTee(source);const game=a.getReader(),cache=b.getReader();
  const fast=cache.read();for(let i=0;i<5;i++)await turn();assert.equal(count,0);
  assert.equal((await game.read()).value[0],0);assert.equal((await fast).value[0],0);
  const second=cache.read();for(let i=0;i<5;i++)await turn();assert.equal(count,1);
  assert.equal((await game.read()).value[0],1);assert.equal((await second).value[0],1);
  await cache.cancel();const remaining=[];
  for(;;){const r=await game.read();if(r.done)break;remaining.push(r.value[0]);}
  assert.deepEqual(remaining,Array.from({length:18},(_,i)=>i+2));
});
test('network stream failures reach both cache and game readers',async()=>{
  const [a,b]=boundedTee(new ReadableStream({pull(c){c.error(new Error('disconnected'));}}));
  const results=await Promise.allSettled([a.getReader().read(),b.getReader().read()]);
  assert.ok(results.every(row=>row.status==='rejected'&&/disconnected/.test(row.reason.message)));
});

test('early cache quota rejection cannot stall the game behind an unread branch',async()=>{
  const branches=boundedTee(new Response(Uint8Array.of(1,2,3)).body);
  const game=branches[0].getReader();
  branches[1].getReader(); // Emulate the browser retaining its rejected body's lock.
  const pending=game.read();await turn();branches.stopStorage();
  assert.deepEqual([...(await pending).value],[1,2,3]);
  assert.equal((await game.read()).done,true);
});
