// Real HTTP integration: no service worker, every removed original is restored.
const fs = require('node:fs');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const path = require('node:path');
const {install} = require('./web_chunk_delivery.js');
const base = process.argv[2];
const stampPath = process.argv[3];
if (!base || !stampPath) throw Error('Usage: node check_cloudflare_chunks.cjs URL release.json');
const stamp = JSON.parse(fs.readFileSync(stampPath, 'utf8'));
const requests = [];
const env = {location: {href: new URL('mobile/index.html', base).href}, crypto: globalThis.crypto,
  ReadableStream, Response, fetch: (url, options) => {requests.push(String(url)); return fetch(url, options);}};
install({version: 1, files: stamp.virtual_files}, env, new URL('index.chunks.js', base).href);
const report = {build_id: stamp.build_id, url: base, checks: [], no_service_worker: true};
(async () => {
  for (const [name, info] of Object.entries(stamp.virtual_files)) {
    const response = await env.fetch(new URL(name, base).href);
    assert.equal(response.status, 200);
    const body = new Uint8Array(await response.arrayBuffer());
    assert.equal(body.byteLength, info.bytes);
    assert.equal(crypto.createHash('sha256').update(body).digest('hex'), info.sha256);
    if (name.endsWith('.wasm')) assert.equal(WebAssembly.validate(body), true);
    report.checks.push({name, bytes: body.length, passed: true});
    console.log('PASS restored', name, body.length);
  }
  assert.ok(requests.length > 0 && requests.every(url => new URL(url).pathname.includes('/chunks/')));
  report.passed = true;
})().catch(error => {report.error = String(error.stack); console.error(error); process.exitCode = 1;})
  .finally(() => {
    const out = path.resolve('deliverables/cloudflare'); fs.mkdirSync(out, {recursive: true});
    fs.writeFileSync(path.join(out, 'chunks-' + (new URL(base).hostname === '127.0.0.1' ? 'local' : 'public') + '.json'), JSON.stringify(report, null, 2));
  });
