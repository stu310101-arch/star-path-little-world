// Run against the local Web export. Uses installed Chrome and Edge, not a mock renderer.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const output = path.resolve(__dirname, '../deliverables');
  const channels = process.env.PLANET_BROWSERS?.split(',') || ['chrome', 'msedge'];
  const resultPath = path.join(output, 'browser-checks.json');
  const results = process.env.PLANET_BROWSERS && fs.existsSync(resultPath) ? JSON.parse(fs.readFileSync(resultPath)).filter(r => !channels.includes(r.channel)) : [];
  for (const channel of channels) {
    console.log('Starting', channel);
    const browser = await chromium.launch({ channel, headless: true });
    let page;
    try {
    page = await browser.newPage({ viewport: { width: 960, height: 600 } });
    page.setDefaultTimeout(90000);
    const errors = [];
    const messages = [];
    page.on('pageerror', e => errors.push(String(e)));
    page.on('console', msg => {
      messages.push(msg.text());
      console.log(channel, msg.type(), msg.text());
      if (msg.type() === 'error' && !msg.text().startsWith('Failed to load resource:')) errors.push(msg.text());
    });
    page.on('response', response => {
      if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) errors.push(`${response.status()} ${response.url()}`);
    });
    const started = Date.now();
    await page.goto('http://127.0.0.1:8765/index.html', { waitUntil: 'domcontentloaded' });
    try {
      await page.waitForFunction(() => window.planetWorldReady === true, null, { timeout: 240000 });
    } catch (error) {
      console.log('LOAD_FAILURE', await page.locator('body').innerText({timeout:5000}).catch(()=>''));
      await page.screenshot({path:path.join(output, `web-${channel}-failure.png`),timeout:5000}).catch(()=>{});
      await browser.close();
      throw error;
    }
    await page.waitForFunction(() => window.planetWorldState?.overview === true);
    const states = [];
    const state = async label => { const value = await page.evaluate(() => window.planetWorldState); states.push({label,...value}); console.log(label,JSON.stringify(value)); return value; };
    await state('overview');
    const beforeOrbit = await state('before-right-drag');
    await page.mouse.move(700,280);
    await page.mouse.down({button:'right'});
    await page.mouse.move(800,320,{steps:8});
    await page.waitForFunction(yaw => Math.abs(window.planetWorldState.yaw-yaw)>0.1,beforeOrbit.yaw);
    await page.mouse.up({button:'right'});
    await page.waitForFunction(() => window.planetWorldState.dragging === false);
    await state('overview-right-drag');
    await page.screenshot({ path: path.join(output, `web-${channel}-overview.png`) });
    // Give the canvas keyboard focus; Tab switches to the character camera.
    await page.locator('#canvas').focus();
    await page.keyboard.press('Tab');
    await page.waitForFunction(() => window.planetWorldState?.overview === false);
    const beforeNear = await state('before-near-right-drag');
    await page.mouse.move(650,280);
    await page.mouse.down({button:'right'});
    await page.mouse.move(730,320,{steps:8});
    await page.waitForFunction(pitch => Math.abs(window.planetWorldState.near_pitch-pitch)>0.04,beforeNear.near_pitch);
    await page.mouse.up({button:'right'});
    await page.waitForFunction(() => window.planetWorldState.dragging === false);
    await state('near-right-drag');
    await page.keyboard.press('Home');
    await page.waitForTimeout(700);
    const before = await state('before-walk');
    await page.keyboard.down('w');
    await page.waitForFunction(() => window.planetWorldState?.animation === 'Walk');
    await page.waitForTimeout(700);
    const walked = await state('walking');
    await page.keyboard.up('w');
    if (Math.hypot(...walked.position.map((x,i)=>x-before.position[i])) < 0.1) throw new Error('Walking did not advance');
    // Reset away from the building before testing a separate run. Walking
    // continuously toward the entrance eventually reaches its wall.
    await page.keyboard.press('Home');
    await page.waitForTimeout(700);
    await page.keyboard.down('Shift');
    await page.keyboard.down('s');
    await page.waitForFunction(() => window.planetWorldState?.animation === 'Run');
    await state('running');
    await page.keyboard.up('s');
    await page.keyboard.up('Shift');
    await page.screenshot({ path: path.join(output, `web-${channel}-character.png`) });
    await page.keyboard.press('Home');
    await page.waitForTimeout(1000);
    const beforeEntry = await state('before-entry');
    await page.keyboard.press('e');
    await page.waitForFunction(() => window.planetWorldState?.entering === true);
    await state('entry-jump');
    await page.waitForFunction(() => window.planetWorldState?.paused === true && !window.planetWorldState.entering && !window.planetWorldState.visible);
    const paused = await state('paused');
    await page.keyboard.press('Escape');
    await page.waitForFunction(() => window.planetWorldState?.paused === false);
    const resumed = await state('resumed');
    if (!resumed.visible) throw new Error('Character stayed hidden after returning');
    if (Math.hypot(...resumed.position.map((x,i)=>x-beforeEntry.position[i])) > 0.03) throw new Error('Entry return changed saved position');
    await page.setViewportSize({ width: 1024, height: 720 });
    await page.keyboard.press('Tab');
    await page.waitForTimeout(600);
    await page.screenshot({ path: path.join(output, `web-${channel}-1024.png`) });
    const fatal = errors.filter(e => !e.includes('favicon.ico'));
    results.push({ channel, checked_at: new Date().toISOString(), ready: true, elapsed_ms: Date.now() - started, errors: fatal, states, messages });
    fs.writeFileSync(path.join(output, 'browser-checks.json'), JSON.stringify(results, null, 2));
    } catch (error) {
      if (page) console.log('FAILURE_STATE', await page.evaluate(() => window.planetWorldState).catch(()=>null));
      throw error;
    } finally { await browser.close(); }
  }
  fs.writeFileSync(path.join(output, 'browser-checks.json'), JSON.stringify(results, null, 2));
  console.log(JSON.stringify(results, null, 2));
  if (results.some(r => r.errors.length)) process.exitCode = 1;
})().catch(e => { console.error(e); process.exit(1); });
