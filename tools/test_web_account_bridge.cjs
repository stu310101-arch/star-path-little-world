'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {create} = require('./web_account_bridge.js');

test('device contexts and concurrent sparse pages stay independent by zone',()=>{
  const f=signedIn(), id='SPDEVCL0000000000006';
  assert.equal(f.api.openForum({zone:'campus',deviceId:id}),true);
  assert.deepEqual(f.messages.at(-1).data.context,{zone:'campus',deviceId:id});
  assert.equal(f.api.openForum({zone:'major',deviceId:id}),false);
  assert.equal(f.api.openForum({zone:'campus',deviceId:id,compose:true}),false);
  for(const zone of ['campus','major']) {
    assert.equal(f.api.requestForumPage({requestId:zone,zone,sessionGeneration:2,direction:'first',devices:true}),true);
    f.emit({channel:'starpath-forum',type:'page-begin',requestId:zone,zone,sessionGeneration:2,count:8,devicePage:0});
  }
  f.emit({channel:'starpath-forum',type:'page-empty',requestId:'campus',zone:'campus',sessionGeneration:2,index:6,threadId:id});
  const packets=JSON.parse(f.api.pollForumMessagesJSON());
  assert.equal(packets.length,3); assert.equal(packets[0].zone,'campus'); assert.equal(packets[1].zone,'major'); assert.equal(packets[2].threadId,id);
});

function fixture(path = '/') {
  let doc;
  class Element {
    constructor(tag) { this.tagName = tag; this.children = []; this.style = {}; this.events = new Map(); this.hidden = false; }
    appendChild(child) { child.parent = this; this.children.push(child); return child; }
    remove() { this.parent.children = this.parent.children.filter(child => child !== this); }
    addEventListener(type, fn) { if (!this.events.has(type)) this.events.set(type, new Set()); this.events.get(type).add(fn); }
    removeEventListener(type, fn) { this.events.get(type)?.delete(fn); }
    emit(type, event = {}) { for (const fn of this.events.get(type) || []) fn({type, target: this, ...event}); }
    setAttribute(key, value) { this[key] = value; }
    contains(target) { return target === this || this.children.some(child => child.contains(target)); }
    focus() { doc.activeElement = this; }
    blur() { if (doc.activeElement === this) doc.activeElement = null; }
  }
  doc = new Element('document'); doc.head = new Element('head'); doc.body = new Element('body');
  doc.body.style.overflow = 'auto';
  const canvas = new Element('canvas'); canvas.inert = false; doc.body.appendChild(canvas); doc.activeElement = canvas;
  const messages = [], frames = [], timers = new Map(); let serial = 0;
  doc.createElement = tag => {
    const element = new Element(tag);
    if (tag === 'iframe') {
      element.contentWindow = {postMessage: (data, origin) => messages.push({data, origin})};
      element.contentDocument = new Element('document'); frames.push(element);
    }
    return element;
  };
  doc.getElementById = id => id === 'canvas' ? canvas : null;
  const env = new Element('window');
  env.document = doc; env.location = {href: 'https://starpath.test' + path};
  env.setTimeout = fn => { const id = ++serial; timers.set(id, fn); return id; };
  env.clearTimeout = id => timers.delete(id);
  const api = create(env);
  const ui = () => { const root = doc.body.children.find(child => child.tagName === 'section');
    return root ? {root, back: root.children[0].children[1], retry: root.children[1].children[0].children[1], frame: frames.at(-1)} : null; };
  const emit = (data, overrides = {}) => env.emit('message', {origin: 'https://starpath.test', source: ui().frame.contentWindow,
    data: {channel: 'starpath-account', version: 1, ...data}, ...overrides});
  const key = (key, target) => ({key, target, preventDefault() { this.prevented = true; }, stopImmediatePropagation() { this.stopped = true; }});
  return {api, env, doc, canvas, messages, frames, timers, ui, emit, key};
}

test('silent resume restores authenticated state without displaying the login modal or taking focus', () => {
  const f = fixture('/mobile/');
  assert.equal(f.api.resume(), true);
  assert.equal(f.api.isOpen(), false);
  assert.equal(f.ui().root.hidden, true);
  assert.equal(f.canvas.inert, false);
  assert.equal(f.doc.activeElement, f.canvas);
  f.emit({type:'ready'});
  f.emit({type:'auth-state',sessionGeneration:4,resolving:true,user:{signedIn:true,profileReady:false,identity:'',sessionGeneration:4}});
  assert.equal(JSON.parse(f.api.stateJSON()).resolved, false);
  f.emit({type:'auth-state',sessionGeneration:4,resolving:false,user:{signedIn:true,profileReady:true,identity:'university',sessionGeneration:4}});
  const state=JSON.parse(f.api.stateJSON());
  assert.equal(state.resolved,true); assert.equal(state.user.profileReady,true); assert.equal(f.api.isOpen(),false);
  f.api.signOut(); assert.equal(f.messages.at(-1).data.type,'sign-out');
  f.emit({type:'auth-state',sessionGeneration:5,user:null});
  assert.equal(JSON.parse(f.api.stateJSON()).user,null);
});

test('lazy host accepts only views, always uses root admissions URL on mobile', () => {
  const f = fixture('/mobile/');
  assert.equal(f.ui(), null); assert.equal(f.api.open('https://foreign.test'), false);
  assert.equal(f.api.open('query'), true);
  assert.equal(f.ui().frame.src, 'https://starpath.test/admissions/host/?platform=web&view=query');
  assert.equal(f.canvas.inert, true);
  f.emit({type: 'ready'});
  assert.deepEqual(f.messages[0], {data: {channel: 'starpath-account', version: 1, type: 'navigate', view: 'query'}, origin: 'https://starpath.test'});
});

test('all three room desks use the same persistent framed terminal', () => {
  const f = fixture();
  for (const view of ['general', 'special', 'apcs']) {
    assert.equal(f.api.open(view), true);
    if (view === 'general') f.emit({type: 'ready'});
    assert.equal(f.messages.at(-1).data.view, view);
    assert.equal(f.frames.length, 1);
  }
  assert.match(f.doc.head.children[0].textContent, /left:18\.5vw/);
  assert.match(f.doc.head.children[0].textContent, /width:78vw/);
  assert.match(f.doc.head.children[0].textContent, /max-width:900px/);
});

test('origin, source, version and channel all guard incoming messages', () => {
  const f = fixture(); f.api.open('account');
  const data = {type: 'auth-state', user: {signedIn: true}};
  f.emit(data, {origin: 'https://foreign.test'}); f.emit(data, {source: {}});
  f.emit({...data, version: 2}); f.emit({...data, channel: 'training-games'});
  assert.equal(JSON.parse(f.api.stateJSON()).user, null);
  f.emit({type: 'close'}, {source: {}}); assert.equal(f.api.isOpen(), true);
  f.emit({type: 'auth-state', user: {signedIn: true, uid: 'student-1', displayName: '小星', idToken: 'never-forward'}});
  assert.deepEqual(JSON.parse(f.api.stateJSON()).user, {signedIn: true, displayName: '小星', identity:'', profileReady:false, sessionGeneration:0});
  assert.equal(f.api.stateJSON().includes('never-forward'), false);
  assert.equal(f.api.stateJSON().includes('student-1'), false);
  f.emit({type: 'auth-state', user: {signedIn: 1}});
  f.emit({type: 'auth-state', user: {uid: 'student-2'}});
  assert.deepEqual(JSON.parse(f.api.stateJSON()).user, {signedIn: true, displayName: '小星', identity:'', profileReady:false, sessionGeneration:0});
});

test('close preserves host and auth updates, reopen navigates without another iframe', () => {
  const f = fixture(); f.api.open('query'); f.emit({type: 'ready'});
  const frame = f.ui().frame, src = frame.src;
  f.api.close(); assert.equal(f.canvas.inert, false); assert.equal(f.doc.body.style.overflow, 'auto');
  assert.equal(f.messages.at(-1).data.type, 'suspend');
  f.emit({type: 'auth-state', user: {signedIn: true}});
  assert.equal(JSON.parse(f.api.stateJSON()).user.signedIn, true);
  f.api.open('scores'); assert.equal(f.frames.length, 1); assert.equal(f.ui().frame, frame); assert.equal(frame.src, src);
  assert.equal(f.messages.at(-1).data.view, 'scores');
  f.api.signOut(); assert.equal(f.messages.at(-1).data.type, 'sign-out');
  f.emit({type: 'auth-state', user: null}); assert.equal(JSON.parse(f.api.stateJSON()).user, null);
});

test('ready while closed does not steal focus, and timed-out host offers retry', () => {
  const f = fixture(); f.api.open('account'); f.api.close(); f.emit({type: 'ready'});
  assert.equal(f.doc.activeElement, f.canvas); assert.equal(f.api.isOpen(), false);
  const broken = fixture(); broken.api.open('scores'); [...broken.timers.values()][0]();
  assert.equal(broken.ui().retry.hidden, false); assert.match(JSON.parse(broken.api.stateJSON()).error, /無法載入/);
  broken.emit({type: 'ready'}); assert.equal(JSON.parse(broken.api.stateJSON()).ready, false);
  broken.ui().retry.emit('click'); broken.emit({type: 'ready'});
  assert.equal(broken.ui().frame.hidden, false); assert.equal(JSON.parse(broken.api.stateJSON()).error, '');
});

test('Escape and parent canvas input stay isolated from world and Go', () => {
  const f = fixture(); f.api.open('query'); f.emit({type: 'ready'});
  const event = f.key('Escape', f.ui().frame.contentDocument);
  f.ui().frame.contentDocument.emit('keydown', event);
  assert.equal(f.api.isOpen(), false); assert.equal(f.doc.activeElement, f.canvas);
  f.api.open('scores');
  const foreign = f.key('F', f.canvas);
  f.doc.emit('keydown', foreign); assert.equal(f.doc.activeElement, f.ui().back);
  f.emit({type: 'open-external', url: 'https://evil.test'});
  assert.equal(f.api.isOpen(), true);
  f.api.destroy(); assert.equal(f.ui(), null); assert.equal(f.env.events.get('message').size, 0);
});

function signedIn() {
  const f = fixture(); f.api.open('account'); f.emit({type:'ready'});
  f.emit({type:'auth-state',sessionGeneration:2,user:{signedIn:true,displayName:'小星',identity:'graduate',profileReady:true,sessionGeneration:2,uid:'private-user'}});
  return f;
}

function interestFixtureProfile() {
  return {schemaVersion:1,catalogVersion:1,title:'秋季量表',riasecDate:'',knowledgeDate:'',riasec:Object.fromEntries(['R','I','A','S','E','C'].map(id=>[id,'0'])),knowledge:Object.fromEntries(Array.from({length:33},(_,i)=>['k'+String(i+1).padStart(2,'0'),'18'])),bestFits:Array.from({length:60},(_,i)=>({groupId:'arts',category:'藝術創作與設計 '+i,z:'-0.3'})),suitableFits:[]};
}

test('hidden interest sync supports large pure Godot forms without navigation or focus changes',()=>{
  const f=signedIn(); f.api.close(); const profile=interestFixtureProfile();
  const command={action:'complete',requestId:'i1',sessionGeneration:2,recordId:'one',expectedRevision:0,profile};
  assert.ok(Buffer.byteLength(JSON.stringify(command))>4096);
  const source=f.ui().frame.src, focus=f.doc.activeElement;
  assert.equal(f.api.interestCommand(JSON.stringify(command)),true);
  assert.equal(f.api.isOpen(),false); assert.equal(f.ui().frame.src,source); assert.equal(f.doc.activeElement,focus);
  assert.equal(f.messages.at(-1).data.type,'interest-command');
  f.emit({channel:'starpath-interest',type:'state',requestId:'i1',sessionGeneration:2,recordId:'one',revision:1,profile,hasCompleted:true,hasDraft:false,activeRecordId:'one',selectionRevision:1,updatedAtMillis:1,uid:'never-return'});
  const packets=JSON.parse(f.api.pollInterestMessagesJSON()); assert.equal(packets.length,1); assert.equal(packets[0].profile.bestFits.length,60);
  assert.equal(JSON.stringify(packets).includes('never-return'),false); assert.equal(f.api.isOpen(),false);
});

test('interest commands reject ownership fields, changed retries and oversized/foreign replies',()=>{
  const f=signedIn(), command={action:'get',requestId:'i1',sessionGeneration:2,recordId:'one'};
  assert.equal(f.api.interestCommand({...command,uid:'bob'}),false);
  assert.equal(f.api.interestCommand(command),true); assert.equal(f.api.interestCommand(command),true);
  assert.equal(f.api.interestCommand({...command,recordId:'two'}),false);
  const packet={channel:'starpath-interest',type:'state',requestId:'i1',sessionGeneration:2,recordId:'one',revision:0,profile:null,hasCompleted:false,hasDraft:false,activeRecordId:'',selectionRevision:0,updatedAtMillis:0};
  f.emit(packet,{origin:'https://foreign.test'}); f.emit(packet,{source:{}}); f.emit({...packet,recordId:'two'});
  f.emit({...packet,padding:'x'.repeat(65536)}); assert.equal(f.api.pollInterestMessagesJSON(),'[]');
  f.emit(packet); assert.equal(JSON.parse(f.api.pollInterestMessagesJSON()).length,1);
  const big=interestFixtureProfile(); big.bestFits=Array.from({length:512},()=>({groupId:'arts',category:'字'.repeat(80),z:'-0.3'}));
  assert.equal(f.api.interestCommand({action:'saveDraft',requestId:'large',sessionGeneration:2,recordId:'one',expectedRevision:0,profile:big}),false);
});

test('account changes erase queued and in-flight private interest records',()=>{
  const f=signedIn(); f.api.interestCommand({action:'get',requestId:'i1',sessionGeneration:2,recordId:'one'});
  f.emit({type:'auth-state',sessionGeneration:3,user:{signedIn:true,identity:'graduate',profileReady:true,sessionGeneration:3}});
  f.emit({channel:'starpath-interest',type:'state',requestId:'i1',sessionGeneration:2,recordId:'one',revision:1,profile:interestFixtureProfile(),hasCompleted:true,hasDraft:false,activeRecordId:'one',selectionRevision:1,updatedAtMillis:1});
  assert.equal(f.api.pollInterestMessagesJSON(),'[]');
  assert.equal(f.api.interestCommand({action:'get',requestId:'new',sessionGeneration:2,recordId:'one'}),false);
});
test('forum bridge accepts JSON commands and returns only public bounded page fields', () => {
  const f = signedIn();
  const command = {requestId:'page_1',sessionGeneration:2,zone:'campus',direction:'first',token:'drop'};
  assert.equal(f.api.requestForumPage(JSON.stringify(command)), true);
  assert.equal('token' in f.messages.at(-1).data.command, false);
  const base = {channel:'starpath-forum',requestId:'page_1',sessionGeneration:2,zone:'campus'};
  f.emit({...base,type:'page-begin',count:1});
  f.emit({...base,type:'page-item',index:0,threadId:'A'.repeat(20),preview:'🌱'.repeat(120),authorName:'不可傳出',identity:'graduate',anonymous:true,deleted:false,createdAtMillis:1,updatedAtMillis:1,uid:'private-user'});
  f.emit({...base,type:'page-end',count:1,hasNext:false,hasPrevious:false});
  const data = JSON.parse(f.api.pollForumMessagesJSON());
  assert.equal(data.length,3); assert.equal(data[1].authorName,'匿名');
  assert.equal(JSON.stringify(data).includes('private-user'),false);
  assert.equal(f.api.pollForumMessagesJSON(),'[]');
  assert.equal(f.api.openForum(JSON.stringify({zone:'major',compose:true})),true);
  assert.equal(f.messages.at(-1).data.type,'forum-open');
  assert.equal(f.api.openForum({zone:'major',threadId:'A'.repeat(20),compose:true}),false);
});
test('account switches invalidate forum requests and private progress in flight', () => {
  const f = signedIn();
  assert.equal(f.api.progressCommand(JSON.stringify({requestId:'u_1',sessionGeneration:2,action:'university-get'})),true);
  f.emit({channel:'starpath-progress',type:'state',requestId:'u_1',sessionGeneration:2,app:'university',favorites:{'001':true},explored:['001'],revision:1,uid:'drop'});
  assert.equal(JSON.parse(f.api.pollProgressMessagesJSON())[0].favorites['001'],true);
  f.api.requestForumPage({requestId:'p',sessionGeneration:2,zone:'campus',direction:'first'});
  f.emit({type:'auth-state',sessionGeneration:3,user:null});
  f.emit({channel:'starpath-forum',type:'page-begin',requestId:'p',sessionGeneration:2,zone:'campus',count:0});
  assert.equal(f.api.pollForumMessagesJSON(),'[]');
  assert.equal(f.api.progressCommand({requestId:'u_2',sessionGeneration:2,action:'university-get'}),false);
  f.emit({type:'auth-state',sessionGeneration:2,user:{signedIn:true,profileReady:true,identity:'graduate'}});
  assert.equal(JSON.parse(f.api.stateJSON()).user,null);
});
test('oversized, foreign, malformed and unmatched page packets never reach Godot', () => {
  const f = signedIn(); f.api.requestForumPage({requestId:'p',sessionGeneration:2,zone:'campus',direction:'first'});
  const row = {channel:'starpath-forum',type:'page-item',index:0,requestId:'p',sessionGeneration:2,zone:'campus',threadId:'A'.repeat(20),preview:'x',authorName:'甲',identity:'graduate',anonymous:false,deleted:false,createdAtMillis:1,updatedAtMillis:1};
  f.emit(row,{origin:'https://foreign.test'}); f.emit({...row,preview:'x'.repeat(121)}); f.emit({...row,requestId:'unknown'}); f.emit({...row,garbage:'中'.repeat(2000)});
  assert.equal(f.api.pollForumMessagesJSON(),'[]');
});
const recommendationSettingsFixture = () => ({source:'manual',manual:[{groupId:'information',category:'資訊工程',level:2}],examId:'',mode:'balanced',year:'115',applicantGender:'',filters:{keyword:'',category:'',status:'all'}});
test('recommendations keep hidden host focus and reject ownership, changed retry and wrong response types',()=>{
  const f=signedIn(), command={action:'query',requestId:'rec-query',sessionGeneration:2,settings:recommendationSettingsFixture()};
  f.api.close();
  assert.equal(f.api.recommendationCommand({...command,uid:'other'}),false);
  assert.equal(f.api.recommendationCommand(command),true);
  assert.equal(f.messages.at(-1).data.type,'recommendation-command');
  assert.equal(f.api.recommendationCommand(command),true);
  assert.equal(f.api.recommendationCommand({...command,settings:{...command.settings,mode:'academic'}}),false);
  f.emit({channel:'starpath-recommendations',type:'settings',requestId:'rec-query',sessionGeneration:2,settings:command.settings,settingsRevision:1});
  assert.deepEqual(JSON.parse(f.api.pollRecommendationMessagesJSON()),[]);
  f.emit({channel:'starpath-recommendations',type:'error',requestId:'rec-query',sessionGeneration:2,code:'unavailable',message:'請重試'});
  assert.equal(JSON.parse(f.api.pollRecommendationMessagesJSON()).length,1);
  assert.equal(f.api.isOpen(),false); assert.equal(f.canvas.inert,false);
});
test('recommendations validate TypeScript real service wire fixtures across the web bridge',()=>{
  const packets=require('../admissions-site/tests/fixtures/recommendation-wire.json').packets;
  const f=signedIn();
  for(let index=0;index<packets.length;index++) {
    const packet=structuredClone(packets[index]), requestId='rec-wire-'+index;
    const action={bootstrap:'bootstrap',exams:'listExams',results:'query',detail:'detail',settings:'saveSettings',favorites:'listFavorites',favorite:'setFavorite'}[packet.type];
    const command={requestId,sessionGeneration:2,action};
    if(['query','saveSettings'].includes(action)) command.settings=packet.settings||packet.inputs.settings;
    if(['listExams','listFavorites'].includes(action)) command.cursor=null;
    if(action==='saveSettings') command.expectedRevision=0;
    if(action==='detail') {command.queryId=packet.queryId;command.programRef=packet.item.programRef;}
    if(action==='setFavorite') Object.assign(command,{programRef:packet.programRef,value:packet.value,expectedRevision:0});
    assert.equal(f.api.recommendationCommand(command),true,action);
    f.emit({...packet,requestId,sessionGeneration:2});
    assert.equal(JSON.parse(f.api.pollRecommendationMessagesJSON()).length,1,packet.type);
  }
});
test('recommendation details require matching query and program; logout invalidates private queues',()=>{
  const f=signedIn(), packet=structuredClone(require('../admissions-site/tests/fixtures/recommendation-wire.json').packets.find(p=>p.type==='detail'));
  const command={requestId:'rec-detail',sessionGeneration:2,action:'detail',queryId:packet.queryId,programRef:packet.item.programRef};
  assert.equal(f.api.recommendationCommand(command),true);
  f.emit({...packet,requestId:command.requestId,sessionGeneration:2,queryId:'other'});
  f.emit({...packet,requestId:command.requestId,sessionGeneration:2,item:{...packet.item,uid:'secret'}});
  assert.deepEqual(JSON.parse(f.api.pollRecommendationMessagesJSON()),[]);
  f.emit({...packet,requestId:command.requestId,sessionGeneration:2});
  f.emit({type:'auth-state',sessionGeneration:3,user:null});
  assert.deepEqual(JSON.parse(f.api.pollRecommendationMessagesJSON()),[]);
  assert.equal(f.api.recommendationCommand(command),false);
});
