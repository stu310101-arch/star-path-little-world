// Real browser bridge + hidden host + Auth/Firestore emulators.
// Run prepare, native interest_account_e2e.gd, then verify for cross-target proof.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const stage = process.argv[2] || 'prepare';
const base = process.argv[3] || 'http://127.0.0.1:4317';
const origin = new URL(base).origin;
assert.ok(['127.0.0.1','localhost'].includes(new URL(base).hostname));
assert.ok(['prepare','verify'].includes(stage));
const output = path.join(root,'deliverables/counseling-room/account');
fs.mkdirSync(output,{recursive:true});
const sessionPath = path.join(root,'build/counseling-qa-session.json');
const catalog = JSON.parse(fs.readFileSync(path.join(root,'game/data/interest_catalog.json'),'utf8'));
const bridge = fs.readFileSync(path.join(root,'tools/web_account_bridge.js'),'utf8');
const password = 'Only-Local-Interest-QA-2026!';
const checks = [], errors = [];
const check = (name,ok) => {assert.ok(ok,name);checks.push(name);console.log('PASS',name);};
const run = Date.now().toString(36);
const session = stage==='prepare' ? {email:`interest-${run}@example.invalid`,recordId:`qa_${run}`,secondId:`qa_second_${run}`} : JSON.parse(fs.readFileSync(sessionPath,'utf8'));
let browser;
async function send(page,command) {
  const requestId = 'qa_'+Math.random().toString(36).slice(2);
  const accepted = await page.evaluate(({command,requestId})=>{
    const state=JSON.parse(LittleWorldAccountBridge.stateJSON());
    return LittleWorldAccountBridge.interestCommand(JSON.stringify({...command,requestId,sessionGeneration:state.sessionGeneration}));
  },{command,requestId});
  assert.equal(accepted,true,'interest request accepted');
  for(let i=0;i<200;i++) {
    const messages=await page.evaluate(()=>JSON.parse(LittleWorldAccountBridge.pollInterestMessagesJSON()));
    const packet=messages.find(item=>item.requestId===requestId);
    if(packet)return packet;
    await page.waitForTimeout(100);
  }
  throw new Error('Interest request timed out');
}
(async()=>{
  const config=await fetch(origin+'/admissions/firebase-config.json').then(r=>r.json());
  assert.equal(config.useEmulators,true);assert.equal(config.projectId,'demo-starpath-tests');
  browser=await chromium.launch({channel:'chrome',headless:true});
  const context=await browser.newContext({viewport:{width:1280,height:900}});
  const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));
  await context.route('**/*',route=>{
    const url=new URL(route.request().url());
    if(url.origin===origin&&url.pathname==='/admissions/interest-qa/')return route.fulfill({contentType:'text/html',body:`<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><body><p id="surface">遊戲量表橋接測試</p><script>${bridge}</script><script>LittleWorldAccountBridge.open('account')</script></body></html>`});
    if(/^https?:$/.test(url.protocol)&&!['127.0.0.1','localhost'].includes(url.hostname))return route.abort();
    return route.continue();
  });
  await page.goto(origin+'/admissions/interest-qa/');
  await page.waitForFunction(()=>Array.from(document.querySelectorAll('iframe')).some(host=>{try{return host.contentDocument.querySelector('iframe.host-content')?.contentWindow.location.pathname==='/admissions/account/';}catch{return false;}}));
  const account=page.frames().find(frame=>new URL(frame.url()||'about:blank').pathname==='/admissions/account/');
  assert.ok(account);
  if(stage==='prepare') {
    await account.getByRole('button',{name:'建立帳號',exact:true}).click();
    await account.getByLabel('公開暱稱',{exact:true}).fill('量表跨裝置測試');
    await account.getByRole('radio',{name:'高中生',exact:true}).check();
  }
  await account.getByLabel('電子信箱',{exact:true}).fill(session.email);
  await account.locator('input[type="password"]').fill(password);
  await account.locator('form').getByRole('button',{name:stage==='prepare'?'建立帳號':'登入',exact:true}).click();
  await page.waitForFunction(()=>JSON.parse(LittleWorldAccountBridge.stateJSON()).user?.profileReady,{},{timeout:30000});
  await page.evaluate(()=>LittleWorldAccountBridge.close());
  check('Interest synchronization starts with the account host hidden',await page.evaluate(()=>!LittleWorldAccountBridge.isOpen()));
  if(stage==='prepare') {
    const profile={schemaVersion:1,catalogVersion:1,title:'跨裝置量表測試',riasecDate:'',knowledgeDate:'2026-10-24',
      riasec:Object.fromEntries(catalog.riasec.map(item=>[item.id,item.id==='R'?'':'0'])),
      knowledge:Object.fromEntries(catalog.knowledge.map(item=>[item.id,'18'])),
      bestFits:Array.from({length:26},(_,i)=>({groupId:'engineering',category:`測試最適合學類${i+1}`,z:String(i/10)})),
      suitableFits:Array.from({length:26},(_,i)=>({groupId:'education',category:`測試適合學類${i+1}`,z:String(-i/10)}))};
    check('Fixture exceeds old IPC limit',Buffer.byteLength(JSON.stringify(profile))>4096);
    const saved=await send(page,{action:'saveDraft',recordId:session.recordId,expectedRevision:0,profile});
    check('Browser saves incomplete draft with 52 fit rows',saved.type==='state'&&saved.hasDraft&&saved.revision===1&&saved.profile.bestFits.length===26&&saved.profile.suitableFits.length===26);
    check('Blank required score remains blank',saved.profile.riasec.R==='');
    check('Incomplete draft is not selected for recommendation',saved.activeRecordId==='');
    fs.writeFileSync(sessionPath,JSON.stringify(session,null,2));
  } else {
    const list=await send(page,{action:'list'});
    check('Browser sees both records written through native Godot',list.type==='list'&&list.records.some(r=>r.id===session.recordId)&&list.records.some(r=>r.id===session.secondId));
    check('Native selected record persists across browser login',list.activeRecordId===session.secondId);
    const first=await send(page,{action:'get',recordId:session.recordId});
    check('Draft and completed copy coexist',first.hasDraft&&first.hasCompleted&&first.profile.riasec.R==='');
    const second=await send(page,{action:'get',recordId:session.secondId});
    check('Native completed scores and signed Z values survive cross-target roundtrip',second.type==='state'&&second.profile.riasec.R==='90'&&second.profile.knowledge.k33==='18'&&second.profile.suitableFits[25].z==='-2.5');
    const active=await page.frames().find(frame=>new URL(frame.url()||'about:blank').pathname==='/admissions/host/').evaluate(async()=>{
      const runtime=await window.__starPathFirebase;
      if(!runtime.auth.emulatorConfig)throw new Error('Local emulator required');
      return runtime.interests(runtime.auth.currentUser.uid).getActiveCompleted();
    });
    check('Recommendation accessor returns only completed profile',active.riasec.R==='90');
  }
  check('Score operations never open a website form',await page.evaluate(()=>!LittleWorldAccountBridge.isOpen()));
  check('No browser JavaScript errors',errors.length===0);
  await page.screenshot({path:path.join(output,`browser-${stage}-hidden-host.png`)});
  fs.writeFileSync(path.join(output,`browser-${stage}.json`),JSON.stringify({stage,passed:true,checks,errors,scope:'Real hidden browser host and local Auth/Firestore emulators; outer canvas is a bridge harness, not a gameplay test.'},null,2));
})().catch(error=>{fs.writeFileSync(path.join(output,`browser-${stage}-failure.json`),JSON.stringify({checks,errors,error:String(error)},null,2));console.error(error);process.exitCode=1;}).finally(async()=>{if(browser)await browser.close();});
