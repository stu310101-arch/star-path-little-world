import { generateKeyPairSync } from "node:crypto";
import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// A fresh test-only signing key per run; never a checked-in or production credential.
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: "jwk" }), kid: "test-key", alg: "RS256", use: "sig" };

export default defineConfig({
  plugins: [cloudflareTest({
    wrangler: { configPath: "./wrangler.jsonc" },
    miniflare: {
      bindings: {
        PUBLIC_ORIGIN: "https://star-path.test",
        FIREBASE_PROJECT_ID: "star-path-test",
        FIREBASE_API_KEY: "test-api-key",
        SERVICE_ACCOUNT_EMAIL: "native-auth@star-path-test.iam.gserviceaccount.com",
        SERVICE_ACCOUNT_PRIVATE_KEY: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
        TEST_PUBLIC_JWK: JSON.stringify(jwk),
      },
    },
  })],
  test: { fileParallelism: false, testTimeout: 15000 },
});
