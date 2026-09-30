from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
sys.argv=['blender','--checkpoint-walk']
import render_regalia_review
sys.argv=['blender','--','--scene-prefix','01_WALK','--frames','1,9,18,19,20,27,36','--output',str(ROOT/'art/Graduate/animation/regalia-walk-checkpoint-audit.json')]
from audit_regalia_pairs import main
main()
