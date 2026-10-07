"""Fetch only matching Windows templates from the official Godot 4.7.2 archive.

Checked HTTP ranges avoid downloading the 1.28 GB multi-platform archive.
ZIP CRC is checked for each selected entry; this is not a whole-archive SHA check.
Existing installed templates are preserved. No editor/renderer settings change.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import urllib.request
import zipfile

VERSION = "4.7.2-stable"
API = "https://api.github.com/repos/godotengine/godot-builds/releases/tags/" + VERSION


class RemoteArchive(io.RawIOBase):
    def __init__(self, url, size):
        self.url, self.size, self.offset, self.downloaded = url, size, 0, 0

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.offset

    def seek(self, offset, whence=0):
        self.offset = (0 if whence == 0 else self.offset if whence == 1 else self.size) + offset
        if self.offset < 0: raise ValueError("Negative archive offset")
        return self.offset

    def read(self, count=-1):
        end = self.size if count < 0 else min(self.size, self.offset + count)
        if end <= self.offset: return b""
        expected = f"bytes {self.offset}-{end-1}/{self.size}"
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={self.offset}-{end-1}",
                                                           "User-Agent": "LittleWorld-local-template-installer"})
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.status != 206 or response.headers.get("Content-Range") != expected:
                raise RuntimeError("Server did not honor the checked archive range")
            data = response.read(end - self.offset + 1)
        if len(data) != end - self.offset: raise RuntimeError("Truncated archive range")
        self.offset = end
        self.downloaded += len(data)
        return data


def main():
    request = urllib.request.Request(API, headers={"User-Agent": "LittleWorld-local-template-installer"})
    with urllib.request.urlopen(request, timeout=30) as response: release = json.load(response)
    asset = next(a for a in release["assets"] if a["name"] == f"Godot_v{VERSION}_export_templates.tpz")
    remote = RemoteArchive(asset["browser_download_url"], asset["size"])
    destination = Path(os.environ["APPDATA"]) / "Godot/export_templates/4.7.2.stable"
    destination.mkdir(parents=True, exist_ok=True)
    evidence = {"source": asset["browser_download_url"], "archive_bytes": asset["size"],
                "official_archive_digest": asset.get("digest"), "whole_archive_digest_checked": False,
                "entries": []}
    with zipfile.ZipFile(remote) as archive:
        for name in ["windows_debug_x86_64.exe", "windows_release_x86_64.exe"]:
            info = archive.getinfo("templates/" + name)
            target = destination / name
            if target.exists():
                print("Preserved existing", target, flush=True)
                continue
            temporary = target.with_suffix(".exe.downloading")
            try:
                with archive.open(info) as source, temporary.open("wb") as output:
                    shutil.copyfileobj(source, output, 4 * 1024 * 1024)
                if temporary.stat().st_size != info.file_size: raise RuntimeError("Template size differs")
                with temporary.open("rb") as source: digest = hashlib.file_digest(source, "sha256").hexdigest()
                temporary.replace(target)
            except BaseException:
                temporary.unlink(missing_ok=True)
                raise
            evidence["entries"].append({"name": name, "bytes": info.file_size, "zip_crc32": info.CRC, "sha256": digest})
            print("Installed", name, info.file_size, flush=True)
    evidence["downloaded_bytes"] = remote.downloaded
    report = Path(__file__).resolve().parents[1] / "build/windows-template-install.json"
    report.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print("Checked selected-entry CRC and sizes; received", remote.downloaded, "bytes", flush=True)


if __name__ == "__main__": main()
