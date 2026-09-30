from pathlib import Path
import numpy as np,json,math
root=Path(__file__).resolve().parents[1]
data=np.load(root/'art/Graduate/animation/jump_physical_cloth.npz')
body=data['body_vertices'][:40]
print('BODY_WORLD_RANGES',body.shape,body.min(axis=(0,1)),body.max(axis=(0,1)))
points=body.reshape(-1,3)[:,[0,2,1]];points[:,2]*=-1
cam=np.array([3.,2.1,6.]);worldup=np.array([0.,1.,0.])
best=[]
for target_y in np.arange(.2,1.31,.05):
    target=np.array([0,target_y,0]);forward=target-cam;forward/=np.linalg.norm(forward)
    right=np.cross(forward,worldup);right/=np.linalg.norm(right)
    up=np.cross(right,forward)
    rel=points-cam;depth=rel@forward;v=rel@up
    for fov in np.arange(30,49,1):
        y=.5-v/(2*depth*np.tan(math.radians(fov/2)))
        # Leave room above hands/hat and above the bottom controls.
        if y.min()>.085 and y.max()<.73:
            best.append((int(fov),round(float(target_y),2),float(y.min()),float(y.max())))
best.sort();print(json.dumps(best[:15],indent=2))
