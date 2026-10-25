const test = require('node:test');
const assert = require('node:assert/strict');
const {createHash, webcrypto} = require('node:crypto');
const {gzipSync} = require('node:zlib');
const {install} = require('./web_chunk_delivery.js');
const {install: installBoot} = require('./web_boot_delivery.js');
const sha = value => createHash('sha256').update(value).digest('hex');

function fixture(options = {}) {
  const base = 'https://game.example/world/';
  const name = options.mobile ? 'mobile/index.wasm' : 'index.wasm';
  const original = Buffer.from('original Godot wasm with ordered binary data '.repeat(40));
  const manifest = {version: 1, files: {[name]: {bytes: original.length, sha256: sha(original), parts: []}}};
  const routes = new Map(), calls = [], invalidations = [];
  for (let offset = 0; offset < original.length; offset += 321) {
    const data = original.subarray(offset, offset + 321);
    const url = 'chunks/engine.' + sha(data).slice(0,16) + '.' + offset + '.bin';
    manifest.files[name].parts.push({url, bytes: data.length, sha256: sha(data)});
    routes.set(new URL(url, base).href, data);
  }
  const env = {
    location: {href: base + (options.mobile ? 'mobile/index.html' : 'index.html')},
    crypto: webcrypto, ReadableStream, Response, Request, URL,
    navigator: options.noWorker ? {} : {serviceWorker: {controller: {postMessage: data => invalidations.push(data)}}},
  };
  env.fetch = async (input, init) => {
    const url = new URL(typeof input === 'string' ? input : input.url || input.href, env.location.href);
    calls.push({input, url: url.href, init});
    if (options.customFetch) return options.customFetch(url, init, routes, calls);
    const data = routes.get(url.href);
    if (data) {
      if (options.corrupt && (!options.repair || init.cache !== 'reload')) return new Response(Buffer.alloc(data.length));
      if (options.truncate) return new Response(data.subarray(1));
      if (options.oversized) return new Response(Buffer.concat([data, Buffer.from('x')]));
      return new Response(data);
    }
    return new Response('native passthrough', {status: 404});
  };
  return {env, base, name, manifest, original, routes, calls, invalidations, native: env.fetch};
}

test('first visit without a service worker reconstructs ordered parts and original wasm hash', async () => {
  const f = fixture({noWorker: true});
  install(f.manifest, f.env, f.base);
  const response = await f.env.fetch('index.wasm');
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Content-Type'), 'application/wasm');
  assert.equal(response.headers.get('Content-Length'), String(f.original.length));
  assert.equal(response.headers.has('Content-Encoding'), false);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), f.original);
  assert.deepEqual(f.calls.map(c => c.url), [...f.routes.keys()]);
  assert.ok(f.calls.every(c => !c.url.endsWith('index.wasm')));
});

test('unsupported gzip boot delivery retains working native wasm fallback without a service worker', async () => {
  const f = fixture({noWorker: true});
  install(f.manifest, f.env, f.base);
  const files = Object.fromEntries(['index.pck', 'index.wasm'].map(name => [name, {
    url: 'index.boot.' + 'a'.repeat(16) + '.' + name.split('.')[1] + '.gz',
    bytes: f.original.length, sha256: sha(f.original), compressed_bytes: 10,
  }]));
  const boot = installBoot({fileSizes: {'index.pck': f.original.length, 'index.wasm': f.original.length}},
    {version: 1, engine_version: '4.7.2', files}, f.env);
  assert.equal(boot.enabled, false);
  assert.deepEqual(Buffer.from(await (await f.env.fetch('index.wasm')).arrayBuffer()), f.original);
});

test('a failed optional gzip request falls through the boot adapter into verified chunk delivery', async () => {
  const f = fixture({noWorker: true});
  Object.assign(f.env, {DecompressionStream, AbortController, performance, setTimeout, clearTimeout});
  install(f.manifest, f.env, f.base);
  const files = Object.fromEntries(['index.pck', 'index.wasm'].map(name => [name, {
    url: 'index.boot.' + 'b'.repeat(16) + '.' + name.split('.')[1] + '.gz',
    bytes: f.original.length, sha256: sha(f.original), compressed_bytes: 10,
  }]));
  const boot = installBoot({fileSizes: {'index.pck': f.original.length, 'index.wasm': f.original.length}},
    {version: 1, engine_version: '4.7.2', files}, f.env);
  assert.equal(boot.enabled, true);
  const response = await f.env.fetch('index.wasm');
  assert.equal(f.env.planetBootDelivery.files['index.wasm'].phase, 'fallback');
  assert.ok(f.calls[0].url.endsWith('.wasm.gz'));
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), f.original);
  assert.equal(f.calls.length, f.routes.size + 1);
});

test('mobile document resolves root-relative manifest and query URLs from the root script URL', async () => {
  const f = fixture({mobile: true});
  install(f.manifest, f.env, f.base + 'index.chunks.js');
  const response = await f.env.fetch(new URL('mobile/index.wasm?v=current', f.base));
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), f.original);
  assert.ok(f.calls.every(c => c.url.startsWith(f.base + 'chunks/')));
});

test('Request cache, credentials and signal reach each native part request; HEAD needs no downloads', async () => {
  const f = fixture();
  install(f.manifest, f.env, f.base);
  const controller = new AbortController();
  const request = new Request(new URL(f.name, f.base), {cache: 'no-store', credentials: 'omit', signal: controller.signal});
  const response = await f.env.fetch(request);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), f.original);
  assert.ok(f.calls.every(c => c.init.cache === 'no-store' && c.init.credentials === 'omit' && c.init.signal === request.signal));
  const count = f.calls.length;
  const head = await f.env.fetch(request, {method: 'HEAD'});
  assert.equal(head.headers.get('Content-Length'), String(f.original.length));
  assert.equal((await head.arrayBuffer()).byteLength, 0);
  assert.equal(f.calls.length, count);
});

test('pre-aborted and in-flight cancelled requests reject without retry', async () => {
  const f = fixture();
  install(f.manifest, f.env, f.base);
  const cancelled = new AbortController(); cancelled.abort();
  await assert.rejects(f.env.fetch('index.wasm', {signal: cancelled.signal}), {name: 'AbortError'});
  assert.equal(f.calls.length, 0);
  const controller = new AbortController();
  const slow = fixture({customFetch: async () => new Response(new ReadableStream({start() { setTimeout(() => controller.abort(), 5); }}))});
  install(slow.manifest, slow.env, slow.base);
  await assert.rejects(slow.env.fetch('index.wasm', {signal: controller.signal}), {name: 'AbortError'});
  assert.equal(slow.calls.length, 1);
  assert.equal(slow.invalidations.length, 0);
});

test('corrupt cached part is invalidated and retried once with cache reload', async () => {
  const f = fixture({corrupt: true, repair: true});
  install(f.manifest, f.env, f.base);
  assert.deepEqual(Buffer.from(await (await f.env.fetch('index.wasm')).arrayBuffer()), f.original);
  assert.equal(f.calls.length, f.routes.size + 1);
  assert.ok(f.calls.slice(1).every(c => c.init.cache === 'reload'));
  assert.equal(f.invalidations.length, f.routes.size);
  assert.ok(f.invalidations.every(v => v.type === 'little-world-invalidate'));
});

test('private progress callback reports real bytes across parts without being sent to native fetch', async () => {
  const f = fixture(); const progress = [];
  install(f.manifest, f.env, f.base);
  await f.env.fetch('index.wasm', {onLittleWorldDownloadProgress: value => progress.push(value)});
  assert.equal(progress.length, f.routes.size);
  assert.deepEqual(progress.at(-1), {loaded: f.original.length, total: f.original.length});
  assert.ok(progress.every((value, index) => !index || value.loaded > progress[index - 1].loaded));
  assert.ok(f.calls.every(call => !Object.hasOwn(call.init, 'onLittleWorldDownloadProgress')));
});

function fakeClock() {
  let now = 0, nextID = 0; const timers = new Map();
  return {
    now: () => now,
    setTimeout(callback, delay) { const id = ++nextID; timers.set(id, {callback, at: now + delay}); return id; },
    clearTimeout(id) { timers.delete(id); },
    advance(milliseconds) {
      const target = now + milliseconds;
      for (;;) {
        const next = [...timers].filter(([, timer]) => timer.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        now = next[1].at; timers.delete(next[0]); next[1].callback();
      }
      now = target;
    },
    pending: () => timers.size,
  };
}

function slowBootFixture(stalled = false) {
  const clock = fakeClock(), base = 'https://game.example/';
  const original = Buffer.from(Array.from({length: 4096}, (_, index) => (index * 73 + 11) % 256));
  const compressed = gzipSync(original);
  const url = 'index.boot.' + sha(compressed).slice(0,16) + '.pck.gz';
  const parts = [], routes = new Map(), calls = [];
  for (let offset = 0; offset < compressed.length; offset += 150) {
    const data = compressed.subarray(offset, offset + 150), partURL = 'chunks/' + offset + '.bin';
    parts.push({url: partURL, bytes: data.length, sha256: sha(data)});
    routes.set(new URL(partURL, base).href, data);
  }
  const env = {
    location: {href: base + 'index.html'}, crypto: webcrypto, ReadableStream, Response,
    DecompressionStream, AbortController, performance: {now: clock.now},
    setTimeout: clock.setTimeout, clearTimeout: clock.clearTimeout,
    fetch: async (input, init) => {
      const target = new URL(input, base).href; calls.push({url: target, init});
      const data = routes.get(target);
      if (!data) return new Response(original);
      assert.equal(Object.hasOwn(init, 'onLittleWorldDownloadProgress'), false);
      let offset = 0;
      return new Response(new ReadableStream({
        pull(controller) {
          if (stalled) { clock.advance(120001); return; }
          if (offset === data.length) {controller.close(); return;}
          clock.advance(60000);
          const end = Math.min(offset + Math.ceil(data.length / 2), data.length);
          controller.enqueue(data.subarray(offset, end)); offset = end;
        },
      }, {highWaterMark: 0}));
    },
  };
  install({version: 1, files: {[url]: {bytes: compressed.length, sha256: sha(compressed), parts}}}, env, base);
  const files = {
    'index.pck': {url, bytes: original.length, sha256: sha(original), compressed_bytes: compressed.length},
    'index.wasm': {url: 'index.boot.' + 'c'.repeat(16) + '.wasm.gz', bytes: original.length, sha256: sha(original), compressed_bytes: compressed.length},
  };
  installBoot({fileSizes: {'index.pck': original.length, 'index.wasm': original.length}},
    {version: 1, engine_version: '4.7.2', files}, env);
  return {clock, env, original, compressed, calls};
}

test('boot chunk download lasting over 120 seconds succeeds while real network bytes keep arriving', async () => {
  const f = slowBootFixture();
  const response = await f.env.fetch('index.pck');
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), f.original);
  assert.ok(f.clock.now() > 120000);
  const status = f.env.planetBootDelivery.files['index.pck'];
  assert.equal(status.phase, 'ready');
  assert.equal(status.downloadedBytes, f.compressed.length);
  assert.equal(status.downloadTotalBytes, f.compressed.length);
  assert.ok(f.calls.every(call => call.url.includes('/chunks/')));
  assert.equal(f.clock.pending(), 0);
});

test('boot chunk download with no bytes for 120 seconds still aborts and uses the original fallback', async () => {
  const f = slowBootFixture(true);
  const response = await f.env.fetch('index.pck');
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), f.original);
  assert.equal(f.env.planetBootDelivery.files['index.pck'].phase, 'fallback');
  assert.match(f.env.planetBootDelivery.files['index.pck'].fallbackReason, /abort/i);
  assert.equal(f.calls.length, 2);
  assert.ok(f.calls[0].init.signal.aborted);
  assert.ok(f.calls[1].url.endsWith('/index.pck'));
  assert.equal(f.clock.pending(), 0);
});

for (const kind of ['corrupt', 'truncate', 'oversized']) test(kind + ' parts never produce a successful Response', async () => {
  const f = fixture({[kind]: true});
  let responses = 0;
  f.env.Response = class extends Response { constructor(...args) { super(...args); responses++; } };
  install(f.manifest, f.env, f.base);
  await assert.rejects(f.env.fetch('index.wasm'), /checksum|incomplete|length/);
  assert.equal(responses, 0);
  assert.equal(f.calls.length, 2);
});

test('final checksum validates order and identity even when every part hash is correct', async () => {
  const f = fixture(); f.manifest.files[f.name].parts.reverse();
  install(f.manifest, f.env, f.base);
  await assert.rejects(f.env.fetch('index.wasm'), /file checksum/);
  assert.equal(f.calls.length, f.routes.size * 2);
});

test('verified response uses a stream rather than a second BufferSource allocation', async () => {
  const f = fixture(); let handedOff = 0;
  f.env.Response = class extends Response { constructor(body, init) {
    assert.ok(body instanceof ReadableStream); handedOff++; super(body, init);
  }};
  install(f.manifest, f.env, f.base);
  const response = await f.env.fetch('index.wasm');
  assert.equal(handedOff, 1);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), f.original);
});

test('unmatched URLs and methods preserve exact native arguments; restore is safe', async () => {
  const f = fixture(); const installed = install(f.manifest, f.env, f.base);
  const unrelated = new Request(f.base + 'other.pck'); const init = {cache: 'reload'};
  await f.env.fetch(unrelated, init);
  assert.equal(f.calls[0].input, unrelated); assert.equal(f.calls[0].init, init);
  await f.env.fetch('https://another.example/index.wasm');
  await f.env.fetch('index.wasm', {method: 'POST'});
  assert.equal(f.calls.length, 3);
  installed.restore(); assert.equal(f.env.fetch, f.native);
});

test('unsafe paths, inconsistent lengths, excessive parts and oversized parts reject before installing', () => {
  const changes = [
    f => { f.manifest.files['../index.wasm'] = f.manifest.files[f.name]; },
    f => { f.manifest.files[f.name].parts[0].url = 'https://other.example/part'; },
    f => { f.manifest.files[f.name].parts[0].url = 'chunks/%2e%2e/part'; },
    f => { f.manifest.files[f.name].bytes++; },
    f => { f.manifest.files[f.name].parts[0].bytes = 8 * 1024 * 1024 + 1; },
    f => { f.manifest.files[f.name].parts = Array(65).fill(f.manifest.files[f.name].parts[0]); },
  ];
  for (const change of changes) {
    const f = fixture(); change(f);
    assert.throws(() => install(f.manifest, f.env, f.base), /Invalid|length/);
    assert.equal(f.env.fetch, f.native); assert.equal(f.calls.length, 0);
  }
});
