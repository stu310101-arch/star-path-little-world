// End-to-end QA: unmodified production Web files and real mouse/keyboard input.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const base = process.argv[2] || 'http://127.0.0.1:8766/';
const out = path.resolve('deliverables/training-room');
fs.mkdirSync(out,{recursive:true});
const report = {errors:[],checks:[],screenshots:[],launch:'Production world -> destination menu -> training room -> chair'};
let browser, page;
const watchdog = setTimeout(async()=>{report.errors.push('Browser QA timeout'); await finish(1);},600000);
async function finish(code) {
  clearTimeout(watchdog);
  fs.writeFileSync(path.join(out,'computer-browser-checks.json'),JSON.stringify(report,null,2));
  if(browser) await browser.close();
  process.exit(code);
}
(async()=>{
  browser = await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
  page = await browser.newPage({viewport:{width:1280,height:720}});
  const gameRequests=[];
  page.on('pageerror',e=>report.errors.push(String(e)));
  page.on('console',m=>{if(m.type()==='error'&&!m.text().startsWith('Failed to load resource:'))report.errors.push(m.text()); if(m.type()==='error'||/READY|Godot/.test(m.text()))console.log('BROWSER',m.text());});
  page.on('response',r=>{if(r.status()>=400&&!r.url().endsWith('/favicon.ico'))report.errors.push(`HTTP ${r.status()}: ${r.url()}`);});
  page.on('request',r=>{if(r.url().includes('/games/'))gameRequests.push(r.url());});
  const state=()=>page.evaluate(()=>window.trainingRoomState);
  const check=(name,value)=>{assert.ok(value,name);report.checks.push(name);console.log('PASS',name);};
  const capture=async name=>{const file=path.join(out,name+'.png');await page.screenshot({path:file,timeout:60000});report.screenshots.push(file);};
  const clickWorldButton=async expression=>{
    for(let attempt=0;attempt<15;attempt++) {
      const buttons=await page.evaluate(()=>window.planetPerformance?.buttons||[]);
      const button=buttons.find(row=>row.visible&&expression.test(row.text));
      const bounds=await page.locator('#canvas').boundingBox();
      const scale=Math.min(bounds.width/1440,bounds.height/900);
      const box={x:bounds.x+(bounds.width-1440*scale)/2,y:bounds.y+(bounds.height-900*scale)/2,width:1440*scale,height:900*scale};
      if(button) {await page.mouse.click(box.x+button.center[0]*box.width,box.y+button.center[1]*box.height);await page.waitForTimeout(600);return;}
      await page.mouse.move(box.x+150*scale,box.y+650*scale);await page.mouse.wheel(0,180);await page.waitForTimeout(600);
    }
    throw Error('Visible world button missing: '+expression);
  };
  const move=async(key,axis,target,increasing)=>{
    await page.keyboard.down(key);
    try { await page.waitForFunction(({axis,target,increasing})=>{
      const at=window.trainingRoomState?.player[axis]; return at!==undefined&&(increasing?at>=target:at<=target);
    },{axis,target,increasing},{timeout:16000}); } finally {await page.keyboard.up(key);}
    await page.waitForTimeout(350);
    console.log('POSITION',JSON.stringify((await state()).player));
  };
  await page.goto(new URL('index.html?performance',base).href,{waitUntil:'domcontentloaded',timeout:60000});
  await page.waitForFunction(()=>window.planetWorldReady&&window.planetPerformance?.buttons,null,{timeout:180000});
  check('Production world is ready',true);
  await clickWorldButton(/選擇目的地/);
  await clickWorldButton(/06.*練功區/);
  await page.waitForFunction(()=>window.planetPerformance?.avatar?.ready&&!window.planetPerformance.preparing_roam&&!window.planetPerformance.player.overview,null,{timeout:120000});
  if(await page.evaluate(()=>window.planetPerformance.destinations_open))await clickWorldButton(/收起目的地/);
  await page.locator('#canvas').focus();
  await page.keyboard.press('e');
  await page.waitForFunction(()=>window.trainingRoomState?.ready,null,{timeout:160000});
  await page.waitForFunction(()=>window.trainingRoomState?.detail_state==='ready',null,{timeout:90000});
  check('Exported room and authored detail meshes ready',true);
  check('Go HTML does not download before entering a game',gameRequests.length===0);
  await page.locator('#canvas').focus();
  await move('w',2,2.0,false);
  await move('a',0,-5.9,false);
  await move('w',2,-1.55,false);
  await page.waitForFunction(()=>window.trainingRoomState?.nearest_target==='gaming_1',null,{timeout:5000});
  check('Approach first chair announces Go',(await state()).prompt.includes('圍棋'));
  await capture('computer-web-approach');
  await page.keyboard.press('f');
  check('Standing cannot launch Go',gameRequests.length===0);
  await page.keyboard.press('e');
  await page.waitForFunction(()=>window.trainingRoomState?.interaction_state==='seated',null,{timeout:10000});
  await capture('computer-web-seated-1280x720');
  await page.setViewportSize({width:1920,height:1080});
  await page.waitForTimeout(600);
  await capture('computer-web-seated-1920x1080');
  await page.setViewportSize({width:1280,height:720});
  await page.keyboard.press('f');
  await page.locator('.lw-computer-game').waitFor({state:'visible'});
  const frame=page.frameLocator('iframe[title="圍棋"]');
  await frame.locator('#new-submit').waitFor({state:'visible',timeout:30000});
  check('Seated F opens the actual embedded Go HTML',gameRequests.length>0);
  await capture('computer-web-go-setup');
  await frame.locator('#new-submit').click();
  await frame.locator('#board-input button').first().click();
  await frame.locator('.move-item').nth(1).waitFor({state:'attached',timeout:30000});
  check('Embedded Go accepts a move and AI replies',await frame.locator('.move-item').count()>=2);
  const moves=await frame.locator('#move-total').innerText();
  await capture('computer-web-go-play');
  await page.keyboard.press('Escape');
  await page.waitForFunction(()=>!window.LittleWorldComputerGames.isOpen()&&!window.trainingRoomState.computer_game_open,null,{timeout:6000});
  check('Iframe Escape returns to the same seated character',(await state()).interaction_state==='seated');
  await page.keyboard.press('f');
  await page.locator('.lw-computer-game').waitFor({state:'visible'});
  check('Reopening preserves the match',await frame.locator('#move-total').innerText()===moves);
  await page.getByRole('button',{name:'返回練功區（Esc）',exact:true}).click();
  await page.waitForFunction(()=>!window.trainingRoomState.computer_game_open);
  await page.keyboard.press('e');
  await page.waitForFunction(()=>window.trainingRoomState.interaction_state==='idle');
  check('Returning then E restores standing exploration',true);
  check('No runtime browser errors',report.errors.length===0);
  await finish(0);
})().catch(async error=>{report.errors.push(String(error.stack||error));console.error(error);if(page){report.lastState=await page.evaluate(()=>({world:window.planetPerformance,room:window.trainingRoomState})).catch(()=>null);await page.screenshot({path:path.join(out,'computer-browser-failure.png'),timeout:15000}).catch(()=>{});}await finish(1);});
