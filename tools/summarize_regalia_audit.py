"""Compact retained clothing contacts; does not infer visible penetration."""
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); data=json.loads(p.read_text(encoding='utf-8'))
print('complete',data.get('complete'),'seconds',data.get('elapsed_seconds'))
for clip,frames in data['clips'].items():
    totals={}
    for frame in frames:
        for pair in frame['pairs']:
            if not any(r.startswith(('01 |','02 |','03 |','04 |','05 |')) for r in pair['roles']):continue
            independent=pair['relation_counts'].get('independent_surface',0)
            key=' <-> '.join(pair['roles'])
            totals.setdefault(key,[]).append({'f':frame['frame'],'raw':pair['raw_crossings'],'relations':pair['relation_counts'],'external':pair['external_reachable_relation_counts']})
    print(clip,json.dumps(totals,ensure_ascii=False))
