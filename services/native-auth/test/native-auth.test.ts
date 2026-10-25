import { env } from "cloudflare:workers";
import { runInDurableObject, runDurableObjectAlarm } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { importPKCS8, SignJWT, importJWK, jwtVerify } from "jose";
import worker, { sha256, type Env } from "../src/index";

const bindings = env as unknown as Env & { TEST_PUBLIC_JWK: string };
let ipCounter = 1;
const origin = "https://star-path.test";
const verifier = "a".repeat(43);
type Pair = { requestId: string; code: string; expiresAt: number; approvalUrl: string };
let account: Record<string, unknown> | undefined;
let lookupDelay = 0;
let lookupSignal: (() => void) | undefined;

function call(action: string, body?: unknown, options: { token?: string; ip?: string; origin?: string } = {}) {
  return worker.fetch(new Request(`${origin}/api/native-auth/${action}`, {
    method: body === undefined ? "GET" : "POST",
    headers: {
      Origin: options.origin ?? origin,
      "Content-Type": "application/json",
      "CF-Connecting-IP": options.ip ?? `192.0.2.${ipCounter}`,
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), bindings);
}

async function pair(): Promise<Pair> {
  const response = await call("create", { verifierHash: await sha256(verifier) });
  expect(response.status).toBe(201);
  return response.json();
}
function stub(requestId: string) { return bindings.NATIVE_AUTH.get(bindings.NATIVE_AUTH.idFromName(requestId)); }

async function token(claims: Record<string, unknown> = {}, key?: CryptoKey) {
  const signingKey = key ?? await importPKCS8(bindings.SERVICE_ACCOUNT_PRIVATE_KEY, "RS256");
  const now = Math.floor(Date.now() / 1000);
  return new SignJWT({ auth_time: now - 10, ...claims })
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setIssuer((claims.iss as string) ?? "https://securetoken.google.com/star-path-test")
    .setAudience((claims.aud as string) ?? "star-path-test")
    .setSubject((claims.sub as string) ?? "alice")
    .setIssuedAt((claims.iat as number) ?? now - 5)
    .setExpirationTime((claims.exp as number) ?? now + 3600)
    .sign(signingKey);
}
function lookup(user: Record<string, unknown> = {}) {
  account = { localId: "alice", validSince: "0", ...user };
}

beforeEach(() => {
  ipCounter++;
  account = undefined;
  lookupDelay = 0;
  lookupSignal = undefined;
  // The tested Worker and DO classes run in this workerd isolate. Mock only HTTP;
  // SQLite, DO dispatch, signatures, and key verification remain real.
  vi.stubGlobal("fetch", vi.fn(async (input: Request | string | URL) => {
    const url = input instanceof Request ? input.url : String(input);
    if (url === "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com") {
      return Response.json({ keys: [JSON.parse(bindings.TEST_PUBLIC_JWK)] });
    }
    if (url === "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=test-api-key" && account) {
      lookupSignal?.();
      if (lookupDelay) await new Promise(resolve => setTimeout(resolve, lookupDelay));
      return Response.json({ users: [account] });
    }
    throw new Error("Unexpected external HTTP request in test");
  }));
});
afterEach(() => { vi.unstubAllGlobals(); });

describe("real SQLite handoff object", () => {
  it("keeps credentials out of URL/status and returns pending until explicitly approved", async () => {
    const item = await pair();
    expect(item.approvalUrl).toBe(`${origin}/admissions/account/native/?requestId=${item.requestId}`);
    expect(item.expiresAt - Date.now()).toBeGreaterThan(290000);
    const status = await call(`status?requestId=${item.requestId}`);
    expect(status.headers.get("Cache-Control")).toContain("no-store");
    expect(await status.json()).toEqual({ status: "pending", code: item.code, expiresAt: item.expiresAt });
    const pending = await call("exchange", { requestId: item.requestId, verifier });
    expect(pending.status).toBe(202);
    expect(await pending.json()).toEqual({ status: "pending" });
  });

  it("verifies a real signed ID token, and concurrent exchanges yield exactly one signed custom token", async () => {
    const item = await pair();
    lookup();
    expect((await call("confirm", { requestId: item.requestId, code: item.code }, { token: await token() })).status).toBe(200);
    const responses = await Promise.all(Array.from({ length: 8 }, () => call("exchange", { requestId: item.requestId, verifier })));
    expect(responses.filter(x => x.status === 200)).toHaveLength(1);
    expect(responses.filter(x => x.status === 410)).toHaveLength(7);
    const result = await responses.find(x => x.status === 200)!.json() as { customToken: string };
    const { payload } = await jwtVerify(result.customToken, await importJWK(JSON.parse(bindings.TEST_PUBLIC_JWK), "RS256"), {
      issuer: bindings.SERVICE_ACCOUNT_EMAIL,
      subject: bindings.SERVICE_ACCOUNT_EMAIL,
      audience: "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit",
    });
    expect(payload.uid).toBe("alice");
    expect(payload.exp! - payload.iat!).toBe(60);
    await runInDurableObject(stub(item.requestId), (_instance, state) => {
      expect(state.storage.sql.exec("SELECT uid,status FROM handoff").one()).toEqual({ uid: null, status: "consumed" });
    });
  });

  it("rejects wrong verifier and wrong code without permitting takeover", async () => {
    const item = await pair();
    expect((await call("exchange", { requestId: item.requestId, verifier: "b".repeat(43) })).status).toBe(403);
    expect((await call("cancel", { requestId: item.requestId, verifier: "b".repeat(43) })).status).toBe(403);
    const badCode = item.code === "000000" ? "000001" : "000000";
    expect((await call("confirm", { requestId: item.requestId, code: badCode }, { token: "invalid" })).status).toBe(403);
    expect((await call("exchange", { requestId: item.requestId, verifier })).status).toBe(202);
  });

  it("cancels with verifier and prevents later approval or exchange", async () => {
    const item = await pair();
    expect((await call("cancel", { requestId: item.requestId, verifier })).status).toBe(200);
    expect((await call("exchange", { requestId: item.requestId, verifier })).status).toBe(410);
    expect((await call("confirm", { requestId: item.requestId, code: item.code }, { token: "invalid" })).status).toBe(410);
  });

  it("checks expiry on every operation even before an alarm fires", async () => {
    const item = await pair();
    await runInDurableObject(stub(item.requestId), (_instance, state) => {
      state.storage.sql.exec("UPDATE handoff SET expires_at=?", Date.now() - 1);
    });
    expect((await call(`status?requestId=${item.requestId}`)).status).toBe(410);
    expect((await call("exchange", { requestId: item.requestId, verifier })).status).toBe(410);
    expect((await call("cancel", { requestId: item.requestId, verifier })).status).toBe(410);
  });

  it("deletes the record on expiry alarm and still reports a closed request", async () => {
    const item = await pair();
    expect(await runDurableObjectAlarm(stub(item.requestId))).toBe(true);
    expect((await call(`status?requestId=${item.requestId}`)).status).toBe(410);
  });

  it("does not overwrite cancellation while Google verification is in flight", async () => {
    const item = await pair();
    lookup();
    lookupDelay = 150;
    const started = new Promise<void>(resolve => { lookupSignal = resolve; });
    const verifying = call("confirm", { requestId: item.requestId, code: item.code }, { token: await token() });
    await started;
    expect((await call("cancel", { requestId: item.requestId, verifier })).status).toBe(200);
    expect((await verifying).status).toBe(410);
    expect((await call("exchange", { requestId: item.requestId, verifier })).status).toBe(410);
  });

  it("allows only the first concurrent approval to change the pending identity", async () => {
    const item = await pair();
    lookup();
    lookupDelay = 30;
    const signed = await token();
    const replies = await Promise.all(Array.from({ length: 2 }, () =>
      call("confirm", { requestId: item.requestId, code: item.code }, { token: signed })));
    expect(replies.map(response => response.status).sort()).toEqual([200, 410]);
    expect((await call("confirm", { requestId: item.requestId, code: item.code }, { token: signed })).status).toBe(409);
  });

  it("bounds pairing guesses and IP creates", async () => {
    const item = await pair();
    const badCode = item.code === "000000" ? "000001" : "000000";
    for (let i = 0; i < 5; i++) expect((await call("confirm", { requestId: item.requestId, code: badCode }, { token: "invalid" })).status).toBe(403);
    expect((await call("confirm", { requestId: item.requestId, code: badCode }, { token: "invalid" })).status).toBe(429);
    for (let i = 0; i < 9; i++) await pair();
    expect((await call("create", { verifierHash: await sha256(verifier) })).status).toBe(429);
  });
});

describe("Firebase verification and public request guards", () => {
  it.each([
    ["disabled", { disabled: true }],
    ["revoked", { validSince: String(Math.floor(Date.now() / 1000)) }],
    ["different user", { localId: "bob" }],
  ])("rejects %s accounts", async (_label, account) => {
    const item = await pair();
    lookup(account);
    expect((await call("confirm", { requestId: item.requestId, code: item.code }, { token: await token() })).status).toBe(401);
    expect((await call("exchange", { requestId: item.requestId, verifier })).status).toBe(202);
  });

  it.each([
    { aud: "another-project" }, { iss: "https://attacker.test" },
    { exp: 1 }, { auth_time: 9999999999 }, { iat: 9999999999 },
  ])("rejects invalid signed claims %j", async claims => {
    const item = await pair();
    expect((await call("confirm", { requestId: item.requestId, code: item.code }, { token: await token(claims) })).status).toBe(401);
  });

  it("rejects invalid signatures", async () => {
    const item = await pair();
    const forged = (await token()).split(".");
    forged[2] = "A".repeat(forged[2].length);
    expect((await call("confirm", { requestId: item.requestId, code: item.code }, { token: forged.join(".") })).status).toBe(401);
  });

  it("rejects cross-origin, malformed, excessive body and token-in-query requests", async () => {
    expect((await call("create", { verifierHash: await sha256(verifier) }, { origin: "https://other.test" })).status).toBe(403);
    expect((await call("create", { verifierHash: "no" })).status).toBe(400);
    expect((await call("create", { verifierHash: "a".repeat(5000) })).status).toBe(413);
    const item = await pair();
    expect((await call(`confirm?token=not-accepted`, { requestId: item.requestId, code: item.code })).status).toBe(401);
    expect((await call("exchange", { requestId: "bad", verifier })).status).toBe(400);
  });
});
