/* Local training-room games: keep their browser context only while in the room. */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) module.exports = {create: factory};
  else root.LittleWorldComputerGames = factory(root);
})(typeof window === 'undefined' ? globalThis : window, function create(env) {
  'use strict';
  const doc = env.document;
  const games = {go: {url: 'games/go/index.html', title: '圍棋'}};
  let ui = null, opened = false, ready = false, loading = false, sequence = 0;
  let controller = null, timeout = null, frameDocument = null, escapeReleased = true;
  let savedOverflow = '', savedCanvasInert = false;
  const stop = event => event.stopPropagation();
  const swallow = event => { event.preventDefault(); event.stopImmediatePropagation(); };

  function element(tag, className, text) {
    const node = doc.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  function clearTimer() {
    if (timeout !== null) env.clearTimeout(timeout);
    timeout = null;
  }

  function escape(event) {
    if (!opened || event.key !== 'Escape') return;
    swallow(event);
    escapeReleased = false;
    close();
  }

  function keyboard(event) {
    if (event.type === 'keyup' && event.key === 'Escape' && !escapeReleased) {
      swallow(event); escapeReleased = true; return;
    }
    if (!opened) return;
    if (event.type === 'keydown' && event.key === 'Escape') { escape(event); return; }
    // The iframe owns its own keyboard events. Keep parent-document input in
    // the modal, including after the Godot canvas tries to regain focus.
    if (!ui.root.contains(event.target)) { swallow(event); ui.back.focus(); }
    else if (event.type === 'keydown' && event.key === 'Tab') {
      if (event.target === ui.back && event.shiftKey) {
        event.preventDefault(); (ready ? ui.frame : ui.retry.hidden ? ui.back : ui.retry).focus();
      } else if (!ready && (event.target === ui.retry || ui.retry.hidden) && !event.shiftKey) {
        event.preventDefault(); ui.back.focus();
      }
    }
  }

  function ensureUI() {
    if (ui) return;
    const style = element('style');
    style.textContent = `
      .lw-computer-game { position:fixed; inset:0; z-index:2147483647; display:flex;
        flex-direction:column; color:#ecf2f9; background:#0a1019;
        font:16px/1.5 system-ui,"Microsoft JhengHei",sans-serif; }
      .lw-computer-game[hidden], .lw-computer-game [hidden] { display:none !important; }
      .lw-computer-game header { display:flex; align-items:center; gap:16px;
        justify-content:space-between; padding:10px max(16px,env(safe-area-inset-right));
        border-bottom:1px solid #2b3a4b; background:#111b28; }
      .lw-computer-game h1 { margin:0; font-size:19px; }
      .lw-computer-game button { background:#203a45; color:#ecf2f9; border:1px solid #527984;
        border-radius:8px; font:inherit; cursor:pointer; padding:8px 14px; }
      .lw-computer-game button:focus-visible { outline:3px solid #65e4c7; outline-offset:2px; }
      .lw-computer-game main { position:relative; flex:1; min-height:0; display:flex; }
      .lw-computer-game iframe { width:100%; height:100%; border:0; background:#0a1019; }
      .lw-computer-game-status { margin:auto; text-align:center; padding:24px; }
      @media (max-width:480px) { .lw-computer-game header { gap:8px; padding:8px; }
        .lw-computer-game button { padding:8px 10px; } }
    `;
    const root = element('section', 'lw-computer-game');
    root.hidden = true;
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-modal', 'true');
    root.setAttribute('aria-label', '圍棋遊戲');
    const header = element('header'), title = element('h1', '', '圍棋');
    const back = element('button', '', '返回練功區（Esc）');
    back.type = 'button'; back.addEventListener('click', close);
    header.appendChild(title); header.appendChild(back);
    const main = element('main'), status = element('div', 'lw-computer-game-status');
    const message = element('p', '', '正在載入圍棋…');
    message.setAttribute('role', 'status'); message.setAttribute('aria-live', 'polite');
    const retry = element('button', '', '重新載入');
    retry.type = 'button'; retry.hidden = true; retry.addEventListener('click', load);
    status.appendChild(message); status.appendChild(retry);
    const frame = element('iframe');
    frame.title = '圍棋'; frame.hidden = true;
    // This is reviewed same-origin source. Avoid sandboxing it into an opaque
    // origin: the game needs localStorage and a locally created Blob Worker.
    frame.referrerPolicy = 'same-origin';
    main.appendChild(status); main.appendChild(frame);
    root.appendChild(header); root.appendChild(main);
    for (const name of ['keydown', 'keyup', 'keypress', 'pointerdown', 'pointerup', 'click', 'wheel']) {
      root.addEventListener(name, stop);
    }
    doc.head.appendChild(style); doc.body.appendChild(root);
    doc.addEventListener('keydown', keyboard, true);
    doc.addEventListener('keyup', keyboard, true);
    ui = {root, title, back, frame, status, message, retry, style};
  }

  function fail(token) {
    if (!ui || sequence !== token) return;
    clearTimer();
    if (controller) controller.abort();
    controller = null; loading = false; ready = false;
    ui.frame.hidden = true; ui.status.hidden = false; ui.retry.hidden = false;
    ui.message.textContent = '圍棋無法載入。請重新載入，或返回練功區稍後再試。';
  }

  async function load() {
    if (!ui) return;
    const token = ++sequence;
    clearTimer();
    if (controller) controller.abort();
    if (frameDocument) frameDocument.removeEventListener('keydown', escape, true);
    frameDocument = null; ready = false; loading = true;
    ui.frame.hidden = true; ui.status.hidden = false; ui.retry.hidden = true;
    ui.message.textContent = '正在載入圍棋…';
    controller = new env.AbortController();
    timeout = env.setTimeout(() => fail(token), 20000);
    try {
      const url = new URL(games.go.url, new URL('.', env.location.href));
      const response = await env.fetch(url.href, {signal: controller.signal, credentials: 'same-origin'});
      if (!response.ok || (response.url && new URL(response.url).href !== url.href)) throw new Error('Game unavailable');
      const html = await response.text();
      if (!html.includes('id="go-app-code"')) throw new Error('Unexpected game response');
      if (!ui || token !== sequence || !loading) return;
      ui.frame.onload = () => {
        if (!ui || token !== sequence || !loading) return;
        try {
          const child = ui.frame.contentWindow;
          if (child.location.href === 'about:blank') return;
          if (child.location.href !== url.href || !child.document.getElementById('board-input')) throw new Error('Game did not load');
          frameDocument = child.document;
          frameDocument.addEventListener('keydown', escape, true);
          clearTimer(); controller = null; loading = false; ready = true;
          ui.frame.hidden = false; ui.status.hidden = true;
          if (opened) ui.frame.focus();
        } catch (_) { fail(token); }
      };
      ui.frame.onerror = () => fail(token);
      ui.frame.src = url.href;
    } catch (_) { fail(token); }
  }

  function open(id, title, url) {
    if (!Object.hasOwn(games, id) || url !== games[id].url || !/^https?:$/.test(env.location.protocol)) return false;
    ensureUI();
    if (opened) return true;
    ui.title.textContent = games[id].title;
    ui.root.hidden = false; opened = true;
    savedOverflow = doc.body.style.overflow; doc.body.style.overflow = 'hidden';
    const canvas = doc.getElementById('canvas');
    if (canvas) { savedCanvasInert = canvas.inert; canvas.inert = true; canvas.blur(); }
    if (doc.pointerLockElement && doc.exitPointerLock) doc.exitPointerLock();
    (ready ? ui.frame : ui.back).focus();
    if (!ready && !loading) load();
    return true;
  }

  function close() {
    if (!opened) return;
    opened = false; ui.root.hidden = true;
    doc.body.style.overflow = savedOverflow;
    const canvas = doc.getElementById('canvas');
    if (canvas) { canvas.inert = savedCanvasInert; canvas.focus(); }
  }

  function destroy() {
    close(); sequence++; clearTimer();
    if (controller) controller.abort();
    controller = null;
    if (frameDocument) frameDocument.removeEventListener('keydown', escape, true);
    frameDocument = null;
    if (ui) {
      ui.frame.onload = null; ui.frame.onerror = null;
      ui.frame.remove(); ui.root.remove(); ui.style.remove(); ui = null;
      doc.removeEventListener('keydown', keyboard, true);
      doc.removeEventListener('keyup', keyboard, true);
    }
    ready = false; loading = false; escapeReleased = true;
  }

  return Object.freeze({open, close, isOpen: () => opened, destroy});
});
