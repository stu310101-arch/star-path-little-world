"""Package the Godot project without editor caches or validation scratch files."""
from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT/'art'/'Graduate'/'Godot'
TARGET=PROJECT.parent/'Graduate_Godot_Asset.zip'
files=[PROJECT/'project.godot',PROJECT/'README.md']
for directory in ['assets','scenes','scripts','materials']:
    files += [p for p in (PROJECT/directory).rglob('*') if p.is_file() and p.name!='graduate-export-validation.json']
assert (PROJECT/'assets'/'graduate.glb').stat().st_size>100000
assert 'meshes/ensure_tangents=false' in (PROJECT/'assets'/'graduate.glb.import').read_text()
with zipfile.ZipFile(TARGET,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
    for path in sorted(files):archive.write(path,'GraduateGodot/'+path.relative_to(PROJECT).as_posix())
with zipfile.ZipFile(TARGET) as archive:
    assert archive.testzip() is None
    assert all('/.godot/' not in n for n in archive.namelist())
report={'zip':str(TARGET),'zip_size_bytes':TARGET.stat().st_size,'zip_sha256':hashlib.sha256(TARGET.read_bytes()).hexdigest(),'files':[p.relative_to(PROJECT).as_posix() for p in sorted(files)],'blender_file':'Male_Graduate_GameReady.blend','blender_sha256':hashlib.sha256((PROJECT.parent/'Male_Graduate_GameReady.blend').read_bytes()).hexdigest(),'import_settings_included':True}
(PROJECT.parent/'animation'/'game-asset-package.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
