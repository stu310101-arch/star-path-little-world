/* Real browser UI -> persistent account host -> Firebase Auth/Firestore emulators.
 * Only the outer game canvas is a harness; no repository or SDK is mocked.
 * Requires admissions build, STARPATH_EMULATORS=1 preview4317, Auth9099/Firestore8080.
 */
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const base = process.argv[2] || 'http://127.0.0.1:4317';
const origin = new URL(base).origin;
if (!['127.0.0.1', 'localhost'].includes(new URL(base).hostname)) throw new Error('Emulator QA only accepts loopback origins');
const output = path.join(root, 'deliverables/discussion-forum'); fs.mkdirSync(output, {recursive:true});
const bridge = fs.readFileSync(path.join(root,'tools/web_account_bridge.js'),'utf8');
const run = Date.now().toString(36), password = 'StarPath-Test-2026!';
const alice = `forum-alice-${run}@example.test`, bob = `forum-bob-${run}@example.test`;
const mainBody = `校園 E2E ${run}：請分享你的選系經驗。\n這是本機模擬器的第二行。`;
const replyBody = `匿名回覆 ${run}：我畢業後仍在探索，也願意分享。`;
const checks = [], errors = [], foreignRequests = [];
const check = (name,value) => {assert.ok(value,name); checks.push(name); console.log('PASS',name);};
let browser;
async function contract(page) {return page.evaluate(()=>JSON.parse(window.LittleWorldAccountBridge.stateJSON()));}
async function ready(page,identity) {await page.waitForFunction(role=>{const s=JSON.parse(window.LittleWorldAccountBridge.stateJSON());return s.user?.profileReady&&(!role||s.user.identity===role);},identity,{timeout:30000});return contract(page);}
async function frame(page,route) {await page.waitForFunction(route=>Array.from(document.querySelectorAll('iframe')).some(el=>{try{return Array.from(el.contentDocument.querySelectorAll('iframe')).some(child=>child.contentWindow.location.pathname===route);}catch{return false;}}),`/admissions/${route}/`); return page.frames().find(f=>{try{return new URL(f.url()).pathname===`/admissions/${route}/`;}catch{return false;}});}
async function makePage() {
  const context=await browser.newContext({viewport:{width:1366,height:1000}}), page=await context.newPage();
  page.on('pageerror',error=>errors.push(error.message));
  await context.route('**/*',route=>{
    const url=new URL(route.request().url());
    if (url.pathname==='/admissions/e2e-parent/' && url.origin===origin) return route.fulfill({contentType:'text/html',body:`<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><body><canvas id="canvas"></canvas><script>${bridge}</script><script>window.qaMessages=[];addEventListener('message',event=>{if(event.origin===location.origin&&event.data?.channel==='starpath-account')qaMessages.push(event.data)});LittleWorldAccountBridge.open('account');</script></body></html>`});
    if (/^https?:$/.test(url.protocol)&&!['127.0.0.1','localhost'].includes(url.hostname)) {foreignRequests.push(url.origin+url.pathname); return route.abort();}
    return route.continue();
  });
  await page.goto(origin+'/admissions/e2e-parent/'); await frame(page,'account');
  return page;
}
async function register(page,email,nickname,role) {
  const account=await frame(page,'account');
  await account.getByRole('button',{name:'建立帳號',exact:true}).click();
  await account.getByLabel('公開暱稱',{exact:true}).fill(nickname);
  await account.getByLabel('電子信箱',{exact:true}).fill(email);
  await account.locator('input[type="password"]').fill(password);
  await account.getByRole('radio',{name:role,exact:true}).check();
  await account.locator('form').getByRole('button',{name:'建立帳號',exact:true}).click();
  return ready(page);
}
async function signIn(page,email) {
  await page.evaluate(()=>LittleWorldAccountBridge.open('account'));
  const account=await frame(page,'account');
  await account.getByLabel('電子信箱',{exact:true}).fill(email);
  await account.locator('input[type="password"]').fill(password);
  await account.locator('form').getByRole('button',{name:'登入',exact:true}).click();
  return ready(page);
}
async function signOut(page) {
  await page.evaluate(()=>LittleWorldAccountBridge.open('account'));
  const account=await frame(page,'account'); await account.getByRole('button',{name:'登出',exact:true}).click();
  await page.waitForFunction(()=>JSON.parse(LittleWorldAccountBridge.stateJSON()).user===null);
}
async function openForum(page,context) {
  await page.evaluate(context=>LittleWorldAccountBridge.openForum(JSON.stringify(context)),context);
  await page.waitForFunction(context=>Array.from(document.querySelectorAll('iframe')).some(host=>{try{return Array.from(host.contentDocument.querySelectorAll('iframe')).some(child=>{const url=new URL(child.contentWindow.location.href);return url.pathname==='/admissions/forum/'&&Object.entries(context).every(([key,value])=>url.searchParams.get(key)===(value===true?'1':String(value)));});}catch{return false;}}),context);
  const forum=page.frames().find(f=>{try{const url=new URL(f.url());return url.pathname==='/admissions/forum/'&&Object.entries(context).every(([key,value])=>url.searchParams.get(key)===(value===true?'1':String(value)));}catch{return false;}});
  await forum.locator('.forum-heading').waitFor(); return forum;
}
async function gardenPage(page,zone) {
  const state=await contract(page),requestId='qa_'+Math.random().toString(36).slice(2);
  await page.evaluate(command=>LittleWorldAccountBridge.requestForumPage(JSON.stringify(command)),{requestId,sessionGeneration:state.sessionGeneration,zone,direction:'first'});
  const packets=[];
  for(let i=0;i<80;i++) {packets.push(...await page.evaluate(()=>JSON.parse(LittleWorldAccountBridge.pollForumMessagesJSON())));if(packets.some(p=>p.type==='page-end'||p.type==='page-error'))break; await page.waitForTimeout(100);}
  assert.ok(packets.some(p=>p.type==='page-end'),'real Firestore page must end successfully');return packets;
}
(async()=>{
  const config=await fetch(origin+'/admissions/firebase-config.json').then(r=>r.json());
  assert.equal(config.useEmulators,true); assert.equal(config.projectId,'demo-starpath-tests');
  browser=await chromium.launch({channel:'chrome',headless:true});
  const a=await makePage(), b=await makePage();
  try {
    check('Initial game-facing contract remains signed out',(await contract(a)).user===null);
    const first=await register(a,alice,'測試小星','大學生');
    check('Register + selected identity produces a confirmed game-facing profile',first.user.identity==='university'&&first.user.profileReady);
    check('Public contract exposes no UID/email/token',!/(uid|email|token)/i.test(JSON.stringify(first.user)));
    const account=await frame(a,'account');
    for(const [identity,label] of [['high_school','高中生'],['graduate','畢業生'],['professional','社會人士'],['university','大學生']]) {
      await account.getByRole('radio',{name:label,exact:true}).check();
      await account.getByRole('button',{name:'儲存身分',exact:true}).click();
      await ready(a,identity);
    }
    check('All four identities save through real Firestore and update host state',true);
    await account.getByLabel('公開暱稱',{exact:true}).fill('湖畔小星');await account.getByRole('button',{name:'儲存身分',exact:true}).click();
    await a.waitForFunction(()=>JSON.parse(LittleWorldAccountBridge.stateJSON()).user?.displayName==='湖畔小星');
    let forum=await openForum(a,{zone:'campus',compose:true});
    await forum.getByRole('button',{name:/裝置 \d+ · 在此留言/}).first().click();
    forum=await frame(a,'forum');
    await forum.getByLabel('主留言',{exact:true}).fill(mainBody);await forum.getByRole('button',{name:'發布主留言',exact:true}).click();
    await forum.locator('.forum-detail').getByText(mainBody,{exact:true}).waitFor();
    const packets=await gardenPage(a,'campus'),row=packets.find(p=>p.type==='page-item'&&p.preview.includes(run));assert.ok(row);
    const threadId=row.threadId;
    check('Main post appears on real garden page with indexed public preview',row.index>=0&&row.index<8&&row.authorName==='湖畔小星'&&row.identity==='university');
    check('Every garden packet respects UTF-8 byte and preview limits',packets.every(p=>Buffer.byteLength(JSON.stringify(p))<=4096)&&Array.from(row.preview).length<=120);
    await a.screenshot({path:path.join(output,'forum-main-post.png')});
    await register(b,bob,'畢業旅人','畢業生');
    forum=await openForum(b,{zone:'campus',threadId});
    await forum.locator('.forum-detail').getByText(mainBody,{exact:true}).waitFor();
    check('Another account cannot see root edit/delete controls',await forum.locator('.forum-detail').getByRole('button',{name:'編輯',exact:true}).count()===0);
    await forum.getByLabel('回覆這則留言',{exact:true}).fill(replyBody);await forum.getByLabel('匿名回覆（仍顯示目前身分）').check();
    await forum.getByRole('button',{name:'送出回覆',exact:true}).click();await forum.locator('.forum-replies article').getByText(replyBody,{exact:true}).waitFor();
    check('Anonymous reply retains graduate role',await forum.locator('.forum-replies article').getByText('匿名',{exact:true}).count()===1&&await forum.locator('.forum-replies article').getByText('畢業生',{exact:true}).count()===1);
    await b.screenshot({path:path.join(output,'forum-anonymous-reply.png')});
    const bobGeneration=(await contract(b)).sessionGeneration;await signOut(b);const switched=await signIn(b,alice);
    check('Sign-out/login changes epoch and restores the correct account profile',switched.sessionGeneration>bobGeneration&&switched.user.displayName==='湖畔小星');
    forum=await openForum(b,{zone:'campus',threadId});await forum.locator('.forum-detail').getByRole('button',{name:'編輯',exact:true}).click();
    const edited=`已由原作者修訂 ${run}`;await forum.locator('.forum-detail textarea').fill(edited);await forum.getByRole('button',{name:'儲存',exact:true}).click();
    await forum.locator('.forum-detail').getByText(edited,{exact:true}).waitFor();check('Original author can edit root after account switch',true);
    await forum.locator('.forum-detail').getByRole('button',{name:'刪除',exact:true}).click();await forum.getByRole('button',{name:'確認刪除',exact:true}).click();
    await forum.locator('.forum-detail').getByText('這則留言已由作者刪除。',{exact:true}).waitFor();
    check('Root tombstone preserves existing reply and prevents new replies',await forum.getByText(replyBody,{exact:true}).count()===1&&await forum.getByLabel('回覆這則留言',{exact:true}).count()===0);
    await signOut(a);await signIn(a,bob);forum=await openForum(a,{zone:'campus',threadId});
    await forum.locator('.forum-replies article').getByRole('button',{name:'編輯',exact:true}).click();await forum.locator('.forum-replies textarea').fill('回覆作者修訂 '+run);await forum.getByRole('button',{name:'儲存',exact:true}).click();
    await forum.getByText('回覆作者修訂 '+run,{exact:true}).waitFor();
    await forum.locator('.forum-replies article').getByRole('button',{name:'刪除',exact:true}).click();await forum.getByRole('button',{name:'確認刪除',exact:true}).click();
    await forum.locator('.forum-replies article').getByText('這則留言已由作者刪除。',{exact:true}).waitFor();check('Reply author can edit and tombstone own reply',true);
    await a.setViewportSize({width:390,height:844});
    check('Mobile forum remains within viewport',await forum.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth));
    await a.screenshot({path:path.join(output,'forum-mobile-tombstones.png'),fullPage:true});
    check('No page errors or production network requests',errors.length===0&&foreignRequests.length===0);
    const report={passed:true,backend:'real local Firebase Auth + Firestore emulators',origin,projectId:config.projectId,checks,errors,foreignRequests,accounts:{alice,bob,password},threadId};
    fs.writeFileSync(path.join(output,'emulator-browser-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
  } catch(error) {
    await a.screenshot({path:path.join(output,'emulator-failure-a.png'),fullPage:true});await b.screenshot({path:path.join(output,'emulator-failure-b.png'),fullPage:true});
    fs.writeFileSync(path.join(output,'emulator-browser-failure.json'),JSON.stringify({checks,errors,foreignRequests,error:String(error),accounts:{alice,bob}},null,2));throw error;
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
