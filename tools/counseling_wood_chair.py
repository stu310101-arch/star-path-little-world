"""Original all-wood desk chair for the counseling studio's Blender generator.

Call build_wood_chair(globals(), name, (x, y, z), angle=0). Construction uses
the generator's Godot Y-up metre coordinates and active collection. The chair
faces local -Z; its pivot is at the floor centre. No colliders or interactions
are created here. Existing joinery PBR maps are reused, without new textures.
"""
from __future__ import annotations

import math


def _smooth(obj):
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def _outline():
    """A rounded, slightly narrower rear seat plan, not a cushion shape."""
    points = []
    width, depth, radius = .480, .454, .065
    for cx, cz, start in [(width/2-radius,depth/2-radius,0),
                          (width/2-radius,-depth/2+radius,90),
                          (-width/2+radius,-depth/2+radius,180),
                          (-width/2+radius,depth/2-radius,270)]:
        for j in range(8):
            a = math.radians(start+j*90/7)
            x, z = cx+math.sin(a)*radius, cz+math.cos(a)*radius
            # A rear taper allows the back legs to meet the saddle cleanly.
            x *= 1-.045*(z/depth+.5)
            points.append((x,z))
    return points


def _seat(api, name):
    outline = _outline()
    profiles = [(.16,.500),(.46,.5005),(.76,.502),(.94,.507),
                (1.0,.505),(1.0,.490),(.97,.477)]
    vertices = [(0,.500,0)]
    for scale, height in profiles:
        vertices += [(x*scale,height,z*scale) for x,z in outline]
    count = len(outline)
    faces = [(0,1+j,1+(j+1)%count) for j in range(count)]
    for ring in range(len(profiles)-1):
        a, b = 1+ring*count, 1+(ring+1)*count
        faces += [(a+j,b+j,b+(j+1)%count,a+(j+1)%count) for j in range(count)]
    bottom = 1+(len(profiles)-1)*count
    faces.append(tuple(bottom+j for j in range(count-1,-1,-1)))
    return _smooth(api['mesh'](name+'_SculptedSolidSeat',vertices,faces,'joinery'))


def _leg(api, name, foot, shoulder):
    # Horizontal end rings keep all four feet exactly on the floor. Rounded
    # lower and upper rings soften the timber rather than using metal ferrules.
    profile = [(0,.016),(.010,.019),(.050,.020),(.410,.025),(.468,.024)]
    sides = 12
    vertices = []
    for y, radius in profile:
        t = y/.468
        x = foot[0]+(shoulder[0]-foot[0])*t
        z = foot[1]+(shoulder[1]-foot[1])*t
        vertices += [(x+radius*math.cos(j*math.tau/sides), y,
                      z+radius*math.sin(j*math.tau/sides)) for j in range(sides)]
    faces = [tuple(range(sides-1,-1,-1))]
    for ring in range(len(profile)-1):
        a,b=ring*sides,(ring+1)*sides
        faces += [(a+j,a+(j+1)%sides,b+(j+1)%sides,b+j) for j in range(sides)]
    faces.append(tuple((len(profile)-1)*sides+j for j in range(sides)))
    return _smooth(api['mesh'](name,vertices,faces,'joinery'))


def _back_rail(api, name):
    """A closed curved timber rail, open beneath and curved toward the sitter."""
    columns, rows = 23, 3
    front = []
    for row in range(rows):
        t=row/(rows-1)
        for col in range(columns):
            u=-1+2*col/(columns-1)
            x=.230*u
            lower=.774-.004*u*u
            upper=.920-.018*u*u
            y=lower+(upper-lower)*t
            z=.235-.055*u*u+.035*t
            front.append((x,y,z))
    vertices=front+[(x,y,z+.026) for x,y,z in front]
    n=len(front)
    faces=[]
    for row in range(rows-1):
        for col in range(columns-1):
            a=row*columns+col
            faces += [(a,a+1,a+columns+1,a+columns),
                      (n+a+columns,n+a+columns+1,n+a+1,n+a)]
    border=(list(range(columns))+[row*columns+columns-1 for row in range(1,rows)]
            +list(range((rows-1)*columns+columns-2,(rows-1)*columns-1,-1))
            +[row*columns for row in range(rows-2,0,-1)])
    faces += [(a,n+a,n+b,b) for a,b in zip(border,border[1:]+border[:1])]
    obj=_smooth(api['mesh'](name+'_CurvedTimberBackRail',vertices,faces,'joinery'))
    api['bevel'](obj,.004,2)
    return obj


def build_wood_chair(api: dict, name: str, p, angle=0):
    """Create one chair; return local design bounds for the parent layout author.

    Sitting surface centre: (0,.50,-.012). Local forward: (0,0,-1).
    Conservative geometry bounds: min(-.25,0,-.265), max(.25,.925,.30).
    Those bounds include feet, rounded seat and curved rear rail, but not a
    player clearance margin. Root owns collision and safe stand-up placement.
    """
    with api['frame'](p,angle):
        _seat(api,name)
        for sx in (-1,1):
            for sz in (-1,1):
                _leg(api,name+('_Left' if sx<0 else '_Right')+('_FrontLeg' if sz<0 else '_RearLeg'),
                     (sx*.224,sz*.242),(sx*.179,sz*.169))
            # Side stretchers meet the splayed legs below the seat apron.
            api['rod'](name+'_SideStretcher',(sx*.205,.195,-.212),
                       (sx*.205,.195,.212),.0105,'joinery',10)
            api['rod'](name+'_SeatSideApron',(sx*.174,.445,-.165),
                       (sx*.174,.445,.165),.019,'joinery',10)
            api['rod'](name+'_BackUpright',(sx*.178,.474,.169),
                       (sx*.191,.806,.223),.014,'joinery',12)
        api['rod'](name+'_FrontStretcher',(-.205,.195,-.212),(.205,.195,-.212),.0105,'joinery',10)
        api['rod'](name+'_RearStretcher',(-.205,.195,.212),(.205,.195,.212),.0105,'joinery',10)
        api['rod'](name+'_FrontSeatApron',(-.174,.445,-.165),(.174,.445,-.165),.019,'joinery',10)
        for x in (-.105,0,.105):
            api['rod'](name+'_TimberBackSpindle',(x,.495,.172),
                       (x,.788,.235-.055*(x/.23)**2),.0095,'joinery',10)
        _back_rail(api,name)
    return {'name':name,'position':list(p),'rotation_y':angle,
            'local_forward':[0,0,-1], 'local_seat_point':[0,.50,-.012],
            'local_bounds_min':[-.25,0,-.265], 'local_bounds_max':[.25,.925,.30],
            'materials':['joinery'],'new_textures':0,
            'colliders_added':0,'seat_anchors_added':0,
            'scope':'Original Blender furniture helper; game validation belongs to the parent integration.'}
