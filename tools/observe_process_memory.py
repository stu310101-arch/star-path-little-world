"""Sample only a QA-owned Windows process tree; no psutil or task termination.

Working-set sums may double count shared pages. Private bytes are committed
private memory, not resident RAM; neither includes independently owned GPU VRAM.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
from pathlib import Path
import time


class ProcessEntry(c.Structure):
    _fields_ = [("size", w.DWORD), ("usage", w.DWORD), ("pid", w.DWORD),
                ("heap", c.c_size_t), ("module", w.DWORD), ("threads", w.DWORD),
                ("parent", w.DWORD), ("priority", w.LONG), ("flags", w.DWORD),
                ("exe", w.WCHAR * 260)]


class MemoryCounters(c.Structure):
    _fields_ = [("cb", w.DWORD), ("faults", w.DWORD)] + [
        (name, c.c_size_t) for name in ("peak_working_set", "working_set", "peak_paged_pool",
        "paged_pool", "peak_nonpaged_pool", "nonpaged_pool", "pagefile", "peak_pagefile", "private")]


class MemoryStatus(c.Structure):
    _fields_ = [("length", w.DWORD), ("load", w.DWORD)] + [
        (name, c.c_ulonglong) for name in ("total_physical", "available_physical", "total_pagefile",
        "available_pagefile", "total_virtual", "available_virtual", "available_extended")]


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--pid", required=True, type=int)
    args.add_argument("--output", required=True, type=Path)
    options = args.parse_args()
    kernel, psapi = c.WinDLL("kernel32", use_last_error=True), c.WinDLL("psapi", use_last_error=True)
    kernel.CreateToolhelp32Snapshot.restype = w.HANDLE
    kernel.OpenProcess.restype = w.HANDLE
    kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
    kernel.CloseHandle.argtypes = [w.HANDLE]
    kernel.Process32FirstW.argtypes = [w.HANDLE, c.POINTER(ProcessEntry)]
    kernel.Process32NextW.argtypes = [w.HANDLE, c.POINTER(ProcessEntry)]
    psapi.GetProcessMemoryInfo.argtypes = [w.HANDLE, c.POINTER(MemoryCounters), w.DWORD]
    rows = []
    start = time.time()
    options.output.parent.mkdir(parents=True, exist_ok=True)
    while time.time() - start < 2400:
        snapshot = kernel.CreateToolhelp32Snapshot(2, 0)
        entries = {}
        item = ProcessEntry(); item.size = c.sizeof(item)
        ok = kernel.Process32FirstW(snapshot, c.byref(item))
        while ok:
            entries[item.pid] = {"parent": item.parent, "name": item.exe}
            ok = kernel.Process32NextW(snapshot, c.byref(item))
        kernel.CloseHandle(snapshot)
        if options.pid not in entries:
            break
        owned = {options.pid}
        while True:
            expanded = owned | {pid for pid, info in entries.items() if info["parent"] in owned}
            if expanded == owned: break
            owned = expanded
        samples = []
        for pid in sorted(owned):
            handle = kernel.OpenProcess(0x1000 | 0x0010, False, pid)
            if not handle: continue
            counters = MemoryCounters(); counters.cb = c.sizeof(counters)
            if psapi.GetProcessMemoryInfo(handle, c.byref(counters), counters.cb):
                samples.append({"pid": pid, "name": entries[pid]["name"], "working_set": counters.working_set,
                                "private_bytes": counters.private, "peak_working_set": counters.peak_working_set})
            kernel.CloseHandle(handle)
        state = MemoryStatus(); state.length = c.sizeof(state)
        kernel.GlobalMemoryStatusEx(c.byref(state))
        rows.append({"epoch_ms": round(time.time()*1000), "elapsed_s": time.time()-start,
                     "working_set_sum": sum(v["working_set"] for v in samples),
                     "private_bytes_sum": sum(v["private_bytes"] for v in samples),
                     "host_available_physical": state.available_physical, "host_total_physical": state.total_physical,
                     "processes": samples})
        options.output.write_text(json.dumps({"root_pid": options.pid, "samples": rows,
            "method": "Windows process tree sampled each second; working set sum includes shared pages; private bytes are commit, not RAM; GPU VRAM excluded."}, indent=2), encoding="utf-8")
        time.sleep(1)


if __name__ == "__main__":
    main()
