// Real hidden host + Web bridge + local Auth/Firestore, with synthetic accounts.
// prepare -> native recommendation_account_e2e.gd -> verify.
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),stage=process.argv[2]||'prepare',origin=process.argv[3]||'http://127.0.0.1:4317';
assert.ok(['prepare','verify'].includes(stage));assert.ok(['127.0.0.1','localhost'].includes(new URL(origin).hostname));
const directory=path.join(root,'deliverables/recommendation-room/account'),sessionPath=path.join(root,'build/recommendation-qa-session.json');
fs.mkdirSync(directory,{recursive:true});
const bridge=fs.readFileSync(path.join(root,'tools/web_account_bridge.js'),'utf8');
const interestCatalog=JSON.parse(fs.readFileSync(path.join(root,'game/data/interest_catalog.json'),'utf8'));
const run=Date.now().toString(36),password='Only-Local-Recommendation-QA-2026!';
const session=stage==='prepare'?{email:`recommendation-${run}@example.invalid`,recordId:`rec_qa_${run}`,examId:`exam_qa_${run}`}:JSON.parse(fs.readFileSync(sessionPath,'utf8'));
const checks=[],errors=[];
const check=(name,value)=>{assert.ok(value,name);checks.push(name);console.log('PASS',name);};
let browser;
async function send(page,command,interest=false,retryId=''){
  const requestId=retryId||'qa_'+Math.random().toString(36).slice(2);
  const accepted=await page.evaluate(({command,requestId,interest})=>{
    const state=JSON.parse(LittleWorldAccountBridge.stateJSON());
    return LittleWorldAccountBridge[interest?'interestCommand':'recommendationCommand'](JSON.stringify({...command,requestId,sessionGeneration:state.sessionGeneration}));
  },{command,requestId,interest});
  assert.equal(accepted,true,'accepted '+command.action);
  for(let index=0;index<250;index++){
    const messages=await page.evaluate(interest=>JSON.parse(LittleWorldAccountBridge[interest?'pollInterestMessagesJSON':'pollRecommendationMessagesJSON']()),interest);
    const packet=messages.find(item=>item.requestId===requestId);if(packet)return packet;
    await page.waitForTimeout(100);
  }
  throw new Error('Timed out '+command.action);
}
async function contextPage(email,signup){
  const context=await browser.newContext({viewport:{width:1280,height:900}}),page=await context.newPage();
  page.on('pageerror',error=>errors.push(error.message));
  await context.route('**/*',route=>{
    const url=new URL(route.request().url());
    if(url.origin===origin&&url.pathname==='/admissions/recommendation-qa/')return route.fulfill({contentType:'text/html',body:`<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><body><p>推薦通道本機驗證</p><script>${bridge}</script><script>LittleWorldAccountBridge.open('account')</script></body></html>`});
    if(/^https?:$/.test(url.protocol)&&!['127.0.0.1','localhost'].includes(url.hostname))return route.abort();
    return route.continue();
  });
  await page.goto(origin+'/admissions/recommendation-qa/');
  await page.waitForFunction(()=>Array.from(document.querySelectorAll('iframe')).some(host=>{try{return host.contentDocument.querySelector('iframe.host-content')?.contentWindow.location.pathname==='/admissions/account/';}catch{return false;}}));
  const form=page.frameLocator('.lw-account iframe').frameLocator('iframe.host-content');
  if(signup){await form.getByRole('button',{name:'建立帳號',exact:true}).click();await form.getByLabel('公開暱稱',{exact:true}).fill('推薦合成測試');await form.getByRole('radio',{name:'高中生',exact:true}).check();}
  await form.getByLabel('電子信箱',{exact:true}).fill(email);await form.locator('input[type="password"]').fill(password);
  await form.locator('form').getByRole('button',{name:signup?'建立帳號':'登入',exact:true}).click();
  await page.waitForFunction(()=>JSON.parse(LittleWorldAccountBridge.stateJSON()).user?.profileReady,{},{timeout:30000});
  await page.evaluate(()=>LittleWorldAccountBridge.close());
  return {context,page,host:page.frames().find(frame=>new URL(frame.url()||'about:blank').pathname==='/admissions/host/')};
}
(async()=>{
  const config=await fetch(origin+'/admissions/firebase-config.json').then(r=>r.json());assert.equal(config.useEmulators,true);assert.equal(config.projectId,'demo-starpath-tests');
  browser=await chromium.launch({channel:'chrome',headless:true});
  const first=await contextPage(session.email,stage==='prepare'),{page,host}=first;
  let bootstrap=await send(page,{action:'bootstrap'});
  check('Real hidden host supplies canonical major choices',bootstrap.type==='bootstrap'&&bootstrap.catalog.length>100&&bootstrap.years.join(',')==='115');
  if(stage==='prepare'){
    check('New account has no completed report',bootstrap.activeReport===null);
    const primary=bootstrap.catalog.find(row=>row.category==='資訊工程')||bootstrap.catalog.find(row=>row.groupId==='information');
    const secondary=bootstrap.catalog.find(row=>row.category==='機械工程')||bootstrap.catalog.find(row=>row.groupId==='engineering');
    const profile={schemaVersion:1,catalogVersion:1,title:'推薦完成報告',riasecDate:'',knowledgeDate:'',riasec:Object.fromEntries(interestCatalog.riasec.map(row=>[row.id,'45'])),knowledge:Object.fromEntries(interestCatalog.knowledge.map(row=>[row.id,'9'])),bestFits:[{groupId:primary.groupId,category:primary.category,z:'1.8'}],suitableFits:[{groupId:secondary.groupId,category:secondary.category,z:'0.6'}]};
    const complete=await send(page,{action:'complete',recordId:session.recordId,expectedRevision:0,profile},true);
    check('Existing interest bridge saves a valid completed report',complete.type==='state'&&complete.activeRecordId===session.recordId);
    const draft=await send(page,{action:'saveDraft',recordId:session.recordId,expectedRevision:complete.revision,profile:{...profile,title:'尚未完成的新草稿',riasec:{...profile.riasec,R:''}}},true);
    check('Draft is separate from completed data',draft.type==='state'&&draft.hasCompleted&&draft.hasDraft);
    await host.evaluate(async session=>{const runtime=await window.__starPathFirebase;if(!runtime.auth.emulatorConfig)throw Error('emulator required');await runtime.exams(runtime.auth.currentUser.uid).create(session.examId,{schemaVersion:1,kind:'mock',title:'推薦合成模考',examDate:'2026-10-25',scores:{國文:12,英文:12,數A:11,數B:12,社會:12,自然:11,英聽:3},apcsScores:{concept:3,practice:3}});},session);
    bootstrap=await send(page,{action:'bootstrap'});
    check('Recommendation reads the completed title and revision',bootstrap.activeReport.title==='推薦完成報告'&&bootstrap.activeReport.revision===complete.revision);
    const exams=await send(page,{action:'listExams',cursor:null});check('Saved exam is available through recommendation channel',exams.type==='exams'&&exams.items.some(item=>item.id===session.examId));
    const settings={...bootstrap.settings,examId:session.examId};
    const result=await send(page,{action:'query',settings});
    check('Joint recommendation returns bounded, explainable exact matches',result.type==='results'&&result.items.length>0&&result.items.length<=20&&result.items.every(row=>row.matchKind==='exact'&&row.reasons.length));
    check('Results identify exact completed report and selected exam',result.inputs.report.revision===complete.revision&&result.inputs.exam.id===session.examId);
    const item=result.items[0],detail=await send(page,{action:'detail',queryId:result.queryId,programRef:item.programRef});
    check('Detail has three annual comparisons and official sources',detail.type==='detail'&&detail.details.history.length===3&&detail.details.sources.length>0);
    if(result.nextCursor){const next=await send(page,{action:'page',queryId:result.queryId,cursor:result.nextCursor});check('Paging stays in one snapshot without duplicate records',next.type==='results'&&next.queryId===result.queryId&&!next.items.some(row=>result.items.some(first=>first.programRef===row.programRef)));}
    const mutation='favorite_'+run;
    const favorite=await send(page,{action:'setFavorite',programRef:item.programRef,value:true,expectedRevision:item.favoriteRevision},false,mutation);
    check('Favorite is acknowledged after cloud write',favorite.type==='favorite'&&favorite.value&&favorite.revision===1);
    const retry=await send(page,{action:'setFavorite',programRef:item.programRef,value:true,expectedRevision:item.favoriteRevision},false,mutation);
    check('Same mutation retry does not duplicate revision',retry.revision===favorite.revision);
    const conflict=await send(page,{action:'setFavorite',programRef:item.programRef,value:false,expectedRevision:0});check('Stale favorite write cannot overwrite',conflict.code==='cloud-revision-conflict');
    const saved=await send(page,{action:'saveSettings',settings:{...settings,mode:'interest'},expectedRevision:bootstrap.settingsRevision});check('Settings save acknowledged',saved.type==='settings'&&saved.settings.mode==='interest');
    const second=await contextPage(session.email,false);
    const favorites=await send(second.page,{action:'listFavorites',cursor:null}),secondBoot=await send(second.page,{action:'bootstrap'});
    check('Independent browser session sees same favorite and settings',favorites.items.some(row=>row.programRef===item.programRef)&&secondBoot.settings.mode==='interest');
    await second.context.close();
    const manual=await send(page,{action:'query',settings:{...settings,source:'manual',manual:[{groupId:primary.groupId,category:primary.category,level:2}],examId:''}});
    check('Manual exploration does not pretend to be joint ranking',manual.type==='results'&&manual.inputs.report===null&&manual.items.every(row=>row.priorityTier===null&&row.status==='explore'));
    const stale=await send(page,{action:'detail',queryId:result.queryId,programRef:item.programRef});check('Old snapshot is rejected after requery',stale.code==='query-expired');
    session.programRef=item.programRef;session.secondRef=result.items.find(row=>row.programRef!==item.programRef)?.programRef;session.universityId=item.universityId;session.settings=settings;
    fs.writeFileSync(sessionPath,JSON.stringify(session,null,2));
  }else{
    const favorites=await send(page,{action:'listFavorites',cursor:null});
    check('Browser sees favorite written by Windows IPC',favorites.type==='favorites'&&favorites.items.some(row=>row.programRef===session.secondRef));
    check('Windows mode setting persisted to browser',bootstrap.settings.mode==='academic');
  }
  check('Data operations keep the account website hidden',await page.evaluate(()=>!LittleWorldAccountBridge.isOpen()));
  await page.evaluate(()=>LittleWorldAccountBridge.signOut());
  await page.waitForFunction(()=>!JSON.parse(LittleWorldAccountBridge.stateJSON()).user?.signedIn);
  check('Logout clears pending private recommendation replies',await page.evaluate(()=>JSON.parse(LittleWorldAccountBridge.pollRecommendationMessagesJSON()).length===0));
  check('No browser script errors',errors.length===0);
  fs.writeFileSync(path.join(directory,`browser-${stage}.json`),JSON.stringify({passed:true,checks,errors,scope:'Actual browser bridge and hidden account host using local Auth/Firestore. Synthetic reports and exam; this is not a gameplay canvas test.'},null,2));
})().catch(error=>{fs.writeFileSync(path.join(directory,`browser-${stage}-failure.json`),JSON.stringify({checks,errors,error:String(error)},null,2));console.error(error);process.exitCode=1;}).finally(async()=>{if(browser)await browser.close();});
