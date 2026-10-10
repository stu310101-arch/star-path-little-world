/* Touch input uses the same Godot actions as keyboard input. */
window.LittleWorldTouchUI = {
  attach(callback) {
    const mobile = /Android|iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    if (!mobile || document.getElementById('little-world-touch')) return;
    const root = document.createElement('div'); root.id = 'little-world-touch';
    root.innerHTML = '<div class="lw-stick" aria-label="移動搖桿"><span></span></div><div class="lw-look" aria-label="拖曳轉視角">拖曳轉視角</div><div class="lw-actions"><button data-action="run">奔跑</button><button data-action="jump">跳躍</button><button data-action="interact">互動</button><button data-action="use">使用</button></div>';
    const style = document.createElement('style');
    style.textContent = '#little-world-touch{position:fixed;inset:0;pointer-events:none;z-index:15;font:14px system-ui;color:white;user-select:none;-webkit-user-select:none}#little-world-touch .lw-stick{position:absolute;left:max(20px,env(safe-area-inset-left));bottom:calc(24px + env(safe-area-inset-bottom));width:110px;height:110px;border:2px solid #ffffff80;border-radius:50%;background:#143e4380;pointer-events:auto;touch-action:none}#little-world-touch .lw-stick span{position:absolute;left:35px;top:35px;width:40px;height:40px;border-radius:50%;background:#ffedbec0}#little-world-touch .lw-look{position:absolute;right:20px;bottom:calc(140px + env(safe-area-inset-bottom));width:150px;height:100px;display:grid;align-items:end;text-align:center;border:1px solid #ffffff30;border-radius:20px;color:#ffffffb0;pointer-events:auto;touch-action:none}#little-world-touch .lw-actions{position:absolute;right:max(16px,env(safe-area-inset-right));bottom:calc(24px + env(safe-area-inset-bottom));display:grid;grid-template-columns:repeat(2,64px);gap:8px;pointer-events:auto}#little-world-touch button{height:48px;border:1px solid #ffffff80;border-radius:16px;background:#143e43bb;color:white;font:inherit;touch-action:none}#little-world-touch button:active{background:#507872}';
    document.head.append(style); document.body.append(root);
    const held = new Map();
    const reset = () => {for(const action of held.values())callback('action',action,0);held.clear();stickId=null;lookId=null;last=null;callback('axis',0,0);root.querySelector('.lw-stick span').style.transform='';};
    for (const button of root.querySelectorAll('button')) {
      button.addEventListener('pointerdown', event => {event.preventDefault();button.setPointerCapture(event.pointerId);held.set(event.pointerId,button.dataset.action);callback('action',button.dataset.action,1);});
      const release = event => {const action=held.get(event.pointerId);if(action){callback('action',action,0);held.delete(event.pointerId);}};
      button.addEventListener('pointerup',release);button.addEventListener('pointercancel',release);button.addEventListener('lostpointercapture',release);
    }
    const stick=root.querySelector('.lw-stick'),look=root.querySelector('.lw-look');
    let stickId=null,lookId=null,last=null;
    const axis = event => {const r=stick.getBoundingClientRect();let x=(event.clientX-r.left-r.width/2)/45,y=(event.clientY-r.top-r.height/2)/45;const length=Math.hypot(x,y);if(length<.12)x=y=0;else if(length>1){x/=length;y/=length;}callback('axis',x,y);stick.firstElementChild.style.transform=`translate(${x*35}px,${y*35}px)`;};
    stick.addEventListener('pointerdown',event=>{event.preventDefault();if(stickId!==null)return;stickId=event.pointerId;stick.setPointerCapture(stickId);axis(event);});
    stick.addEventListener('pointermove',event=>{if(event.pointerId===stickId)axis(event);});
    const releaseStick=event=>{if(event.pointerId===stickId){stickId=null;callback('axis',0,0);stick.firstElementChild.style.transform='';}};
    for(const type of ['pointerup','pointercancel','lostpointercapture'])stick.addEventListener(type,releaseStick);
    look.addEventListener('pointerdown',event=>{event.preventDefault();if(lookId!==null)return;lookId=event.pointerId;last=[event.clientX,event.clientY];look.setPointerCapture(lookId);});
    look.addEventListener('pointermove',event=>{if(event.pointerId===lookId){callback('look',event.clientX-last[0],event.clientY-last[1]);last=[event.clientX,event.clientY];}});
    const releaseLook=event=>{if(event.pointerId===lookId){lookId=null;last=null;}};
    for(const type of ['pointerup','pointercancel','lostpointercapture'])look.addEventListener(type,releaseLook);
    window.addEventListener('blur',reset);
    document.addEventListener('visibilitychange',()=>{if(document.hidden)reset();});
  }
};
