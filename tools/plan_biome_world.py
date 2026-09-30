"""Deterministic authored urban parcels and ecological reserves. No random buildings."""
import json, zipfile, datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
backup=ROOT/'build/backups'/('biomes-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'.zip')
with zipfile.ZipFile(backup,'w',zipfile.ZIP_DEFLATED) as z:
    for folder in ['game/data','game/scripts','game/tools','game/tests']:
        for p in (ROOT/folder).rglob('*'):
            if p.is_file(): z.write(p,p.relative_to(ROOT))
layout=json.loads((ROOT/'game/data/world_layout.json').read_text(encoding='utf8'))
layout['radius']=48.0
(ROOT/'game/data/world_layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf8')
districts=json.loads((ROOT/'game/data/districts.json').read_text(encoding='utf8'))
plans=[
 dict(theme='湖畔市政中心', loop=[[-16,-15],[14,-15],[14,15],[-16,15]], roads=[[[-1,-15],[-1,15]],[[-16,2],[14,2]]],
      positions=[[-9,-7],[6,-7],[-10,8],[-5,8],[5,8],[10,8],[-23,-10],[21,-6]],
      gardens=[[-7,-1],[-7,20],[7,21]], civic=[6,-1.3], extent=[36,32],
      paths=[[[0,15],[0,22],[-13,23],[-21,19],[-22,15]],[[-16,2],[-20,2],[-21,-4]]],
      water=[dict(kind='lake',center=[-27,6],size=[4.8,7.5])], biome='湖岸闊葉林', habitat=[[-27,-8],[-26,-16],[-18,23]],visit=[-21,15]),
 dict(theme='曲岸商務碼頭', loop=[[-17,-15],[6,-18],[17,-10],[18,12],[-17,15]],roads=[[[-17,1],[18,1]]],
      positions=[[1,-9],[-9,-7],[9,-7],[10,8],[2,8],[-10,9],[-24,0],[22,-15]],
      gardens=[[-8,-1],[3,15],[-21,16]],civic=[-9,-1.3],extent=[36,33],
      paths=[[[18,10],[20,16],[17,23],[7,26]],[[18,1],[23,1],[29,1],[32,1]]],
      water=[dict(kind='river',points=[[26,-25],[24,-16],[27,-7],[26,3],[25,13],[18,26]],width=2.6)],biome='河口蘆葦濕地',habitat=[[30,9],[29,16],[23,23]],visit=[20,16]),
 dict(theme='文化步行院落', loop=[[-17,-15],[15,-15],[15,13],[1,13],[1,18],[-17,18]],roads=[],
      positions=[[-7,-8],[6,-8],[-10,5],[-10,12],[7,7],[22,-3],[-24,-8],[-5,24]],
      gardens=[[-5,1],[7,18],[-22,9]],civic=[6,-2.3],extent=[37,34],
      paths=[[[0,-15],[0,13]],[[-17,0],[15,0]],[[-17,-15],[-22,-21],[-10,-25],[0,-26],[16,-23]]],
      water=[dict(kind='lake',center=[25,12],size=[5,6])],biome='蕨類混合林',habitat=[[-18,-24],[-9,-26],[7,-26],[19,-23]],visit=[-10,-25]),
 dict(theme='溪谷大學校園', loop=[[-17,-15],[17,-15],[17,15],[-17,15]],roads=[[[-17,0],[-3,0]],[[3,0],[17,0]]],
      positions=[[-8,-8],[8,-8],[-9,8],[9,8],[-24,-3],[24,-3],[-8,-23],[8,-23]],
      gardens=[[-7,1],[7,1],[0,17]],civic=[8,-2.3],extent=[37,35],
      paths=[[[0,-26],[0,29]],[[-17,-15],[-17,-20],[17,-20],[17,-15]],[[0,28],[14,29],[22,26]]],
      water=[dict(kind='river',points=[[-31,21],[-20,22],[-10,25],[0,23],[11,24],[22,22],[32,26]],width=2.7)],biome='溪畔柳樹林',habitat=[[-20,28],[-10,30],[12,29],[25,28]],visit=[0,28]),
 dict(theme='林蔭慢行住宅', loop=[[-17,-17],[8,-17],[19,-9],[19,8],[9,17],[-8,18],[-18,9]],roads=[],
      positions=[[-8,-8],[6,-7],[-10,5],[-3,10],[5,9],[12,2],[24,-9],[-24,-12]],
      gardens=[[-7,-1],[9,22],[-22,5]],civic=[6,-1.3],extent=[37,35],
      paths=[[[0,-17],[0,1],[-3,3],[-5,4]],[[-8,18],[-12,23],[-22,24],[-29,18]],[[-18,9],[-23,11],[-29,18]]],
      water=[dict(kind='lake',center=[-22,18],size=[4.7,4.4])],biome='湖畔針闊混合林',habitat=[[-28,7],[-29,13],[-24,27],[-10,28]],visit=[-12,23]),
 dict(theme='濕地創業工坊', loop=[[-18,-16],[11,-16],[13,13],[-18,16]],roads=[[[-18,1],[12,1]]],
      positions=[[-14,-8],[-6,-8],[5,-9],[-12,8],[-4,10],[6,7],[-25,-3],[18,-8]],
      gardens=[[-8,-1],[-22,18],[6,19]],civic=[-6,-2.3],extent=[37,35],
      paths=[[[13,9],[18,13],[22,16],[25,20],[20,25]],[[20,25],[10,27],[4,20],[4,14]]],
      water=[dict(kind='lake',center=[24,19],size=[8,7])],biome='淺水沼澤保育地',habitat=[[18,19],[28,20],[23,26],[29,13]],visit=[20,25])
]
for i,(d,p) in enumerate(zip(districts,plans)):
    d.update({k:v for k,v in p.items() if k!='positions'})
    for j,row in enumerate(d['urban_buildings']):
        row['offset']=p['positions'][j]
        row['max_width']=5.4 if j<2 else 3.5
        row['max_depth']=5.5 if j<2 else 4.3
        row['front']=3.1 if j<2 else 2.45
        row['yaw']=0 if j<2 else (180 if j<6 else (90 if j==6 else -90))
    # Campus buildings sit beside an axial promenade; residential stays low.
    if i in (3,4):
        d['urban_buildings'][0]['asset']='commercial/Models/GLB format/building-'+('l' if i==3 else 'm')+'.glb'
        d['urban_buildings'][0]['height']=4.8
    # No duplicate coordinate signature or loop exists between districts.
for i,j,letter in [(4,0,'b'),(4,2,'f'),(4,3,'a'),(4,4,'c'),(4,5,'d'),(0,3,'e')]:
    row=districts[i]['urban_buildings'][j]
    row.update(asset=f'suburban-edited/house-{letter}-red.glb',height=3.7,max_width=3.5,max_depth=4.3,front=2.5)
assert len({json.dumps(p['positions']) for p in plans})==6
assert len({json.dumps(p['loop'])+json.dumps(p['roads']) for p in plans})==6
for i,y in [(0,-2.6),(1,-3.6),(3,-3.65),(5,-3.6)]: districts[i]['civic'][1]=y
for i,v in {1:[[-23,-10],[-21,20],[7,23]],2:[[-5,4],[7,18],[-22,9]],3:[[-7,18.5],[7,18.5],[22,10]],4:[[-7,-1],[9,22],[-24,5]],5:[[-8,4],[-25,17],[6,19]]}.items(): districts[i]['gardens']=v
districts[0]['urban_buildings'][3]['offset'][0]=-5.6
districts[5]['urban_buildings'][0]['offset'][0]=-12.3
(ROOT/'game/data/districts.json').write_text(json.dumps(districts,ensure_ascii=False,indent=2),encoding='utf8')
print('SIX_AUTHORED_PLANS_OK',backup)
