/* Static-host fallback for files larger than the host's per-file limit.
 * Every part and the complete original are verified before Godot sees a
 * Response: its boot loader cannot reliably report a failed body stream.
 * This works on the first visit and without a controlling service worker.
 */
(function (root) {
  'use strict';
  const MAX_FILE_BYTES = 256 * 1024 * 1024;
  const MAX_PART_BYTES = 8 * 1024 * 1024;
  const safePath = value => typeof value === 'string' &&
    /^[A-Za-z0-9_./-]+$/.test(value) && !value.startsWith('/') &&
    value.split('/').every(segment => segment && segment !== '.' && segment !== '..');
  const validHash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
  const validBytes = (value, maximum) => Number.isSafeInteger(value) && value > 0 && value <= maximum;

  function install(manifest, env = root, baseURL = env.location.href) {
    const pageURL = new URL(env.location.href);
    const base = new URL('./', new URL(baseURL, pageURL));
    if (base.origin !== pageURL.origin) throw Error('Chunk base must have the page origin');
    if (!manifest || manifest.version !== 1 || !manifest.files ||
        typeof manifest.files !== 'object' || Array.isArray(manifest.files) ||
        Object.keys(manifest.files).length > 256) throw Error('Invalid chunk manifest');
    if (!env.crypto?.subtle || !env.ReadableStream || !env.Response || typeof env.fetch !== 'function')
      throw Error('This browser cannot validate the game download');

    const entries = new Map(), partIdentities = new Map();
    for (const [name, file] of Object.entries(manifest.files)) {
      if (!safePath(name) || !file || !validBytes(file.bytes, MAX_FILE_BYTES) || !validHash(file.sha256) ||
          !Array.isArray(file.parts) || !file.parts.length || file.parts.length > 64)
        throw Error('Invalid chunk file metadata');
      let total = 0;
      const parts = file.parts.map(part => {
        if (!part || !safePath(part.url) || !validBytes(part.bytes, MAX_PART_BYTES) || !validHash(part.sha256))
          throw Error('Invalid chunk part metadata');
        total += part.bytes;
        const url = new URL(part.url, base).href;
        const identity = part.bytes + ':' + part.sha256;
        if (partIdentities.has(url) && partIdentities.get(url) !== identity)
          throw Error('Chunk identity differs between files');
        partIdentities.set(url, identity);
        return {url, bytes: part.bytes, sha256: part.sha256};
      });
      if (total !== file.bytes) throw Error('Chunk lengths do not match the original');
      entries.set(new URL(name, base).href, {name, bytes: file.bytes, sha256: file.sha256, parts});
    }
    for (const url of partIdentities.keys()) if (entries.has(url)) throw Error('A chunk cannot name an original file');

    const nativeFetch = env.fetch;
    const digest = async bytes => Array.from(new Uint8Array(await env.crypto.subtle.digest('SHA-256', bytes)),
      value => value.toString(16).padStart(2, '0')).join('');
    function checkAbort(signal) {
      if (!signal?.aborted) return;
      if (typeof signal.throwIfAborted === 'function') signal.throwIfAborted();
      const error = new Error('Download aborted'); error.name = 'AbortError'; throw error;
    }
    function invalidate(file) {
      for (const part of file.parts) {
        try { env.navigator?.serviceWorker?.controller?.postMessage({type: 'little-world-invalidate', url: part.url}); }
        catch { /* Cache permission failures cannot prevent the network retry. */ }
      }
    }
    function downloadOptions(input, init, retry) {
      const options = {method: 'GET'};
      // Original integrity/Range/conditional headers describe the whole file,
      // so they cannot be applied to its independently addressed part requests.
      for (const key of ['signal', 'cache', 'credentials', 'mode', 'redirect', 'referrer', 'referrerPolicy', 'priority']) {
        const value = init && init[key] !== undefined ? init[key] : input?.[key];
        if (value !== undefined) options[key] = value;
      }
      if (retry) options.cache = 'reload';
      return options;
    }
    async function readPart(part, options, progress) {
      checkAbort(options.signal);
      const response = await nativeFetch.call(env, part.url, options);
      checkAbort(options.signal);
      if (response.status !== 200 || !response.body) {
        await response.body?.cancel();
        throw Error('Game chunk download failed (HTTP ' + response.status + ')');
      }
      if (response.url && new URL(response.url).origin !== base.origin) {
        await response.body.cancel();
        throw Error('Game chunk redirected outside this site');
      }
      const bytes = new Uint8Array(part.bytes);
      const reader = response.body.getReader();
      const abortRead = () => { void reader.cancel().catch(() => {}); };
      options.signal?.addEventListener('abort', abortRead, {once: true});
      let offset = 0;
      try {
        for (;;) {
          checkAbort(options.signal);
          const {value, done} = await reader.read();
          checkAbort(options.signal);
          if (done) break;
          if (offset + value.byteLength > bytes.byteLength) throw Error('Game chunk exceeds its expected length');
          bytes.set(value, offset); offset += value.byteLength;
          if (value.byteLength) progress?.(offset);
        }
        if (offset !== part.bytes) throw Error('Game chunk download is incomplete');
        if (await digest(bytes) !== part.sha256) throw Error('Game chunk checksum differs');
        checkAbort(options.signal);
        return bytes;
      } finally {
        options.signal?.removeEventListener('abort', abortRead);
        await reader.cancel().catch(() => {});
        reader.releaseLock();
      }
    }
    async function verifiedBytes(file, options, progress) {
      const bytes = new Uint8Array(file.bytes);
      let offset = 0;
      for (const part of file.parts) {
        const partBytes = await readPart(part, options, loaded => progress?.({loaded: offset + loaded, total: file.bytes}));
        bytes.set(partBytes, offset); offset += partBytes.byteLength;
      }
      if (offset !== file.bytes || await digest(bytes) !== file.sha256) throw Error('Game file checksum differs');
      checkAbort(options.signal);
      return bytes;
    }
    async function deliver(file, input, init, method) {
      const options = downloadOptions(input, init, false);
      checkAbort(options.signal);
      const headers = {
        'Content-Type': file.name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream',
        'Content-Length': String(file.bytes),
      };
      if (method === 'HEAD') return new env.Response(null, {status: 200, headers});
      // This private callback stays inside the adapter. It lets the boot
      // decoder's idle timer observe real network progress while this layer
      // validates the entire compressed file before returning a Response.
      const progress = typeof init?.onLittleWorldDownloadProgress === 'function'
        ? init.onLittleWorldDownloadProgress : null;
      let bytes;
      try { bytes = await verifiedBytes(file, options, progress); }
      catch (error) {
        checkAbort(options.signal);
        if (error?.name === 'AbortError') throw error;
        invalidate(file);
        // One reload retry repairs stale or corrupt cached parts. Never hand a
        // partial response to Godot, and never retry user cancellation.
        bytes = await verifiedBytes(file, downloadOptions(input, init, true), progress);
      }
      const body = new env.ReadableStream({start(controller) { controller.enqueue(bytes); controller.close(); }});
      bytes = null; // Transfer the verified buffer without a BufferSource copy.
      return new env.Response(body, {status: 200, headers});
    }
    function adapter(input, init) {
      let url;
      try {
        url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url, pageURL);
      } catch { return nativeFetch.call(env, input, init); }
      const method = String(init?.method || input?.method || 'GET').toUpperCase();
      if (url.origin !== base.origin || (method !== 'GET' && method !== 'HEAD')) return nativeFetch.call(env, input, init);
      url.search = ''; url.hash = '';
      const file = entries.get(url.href);
      if (!file) return nativeFetch.call(env, input, init);
      return deliver(file, input, init, method);
    }
    env.fetch = adapter;
    return {enabled: true, files: entries.size, restore() { if (env.fetch === adapter) env.fetch = nativeFetch; }};
  }
  const api = {install};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.LittleWorldChunkDelivery = api;
})(globalThis);
