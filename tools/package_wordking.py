"""Build an isolated same-origin WordKing copy without changing its original checkout or service."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'wordking-source'
OUTPUT = ROOT / 'admissions-site/public/wordking-app'

def once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f'WordKing integration anchor changed: {old[:70]}')
    return text.replace(old, new)

def package(source: Path = SOURCE, output: Path = OUTPUT) -> dict:
    source, output = source.resolve(), output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for folder in ['assets', 'data', 'background music']:
        shutil.copytree(source / folder, output / folder, dirs_exist_ok=True)
    app = (source / 'assets/app.js').read_text(encoding='utf-8')
    app = app[app.index('const WORD_DATABASE_URL'):]
    start, end = app.index('const firebaseConfig = {'), app.index('const BGM_TRACKS = [')
    app = app[:start] + app[end:]
    app = once(app, 'const app = initializeApp(firebaseConfig);\nconst auth = getAuth(app);\nconst db = getFirestore(app);\nconst provider = new GoogleAuthProvider();',
        "const starpath = await globalThis.WordKingStarPath.connect();\nconst auth = starpath.auth;\nconst provider = null;\nconst onAuthStateChanged = (_auth, next, error) => starpath.observe(next, error);\nconst signInWithPopup = () => starpath.openAccount();\nconst signOut = () => starpath.signOut();")
    start, end = app.index('function getPersistence() {'), app.index('\nfunction acknowledgeCloudRevision')
    app = app[:start] + 'function getPersistence() { return starpath.persistence(); }\n' + app[end:]
    app = once(app, '`?page=${page}`', '`?page=${page}${starpath.libraryQuery}`')
    app = once(app, "document.addEventListener('DOMContentLoaded', bootstrap);", "if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bootstrap); else void bootstrap();")
    app = app.replace('請先登入 Google 帳號', '請先登入星途帳號')
    if 'firebasejs/' in app or 'wordking-434f7' in app: raise ValueError('Original Firebase boundary leaked into integrated app')
    (output / 'assets/app.js').write_text(app, encoding='utf-8', newline='\n')
    shutil.copyfile(ROOT / 'tools/wordking_starpath_adapter.js', output / 'assets/starpath-adapter.js')
    shutil.copyfile(ROOT / 'tools/export_wordking_readonly.js', output / 'readonly-export.js')
    html = (source / 'index.html').read_text(encoding='utf-8')
    html = once(html, '<script src="./assets/persistence.js?v=20260908-u2"></script>', '<script src="./assets/starpath-adapter.js"></script>')
    html = html.replace('<title>單字王 - 核心系統</title>', '<title>星途 · 單字王</title>')
    (output / 'index.html').write_text(html, encoding='utf-8', newline='\n')
    guide = '''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><title>原單字王唯讀備份</title><style>body{max-width:760px;margin:3rem auto;padding:1rem;font:18px/1.7 sans-serif;color:#173e43}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#edf0e9;padding:1rem}</style><h1>只匯出你自己的原單字王資料</h1><p>原服務、帳號及資料均不會被更改。請先在原單字王登入自己的帳號並完成同步。舊的「遷移備份」不是目前完整備份。</p><ol><li>下載下方唯讀工具並檢查原始碼；它只讀取目前登入 UID 的資料，不包含任何寫入 API。</li><li>在原單字王頁面開啟瀏覽器開發者工具的 Console，執行這份程式。</li><li>取得 wordking-current-snapshot.json 後回到星途選擇檔案，檢查預覽，再按確認匯入。</li></ol><p><a href="readonly-export.js" download>下載唯讀匯出工具</a> · <a href="https://stu310101-arch.github.io/wordking/?page=home" target="_blank" rel="noopener">開啟原單字王</a></p><p>如果原站的版本、登入狀態或瀏覽器政策使工具無法讀取，請保留原資料，改用已持有的完整備份。星途不會修改原站的登入網域或設定來繞過限制。</p></html>'''
    (output / 'readonly-export.html').write_text(guide, encoding='utf-8')
    go_output = output.parent / 'games/go'
    go_output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'game/web_games/go/index.html', go_output / 'index.html')
    commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    manifest = {'source': 'https://github.com/stu310101-arch/wordking', 'commit': commit, 'source_modified': False,
        'account_project': 'StarPath host runtime only', 'original_service_changes': False,
        'files': {p.relative_to(output).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.rglob('*')) if p.is_file() and p.name != 'integration-manifest.json'}}
    (output / 'integration-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    return manifest

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=SOURCE); parser.add_argument('--output', type=Path, default=OUTPUT)
    args = parser.parse_args(); result = package(args.source, args.output)
    print(json.dumps({'commit': result['commit'], 'files': len(result['files'])}))
