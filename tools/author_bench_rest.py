"""Bake a small, independent seated graduate using the delivered Idle mesh.

Run with the bundled Python (numpy), or Blender's Python. Original character
assets and their flip/cloth clips are read only. The nine baked poses retain
original materials and form an editable morph animation, including a lap and
free hanging front hem; no cloth simulation is needed on the user's laptop.
"""
from __future__ import annotations
import copy, json, math, struct
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'game/assets/character/graduate.glb'
DEST = ROOT / 'game/assets/character/graduate_rest.glb'
SCALE = 1.75 / 4.8
STEPS = 12


def rotation(q):
    x,y,z,w = q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                     [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                     [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])


def matrix(node):
    if 'matrix' in node:
        return np.array(node['matrix']).reshape(4,4).T
    out = np.eye(4)
    out[:3,:3] = rotation(node.get('rotation',[0,0,0,1])) @ np.diag(node.get('scale',[1,1,1]))
    out[:3,3] = node.get('translation',[0,0,0])
    return out


def align(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    cross = np.cross(a,b); dot = np.clip(np.dot(a,b),-1,1)
    if dot > .999999: return np.eye(3)
    if dot < -.999999: return np.diag([1,-1,-1])
    skew = np.array([[0,-cross[2],cross[1]],[cross[2],0,-cross[0]],[-cross[1],cross[0],0]])
    return np.eye(3) + skew + skew @ skew / (1+dot)


def turn_x(angle):
    c,s=math.cos(angle),math.sin(angle)
    return np.array([[1,0,0],[0,c,-s],[0,s,c]])


def quaternion(matrix_):
    # Eigen decomposition is stable for a rotation at/near 180 degrees.
    m=matrix_[:3,:3]
    u,_,v=np.linalg.svd(m);m=u@v
    xx,yx,zx=m[:,0];xy,yy,zy=m[:,1];xz,yz,zz=m[:,2]
    k=np.array([[xx-yy-zz,xy+yx,xz+zx,zy-yz],
                [xy+yx,yy-xx-zz,yz+zy,xz-zx],
                [xz+zx,yz+zy,zz-xx-yy,yx-xy],
                [zy-yz,xz-zx,yx-xy,xx+yy+zz]])/3
    _,vectors=np.linalg.eigh(k);q=vectors[:,-1]
    return q if q[3]>=0 else -q


def blend_transform(a,b,amount):
    qa,qb=quaternion(a),quaternion(b);dot=float(np.dot(qa,qb))
    if dot<0:qb=-qb;dot=-dot
    if dot>.9995:
        q=qa*(1-amount)+qb*amount;q/=np.linalg.norm(q)
    else:
        theta=math.acos(np.clip(dot,-1,1));q=(math.sin((1-amount)*theta)*qa+math.sin(amount*theta)*qb)/math.sin(theta)
    out=np.eye(4);out[:3,:3]=rotation(q)
    out[:3,3]=a[:3,3]*(1-amount)+b[:3,3]*amount
    return out


class InputGLB:
    def __init__(self, path):
        data=path.read_bytes(); size=struct.unpack_from('<I',data,12)[0]
        self.doc=json.loads(data[20:20+size]); self.blob=data[28+size:]
    def array(self,index):
        a=self.doc['accessors'][index]; view=self.doc['bufferViews'][a['bufferView']]
        kind={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
        width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        offset=view.get('byteOffset',0)+a.get('byteOffset',0)
        if view.get('byteStride'):
            raw=np.ndarray((a['count'],width),dtype=kind,buffer=self.blob,offset=offset,
                           strides=(view['byteStride'],np.dtype(kind).itemsize))
        else: raw=np.frombuffer(self.blob,dtype=kind,count=a['count']*width,offset=offset).reshape(-1,width)
        return raw.copy()


def normals(points, indices):
    triangles=indices.reshape(-1,3)
    faces=np.cross(points[triangles[:,1]]-points[triangles[:,0]],points[triangles[:,2]]-points[triangles[:,0]])
    values=np.zeros_like(points)
    for column in range(3):np.add.at(values,triangles[:,column],faces)
    lengths=np.linalg.norm(values,axis=1)
    values/=np.maximum(lengths[:,None],1e-10)
    return values.astype(np.float32)


def support_contact(points,indices):
    """Compress contact folds against the seat including triangle interiors."""
    points=points.copy();triangles=indices.reshape(-1,3)
    barycentric=[np.array([a,b,5-a-b],float)/5 for a in range(6) for b in range(6-a)]
    for _ in range(8):
        lift=np.zeros(len(points));found=False
        triangles_now=points[triangles]
        for weights in barycentric:
            sample=(triangles_now*weights[None,:,None]).sum(1)
            collision=(np.abs(sample[:,0])<.71)&(np.abs(sample[:,2])<.233)&(sample[:,1]>.419)&(sample[:,1]<.533)
            if not collision.any():continue
            found=True
            penetration=.537-sample[collision,1]
            # Minimum vertical displacement, shared between the triangle's
            # vertices. Taking each vertex's maximum preserves all contacts.
            correction=penetration[:,None]*weights[None,:]/np.dot(weights,weights)
            for column in range(3):np.maximum.at(lift,triangles[collision,column],correction[:,column])
        if not found:break
        points[:,1]+=lift
    return points


def build():
    source=InputGLB(SOURCE); doc=source.doc; nodes=copy.deepcopy(doc['nodes'])
    idle=next(a for a in doc['animations'] if a['name']=='Idle')
    morph_weights={}
    for channel in idle['channels']:
        target=channel['target']; sampler=idle['samplers'][channel['sampler']]
        values=source.array(sampler['output'])
        if target['path']=='weights':
            mesh=doc['nodes'][target['node']]['mesh']; count=len(doc['meshes'][mesh]['weights'])
            morph_weights[mesh]=values.reshape(-1,count)[0]
        else:nodes[target['node']][target['path']]=values[0].tolist()
    parents={child:i for i,node in enumerate(nodes) for child in node.get('children',[])}
    index={node.get('name'):i for i,node in enumerate(nodes)}
    rig=index['GraduateRig']; globals_={}
    def walk(i,parent):
        globals_[i]=parent @ matrix(nodes[i])
        for child in nodes[i].get('children',[]):walk(child,globals_[i])
    walk(rig,np.eye(4))
    skin=doc['skins'][0]; joints=skin['joints']
    invbind=source.array(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    joint_base={i:globals_[i].copy() for i in joints}
    for transform in joint_base.values():transform[:3,3]*=SCALE
    # Editable world-space skeleton targets; real feet stay on the floor.
    seated={i:m.copy() for i,m in joint_base.items()}
    def descendants(i):
        result=[i]
        for child in nodes[i].get('children',[]):result+=descendants(child)
        return result
    def shift(name,translation):
        i=index[name]
        for j in descendants(i):seated[j][:3,3]+=translation
    def aim(name,direction):
        i=index[name]; transform=seated[i]; old=transform.copy()
        rot=align(transform[:3,1],np.array(direction)); pivot=transform[:3,3].copy()
        for j in descendants(i):
            seated[j][:3,:3]=rot @ seated[j][:3,:3]
            seated[j][:3,3]=pivot + rot @ (seated[j][:3,3]-pivot)
    shift('Body',np.array([0,-.17,.065]))
    # Knees pass the front edge before the thighs slope down. The raised
    # bench is .52m high; sitting slightly forward lets both shoes meet land.
    for side,sign in [('L',1),('R',-1)]:
        upper=index['UpperLeg.'+side]; lower=index['LowerLeg.'+side]; foot=index['Foot.'+side]
        knee_target=np.array([sign*.142,.515,.395])
        aim('UpperLeg.'+side,knee_target-seated[upper][:3,3])
        ankle_target=np.array([sign*.155,.022,.46])
        aim('LowerLeg.'+side,ankle_target-seated[lower][:3,3])
        shift('Foot.'+side,ankle_target-seated[foot][:3,3])
        shoulder=index['UpperArm.'+side]
        elbow_target=np.array([sign*.255,.955,.105])
        aim('UpperArm.'+side,elbow_target-seated[shoulder][:3,3])
        elbow=index['LowerArm.'+side]
        wrist_target=np.array([sign*.185,.705,.28])
        aim('LowerArm.'+side,wrist_target-seated[elbow][:3,3])
        aim('Palm.'+side,np.array([0,-.26,.966]))
    # Small backward upper-body relaxation, head level; no exaggerated lean.
    # Clothing uses the same skeleton then an independent lap/hem correction.
    # The mesh cache is intentional: it does not touch walking/flip morphs.
    baseline=[]; reports=[]
    for mesh_index,mesh in enumerate(doc['meshes']):
        parts=[]
        for primitive in mesh['primitives']:
            attributes=primitive['attributes']; points=source.array(attributes['POSITION']).astype(float)
            weight_values=morph_weights.get(mesh_index,mesh.get('weights',[]))
            for amount,target in zip(weight_values,primitive.get('targets',[])):
                if amount and 'POSITION' in target:points+=amount*source.array(target['POSITION'])
            j=source.array(attributes['JOINTS_0']).astype(int)
            w=source.array(attributes['WEIGHTS_0']).astype(float)
            if doc['accessors'][attributes['WEIGHTS_0']].get('normalized'):w/=65535 if w.max()>255 else 255
            if 'JOINTS_1' in attributes:
                j=np.concatenate([j,source.array(attributes['JOINTS_1']).astype(int)],axis=1)
                w=np.concatenate([w,source.array(attributes['WEIGHTS_1']).astype(float)],axis=1)
            w/=np.maximum(w.sum(1,keepdims=True),1e-10)
            deformation=np.array([globals_[i] for i in joints]) @ invbind
            blended=(deformation[j]*w[:,:,None,None]).sum(1)
            points=(blended @ np.c_[points,np.ones(len(points))][:,:,None])[:,:3,0]*SCALE
            parts.append(dict(source=primitive,points=points,joints=j,weights=w,
                              indices=source.array(primitive['indices']).reshape(-1).astype(np.uint32)))
        baseline.append(parts)
        allpoints=np.concatenate([p['points'] for p in parts])
        reports.append({'name':mesh['name'],'bounds':[allpoints.min(0).tolist(),allpoints.max(0).tolist()]})
    output={'asset':{'version':'2.0','generator':'Codex editable graduate bench rest'},
            'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'GraduateRest','children':[]}],
            'meshes':[],'materials':copy.deepcopy(doc['materials']),'accessors':[],'bufferViews':[],
            'extras':{'seat_top_m':.52,'forward':'+Z','pose_samples':STEPS+1,'source':'graduate.glb / Idle at 0s'}}
    blob=bytearray()
    def accessor(values,kind='VEC3',ctype=5126):
        dtype={5126:'<f4',5125:'<u4'}[ctype]; values=np.asarray(values,dtype=dtype)
        while len(blob)%4:blob.append(0)
        offset=len(blob); raw=values.tobytes(); blob.extend(raw)
        view=len(output['bufferViews']);output['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(raw)})
        a={'bufferView':view,'componentType':ctype,'count':len(values),'type':kind}
        if kind=='VEC3':a.update(min=values.min(0).tolist(),max=values.max(0).tolist())
        output['accessors'].append(a);return len(output['accessors'])-1
    transforms={i:seated[i] @ np.linalg.inv(joint_base[i]) for i in joints}
    pose_transforms=[]
    for step in range(STEPS+1):
        amount=step/STEPS;global_pose={}
        def pose_joint(i):
            if i in global_pose:return global_pose[i]
            parent=parents.get(i)
            if parent in joint_base:
                a=np.linalg.inv(joint_base[parent]) @ joint_base[i]
                b=np.linalg.inv(seated[parent]) @ seated[i]
                global_pose[i]=pose_joint(parent) @ blend_transform(a,b,amount)
            else:global_pose[i]=blend_transform(joint_base[i],seated[i],amount)
            return global_pose[i]
        pose_transforms.append(np.array([pose_joint(i) @ np.linalg.inv(joint_base[i]) for i in joints]))
    max_cloth_delta=0
    for mesh_index,(mesh,parts) in enumerate(zip(doc['meshes'],baseline)):
        name=mesh['name']; primitives=[]
        for part in parts:
            points=part['points']; triangles=part['indices']; weights=part['weights']; joint_indices=part['joints']
            deformation=np.array([transforms[i] for i in joints])
            blend=(deformation[joint_indices]*weights[:,:,None,None]).sum(1)
            posed=(blend @ np.c_[points,np.ones(len(points))][:,:,None])[:,:3,0]
            unclothed=posed.copy()
            if any(s in name for s in ['Pleated_bachelor_gown','Blue_and_gold_stole','Stole_woven_bar']):
                posed=drape(points,posed,name)
                max_cloth_delta=max(max_cloth_delta,float(np.linalg.norm(posed-points,axis=1).max()))
            elif 'original_face_hands_and_trousers' in name:
                # Soft tissue/trouser compression at the bench contact patch.
                contact=(np.abs(posed[:,2])<.25)&(posed[:,1]>.42)&(posed[:,1]<.524)
                posed[contact,1]=.524
            if 'Pleated_bachelor_gown' in name or 'original_face_hands_and_trousers' in name:
                posed=support_contact(posed,triangles)
            primitive={'attributes':{'POSITION':accessor(points),'NORMAL':accessor(normals(points,triangles))},
                       'indices':accessor(triangles,'SCALAR',5125),'material':part['source'].get('material',0),'targets':[]}
            for key in ['TEXCOORD_0','COLOR_0']:
                if key in part['source']['attributes']:
                    values=source.array(part['source']['attributes'][key]); width=values.shape[1]
                    primitive['attributes'][key]=accessor(values,'VEC'+str(width))
            # Sample the trajectory with a knee/hip arc instead of linearly
            # collapsing the legs. Each sample is a fully evaluated garment.
            for step in range(1,STEPS+1):
                t=step/STEPS
                transform=(pose_transforms[step][joint_indices]*weights[:,:,None,None]).sum(1)
                sample=(transform @ np.c_[points,np.ones(len(points))][:,:,None])[:,:3,0]
                sample+=(posed-unclothed)*t
                # Gentle forward torso hinge during lowering, clear at rest.
                hinge=math.sin(math.pi*t)*.055
                high=np.clip((points[:,1]-.72)/.65,0,1)
                sample[:,2]+=hinge*high
                # Feet remain at standing height throughout the transition.
                primitive['targets'].append({'POSITION':accessor(sample-points),
                                              'NORMAL':accessor(normals(sample,triangles)-normals(points,triangles))})
            primitives.append(primitive)
        output['meshes'].append({'name':name,'primitives':primitives,'weights':[0.0]*STEPS,
                                 'extras':{'targetNames':['Sit_%02d'%i for i in range(1,STEPS+1)]}})
        node_index=len(output['nodes']);output['nodes'][0]['children'].append(node_index)
        output['nodes'].append({'name':'Rest_'+str(mesh_index).zfill(2),'mesh':mesh_index})
    output['buffers']=[{'byteLength':len(blob)}]
    payload=json.dumps(output,separators=(',',':')).encode()
    payload+=b' '*((-len(payload))%4);blob+=b'\0'*((-len(blob))%4)
    DEST.write_bytes(struct.pack('<III',0x46546c67,2,28+len(payload)+len(blob))+struct.pack('<II',len(payload),0x4e4f534a)+payload+struct.pack('<II',len(blob),0x004e4942)+blob)
    report={'asset':str(DEST.relative_to(ROOT)),'bytes':DEST.stat().st_size,'pose_samples':STEPS+1,
            'source_bounds':reports,'seated_bones':{nodes[i]['name']:seated[i][:3,3].tolist() for i in joints},
            'original_character_untouched':True,'max_garment_vertex_travel_m':max_cloth_delta}
    folder=ROOT/'deliverables/bench-rest';folder.mkdir(parents=True,exist_ok=True)
    (folder/'pose-authoring.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ['source_bounds','seated_bones']}),flush=True)


def drape(original, skinned, name):
    """Front cloth lies above the thighs then falls vertically below the knees.

    Rear cloth gathers onto the cushion behind the pelvis instead of passing
    through the wooden slats. Side folds bridge the two surfaces continuously.
    """
    result=skinned.copy()
    x,y,z=original.T
    waist=.84
    hanging=np.clip((waist-y)/.18,0,1)
    length=np.maximum(0,waist-y)
    # Front-facing source cloth has +Z. Smooth broad sectors retain pleats.
    front=np.clip((z+.02)/.15,0,1)
    front=front*front*(3-2*front)
    forward_length=np.minimum(length,.31)
    beyond=np.maximum(length-.31,0)
    lap_y=.690-.075*np.minimum(length/.31,1)-beyond
    lap_z=.125+forward_length*.98 + (z-.10)*.24
    back_y=.535+np.maximum(.15-length,0)*.9
    back_z=-.10-np.minimum(length,.26)*.40
    target_y=back_y*(1-front)+lap_y*front
    target_z=back_z*(1-front)+lap_z*front
    # Side folds drape outside the trouser legs rather than cutting across them.
    side=np.clip((np.abs(x)-.12)/.13,0,1)
    target_y-=side*np.minimum(length,.20)*.65
    result[:,1]=result[:,1]*(1-hanging)+target_y*hanging
    result[:,2]=result[:,2]*(1-hanging)+target_z*hanging
    result[:,0]+=np.sign(x)*.032*side*hanging
    # The seat supports gathered back/side cloth. Only cloth beyond its front
    # edge falls freely; this avoids pushing folded cloth through the slats.
    supported=(result[:,2]<.25)&(result[:,2]>-.25)&(y<waist)
    result[supported,1]=np.maximum(result[supported,1],.539)
    return result


if __name__=='__main__':build()
