"""Preserve/recreate the admissions integration without touching its real index.

Git's canonical file bytes are the portable source inventory. The additional
working-tree inventory ties a snapshot to byte-level release provenance even on
Windows checkouts with core.autocrlf=true.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "admissions-site"
DEFAULT_SNAPSHOT = ROOT / "integrations/admissions"
PATCH_NAME = "integration.patch"
MANIFEST_NAME = "source-manifest.json"
EXCLUDED_PARTS = {".git", "node_modules", ".next", ".vinext", "out", "dist", ".firebase", ".wrangler", "coverage", ".test-results"}


def sha(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def canonical_json(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")


def git(source: Path, *arguments: str, env: dict[str, str] | None = None, data: bytes | None = None) -> bytes:
    result = subprocess.run(["git", "-c", "core.quotepath=true", *arguments], cwd=source,
                            env=env, input=data, capture_output=True)
    if result.returncode:
        # Commands contain paths/revisions, never credentials; do not echo arbitrary Git stderr.
        raise ValueError(f"Git command failed ({result.returncode}): {arguments[0]}")
    return result.stdout


def safe_name(name: str) -> str:
    path = PurePosixPath(name)
    if not name or path.is_absolute() or "\\" in name or ":" in name or any(ord(char) < 32 for char in name) or any(part in ("", ".", "..") for part in name.split("/")):
        raise ValueError("Unsafe inventory path")
    if any(part in EXCLUDED_PARTS for part in path.parts):
        raise ValueError("Excluded source path: " + name)
    if path.name.startswith((".env", ".dev.vars")) or path.suffix.lower() in {".pem", ".key", ".p12", ".pfx"}:
        raise ValueError("Secret/configuration file must not be snapshotted: " + name)
    return name


def repository_url(value: str) -> str:
    parsed = urlsplit(value)
    if parsed.scheme == "https" and parsed.netloc and not (parsed.username or parsed.password or parsed.query or parsed.fragment):
        return value
    # Local repositories are useful for reproducibility tests; production uses HTTPS.
    local = Path(value)
    if local.is_absolute() and local.is_dir():
        return str(local.resolve())
    raise ValueError("Repository must be an HTTPS URL without credentials, or an existing absolute local fixture path")


def file_inventory(source: Path, names: list[str]) -> dict[str, str]:
    result = {}
    for name in sorted(set(names)):
        safe_name(name)
        path = source / name
        if path.is_symlink() or not path.resolve().is_relative_to(source):
            raise ValueError("Source path escapes checkout: " + name)
        if not path.exists():  # A tracked deletion is represented in the patch, not the resulting tree.
            continue
        if not path.is_file():
            raise ValueError("Submodules and non-file source entries are unsupported: " + name)
        result[name] = sha(path.read_bytes())
    return result


def source_names(source: Path) -> list[str]:
    return [value for value in git(source, "ls-files", "--cached", "--others", "--exclude-standard", "-z").decode("utf-8").split("\0") if value]


def staged_inventory(source: Path, env: dict[str, str]) -> tuple[dict[str, str], dict[str, str]]:
    entries = git(source, "ls-files", "--stage", "-z", env=env).decode("utf-8").split("\0")
    paths, object_ids, modes = [], [], {}
    for entry in filter(None, entries):
        attributes, name = entry.split("\t", 1)
        mode, object_id, stage = attributes.split(" ")
        safe_name(name)
        if mode not in {"100644", "100755"} or stage != "0":
            raise ValueError("Symlinks, submodules, or conflicted source entries are unsupported: " + name)
        paths.append(name)
        object_ids.append(object_id)
        modes[name] = mode
    # One cat-file process avoids spawning Git once per file, including large datasets.
    output = git(source, "cat-file", "--batch", env=env, data=("\n".join(object_ids) + "\n").encode("ascii")) if paths else b""
    inventory, offset = {}, 0
    for name, object_id in zip(paths, object_ids):
        header_end = output.index(b"\n", offset)
        found_id, kind, size = output[offset:header_end].decode("ascii").split(" ")
        if found_id != object_id or kind != "blob":
            raise ValueError("Unexpected Git object for " + name)
        offset = header_end + 1
        payload = output[offset:offset + int(size)]
        if len(payload) != int(size):
            raise ValueError("Truncated Git object")
        inventory[name] = sha(payload)
        offset += int(size) + 1
    return dict(sorted(inventory.items())), dict(sorted(modes.items()))


def capture(source: Path) -> dict:
    source = source.resolve()
    if git(source, "rev-parse", "--show-toplevel").decode().strip().replace("\\", "/").casefold() != source.as_posix().casefold():
        raise ValueError("Source must be the root of its own Git checkout")
    head = git(source, "rev-parse", "HEAD").decode().strip()
    before = file_inventory(source, source_names(source))
    with tempfile.TemporaryDirectory(prefix="starpath-admissions-index-") as folder:
        # The path must be absent: Git rejects an empty file as an index.
        env = {**os.environ, "GIT_INDEX_FILE": str(Path(folder) / "index"), "GIT_OPTIONAL_LOCKS": "0"}
        git(source, "read-tree", head, env=env)
        git(source, "add", "-A", "--", ".", env=env)
        ignored = git(source, "ls-files", "--cached", "--ignored", "--exclude-standard", "-z", env=env)
        if ignored:
            raise ValueError("Tracked ignored files cannot enter the snapshot; remove them from source tracking first")
        inventory, modes = staged_inventory(source, env)
        patch = git(source, "diff", "--cached", "--binary", "--full-index", "--no-ext-diff", "--no-color", "--no-renames",
                    "--src-prefix=a/", "--dst-prefix=b/", head, "--", env=env)
        tree = git(source, "write-tree", env=env).decode().strip()
    after = file_inventory(source, source_names(source))
    if before != after or head != git(source, "rev-parse", "HEAD").decode().strip():
        raise ValueError("Source changed while snapshotting; wait for editing/build work to finish and retry")
    if set(after) != set(inventory):
        raise ValueError("Source inventory and temporary index disagree")
    return {"head": head, "tree": tree, "patch": patch, "files": inventory, "modes": modes, "working_files": after}


def snapshot(source: Path, output: Path, upstream: str | None = None) -> dict:
    source, output = source.resolve(), output.resolve()
    if output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError("Snapshot must be outside the source checkout")
    origin = repository_url(upstream or git(source, "remote", "get-url", "origin").decode().strip())
    captured = capture(source)
    manifest = {
        "version": 1,
        "source_repository": origin,
        "source_base_commit": captured["head"],
        "source_git_tree": captured["tree"],
        "patch_file": PATCH_NAME,
        "patch_sha256": sha(captured["patch"]),
        "source_sha256": sha(canonical_json(captured["files"])),
        "source_files": captured["files"],
        "source_modes": captured["modes"],
        "working_tree_sha256": sha(canonical_json(captured["working_files"])),
        "working_tree_files": captured["working_files"],
        "inventory_encoding": "git-canonical-blobs; restore checkout uses core.autocrlf=false",
    }
    output.mkdir(parents=True, exist_ok=True)
    for name, payload in ((PATCH_NAME, captured["patch"]), (MANIFEST_NAME, json.dumps(manifest, sort_keys=True, indent=2).encode() + b"\n")):
        # Each replacement is atomic; manifest hashes expose any interrupted pair update.
        with tempfile.NamedTemporaryFile(dir=output, prefix=".snapshot-", delete=False) as temporary:
            temporary.write(payload)
            temporary_name = temporary.name
        os.replace(temporary_name, output / name)
    return manifest


def read_snapshot(folder: Path) -> tuple[dict, bytes]:
    manifest = json.loads((folder / MANIFEST_NAME).read_text(encoding="utf-8"))
    if manifest.get("version") != 1 or manifest.get("patch_file") != PATCH_NAME:
        raise ValueError("Unsupported source snapshot")
    if not re.fullmatch(r"[a-f0-9]{40}|[a-f0-9]{64}", manifest.get("source_base_commit", "")):
        raise ValueError("Snapshot must pin a full Git commit")
    repository_url(manifest["source_repository"])
    patch = (folder / PATCH_NAME).read_bytes()
    if sha(patch) != manifest.get("patch_sha256"):
        raise ValueError("Snapshot patch hash mismatch")
    files = manifest.get("source_files", {})
    if not files or sha(canonical_json(files)) != manifest.get("source_sha256"):
        raise ValueError("Snapshot inventory hash mismatch")
    for name, digest in files.items():
        safe_name(name)
        if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise ValueError("Invalid source digest")
    if set(manifest.get("source_modes", {})) != set(files) or any(mode not in {"100644", "100755"} for mode in manifest["source_modes"].values()):
        raise ValueError("Invalid source mode inventory")
    if sha(canonical_json(manifest.get("working_tree_files", {}))) != manifest.get("working_tree_sha256"):
        raise ValueError("Snapshot working-tree inventory hash mismatch")
    return manifest, patch


def verify(source: Path, folder: Path, *, original_bytes: bool = False) -> dict:
    manifest, _ = read_snapshot(folder)
    current = capture(source)
    if current["head"] != manifest["source_base_commit"]:
        raise ValueError("Checkout base commit differs from snapshot")
    if current["files"] != manifest["source_files"] or current["modes"] != manifest["source_modes"]:
        raise ValueError("Patched source inventory differs from snapshot")
    if original_bytes and current["working_files"] != manifest["working_tree_files"]:
        raise ValueError("Original working-tree byte inventory differs from snapshot")
    return {"verified": True, "files": len(current["files"]), "source_sha256": manifest["source_sha256"],
            "original_bytes": original_bytes}


def restore(folder: Path, destination: Path) -> dict:
    folder, destination = folder.resolve(), destination.resolve()
    if destination.exists():
        raise ValueError("Restore destination must be absent; existing checkouts are never overwritten")
    manifest, patch = read_snapshot(folder)
    destination.parent.mkdir(parents=True, exist_ok=True)
    git(destination.parent, "clone", "--no-checkout", "--no-hardlinks", "-c", "core.autocrlf=false",
        "--", manifest["source_repository"], str(destination))
    git(destination, "-c", "advice.detachedHead=false", "checkout", "--detach", manifest["source_base_commit"])
    if patch:
        git(destination, "apply", "--check", "--binary", "--whitespace=nowarn", "-", data=patch)
        git(destination, "apply", "--binary", "--whitespace=nowarn", "-", data=patch)
    # New files stay untracked; edits remain unstaged. Only the new clone is changed.
    return verify(destination, folder)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    save = sub.add_parser("snapshot", help="Capture stable integration source with a temporary Git index")
    save.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    save.add_argument("--output", type=Path, default=DEFAULT_SNAPSHOT)
    save.add_argument("--repository", help="Pinned upstream HTTPS repository; defaults to source origin")
    check = sub.add_parser("verify", help="Verify canonical source, including previously untracked files")
    check.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    check.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    check.add_argument("--original-bytes", action="store_true", help="Also match the original Windows working-tree hashes")
    load = sub.add_parser("restore", help="Clone pinned upstream and apply integration to an absent destination")
    load.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    load.add_argument("--destination", type=Path, default=DEFAULT_SOURCE)
    args = parser.parse_args()
    if args.command == "snapshot":
        result = snapshot(args.source, args.output, args.repository)
        report = {"snapshot": str(args.output.resolve()), "files": len(result["source_files"]),
                  "source_base_commit": result["source_base_commit"], "patch_sha256": result["patch_sha256"],
                  "source_sha256": result["source_sha256"]}
    elif args.command == "verify":
        report = verify(args.source, args.snapshot, original_bytes=args.original_bytes)
    else:
        report = restore(args.snapshot, args.destination)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
