/* Page-lifetime downloads. Fetch reads continue without Godot/requestAnimationFrame.
 * No Worker, Service Worker, persistent storage or background-sync permission.
 * A discarded/frozen page is outside this lifetime; the UI must not promise more.
 */
(function (scope) {
  'use strict';
  function createBackgroundPacks(fetchImpl, memoryLimit = 128 * 1024 * 1024) {
    const jobs = new Map();
    let base = null, active = null, reserved = 0, peak = 0, closed = false;
    const now = () => performance.now();
    const view = job => job ? {
      id: job.id, state: job.state, received: job.received, expected: job.bytes,
      error: job.error, started: job.started, finished: job.finished,
    } : { state: 'missing', received: 0, expected: 0, error: '' };
    function dropBuffer(job) {
      if (job.buffer) { reserved -= job.bytes; job.buffer = null; }
    }
    async function download(job) {
      let reader;
      const timeout = setTimeout(() => job.controller.abort(), 600000);
      try {
        const response = await fetchImpl(job.url, { signal: job.controller.signal, credentials: 'same-origin', priority: 'low' });
        if (response.status !== 200) throw Error(response.status === 404
          ? '找不到遊戲內容（HTTP 404），請重新整理後再試。' : `下載失敗（HTTP ${response.status}），請重試。`);
        if (response.url && new URL(response.url).origin !== base.origin) throw Error('下載網址已變更，請重新整理。');
        if (!response.body) throw Error('伺服器沒有回應內容，請重試。');
        reader = response.body.getReader();
        for (;;) {
          // The next read is scheduled by network completion, never a game frame.
          const { value, done } = await reader.read();
          if (job.cancelled) return;
          if (done) break;
          if (job.received + value.byteLength > job.bytes) throw Error('下載內容超過預期大小，請重試。');
          job.buffer.set(value, job.received);
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
        if (active === job) active = null;
        pump();
      }
    }
    function pump() {
      if (active || closed) return;
      const pending = [...jobs.values()].filter(job => job.state === 'queued')
        .sort((a, b) => b.priority - a.priority);
      const job = pending[0];
      if (!job || reserved + job.bytes > memoryLimit) return;
      try { job.buffer = new Uint8Array(job.bytes); }
      catch { job.state = 'failed'; job.error = '暫存空間不足，請關閉其他遊戲分頁後重試。'; pump(); return; }
      reserved += job.bytes; peak = Math.max(peak, reserved);
      job.controller = new AbortController();
      job.state = 'downloading'; job.started = now(); active = job;
      void download(job);
    }
    return {
      configure(url) { base = new URL(url); },
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
          job = { id, url: url.href, bytes, priority, state: 'queued', received: 0, error: '', buffer: null, started: 0, finished: 0 };
          jobs.set(id, job);
        }
        pump();
      },
      status(id) { return view(jobs.get(id)); },
      read(id, offset, count) {
        const job = jobs.get(id);
        if (!job?.buffer || offset < 0 || count <= 0 || !Number.isSafeInteger(offset) || !Number.isSafeInteger(count))
          return new Uint8Array();
        return job.buffer.subarray(offset, Math.min(job.received, offset + count));
      },
      release(id) {
        const job = jobs.get(id);
        if (!job) return;
        job.cancelled = true;
        if (active === job) job.controller.abort();
        dropBuffer(job); jobs.delete(id); pump();
      },
      snapshot() {
        return { transport: 'background_fetch', active: active?.id || '', buffered_bytes: reserved,
          peak_buffered_bytes: peak, buffer_limit_bytes: memoryLimit, jobs: [...jobs.values()].map(view) };
      },
      snapshotJson() { return JSON.stringify(this.snapshot()); },
      close() { closed = true; for (const id of [...jobs.keys()]) this.release(id); },
    };
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = { createBackgroundPacks };
  else scope.LittleWorldBackgroundPacks = createBackgroundPacks(scope.fetch.bind(scope));
})(globalThis);
