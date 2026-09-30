const { chromium } = require('playwright');
const path = require('node:path');
const fs = require('node:fs');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
 const errors=[]; const states=[];
 try {
  const page=await browser.newPage({viewport:{width:1200,height:800}});
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('response',r=>{if(r.status()>=400&&!r.url().endsWith('/favicon.ico')) errors.push(r.status()+' '+r.url());});
  page.on('console',m=>{if(m.type()==='error'&&!m.text().startsWith('Failed to load resource:')) errors.push(m.text());console.log(m.text());});
  await page.goto('http://127.0.0.1:8765/index.html#review-district-0');
  await page.waitForFunction(()=>window.planetWorldReady===true,null,{timeout:240000});
  for (const name of ['district-0','district-1','district-2','district-3','district-4','district-5','ecology-0','ecology-3','ecology-4','ecology-5']) {
   await page.evaluate(name=>location.hash='review-'+name,name);
   await page.waitForTimeout(2200);
   await page.screenshot({path:path.resolve(__dirname,'../deliverables/'+name+'.png'),timeout:60000});
   console.log('CAPTURED',name);
  }
  await page.evaluate(()=>location.hash='');
  await page.waitForTimeout(1200);
  await page.waitForFunction(()=>window.planetWorldState?.overview===true);
  let before=await page.evaluate(()=>window.planetWorldState);
  await page.mouse.move(850,320); await page.mouse.down({button:'right'});
  await page.mouse.move(960,355,{steps:6}); await page.mouse.up({button:'right'});
  await page.waitForFunction(yaw=>Math.abs(window.planetWorldState.yaw-yaw)>.05,before.yaw,{timeout:90000});
  states.push({step:'RMB orbit',...await page.evaluate(()=>window.planetWorldState)});
  await page.screenshot({path:path.resolve(__dirname,'../deliverables/biome-world-overview.png'),timeout:60000});
  await page.locator('#canvas').focus(); await page.keyboard.press('Tab'); await page.keyboard.press('Home');
  await page.waitForTimeout(1000);
  before=await page.evaluate(()=>window.planetWorldState);
  await page.keyboard.down('w'); await page.waitForTimeout(1400); await page.keyboard.up('w');
  await page.waitForTimeout(600);
  let walked=await page.evaluate(()=>window.planetWorldState);
  if(Math.hypot(...walked.position.map((x,i)=>x-before.position[i]))<.3) throw new Error('Browser walk did not advance');
  states.push({step:'walk',...walked});
  await page.keyboard.press('Home'); await page.waitForTimeout(800); await page.keyboard.press('e');
  await page.waitForFunction(()=>window.planetWorldState?.paused&&!window.planetWorldState?.visible,null,{timeout:90000});
  states.push({step:'entry',...await page.evaluate(()=>window.planetWorldState)});
  await page.keyboard.press('Escape');
  await page.waitForFunction(()=>!window.planetWorldState?.paused&&window.planetWorldState?.visible,null,{timeout:90000});
  states.push({step:'return',...await page.evaluate(()=>window.planetWorldState)});
  console.log('ECOLOGY_BROWSER_CONTROLS_OK',JSON.stringify(states));
  fs.writeFileSync(path.resolve(__dirname,'../deliverables/ecology-browser-review.json'),JSON.stringify({checked_at:new Date().toISOString(),errors,states},null,2));
  if(errors.some(e=>!e.includes('404'))) process.exitCode=1;
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
