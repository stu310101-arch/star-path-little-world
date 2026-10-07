/* Application-level gzip for the two boot files only. No persistent cache.
 * Decode and validate before exposing a body to Godot 4.7.2: its loader does
 * not propagate a failed body stream reliably. The original URLs stay valid.
 */
(function (root) {
  'use strict';
  function attachStatusUI(env = root) {
    const overlay = env.document?.getElementById('status');
    const progress = env.document?.getElementById('status-progress');
    const notice = env.document?.getElementById('status-notice');
    if (!overlay || !progress) return {engineProgress() { return true; }, dispose() {}};
    const line = env.document.createElement('div');
    line.id = 'little-world-boot-stage';
    line.style.cssText = 'position:absolute;bottom:calc(10% + 30px);left:1rem;right:1rem;z-index:2;text-align:center;font:15px/1.6 system-ui,sans-serif;color:#fff;text-shadow:0 1px 3px #000;pointer-events:none;';
    const phase = env.document.createElement('div');
    phase.setAttribute('role', 'status');
    phase.setAttribute('aria-live', 'polite');
    const detail = env.document.createElement('div');
    detail.style.cssText = 'font-size:13px;color:#dce5ec;';
    detail.setAttribute('aria-hidden', 'true');
    line.appendChild(phase); line.appendChild(detail); overlay.appendChild(line);
    let timer = null, disposed = false, engineComplete = false, ownsProgress = false;
    const setText = (node, text) => { if (node.textContent !== text) node.textContent = text; };
    const dispose = () => {
      disposed = true;
      if (timer !== null) env.clearInterval(timer);
      timer = null;
      env.removeEventListener('planet-boot-delivery', update);
    };
    const update = () => {
      if (disposed) return;
      if (!overlay.isConnected) { dispose(); return; }
      if (notice?.style.display === 'block') { line.style.display = 'none'; dispose(); return; }
      const status = env.planetBootDelivery;
      const files = Object.values(status?.files || {});
      const compressed = status?.enabled && files.length === 2 && !files.some(file => file.phase === 'fallback');
      const ready = compressed && files.every(file => file.phase === 'ready');
      ownsProgress = Boolean(compressed && !ready && !engineComplete);
      if (engineComplete || ready) {
        setText(phase, '正在啟動引擎與準備畫面…');
        setText(detail, '啟動檔已就緒，正在準備遊戲畫面');
      } else if (compressed) {
        const downloading = files.some(file => ['waiting', 'downloading'].includes(file.phase));
        setText(phase, downloading ? '正在下載啟動檔…' : '正在驗證啟動檔…');
        const received = files.reduce((sum, file) => sum + file.decodedBytes, 0);
        const expected = files.reduce((sum, file) => sum + file.expectedBytes, 0);
        setText(detail, `已解壓 ${(received / 1000000).toFixed(1)} / ${(expected / 1000000).toFixed(1)} MB`);
        // Decoded bytes, explicitly labelled above; not compressed wire bytes.
        // Stop owning the bar when buffers are handed to the original loader.
        if (progress.max !== expected) progress.max = expected;
        if (progress.value !== received) progress.value = received;
      } else {
        setText(phase, '正在下載啟動檔…');
        setText(detail, status?.enabled ? '使用相容載入方式' : '');
      }
    };
    env.addEventListener('planet-boot-delivery', update);
    timer = env.setInterval(update, 250);
    update();
    return {
      engineProgress(current, total) {
        if (current > 0 && total > 0 && current >= total) engineComplete = true;
        update();
        return !ownsProgress;
      },
      dispose,
    };
  }
  function install(config, manifest, env = root) {
    const status = env.planetBootDelivery = {enabled: false, files: {}, restored: false};
    const emit = () => {
      if (typeof env.dispatchEvent === 'function' && typeof env.CustomEvent === 'function') {
        env.dispatchEvent(new env.CustomEvent('planet-boot-delivery', {detail: status}));
      }
    };
    const now = () => env.performance.now();
    const names = ['index.pck', 'index.wasm'];
    const entries = new Map();
    try {
      if (manifest.version !== 1 || manifest.engine_version !== '4.7.2' ||
          Object.keys(manifest.files).sort().join(',') !== names.join(',')) {
        throw new Error('Unsupported boot delivery manifest');
      }
      for (const name of names) {
        const item = manifest.files[name];
        const original = new URL(name, env.location.href);
        const compressed = new URL(item.url, env.location.href);
        if (original.origin !== compressed.origin || compressed.pathname === original.pathname ||
            !/^index\.boot\.[a-f0-9]{16}\.(pck|wasm)\.gz$/.test(item.url) ||
            !Number.isSafeInteger(item.bytes) || item.bytes <= 0 || item.bytes > 268435456 ||
            item.bytes !== config.fileSizes[name] || !/^[a-f0-9]{64}$/.test(item.sha256) ||
            !Number.isSafeInteger(item.compressed_bytes) || item.compressed_bytes <= 0) {
          throw new Error('Invalid boot delivery metadata');
        }
        const row = status.files[name] = {
          phase: 'waiting', decodedBytes: 0, expectedBytes: item.bytes,
          compressedBytes: item.compressed_bytes, url: compressed.href,
        };
        entries.set(original.href, {name, item, row, compressed: compressed.href});
      }
      // Constructor probing covers browsers which expose the API but do not
      // implement gzip. SHA-256 is mandatory; unsupported browsers use originals.
      if (!env.crypto?.subtle || !env.ReadableStream || !env.Response || !env.AbortController) throw new Error('Missing streaming integrity APIs');
      new env.DecompressionStream('gzip');
    } catch (error) {
      status.reason = String(error.message || error);
      emit();
      return {enabled: false, restore() {}};
    }

    const originalFetch = env.fetch;
    const pending = new Set(entries.keys());
    const setPhase = (row, phase) => { row.phase = phase; row[phase + 'At'] = now(); emit(); };
    const restore = () => {
      if (env.fetch === adapter) env.fetch = originalFetch;
      status.restored = true;
      emit();
    };
    async function decodedResponse(entry, input, init) {
      const {item, row} = entry;
      let reader;
      let bytes;
      let timer;
      const controller = new env.AbortController();
      const armIdleTimeout = () => {
        if (timer !== undefined && timer !== null) env.clearTimeout(timer);
        timer = env.setTimeout(() => controller.abort(), 120000);
      };
      try {
        setPhase(row, 'downloading');
        // A stalled optional compressed route must not wait forever before the
        // ordinary loader can retry. Slow downloads which progress can continue.
        armIdleTimeout();
        const response = await originalFetch.call(env, entry.compressed, {signal: controller.signal});
        if (!response.ok || !response.body) throw new Error('gzip HTTP ' + response.status);
        armIdleTimeout();
        bytes = new Uint8Array(item.bytes);
        reader = response.body.pipeThrough(new env.DecompressionStream('gzip')).getReader();
        let offset = 0;
        for (;;) {
          const {value, done} = await reader.read();
          if (done) break; // gzip footer CRC/size is checked by DecompressionStream.
          if (offset + value.byteLength > bytes.byteLength) throw new Error('Decoded boot file is too large');
          bytes.set(value, offset);
          offset += value.byteLength;
          row.decodedBytes = offset;
          armIdleTimeout();
        }
        env.clearTimeout(timer); timer = null;
        if (offset !== item.bytes) throw new Error('Decoded boot file is incomplete');
        setPhase(row, 'verifying');
        const hash = new Uint8Array(await env.crypto.subtle.digest('SHA-256', bytes));
        const actual = Array.from(hash, v => v.toString(16).padStart(2, '0')).join('');
        if (actual !== item.sha256) throw new Error('Decoded boot file hash differs');
        setPhase(row, 'ready');
        // A BufferSource Response copies its input. Transfer our already verified
        // array to a one-chunk stream instead, so the loader can consume it without
        // a second full decoded PCK/WASM copy owned by this adapter.
        const body = new env.ReadableStream({start(controller) {
          controller.enqueue(bytes);
          controller.close();
        }});
        bytes = null;
        // No gzip header: the body is decoded and fileSizes remain unchanged.
        return new env.Response(body, {status: 200, headers: {
          'Content-Type': entry.name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream',
          'Content-Length': String(item.bytes),
        }});
      } catch (error) {
        row.fallbackReason = String(error.message || error);
        setPhase(row, 'fallback');
        controller.abort();
        if (reader) await reader.cancel().catch(() => {});
        bytes = null;
        // Call the saved function, not the adapter; no recursion or cache change.
        return originalFetch.call(env, input, init);
      } finally {
        if (timer !== undefined && timer !== null) env.clearTimeout(timer);
        if (reader) reader.releaseLock();
      }
    }
    function adapter(input, init) {
      // Godot's boot preloader calls fetch(string) without options. Restrict the
      // adapter to those two exact same-origin requests; methods, Request objects,
      // query strings, later asset packs and every other fetch are untouched.
      if (typeof input !== 'string' || init != null) return originalFetch.call(env, input, init);
      let url;
      try { url = new URL(input, env.location.href).href; } catch { return originalFetch.call(env, input, init); }
      const entry = entries.get(url);
      if (!entry || !pending.delete(url)) return originalFetch.call(env, input, init);
      // Both native fetch references are already captured. Restore before their
      // bodies finish, so post-boot HTTPClient traffic never sees this wrapper.
      if (!pending.size) restore();
      return decodedResponse(entry, input, init);
    }
    env.fetch = adapter;
    status.enabled = true;
    emit();
    return {enabled: true, restore};
  }
  const api = {install, attachStatusUI};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.LittleWorldBootDelivery = api;
})(globalThis);
