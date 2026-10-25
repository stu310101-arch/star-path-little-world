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
    await register(a,alice,'裝置測試甲','高中生'); await register(b,bob,'裝置測試乙','大學生');
    let af=await openForum(a,{zone:'major',compose:true});
    for(let group=0;group<100;group++) {
      await af.getByRole('status').waitFor({state:'hidden'});
      if(await af.getByRole('button',{name:/裝置 \d+ · 在此留言/}).count()>=2) break;
      await af.getByRole('button',{name:'下一組裝置',exact:true}).click();
    }
    await af.getByRole('button',{name:/裝置 \d+ · 在此留言/}).first().click();
    af=await frame(a,'forum'); await af.getByLabel('主留言',{exact:true}).waitFor();
    const deviceId=new URL(af.url()).searchParams.get('deviceId'); assert.ok(deviceId?.startsWith('SPDEVMA'));
    const devicePage=Number(deviceId.slice(7,19));
    let bf=await openForum(b,{zone:'major',deviceId}); await bf.getByLabel('主留言',{exact:true}).waitFor();
    check('Both players open the same empty device directly, ready to compose',true);
    await af.getByLabel('主留言',{exact:true}).fill(mainBody); await bf.getByLabel('主留言',{exact:true}).fill('保留我的競爭草稿 '+run);
    await af.getByRole('button',{name:'發布主留言',exact:true}).click(); await af.locator('.forum-detail').getByText(mainBody,{exact:true}).waitFor();
    check('Empty device accepts exactly one root and changes to its own discussion',true);
    await bf.getByRole('button',{name:'發布主留言',exact:true}).click(); await bf.getByRole('alert').getByText(/不能覆蓋/).waitFor();
    check('A stale second composer cannot overwrite the device and retains its draft',await bf.locator('textarea').evaluateAll(nodes=>nodes.some(node=>node.value.includes('競爭草稿'))));
    await bf.getByRole('button',{name:'重新讀取',exact:true}).click(); await bf.locator('.forum-detail').getByText(mainBody,{exact:true}).waitFor();
    check('Reloading an occupied device opens the original post and retains unsent draft',await bf.getByText('尚未發布的草稿',{exact:true}).count()===1);
    await bf.getByLabel('回覆這則留言',{exact:true}).fill(replyBody); await bf.getByRole('button',{name:'送出回覆',exact:true}).click(); await bf.locator('.forum-replies article').getByText(replyBody,{exact:true}).waitFor();
    check('Another player replies beneath this device without root edit rights',await bf.locator('.forum-detail').getByRole('button',{name:'編輯',exact:true}).count()===0);
    async function fixedPage(page,zone){
      let result;
      for(let group=0;group<=devicePage;group++) {
      const state=await contract(page),requestId='devices_'+Math.random().toString(36).slice(2);
      await page.evaluate(c=>LittleWorldAccountBridge.requestForumPage(c),{zone,requestId,sessionGeneration:state.sessionGeneration,direction:group===0?'first':'next',devices:true});
      const packets=[];
      for(let i=0;i<100;i++){packets.push(...await page.evaluate(()=>JSON.parse(LittleWorldAccountBridge.pollForumMessagesJSON())));if(packets.some(p=>p.type==='page-end'||p.type==='page-error'))break;await page.waitForTimeout(100);}
      assert.equal(packets.at(-1).type,'page-end');result=packets;
      }
      return result;
    }
    const packets=await fixedPage(a,'major'), row=packets.find(p=>p.threadId===deviceId);
    check('Garden receives one public record in the exact physical slot',row.type==='page-item'&&row.index===Number(deviceId.slice(-1))&&row.preview.includes(run));
    check('Empty devices keep explicit independent addresses',packets.filter(p=>['page-item','page-empty'].includes(p.type)).length===8);
    const next=packets.find(p=>p.type==='page-empty'); assert.ok(next,'Need second empty QA device');
    af=await openForum(a,{zone:'major',deviceId:next.threadId}); await af.getByLabel('主留言',{exact:true}).fill('另一座裝置 '+run);await af.getByRole('button',{name:'發布主留言',exact:true}).click(); await af.locator('.forum-detail').getByText('另一座裝置 '+run,{exact:true}).waitFor();
    const after=await fixedPage(a,'major');
    check('Posting to another device never moves or replaces the first post',after.find(p=>p.threadId===deviceId)?.index===row.index&&after.find(p=>p.threadId===deviceId)?.preview===row.preview);
    af=await openForum(a,{zone:'major',deviceId});await af.locator('.forum-detail').getByRole('button',{name:'編輯',exact:true}).click();await af.getByLabel('編輯內容',{exact:true}).fill('原裝置修訂 '+run);await af.getByRole('button',{name:'儲存',exact:true}).click();await af.locator('.forum-detail p.forum-body').getByText('原裝置修訂 '+run,{exact:true}).waitFor();
    check('Owner editing preserves the device and its replies',await af.locator('.forum-replies article').getByText(replyBody,{exact:true}).count()===1);
    await a.screenshot({path:path.join(output,'independent-device-desktop.png')});
    await a.setViewportSize({width:390,height:844}); check('Device UI fits mobile viewport',await af.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth));
    await a.screenshot({path:path.join(output,'independent-device-mobile.png'),fullPage:true});
    check('No browser errors or production data requests',errors.length===0&&foreignRequests.length===0);
    const report={passed:true,backend:'real local Firebase emulators',checks,errors,foreignRequests,devices:[deviceId,next.threadId]};
    fs.writeFileSync(path.join(output,'independent-device-browser.json'),JSON.stringify(report,null,2)); console.log(JSON.stringify(report));
  }catch(error){await a.screenshot({path:path.join(output,'independent-device-failure.png'),fullPage:true});await b.screenshot({path:path.join(output,'independent-device-failure-b.png'),fullPage:true});console.log('B UI:',await (await frame(b,'forum')).locator('body').innerText());throw error;}
  finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
