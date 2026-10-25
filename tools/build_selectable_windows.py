"""Export a native boot plus independently installable full/low PCK bundles."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from split_web_packs import split
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--editor-recovery-mode',action='store_true',help='Export an already prepared import cache without editor extensions')
    parser.add_argument('--debug-candidate',action='store_true',help='Allow the existing localhost-only emulator host override in this candidate')
    parser.add_argument('--output',type=Path,default=ROOT/'build/windows-resource-packs',help='New candidate directory; keep prior published packages intact')
    parser.add_argument('--report',type=Path,default=ROOT/'deliverables/resource-packs/native-build.json')
    args=parser.parse_args()
    output=args.output.resolve()
    output.mkdir(parents=True,exist_ok=True)
    # Existing verification checks the unmodified full content before splitting.
    subprocess.run([sys.executable,str(ROOT/'tools/build_windows_release.py'),'--godot',args.godot,'--preset','Windows Standard','--output',str(output)]+(['--editor-recovery-mode'] if args.editor_recovery_mode else [])+(['--debug-candidate'] if args.debug_candidate else []),cwd=ROOT,check=True)
    inventory=ROOT/'build/native-resource-dependencies.json'
    subprocess.run([args.godot,'--headless','--path',str(ROOT/'game'),'--script','res://tools/collect_web_pack_dependencies.gd','--',str(inventory),'--native'],cwd=ROOT,check=True)
    report=split(output/'LittleWorld.pck',inventory,output,args.report.resolve(),boot_name='LittleWorld.pck')
    (output/'資源包說明.txt').write_text('首次開啟可選擇低階或滿血資源包。\n資源由本機 packs 資料夾安裝並驗證到使用者快取，請完整保留發行資料夾。\n主頁 → 遊戲設定 → 切換材質包：可安裝另一包並選擇是否保留原包，重新啟動套用。\n刪除只清除使用者的資源包快取；不會刪除帳號或探索進度。\n設定中可登出或切換帳號。\n',encoding='utf-8-sig')
    if args.debug_candidate:
        (output/'Start-Local-Candidate.ps1').write_text('''$ErrorActionPreference = 'Stop'
$candidateOrigin = 'http://127.0.0.1:4317'
$candidateConfig = Invoke-RestMethod ($candidateOrigin + '/admissions/firebase-config.json') -TimeoutSec 5
if (-not $candidateConfig.useEmulators -or $candidateConfig.projectId -ne 'demo-starpath-tests') {
    throw 'Start the local recommendation candidate server and demo Firebase emulators first.'
}
$candidateEmulators = Invoke-RestMethod 'http://127.0.0.1:4400/emulators' -TimeoutSec 5
if ($candidateEmulators.auth.port -ne 9099 -or $candidateEmulators.firestore.port -ne 8080) {
    throw 'The expected local Auth and Firestore emulators are not ready.'
}
$env:STARPATH_DEV_HOST_ORIGIN = $candidateOrigin
Start-Process -FilePath (Join-Path $PSScriptRoot 'LittleWorld.exe') -WorkingDirectory $PSScriptRoot
''',encoding='utf-8-sig')
        (output/'本機候選版說明.txt').write_text('此版本為尚未正式發布的選校推薦候選包。\n先依專案 docs/recommendation-room.md 啟動本機 Firebase 模擬器與推薦 host，再執行 Start-Local-Candidate.ps1。\n測試帳號資料只保存在本機模擬器。關閉模擬器前未匯出的測試資料不會保留。\n直接開啟 LittleWorld.exe 使用既有正式帳號服務；本輪新增推薦通道及規則尚未發布到正式服務。\n',encoding='utf-8-sig')
    # Re-stamp after replacing the monolithic pack with the verified boot/packs.
    import hashlib
    metadata=json.loads((output/'release.json').read_text(encoding='utf-8'))
    files=[p for p in output.rglob('*') if p.is_file() and p.name!='release.json' and p.suffix!='.log']
    metadata['native_files']={p.relative_to(output).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    metadata['file_bytes']={p.relative_to(output).as_posix():p.stat().st_size for p in files}
    metadata['resource_profiles']=json.loads((output/'index.packs.json').read_text(encoding='utf-8'))['profiles']
    (output/'release.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('SELECTABLE_WINDOWS_READY',output,'boot_bytes=',report['packs']['boot']['bytes'])
if __name__=='__main__':main()
