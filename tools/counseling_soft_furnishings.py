"""Original soft furnishing geometry for the local counseling studio r7.

Call ``add_soft_furnishings(globals())`` after the room's crafted_details().
Remove that function's old FoldedLinenThrow first, retaining the sofa piping.
All coordinates use the generator's Godot Y-up metre convention. The helper
reuses linen/sage/apricot, adds no textures, and creates no floor colliders.

The throw stays on the negative local-X sofa arm. The canvas insert occupies
the reserved lower-left east-wall cubby, supported at Y=.36 m. Neither prop
occupies a seat anchor or the room's walking space. These are design assets;
this module does not run game, route, performance or acceptance tests.
"""
from __future__ import annotations

import math


def _add(a, b):
    return tuple(a[i] + b[i] for i in range(3))


def _sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def _cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def _unit(v):
    length = max(sum(x*x for x in v)**.5, 1e-9)
    return tuple(x/length for x in v)


def _smooth(obj):
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def _bezier(points, t):
    return tuple((1-t)**3*points[0][i] + 3*(1-t)**2*t*points[1][i]
                 + 3*(1-t)*t*t*points[2][i] + t**3*points[3][i] for i in range(2))


def _arm_profile(t):
    # Inner hang, softened arm crest, then a free outer hang with a turned hem.
    # Actual sofa arm is centred X=-1.19, top Y=.83, outer X=-1.30.
    segments = [
        ((-1.005,.610),(-1.010,.690),(-1.035,.735),(-1.048,.770)),
        ((-1.048,.770),(-1.060,.840),(-1.095,.866),(-1.128,.866)),
        ((-1.128,.866),(-1.170,.872),(-1.220,.871),(-1.258,.866)),
        ((-1.258,.866),(-1.300,.862),(-1.330,.833),(-1.329,.782)),
        ((-1.329,.782),(-1.337,.670),(-1.323,.500),(-1.329,.415)),
        ((-1.329,.415),(-1.328,.386),(-1.320,.372),(-1.309,.379)),
    ]
    value = max(0.0, min(1.0, t)) * len(segments)
    index = min(len(segments)-1, int(value))
    return _bezier(segments[index], value-index)


def _throw_point(t, across):
    x, y = _arm_profile(t)
    before = _arm_profile(max(0.0,t-.001))
    after = _arm_profile(min(1.0,t+.001))
    tangent = _unit((after[0]-before[0],after[1]-before[1],0))
    outward = (tangent[1],-tangent[0],0)
    # Unequal, gravity-led folds run down the hanging fabric, rather than a
    # regular corrugated sheet. They relax over the supporting upholstered arm.
    hang = .35 + .65*abs(math.sin(math.pi*(t-.40)))
    wave = (.0075*math.sin(across*math.tau*2.4+.45)
            + .0035*math.sin(across*math.tau*4.7+1.4))*hang
    z = -.29 + across*.54 + .009*math.sin(math.pi*t)*math.sin(across*math.pi)
    return (x+outward[0]*wave, y+outward[1]*wave, z)


def _cloth(api, name, point_at, rows, cols, material, thickness=.005):
    """Explicit front, back and closed border; UVs follow the cloth's length."""
    front = [point_at(row/(rows-1),col/(cols-1))
             for row in range(rows) for col in range(cols)]
    normals = []
    for row in range(rows):
        for col in range(cols):
            longitudinal = _sub(front[min(row+1,rows-1)*cols+col],front[max(row-1,0)*cols+col])
            transverse = _sub(front[row*cols+min(col+1,cols-1)],front[row*cols+max(col-1,0)])
            normals.append(_unit(_cross(longitudinal,transverse)))
    back = [tuple(p[k]-normals[i][k]*thickness for k in range(3)) for i,p in enumerate(front)]
    count = len(front)
    faces = []
    for row in range(rows-1):
        for col in range(cols-1):
            a = row*cols+col
            faces.extend([(a,a+1,a+cols+1,a+cols),
                          (count+a+cols,count+a+cols+1,count+a+1,count+a)])
    border = (list(range(cols)) + [row*cols+cols-1 for row in range(1,rows)]
              + list(range((rows-1)*cols+cols-2,(rows-1)*cols-1,-1))
              + [row*cols for row in range(rows-2,0,-1)])
    for a,b in zip(border,border[1:]+border[:1]):
        faces.append((a,count+a,count+b,b))
    obj = _smooth(api['mesh'](name,front+back,faces,material))
    uv = obj.data.uv_layers.active
    for polygon in obj.data.polygons:
        for loop in polygon.loop_indices:
            vertex = obj.data.loops[loop].vertex_index % count
            uv.data[loop].uv = ((vertex % cols)/(cols-1)*.84,
                               (vertex // cols)/(rows-1)*1.30)
    return obj


def _throw(api):
    with api['frame'](api.get('SOFA_POSITION',(-4.43,0,.35)),-math.pi/2):
        _cloth(api,'R7_ArmDrapedLinenThrow',_throw_point,43,19,'linen')
        # Bound edges are stitched textile, not metallic piping.
        for across in (0.0,1.0):
            api['tube_path']('R7_ThrowLongBoundEdge',
                [_throw_point(i/48,across) for i in range(49)],.0032,'apricot',6)
        for t in (0.0,1.0):
            api['tube_path']('R7_ThrowTurnedHem',
                [_throw_point(t,i/20) for i in range(21)],.0038,'apricot',6)
        # A short return fold makes the textile visibly folded over the arm.
        def folded_point(t, across):
            along = .23+t*.38
            p = _throw_point(along,.06+.88*across)
            before = _throw_point(max(0.0,along-.001),across)
            after = _throw_point(min(1.0,along+.001),across)
            tangent = _unit(_sub(after,before))
            outward = (tangent[1],-tangent[0],0)
            return _add(p,tuple(v*.012 for v in outward))
        _cloth(api,'R7_ThrowReturnedFold',folded_point,15,17,'linen',.004)
        api['tube_path']('R7_ThrowFoldBinding',
            [folded_point(1.0,i/20) for i in range(21)],.0030,'sage',6)
        # Sparse tiny stitches follow the visible terminal hem at real scale.
        for index in range(15):
            a = _throw_point(.982,.045+index*.062)
            b = _throw_point(.982,.068+index*.062)
            api['rod']('R7_ThrowHemStitch',a,b,.0009,'sage',5)


def _rounded_ring(width, depth, radius, y, bulge=0.0):
    points = []
    for cx,cz,start in [(width/2-radius,depth/2-radius,0),
                        (width/2-radius,-depth/2+radius,90),
                        (-width/2+radius,-depth/2+radius,180),
                        (-width/2+radius,depth/2-radius,270)]:
        for index in range(8):
            angle = math.radians(start+index*90/7)
            x,z = cx+math.sin(angle)*radius,cz+math.cos(angle)*radius
            # Small irregular panel give keeps the fabric softer than a drawer.
            x += bulge*math.sin(z*12+.5)*(.5+abs(x)/width)
            z += bulge*.7*math.sin(x*10+1.3)
            points.append((x,y,z))
    return points


def _canvas_insert(api):
    with api['frame']((4.96,0,.70),-math.pi/2):
        with api['frame']((-.82,.36,.025)):
            profiles = [(.520,.282,.025,.000,0),(.536,.300,.030,.120,.003),
                        (.560,.320,.035,.300,.002),(.545,.305,.029,.300,.002),
                        (.522,.286,.024,.120,.002),(.505,.267,.020,.013,0)]
            vertices = []
            for width,depth,radius,y,bulge in profiles:
                vertices.extend(_rounded_ring(width,depth,radius,y,bulge))
            sides = 32
            faces = [tuple(range(sides-1,-1,-1)),tuple(range(5*sides,6*sides))]
            for ring in range(len(profiles)-1):
                for j in range(sides):
                    faces.append((ring*sides+j,ring*sides+(j+1)%sides,
                                  (ring+1)*sides+(j+1)%sides,(ring+1)*sides+j))
            _smooth(api['mesh']('R7_HollowCanvasBookInsert',vertices,faces,'linen'))
            rim = _rounded_ring(.553,.313,.032,.302,.002)
            api['tube_path']('R7_InsertRolledFabricRim',rim+[rim[0]],.004,'sage',6)
            # Actual loop handle, with air behind it, stitched onto the front.
            def handle_point(t, across):
                angle = math.pi*t
                x = -.075+.150*t
                y = .205 + (across-.5)*.035
                z = .164 + .035*math.sin(angle)
                return x,y,z
            _cloth(api,'R7_InsertCanvasLoopHandle',handle_point,17,5,'sage',.003)
            for x in (-.075,.075):
                for y in (.195,.215):
                    api['rod']('R7_InsertHandleAttachmentStitch',(x-.009,y,.168),(x+.009,y,.168),.0009,'apricot',5)
            # Sewn corner channels sit on the cloth wall, not a hard box frame.
            for x in (-.235,.235):
                api['tube_path']('R7_InsertFrontSeam',
                    [(x*.94,.030,.145),(x,.15,.154),(x,.278,.159)],.0012,'sage',6)


def add_soft_furnishings(api):
    """Add sofa throw and reserved wall insert, returning authoring metadata."""
    # api is the actual generator globals dict, so its active collection changes
    # are respected by the existing mesh helper without inventing a new zone.
    api['COL'] = api['COLS']['SharedQuietSeating']
    _throw(api)
    api['COL'] = api['COLS']['OriginalDecor']
    _canvas_insert(api)
    return {
        'revision':'r7-local-design',
        'materials':['linen','sage','apricot'],
        'textures_added':0,
        'colliders_added':0,
        'throw':{'frame_origin':list(api.get('SOFA_POSITION',(-4.43,0,.35))),'frame_yaw':-math.pi/2,
                 'local_bounds_approx':[[-1.35,.37,-.30],[-.99,.90,.27]],
                 'placement':'negative local-X existing sofa arm; seats remain clear'},
        'storage_insert':{'frame_origin':[4.96,0,.70],'frame_yaw':-math.pi/2,
                          'local_center':[-.82,.51,.025],'size':[.56,.30,.32],
                          'support_y':.36,'placement':'reserved lower-left wall cubby'},
        'acceptance':'Not run; local authoring only, per user instruction',
    }
