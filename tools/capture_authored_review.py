"""Capture the actual renderer sequentially, within the laptop's GPU budget."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = 'C:/Users/xuan9/AppData/Local/Microsoft/WinGet/Links/godot_console.exe'
stages = [
    ('garden', 'capture_authored_garden.gd', []),
    ('world', 'capture_world_polish.gd', ['--', '--authored']),
    ('streets', 'capture_authored_streets.gd', []),
]
if len(sys.argv) > 1:
    stages = [stage for stage in stages if stage[0] == sys.argv[1]]
    if not stages:
        raise SystemExit('Unknown capture stage')
for name, script, arguments in stages:
    print('CAPTURE_START', name, flush=True)
    path = ROOT / f'deliverables/authored-{name}-final.log'
    command = [GODOT, '--path', 'game', '--script', 'res://tools/' + script,
               '--position', '1450,30', '--rendering-driver', 'opengl3'] + arguments
    with path.open('w', encoding='utf-8') as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=600)
    text = path.read_text(encoding='utf-8')
    if result.returncode or 'SCRIPT ERROR:' in text or '\nERROR:' in text:
        print('CAPTURE_FAILED', name, path, flush=True)
        raise SystemExit(result.returncode or 1)
    print('CAPTURE_COMPLETE', name, flush=True)
print('CAPTURE_COMPLETE_REQUIRES_VISUAL_REVIEW', flush=True)
