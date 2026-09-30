from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
import render_regalia_review
sys.argv=['blender','--','--scene-prefix','04_IDLE','--frames','1,51,77','--max-examples','6','--output',str(ROOT/'art/Graduate/animation/regalia-idle-hang-audit.json')]
from audit_regalia_pairs import main
main()
