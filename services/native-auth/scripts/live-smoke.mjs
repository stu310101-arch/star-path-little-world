// Explicitly opt in: creates two disposable example.invalid users, then removes them.
// Credentials stay in memory. Evidence contains only checks/status, never tokens/passwords.
import assert from 'node:assert/strict';
import {randomBytes, createHash, randomUUID} from 'node:crypto';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

if (!process.argv.includes('--production')) throw new Error('Pass --production for the approved cloud integration test');
const env = JSON.parse(await readFile(new URL('../production.vars.json', import.meta.url), 'utf8'));
const checks = [], users = [], documents = [];
const authBase = 'https://identitytoolkit.googleapis.com/v1/accounts:';
const dbBase = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
const dbName = `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
function pass(name) { checks.push(name); console.log('PASS ' + name); }
async function request(url, body, token, method = 'POST', extra = {}) {
  const response = await fetch(url, {method, headers: {
    ...(body ? {'Content-Type': 'application/json'} : {}), ...(token ? {Authorization: `Bearer ${token}`} : {}), ...extra,
  }, ...(body ? {body: JSON.stringify(body)} : {}), signal: AbortSignal.timeout(30000)});
  const data = await response.json().catch(() => ({}));
  return {status: response.status, data, headers: response.headers};
}
function expect(result, code, label) {
  if (result.status !== code) throw new Error(`${label}: HTTP ${result.status}, expected ${code}`);
}
const identity = (action, body) => request(`${authBase}${action}?key=${env.FIREBASE_API_KEY}`, body);
const native = (action, body, token) => request(`${env.PUBLIC_ORIGIN}/api/native-auth/${action}`, body, token, 'POST', {Origin: env.PUBLIC_ORIGIN});
async function createUser() {
  const result = await identity('signUp', {email: `starpath-qa-${randomUUID()}@example.invalid`, password: randomBytes(32).toString('base64url'), returnSecureToken: true});
  expect(result, 200, 'create disposable test user'); users.push(result.data); return result.data;
}
async function commit(writes, token) { return request(`${dbBase}:commit`, {writes}, token); }
const transforms = [{fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'}];
const reportPath = new URL('../../../build/admissions-evidence/live-cloud-smoke.json', import.meta.url);
let failed = null;
try {
  const user = await createUser(), other = await createUser();
  pass('Firebase Email sign-in provider accepts disposable test accounts');
  const path = `users/${user.localId}/examAttempts/${randomUUID()}`;
  const name = `${dbName}/${path}`;
  documents.push({path, token: user.idToken});
  const fields = {schemaVersion: {integerValue: '1'}, kind: {stringValue: 'practice'}, title: {stringValue: 'Disposable integration QA'},
    examDate: {stringValue: '2026-10-19'}, scores: {mapValue: {fields: {'國文': {integerValue: '0'}, '英聽': {integerValue: '0'}}}},
    apcsScores: {mapValue: {fields: {concept: {integerValue: '0'}}}}};
  expect(await commit([{update: {name, fields}, updateTransforms: [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}, ...transforms]}], user.idToken), 200, 'cloud create');
  let read = await request(`${dbBase}/${path}`, null, user.idToken, 'GET');
  expect(read, 200, 'cloud get');
  const createdAt = read.data.fields.createdAt.timestampValue;
  assert(read.data.fields.scores.mapValue.fields['國文'].integerValue === '0', 'zero was not retained');
  assert(!('英文' in read.data.fields.scores.mapValue.fields), 'blank subject became a score');
  pass('Cloud Firestore preserves partial subjects, zero, listening F and APCS zero');
  expect(await request(`${dbBase}/${path}`, null, undefined, 'GET'), 403, 'unauthenticated get');
  expect(await request(`${dbBase}/${path}`, null, other.idToken, 'GET'), 403, 'cross-account get');
  expect(await commit([{update: {name, fields: {scores: {mapValue: {fields: {'國文': {integerValue: '16'}}}}}}, updateMask: {fieldPaths: ['scores']}, updateTransforms: transforms}], user.idToken), 403, 'invalid score');
  pass('Production rules reject anonymous/cross-account reads and invalid score writes');
  expect(await commit([{update: {name, fields: {title: {stringValue: 'Updated disposable integration QA'}}}, updateMask: {fieldPaths: ['title']}, updateTransforms: transforms}], user.idToken), 200, 'cloud update');
  read = await request(`${dbBase}/${path}`, null, user.idToken, 'GET');
  assert(read.data.fields.createdAt.timestampValue === createdAt, 'update changed createdAt');
  const listing = await request(`${dbBase}/users/${user.localId}:runQuery`, {structuredQuery: {from: [{collectionId: 'examAttempts'}], orderBy: [
    {field: {fieldPath: 'examDate'}, direction: 'DESCENDING'}, {field: {fieldPath: 'createdAt'}, direction: 'DESCENDING'}], limit: 20}}, user.idToken);
  expect(listing, 200, 'indexed history');
  assert(listing.data.some(row => row.document?.name === name), 'history omitted saved record');
  pass('Cloud update preserves createdAt and indexed history returns the record');

  const verifier = randomBytes(32).toString('base64url');
  const pairing = await native('create', {verifierHash: createHash('sha256').update(verifier).digest('hex')});
  expect(pairing, 201, 'pair create');
  assert(pairing.headers.get('cache-control')?.includes('no-store'), 'pair response is cacheable');
  const {requestId, code} = pairing.data;
  expect(await native('exchange', {requestId, verifier}), 202, 'pending exchange');
  expect(await native('confirm', {requestId, code: code === '000000' ? '000001' : '000000'}, user.idToken), 403, 'incorrect pairing code');
  expect(await native('confirm', {requestId, code}, user.idToken), 200, 'confirm verified Firebase ID token');
  const competing = await Promise.all([native('exchange', {requestId, verifier}), native('exchange', {requestId, verifier})]);
  assert(competing.filter(result => result.status === 200).length === 1, 'pairing redeemed more than once');
  assert(competing.filter(result => result.status === 410).length === 1, 'competing redemption was not refused');
  const customToken = competing.find(result => result.status === 200).data.customToken;
  const signed = await identity('signInWithCustomToken', {token: customToken, returnSecureToken: true});
  expect(signed, 200, 'real Firebase custom-token sign-in');
  const signedIdentity = await identity('lookup', {idToken: signed.data.idToken});
  expect(signedIdentity, 200, 'lookup native signed-in identity');
  assert(signedIdentity.data.users?.[0]?.localId === user.localId, 'native sign-in changed UID');
  expect(await native('exchange', {requestId, verifier}), 410, 'repeated exchange');
  expect(await request(`${dbBase}/${path}`, null, signed.data.idToken, 'GET'), 200, 'native UID reads web score');
  pass('Live Worker verifies Firebase token, signs accepted custom token, and shares the same UID/score');
  pass('Live SQLite handoff permits exactly one winner under two concurrent exchanges');
  const cancelVerifier = randomBytes(32).toString('base64url');
  const cancelled = await native('create', {verifierHash: createHash('sha256').update(cancelVerifier).digest('hex')});
  expect(cancelled, 201, 'cancel pair create');
  expect(await native('cancel', {requestId: cancelled.data.requestId, verifier: cancelVerifier}), 200, 'cancel');
  expect(await native('exchange', {requestId: cancelled.data.requestId, verifier: cancelVerifier}), 410, 'cancelled exchange');
  pass('Live cancellation permanently closes the pairing');
} catch (error) { failed = String(error.message); }
finally {
  const cleanup = [];
  for (const item of documents) {
    const result = await request(`${dbBase}/${item.path}`, null, item.token, 'DELETE').catch(() => ({status: 0}));
    cleanup.push([200, 404].includes(result.status));
  }
  for (const user of users) {
    const result = await identity('delete', {idToken: user.idToken}).catch(() => ({status: 0}));
    cleanup.push(result.status === 200);
  }
  if (cleanup.every(Boolean)) pass('Disposable cloud documents and test accounts removed');
  else failed = (failed ? failed + '; ' : '') + 'cleanup requires attention';
  await mkdir(fileURLToPath(new URL('.', reportPath)), {recursive: true});
  await writeFile(reportPath, JSON.stringify({project: env.FIREBASE_PROJECT_ID, origin: env.PUBLIC_ORIGIN,
    checkedAt: new Date().toISOString(), passed: !failed, checks, error: failed,
    note: 'Protocol/REST test with disposable data; real Google/browser/WebView user journeys are separate acceptance checks.'}, null, 2) + '\n');
}
if (failed) throw new Error(failed);
