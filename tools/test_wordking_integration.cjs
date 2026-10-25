const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
async function exportFixture({ locked = false, changed = false, switchUser = false } = {}) {
  const calls = [], downloads = []; let rootReads = 0;
  const auth = { currentUser: { uid: 'alice' } };
  const ref = (...parts) => parts.filter(part => typeof part === 'string').join('/');
  const current = { schemaVersion: 6, revision: 7, migrationV6: { status: 'complete', backupId: 'old-migration' }, ...(locked ? { syncLock: {} } : {}) };
  const rows = {
    wordOverrides: [{ id: 'a', data: () => ({ schemaVersion: 6, english: 'latest change', isWrong: false }) }],
    customWords: [{ id: 'c_one', data: () => ({ schemaVersion: 6, english: 'private', meanings: [{ partOfSpeech: 'noun', definitions: ['自訂'] }], isWrong: true, folderIds: ['f_one'], lessonIds: [] }) }],
    hiddenWords: [{ id: 'hidden', data: () => ({ schemaVersion: 6 }) }], folders: [{ id: 'f_one', data: () => ({ schemaVersion: 6, name: '私人' }) }],
  };
  const sdk = { getApps: () => [{ options: { projectId: 'wordking-434f7' } }], getAuth: () => auth, getFirestore: () => ({}), doc: ref, collection: ref,
    getDocFromServer: async target => { calls.push(target); if (target.endsWith('settings/main')) return { exists: () => true, data: () => ({ schemaVersion: 6, hiddenLessonIds: ['L2'] }) };
      rootReads++; return { data: () => ({ ...current, revision: changed && rootReads > 1 ? 8 : 7 }) }; },
    getDocsFromServer: async target => { calls.push(target); if (switchUser) auth.currentUser = { uid: 'bob' }; return { docs: rows[target.split('/').at(-1)] }; },
  };
  const source = fs.readFileSync(path.join(root, 'tools/export_wordking_readonly.js'), 'utf8').replace(/import\('https:\/\/www\.gstatic\.com\/firebasejs\/12\.8\.0\/[^']+'\)/g, 'Promise.resolve(sdk)');
  const result = vm.runInNewContext(source, { sdk, location: { protocol: 'https:' }, Blob, URL: { createObjectURL(blob) { downloads.push(blob); return 'blob:test'; }, revokeObjectURL() {} },
    document: { createElement: () => ({ click() {} }) }, setTimeout() {}, console: { info() {} } });
  await result; return { calls, backup: JSON.parse(await downloads[0].text()) };
}
test('read-only exporter reads the current logged-in UID and latest complete canonical state', async () => {
  const { calls, backup } = await exportFixture();
  assert.equal(backup.format, 'wordking-current-snapshot'); assert.equal(backup.complete, true);
  assert.equal(backup.source.uid, 'alice'); assert.equal(backup.snapshot.userOverrides.a.english, 'latest change');
  assert.equal(backup.snapshot.userOverrides.a.isWrong, false); assert.equal(backup.snapshot.customWords.c_one.isWrong, true);
  assert.deepEqual(backup.snapshot.hiddenWordIds, ['hidden']); assert.deepEqual(backup.snapshot.settings, { hiddenLessonIds: ['L2'] });
  assert.ok(calls.every(value => value.startsWith('users/alice'))); assert.ok(calls.every(value => !value.includes('migrationBackups')));
});
test('read-only exporter refuses active migration, changed revision and user switch', async () => {
  await assert.rejects(exportFixture({ locked: true }), /穩定/); await assert.rejects(exportFixture({ changed: true }), /變更/); await assert.rejects(exportFixture({ switchUser: true }), /帳號已切換/);
});
test('integrated WordKing has no original SDK or credentials and source remains separately pinned', () => {
  const app = fs.readFileSync(path.join(root, 'admissions-site/public/wordking-app/assets/app.js'), 'utf8');
  assert.ok(app.includes('WordKingStarPath.connect')); assert.ok(!app.includes('firebasejs/')); assert.ok(!app.includes('wordking-434f7'));
  const original = fs.readFileSync(path.join(root, 'wordking-source/assets/app.js'), 'utf8'); assert.ok(original.includes('wordking-434f7'));
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'integrations/wordking/source-manifest.json'), 'utf8'));
  assert.equal(manifest.source_base_commit, '2d446cb27775b7c2e4af2a4693fd8891650dfa58');
});
