/* One lazy, same-origin account host for the lifetime of the world page. */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) module.exports = {create: factory};
  else root.LittleWorldAccountBridge = factory(root);
})(typeof window === 'undefined' ? globalThis : window, function create(env) {
  'use strict';
  const doc = env.document, origin = new URL(env.location.href).origin;
  const channel = 'starpath-account', views = new Set(['query', 'general', 'special', 'apcs', 'scores', 'account', 'forum', 'wordking', 'go']);
  const titles = {query:'落點分析工作台',general:'一般大學工作台',special:'特殊招生工作台',apcs:'APCS 工作台',scores:'我的成績紀錄',account:'星途共用帳號',forum:'校園生活誌',wordking:'WordKing 單字王',go:'星途圍棋'};
  const identities = new Set(['high_school', 'graduate', 'university', 'professional']);
  const zones = new Set(['university', 'major', 'career', 'high_school', 'campus']);
  let ui = null, opened = false, ready = false, loading = false, view = 'account';
  let user = null, error = '', timer = null, pendingSignOut = false, childDocument = null;
  let resolved = false;
  let savedOverflow = '', savedInert = false, escapeReleased = true;
  let sessionGeneration = 0, pendingForumContext = null, forumQueue = [], progressQueue = [];
  const forumRequests = new Map();
  const deviceCodes = {university:'UN',major:'MA',career:'CA',high_school:'HS',campus:'CL'};
  const validDevice = (id, zone) => typeof id === 'string' && new RegExp('^SPDEV'+deviceCodes[zone]+'000000[0-9]{6}[0-7]$').test(id);
  const progressRequests = new Set();
  let interestQueue = [];
  const interestRequests = new Map();
  let recommendationQueue = [];
  const recommendationRequests = new Map();
  const interestLimit = 65536;
  const interestId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(value);
  const nonnegative = value => Number.isSafeInteger(value) && value >= 0;
  const exact = (data, keys) => data && typeof data === 'object' && !Array.isArray(data) && Object.keys(data).length === keys.length && keys.every(key => Object.hasOwn(data,key));
  const interestText = (value, maximum) => typeof value === 'string' && Array.from(value).length <= maximum && !/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value);
  const interestGroups = new Set(['information','engineering','math-chemistry','health-medicine','life-science','bio-resources','earth-environment','architecture-design','arts','social-psychology','mass-communication','foreign-languages','literature-history-philosophy','education','law-politics','management','finance-economics','recreation-sports']);
  const bytes = value => new TextEncoder().encode(JSON.stringify(value)).length;
  const isId = value => typeof value === 'string' && /^[A-Za-z0-9]{20}$/.test(value);
  function object(input) { try { if (typeof input === 'string') input = JSON.parse(input); return input && typeof input === 'object' && !Array.isArray(input) && bytes(input) <= 4096 ? input : null; } catch (_) { return null; } }
  function interestObject(input) { try { if (typeof input === 'string') { if (new TextEncoder().encode(input).length > interestLimit) return null; input=JSON.parse(input); } return input && typeof input === 'object' && !Array.isArray(input) && bytes(input)<=interestLimit ? input : null; } catch (_) { return null; } }
  function interestProfile(input) {
    if (!exact(input,['schemaVersion','catalogVersion','title','riasecDate','knowledgeDate','riasec','knowledge','bestFits','suitableFits']) || bytes(input)>61440 || input.schemaVersion!==1 || input.catalogVersion!==1 || !interestText(input.title,80) || !interestText(input.riasecDate,32) || !interestText(input.knowledgeDate,32)) return null;
    const clean={schemaVersion:1,catalogVersion:1,title:input.title,riasecDate:input.riasecDate,knowledgeDate:input.knowledgeDate,riasec:{},knowledge:{},bestFits:[],suitableFits:[]};
    for(const [field,keys] of [['riasec',['R','I','A','S','E','C']],['knowledge',Array.from({length:33},(_,i)=>'k'+String(i+1).padStart(2,'0'))]]) {
      if(!exact(input[field],keys)) return null;
      for(const key of keys) { if(!interestText(input[field][key],32)) return null; clean[field][key]=input[field][key]; }
    }
    for(const field of ['bestFits','suitableFits']) {
      if(!Array.isArray(input[field]) || input[field].length>512) return null;
      for(const row of input[field]) {
        if(!exact(row,['groupId','category','z']) || !interestText(row.groupId,40) || (row.groupId!==''&&!interestGroups.has(row.groupId)) || !interestText(row.category,80) || !interestText(row.z,32)) return null;
        clean[field].push({groupId:row.groupId,category:row.category,z:row.z});
      }
    }
    return clean;
  }
  const interestCursor = value => exact(value,['createdAtMillis','id']) && nonnegative(value.createdAtMillis) && interestId(value.id);
  function requestBase(data) { return data && typeof data.requestId === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(data.requestId) && Number.isSafeInteger(data.sessionGeneration) && data.sessionGeneration === sessionGeneration && user?.profileReady === true; }
  const stop = event => event.stopPropagation();
  const swallow = event => { event.preventDefault(); event.stopImmediatePropagation(); };
  const node = (tag, text) => {
    const value = doc.createElement(tag);
    if (text) value.textContent = text;
    return value;
  };
  function clearTimer() { if (timer !== null) env.clearTimeout(timer); timer = null; }
  function send(type, extra = {}) {
    if (ready && ui) ui.frame.contentWindow.postMessage({channel, version: 1, type, ...extra}, origin);
  }
  function escape(event) {
    if (!opened || event.key !== 'Escape') return;
    swallow(event); escapeReleased = false; close();
  }
  function keyboard(event) {
    if (event.type === 'keyup' && event.key === 'Escape' && !escapeReleased) {
      swallow(event); escapeReleased = true; return;
    }
    if (!opened) return;
    if (event.type === 'keydown' && event.key === 'Escape') { escape(event); return; }
    if (!ui.root.contains(event.target)) { swallow(event); ui.back.focus(); }
    else if (event.key === 'Tab' && event.shiftKey && event.target === ui.back) {
      event.preventDefault(); (ready ? ui.frame : ui.retry.hidden ? ui.back : ui.retry).focus();
    }
  }
  function fail() {
    if (!ui) return;
    send('suspend');
    clearTimer(); ready = false; loading = false;
    error = '無法載入星途帳號服務。請重試，或返回世界稍後再試。';
    ui.status.hidden = false; ui.frame.hidden = true; ui.retry.hidden = false;
    ui.message.textContent = error;
  }
  function load() {
    clearTimer();
    if (childDocument) childDocument.removeEventListener('keydown', escape, true);
    childDocument = null; ready = false; loading = true; error = ''; resolved = false;
    ui.status.hidden = false; ui.frame.hidden = true; ui.retry.hidden = true;
    ui.message.textContent = '正在載入落點分析與星途帳號…';
    timer = env.setTimeout(fail, 30000);
    // Absolute root path is intentional: /mobile/ must use the same account host.
    ui.frame.src = new URL('/admissions/host/?platform=web&view=' + view, origin).href;
  }
  function ensureUI() {
    if (ui) return;
    const style = node('style');
    style.textContent = `
      .lw-account-shade{position:fixed;inset:0;z-index:2147483645;background:rgba(9,28,30,.23)}
      .lw-account {position:fixed;left:18.5vw;top:9vh;top:9dvh;width:78vw;height:82vh;height:82dvh;
        z-index:2147483646;display:flex;flex-direction:column;box-sizing:border-box;padding:0 12px 6px;
        border:2px solid #bba576;border-radius:18px;background:#173b3d;color:#f6ecd3;
        box-shadow:0 14px 0 rgba(7,27,29,.38),0 28px 64px rgba(4,20,22,.35),inset 0 1px 0 #82978b;
        font:16px/1.5 system-ui,"Microsoft JhengHei",sans-serif}
      .lw-account[hidden],.lw-account [hidden],.lw-account-shade[hidden]{display:none!important}
      .lw-account header{display:flex;align-items:center;justify-content:space-between;gap:8px;min-height:58px;padding:2px 6px}
      .lw-account h1{font-size:20px;letter-spacing:.08em;margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      .lw-account button{font:inherit;min-height:44px;flex:none;padding:8px 14px;border:1px solid #d7b878;
        background:#efd7a5;border-radius:9px;color:#203e46;cursor:pointer}
      .lw-account button:hover{background:#fff0ca}.lw-account button:focus-visible{outline:3px solid #f8edcf;outline-offset:2px}
      .lw-account main{display:flex;flex:1;min-height:0;background:#f6f3e9;border:1px solid #82978b;border-radius:3px;overflow:hidden}
      .lw-account iframe{width:100%;height:100%;border:0;background:#f6f3e9}
      .lw-account footer{font-size:11px;letter-spacing:.06em;color:#b9c7b8;padding:5px 4px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      @media(max-width:900px),(max-aspect-ratio:5/4){.lw-account{left:8px;top:max(8px,env(safe-area-inset-top),3.5dvh);
        width:calc(100vw - 16px);height:calc(93dvh - env(safe-area-inset-bottom));padding:0 6px 5px;border-radius:12px}
        .lw-account header{min-height:54px;padding:2px 3px}.lw-account h1{font-size:16px;letter-spacing:.02em}
        .lw-account button{font-size:14px;padding:8px 10px}.lw-account footer{font-size:10px}}
      .lw-account-status{margin:auto;text-align:center;padding:24px}
      .lw-account-status p{color:#244f4b}
    `;
    const shade = node('div'); shade.className = 'lw-account-shade'; shade.hidden = true;
    const root = node('section'); root.className = 'lw-account'; root.hidden = true;
    root.setAttribute('role', 'dialog'); root.setAttribute('aria-modal', 'true'); root.setAttribute('aria-label', '星途帳號與落點分析');
    const header = node('header'), title = node('h1', '落點分析工作台');
    const back = node('button', '離開螢幕 Esc'); back.type = 'button'; back.addEventListener('click', close);
    header.appendChild(title); header.appendChild(back);
    const main = node('main'), status = node('div'); status.className = 'lw-account-status';
    const message = node('p'); message.setAttribute('role', 'status'); message.setAttribute('aria-live', 'polite');
    const retry = node('button', '重新載入'); retry.type = 'button'; retry.hidden = true; retry.addEventListener('click', load);
    status.appendChild(message); status.appendChild(retry);
    const frame = node('iframe'); frame.title = '落點分析與我的成績'; frame.hidden = true;
    frame.referrerPolicy = 'same-origin';
    // Reviewed same-origin application; Firebase Auth needs its origin storage.
    frame.onerror = fail;
    main.appendChild(status); main.appendChild(frame); root.appendChild(header); root.appendChild(main);
    root.appendChild(node('footer', '星途・學習工作站  /  每一次練習，都讓方向更清楚'));
    for (const name of ['keydown', 'keyup', 'keypress', 'pointerdown', 'pointerup', 'click', 'wheel']) root.addEventListener(name, stop);
    doc.head.appendChild(style); doc.body.appendChild(shade); doc.body.appendChild(root);
    ui = {root, shade, style, title, back, frame, status, message, retry};
    doc.addEventListener('keydown', keyboard, true); doc.addEventListener('keyup', keyboard, true);
  }
  function receive(event) {
    if (!ui || event.origin !== origin || event.source !== ui.frame.contentWindow) return;
    const data = event.data;
    if (data?.channel === 'starpath-recommendations') { receiveRecommendation(data); return; }
    if (data?.channel === 'starpath-interest') { receiveInterest(data); return; }
    if (data?.channel === 'starpath-forum') { receiveForum(data); return; }
    if (data?.channel === 'starpath-progress') { receiveProgress(data); return; }
    if (!data || typeof data !== 'object' || data.channel !== channel || data.version !== 1) return;
    if (data.type === 'ready') {
      if (!loading) return;
      clearTimer(); ready = true; loading = false; error = '';
      ui.status.hidden = true; ui.frame.hidden = false;
      try {
        if (childDocument) childDocument.removeEventListener('keydown', escape, true);
        childDocument = ui.frame.contentDocument;
        childDocument?.addEventListener('keydown', escape, true);
      } catch (_) { fail(); return; }
      send('navigate', {view});
      if (pendingForumContext) { send('forum-open', {context: pendingForumContext}); pendingForumContext = null; }
      if (pendingSignOut) { pendingSignOut = false; send('sign-out'); }
      if (opened) ui.frame.focus();
    } else if (data.type === 'auth-state') {
      const generation = Number.isSafeInteger(data.sessionGeneration) ? data.sessionGeneration : Number.isSafeInteger(data.user?.sessionGeneration) ? data.user.sessionGeneration : 0;
      if (generation < sessionGeneration) return;
      resolved = data.resolving !== true;
      if (generation !== sessionGeneration) { sessionGeneration = generation; forumQueue = []; progressQueue = []; forumRequests.clear(); progressRequests.clear(); interestQueue=[]; interestRequests.clear(); recommendationQueue=[]; recommendationRequests.clear(); }
      if (data.user === null || data.user === undefined) user = null;
      else if (data.user.signedIn === true &&
        (data.user.displayName === undefined || typeof data.user.displayName === 'string')) {
        const identity = identities.has(data.user.identity) ? data.user.identity : '';
        user = {signedIn: true, displayName: Array.from(data.user.displayName || '').slice(0, 40).join(''), identity, profileReady: data.user.profileReady === true && !!identity, sessionGeneration};
      }
      if (!user?.profileReady) { forumQueue = []; progressQueue = []; forumRequests.clear(); progressRequests.clear(); interestQueue=[]; interestRequests.clear(); recommendationQueue=[]; recommendationRequests.clear(); }
    } else if (data.type === 'close' && opened) close();
    // Browser OAuth is initiated by the host's actual click, never by an
    // untrusted postMessage asking this bridge to open an arbitrary URL.
  }
  env.addEventListener('message', receive);
  function receiveForum(data) {
    if (!object(data) || data.version !== 1 || !requestBase(data)) return;
    const forumRequest = forumRequests.get(data.zone);
    if (!forumRequest || data.requestId !== forumRequest.requestId) return;
    const base = {channel:'starpath-forum',version:1,type:data.type,requestId:data.requestId,sessionGeneration,zone:data.zone};
    if (data.type === 'page-begin' && Number.isInteger(data.count) && data.count >= 0 && data.count <= 8) {
      if (data.devicePage !== undefined && (!forumRequest.devices || !Number.isInteger(data.devicePage) || data.devicePage < 0 || data.devicePage > 999999)) return;
      forumQueue = forumQueue.filter(item => item.zone !== data.zone);
      forumQueue.push({...base,count:data.count,...(data.devicePage !== undefined ? {devicePage:data.devicePage} : {})});
    }
    else if (data.type === 'page-empty' && forumRequest.devices && Number.isInteger(data.index) && data.index >= 0 && data.index < 8 && validDevice(data.threadId,data.zone)) {
      forumQueue.push({...base,index:data.index,threadId:data.threadId});
    }
    else if (data.type === 'page-item' && Number.isInteger(data.index) && data.index >= 0 && data.index < 8 && isId(data.threadId) && typeof data.preview === 'string' && Array.from(data.preview).length <= 120 && typeof data.authorName === 'string' && Array.from(data.authorName).length <= 40 && identities.has(data.identity) && typeof data.anonymous === 'boolean' && typeof data.deleted === 'boolean' && Number.isFinite(data.createdAtMillis) && Number.isFinite(data.updatedAtMillis)) {
      if (forumQueue.filter(item => item.zone === data.zone && ['page-item','page-empty'].includes(item.type)).length >= 8) return;
      forumQueue.push({...base,index:data.index,threadId:data.threadId,preview:data.preview,authorName:data.anonymous ? '匿名' : data.authorName,identity:data.identity,anonymous:data.anonymous,deleted:data.deleted,createdAtMillis:data.createdAtMillis,updatedAtMillis:data.updatedAtMillis});
    } else if (data.type === 'page-end' && typeof data.hasNext === 'boolean' && typeof data.hasPrevious === 'boolean' && Number.isInteger(data.count) && data.count >= 0 && data.count <= 8) forumQueue.push({...base,hasNext:data.hasNext,hasPrevious:data.hasPrevious,count:data.count});
    else if (data.type === 'page-error') { forumQueue = [...forumQueue.filter(item => item.zone !== data.zone),{...base,message:'交流留言暫時無法載入，請重新整理後再試。'}]; }
    if (forumQueue.filter(item => item.zone === data.zone).length > 10) forumQueue = forumQueue.filter(item => item.zone !== data.zone);
  }
  function receiveProgress(data) {
    if (!object(data) || data.version !== 1 || data.app !== 'university' || !requestBase(data) || !progressRequests.has(data.requestId)) return;
    const base = {channel:'starpath-progress',version:1,type:data.type,app:'university',requestId:data.requestId,sessionGeneration};
    if (data.type === 'state' && Number.isSafeInteger(data.revision) && data.revision >= 0 && data.favorites && typeof data.favorites === 'object' && !Array.isArray(data.favorites) && Object.entries(data.favorites).length <= 138 && Object.entries(data.favorites).every(([id,value]) => /^\d{3}$/.test(id) && typeof value === 'boolean') && Array.isArray(data.explored) && data.explored.length <= 138 && data.explored.every(id => typeof id === 'string' && /^\d{3}$/.test(id))) {
      progressQueue.push({...base,favorites:Object.fromEntries(Object.entries(data.favorites)),explored:[...data.explored],revision:data.revision});
    } else if (data.type === 'error') progressQueue.push({...base,message:'大學館進度暫時無法同步，請確認網路後重試。'});
    else return;
    progressRequests.delete(data.requestId);
    if (progressQueue.length > 32) progressQueue.shift();
  }
  function requestForumPage(input) {
    const data = object(input);
    if (!ready || !requestBase(data) || !zones.has(data.zone) || !['first','next','previous','refresh'].includes(data.direction)) return false;
    if (data.devices !== undefined && typeof data.devices !== 'boolean') return false;
    const forumRequest = {requestId:data.requestId,sessionGeneration,zone:data.zone,direction:data.direction,...(data.devices === true ? {devices:true} : {})};
    forumRequests.set(data.zone,forumRequest); forumQueue = forumQueue.filter(item => item.zone !== data.zone);
    send('forum-page', {command:forumRequest}); return true;
  }
  function openForum(input) {
    const data = object(input);
    if (!data || !zones.has(data.zone) || (data.threadId !== undefined && !isId(data.threadId)) || (data.compose !== undefined && typeof data.compose !== 'boolean') || (data.threadId && data.compose)) return false;
    if (data.deviceId !== undefined && (!validDevice(data.deviceId,data.zone) || data.threadId || data.compose)) return false;
    const context = {zone:data.zone,...(data.threadId ? {threadId:data.threadId} : {}),...(data.compose ? {compose:true} : {}),...(data.deviceId ? {deviceId:data.deviceId} : {})};
    if (!open('forum')) return false;
    if (ready) send('forum-open',{context}); else pendingForumContext = context;
    return true;
  }
  function progressCommand(input) {
    const data = object(input);
    if (!ready || !requestBase(data)) return false;
    const command = {requestId:data.requestId,sessionGeneration,action:data.action};
    if (data.action === 'university-favorite' || data.action === 'university-explored') {
      if (typeof data.id !== 'string' || !/^\d{3}$/.test(data.id)) return false;
      command.id = data.id;
      if (data.action === 'university-favorite') { if (typeof data.value !== 'boolean') return false; command.value = data.value; }
    } else if (data.action === 'university-import') {
      if (![data.visited_ids,data.favorite_ids].every(value => Array.isArray(value) && value.length <= 138 && value.every(id => typeof id === 'string' && /^\d{3}$/.test(id)))) return false;
      command.visited_ids = [...data.visited_ids]; command.favorite_ids = [...data.favorite_ids];
    } else if (data.action !== 'university-get') return false;
    if (progressRequests.size >= 32) return false;
    progressRequests.add(command.requestId); send('progress-command',{command}); return true;
  }
  function interestCommand(input) {
    const data=interestObject(input);
    if(!ready || !requestBase(data)) return false;
    const keys=['requestId','sessionGeneration','action'], command={requestId:data.requestId,sessionGeneration,action:data.action};
    if(data.action==='list') {
      if(data.cursor!==undefined) { if(!interestCursor(data.cursor)) return false; keys.push('cursor'); command.cursor={createdAtMillis:data.cursor.createdAtMillis,id:data.cursor.id}; }
    } else if(['get','saveDraft','complete','setActive'].includes(data.action)) {
      if(!interestId(data.recordId)) return false;
      keys.push('recordId'); command.recordId=data.recordId;
      if(data.action==='setActive') { if(!nonnegative(data.expectedSelectionRevision)) return false; keys.push('expectedSelectionRevision'); command.expectedSelectionRevision=data.expectedSelectionRevision; }
      else if(data.action==='saveDraft'||data.action==='complete') {
        const profile=interestProfile(data.profile); if(!profile || !nonnegative(data.expectedRevision)) return false;
        keys.push('expectedRevision','profile'); command.expectedRevision=data.expectedRevision; command.profile=profile;
      }
    } else return false;
    if(!exact(data,keys)) return false;
    for(const [id,request] of interestRequests) if(Date.now()-request.at>60000) interestRequests.delete(id);
    const signature=JSON.stringify(command), prior=interestRequests.get(data.requestId);
    if(prior ? prior.signature!==signature : interestRequests.size>=8) return false;
    interestRequests.set(data.requestId,{action:data.action,recordId:data.recordId,signature,at:Date.now()}); send('interest-command',{command}); return true;
  }
  function receiveInterest(input) {
    const data=interestObject(input);
    if(!data || data.version!==1 || !requestBase(data) || !interestRequests.has(data.requestId)) return;
    const request=interestRequests.get(data.requestId);
    const clean={channel:'starpath-interest',version:1,type:data.type,requestId:data.requestId,sessionGeneration};
    if(data.type==='error') {
      if(!interestText(data.code,80)||!interestText(data.message,240)) return;
      clean.code=data.code; clean.message=data.message;
    } else {
      if(typeof data.activeRecordId!=='string'||(data.activeRecordId!==''&&!interestId(data.activeRecordId))||!nonnegative(data.selectionRevision)) return;
      clean.activeRecordId=data.activeRecordId; clean.selectionRevision=data.selectionRevision;
      if(data.type==='active'&&request.action==='setActive') { /* selection acknowledgement */ }
      else if(data.type==='state'&&['get','saveDraft','complete'].includes(request.action)) {
        if(!interestId(data.recordId)||data.recordId!==request.recordId||!nonnegative(data.revision)||!nonnegative(data.updatedAtMillis)||typeof data.hasCompleted!=='boolean'||typeof data.hasDraft!=='boolean') return;
        const profile=data.profile===null?null:interestProfile(data.profile);
        if(data.profile!==null&&!profile || profile===null&&(data.hasCompleted||data.hasDraft||data.revision!==0)) return;
        Object.assign(clean,{recordId:data.recordId,revision:data.revision,profile,hasCompleted:data.hasCompleted,hasDraft:data.hasDraft,updatedAtMillis:data.updatedAtMillis});
      } else if(data.type==='list'&&request.action==='list') {
        if(!Array.isArray(data.records)||data.records.length>20||(data.nextCursor!==null&&!interestCursor(data.nextCursor))) return;
        clean.records=[];
        for(const row of data.records) {
          if(!interestId(row?.id)||!interestText(row.title,80)||!interestText(row.riasecDate,32)||!interestText(row.knowledgeDate,32)||!nonnegative(row.revision)||!nonnegative(row.createdAtMillis)||!nonnegative(row.updatedAtMillis)||typeof row.hasCompleted!=='boolean'||typeof row.hasDraft!=='boolean') return;
          clean.records.push(Object.fromEntries(['id','title','riasecDate','knowledgeDate','revision','createdAtMillis','updatedAtMillis','hasCompleted','hasDraft'].map(key=>[key,row[key]])));
        }
        clean.nextCursor=data.nextCursor===null?null:{id:data.nextCursor.id,createdAtMillis:data.nextCursor.createdAtMillis};
      } else return;
    }
    interestRequests.delete(data.requestId); interestQueue.push(clean);
    if(interestQueue.length>8) interestQueue.shift();
  }
  const recommendationTypes = {bootstrap:'bootstrap',listExams:'exams',query:'results',page:'results',detail:'detail',saveSettings:'settings',listFavorites:'favorites',setFavorite:'favorite'};
  const programRef = value => typeof value==='string' && /^(113|114|115):[0-9]{6}$/.test(value);
  const recommendationCursor = value => value===null || (typeof value==='string' && value.length>0 && interestText(value,2048));
  function recommendationSafe(value,depth=0) {
    if(depth>10) return false;
    if(Array.isArray(value)) return value.length<=1024 && value.every(child=>recommendationSafe(child,depth+1));
    if(value && typeof value==='object') return Object.keys(value).length<=80 && Object.entries(value).every(([key,child])=>!['uid','token','idToken','accessToken','refreshToken','password','credential','customToken','path','__proto__','constructor','prototype'].includes(key) && recommendationSafe(child,depth+1));
    return value===null || typeof value==='boolean' || (typeof value==='number' && Number.isFinite(value)) || interestText(value,8192);
  }
  function recommendationSettings(value) {
    return exact(value,['source','manual','examId','mode','year','applicantGender','filters']) && ['activeReport','manual'].includes(value.source) && Array.isArray(value.manual) && value.manual.length<=128 && value.manual.every(row=>exact(row,['groupId','category','level']) && interestGroups.has(row.groupId) && interestText(row.category,80) && row.category.trim() && [1,2].includes(row.level)) && (value.examId===''||interestId(value.examId)) && ['balanced','interest','academic'].includes(value.mode) && value.year==='115' && ['','male','female'].includes(value.applicantGender) && exact(value.filters,['keyword','category','status']) && interestText(value.filters.keyword,80) && interestText(value.filters.category,80) && ['all','passed','failed','pending','explore','extension'].includes(value.filters.status);
  }
  function recommendationCommand(input) {
    const data=interestObject(input);
    if(!ready || !data || !requestBase(data) || !recommendationSafe(data) || !Object.hasOwn(recommendationTypes,data.action)) return false;
    const keys=['requestId','sessionGeneration','action'];
    if(['listExams','listFavorites'].includes(data.action)) { keys.push('cursor'); if(!recommendationCursor(data.cursor)) return false; }
    if(['query','saveSettings'].includes(data.action)) { keys.push('settings'); if(!recommendationSettings(data.settings)) return false; }
    if(data.action==='saveSettings') { keys.push('expectedRevision'); if(!nonnegative(data.expectedRevision)) return false; }
    if(['page','detail'].includes(data.action)) { keys.push('queryId'); if(!interestId(data.queryId)) return false; }
    if(data.action==='page') { keys.push('cursor'); if(data.cursor===null || !recommendationCursor(data.cursor)) return false; }
    if(['detail','setFavorite'].includes(data.action)) { keys.push('programRef'); if(!programRef(data.programRef)) return false; }
    if(data.action==='setFavorite') { keys.push('value','expectedRevision'); if(typeof data.value!=='boolean' || !nonnegative(data.expectedRevision)) return false; }
    if(!exact(data,keys)) return false;
    for(const [id,request] of recommendationRequests) if(Date.now()-request.at>60000) recommendationRequests.delete(id);
    const signature=JSON.stringify(data), previous=recommendationRequests.get(data.requestId);
    if(previous ? previous.signature!==signature : recommendationRequests.size>=8) return false;
    const command=JSON.parse(signature);
    recommendationRequests.set(command.requestId,{command,signature,at:Date.now()});
    send('recommendation-command',{command}); return true;
  }
  function receiveRecommendation(input) {
    const data=interestObject(input);
    if(!data || data.version!==1 || !requestBase(data) || !recommendationSafe(data) || !recommendationRequests.has(data.requestId)) return;
    const command=recommendationRequests.get(data.requestId).command;
    const keys=['channel','version','type','requestId','sessionGeneration'];
    if(data.type==='error') { keys.push('code','message'); if(!interestText(data.code,80)||!interestText(data.message,240)) return; }
    else {
      if(data.type!==recommendationTypes[command.action]) return;
      if(['page','detail'].includes(command.action) && data.queryId!==command.queryId) return;
      if(command.action==='detail' && data.item?.programRef!==command.programRef) return;
      if(command.action==='setFavorite' && data.programRef!==command.programRef) return;
      const payload={bootstrap:['settings','settingsRevision','activeReport','catalog','years','algorithmVersion','dataVersion'],exams:['items','nextCursor'],results:['queryId','items','nextCursor','total','counts','inputs','warnings'],detail:['queryId','item','details'],settings:['settings','settingsRevision'],favorites:['items','nextCursor'],favorite:['programRef','value','revision']}[data.type];
      if(!payload) return; keys.push(...payload);
      if(['bootstrap','settings'].includes(data.type) && (!recommendationSettings(data.settings)||!nonnegative(data.settingsRevision))) return;
      if(['exams','results','favorites'].includes(data.type) && (!Array.isArray(data.items)||data.items.length>20||!recommendationCursor(data.nextCursor))) return;
      if(['results','detail'].includes(data.type) && !interestId(data.queryId)) return;
      if(data.type==='favorite' && (!programRef(data.programRef)||typeof data.value!=='boolean'||!nonnegative(data.revision))) return;
    }
    if(!exact(data,keys)) return;
    recommendationRequests.delete(data.requestId); recommendationQueue.push(JSON.parse(JSON.stringify(data)));
    if(recommendationQueue.length>8) recommendationQueue.shift();
  }
  function open(nextView) {
    if (!views.has(nextView) || !/^https?:$/.test(new URL(env.location.href).protocol)) return false;
    ensureUI(); view = nextView; ui.title.textContent = titles[view];
    if (!opened) {
      opened = true; ui.root.hidden = false; ui.shade.hidden = false;
      savedOverflow = doc.body.style.overflow; doc.body.style.overflow = 'hidden';
      const canvas = doc.getElementById('canvas');
      if (canvas) { savedInert = canvas.inert; canvas.inert = true; canvas.blur(); }
      if (doc.pointerLockElement && doc.exitPointerLock) doc.exitPointerLock();
    }
    (ready ? ui.frame : ui.back).focus();
    if (ready) send('navigate', {view}); else if (!loading) load();
    return true;
  }
  function close() {
    if (!opened) return;
    send('suspend');
    opened = false; ui.root.hidden = true; ui.shade.hidden = true; doc.body.style.overflow = savedOverflow;
    const canvas = doc.getElementById('canvas');
    if (canvas) { canvas.inert = savedInert; canvas.focus(); }
  }
  function signOut() {
    if (ready) send('sign-out');
    else { pendingSignOut = true; open('account'); }
  }
  function resume() {
    if (!/^https?:$/.test(new URL(env.location.href).protocol)) return false;
    ensureUI();
    if (!ready && !loading) load();
    return true;
  }
  function destroy() {
    close(); clearTimer(); env.removeEventListener('message', receive);
    if (childDocument) childDocument.removeEventListener('keydown', escape, true);
    doc.removeEventListener('keydown', keyboard, true); doc.removeEventListener('keyup', keyboard, true);
    if (ui) { ui.frame.onerror = null; ui.frame.remove(); ui.root.remove(); ui.shade.remove(); ui.style.remove(); }
    ui = null; ready = false; loading = false; user = null; forumQueue = []; progressQueue = []; forumRequests.clear(); progressRequests.clear(); pendingForumContext = null; interestQueue=[]; interestRequests.clear(); recommendationQueue=[]; recommendationRequests.clear();
  }
  return Object.freeze({open, close, signOut, resume, isOpen: () => opened, requestForumPage, openForum, progressCommand, interestCommand, recommendationCommand,
    pollRecommendationMessagesJSON: () => { const messages=recommendationQueue; recommendationQueue=[]; return JSON.stringify(messages); },
    pollInterestMessagesJSON: () => { const messages=interestQueue; interestQueue=[]; return JSON.stringify(messages); },
    pollForumMessagesJSON: () => { const messages = forumQueue; forumQueue = []; return JSON.stringify(messages); },
    pollProgressMessagesJSON: () => { const messages = progressQueue; progressQueue = []; return JSON.stringify(messages); },
    stateJSON: () => JSON.stringify({ready, resolved, user, error, sessionGeneration}), destroy});
});
