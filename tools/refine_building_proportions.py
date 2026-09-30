"""Apply reviewed, uniformly scaled asset/plot adjustments without moving parcels."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / 'game/data/districts.json'
districts = json.loads(path.read_text(encoding='utf8'))
before_path = ROOT / 'deliverables/building-scale-before.json'
if not before_path.exists():
    before_path.write_text(json.dumps({d['station']: d['urban_buildings'] for d in districts}, indent=2), encoding='utf8')

# Preserve pitched red-roof housing where isolated parcels have room; use narrow
# facade models for closely spaced town houses and shopfronts. All axes scale
# uniformly in the existing generator; offsets and facing remain authored.
changes = {
    ('counseling', 4): dict(asset='suburban/Models/GLB format/building-type-k.glb', height=3.8),
    ('counseling', 7): dict(asset='commercial/Models/GLB format/building-d.glb', height=4.3),
    ('recommendations', 4): dict(asset='commercial/Models/GLB format/building-b.glb', height=4.5),
    ('life', 0): dict(max_width=4.8),
    ('life', 2): dict(max_width=4.2),
    ('life', 3): dict(max_width=4.8),
    ('life', 4): dict(max_width=4.3),
    ('life', 5): dict(max_width=4.8),
    ('life', 7): dict(asset='commercial/Models/GLB format/building-c.glb', height=3.5),
    ('wordking', 3): dict(asset='commercial/Models/GLB format/building-a.glb', height=4.5),
    ('universities', 7): dict(max_width=3.15),
}
for district in districts:
    for index, row in enumerate(district['urban_buildings']):
        row.update(changes.get((district['station'], index), {}))
# Re-read before the single write, so unrelated concurrent route/garden fields
# are preserved even if they changed while the reviewed patch was prepared.
current = json.loads(path.read_text(encoding='utf8'))
for district in current:
    for index, row in enumerate(district['urban_buildings']):
        row.update(changes.get((district['station'], index), {}))
path.write_text(json.dumps(current, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
print(f'Updated {len(changes)} building rows; offsets, yaw, front and other district data preserved.')
