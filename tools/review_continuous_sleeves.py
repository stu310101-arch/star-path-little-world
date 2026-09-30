"""Read-only sleeve review and non-sleeve preservation verification."""
import bpy,sys,runpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
runpy.run_path(str(ROOT/'tools/validate_sleeve_delivery.py'),run_name='__main__')
for label,frames in [('run','1,7,13,19'),('walk','1,19'),('jump','18,27,35')]:
    sys.argv=['render_sleeve_probes.py','--','--clip',label,'--frames',frames]
    runpy.run_path(str(ROOT/'tools/render_sleeve_probes.py'),run_name='__main__')
runpy.run_path(str(ROOT/'tools/audit_continuous_sleeve_contacts.py'),run_name='__main__')
print('CONTINUOUS_REVIEW_DONE',flush=True)
