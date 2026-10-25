"""Install the approved signer key via stdin, then remove its downloaded copy.

This command never prints the private key or writes it into the project.
Run only with the exact approved service-account download.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-file", required=True, type=Path)
    parser.add_argument("--node", required=True, type=Path)
    args = parser.parse_args()
    path = args.key_file.resolve(strict=True)
    key = json.loads(path.read_text(encoding="utf-8"))
    public = json.loads((ROOT / "services/native-auth/production.vars.json").read_text(encoding="utf-8"))
    if key.get("type") != "service_account" or key.get("project_id") != public["FIREBASE_PROJECT_ID"] or key.get("client_email") != public["SERVICE_ACCOUNT_EMAIL"]:
        raise ValueError("The key is not for the approved dedicated native signer")
    private = key.get("private_key", "")
    if not private.startswith("-----BEGIN PRIVATE KEY-----") or not private.strip().endswith("-----END PRIVATE KEY-----"):
        raise ValueError("Expected a PKCS8 private key")
    cli = ROOT / "services/native-auth/node_modules/wrangler/bin/wrangler.js"
    result = subprocess.run([str(args.node), str(cli), "secret", "put", "SERVICE_ACCOUNT_PRIVATE_KEY", "--name", "star-path-little-world"],
                            cwd=ROOT / "services/native-auth", input=private, text=True,
                            encoding="utf-8", capture_output=True)
    if result.returncode:
        raise RuntimeError(f"Wrangler secret upload failed (exit {result.returncode}); original download preserved")
    check = subprocess.run([str(args.node), str(cli), "secret", "list", "--name", "star-path-little-world"],
                           cwd=ROOT / "services/native-auth", text=True, encoding="utf-8", capture_output=True, check=True)
    if not any(item.get("name") == "SERVICE_ACCOUNT_PRIVATE_KEY" for item in json.loads(check.stdout)):
        raise RuntimeError("Secret name was not confirmed; original download preserved")
    evidence = ROOT / "build/admissions-evidence/signer.json"
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps({"project_id": key["project_id"], "service_account": key["client_email"],
        "key_id": key["private_key_id"], "worker": "star-path-little-world", "secret": "SERVICE_ACCOUNT_PRIVATE_KEY",
        "verified_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "local_download_removed": True}, indent=2) + "\n", encoding="utf-8")
    path.unlink()
    print("Worker secret name verified; local signer download removed. No private key included in evidence.")


if __name__ == "__main__":
    main()
