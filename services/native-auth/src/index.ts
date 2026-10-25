import { DurableObject } from "cloudflare:workers";
import { createCustomToken, verifyFirebaseUser, type FirebaseEnv } from "./firebase";

export interface Env extends FirebaseEnv {
  PUBLIC_ORIGIN: string;
  NATIVE_AUTH: DurableObjectNamespace<NativeAuthHandoff>;
  NATIVE_AUTH_LIMITS: DurableObjectNamespace<NativeAuthLimits>;
  ASSETS?: Fetcher;
}

const PREFIX = "/api/native-auth/";
const TTL = 5 * 60 * 1000;
const REQUEST_ID = /^[a-f0-9]{32}$/;
const VERIFIER = /^[A-Za-z0-9_-]{43,128}$/;

export function json(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: {
    "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Resource-Policy": "same-origin",
  } });
}
const error = (name: string, status: number) => json({ error: name }, status);
export async function sha256(value: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(hash), b => b.toString(16).padStart(2, "0")).join("");
}
function sameHash(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}
function pairingCode(): string {
  // Rejection sampling avoids modulo bias while retaining a readable six-digit code.
  const limit = Math.floor(2 ** 32 / 1000000) * 1000000;
  let sample: number;
  do { sample = crypto.getRandomValues(new Uint32Array(1))[0]; } while (sample >= limit);
  return String(sample % 1000000).padStart(6, "0");
}

interface HandoffRow extends Record<string, SqlStorageValue> {
  verifier_hash: string; code: string; status: string; expires_at: number;
  uid: string | null; confirms: number; window_start: number; window_count: number;
}

/** One object per random request ID. Secrets and identity never appear in public status. */
export class NativeAuthHandoff extends DurableObject<Env> {
  private deleted = false;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS handoff (
      id INTEGER PRIMARY KEY CHECK (id = 1), verifier_hash TEXT NOT NULL,
      code TEXT NOT NULL, status TEXT NOT NULL, expires_at INTEGER NOT NULL,
      uid TEXT, confirms INTEGER NOT NULL DEFAULT 0,
      window_start INTEGER NOT NULL DEFAULT 0, window_count INTEGER NOT NULL DEFAULT 0
    )`);
  }

  private row(): HandoffRow | undefined {
    return this.ctx.storage.sql.exec<HandoffRow>("SELECT * FROM handoff WHERE id=1").toArray()[0];
  }

  private current(): HandoffRow | Response {
    const row = this.row();
    if (!row || row.expires_at <= Date.now()) return error("expired", 410);
    if (row.status === "consumed" || row.status === "cancelled") return error(row.status, 410);
    const windowStart = Math.floor(Date.now() / 60000) * 60000;
    const count = row.window_start === windowStart ? row.window_count + 1 : 1;
    this.ctx.storage.sql.exec("UPDATE handoff SET window_start=?, window_count=? WHERE id=1", windowStart, count);
    if (count > 90) return error("rate_limited", 429);
    return row;
  }

  async fetch(request: Request): Promise<Response> {
    if (this.deleted) return error("expired", 410);
    const action = new URL(request.url).pathname.slice(1);
    const body = request.method === "POST" ? await request.json() as Record<string, string> : {};
    if (action === "create") {
      if (this.row()) return error("already_exists", 409);
      const code = pairingCode(), expiresAt = Date.now() + TTL;
      this.ctx.storage.sql.exec(
        "INSERT INTO handoff (id,verifier_hash,code,status,expires_at) VALUES (1,?,?,?,?)",
        body.verifierHash, code, "pending", expiresAt,
      );
      await this.ctx.storage.setAlarm(expiresAt);
      return json({ code, expiresAt }, 201);
    }
    const row = this.current();
    if (row instanceof Response) return row;
    if (action === "status") return json({ code: row.code, status: row.status, expiresAt: row.expires_at });
    if (action === "confirm") {
      if (row.status !== "pending") return error("already_confirmed", 409);
      this.ctx.storage.sql.exec("UPDATE handoff SET confirms=confirms+1 WHERE id=1");
      if (row.confirms >= 5) return error("rate_limited", 429);
      if (body.code !== row.code) return error("invalid_code", 403);
      let uid: string;
      try { uid = await verifyFirebaseUser(body.idToken, this.env); }
      catch { return error("invalid_authentication", 401); }
      if (this.deleted) return error("expired", 410);
      // Recheck time and state after awaiting Google: first account wins, cancellation wins.
      const changed = this.ctx.storage.sql.exec(
        "UPDATE handoff SET status='confirmed', uid=? WHERE id=1 AND status='pending' AND expires_at>? RETURNING id",
        uid, Date.now(),
      ).toArray();
      if (!changed.length) return error("request_closed", 410);
      return json({ status: "confirmed" });
    }
    if (action === "exchange" || action === "cancel") {
      const hash = await sha256(body.verifier);
      if (this.deleted) return error("expired", 410);
      if (!sameHash(hash, row.verifier_hash)) return error("invalid_verifier", 403);
      // Hashing yields; all decisions below re-read and mutate within one SQLite transaction.
      const outcome = this.ctx.storage.transactionSync(() => {
        const fresh = this.row();
        if (!fresh || fresh.expires_at <= Date.now()) return { error: "expired", status: 410 };
        if (fresh.status === "consumed" || fresh.status === "cancelled") return { error: fresh.status, status: 410 };
        if (action === "cancel") {
          this.ctx.storage.sql.exec("UPDATE handoff SET status='cancelled', uid=NULL WHERE id=1");
          return { cancelled: true };
        }
        if (fresh.status === "pending") return { pending: true };
        this.ctx.storage.sql.exec("UPDATE handoff SET status='consumed', uid=NULL WHERE id=1");
        return { uid: fresh.uid! };
      });
      if (outcome.error) return error(outcome.error, outcome.status!);
      if (outcome.cancelled) return json({ status: "cancelled" });
      if (outcome.pending) return json({ status: "pending" }, 202);
      try {
        // Consumed BEFORE signing: a lost response requires starting a new pairing.
        return json({ customToken: await createCustomToken(outcome.uid!, this.env) });
      } catch { return error("signing_unavailable", 503); }
    }
    return error("not_found", 404);
  }

  async alarm(): Promise<void> { this.deleted = true; await this.ctx.storage.deleteAll(); }
}

/** One SQLite object per SHA-256(IP + minute). No IP addresses are persisted. */
export class NativeAuthLimits extends DurableObject<Env> {
  private deleted = false;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS counters (bucket TEXT PRIMARY KEY, count INTEGER NOT NULL)");
  }
  async fetch(request: Request): Promise<Response> {
    if (this.deleted) return json({ allowed: false }, 429);
    const { bucket, limit } = await request.json() as { bucket: string; limit: number };
    const count = this.ctx.storage.sql.exec<{ count: number }>(
      "INSERT INTO counters (bucket,count) VALUES (?,1) ON CONFLICT(bucket) DO UPDATE SET count=count+1 RETURNING count", bucket,
    ).one().count;
    if (count === 1) await this.ctx.storage.setAlarm(Date.now() + 120000);
    return json({ allowed: count <= limit }, count <= limit ? 200 : 429);
  }
  async alarm(): Promise<void> { this.deleted = true; await this.ctx.storage.deleteAll(); }
}

async function limited(request: Request, env: Env, action: string): Promise<boolean> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "local";
  const hash = await sha256(`${ip}:${Math.floor(Date.now() / 60000)}`);
  const stub = env.NATIVE_AUTH_LIMITS.get(env.NATIVE_AUTH_LIMITS.idFromName(hash));
  const response = await stub.fetch("https://limits.internal/", {
    method: "POST", body: JSON.stringify({
      bucket: action === "create" ? "create" : "requests",
      limit: action === "create" ? 10 : 300,
    }),
  });
  return response.status === 429;
}

async function boundedText(request: Request): Promise<string | null> {
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > 4096) { await reader.cancel(); return null; }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder().decode(bytes);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (!url.pathname.startsWith(PREFIX)) {
      return env.ASSETS ? env.ASSETS.fetch(request) : error("not_found", 404);
    }
    try {
      const action = url.pathname.slice(PREFIX.length);
      if (!["create", "status", "confirm", "exchange", "cancel"].includes(action)) return error("not_found", 404);
      if (request.method !== (action === "status" ? "GET" : "POST")) return error("method_not_allowed", 405);
      if (url.origin !== env.PUBLIC_ORIGIN) return error("invalid_origin", 403);
      if (request.method === "POST" && request.headers.get("Origin") !== env.PUBLIC_ORIGIN) return error("invalid_origin", 403);
      if (request.method === "POST" && request.headers.get("Content-Type")?.split(";")[0].trim() !== "application/json") return error("invalid_content_type", 415);
      if (!env.FIREBASE_PROJECT_ID || !env.FIREBASE_API_KEY || !env.SERVICE_ACCOUNT_EMAIL || !env.SERVICE_ACCOUNT_PRIVATE_KEY) return error("not_configured", 503);
      if (await limited(request, env, action)) return error("rate_limited", 429);
      let body: Record<string, string> = {};
      if (request.method === "POST") {
        if (Number(request.headers.get("Content-Length") ?? 0) > 4096) return error("request_too_large", 413);
        const text = await boundedText(request);
        if (text === null) return error("request_too_large", 413);
        try { body = JSON.parse(text); } catch { return error("invalid_json", 400); }
        if (!body || typeof body !== "object" || Array.isArray(body)) return error("invalid_request", 400);
      }
      if (action === "create") {
        if (typeof body.verifierHash !== "string" || !/^[a-f0-9]{64}$/.test(body.verifierHash)) return error("invalid_verifier_hash", 400);
        const requestId = crypto.randomUUID().replace(/-/g, "");
        const stub = env.NATIVE_AUTH.get(env.NATIVE_AUTH.idFromName(requestId));
        const response = await stub.fetch("https://handoff.internal/create", {
          method: "POST", body: JSON.stringify({ verifierHash: body.verifierHash }),
        });
        if (!response.ok) return response;
        const details = await response.json() as { code: string; expiresAt: number };
        const approvalUrl = `${env.PUBLIC_ORIGIN}/admissions/account/native/?requestId=${requestId}`;
        return json({ requestId, ...details, approvalUrl }, 201);
      }
      const requestId = action === "status" ? url.searchParams.get("requestId") : body.requestId;
      if (typeof requestId !== "string" || !REQUEST_ID.test(requestId)) return error("invalid_request_id", 400);
      if ((action === "exchange" || action === "cancel") && (typeof body.verifier !== "string" || !VERIFIER.test(body.verifier))) return error("invalid_verifier", 400);
      if (action === "confirm") {
        if (typeof body.code !== "string" || !/^\d{6}$/.test(body.code)) return error("invalid_code", 400);
        const auth = request.headers.get("Authorization") ?? "";
        if (!auth.startsWith("Bearer ") || auth.length > 8192) return error("invalid_authentication", 401);
        body = { code: body.code, idToken: auth.slice(7) };
      }
      const stub = env.NATIVE_AUTH.get(env.NATIVE_AUTH.idFromName(requestId));
      return await stub.fetch(`https://handoff.internal/${action}`, action === "status" ? {} : {
        method: "POST", body: JSON.stringify(body),
      });
    } catch {
      return error("temporarily_unavailable", 503);
    }
  },
} satisfies ExportedHandler<Env>;
