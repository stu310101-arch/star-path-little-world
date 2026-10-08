/* Lifecycle and failure tests without starting the WebGL game. */
const test = require('node:test');
const assert = require('node:assert/strict');
const {create} = require('./training_computer_games.js');

function fixture() {
  let doc;
  class Node {
    constructor(tag) { this.tagName=tag; this.children=[]; this.style={}; this.listeners=new Map(); this.hidden=false; }
    appendChild(child) { this.children.push(child); child.parent=this; return child; }
    remove() { if(this.parent) this.parent.children=this.parent.children.filter(c=>c!==this); this.removed=true; }
    addEventListener(name,fn) { if(!this.listeners.has(name))this.listeners.set(name,new Set()); this.listeners.get(name).add(fn); }
    removeEventListener(name,fn) { this.listeners.get(name)?.delete(fn); }
    emit(name,event={}) { for(const fn of this.listeners.get(name)||[])fn({type:name,target:this,...event}); }
    setAttribute(name,value) { this[name]=value; }
    contains(node) { return this===node || this.children.some(child=>child.contains(node)); }
    focus() { doc.activeElement=this; }
    blur() { if(doc.activeElement===this)doc.activeElement=null; this.blurred=true; }
  }
  doc=new Node('document');
  doc.head=new Node('head'); doc.body=new Node('body'); doc.body.style.overflow='auto';
  const canvas=new Node('canvas');canvas.inert=false;
  doc.body.appendChild(canvas);doc.activeElement=canvas;
  doc.createElement=tag=>new Node(tag);doc.getElementById=id=>id==='canvas'?canvas:null;
  doc.pointerLockElement=canvas;doc.exitPointerLock=()=>{doc.pointerLockElement=null;};
  const calls=[],timers=new Map();let serial=0,response={ok:true,text:async()=>'<script id="go-app-code"></script>'};
  const env={document:doc,location:{href:'https://example.test/little-world/',protocol:'https:'},AbortController,
    fetch:async(url,init)=>{calls.push({url,init});return response;},
    setTimeout:fn=>{const id=++serial;timers.set(id,fn);return id;},clearTimeout:id=>timers.delete(id)};
  const api=create(env);
  const ui=()=>{const root=doc.body.children.find(n=>n.tagName==='section');if(!root)return null;
    return {root,back:root.children[0].children[1],status:root.children[1].children[0],
      retry:root.children[1].children[0].children[1],frame:root.children[1].children[1]};};
  const flush=async()=>{for(let i=0;i<5;i++)await Promise.resolve();};
  const load=()=>{const frame=ui().frame;const childDoc=new Node('child-document');childDoc.getElementById=id=>id==='board-input'?{}:null;
    frame.contentWindow={location:{href:frame.src},document:childDoc};frame.onload();return childDoc;};
  const event=(key,target)=>({key,target,preventDefault(){this.prevented=true;},stopImmediatePropagation(){this.stopped=true;},stopPropagation(){this.stopped=true;}});
  return {env,doc,canvas,api,calls,timers,ui,flush,load,event,response:value=>{response=value;}};
}

test('idle bridge does not load game; opening displays modal synchronously and validates URL',async()=>{
  const f=fixture();assert.equal(f.calls.length,0);assert.equal(f.ui(),null);
  for(const [id,url] of [['go','https://bad.test/game.html'],['go','../games/go/index.html'],['future','games/go/index.html']]) {
    assert.equal(f.api.open(id,'ignored',url),false);
  }
  assert.equal(f.calls.length,0);
  assert.equal(f.api.open('go','圍棋','games/go/index.html'),true);
  assert.equal(f.api.isOpen(),true);assert.equal(f.ui().root.hidden,false);
  assert.equal(f.canvas.inert,true);assert.equal(f.canvas.blurred,true);assert.equal(f.doc.pointerLockElement,null);
  assert.equal(f.ui().frame.src,undefined);await f.flush();
  assert.equal(f.calls[0].url,'https://example.test/little-world/games/go/index.html');
  assert.equal(f.ui().frame.src,f.calls[0].url);
  f.load();assert.equal(f.ui().frame.hidden,false);assert.equal(f.ui().status.hidden,true);
  assert.equal(f.timers.size,0);
});

test('close preserves match iframe and reopen does not fetch or reload',async()=>{
  const f=fixture();f.api.open('go','圍棋','games/go/index.html');await f.flush();f.load();
  const frame=f.ui().frame;frame.matchState={move:23};f.ui().back.emit('click');
  assert.equal(f.api.isOpen(),false);assert.equal(f.ui().root.hidden,true);
  assert.equal(f.canvas.inert,false);assert.equal(f.doc.activeElement,f.canvas);assert.equal(f.doc.body.style.overflow,'auto');
  f.api.open('go','圍棋','games/go/index.html');
  assert.equal(f.ui().frame,frame);assert.equal(frame.matchState.move,23);assert.equal(f.calls.length,1);
});

test('initial iframe about:blank load cannot turn a cached fetch into failure',async()=>{
  const f=fixture();f.api.open('go','圍棋','games/go/index.html');await f.flush();
  f.ui().frame.contentWindow={location:{href:'about:blank'}};f.ui().frame.onload();
  assert.equal(f.ui().retry.hidden,true);f.load();assert.equal(f.ui().frame.hidden,false);
});

test('Escape inside iframe closes without reaching game hotkeys or canvas keyup',async()=>{
  const f=fixture();f.api.open('go','圍棋','games/go/index.html');await f.flush();const child=f.load();
  const escape=f.event('Escape',child);for(const fn of child.listeners.get('keydown'))fn(escape);
  assert.equal(f.api.isOpen(),false);assert.equal(escape.prevented,true);assert.equal(escape.stopped,true);
  const keyup=f.event('Escape',f.canvas);f.doc.emit('keyup',keyup);
  // emit makes an event copy, so verify direct keyup listener as well.
  f.api.open('go','圍棋','games/go/index.html');
  const parentEscape=f.event('Escape',f.ui().back);for(const fn of f.doc.listeners.get('keydown'))fn({...parentEscape,type:'keydown'});
  const release=f.event('Escape',f.canvas);release.type='keyup';for(const fn of f.doc.listeners.get('keyup'))fn(release);
  assert.equal(release.prevented,true);assert.equal(release.stopped,true);
});

test('failed response exposes retry, which loads successfully',async()=>{
  const f=fixture();f.response({ok:false});f.api.open('go','圍棋','games/go/index.html');await f.flush();
  assert.equal(f.api.isOpen(),true);assert.equal(f.ui().retry.hidden,false);assert.equal(f.ui().frame.src,undefined);
  f.response({ok:true,text:async()=>'<script id="go-app-code"></script>'});
  f.ui().retry.emit('click');await f.flush();f.load();
  assert.equal(f.calls.length,2);assert.equal(f.ui().status.hidden,true);assert.equal(f.ui().frame.hidden,false);
});

test('foreign redirect and successful wrong-page response remain failures',async()=>{
  for(const response of [{ok:true,url:'https://other.test/game.html'}, {ok:true,text:async()=>'<html>404 fallback</html>'}]) {
    const f=fixture();f.response(response);f.api.open('go','圍棋','games/go/index.html');await f.flush();
    assert.equal(f.ui().frame.src,undefined);assert.equal(f.ui().retry.hidden,false);
  }
});

test('closing during fetch never steals focus when background load completes',async()=>{
  const f=fixture();let resolve;f.response({ok:true,text:()=>new Promise(r=>resolve=r)});
  f.api.open('go','圍棋','games/go/index.html');await f.flush();f.api.close();
  resolve('<script id="go-app-code"></script>');await f.flush();f.load();
  assert.equal(f.api.isOpen(),false);assert.equal(f.doc.activeElement,f.canvas);assert.equal(f.ui().root.hidden,true);
});

test('timeout exposes retry and prevents a late load from becoming ready',async()=>{
  const f=fixture();f.api.open('go','圍棋','games/go/index.html');await f.flush();
  for(const fn of f.timers.values())fn();
  assert.equal(f.ui().retry.hidden,false);f.load();assert.equal(f.ui().frame.hidden,true);
});

test('destroy aborts pending work and unloads iframe; a later visit can open afresh',async()=>{
  const f=fixture();f.api.open('go','圍棋','games/go/index.html');await f.flush();const frame=f.ui().frame;
  f.api.destroy();assert.equal(frame.removed,true);assert.equal(f.ui(),null);assert.equal(f.api.isOpen(),false);
  assert.equal(f.calls[0].init.signal.aborted,true);assert.equal(f.timers.size,0);
  assert.equal(f.doc.listeners.get('keydown').size,0);
  f.api.open('go','圍棋','games/go/index.html');await f.flush();f.load();assert.equal(f.calls.length,2);
});

test('parent canvas input is swallowed while overlay owns focus',()=>{
  const f=fixture();f.api.open('go','圍棋','games/go/index.html');
  const event=f.event('w',f.canvas);event.type='keydown';for(const fn of f.doc.listeners.get('keydown'))fn(event);
  assert.equal(event.prevented,true);assert.equal(event.stopped,true);assert.equal(f.doc.activeElement,f.ui().back);
});
