"""Run sequential Blender stages in one process on the validated locomotion file."""
import runpy,sys
from pathlib import Path
TOOLS=Path(__file__).resolve().parent
for script,args in [('animate_portal_entry.py',[]),('simulate_portal_cloth.py',['--quality','16']),('render_portal_entry.py',['--probes'])]:
    sys.argv=['blender','--']+args
    print('PORTAL_STAGE',script,flush=True)
    runpy.run_path(str(TOOLS/script),run_name='__main__')
