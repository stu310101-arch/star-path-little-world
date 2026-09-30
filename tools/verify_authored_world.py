"""Sequential checks for authored layout, camera interaction, and exported Web build."""
from pathlib import Path
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
def gd(script):
    return [GODOT, '--headless', '--path', 'game', '--script', 'res://' + script]
stages = [
    ('authored-layout', gd('tests/authored_layout_checks.gd'), 600),
    ('camera', gd('tests/camera_drag_checks.gd'), 180),
    ('camera-vegetation', gd('tests/camera_vegetation_checks.gd'), 120),
    ('static-multimesh', gd('tests/static_multimesh_checks.gd'), 120),
    ('frontage', gd('tests/building_frontage_checks.gd'), 180),
    ('building-proportions', [PYTHON, 'tools/check_building_proportions.py', '--actual'], 120),
    ('building-clearances', [PYTHON, 'tools/check_building_spherical_clearances.py'], 120),
    ('building-dry-footprints', [PYTHON, 'tools/check_building_dry_footprints.py'], 120),
    ('planting', gd('tests/planting_plan_checks.gd'), 180),
    ('street-lighting', gd('tests/street_lighting_checks.gd'), 180),
    ('world', gd('tests/world_checks.gd'), 360),
    ('infrastructure', gd('tests/infrastructure_checks.gd'), 480),
    ('minimap', gd('tests/minimap_checks.gd'), 180),
    ('minimap-location', gd('tests/minimap_location_checks.gd'), 120),
    ('sakura-cartography', gd('tests/sakura_cartography_checks.gd'), 180),
    ('garden-sign', gd('tests/garden_sign_checks.gd'), 120),
    ('minimap-projection', gd('tests/minimap_projection_checks.gd'), 240),
    ('static', [PYTHON, 'C:/Users/xuan9/.codex/skills/godot/scripts/debug/validate_project.py', 'game', '--godot-bin', GODOT, '--timeout', '240', '--pretty'], 300),
    ('export', [GODOT, '--headless', '--path', 'game', '--export-debug', 'Web', '../build/web/index.html'], 360),
    ('notices', [PYTHON, '-X', 'utf8', 'tools/package_web_notices.py'], 90),
    ('browser', [NODE, 'tools/check_world_polish_browser.cjs'], 900),
    ('visible-drag', [NODE, 'tools/check_visible_drag_browser.cjs'], 900),
]
start = sys.argv[1] if len(sys.argv) > 1 else stages[0][0]
if start not in [stage[0] for stage in stages]:
    raise SystemExit('Unknown stage: ' + start)
stages = stages[[stage[0] for stage in stages].index(start):]
stop = sys.argv[2] if len(sys.argv) > 2 else None
if stop:
    if stop not in [stage[0] for stage in stages]:
        raise SystemExit('Unknown or earlier stop stage: ' + stop)
    stages = stages[:[stage[0] for stage in stages].index(stop) + 1]
for name, command, timeout in stages:
    print('START', name, flush=True)
    log = ROOT / f'deliverables/authored-final-{name}.log'
    with log.open('w', encoding='utf-8') as output:
        process = subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    result = log.read_text(encoding='utf-8')
    if process.returncode or 'SCRIPT ERROR:' in result or '\nERROR:' in result:
        print('FAILED', name, 'see', log, flush=True)
        raise SystemExit(process.returncode or 1)
    print('PASS', name, flush=True)
print('SELECTED_STAGES_VERIFIED' if stop else 'AUTHORED_WORLD_VERIFIED', flush=True)
