"""Run the world, collision, resource, and real browser checks sequentially."""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = 'C:/Users/xuan9/AppData/Local/Microsoft/WinGet/Links/godot_console.exe'
RUNTIME = Path('C:/Users/xuan9/.cache/codex-runtimes/codex-primary-runtime/dependencies')
NODE = str(RUNTIME / 'node/bin/node.exe')
PYTHON = str(RUNTIME / 'python/python.exe')
env = os.environ.copy()
env['NODE_PATH'] = str(RUNTIME / 'node/node_modules')
env['PYTHONUTF8'] = '1'
stages = [
    ('world', [GODOT, '--headless', '--path', 'game', '--script', 'res://tests/world_checks.gd'], 360),
    ('infrastructure', [GODOT, '--headless', '--path', 'game', '--script', 'res://tests/infrastructure_checks.gd'], 480),
    ('minimap', [GODOT, '--headless', '--path', 'game', '--script', 'res://tests/minimap_checks.gd'], 180),
    ('minimap-projection', [GODOT, '--headless', '--path', 'game', '--script', 'res://tests/minimap_projection_checks.gd'], 180),
    ('static', [PYTHON, 'C:/Users/xuan9/.codex/skills/godot/scripts/debug/validate_project.py', 'game', '--godot-bin', GODOT, '--timeout', '240', '--pretty'], 300),
    ('export', [GODOT, '--headless', '--path', 'game', '--export-debug', 'Web', '../build/web/index.html'], 360),
    ('browser', [NODE, 'tools/check_world_polish_browser.cjs'], 900),
]
start = sys.argv[1] if len(sys.argv) > 1 else 'world'
if start not in [stage[0] for stage in stages]:
    raise SystemExit('Unknown stage: ' + start)
stages = stages[[stage[0] for stage in stages].index(start):]
for name, command, timeout in stages:
    print('START', name, flush=True)
    log = ROOT / f'deliverables/world-polish-final-{name}.log'
    with log.open('w', encoding='utf-8') as output:
        process = subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    result = log.read_text(encoding='utf-8')
    if process.returncode or 'SCRIPT ERROR:' in result or '\nERROR:' in result:
        print('FAILED', name, 'see', log, flush=True)
        raise SystemExit(process.returncode or 1)
    print('PASS', name, flush=True)
print('WORLD_POLISH_VERIFIED', flush=True)
