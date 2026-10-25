/* Actual integrated UIs against isolated owner-scoped fixture repositories; no production accounts. */
const { chromium } = require('playwright');
const { createServer } = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const publicRoot = path.join(root, 'admissions-site/public');
function fixture() {
  const clone = value => JSON.parse(JSON.stringify(value));
  const empty = () => ({ userOverrides: {}, customWords: {}, hiddenWordIds: [], userFolders: {}, settings: {} });
  const a = empty(); a.customWords.c_private = { english: 'aliceprivateword', meanings: [{ partOfSpeech: 'noun', definitions: ['A 的私人單字'] }], isWrong: true, folderIds: [], lessonIds: [] };
  const records = { alice: { state: a, revision: 1 }, bob: { state: empty(), revision: 0 } }, go = {};
  let user = { uid: 'alice', email: 'alice@example.test' }; const listeners = new Set();
  const runtime = { auth: { currentUser: user }, observeUser(next) { listeners.add(next); next(user); return () => listeners.delete(next); },
    requestSignOut: async () => window.setFixtureUser(null),
    wordking(uid) { return { list: async () => [{ id: 'main', label: '星途單字庫' }], forApp() { return {
      load: async () => ({ snapshot: clone(records[uid].state), revision: records[uid].revision, recovery: null }),
      save: async (_old, next, _user, options) => { if (uid !== user?.uid) throw new Error('stale owner'); if (options.expectedRevision !== records[uid].revision) throw new Error('conflict'); records[uid].state = clone(next); return { revision: ++records[uid].revision }; },
      subscribe: () => () => {}, exportRecovery: async () => null,
    }; } }; },
    progress(uid) { return { loadGo: async () => clone(go[uid] || { state: null, revision: 0 }),
      saveGo: async (value, revision) => { if (uid !== user?.uid) throw new Error('stale owner'); if ((go[uid]?.revision || 0) !== revision) throw new Error('conflict'); go[uid] = { state: clone(value), revision: revision + 1 }; return { revision: revision + 1 }; },
      importGo: async () => { throw new Error('not used in fixture'); } }; }
  };
  window.setFixtureUser = uid => { user = uid ? { uid, email: `${uid}@example.test` } : null; runtime.auth.currentUser = user; for (const next of listeners) next(user); };
  window.fixtureRecords = records; window.fixtureGo = go; window.__starPathFirebase = Promise.resolve(runtime);
  window.StarPathHost = { navigate() {} };
}
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json', '.css': 'text/css', '.mp3': 'audio/mpeg' };
const server = createServer((request, response) => {
  const url = new URL(request.url, 'http://localhost');
  if (url.pathname === '/admissions/host/') { response.setHeader('Content-Type', mime['.html']); response.end(`<!doctype html><html><body style="margin:0"><script>(${fixture.toString()})();</script><iframe id="child" style="border:0;width:100vw;height:100vh" src="/admissions/wordking-app/index.html"></iframe></body></html>`); return; }
  const file = path.resolve(publicRoot, '.' + decodeURIComponent(url.pathname.replace(/^\/admissions/, '')));
  if (!file.startsWith(publicRoot + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { response.writeHead(404); response.end('missing'); return; }
  response.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream'); response.end(fs.readFileSync(file));
});
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/admissions/host/`;
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } }); const page = await context.newPage();
  const errors = [], foreignRequests = []; page.on('pageerror', error => errors.push(error.message));
  await context.route('**/*', route => { const target = route.request().url(); if (/^https?:/.test(target) && !target.startsWith(new URL(url).origin)) { foreignRequests.push(target); return route.abort(); } return route.continue(); });
  try {
    await page.goto(url); let frame = page.frames().find(frame => frame.url().includes('/wordking-app/'));
    await frame.waitForFunction(() => window.state?.words.some(word => word.english === 'aliceprivateword'));
    assert.equal(await frame.evaluate(() => state.words.find(word => word.english === 'aliceprivateword').isWrong), true);
    await page.evaluate(() => setFixtureUser('bob'));
    await frame.waitForFunction(() => document.getElementById('user-email').textContent.includes('bob'));
    assert.equal(await frame.evaluate(() => state.words.some(word => word.english === 'aliceprivateword')), false);
    await page.evaluate(() => setFixtureUser('alice'));
    await frame.waitForFunction(() => window.state?.words.some(word => word.english === 'aliceprivateword'));
    await page.setViewportSize({ width: 390, height: 844 });
    const overflow = await frame.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
    assert.equal(overflow, false, 'mobile WordKing must fit viewport');
    const deliverables = path.join(root, 'deliverables/shared-games'); fs.mkdirSync(deliverables, { recursive: true });
    await page.screenshot({ path: path.join(deliverables, 'wordking-mobile.png'), fullPage: true });
    await page.setViewportSize({ width: 1280, height: 900 });
    // Old ownerless local save remains untouched and must not be auto-imported by cloud mode.
    await page.evaluate(() => { localStorage.setItem('songfeng-go-v1', '{"legacy":"untouched"}'); document.getElementById('child').src = '/admissions/games/go/index.html?starpath=1'; });
    await page.waitForTimeout(100); frame = page.frames().find(frame => frame.url().includes('/games/go/'));
    await frame.locator('#new-submit').waitFor();
    await frame.locator('input[name="mode"][value="local"]').check(); await frame.locator('#new-submit').click();
    await frame.locator('#board-input button').nth(40).click();
    await page.waitForFunction(() => fixtureGo.alice?.state?.game?.moveNumber === 1);
    assert.equal(await page.evaluate(() => localStorage.getItem('songfeng-go-v1')), '{"legacy":"untouched"}');
    await page.screenshot({ path: path.join(deliverables, 'go-cloud.png') });
    await page.evaluate(() => setFixtureUser('bob'));
    await frame.waitForFunction(() => !document.getElementById('setup-view').hidden && document.getElementById('continue-card').hidden);
    assert.equal(await page.evaluate(() => !!fixtureGo.bob), false);
    await page.evaluate(() => setFixtureUser('alice'));
    await frame.waitForFunction(() => !document.getElementById('continue-card').hidden);
    assert.equal(await frame.locator('#continue-summary').innerText().then(text => text.includes('第 1 手')), true);
    await page.evaluate(() => setFixtureUser(null));
    await frame.getByText('請先登入星途帳號。', { exact: true }).waitFor();
    assert.deepEqual(errors, []); assert.deepEqual(foreignRequests, []);
    const report = { passed: true, checks: ['WordKing A/B/A private state and isWrong', 'WordKing 390px width', 'Go move cloud save', 'old local save untouched', 'Go A/B/A isolation', 'sign-out gate', 'no original Firebase/CDN requests'], errors, foreignRequests };
    fs.writeFileSync(path.join(deliverables, 'browser-checks.json'), JSON.stringify(report, null, 2)); console.log(JSON.stringify(report));
  } finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
