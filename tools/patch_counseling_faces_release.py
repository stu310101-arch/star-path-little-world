"""Patch only counseling geometry into the last published Web release."""
from pathlib import Path
import hashlib, json, re, shutil, urllib.request
from split_web_packs import read_pack, write_pack, update_html_size
from prepare_web_delivery import prepare as delivery
from prepare_cloudflare_release import prepare, metadata

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'build/cloudflare-counseling-low-20261025'
SOURCE=ROOT/'build/web'
OUTPUT=ROOT/'build/web-counseling-double-faces-20261025'
TARGET=ROOT/'build/cloudflare-counseling-double-faces-20261025'
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
write=lambda p,d:p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
previous=read(BASE/'site/index.release.json')
request=urllib.request.Request('https://star-path-little-world.star-path-little-world.workers.dev/index.release.json',headers={'User-Agent':'Mozilla/5.0'})
with urllib.request.urlopen(request,timeout=40) as response:
    live=json.load(response)
assert live==previous,'Published release changed: select its matching baseline first'
source_stamp=read(SOURCE/'index.release.json')
assert source_stamp['build_id']==previous['source_build_id']
assert not OUTPUT.exists() and not TARGET.exists()
OUTPUT.mkdir()
for name,info in source_stamp['files'].items():
    origin=SOURCE/name
    assert metadata(origin)==info,name
    dest=OUTPUT/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(origin,dest)
write(OUTPUT/'index.release.json',source_stamp)
for variant in ['mobile','']:
    shutil.copytree(BASE/'site'/variant/'licenses',OUTPUT/variant/'licenses')
    shutil.copyfile(BASE/'site'/variant/'THIRD_PARTY_NOTICES.txt',OUTPUT/variant/'THIRD_PARTY_NOTICES.txt')
patches=[]
for variant in ['mobile','']:
    folder=OUTPUT/variant
    manifest=read(folder/'index.packs.json')
    for group in ['counseling_room','counseling_low']:
        old=manifest['packs'][group]
        pack=read_pack(folder/old['url']);entries=dict(pack.entries)
        if group=='counseling_room':
            changed=[n for n in entries if n.startswith('.godot/imported/counseling_room.glb-') and n.endswith('.scn')]
        else:changed=['generated/low/counseling/room.scn']
        assert len(changed)==1
        for name in changed:entries[name]=(ROOT/'game'/name).read_bytes()
        temporary=folder/'packs/counseling-patch.tmp'
        info=write_pack(temporary,entries,pack.engine)
        url=f"packs/{group}-{info['sha256'][:16]}.pck"
        temporary.replace(folder/url)
        check=read_pack(folder/url)
        assert set(check.entries)==set(pack.entries)
        assert all(bytes(check.entries[n])==bytes(pack.entries[n]) for n in entries if n not in changed)
        manifest['packs'][group]={**old,'url':url,'bytes':info['bytes'],'sha256':info['sha256']}
        patches.append({'variant':variant or 'desktop','group':group,'changed_entries':changed,'sha256':info['sha256']})
        # Only the isolated new candidate is pruned; baseline is immutable.
        (folder/old['url']).unlink()
    write(folder/'index.packs.json',manifest)
    boot=read_pack(folder/'index.pck');entries=dict(boot.entries)
    entries['data/web_packs.json']=(folder/'index.packs.json').read_bytes()
    info=write_pack(folder/'boot-new.pck',entries,boot.engine)
    (folder/'boot-new.pck').replace(folder/'index.pck')
    update_html_size(folder/'index.html',info['bytes'])
    delivery(folder)
    stamp=read(folder/'index.release.json')
    identity=hashlib.sha256((source_stamp['build_id']+json.dumps(patches,sort_keys=True)).encode()).hexdigest()
    stamp.update(build_id='packs-'+identity[:16],source_sha256=identity,
                 geometry_patch={'base_build_id':source_stamp['build_id'],'patches':patches.copy()})
    html=(folder/'index.html').read_text(encoding='utf-8')
    html=re.sub(r'(<meta name="little-world-build" content=")[^"]+(\">)',lambda m:m[1]+stamp['build_id']+m[2],html)
    (folder/'index.html').write_text(html,encoding='utf-8')
    stamp['files']={p.relative_to(folder).as_posix():metadata(p) for p in sorted(folder.rglob('*')) if p.is_file() and p!=folder/'index.release.json' and p.name!='index.service-worker.js'}
    write(folder/'index.release.json',stamp)
config=read(BASE/'wrangler.jsonc')
vars_path=ROOT/'build/counseling-faces-public-vars.json';write(vars_path,config['vars'])
report=prepare(OUTPUT,TARGET,admissions_source=ROOT/'admissions-site',admissions_out=BASE/'site/admissions',auth_worker=BASE/'auth-worker.js',auth_vars=vars_path)
assert (TARGET/'auth-worker.js').read_bytes()==(BASE/'auth-worker.js').read_bytes()
assert read(TARGET/'wrangler.jsonc')==config
for name,info in previous['files'].items():
    if name.startswith('admissions/'):
        assert metadata(TARGET/'site'/name)==info,name
report['geometry_patch']={'base_build_id':previous['build_id'],'patches':patches,'other_pck_entries_preserved':True}
write(TARGET/'verification.json',report)
print(json.dumps({'output':str(TARGET),'build_id':report['build_id'],'passed':report['passed'],'patches':patches},indent=2))
