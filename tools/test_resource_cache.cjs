const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function fixture(optional=false){
  const handlers={},data=new Map(),scope='https://example.com/game/';
  const names={common:'packs/common-0000000000000000.pck',low:'packs/low-1111111111111111.pck',full:'packs/full-2222222222222222.pck',extra:'packs/extra-3333333333333333.pck',room:'packs/room-4444444444444444.pck',room_dep:'packs/room_dep-5555555555555555.pck'};
  const requests=[],failures=new Set();
  const files=Object.fromEntries(Object.entries(names).map(([key,name],i)=>[name,{bytes:80*1024*1024,sha256:key}]));
  const cache={async keys(){return [...data.keys()].map(url=>({url}));},async match(key){const row=data.get(typeof key==='string'?key:key.url);return row?new Response(row.body,{headers:row.headers}):undefined;},async put(key,response){data.set(typeof key==='string'?key:key.url,{body:await response.arrayBuffer(),headers:response.headers});},async delete(key){return data.delete(typeof key==='string'?key:key.url);}};
  const context={URL,Response,ReadableStream,Uint8Array,Set,Map,Promise,JSON,encodeURIComponent,decodeURIComponent,
    RELEASE:{build_id:'test',files,shell:[],profiles:{desktop:{low:[names.common,names.low],full:[names.common,names.full,...(optional?[names.room_dep]:[])]}},shared_on_demand:optional?{desktop:[names.room,names.room_dep]}:{}},
    self:{registration:{scope},clients:{claim:async()=>{}},addEventListener:(type,handler)=>{handlers[type]=handler;}},
    caches:{open:async()=>cache,keys:async()=>[],delete:async()=>true},fetch:async request=>{const url=typeof request==='string'?request:request.url;requests.push(url);return new Response('asset',{status:failures.has(url)?503:200});}};
  vm.runInNewContext(fs.readFileSync(__dirname+'/web_service_worker.js','utf8'),context);
  const key=name=>scope+'__content/'+files[names[name]].sha256;
  const fetchAsset=async name=>{const waits=[];let response;handlers.fetch({request:{method:'GET',url:scope+names[name],cache:'default'},respondWith:job=>{response=job;},waitUntil:job=>waits.push(job)});const result=await response;await result.arrayBuffer();await Promise.all(waits);return result.status;};
  return {data,key,requests,fetchAsset,fail(name){failures.add(scope+names[name]);},async add(name){await cache.put(key(name),new Response('asset'));},
    async install(){await new Promise(resolve=>handlers.install({waitUntil:job=>job.then(resolve)}));},
    async manage(action,profile){let response;await new Promise(resolve=>handlers.message({data:{type:'little-world-profile',action,profile,renderer:'desktop'},ports:[{postMessage:value=>{response=value;}}],waitUntil:job=>job.then(resolve)}));return JSON.parse(JSON.stringify(response));},
    fetchExtra:()=>fetchAsset('extra')};
}
test('retain requires actual cached bytes, not a saved preference',async()=>{
  const f=fixture();await f.add('common');
  assert.equal((await f.manage('retain','low')).ok,false);
  assert.equal((await f.manage('status','low')).installed.low,false);
  await f.add('low');assert.equal((await f.manage('retain','low')).installed.low,true);
});
test('switching can retain both packs and delete either without deleting shared bytes',async()=>{
  const f=fixture();for(const name of ['common','low','full'])await f.add(name);
  await f.manage('retain','low');await f.manage('retain','full');
  assert.deepEqual((await f.manage('status','full')).installed,{low:true,full:true});
  await f.manage('delete','low');assert.equal(f.data.has(f.key('low')),false);assert.equal(f.data.has(f.key('common')),true);assert.equal(f.data.has(f.key('full')),true);
  await f.add('low');await f.manage('retain','low');await f.manage('delete','full');
  assert.equal(f.data.has(f.key('full')),false);assert.equal(f.data.has(f.key('low')),true);assert.equal(f.data.has(f.key('common')),true);
});
test('a download reservation protects a chosen pack from the ordinary 128 MiB eviction budget',async()=>{
  const f=fixture();await f.manage('reserve','low');await f.add('common');await f.add('low');await f.fetchExtra();
  assert.equal(f.data.has(f.key('common')),true);assert.equal(f.data.has(f.key('low')),true);assert.equal(f.data.has(f.key('extra')),false);
});

test('optional room is not fetched by installation or profile retention, and a failed entry does not invalidate the installed main profile',async()=>{
  const f=fixture(true);await f.install();await f.manage('reserve','low');await f.add('common');await f.add('low');
  assert.equal((await f.manage('retain','low')).installed.low,true);
  assert.deepEqual(f.requests,[]);assert.equal(f.data.has(f.key('room')),false);
  f.fail('room');assert.equal(await f.fetchAsset('room'),503);
  assert.equal(f.data.has(f.key('room')),false);assert.equal((await f.manage('status','low')).installed.low,true);
});

test('downloaded optional room survives ordinary eviction and deleting another profile including its shared dependencies',async()=>{
  const f=fixture(true);await f.manage('reserve','low');await f.add('common');await f.add('low');await f.manage('retain','low');
  await f.fetchAsset('room_dep');await f.fetchAsset('room');await f.fetchExtra();
  assert.equal(f.data.has(f.key('room')),true);assert.equal(f.data.has(f.key('room_dep')),true);assert.equal(f.data.has(f.key('extra')),false);
  await f.add('full');await f.manage('retain','full');await f.manage('delete','full');
  assert.equal(f.data.has(f.key('full')),false);assert.equal(f.data.has(f.key('room_dep')),true);assert.equal(f.data.has(f.key('room')),true);
  assert.equal((await f.manage('status','low')).installed.low,true);
  const downloads=f.requests.length;await f.fetchAsset('room');assert.equal(f.requests.length,downloads);
});
