"""Split a normal Godot 4.7 Web export into a boot PCK and deferred packs.

Run collect_web_pack_dependencies.gd against the same imported project first.
No image/model conversion happens here: original exported entry bytes and
resource paths are preserved. Identical bytes can share one physical payload.
The format-4 layout follows Godot core/io/file_access_pack.cpp. Encrypted,
sparse, patched, and unknown pack variants deliberately fail closed.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
from typing import Mapping

MAGIC = 0x43504447
HEADER_BYTES = 112
MANIFEST_PATH = "data/web_packs.json"


@dataclass(frozen=True)
class Pack:
    engine: tuple[int, int, int]
    entries: Mapping[str, memoryview]


def resource_name(path: str) -> str:
    name = path.removeprefix("res://")
    if not name or "\\" in name or "\0" in name or name.startswith("/") or any(
        part in (".", "..", "") for part in name.split("/")
    ):
        raise ValueError(f"Unsafe resource path: {path!r}")
    return name


def read_pack(path: Path) -> Pack:
    """Read and fully validate every directory record and payload MD5."""
    data = memoryview(path.read_bytes())
    if len(data) < HEADER_BYTES:
        raise ValueError("Truncated PCK header")
    magic, version, major, minor, patch, flags, base, directory = struct.unpack_from("<6I2Q", data)
    if magic != MAGIC or version != 4 or flags != 2:
        raise ValueError(f"Unsupported PCK format: magic={magic:x}, version={version}, flags={flags}")
    if not HEADER_BYTES <= base <= directory <= len(data) - 4:
        raise ValueError("PCK payload/directory offsets are out of bounds")
    count, = struct.unpack_from("<I", data, directory)
    cursor = directory + 4
    if count > (len(data) - cursor) // 40:
        raise ValueError("PCK directory count exceeds available records")
    entries: dict[str, memoryview] = {}
    ranges: dict[tuple[int, int], bytes] = {}
    for _ in range(count):
        if cursor + 4 > len(data):
            raise ValueError("Truncated PCK path length")
        length, = struct.unpack_from("<I", data, cursor)
        cursor += 4
        if length == 0 or cursor + length + 36 > len(data):
            raise ValueError("Truncated PCK directory record")
        raw_name = bytes(data[cursor:cursor + length])
        cursor += length
        try:
            name = resource_name(raw_name.rstrip(b"\0").decode("utf-8"))
        except UnicodeDecodeError as error:
            raise ValueError("Non-UTF8 PCK resource path") from error
        relative, size = struct.unpack_from("<2Q", data, cursor)
        expected_md5 = bytes(data[cursor + 16:cursor + 32])
        entry_flags, = struct.unpack_from("<I", data, cursor + 32)
        cursor += 36
        start, end = base + relative, base + relative + size
        if entry_flags != 0 or start < base or end > directory:
            raise ValueError(f"Invalid PCK entry bounds/flags: {name}")
        if name in entries:
            raise ValueError(f"Duplicate PCK resource path: {name}")
        payload = data[start:end]
        if hashlib.md5(payload).digest() != expected_md5:
            raise ValueError(f"PCK MD5 mismatch: {name}")
        extent = (start, end)
        if extent in ranges and ranges[extent] != expected_md5:
            raise ValueError(f"Conflicting aliased PCK payload: {name}")
        ranges[extent] = expected_md5
        entries[name] = payload
    previous_end = base
    for start, end in sorted(ranges):
        if start < previous_end:
            raise ValueError("Partially overlapping PCK payloads")
        previous_end = end
    if cursor != len(data):
        raise ValueError("Unexpected bytes after PCK directory")
    return Pack((major, minor, patch), entries)


def write_pack(path: Path, entries: Mapping[str, memoryview | bytes], engine: tuple[int, int, int]) -> dict:
    """Write deterministic PCK bytes; equal payloads retain their original paths."""
    path.parent.mkdir(parents=True, exist_ok=True)
    records: list[tuple[str, int, int, bytes]] = []
    seen: dict[bytes, tuple[int, memoryview | bytes]] = {}
    deduplicated_bytes = 0
    with path.open("wb") as stream:
        stream.write(bytes(HEADER_BYTES))
        for original_name, payload in sorted(entries.items()):
            name = resource_name(original_name)
            sha = hashlib.sha256(payload).digest()
            prior = seen.get(sha)
            if prior is not None:
                if prior[1] != payload:
                    raise ValueError("SHA-256 collision while deduplicating PCK")
                offset = prior[0]
                deduplicated_bytes += len(payload)
            else:
                stream.write(bytes((-stream.tell()) % 16))
                offset = stream.tell() - HEADER_BYTES
                stream.write(payload)
                seen[sha] = (offset, payload)
            records.append((name, offset, len(payload), hashlib.md5(payload).digest()))
        stream.write(bytes((-stream.tell()) % 16))
        directory = stream.tell()
        stream.write(struct.pack("<I", len(records)))
        for name, offset, size, md5 in records:
            encoded = name.encode("utf-8")
            encoded += bytes((-len(encoded)) % 4)
            stream.write(struct.pack("<I", len(encoded)))
            stream.write(encoded)
            stream.write(struct.pack("<2Q", offset, size))
            stream.write(md5)
            stream.write(struct.pack("<I", 0))
        stream.seek(0)
        stream.write(struct.pack("<6I2Q", MAGIC, 4, *engine, 2, HEADER_BYTES, directory))
    # Re-reading verifies all written bounds and digests, not just file size.
    checked = read_pack(path)
    if set(checked.entries) != set(entries):
        raise ValueError("Written PCK directory differs from input")
    return {"bytes": path.stat().st_size, "sha256": file_hash(path),
            "entries": len(entries), "deduplicated_bytes": deduplicated_bytes}


def file_hash(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def closure(roots: list[str], graph: dict[str, list[str]]) -> set[str]:
    result: set[str] = set()
    pending = list(roots)
    while pending:
        path = pending.pop()
        if path in result:
            continue
        if path not in graph:
            raise ValueError(f"Dependency inventory has no record for {path}")
        result.add(path)
        pending.extend(graph[path])
    return result


def exported_entries(source: str, entries: Mapping[str, memoryview]) -> set[str]:
    """Follow exported Godot import/remap metadata, including platform targets."""
    name = resource_name(source)
    found: set[str] = set()
    pending = [name, name + ".remap", name + ".import", name + ".uid"]
    while pending:
        candidate = pending.pop()
        if candidate in found or candidate not in entries:
            continue
        found.add(candidate)
        if candidate.endswith((".remap", ".import")):
            text = bytes(entries[candidate]).decode("utf-8")
            for ref in re.findall(r'"(res://[^"\r\n]+)"', text):
                target = resource_name(ref)
                # source_file is the source's own path, which is normally
                # absent from an exported PCK. Actual destinations must exist.
                if target == name:
                    continue
                if target not in entries:
                    raise ValueError(f"Export metadata points to a missing entry: {candidate} -> {target}")
                pending.append(target)
    if not found:
        raise ValueError(f"Required runtime source is absent from the exported PCK: {source}")
    return found


def plan_pack(pack: Pack, inventory: dict) -> tuple[dict, dict, dict, dict]:
    if inventory.get("version") != 1 or inventory.get("errors"):
        raise ValueError("Dependency inventory is unsupported or contains errors")
    engine = inventory.get("engine", {})
    if tuple(engine.get(key) for key in ("major", "minor", "patch")) != pack.engine:
        raise ValueError("Dependency inventory and exported PCK use different Godot versions")
    groups = inventory["groups"]
    if "boot" not in groups or "shared" in groups:
        raise ValueError("Inventory requires boot and reserves the shared group name")
    if any(not re.fullmatch(r"[a-z][a-z0-9_]*", key) for key in groups):
        raise ValueError("Invalid resource pack group identifier")
    graph = inventory["dependencies"]
    sources = {key: closure(roots, graph) for key, roots in groups.items()}
    source_entries = {source: exported_entries(source, pack.entries) for source in set().union(*sources.values())}
    group_entries = {key: set().union(*(source_entries[source] for source in resources))
                     for key, resources in sources.items()}
    # Metadata is small and the exported runtime may consult it before dynamic
    # packs exist. Import payloads remain assigned through dependency closure.
    metadata = {name for name in pack.entries if name in {
        "project.binary", ".godot/global_script_class_cache.cfg",
        ".godot/uid_cache.bin", ".godot/extension_list.cfg"}}
    if "project.binary" not in metadata:
        raise ValueError("This is not a complete Godot export (project.binary is missing)")
    group_entries["boot"].update(metadata)
    owners: dict[str, str] = {}
    for name in set().union(*group_entries.values()):
        users = [key for key, names in group_entries.items() if name in names]
        owners[name] = "boot" if "boot" in users else users[0] if len(users) == 1 else "shared"
    # Byte-identical entries must live in the same pack to share one payload.
    # If the boot needs a copy, all aliases stay there; otherwise common bytes
    # become shared, with explicit dependencies on the shared pack below.
    equal_payloads: dict[bytes, list[str]] = {}
    for name in owners:
        equal_payloads.setdefault(hashlib.sha256(pack.entries[name]).digest(), []).append(name)
    for names in equal_payloads.values():
        users = {owners[name] for name in names}
        if len(users) > 1:
            owner = "boot" if "boot" in users else "shared"
            for name in names:
                if pack.entries[name] != pack.entries[names[0]]:
                    raise ValueError("SHA-256 collision while assigning shared payloads")
                owners[name] = owner
    contents: dict[str, dict] = {key: {} for key in sorted(set(owners.values()))}
    for name, owner in owners.items():
        contents[owner][name] = pack.entries[name]
    dependencies: dict[str, list[str]] = {}
    for key, names in group_entries.items():
        if key != "boot":
            dependencies[key] = sorted({owners[name] for name in names} - {"boot", key})
    if "shared" in contents:
        # Shared payloads are dependency leaves because they contain every
        # non-boot dependency used by two or more closures.
        dependencies["shared"] = []
    for key, required in inventory.get("prerequisites", {}).items():
        if key not in groups or any(value not in groups or value == key for value in required):
            raise ValueError("Invalid explicit pack prerequisite")
        dependencies[key] = sorted(set(dependencies.get(key, [])) | set(required))
    resources: dict[str, str] = {}
    for source, names in source_entries.items():
        users = [key for key, paths in sources.items() if source in paths]
        if "boot" in users:
            continue
        owner = users[0] if len(users) == 1 else "shared"
        # A group can have no unique bytes (e.g. aliases). Keep a tiny marker
        # pack so its readiness contract can still include required shared
        # resources without assuming a caller knows physical entry ownership.
        contents.setdefault(owner, {})
        dependencies.setdefault(owner, sorted({owners[name] for name in names} - {"boot", owner}))
        resources[source] = owner
    # Check logical readiness against physical ownership. This catches a future
    # importer/remap change before publishing packs which mount successfully but
    # fail when a dependent resource is first accessed.
    for key in contents:
        available = pack_dependency_closure(key, dependencies, set(contents)) | {"boot"}
        for source in sources.get(key, []):
            if not {owners[name] for name in source_entries[source]} <= available:
                raise ValueError(f"Pack {key} does not include every dependency of {source}")
    report = {
        "source_entries": len(pack.entries), "runtime_source_count": len(source_entries),
        "required_entries": len(owners), "omitted_entries": [
            {"path": name, "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
            for name, payload in sorted(pack.entries.items()) if name not in owners],
        "group_roots": groups,
    }
    return contents, dependencies, resources, report


def pack_dependency_closure(key: str, dependencies: dict, keys: set[str], visiting: frozenset = frozenset()) -> set[str]:
    if key not in keys:
        raise ValueError(f"Missing resource pack dependency: {key}")
    if key in visiting:
        raise ValueError(f"Cyclic resource pack dependency: {key}")
    result = {key}
    for required in dependencies.get(key, []):
        result.update(pack_dependency_closure(required, dependencies, keys, visiting | {key}))
    return result


def update_html_size(path: Path, size: int) -> None:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"const GODOT_CONFIG\s*=\s*(\{[^\n]+\});", text)
    if match is None:
        raise ValueError("Cannot identify Godot HTML export configuration")
    config = json.loads(match[1])
    if "index.pck" not in config.get("fileSizes", {}):
        raise ValueError("Godot HTML does not reference index.pck")
    config["fileSizes"]["index.pck"] = size
    text = text[:match.start(1)] + json.dumps(config, separators=(",", ":"), ensure_ascii=False) + text[match.end(1):]
    path.write_text(text, encoding="utf-8", newline="\n")


def split(source: Path, inventory_path: Path, output: Path, report_path: Path) -> dict:
    source_hash = file_hash(source)
    source_bytes = source.stat().st_size
    pack = read_pack(source)
    if MANIFEST_PATH in pack.entries:
        raise ValueError("Input is already split; run a fresh full Godot export before splitting")
    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    contents, dependencies, resources, report = plan_pack(pack, inventory)
    output.mkdir(parents=True, exist_ok=True)
    packs_dir = output / "packs"
    packs_dir.mkdir(exist_ok=True)
    previous = output / "index.packs.json"
    old_urls: list[str] = []
    if previous.exists():
        old_urls = [row["url"] for row in json.loads(previous.read_text(encoding="utf-8"))["packs"].values()]
    for url in old_urls:
        parsed = PurePosixPath(url)
        if len(parsed.parts) != 2 or parsed.parts[0] != "packs" or not re.fullmatch(r"[a-z0-9_]+-[0-9a-f]{16}\.pck", parsed.name):
            raise ValueError("Previous manifest has an unsafe pack path; refusing cleanup")
    manifest = {"version": 1, "packs": {}, "resources": dict(sorted(resources.items()))}
    details = {}
    for key in sorted(set(contents) - {"boot"}):
        temporary = packs_dir / f"{key}.pck.tmp"
        info = write_pack(temporary, contents[key], pack.engine)
        url = f"packs/{key}-{info['sha256'][:16]}.pck"
        temporary.replace(output / url)
        manifest["packs"][key] = {"url": url, "bytes": info["bytes"], "sha256": info["sha256"],
                                  "dependencies": dependencies.get(key, [])}
        details[key] = info
    encoded_manifest = (json.dumps(manifest, sort_keys=True, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    contents["boot"][MANIFEST_PATH] = encoded_manifest
    temporary_boot = output / "index.pck.tmp"
    details["boot"] = write_pack(temporary_boot, contents["boot"], pack.engine)
    # Update only after all packs have passed structural and digest validation.
    update_html_size(output / "index.html", details["boot"]["bytes"])
    temporary_boot.replace(output / "index.pck")
    previous.write_bytes(encoded_manifest)
    current_urls = {row["url"] for row in manifest["packs"].values()}
    for url in old_urls:
        if url not in current_urls:
            (output / url).unlink(missing_ok=True)
    report.update({"source_sha256": source_hash, "source_bytes": source_bytes,
                   "godot_version": list(pack.engine), "packs": details,
                   "published_pck_bytes": sum(row["bytes"] for row in details.values()),
                   "omitted_payload_bytes": sum(row["bytes"] for row in report["omitted_entries"]),
                   "exact_duplicate_payload_bytes_removed": sum(row["deduplicated_bytes"] for row in details.values())})
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("build/web/index.pck"))
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("build/web"))
    parser.add_argument("--report", type=Path, default=Path("deliverables/performance/web-pack-build.json"))
    args = parser.parse_args()
    report = split(args.source, args.dependencies, args.output, args.report)
    print(json.dumps({key: report[key] for key in ("source_bytes", "published_pck_bytes", "omitted_payload_bytes", "exact_duplicate_payload_bytes_removed", "packs")}, indent=2))


if __name__ == "__main__":
    main()
