import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(process.argv[2] || 'build/cloudflare-performance-20261020');
const reportPath = process.argv[3] || 'deliverables/render-budget/public-deployment.json';
const site = path.join(root, 'site');
const stamp = JSON.parse(await readFile(path.join(site, 'index.release.json'), 'utf8'));
const origin = 'https://star-path-little-world.star-path-little-world.workers.dev';
const routes = {
  '/': 'index.html', '/index.release.json': 'index.release.json',
  '/index.js': 'index.js', '/mobile/index.js': 'mobile/index.js',
  '/admissions/host/': 'admissions/host/index.html',
  '/admissions/115/query/': 'admissions/115/query/index.html',
  '/admissions/account/native/': 'admissions/account/native/index.html',
  '/admissions/firebase-config.json': 'admissions/firebase-config.json',
  '/admissions-source.json': 'admissions-source.json', '/mobile/': 'mobile/index.html',
};
const sha = data => createHash('sha256').update(data).digest('hex');
const checks = await Promise.all(Object.entries(routes).map(async ([route, file]) => {
  const response = await fetch(origin + route, {
    signal: AbortSignal.timeout(45000), headers: {'Cache-Control': 'no-cache'},
  });
  assert.equal(response.status, 200, route);
  const actual = sha(Buffer.from(await response.arrayBuffer()));
  assert.equal(actual, sha(await readFile(path.join(site, file))), route);
  const cacheControl = response.headers.get('cache-control');
  const coop = response.headers.get('cross-origin-opener-policy');
  const coep = response.headers.get('cross-origin-embedder-policy');
  if (route.startsWith('/admissions/')) {
    assert.notEqual(coop, 'same-origin');
    assert(!['require-corp', 'credentialless'].includes(coep));
  }
  if (route.endsWith('firebase-config.json')) assert(cacheControl?.includes('no-store'));
  return {route, status: response.status, sha256: actual, cacheControl, coop, coep, passed: true};
}));
const report = {verified_at_utc: new Date().toISOString(), origin, build_id: stamp.build_id, passed: true, checks};
await writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
