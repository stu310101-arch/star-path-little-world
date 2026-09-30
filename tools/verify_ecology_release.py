"""Run dependent final checks sequentially, retaining logs for every stage."""
import os, subprocess, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
GODOT='C:/Users/xuan9/AppData/Local/Microsoft/WinGet/Links/godot_console.exe'
PY='C:/Users/xuan9/.codex/skill-runtimes/3d-art/Scripts/python.exe'
NODE='C:/Users/xuan9/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'
env=os.environ.copy(); env['NODE_PATH']='C:/Users/xuan9/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules'
stages=[
 ('physics',[GODOT,'--headless','--path','game','--script','res://tests/world_checks.gd'],'build/ecology-tests.log',240),
 ('static',[PY,'-X','utf8','C:/Users/xuan9/.codex/skills/godot/scripts/debug/validate_project.py','game','--godot-bin',GODOT,'--timeout','180','--pretty'],'game/validation.json',240),
 ('web-export',[GODOT,'--headless','--path','game','--export-debug','Web','../build/web/index.html'],'build/ecology-export.log',360),
 ('visual-and-controls',[NODE,'tools/capture_ecology_browser.cjs'],'build/ecology-browser-capture.log',900),
]
for name,command,log,timeout in stages:
 print('START',name,flush=True)
 with (ROOT/log).open('w',encoding='utf8') as output:
  result=subprocess.run(command,cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT,timeout=timeout)
 if result.returncode:
  print('FAILED',name,result.returncode,flush=True); raise SystemExit(result.returncode)
 text=(ROOT/log).read_text(encoding='utf8')
 if name in ('physics','web-export') and ('SCRIPT ERROR:' in text or '\nERROR:' in text):
  raise RuntimeError(name+' logged engine errors')
 print('PASS',name,flush=True)
print('ECOLOGY_RELEASE_CHECKS_OK',flush=True)
