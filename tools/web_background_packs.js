/* Page-lifetime downloads. Fetch reads continue without Godot/requestAnimationFrame.
 * No Worker, Service Worker, persistent storage or background-sync permission.
 * A discarded/frozen page is outside this lifetime; the UI must not promise more.
 */
(function (scope) {
  'use strict';
  function createBackgroundPacks(fetchImpl, memoryLimit = 128 * 1024 * 1024, concurrency = 2) {
    if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 4) throw Error('Invalid download concurrency');
    const jobs = new Map();
    const active = new Set();
    let base = null, delivery = {}, reserved = 0, buffered = 0, peak = 0, closed = false;
    const now = () => performance.now();
    const view = job => job ? {
      id: job.id, state: job.state, received: job.received, expected: job.bytes,
      error: job.error, started: job.started, finished: job.finished,
    } : { state: 'missing', received: 0, expected: 0, error: '' };
    function dropBuffer(job) {
      if (job.reserved) { reserved -= job.bytes; job.reserved = false; }
      buffered -= job.buffered;
      job.buffered = 0; job.chunks = []; job.head = 0;
    }
    async function download(job) {
      let reader;
      const timeout = setTimeout(() => job.controller.abort(), 600000);
      try {
        let decoder = null;
        if (job.delivery && typeof DecompressionStream === 'function') {
          try { decoder = new DecompressionStream('gzip'); } catch {}
        }
        const options = { signal: job.controller.signal, credentials: 'same-origin', priority: 'low' };
        let response = await fetchImpl(decoder ? job.delivery : job.url, options);
        // A stale CDN entry may temporarily lack its optional compressed copy.
        // Fallback is safe here: no bytes have been exposed to Godot's hasher.
        if (decoder && response.status !== 200) {
          await response.body?.cancel();
          decoder = null;
          response = await fetchImpl(job.url, options);
        }
        if (response.status !== 200) throw Error(response.status === 404
          ? '找不到遊戲內容（HTTP 404），請重新整理後再試。' : `下載失敗（HTTP ${response.status}），請重試。`);
        if (response.url && new URL(response.url).origin !== base.origin) throw Error('下載網址已變更，請重新整理。');
        if (!response.body) throw Error('伺服器沒有回應內容，請重試。');
        reader = (decoder ? response.body.pipeThrough(decoder) : response.body).getReader();
        for (;;) {
          // The next read is scheduled by network completion, never a game frame.
          const { value, done } = await reader.read();
          if (job.cancelled) return;
          if (done) break;
          if (job.received + value.byteLength > job.bytes) throw Error('下載內容超過預期大小，請重試。');
          // Retain streamed segments, not another full-pack allocation. Once
          // Godot has written+hashed a segment, consume() drops its JS owner.
          if (!value.byteLength) continue;
          const bytes = value.byteLength === value.buffer.byteLength ? value : value.slice();
          job.chunks.push({offset:job.received, bytes});
          job.buffered += bytes.byteLength; buffered += bytes.byteLength;
          peak = Math.max(peak, buffered);
          job.received += value.byteLength;
        }
        if (job.received !== job.bytes) throw Error('下載不完整，請重試。');
        job.state = 'downloaded';
        job.finished = now();
      } catch (error) {
        if (!job.cancelled) {
          job.state = 'failed';
          job.error = error.name === 'AbortError' ? '下載逾時，請檢查連線後重試。' : String(error.message || error);
          dropBuffer(job);
        }
      } finally {
        clearTimeout(timeout);
        if (reader) { try { await reader.cancel(); } catch {} }
        active.delete(job);
        pump();
      }
    }
    function pump() {
      if (closed) return;
      while (active.size < concurrency) {
        const pending = [...jobs.values()].filter(job => job.state === 'queued')
          .sort((a, b) => b.priority - a.priority);
        const job = pending[0];
        if (!job || reserved + job.bytes > memoryLimit) return;
        // Reserve decoded bytes, not compressed bytes, before starting either
        // request. Parallel network work cannot exceed the existing RAM bound.
        reserved += job.bytes; job.reserved = true;
        job.controller = new AbortController();
        job.state = 'downloading'; job.started = now(); active.add(job);
        void download(job);
      }
    }
    return {
      configure(url, manifest) {
        const next = new URL(url);
        if (base && base.href !== next.href && jobs.size) throw Error('Pack base changed during downloads');
        base = next;
        if (manifest) delivery = manifest;
      },
      enqueue(id, relative, bytes, priority) {
        if (!base) throw Error('Background packs not configured');
        if (!Number.isSafeInteger(bytes) || bytes <= 0 || bytes > memoryLimit) throw Error('Pack exceeds temporary download budget');
        const url = new URL(relative, base);
        if (url.origin !== base.origin || !url.pathname.startsWith(base.pathname) || url.search || url.hash)
          throw Error('Invalid pack URL');
        let job = jobs.get(id);
        if (job) {
          if (job.url !== url.href || job.bytes !== bytes) throw Error('Pack identity changed');
          job.priority = Math.max(job.priority, priority);
        } else {
          let compressed = null;
          const item = delivery[id];
          if (item && item.original_url === relative && item.bytes === bytes && item.encoding === 'gzip') {
            const candidate = new URL(item.url, base);
            if (candidate.origin !== base.origin || !candidate.pathname.startsWith(base.pathname) || candidate.search || candidate.hash)
              throw Error('Invalid compressed pack URL');
            compressed = candidate.href;
          }
          job = { id, url: url.href, delivery: compressed, bytes, priority, state: 'queued', received: 0, error: '', chunks:[], head:0, buffered:0, consumed:0, reserved:false, started:0, finished:0 };
          jobs.set(id, job);
        }
        pump();
      },
      status(id) { return view(jobs.get(id)); },
      read(id, offset, count) {
        const job = jobs.get(id);
        if (!job || offset < job.consumed || count <= 0 || !Number.isSafeInteger(offset) || !Number.isSafeInteger(count))
          return new Uint8Array();
        for(let i=job.head;i<job.chunks.length;i++) {
          const chunk=job.chunks[i], start=offset-chunk.offset;
          if(start>=0 && start<chunk.bytes.byteLength)return chunk.bytes.subarray(start,Math.min(chunk.bytes.byteLength,start+count));
        }
        return new Uint8Array();
      },
      consume(id, offset) {
        const job=jobs.get(id);
        if(!job || !Number.isSafeInteger(offset) || offset<job.consumed || offset>job.received)throw Error('Invalid consumer offset');
        job.consumed=offset;
        while(job.head<job.chunks.length) {
          const chunk=job.chunks[job.head];
          if(chunk.offset+chunk.bytes.byteLength>offset)break;
          buffered-=chunk.bytes.byteLength;job.buffered-=chunk.bytes.byteLength;
          job.chunks[job.head++]=null;
        }
        if(job.head>=256) {job.chunks=job.chunks.slice(job.head);job.head=0;}
      },
      release(id) {
        const job = jobs.get(id);
        if (!job) return;
        job.cancelled = true;
        if (active.has(job)) job.controller.abort();
        dropBuffer(job); jobs.delete(id); pump();
      },
      snapshot() {
        return { transport: 'background_fetch', active: active.values().next().value?.id || '', active_count:active.size, concurrency, buffered_bytes: buffered, reserved_bytes:reserved,
          peak_buffered_bytes: peak, buffer_limit_bytes: memoryLimit, jobs: [...jobs.values()].map(view) };
      },
      snapshotJson() { return JSON.stringify(this.snapshot()); },
      close() { closed = true; for (const id of [...jobs.keys()]) this.release(id); },
    };
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = { createBackgroundPacks };
  else scope.LittleWorldBackgroundPacks = createBackgroundPacks(scope.fetch.bind(scope));
})(globalThis);
