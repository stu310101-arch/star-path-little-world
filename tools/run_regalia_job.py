"""Launch one named Blender check with bounded logs and a recorded PID."""
from pathlib import Path
import subprocess, sys, json
ROOT=Path(__file__).resolve().parents[1]
BLENDER=r'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
jobs={
 'layers':['--background',str(ROOT/'art/Graduate/Male_Graduate_GameReady.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_graduate_regalia.py')],
 'render_layers':['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'),'--threads','3','--python-exit-code','1','--python',str(ROOT/'tools/render_regalia_review.py')],
 'layers_audit':['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/audit_regalia_pairs.py'),'--','--scene-prefix','04_IDLE','01_WALK','02_RUN','03_JUMP','--samples','04_IDLE=1,51,91','01_WALK=9','02_RUN=7','03_JUMP=27','--output',str(ROOT/'art/Graduate/animation/regalia-pairs-layers.json')],
 'arm_probe':['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/probe_regalia_arm_abduction.py'),'--','--samples','04_IDLE=1,51,91','01_WALK=9','02_RUN=7','03_JUMP=27','--output',str(ROOT/'art/Graduate/animation/arm-abduction-probe.json')],
 'audit_before':['--background',str(ROOT/'art/Graduate/Male_Graduate_GameReady.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/audit_regalia_pairs.py'),'--','--scene-prefix','04_IDLE','01_WALK','02_RUN','03_JUMP','--samples','04_IDLE=1,51,91','01_WALK=9','02_RUN=7','03_JUMP=27','--output',str(ROOT/'art/Graduate/animation/regalia-pairs-before.json')],
 'bulk_smoke':['--background','--factory-startup','--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/smoke_export_morph_bulk.py')],
}
name=sys.argv[1]
thin_candidate=ROOT/'art/Graduate/Male_Graduate_Regalia_ThinFabric_Candidate.blend'
jobs['thin_fabric']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Pants_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/prepare_regalia_thin_fabric.py'),'--','--output',str(thin_candidate)]
jobs['thin_audit']=['--background',str(thin_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/audit_regalia_pairs.py'),'--','--samples','01_WALK=5,13,15,24,30','02_RUN=1,7,12,13,16,18,19,20,22,24','03_JUMP=4,7,8,19,20,27,38','04_IDLE=1,51,101,103','--max-examples','8','--output',str(ROOT/'art/Graduate/animation/regalia-thin-audit.json')]
jobs['thin_render']=['--background',str(thin_candidate),'--threads','3','--python-exit-code','1','--python',str(ROOT/'tools/render_regalia_review.py'),'--','--worst']
motion_candidate=ROOT/'art/Graduate/Male_Graduate_Regalia_MotionPants_Candidate.blend'
jobs['motion_pants']=['--background',str(thin_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_motion_pants_clearance.py'),'--','--output',str(motion_candidate),'--clips','run','jump']
jobs['drape_inspect']=['--background',str(motion_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/inspect_idle_drape.py')]
vertical_review=ROOT/'art/Graduate/Male_Graduate_Idle_VerticalDrape_Review.blend'
jobs['vertical_drape']=['--background',str(thin_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_idle_vertical_drape.py'),'--','--output',str(vertical_review)]
jobs['vertical_verify']=['--background',str(vertical_review),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/verify_idle_vertical_drape.py')]
jobs['pants_diagnostic']=['--background',str(thin_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_motion_pants_clearance.py'),'--','--output',str(ROOT/'art/Graduate/Unused_MotionPants_Diagnostic.blend'),'--diagnose-preservation','--report',str(ROOT/'art/Graduate/animation/motion-pants-preservation-probe.json')]
jobs['stole_probe']=['--background',str(thin_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_stole_sleeve_contacts.py'),'--','--output',str(ROOT/'art/Graduate/Male_Graduate_Stole_Probe.blend'),'--probe','--samples','02_RUN=7,19,20','03_JUMP=27']
jobs['stole_probe2']=['--background',str(thin_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_stole_sleeve_contacts.py'),'--','--output',str(ROOT/'art/Graduate/Male_Graduate_Stole_Probe2.blend'),'--probe','--samples','02_RUN=19,20','--maximum','.05']
jobs['stole_probe3']=['--background',str(thin_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_stole_sleeve_contacts.py'),'--','--output',str(ROOT/'art/Graduate/Male_Graduate_Stole_Probe3.blend'),'--probe','--samples','02_RUN=19','03_JUMP=38','--maximum','.06']
exact_candidate=ROOT/'art/Graduate/Male_Graduate_Regalia_Exact_Candidate.blend'
jobs['exact_finish']=['--background',str(motion_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/finish_regalia_exact_contacts.py'),'--','--output',str(exact_candidate)]
jobs['exact_probe']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Pants_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/finish_regalia_exact_contacts.py'),'--','--output',str(ROOT/'art/Graduate/Male_Graduate_Exact_Probe.blend'),'--probe']
final_candidate=ROOT/'art/Graduate/Male_Graduate_Regalia_Final_Candidate.blend'
jobs['postprocess']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/postprocess_regalia_layers.py'),'--','--output',str(final_candidate)]
jobs['idle_hang']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_LoopV2_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_idle_gown_hang.py'),'--','--output',str(ROOT/'art/Graduate/Male_Graduate_Idle_Hang_Candidate.blend')]
jobs['review_hang']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Idle_Hang_Candidate.blend'),'--threads','3','--python-exit-code','1','--python',str(ROOT/'tools/review_idle_hang.py')]
jobs['postprocess_hang']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Idle_Hang_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/postprocess_regalia_layers.py'),'--','--output',str(final_candidate)]
jobs['pants_probe']=['--background',str(final_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_idle_pants_clearance.py'),'--','--output',str(ROOT/'art/Graduate/Male_Graduate_Pants_Probe.blend'),'--probe-frames','1,51,77']
jobs['pants']=['--background',str(final_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_idle_pants_clearance.py'),'--','--output',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Pants_Candidate.blend')]
jobs['trajectory']=['--background','--factory-startup','--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/validate_regalia_trajectory.py'),'--','--candidate',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend')]
jobs['loop_join']=['--background','--factory-startup','--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_regalia_loop_join.py'),'--','--candidate',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'),'--output',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Loop_Candidate.blend'),'--maximum-adjustment','.04','--window','12']
jobs['loop_join_run']=['--background','--factory-startup','--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_regalia_loop_join.py'),'--','--candidate',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Loop_Candidate.blend'),'--output',str(ROOT/'art/Graduate/Male_Graduate_Regalia_LoopV2_Candidate.blend'),'--report',str(ROOT/'art/Graduate/animation/regalia-local-loop-run-v2.json'),'--clips','run','--maximum-adjustment','.04','--window','12','--projection-maximum','.015','--projection-iterations','24']
jobs['focused_audit']=['--background','--factory-startup','--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/audit_regalia_focused.py'),'--','--baseline',str(ROOT/'art/Graduate/Male_Graduate_BeforeRegalia_2026-09-20.blend'),'--candidate',str(final_candidate),'--output',str(ROOT/'art/Graduate/animation/regalia-focused.json')]
jobs['focused_pants']=['--background','--factory-startup','--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/audit_regalia_focused.py'),'--','--baseline',str(ROOT/'art/Graduate/Male_Graduate_BeforeRegalia_2026-09-20.blend'),'--candidate',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Pants_Candidate.blend'),'--output',str(ROOT/'art/Graduate/animation/regalia-focused-pants.json')]
jobs['critical_subframes']=['--background',str(final_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/audit_regalia_pairs.py'),'--','--samples','01_WALK=4.5,5,5.5,12.5,13,13.5,23.5,24,24.5,36.5','02_RUN=1,1.5,7.5,18.5,19.5,20.5,21.5,22,22.5,24.5','04_IDLE=1.5,50.5,77.5,101.5,103.5,120.5','03_JUMP=7.5,19.5,27.5,38.5,39.5','--max-examples','4','--output',str(ROOT/'art/Graduate/animation/regalia-critical-subframes.json')]
jobs['render_final']=['--background',str(final_candidate),'--threads','3','--python-exit-code','1','--python',str(ROOT/'tools/render_regalia_review.py')]
jobs['export_final']=['--background',str(final_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/export_graduate_godot.py'),'--','--output',str(ROOT/'art/Graduate/animation/graduate-regalia-candidate.glb')]
jobs['motion_final']=['--background',str(final_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/validate_regalia_motion.py')]
jobs['split_probe']=['--background',str(ROOT/'art/Graduate/Male_Graduate_GameReady.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/probe_regalia_constraint_split.py')]
jobs['accessory_probe']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Checkpoint.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/postprocess_regalia_layers.py'),'--','--output',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Walk_Postprocess.blend'),'--scene-prefix','01_WALK','--probe-frames','1,9,19']
jobs['order_probe']=['--background',str(ROOT/'art/Graduate/Male_Graduate_GameReady.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/probe_regalia_order.py')]
jobs['layers_resume']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Checkpoint.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_graduate_regalia.py')]
jobs['render_checkpoint']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Checkpoint.blend'),'--threads','3','--python-exit-code','1','--python',str(ROOT/'tools/render_regalia_review.py'),'--','--checkpoint-walk']
jobs['review_checkpoint']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Checkpoint.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/review_walk_checkpoint.py')]
jobs['neck_probe']=['--background',str(ROOT/'art/Graduate/Male_Graduate_GameReady.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/probe_regalia_neck.py'),'--','--only','gown','--output',str(ROOT/'art/Graduate/animation/regalia-neck-probe.json')]
jobs['motion']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/validate_regalia_motion.py')]
jobs['full_audit']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/audit_regalia_pairs.py'),'--','--stride','1','--max-examples','4','--output',str(ROOT/'art/Graduate/animation/regalia-pairs-full.json')]
jobs['export']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/export_graduate_godot.py'),'--','--output',str(ROOT/'art/Graduate/animation/graduate-regalia-candidate.glb')]
jobs['gown_probe']=['--background',str(ROOT/'art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend'),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/probe_gown_repair.py')]
jobs['layers_v2_audit']=jobs['layers_audit'][:-1]+[str(ROOT/'art/Graduate/animation/regalia-pairs-layers-v2.json')]
cuff_candidate=ROOT/'art/Graduate/Male_Graduate_Regalia_Cuff_Candidate.blend'
delivery_candidate=ROOT/'art/Graduate/Male_Graduate_Regalia_Delivery_Candidate.blend'
jobs['idle_cuff']=['--background',str(exact_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_idle_cuff_clearance.py'),'--','--output',str(cuff_candidate)]
jobs['stole_all']=['--background',str(cuff_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/repair_stole_sleeve_contacts.py'),'--','--output',str(delivery_candidate),'--all-frames','--maximum','.06']
for key in ('focused_audit','critical_subframes','render_final','export_final','motion_final'):
    jobs[key]=[str(delivery_candidate) if arg==str(final_candidate) else arg for arg in jobs[key]]
jobs['save_delivery']=['--background',str(delivery_candidate),'--threads','2','--python-exit-code','1','--python',str(ROOT/'tools/save_regalia_delivery.py')]
if name=='status':
    output=subprocess.check_output(['tasklist','/FO','CSV'],text=True)
    print('\n'.join(l for l in output.splitlines() if any(n in l.lower() for n in ['blender','powershell','pwsh','python.exe'])),flush=True)
else:
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    with (ROOT/f'tools/regalia-{name}.log').open('w',encoding='utf-8') as out,(ROOT/f'tools/regalia-{name}.err').open('w',encoding='utf-8') as err:
        p=subprocess.Popen([BLENDER,*jobs[name]],cwd=ROOT,stdout=out,stderr=err,startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW)
    (ROOT/f'tools/regalia-{name}-process.json').write_text(json.dumps({'pid':p.pid,'args':jobs[name]},indent=2),encoding='utf-8')
    print(json.dumps({'job':name,'pid':p.pid}),flush=True)
