"""Verify preserved original content and the explicit restored-skin addition."""
import json
import sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from validate_sleeve_cloth import snapshot, compare

baseline = json.loads((ROOT / 'tools/sleeve-preservation-before.json').read_text(encoding='utf-8'))
current = snapshot()
restored = {}
for label, scene in current['scenes'].items():
    restored[label] = scene['meshes'].pop('Graduate | restored arm skin')
    source = next(s for s in bpy.data.scenes if s.name.startswith({'Walk':'01_WALK','Run':'02_RUN','JumpDown':'03_JUMP'}[label]))
    obj = next(o for o in source.objects if o.get('graduate_role') == 'Graduate | restored arm skin')
    assert len(obj.data.vertices) == 78 and len(obj.data.polygons) == 64
    assert len(obj.modifiers) and any(m.type == 'ARMATURE' for m in obj.modifiers)
report = compare(baseline, current)
report['intentional_addition'] = {'role':'Graduate | restored arm skin',
                                'vertices_per_scene':78,'faces_per_scene':64,
                                'fingerprints':restored}
(ROOT / 'tools/sleeve-final-preservation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
if not report['ok']:
    raise AssertionError({'differences':report['differences'],'sleeve_errors':report['sleeve_errors']})
print('SLEEVE_FINAL_PRESERVATION_OK', flush=True)
