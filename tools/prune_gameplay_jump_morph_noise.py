"""Inspect/prune only sub-10-micrometre somersault morph noise, without Blender.

Default is read-only. --apply preserves an exact pre-optimization copy, removes
only tiny POSITION+NORMAL targets, rewrites weights and compacts reachable
accessors/buffers. No animation times, bones, materials or base vertices change.
"""
import argparse, copy, hashlib, json, math, mmap, os, shutil, struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/'game/assets/character/graduate_jump.glb'
OUT=ROOT/'deliverables/gameplay-jump'
COUNTS={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
TYPES={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
SCALE=1.75/4.8

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        while chunk:=f.read(1024*1024):h.update(chunk)
    return h.hexdigest()

class GLB:
    def __init__(self,path):
        self.file=path.open('rb');self.raw=mmap.mmap(self.file.fileno(),0,access=mmap.ACCESS_READ)
        assert struct.unpack_from('<III',self.raw,0)==(0x46546c67,2,len(self.raw))
        n,t=struct.unpack_from('<II',self.raw,12);assert t==0x4e4f534a
        self.doc=json.loads(self.raw[20:20+n]);self.base=28+n
        size,t=struct.unpack_from('<II',self.raw,20+n);assert t==0x004e4942
    def close(self):self.raw.close();self.file.close()
    def accessor(self,index):
        a=self.doc['accessors'][index];components=COUNTS[a['type']];kind,width=TYPES[a['componentType']]
        unpack=struct.Struct('<'+kind*components)
        values=[(0,)*components]*a['count']
        if 'bufferView' in a:
            view=self.doc['bufferViews'][a['bufferView']]
            offset=self.base+view.get('byteOffset',0)+a.get('byteOffset',0)
            stride=view.get('byteStride',width*components)
            values=[unpack.unpack_from(self.raw,offset+i*stride) for i in range(a['count'])]
        if 'sparse' in a:
            sparse=a['sparse'];index=sparse['indices'];view=self.doc['bufferViews'][index['bufferView']]
            kind,iw=TYPES[index['componentType']];ist=struct.Struct('<'+kind)
            io=self.base+view.get('byteOffset',0)+index.get('byteOffset',0)
            view=self.doc['bufferViews'][sparse['values']['bufferView']]
            vo=self.base+view.get('byteOffset',0)+sparse['values'].get('byteOffset',0)
            for i in range(sparse['count']):values[ist.unpack_from(self.raw,io+i*iw)[0]]=unpack.unpack_from(self.raw,vo+i*unpack.size)
        return values

def normmax(values):return math.sqrt(max((sum(x*x for x in v) for v in values),default=0))

def compact(doc,src,additions,path):
    references=[]
    def ref(mapping,key):references.append((mapping,key))
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            for k in primitive['attributes']:ref(primitive['attributes'],k)
            if 'indices' in primitive:ref(primitive,'indices')
            for morph in primitive.get('targets',[]):
                for k in morph:ref(morph,k)
    for skin in doc.get('skins',[]):
        if 'inverseBindMatrices' in skin:ref(skin,'inverseBindMatrices')
    for clip in doc['animations']:
        for s in clip['samplers']:ref(s,'input');ref(s,'output')
    used=sorted({m[k] for m,k in references});remap={old:i for i,old in enumerate(used)}
    doc['accessors']=[doc['accessors'][i] for i in used]
    for m,k in references:m[k]=remap[m[k]]
    vr=[]
    for a in doc['accessors']:
        if 'bufferView' in a:vr.append(a)
        if 'sparse' in a:vr.extend([a['sparse']['indices'],a['sparse']['values']])
    vr.extend(im for im in doc.get('images',[]) if 'bufferView' in im)
    used=sorted({m['bufferView'] for m in vr});remap={old:i for i,old in enumerate(used)}
    views=[];length=0;segments=[]
    for old in used:
        view=copy.deepcopy(doc['bufferViews'][old]);length=(length+3)//4*4
        start=view.get('byteOffset',0);segments.append((length,old,start,view['byteLength']))
        view['byteOffset']=length;view['buffer']=0;length+=view['byteLength'];views.append(view)
    for m in vr:m['bufferView']=remap[m['bufferView']]
    doc['bufferViews']=views;doc['buffers']=[{'byteLength':length}]
    encoded=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode('utf8');encoded+=b' '*(-len(encoded)%4)
    padded=(length+3)//4*4
    with path.open('wb') as f:
        f.write(struct.pack('<III',0x46546c67,2,28+len(encoded)+padded))
        f.write(struct.pack('<II',len(encoded),0x4e4f534a));f.write(encoded)
        f.write(struct.pack('<II',padded,0x004e4942));position=0
        for offset,old,start,n in segments:
            f.write(b'\0'*(offset-position))
            if old in additions:f.write(additions[old])
            else:f.write(src.raw[src.base+start:src.base+start+n])
            position=offset+n
        f.write(b'\0'*(padded-position))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');args=parser.parse_args()
    src=GLB(PATH);doc=src.doc
    rows=[];kept={};caps={};normalcaps={}
    for mi,mesh in enumerate(doc['meshes']):
        count=len(mesh['primitives'][0].get('targets',[]));magnitudes=[0.]*count;normals=[0.]*count
        for primitive in mesh['primitives']:
            assert len(primitive.get('targets',[]))==count
            for i,target in enumerate(primitive.get('targets',[])):
                if 'POSITION' in target:magnitudes[i]=max(magnitudes[i],normmax(src.accessor(target['POSITION']))*SCALE)
                if 'NORMAL' in target:normals[i]=max(normals[i],normmax(src.accessor(target['NORMAL'])))
                assert not set(target)-{'POSITION','NORMAL'}
        kept[mi]=[i for i in range(count) if magnitudes[i]>1e-5 or normals[i]>1e-4]
        caps[mi]=magnitudes;normalcaps[mi]=normals
        removed=set(range(count))-set(kept[mi])
        rows.append({'mesh':mi,'name':mesh.get('name'),'before':count,'after':len(kept[mi]),
          'max_position_metres':max(magnitudes,default=0),'max_normal_delta':max(normals,default=0),
          'removed_position_bound_metres':max((magnitudes[i] for i in removed),default=0),
          'removed_normal_bound':max((normals[i] for i in removed),default=0)})
    report={'mode':'apply' if args.apply else 'inspect','input_bytes':PATH.stat().st_size,'input_sha256':sha(PATH),
      'position_threshold_metres':1e-5,'normal_threshold':1e-4,'targets_before':sum(r['before'] for r in rows),
      'targets_after':sum(r['after'] for r in rows),'meshes':rows,'sample_rate_changed':False}
    print(json.dumps(report,indent=2),flush=True)
    if not args.apply:
        (OUT/'morph-noise-inspection.json').write_text(json.dumps(report,indent=2),encoding='utf8');src.close();return
    backup=OUT/'graduate_jump-before-noise-prune.glb'
    if backup.exists():assert sha(backup)==sha(PATH),'Existing backup differs; do not overwrite review source'
    else:shutil.copyfile(PATH,backup)
    originals={str(p):sha(p) for p in [ROOT/'art/Graduate/Male_Graduate_GameReady.blend',ROOT/'game/assets/character/graduate.glb',ROOT/'art/Graduate/Godot/assets/graduate.glb']}
    old_counts={i:len(m['primitives'][0].get('targets',[])) for i,m in enumerate(doc['meshes'])}
    additions={};clip_bounds=[]
    for clip in doc['animations']:
        new_channels=[];new_samplers=[];max_error=0.;max_normal=0.
        for channel in clip['channels']:
            sampler=copy.deepcopy(clip['samplers'][channel['sampler']]);channel=copy.deepcopy(channel)
            if channel['target']['path']=='weights':
                mi=doc['nodes'][channel['target']['node']]['mesh'];count=old_counts[mi]
                values=[v[0] for v in src.accessor(sampler['output'])];assert count and len(values)%count==0
                removed=set(range(count))-set(kept[mi])
                for f in range(len(values)//count):
                    max_error=max(max_error,sum(abs(values[f*count+i])*caps[mi][i] for i in removed))
                    max_normal=max(max_normal,sum(abs(values[f*count+i])*normalcaps[mi][i] for i in removed))
                if not kept[mi]:continue
                values=[values[f*count+i] for f in range(len(values)//count) for i in kept[mi]]
                data=struct.pack('<'+'f'*len(values),*values);vi=len(doc['bufferViews'])
                doc['bufferViews'].append({'buffer':0,'byteOffset':0,'byteLength':len(data)})
                additions[vi]=data
                sampler['output']=len(doc['accessors'])
                doc['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(values),'type':'SCALAR'})
            else:
                # Rotation interpolation and original key times remain byte-identical.
                if channel['target']['path']=='scale':
                    assert max(abs(x-1) for v in src.accessor(sampler['output']) for x in v)<1e-5
            channel['sampler']=len(new_samplers);new_channels.append(channel);new_samplers.append(sampler)
        clip['channels']=new_channels;clip['samplers']=new_samplers
        clip_bounds.append({'clip':clip['name'],'max_position_error_bound_metres':max_error,'max_normal_error_bound':max_normal})
    for mi,mesh in enumerate(doc['meshes']):
        for p in mesh['primitives']:
            if 'targets' in p:
                p['targets']=[p['targets'][i] for i in kept[mi]]
                if not p['targets']:del p['targets']
        if 'weights' in mesh:
            mesh['weights']=[mesh['weights'][i] for i in kept[mi]]
            if not mesh['weights']:del mesh['weights']
        if 'targetNames' in mesh.get('extras',{}):mesh['extras']['targetNames']=[mesh['extras']['targetNames'][i] for i in kept[mi]]
    for node in doc['nodes']:
        if 'weights' in node:
            node['weights']=[node['weights'][i] for i in kept[node['mesh']]]
            if not node['weights']:del node['weights']
    temporary=PATH.with_suffix('.optimized.tmp')
    compact(doc,src,additions,temporary);src.close()
    check=GLB(temporary)
    assert [a['name'] for a in check.doc['animations']]==['JumpStart','JumpAir','JumpLand']
    for clip in check.doc['animations']:
        for channel in clip['channels']:
            sampler=clip['samplers'][channel['sampler']]
            n=check.doc['accessors'][sampler['input']]['count'];output=check.doc['accessors'][sampler['output']]
            if channel['target']['path']=='weights':
                mi=check.doc['nodes'][channel['target']['node']]['mesh']
                assert output['count']==n*len(check.doc['meshes'][mi]['primitives'][0]['targets'])
            else:assert output['count']==n
    check.close()
    assert all(sha(Path(p))==h for p,h in originals.items())
    report.update(output_bytes=temporary.stat().st_size,output_sha256=sha(temporary),clips=clip_bounds,
      preserved_originals=originals,backup=str(backup),error_bound_basis='Each retained target unchanged. Removed displacement bounded by sum absolute animated weights times per-target maximum; LINEAR interpolation remains inside endpoint bound. All bone scales unity.')
    assert max(c['max_position_error_bound_metres'] for c in clip_bounds)<=1e-5
    os.replace(temporary,PATH)
    (OUT/'morph-noise-prune-validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print('MORPH_NOISE_PRUNED '+json.dumps({k:report[k] for k in ['input_bytes','output_bytes','targets_before','targets_after','clips']}),flush=True)

if __name__=='__main__':main()
