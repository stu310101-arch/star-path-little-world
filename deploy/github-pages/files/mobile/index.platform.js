(function () {
  'use strict';
  const mobile = /Android|iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const here = new URL(location.href);
  const mobilePath = /\/mobile\/(?:index\.html)?$/.test(here.pathname);
  const choice = here.searchParams.get('renderer');
  // User agent alone is insufficient (desktop-mode phones and emulators).
  // Probe the actual GPU formats before choosing the ETC2-only package.
  let etc2 = false;
  if (mobile || mobilePath || choice === 'mobile') {
    try {
      const gl = document.createElement('canvas').getContext('webgl2');
      if (gl) {
        gl.getExtension('WEBGL_compressed_texture_etc');
        etc2 = Array.from(gl.getParameter(gl.COMPRESSED_TEXTURE_FORMATS)).includes(0x9278);
        gl.getExtension('WEBGL_lose_context')?.loseContext();
      }
    } catch { /* Use the existing desktop texture path when probing fails. */ }
  }
  const wantsMobile = etc2 && (choice === 'mobile' || (mobile && choice !== 'desktop'));
  window.LittleWorldRedirecting = mobilePath !== wantsMobile;
  if (window.LittleWorldRedirecting) {
    const target = new URL(wantsMobile ? 'mobile/index.html' : '../index.html', here);
    target.search = here.search; target.hash = here.hash;
    location.replace(target.href);
  }
  window.LittleWorldCacheReady = (async () => {
    if (window.LittleWorldRedirecting || !('serviceWorker' in navigator)) return;
    try {
      const root = new URL(mobilePath ? '../' : './', here);
      await Promise.race([
        (async () => {
          await navigator.serviceWorker.register(new URL('index.service-worker.js', root), {scope:root.pathname});
          await navigator.serviceWorker.ready;
          if (!navigator.serviceWorker.controller) await new Promise(resolve => navigator.serviceWorker.addEventListener('controllerchange', resolve, {once:true}));
        })(),
        new Promise(resolve => setTimeout(resolve, 2500)),
      ]);
    } catch { /* Private mode/quota/network failures retain ordinary delivery. */ }
  })();
})();
