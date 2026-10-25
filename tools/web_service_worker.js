/* Generated configuration is prepended by prepare_web_platform.py.
 * Cache only this release's allowlisted files, with content-addressed keys.
 * Both consumers must pull before another network chunk is read: ordinary
 * Response.clone()/tee() could buffer an entire pack behind a paused game.
 */
'use strict';
function boundedTee(body) {
  const reader = body.getReader();
  const controllers = [], demand = [false, false], cancelled = [false, false];
  let busy = false;
  async function pump() {
    if (busy || !demand.every((value, i) => value || cancelled[i])) return;
    if (cancelled.every(Boolean)) { await reader.cancel().catch(() => {}); return; }
    busy = true;
    try {
      const item = await reader.read();
      for (let i = 0; i < 2; i++) if (!cancelled[i]) {
        demand[i] = false;
        if (item.done) controllers[i].close();
        else controllers[i].enqueue(item.value);
      }
    } catch (error) {
      for (let i = 0; i < 2; i++) if (!cancelled[i]) controllers[i].error(error);
      cancelled.fill(true);
    } finally { busy = false; }
  }
  const branches = [0, 1].map(i => new ReadableStream({
    start(controller) { controllers[i] = controller; },
    pull() { demand[i] = true; return pump(); },
    cancel() { cancelled[i] = true; void pump(); },
  }, {highWaterMark: 0}));
  // Cache.put may reject before reading (quota/private mode). The game must
  // continue even when the browser retains the failed response's stream lock.
  branches.stopStorage = () => {cancelled[1] = true; void pump();};
  return branches;
}
if (typeof module !== 'undefined') module.exports = {boundedTee};
else {
  const scopeURL = new URL(self.registration.scope);
  const cachePrefix = 'little-world-' + encodeURIComponent(scopeURL.pathname) + '-';
  const cacheName = cachePrefix + RELEASE.build_id;
  const cacheKey = file => new URL('__content/' + file.sha256, scopeURL).href;
  const digest = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), v => v.toString(16).padStart(2, '0')).join('');
  const shell = RELEASE.shell;
  const shellKeys = new Set(shell.map(name => cacheKey(RELEASE.files[name])));
  // This allowlist never fetches anything. It protects an optional shared room
  // only once the player has requested and cached its bytes on actual entry.
  const onDemandKeys = new Set(Object.values(RELEASE.shared_on_demand || {}).flat().filter(name => RELEASE.files[name]).map(name => cacheKey(RELEASE.files[name])));
  const byKey = new Map(Object.values(RELEASE.files).map(file => [cacheKey(file), file.bytes]));
  let maintenance = Promise.resolve();
  const pendingWrites = new Map();
  const pinPrefix = new URL('__profiles/', scopeURL).href;
  const pinKey = (renderer, profile) => new URL(`__profiles/${renderer}/${profile}`, scopeURL).href;
  const profileKeys = (renderer, profile) => {
    const names = RELEASE.profiles?.[renderer]?.[profile];
    if (!Array.isArray(names) || names.some(name => !RELEASE.files[name])) throw Error('Unknown resource profile');
    return [...new Set(names.map(name => cacheKey(RELEASE.files[name])))];
  };
  async function pins(cache) {
    const keys = new Set();
    for (const request of await cache.keys()) if (request.url.startsWith(pinPrefix)) {
      const saved = await cache.match(request);
      for (const key of (await saved.json()).keys || []) keys.add(key);
    }
    return keys;
  }
  async function installed(cache, renderer) {
    const status = {};
    for (const profile of Object.keys(RELEASE.profiles?.[renderer] || {})) {
      const keys = profileKeys(renderer, profile);
      status[profile] = keys.length > 0;
      for (const key of keys) if (!await cache.match(key)) {status[profile] = false; break;}
    }
    return status;
  }
  let profileMaintenance = Promise.resolve();
  async function manageProfile(data) {
    const {renderer, profile, action} = data;
    const keys = profileKeys(renderer, profile);
    const cache = await caches.open(cacheName);
    if (action === 'reserve' || action === 'retain') {
      if (action === 'retain') {
        // Godot's SHA verification can finish slightly ahead of Cache.put.
        await Promise.all(keys.map(key => pendingWrites.get(key)));
        for (const key of keys) if (!await cache.match(key)) throw Error('資源未完整快取，儲存空間可能不足');
      }
      await cache.put(pinKey(renderer, profile), new Response(JSON.stringify({keys}), {headers:{'Content-Type':'application/json'}}));
    } else if (action === 'delete') {
      await cache.delete(pinKey(renderer, profile));
      const protectedKeys = await pins(cache);
      for (const key of keys) if (!protectedKeys.has(key) && !shellKeys.has(key) && !onDemandKeys.has(key)) {
        await pendingWrites.get(key);
        await cache.delete(key);
      }
    } else if (action !== 'status') throw Error('Unknown profile action');
    return {ok:true,installed:await installed(cache, renderer)};
  }
  function trim(cache) {
    maintenance = maintenance.catch(() => {}).then(async () => {
      const keys = await cache.keys();
      const retained = await pins(cache);
      let bytes = keys.reduce((sum, key) => sum + (byKey.get(key.url) || 0), 0);
      for (const key of keys) {
        if (bytes <= 128 * 1024 * 1024) break;
        if (shellKeys.has(key.url) || retained.has(key.url) || onDemandKeys.has(key.url) || key.url.startsWith(pinPrefix)) continue;
        await cache.delete(key);
        bytes -= byKey.get(key.url) || 0;
      }
    });
    return maintenance;
  }
  self.addEventListener('install', event => {
    event.waitUntil((async () => {
      const cache = await caches.open(cacheName);
      // All small shell files are verified before the worker can activate.
      // A deployment in flight never creates a mixed offline shell.
      for (const name of shell) {
        const response = await fetch(new URL(name, scopeURL), {cache:'reload'});
        if (!response.ok) throw Error('Shell HTTP ' + response.status);
        const bytes = await response.arrayBuffer();
        const file = RELEASE.files[name];
        if (bytes.byteLength !== file.bytes || await digest(bytes) !== file.sha256) throw Error('Shell changed during deployment');
        await cache.put(cacheKey(file), new Response(bytes, {headers:response.headers}));
      }
    })());
    // Updates wait for existing clients to close; no mid-game skipWaiting.
  });
  self.addEventListener('activate', event => event.waitUntil((async () => {
    for (const name of await caches.keys()) if (name.startsWith(cachePrefix) && name !== cacheName) await caches.delete(name);
    await self.clients.claim();
  })()));
  self.addEventListener('message', event => {
    if (event.data?.type === 'little-world-activate-before-start') {
      event.waitUntil((async () => {
        const clients = await self.clients.matchAll({type:'window',includeUncontrolled:true});
        const games = clients.filter(client => /\/(?:mobile\/)?(?:index\.html)?$/.test(new URL(client.url).pathname));
        if (games.length <= 1) await self.skipWaiting();
      })());
      return;
    }
    if (event.data?.type === 'little-world-profile') {
      const job = profileMaintenance.catch(() => {}).then(() => manageProfile(event.data));
      profileMaintenance = job;
      event.waitUntil(job.then(result => event.ports[0]?.postMessage(result)).catch(error => event.ports[0]?.postMessage({ok:false,error:error.message})));
      return;
    }
    if (event.data?.type !== 'little-world-invalidate') return;
    const url = new URL(event.data.url, scopeURL);
    if (url.origin !== scopeURL.origin || !url.pathname.startsWith(scopeURL.pathname)) return;
    const name = decodeURIComponent(url.pathname.slice(scopeURL.pathname.length));
    const file = RELEASE.files[name];
    if (file) event.waitUntil((async () => {
      const key = cacheKey(file);
      // A consumer can finish hashing before Cache.put finishes its disk write.
      // Delete after that write, so a corrupt response cannot reappear on retry.
      await pendingWrites.get(key);
      return (await caches.open(cacheName)).delete(key);
    })());
  });
  self.addEventListener('fetch', event => {
    const url = new URL(event.request.url);
    if (event.request.method !== 'GET' || url.origin !== scopeURL.origin || !url.pathname.startsWith(scopeURL.pathname)) return;
    let name = decodeURIComponent(url.pathname.slice(scopeURL.pathname.length));
    if (!name || name.endsWith('/')) name += 'index.html';
    const file = RELEASE.files[name];
    if (!file) return;
    // HTML/JS/JSON are network-first: online visits see the current deployment
    // even while an older worker waits for its remaining tabs to close.
    const immutable = /(?:[.-][a-f0-9]{16}\.)/.test(name);
    event.respondWith((async () => {
      let cache;
      try {cache = await caches.open(cacheName);} catch {return fetch(event.request);}
      if (immutable && event.request.cache !== 'reload') {
        const saved = await cache.match(cacheKey(file));
        if (saved) return saved;
      }
      let response;
      try {response = await fetch(event.request);} catch {
        return await cache.match(cacheKey(file)) || new Response('Offline: this area has not been downloaded.', {status:503});
      }
      if (!response.ok || !response.body || !immutable) return response;
      const branches = boundedTee(response.body);
      const [game, storage] = branches;
      const options = {status:response.status, statusText:response.statusText, headers:response.headers};
      const key = cacheKey(file);
      const write = cache.put(key, new Response(storage, options)).then(() => trim(cache)).catch(() => branches.stopStorage());
      pendingWrites.set(key, write);
      event.waitUntil(write.finally(() => {if (pendingWrites.get(key) === write) pendingWrites.delete(key);}));
      return new Response(game, options);
    })());
  });
}
