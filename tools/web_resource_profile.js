(function () {
  'use strict';
  const KEY = 'little-world-resource-profile-v1';
  const valid = value => value === 'low' || value === 'full';
  const read = () => {try {return localStorage.getItem(KEY);} catch {return null;}};
  const save = value => {try {localStorage.setItem(KEY, value);} catch {/* Session choice remains usable. */}};
  const here = new URL(location.href);
  const forced = here.searchParams.get('pack');
  window.LittleWorldResourceProfile = valid(forced) ? forced : valid(read()) ? read() : '';
  window.LittleWorldUseResources = value => {
    if (!valid(value)) return;
    save(value);
    const target = new URL(location.href);
    target.searchParams.set('pack', value);
    location.replace(target.href);
  };
  window.LittleWorldChooseResources = () => {
    try {localStorage.removeItem(KEY);} catch {}
    const target = new URL(location.href);target.searchParams.delete('pack');location.replace(target.href);
  };
  window.LittleWorldResourceReady = new Promise(resolve => {
    if (window.LittleWorldRedirecting) return;
    if (window.LittleWorldResourceProfile) {resolve(); return;}
    const show = () => {
      const overlay = document.createElement('section');
      overlay.id = 'resource-choice';
      overlay.setAttribute('role', 'dialog');
      overlay.setAttribute('aria-modal', 'true');
      overlay.setAttribute('aria-labelledby', 'resource-choice-title');
      overlay.innerHTML = `<style>
        #resource-choice{position:fixed;inset:0;z-index:9999;overflow:auto;box-sizing:border-box;display:grid;place-items:center;background:#173b3d;color:#f7f3e7;padding:calc(24px + env(safe-area-inset-top)) 20px calc(24px + env(safe-area-inset-bottom));font:16px/1.7 system-ui,sans-serif}
        #resource-choice main{width:min(100%,560px)}#resource-choice h1{font-size:clamp(24px,5vw,34px);line-height:1.35}#resource-choice p{color:#d2ded6}
        #resource-choice button{font:inherit;display:block;width:100%;min-height:60px;border:1px solid #96b8aa;border-radius:12px;padding:16px;margin:14px 0;background:#f7f3e7;color:#173b3d;text-align:left;cursor:pointer}
        #resource-choice button:focus-visible{outline:3px solid #e7b579;outline-offset:4px}#resource-choice small{display:block;font-size:14px;line-height:1.6}#resource-choice footer{font-size:13px;color:#b4c9bf}
      </style><main><p>星途 · Little World</p><h1 id="resource-choice-title">先選擇適合你的材質包</h1><p>下載完成後開始探索。之後可在主頁「畫面設定」下載另一個包，切換時選擇保留或刪除原資源包。</p><button data-pack="low"><strong>下載低階材質包</strong><small>降低貼圖解析度與場景密度，保留原有美術風格；抽減樹木、建物、船舶與魚群，移除櫻花林區域。保留各區主要功能與全部留言裝置。適合手機或較低規格裝置。</small></button><button data-pack="full"><strong>下載滿血材質包</strong><small>保留現有完整場景、模型與美術細節。需要較多下載流量與儲存空間。</small></button><footer>此選擇會儲存在這台裝置。遊戲中的文字與操作功能保留。</footer></main>`;
      document.body.appendChild(overlay);
      for (const button of overlay.querySelectorAll('[data-pack]')) button.addEventListener('click', () => {
        const value = button.dataset.pack;
        save(value); window.LittleWorldResourceProfile = value;
        overlay.remove(); resolve();
      }, {once:true});
      overlay.querySelector('button').focus();
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', show, {once:true});
    else show();
  });

  // Godot polls these scalar properties while worker operations run asynchronously.
  // Cached status comes from CacheStorage, never from a localStorage download flag.
  const store = window.LittleWorldResourceStore = {
    busy:false, ok:false, error:'', installed:{},
    cached(profile) {return this.installed[profile] === true;},
    run(action, profile) {
      if (this.busy || !valid(profile)) return;
      this.busy = true; this.ok = false; this.error = '';
      void (async () => {
        try {
          await window.LittleWorldCacheReady;
          if ('serviceWorker' in navigator && !navigator.serviceWorker.controller) await Promise.race([
            new Promise(resolve => navigator.serviceWorker.addEventListener('controllerchange', resolve, {once:true})),
            new Promise(resolve => setTimeout(resolve, 15000)),
          ]);
          const worker = navigator.serviceWorker?.controller;
          if (!worker) throw Error('資源快取尚未就緒');
          const response = await new Promise((resolve, reject) => {
            const channel = new MessageChannel();
            const timer = setTimeout(() => {channel.port1.close(); reject(Error('資源快取回應逾時'));}, 30000);
            channel.port1.onmessage = event => {clearTimeout(timer); channel.port1.close(); resolve(event.data);};
            worker.postMessage({type:'little-world-profile',action,profile,renderer:/\/mobile\/(?:index\.html)?$/.test(location.pathname)?'mobile':'desktop'}, [channel.port2]);
          });
          this.installed = response.installed || {};
          if (!response.ok) throw Error(response.error || '無法更新資源快取');
          this.ok = true;
        } catch (error) {this.error = error.message;}
        finally {this.busy = false;}
      })();
    },
  };

  // Android's native install prompt and iOS's Share-menu instructions share one entry.
  let prompt = null;
  let installButton = null;
  const standalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const install = async () => {
    if (prompt) {const event = prompt; prompt = null; await event.prompt(); await event.userChoice;}
    else {
      const ios = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
      window.alert(ios ? '加入手機主畫面：開啟瀏覽器的「分享」選單 →「加入主畫面」→「加入」。' : '開啟瀏覽器選單，選擇「安裝應用程式」或「加到主畫面」。');
    }
  };
  window.LittleWorldInstallApp = install;
  window.addEventListener('beforeinstallprompt', event => {event.preventDefault(); prompt = event;});
  window.addEventListener('appinstalled', () => {prompt = null; installButton?.remove();});
  const showInstall = () => {
    if (standalone() || !window.LittleWorldMobileMode || window.LittleWorldRedirecting) return;
    installButton = document.createElement('button');
    installButton.id = 'pwa-install'; installButton.textContent = '加入手機主畫面';
    installButton.style.cssText = 'position:fixed;right:max(12px,env(safe-area-inset-right));bottom:max(12px,env(safe-area-inset-bottom));z-index:10000;min-height:44px;padding:8px 14px;border:1px solid #96b8aa;border-radius:10px;background:#173b3d;color:#f7f3e7;font:14px system-ui;cursor:pointer';
    installButton.addEventListener('click', install);
    document.body.appendChild(installButton);
    // Gameplay already uses the phone's bottom controls; installation remains
    // available from the browser menu after leaving the initial selection.
    void window.LittleWorldResourceReady.then(() => installButton?.remove());
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', showInstall, {once:true});
  else showInstall();
})();
