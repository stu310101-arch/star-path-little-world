/* Run only on the original WordKing page after logging into YOUR own account.
 * READ ONLY: no persistence.load(), transactions, writes, deletes or auth changes. */
(async () => {
  'use strict';
  if (location.protocol !== 'https:') throw new Error('請在你原本的 HTTPS 單字王網站操作。');
  const [{ getApps }, { getAuth }, { getFirestore, doc, collection, getDocFromServer, getDocsFromServer }] = await Promise.all([
    import('https://www.gstatic.com/firebasejs/12.8.0/firebase-app.js'),
    import('https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js'),
    import('https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js')
  ]);
  const app = getApps().find(app => app.options.projectId === 'wordking-434f7');
  if (!app) throw new Error('未找到原單字王帳號連線；沒有更改任何資料。');
  const auth = getAuth(app), user = auth.currentUser;
  if (!user) throw new Error('請先登入你自己的原單字王帳號。');
  const uid = user.uid, db = getFirestore(app), root = doc(db, 'users', uid);
  const guard = () => { if (auth.currentUser?.uid !== uid) throw new Error('帳號已切換，匯出已取消。'); };
  const before = (await getDocFromServer(root)).data() || {}; guard();
  if (before.schemaVersion !== 6 || before.migrationV6?.status !== 'complete' || before.syncLock) throw new Error('資料尚未處於穩定的第 6 版狀態，請先在原站完成同步；工具不會遷移或修改資料。');
  const names = ['wordOverrides', 'customWords', 'hiddenWords', 'folders'];
  const rows = await Promise.all(names.map(name => getDocsFromServer(collection(root, name))));
  const settings = await getDocFromServer(doc(root, 'settings', 'main')); guard();
  const after = (await getDocFromServer(root)).data() || {}; guard();
  if (after.schemaVersion !== 6 || after.syncLock || after.revision !== before.revision || JSON.stringify(after.migrationV6) !== JSON.stringify(before.migrationV6)) throw new Error('匯出途中資料有變更，請重新執行。');
  const clean = data => Object.fromEntries(Object.entries(data).filter(([key]) => !['schemaVersion', 'updatedAt', 'createdAt', 'id'].includes(key)));
  for (const group of rows) if (group.docs.some(row => row.data().schemaVersion > 6)) throw new Error('資料版本較新，匯出已取消。');
  if (settings.exists() && settings.data().schemaVersion > 6) throw new Error('設定版本較新，匯出已取消。');
  const modern = group => group.docs.filter(row => row.data().schemaVersion === 6);
  const snapshot = { userOverrides: Object.fromEntries(modern(rows[0]).map(row => [row.id, clean(row.data())])),
    customWords: Object.fromEntries(modern(rows[1]).map(row => [row.id, clean(row.data())])),
    hiddenWordIds: modern(rows[2]).map(row => row.id), userFolders: Object.fromEntries(modern(rows[3]).map(row => [row.id, clean(row.data())])),
    settings: settings.exists() && settings.data().schemaVersion === 6 ? clean(settings.data()) : {} };
  const backup = { format: 'wordking-current-snapshot', version: 1, schemaVersion: 6, complete: true,
    source: { app: 'wordking-original', uid, exportedAt: new Date().toISOString() }, snapshot };
  const url = URL.createObjectURL(new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json' }));
  const link = document.createElement('a'); link.href = url; link.download = 'wordking-current-snapshot.json'; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  console.info('已下載目前帳號的完整備份。原站資料、帳號與其他使用者均未更改。');
})();
