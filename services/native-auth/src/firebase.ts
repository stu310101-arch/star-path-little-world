import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "jose";

export interface FirebaseEnv {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_API_KEY: string;
  SERVICE_ACCOUNT_EMAIL: string;
  SERVICE_ACCOUNT_PRIVATE_KEY: string;
}

const GOOGLE_KEYS = createRemoteJWKSet(new URL(
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
), { timeoutDuration: 5000, cooldownDuration: 30000, cacheMaxAge: 3600000 });

export class AuthError extends Error {}

/** JWT validation alone does not reject disabled users or revoked sessions. */
export async function verifyFirebaseUser(idToken: string, env: FirebaseEnv): Promise<string> {
  try {
    const { payload } = await jwtVerify(idToken, GOOGLE_KEYS, {
      algorithms: ["RS256"],
      issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
      audience: env.FIREBASE_PROJECT_ID,
      requiredClaims: ["sub", "iat", "exp", "auth_time"],
      clockTolerance: 0,
    });
    const now = Math.floor(Date.now() / 1000);
    if (!payload.sub || payload.sub.length > 128 || typeof payload.iat !== "number"
      || payload.iat > now || typeof payload.auth_time !== "number"
      || payload.auth_time > now || payload.auth_time < 0) throw new AuthError();
    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_API_KEY)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ idToken }),
        signal: AbortSignal.timeout(5000),
      },
    );
    if (!response.ok) throw new AuthError();
    const body = await response.json() as {
      users?: Array<{ localId?: string; disabled?: boolean; validSince?: string }>;
    };
    const user = body.users?.[0];
    const validSince = user?.validSince === undefined ? 0 : Number(user.validSince);
    if (!user || user.localId !== payload.sub || user.disabled === true
      || !Number.isFinite(validSince) || payload.auth_time < validSince) throw new AuthError();
    return payload.sub;
  } catch {
    // Do not expose JWTs, Google's response bodies, or verifier diagnostics.
    throw new AuthError("invalid_authentication");
  }
}

export async function createCustomToken(uid: string, env: FirebaseEnv): Promise<string> {
  if (!uid || uid.length > 128) throw new AuthError("invalid_user");
  const key = await importPKCS8(env.SERVICE_ACCOUNT_PRIVATE_KEY.replace(/\\n/g, "\n"), "RS256");
  const now = Math.floor(Date.now() / 1000);
  return new SignJWT({ uid })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(env.SERVICE_ACCOUNT_EMAIL)
    .setSubject(env.SERVICE_ACCOUNT_EMAIL)
    .setAudience("https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit")
    .setIssuedAt(now)
    .setExpirationTime(now + 60)
    .sign(key);
}
