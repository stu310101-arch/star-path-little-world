/* StarPath-only adapter. The original WordKing site and its Firebase app stay untouched. */
globalThis.WordKingStarPath = {
  async connect() {
    let host;
    try { if (parent !== window && parent.location.origin === location.origin && parent.location.pathname.endsWith('/host/')) host = parent; } catch {}
    if (!host?.__starPathFirebase) {
      const base = location.pathname.slice(0, location.pathname.indexOf('/wordking-app/'));
      location.replace(base + '/host/?view=wordking');
      throw new Error('請由星途帳號開啟單字王。');
    }
    const runtime = await host.__starPathFirebase;
    const id = new URLSearchParams(location.search).get('library') || 'main';
    let repo = null, epoch = 0, owner = null, preview = null;
    const bar = document.createElement('section');
    bar.setAttribute('aria-label', '星途單字庫');
    bar.style.cssText = 'padding:12px 18px;background:#e9efe7;color:#173e43;border-bottom:1px solid #c7b78e;display:flex;align-items:center;gap:10px;flex-wrap:wrap';
    const select = document.createElement('select'); select.setAttribute('aria-label', '選擇單字庫');
    const file = document.createElement('input'); file.type = 'file'; file.accept = '.json,application/json'; file.setAttribute('aria-label', '選擇完整單字王備份');
    const confirm = document.createElement('button'); confirm.textContent = '確認匯入為獨立單字庫'; confirm.hidden = true;
    const cancel = document.createElement('button'); cancel.textContent = '取消'; cancel.hidden = true;
    const download = document.createElement('button'); download.textContent = '下載此單字庫完整備份';
    const details = document.createElement('details'), summary = document.createElement('summary'); summary.textContent = '從原單字王帶入自己的資料';
    const help = document.createElement('p'); help.textContent = '原單字王的帳號、服務和其他使用者保持原樣。這裡只會複製你親自選擇的完整備份，建立另一個單字庫；不覆蓋星途單字庫。原站的「遷移備份」不含後續變更，不能當完整備份。';
    const guide = document.createElement('a'); guide.href = './readonly-export.html'; guide.target = '_blank'; guide.rel = 'noopener'; guide.textContent = '取得自己的完整備份（原站唯讀操作說明）';
    details.append(summary, help, guide);
    const status = document.createElement('p'); status.setAttribute('role', 'status'); status.style.width = '100%';
    for (const button of [confirm, cancel, download]) button.style.cssText = 'padding:8px 12px;border:1px solid #91a5a0;border-radius:8px;background:#fffdf6;cursor:pointer;min-height:40px';
    select.style.cssText = 'padding:8px;max-width:100%;border:1px solid #91a5a0;border-radius:8px;background:#fffdf6;min-height:40px'; file.style.maxWidth = '100%';
    bar.append(select, file, download, confirm, cancel, details, status); document.body.prepend(bar);
    function clear() { epoch++; repo = null; preview = null; select.replaceChildren(); file.value = ''; status.textContent = ''; confirm.hidden = cancel.hidden = true; }
    async function libraries() { const mine = epoch; const rows = await repo.list(); if (mine !== epoch) return;
      select.replaceChildren(...rows.map(row => new Option(row.label, row.id))); select.value = id; }
    select.addEventListener('change', () => { location.assign(`?page=home&library=${encodeURIComponent(select.value)}`); });
    cancel.addEventListener('click', () => { preview = null; file.value = ''; confirm.hidden = cancel.hidden = true; status.textContent = '已取消匯入。'; });
    file.addEventListener('change', async () => {
      const mine = epoch; preview = null; confirm.hidden = cancel.hidden = true;
      if (!file.files?.[0] || !repo) return;
      try {
        if (file.files[0].size > 9 * 1024 * 1024) throw new Error('備份檔案過大，尚未匯入。');
        const candidate = await repo.previewImport(await file.files[0].text()); if (mine !== epoch) return;
        preview = candidate; const c = candidate.counts;
        status.textContent = `預覽：修改單字 ${c.overrides}、自訂單字 ${c.customWords}、隱藏單字 ${c.hiddenWords}、資料夾 ${c.folders}、待複習 ${c.wrongWords}。確認後建立獨立單字庫，原資料不變。`;
        confirm.hidden = cancel.hidden = false;
      } catch (error) { if (mine === epoch) status.textContent = error.message; }
    });
    confirm.addEventListener('click', async () => {
      if (!preview || !repo) return; const mine = epoch; confirm.disabled = true;
      try { const result = await repo.importSnapshot(preview); if (mine !== epoch) return;
        status.textContent = result.existing ? '相同備份已存在，已保留現有單字庫。' : '已匯入為獨立單字庫。';
        preview = null; confirm.hidden = cancel.hidden = true; await libraries();
        const open = document.createElement('button'); open.textContent = '開啟匯入的單字庫'; open.onclick = () => location.assign(`?page=home&library=${result.libraryId}`); status.append(' ', open);
      } catch (error) { if (mine === epoch) status.textContent = error.message; } finally { confirm.disabled = false; }
    });
    download.addEventListener('click', async () => {
      if (!repo) return; const mine = epoch; download.disabled = true;
      try { const backup = await repo.exportSnapshot(id); if (mine !== epoch) return;
        const url = URL.createObjectURL(new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json' }));
        const link = document.createElement('a'); link.href = url; link.download = `wordking-${id}-${new Date().toISOString().slice(0, 10)}.json`; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
        status.textContent = '已下載目前完整資料。';
      } catch (error) { if (mine === epoch) status.textContent = error.message; } finally { download.disabled = false; }
    });
    return { auth: runtime.auth, libraryQuery: `&library=${encodeURIComponent(id)}`,
      persistence: () => { if (!repo) throw new Error('請先登入星途帳號。'); return repo.forApp(id); },
      openAccount: () => host.StarPathHost.navigate('account'), signOut: () => runtime.requestSignOut(),
      observe: (callback, error) => runtime.observeUser(user => {
        const next = user?.uid ?? null; if (owner === next && owner !== null) return; clear(); owner = next;
        if (user) { repo = runtime.wordking(user.uid); void libraries().catch(reason => { status.textContent = reason.message; }); }
        select.disabled = file.disabled = download.disabled = !user; callback(user);
      }, error),
    };
  }
};
