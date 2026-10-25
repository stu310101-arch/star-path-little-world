"""Guard the actual GLB channels that previously broke palette and leaf export.

This checks exported arrays, not Blender source settings. A valid file alone
cannot catch a canopy sampling one transparent UV or a white colour palette.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import struct

def audit(path:Path)->dict:
    raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
    document=json.loads(raw[20:20+length]);binary=raw[28+length:]
    def values(index):
        accessor=document['accessors'][index];view=document['bufferViews'][accessor['bufferView']]
        components={'VEC2':2,'VEC3':3,'VEC4':4}[accessor['type']]
        kind,size={5126:('f',4),5121:('B',1),5123:('H',2)}[accessor['componentType']]
        stride=view.get('byteStride',components*size);offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
        divisor=(255 if kind=='B' else 65535) if accessor.get('normalized') else 1
        for row in range(accessor['count']):yield tuple(v/divisor for v in struct.unpack_from('<'+kind*components,binary,offset+row*stride))
    errors=[];palette=0;canopies=0
    for mesh in document['meshes']:
        for primitive in mesh['primitives']:
            material=document['materials'][primitive['material']];name=material.get('name','')
            attrs=primitive['attributes']
            if 'Palette' in name:
                palette+=1
                if 'COLOR_0' not in attrs or not any(any(c<.99 for c in value[:3]) for value in values(attrs['COLOR_0'])):
                    errors.append(mesh['name']+': palette has no authored colour')
            if 'Foliage' in name:
                canopies+=1
                channel=material.get('pbrMetallicRoughness',{}).get('baseColorTexture',{}).get('texCoord',0)
                attr='TEXCOORD_'+str(channel)
                if attr not in attrs or len(set(values(attrs[attr])))<4:errors.append(mesh['name']+': canopy UV collapsed')
                if 'COLOR_0' in attrs and not any(any(c>.01 for c in value[:3]) for value in values(attrs['COLOR_0'])):
                    errors.append(mesh['name']+': canopy colour multiplier is black')
    return {'path':str(path),'palettePrimitives':palette,'canopyPrimitives':canopies,'errors':errors,'passed':not errors}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('paths',nargs='+',type=Path);parser.add_argument('--output',type=Path)
    args=parser.parse_args();reports=[audit(path) for path in args.paths]
    result={'passed':all(r['passed'] for r in reports),'assets':reports}
    text=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if args.output:args.output.write_text(text,encoding='utf-8')
    print(text);raise SystemExit(0 if result['passed'] else 1)
