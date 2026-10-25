/* DOM controls share Godot's keyboard actions; only pointer motion is batched. */
(function (host) {
  'use strict';
  const DEAD_ZONE = 0.12;
  const STYLE = [
    '#little-world-touch{position:fixed;inset:0;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);pointer-events:none;z-index:15;font:14px system-ui;color:white;user-select:none;-webkit-user-select:none;-webkit-touch-callout:none}',
    '#little-world-touch *{box-sizing:border-box}',
    '#little-world-touch .lw-stick{position:absolute;left:calc(20px + env(safe-area-inset-left));bottom:calc(24px + env(safe-area-inset-bottom));width:clamp(116px,24vw,150px);height:clamp(116px,24vw,150px);border:2px solid #ffffffb0;border-radius:50%;background:#143e4399;pointer-events:auto;touch-action:none}',
    '#little-world-touch .lw-stick:before{content:"";position:absolute;inset:16%;border:1px solid #ffffff30;border-radius:50%}',
    '#little-world-touch .lw-stick span{position:absolute;left:32%;top:32%;width:36%;height:36%;border:1px solid #fff5;border-radius:50%;background:#ffedbee6;will-change:transform}',
    '#little-world-touch .lw-stick small{position:absolute;left:0;right:0;top:-28px;text-align:center;font-size:13px;text-shadow:0 1px 4px #000}',
    '#little-world-touch .lw-look{position:absolute;right:calc(12px + env(safe-area-inset-right));top:calc(154px + env(safe-area-inset-top));bottom:calc(148px + env(safe-area-inset-bottom));width:46%;display:flex;align-items:flex-end;justify-content:center;padding:12px;border:1px solid transparent;border-radius:24px;background:transparent;color:#ffffffb0;text-shadow:0 1px 4px #000;pointer-events:auto;touch-action:none;font-size:12px}',
    '#little-world-touch .lw-look.is-held{border-color:#fff9;background:#143e4338}',
    '#little-world-touch .lw-actions{position:absolute;right:calc(16px + env(safe-area-inset-right));bottom:calc(24px + env(safe-area-inset-bottom));display:grid;grid-template-columns:repeat(2,64px);gap:8px;pointer-events:auto}',
    '#little-world-touch button{height:52px;padding:0;border:1px solid #ffffffa0;border-radius:18px;background:#143e43d9;color:white;font:16px system-ui;touch-action:none}',
    '#little-world-touch button.is-held{background:#527e73;border-color:#ffedbe}',
    '@media(max-height:460px){#little-world-touch .lw-stick{width:108px;height:108px;bottom:calc(16px + env(safe-area-inset-bottom))}#little-world-touch .lw-actions{bottom:calc(16px + env(safe-area-inset-bottom))}#little-world-touch .lw-look{top:calc(112px + env(safe-area-inset-top));bottom:calc(136px + env(safe-area-inset-bottom));width:40%}}',
    '@media(min-width:768px) and (min-height:600px){#little-world-touch .lw-actions{grid-template-columns:repeat(2,76px);gap:10px}#little-world-touch button{height:60px}#little-world-touch .lw-look{bottom:calc(174px + env(safe-area-inset-bottom))}}',
    '#little-world-touch[data-gameplay="false"] .lw-stick,#little-world-touch[data-gameplay="false"] .lw-look,#little-world-touch[data-gameplay="false"] .lw-actions,#little-world-touch[data-menu="true"] .lw-stick,#little-world-touch[data-menu="true"] .lw-look,#little-world-touch[data-menu="true"] .lw-actions{display:none}',
    '#little-world-touch .lw-fullscreen{display:none;position:absolute;left:50%;transform:translateX(-50%);bottom:calc(18px + env(safe-area-inset-bottom));width:min(260px,70vw);height:46px;pointer-events:auto}',
    '#little-world-touch[data-menu="true"] .lw-fullscreen{display:block}',
    '#little-world-touch .lw-screen-note{display:none;position:absolute;left:12px;right:12px;bottom:calc(72px + env(safe-area-inset-bottom));max-width:520px;margin:auto;padding:14px 18px;background:#102f3af5;border:1px solid #fff6;border-radius:14px;font-size:16px;line-height:1.5;pointer-events:auto}'
  ].join('\n');

  function touchAvailable(env) {
    const nav = env.navigator || {};
    const forced = new URLSearchParams(env.location?.search || '').get('touch') === '1';
    return forced || /Android|iPhone|iPad|iPod/.test(nav.userAgent || '') ||
      (nav.platform === 'MacIntel' && nav.maxTouchPoints > 1) ||
      (nav.maxTouchPoints > 0 && Boolean(env.matchMedia?.('(any-pointer: coarse)').matches));
  }

  function joystickAxis(clientX, clientY, rect) {
    const radius = Math.max(1, rect.width * 0.34);
    let x = (clientX - rect.left - rect.width / 2) / radius;
    let y = (clientY - rect.top - rect.height / 2) / radius;
    const length = Math.hypot(x, y);
    if (length <= DEAD_ZONE) return [0, 0];
    // Continuous travel after the dead zone, with equal diagonal/axial speed.
    const strength = Math.min(1, (length - DEAD_ZONE) / (1 - DEAD_ZONE));
    return [x * strength / length, y * strength / length];
  }

  function createTouchUI(env) {
    const doc = env.document;
    let callback = null;
    let root = null;
    let resetInput = () => {};
    const ui = {
      modalOpen: false,
      menuOpen: false,
      gameplayActive: true,
      safeArea() {
        const computed = root && env.getComputedStyle?.(root);
        return computed ? ['paddingLeft', 'paddingTop', 'paddingRight', 'paddingBottom'].map(key => parseFloat(computed[key]) || 0) : [0, 0, 0, 0];
      },
      updateVisibility() {
        if (!root) return;
        root.style.display = this.modalOpen && !this.menuOpen ? 'none' : '';
        root.setAttribute('aria-hidden', String(this.modalOpen && !this.menuOpen));
        root.setAttribute('data-menu', String(this.menuOpen));
        root.setAttribute('data-gameplay', String(this.gameplayActive));
      },
      setModalOpen(open) {
        this.modalOpen = Boolean(open);
        if (this.modalOpen) resetInput();
        this.updateVisibility();
      },
      setMenuOpen(open) {
        this.menuOpen = Boolean(open);
        if (this.menuOpen) resetInput();
        if (!this.menuOpen && root) root.querySelector('.lw-screen-note').style.display = 'none';
        this.updateVisibility();
      },
      setGameplayActive(active) {
        const changed = this.gameplayActive !== Boolean(active);
        this.gameplayActive = Boolean(active);
        if (changed && !this.gameplayActive) resetInput();
        this.updateVisibility();
      },
      resetInput() { resetInput(); },
      attach(nextCallback) {
        if (typeof nextCallback !== 'function') return;
        if (callback && callback !== nextCallback) resetInput();
        callback = nextCallback;
        if (root || !touchAvailable(env)) return;
        root = doc.createElement('div');
        root.id = 'little-world-touch';
        root.setAttribute('aria-label', '觸控遊戲操作');
        root.innerHTML = '<div class="lw-stick" role="group" aria-label="移動搖桿：推得越遠走得越快"><small>移動搖桿</small><span></span></div><div class="lw-look" role="group" aria-label="右手拖曳轉動視角">拖曳轉視角</div><div class="lw-actions"><button type="button" data-action="run" aria-label="按住奔跑">奔跑</button><button type="button" data-action="jump">跳躍</button><button type="button" data-action="interact">互動</button><button type="button" data-action="use">使用</button></div><button type="button" class="lw-fullscreen">⛶ 全螢幕</button><div class="lw-screen-note" role="status" aria-live="polite"></div>';
        const style = doc.createElement('style');
        style.textContent = STYLE;
        doc.head.append(style);
        doc.body.append(root);
        const stick = root.querySelector('.lw-stick');
        const knob = root.querySelector('.lw-stick span');
        const look = root.querySelector('.lw-look');
        const fullscreen = root.querySelector('.lw-fullscreen');
        const note = root.querySelector('.lw-screen-note');
        fullscreen.addEventListener('click', async event => {
          event.preventDefault(); event.stopPropagation();
          const target = doc.documentElement;
          const request = target?.requestFullscreen || target?.webkitRequestFullscreen;
          const exit = doc.exitFullscreen || doc.webkitExitFullscreen;
          const active = doc.fullscreenElement || doc.webkitFullscreenElement;
          note.style.display = 'none';
          try {
            if (active && exit) await exit.call(doc);
            else if (request) await request.call(target);
            else {
              const ios = /iPhone|iPad|iPod/.test(env.navigator?.userAgent || '') || (env.navigator?.platform === 'MacIntel' && env.navigator?.maxTouchPoints > 1);
              note.textContent = ios ? '此瀏覽器不支援網頁全螢幕。請用 Safari 的「分享」→「加入主畫面」，再從主畫面開啟。' : '此瀏覽器不支援網頁全螢幕。可使用瀏覽器的全螢幕功能，或橫向遊玩。';
              note.style.display = 'block';
            }
          } catch {
            note.textContent = '瀏覽器沒有開啟全螢幕。請確認允許全螢幕，或橫向遊玩。';
            note.style.display = 'block';
          }
        });
        const fullscreenChanged = () => {
          fullscreen.textContent = doc.fullscreenElement || doc.webkitFullscreenElement ? '⛶ 離開全螢幕' : '⛶ 全螢幕';
        };
        doc.addEventListener('fullscreenchange', fullscreenChanged);
        doc.addEventListener('webkitfullscreenchange', fullscreenChanged);
        const held = new Map();
        const captures = new Map();
        let stickId = null;
        let stickRect = null;
        let lookId = null;
        let last = null;
        let axis = [0, 0];
        let axisDirty = false;
        let lookDelta = [0, 0];
        let frame = null;
        const emit = (kind, x, y) => callback?.(kind, x, y);
        const consume = event => { event.preventDefault(); event.stopPropagation(); };
        const capture = (element, id) => {
          captures.set(id, element);
          try { element.setPointerCapture(id); } catch { /* Window release remains a fallback. */ }
        };
        const releaseCapture = id => {
          const element = captures.get(id);
          captures.delete(id);
          try { if (element?.hasPointerCapture(id)) element.releasePointerCapture(id); } catch { /* Pointer already ended. */ }
        };
        const flush = () => {
          frame = null;
          if (axisDirty) {
            axisDirty = false;
            emit('axis', axis[0], axis[1]);
            const travel = stickRect ? stickRect.width * 0.30 : 0;
            knob.style.transform = 'translate(' + axis[0] * travel + 'px,' + axis[1] * travel + 'px)';
          }
          if (lookDelta[0] || lookDelta[1]) {
            const delta = lookDelta;
            lookDelta = [0, 0];
            emit('look', delta[0], delta[1]);
          }
        };
        const schedule = () => { if (frame === null) frame = env.requestAnimationFrame(flush); };
        const moveStick = event => {
          axis = joystickAxis(event.clientX, event.clientY, stickRect);
          axisDirty = true;
          schedule();
        };
        const releaseStick = event => {
          if (event.pointerId !== stickId) return;
          const id = stickId;
          stickId = null;
          axis = [0, 0];
          axisDirty = false;
          knob.style.transform = '';
          // Release synchronously, even if the next animation frame is delayed.
          emit('axis', 0, 0);
          releaseCapture(id);
        };
        const releaseLook = event => {
          if (event.pointerId !== lookId) return;
          const id = lookId;
          lookId = null;
          last = null;
          look.classList.remove('is-held');
          releaseCapture(id);
        };
        const releaseAction = event => {
          const heldButton = held.get(event.pointerId);
          if (!heldButton) return;
          held.delete(event.pointerId);
          if (![...held.values()].includes(heldButton)) {
            emit('action', heldButton.dataset.action, 0);
            heldButton.classList.remove('is-held');
            heldButton.setAttribute('aria-pressed', 'false');
          }
          releaseCapture(event.pointerId);
        };
        resetInput = () => {
          if (frame !== null) env.cancelAnimationFrame(frame);
          frame = null;
          axisDirty = false;
          axis = [0, 0];
          lookDelta = [0, 0];
          stickId = lookId = null;
          last = null;
          for (const button of new Set(held.values())) {
            emit('action', button.dataset.action, 0);
            button.classList.remove('is-held');
            button.setAttribute('aria-pressed', 'false');
          }
          held.clear();
          emit('axis', 0, 0);
          knob.style.transform = '';
          look.classList.remove('is-held');
          for (const id of [...captures.keys()]) releaseCapture(id);
        };
        const canStart = event => !ui.modalOpen && !ui.menuOpen && ui.gameplayActive && (event.pointerType !== 'mouse' || event.button === 0);
        stick.addEventListener('pointerdown', event => {
          if (!canStart(event) || stickId !== null) return;
          consume(event);
          stickId = event.pointerId;
          stickRect = stick.getBoundingClientRect();
          capture(stick, stickId);
          moveStick(event);
        });
        stick.addEventListener('pointermove', event => {
          if (event.pointerId !== stickId) return;
          consume(event);
          moveStick(event);
        });
        look.addEventListener('pointerdown', event => {
          if (!canStart(event) || lookId !== null) return;
          consume(event);
          lookId = event.pointerId;
          last = [event.clientX, event.clientY];
          look.classList.add('is-held');
          capture(look, lookId);
        });
        look.addEventListener('pointermove', event => {
          if (event.pointerId !== lookId) return;
          consume(event);
          lookDelta[0] += event.clientX - last[0];
          lookDelta[1] += event.clientY - last[1];
          last = [event.clientX, event.clientY];
          schedule();
        });
        for (const button of root.querySelectorAll('button')) {
          if (!button.dataset.action) continue;
          button.setAttribute('aria-pressed', 'false');
          button.addEventListener('pointerdown', event => {
            if (!canStart(event) || held.has(event.pointerId)) return;
            consume(event);
            const alreadyHeld = [...held.values()].includes(button);
            held.set(event.pointerId, button);
            capture(button, event.pointerId);
            button.classList.add('is-held');
            button.setAttribute('aria-pressed', 'true');
            if (!alreadyHeld) emit('action', button.dataset.action, 1);
          });
          for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) button.addEventListener(type, releaseAction);
          button.addEventListener('contextmenu', consume);
        }
        for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
          stick.addEventListener(type, releaseStick);
          look.addEventListener(type, releaseLook);
        }
        for (const type of ['pointerup', 'pointercancel']) env.addEventListener(type, event => {
          releaseStick(event); releaseLook(event); releaseAction(event);
        });
        for (const type of ['blur', 'pagehide', 'orientationchange', 'resize']) env.addEventListener(type, resetInput);
        doc.addEventListener('visibilitychange', () => { if (doc.hidden) resetInput(); });
        this.setModalOpen(this.modalOpen);
      }
    };
    return ui;
  }

  if (typeof module !== 'undefined' && module.exports) module.exports = {createTouchUI, joystickAxis, touchAvailable};
  if (host?.document) host.LittleWorldTouchUI = createTouchUI(host);
})(typeof window === 'undefined' ? null : window);
