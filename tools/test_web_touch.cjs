'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {createTouchUI, joystickAxis, touchAvailable} = require('./web_touch.js');

// Exercise the shipped event handlers with deterministic animation frames. This
// models DOM pointer ownership; it does not claim real Safari/device coverage.
class Surface {
  constructor() {
    this.listeners = new Map(); this.style = {}; this.attributes = {}; this.dataset = {};
    this.children = []; this.captured = new Set(); this.classes = new Set();
    this.classList = {add: value => this.classes.add(value), remove: value => this.classes.delete(value)};
    this.rect = {left: 20, top: 300, width: 120, height: 120};
  }
  addEventListener(type, fn) { if (!this.listeners.has(type)) this.listeners.set(type, []); this.listeners.get(type).push(fn); }
  fire(type, values = {}) {
    const event = {pointerId: 1, pointerType: 'touch', button: 0, clientX: 80, clientY: 360,
      preventDefault() { this.prevented = true; }, stopPropagation() {}, ...values};
    event.done = Promise.all((this.listeners.get(type) || []).map(listener => listener(event)));
    return event;
  }
  setAttribute(key, value) { this.attributes[key] = value; }
  append(child) { this.children.push(child); }
  setPointerCapture(id) { this.captured.add(id); }
  hasPointerCapture(id) { return this.captured.has(id); }
  releasePointerCapture(id) { this.captured.delete(id); this.fire('lostpointercapture', {pointerId: id}); }
  getBoundingClientRect() { return this.rect; }
  set innerHTML(value) {
    assert.match(value, /移動搖桿/);
    this.stick = new Surface(); this.knob = new Surface(); this.look = new Surface();
    this.fullscreen = new Surface(); this.note = new Surface();
    this.buttons = ['run', 'jump', 'interact', 'use'].map(action => { const button = new Surface(); button.dataset.action = action; return button; });
  }
  querySelector(selector) { return {'.lw-stick': this.stick, '.lw-stick span': this.knob, '.lw-look': this.look, '.lw-fullscreen': this.fullscreen, '.lw-screen-note': this.note}[selector]; }
  querySelectorAll(selector) { assert.equal(selector, 'button'); return this.buttons; }
}

function fixture(navigator = {userAgent: 'Android', maxTouchPoints: 5}) {
  const env = new Surface();
  const document = new Surface();
  document.head = new Surface(); document.body = new Surface();
  document.createElement = () => new Surface();
  env.document = document; env.navigator = navigator; env.location = {search: ''};
  env.matchMedia = () => ({matches: false});
  let nextFrame = 0;
  const frames = new Map();
  env.requestAnimationFrame = fn => { const id = ++nextFrame; frames.set(id, fn); return id; };
  env.cancelAnimationFrame = id => frames.delete(id);
  env.flush = () => { const callbacks = [...frames.values()]; frames.clear(); for (const callback of callbacks) callback(); };
  const ui = createTouchUI(env);
  const messages = [];
  const attach = () => { ui.attach((...args) => messages.push(args)); return document.body.children[0]; };
  return {env, document, ui, messages, attach};
}

test('phone, Android, desktop-UA iPad, and coarse-pointer tablet detection', () => {
  for (const navigator of [{userAgent: 'iPhone'}, {userAgent: 'Android'}, {userAgent: 'Macintosh', platform: 'MacIntel', maxTouchPoints: 5}]) {
    assert.equal(touchAvailable({navigator}), true);
  }
  assert.equal(touchAvailable({navigator: {userAgent: 'Windows', maxTouchPoints: 10}, matchMedia: () => ({matches: true})}), true);
  assert.equal(touchAvailable({navigator: {userAgent: 'Windows', maxTouchPoints: 0}}), false);
  assert.equal(touchAvailable({navigator: {}, location: {search: '?touch=1'}}), true);
});

test('compact menu releases controls, keeps fullscreen accessible and blocks movement', () => {
  const f = fixture(); const root = f.attach();
  root.stick.fire('pointerdown', {clientY: 310}); f.env.flush();
  f.ui.setModalOpen(true); f.ui.setMenuOpen(true);
  assert.equal(root.style.display, '');
  assert.equal(root.attributes['data-menu'], 'true');
  assert.deepEqual(f.messages.at(-1), ['axis', 0, 0]);
  const count = f.messages.length;
  root.buttons[0].fire('pointerdown'); root.stick.fire('pointerdown'); f.env.flush();
  assert.equal(f.messages.length, count);
  f.ui.setMenuOpen(false);
  assert.equal(root.style.display, 'none');
});

test('overview hides and disables game controls until roaming starts', () => {
  const f = fixture(); const root = f.attach();
  f.ui.setGameplayActive(false); const count = f.messages.length;
  root.buttons[1].fire('pointerdown'); f.env.flush();
  assert.equal(root.attributes['data-gameplay'], 'false');
  assert.equal(f.messages.length, count);
  f.ui.setGameplayActive(true); root.buttons[1].fire('pointerdown');
  assert.deepEqual(f.messages.at(-1), ['action', 'jump', 1]);
});

test('fullscreen is requested directly by a click and can exit', async () => {
  const f = fixture(); const root = f.attach(); let requested = 0, exited = 0;
  f.document.documentElement = {requestFullscreen() { requested++; f.document.fullscreenElement = this; }};
  f.document.exitFullscreen = () => { exited++; f.document.fullscreenElement = null; };
  assert.equal(requested, 0);
  await root.fullscreen.fire('click').done;
  assert.equal(requested, 1);
  f.document.fire('fullscreenchange');
  assert.match(root.fullscreen.textContent, /離開全螢幕/);
  await root.fullscreen.fire('click').done;
  assert.equal(exited, 1);
});

test('unsupported iPhone fullscreen gives truthful Home Screen instructions', async () => {
  const f = fixture({userAgent:'iPhone',maxTouchPoints:5}); const root = f.attach();
  await root.fullscreen.fire('click').done;
  assert.match(root.note.textContent, /不支援.*分享.*加入主畫面/);
  assert.equal(root.note.style.display, 'block');
});

test('denied fullscreen reports failure without claiming it opened', async () => {
  const f = fixture(); const root = f.attach();
  f.document.documentElement = {requestFullscreen() { return Promise.reject(new Error('denied')); }};
  await root.fullscreen.fire('click').done;
  assert.match(root.note.textContent, /沒有開啟全螢幕/);
});

test('radial dead zone has continuous analog travel and normalized diagonals', () => {
  const rect = {left: 0, top: 0, width: 100, height: 100};
  assert.deepEqual(joystickAxis(53, 50, rect), [0, 0]);
  const light = joystickAxis(60, 50, rect);
  assert.ok(light[0] > 0 && light[0] < 0.25);
  const diagonal = joystickAxis(100, 100, rect);
  assert.ok(Math.abs(Math.hypot(...diagonal) - 1) < 1e-9);
  assert.equal(diagonal[0], diagonal[1]);
});

test('desktop stays clean; repeated attach creates one overlay', () => {
  const desktop = fixture({userAgent: 'Windows', maxTouchPoints: 0});
  desktop.attach(); assert.equal(desktop.document.body.children.length, 0);
  const f = fixture(); f.attach(); f.attach();
  assert.equal(f.document.body.children.length, 1);
  assert.equal(f.document.head.children.length, 1);
});

test('walking, looking and running work simultaneously with one motion callback per frame', () => {
  const f = fixture(); const root = f.attach();
  root.stick.fire('pointerdown', {pointerId: 1, clientX: 80, clientY: 320});
  root.look.fire('pointerdown', {pointerId: 2, clientX: 200, clientY: 200});
  root.buttons[0].fire('pointerdown', {pointerId: 3});
  for (let i = 1; i <= 30; i++) {
    root.stick.fire('pointermove', {pointerId: 1, clientX: 80 + i, clientY: 320});
    root.look.fire('pointermove', {pointerId: 2, clientX: 200 + i, clientY: 200 + i * 2});
  }
  assert.deepEqual(f.messages, [['action', 'run', 1]]);
  f.env.flush();
  assert.equal(f.messages.filter(row => row[0] === 'axis').length, 1);
  assert.deepEqual(f.messages.find(row => row[0] === 'look'), ['look', 30, 60]);
  root.stick.fire('pointerup', {pointerId: 1});
  assert.deepEqual(f.messages.at(-1), ['axis', 0, 0]);
  assert.equal(root.buttons[0].attributes['aria-pressed'], 'true');
  root.buttons[0].fire('pointerup', {pointerId: 3});
  assert.deepEqual(f.messages.at(-1), ['action', 'run', 0]);
});

test('a second pointer cannot steal an active stick or camera gesture', () => {
  const f = fixture(); const root = f.attach();
  root.stick.fire('pointerdown', {pointerId: 1, clientX: 80, clientY: 320});
  root.stick.fire('pointerdown', {pointerId: 2, clientX: 120, clientY: 360});
  root.stick.fire('pointermove', {pointerId: 2, clientX: 120, clientY: 360});
  root.stick.fire('pointerup', {pointerId: 2});
  root.look.fire('pointerdown', {pointerId: 3, clientX: 10, clientY: 10});
  root.look.fire('pointerdown', {pointerId: 4, clientX: 100, clientY: 100});
  root.look.fire('pointermove', {pointerId: 4, clientX: 200, clientY: 200});
  root.look.fire('pointermove', {pointerId: 3, clientX: 15, clientY: 20});
  f.env.flush();
  assert.equal(f.messages[0][1], 0); assert.ok(f.messages[0][2] < -0.9);
  assert.deepEqual(f.messages[1], ['look', 5, 10]);
});

test('release before animation frame cannot leave stale movement queued', () => {
  const f = fixture(); const root = f.attach();
  root.stick.fire('pointerdown', {clientY: 300});
  root.stick.fire('pointerup');
  f.env.flush();
  assert.deepEqual(f.messages, [['axis', 0, 0]]);
  assert.equal(root.knob.style.transform, '');
});

test('cancellation and lost capture release actions exactly once', () => {
  const f = fixture(); const root = f.attach();
  root.buttons[1].fire('pointerdown');
  root.buttons[1].fire('pointercancel');
  root.buttons[1].fire('lostpointercapture');
  assert.deepEqual(f.messages, [['action', 'jump', 1], ['action', 'jump', 0]]);
  assert.equal(root.buttons[1].attributes['aria-pressed'], 'false');
});

test('two touches on the same action keep it pressed until both release', () => {
  const f = fixture(); const root = f.attach();
  root.buttons[0].fire('pointerdown', {pointerId: 1});
  root.buttons[0].fire('pointerdown', {pointerId: 2});
  root.buttons[0].fire('pointerup', {pointerId: 1});
  assert.deepEqual(f.messages, [['action', 'run', 1]]);
  root.buttons[0].fire('pointerup', {pointerId: 2});
  assert.deepEqual(f.messages.at(-1), ['action', 'run', 0]);
});

test('browser suspension and rotation reset all held input and pending camera motion', () => {
  for (const lifecycle of ['blur', 'pagehide', 'orientationchange', 'resize', 'visibilitychange']) {
    const f = fixture(); const root = f.attach();
    root.stick.fire('pointerdown', {pointerId: 1, clientY: 320});
    root.buttons[0].fire('pointerdown', {pointerId: 2});
    root.look.fire('pointerdown', {pointerId: 3});
    root.look.fire('pointermove', {pointerId: 3, clientX: 200});
    if (lifecycle === 'visibilitychange') { f.document.hidden = true; f.document.fire(lifecycle); }
    else f.env.fire(lifecycle);
    f.env.flush();
    assert.deepEqual(f.messages, [['action', 'run', 1], ['action', 'run', 0], ['axis', 0, 0]], lifecycle);
    assert.equal(root.stick.captured.size, 0);
    assert.equal(root.look.captured.size, 0);
  }
});

test('modal state survives attach, rejects input, and returns controls on close', () => {
  const f = fixture(); f.ui.setModalOpen(true); const root = f.attach();
  assert.equal(root.style.display, 'none'); assert.equal(root.attributes['aria-hidden'], 'true');
  f.messages.length = 0;
  root.buttons[0].fire('pointerdown'); root.stick.fire('pointerdown');
  f.env.flush(); assert.deepEqual(f.messages, []);
  f.ui.setModalOpen(false);
  assert.equal(root.style.display, '');
  root.stick.fire('pointerdown', {clientY: 320}); f.env.flush();
  assert.ok(f.messages.at(-1)[2] < 0);
  f.ui.setModalOpen(true); assert.deepEqual(f.messages.at(-1), ['axis', 0, 0]);
});

test('window release is a fallback when pointer capture fails', () => {
  const f = fixture(); const root = f.attach();
  root.stick.setPointerCapture = () => { throw new Error('capture unavailable'); };
  root.stick.fire('pointerdown', {clientY: 300}); f.env.flush();
  f.env.fire('pointerup');
  assert.deepEqual(f.messages.at(-1), ['axis', 0, 0]);
});

test('replacing the engine callback releases its held actions before rebinding', () => {
  const f = fixture(); const root = f.attach();
  root.buttons[0].fire('pointerdown');
  const next = []; f.ui.attach((...args) => next.push(args));
  assert.deepEqual(f.messages, [['action', 'run', 1], ['action', 'run', 0], ['axis', 0, 0]]);
  root.buttons[1].fire('pointerdown');
  assert.deepEqual(next, [['action', 'jump', 1]]);
});
