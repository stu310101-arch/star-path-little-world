extends RefCounted

# These are the actual recessed entrance panels in the supplied Kenney meshes,
# in unscaled model coordinates. They were checked against the source triangles,
# palette colours and front views; the widest dark face is often a wall/window.
# Commercial fronts point toward -Z before the scene builder rotates the visual.
# Each row is: door centre X, door plane Z, panel width, panel height, first-floor Y.
const ENTRANCES: Dictionary = {
	"building-a": [.22179395,-.34999985,.24,.27,.4],
	"building-b": [-.135,.05,.14,.27,.4],
	"building-c": [-.17820606,-.275,.14,.27,.4],
	"building-d": [.2,-.41,.24,.27,.4],
	"building-f": [-.2,-.345,.24,.27,.4],
	"building-g": [-.135,-.399,.24,.27,.4],
	"building-h": [-.17820606,-.3561,.14,.27,.4],
	"building-i": [0.0,-.589,.24,.27,.4],
	"building-j": [.02179394,-.6,.24,.27,.4],
	"building-l": [.065,-.539,.24,.27,.4],
	"building-m": [0.0,-.601,.24,.27,.4],
	"building-n": [.34,-.69,.6,.25,.4],
	"building-skyscraper-a": [0.0,-.5,.14,.27,.4],
	"building-skyscraper-b": [0.0,-.5,.14,.27,.4],
	"building-skyscraper-c": [0.0,-.4461,.24,.27,.4],
	"building-type-k": [.203095,.46,.14,.27,.4],
	"house-a-red": [0.0,.4559,.14,.27,.4],
	"house-b-red": [-.544,.4,.14,.27,.4],
	"house-c-red": [-.0068,.4559,.14,.27,.4],
	"house-d-red": [.1582,.456,.14,.27,.4],
	"house-e-red": [0.0,.456,.14,.27,.4],
	"house-f-red": [.056,.6449,.14,.27,.4],
}
const DOOR_HEIGHT: float = 2.05
const DOOR_MIN_WIDTH: float = .95

# Call on the newly instantiated visual BEFORE scale/position/rotation, tinting
# and collision generation. The imported meshes and GLB files remain untouched.
# X/Z bounds stay fixed. Above the authored first-floor band every point moves
# by the same vertical gain, preserving upper-storey windows and roof geometry.
static func refine(visual: Node3D,source_box: AABB,scale_factor: float,asset_path: String) -> Dictionary:
	var key: String = asset_path.get_file().get_basename()
	if not ENTRANCES.has(key) or scale_factor <= 0.0:
		return {"applied":false,"asset":asset_path,"height":source_box.size.y*scale_factor,"reason":"No audited entrance profile"}
	assert(not visual.has_meta("human_scale_frontage"),"Frontage refinement must only run once per visual")
	var row: Array = ENTRANCES[key]
	var source_height: float = float(row[3])
	var floor_y: float = float(row[4])
	var floor_scale: float = maxf(1.0,DOOR_HEIGHT/(source_height*scale_factor))
	var source_width: float = float(row[2])
	var door_centre: float = float(row[0])
	var target_width: float = maxf(source_width,DOOR_MIN_WIDTH/scale_factor)
	var inner_radius: float = source_width*.5+.03
	var door_factor: float = target_width/source_width
	var target_frame_radius: float = inner_radius*door_factor
	assert(source_box.size.x>target_frame_radius*2.0+.04,"Entrance frame must fit inside the source footprint: "+asset_path)
	# Very narrow shops place the source door close to one side wall. Keep the
	# expanded frame inside that wall with a small local inward correction.
	# The asymmetric transition returns to the original wall/footprint edges.
	var target_centre: float = clampf(door_centre,source_box.position.x+target_frame_radius+.02,source_box.end.x-target_frame_radius-.02)
	var transition_left: float = maxf(source_box.position.x,minf(door_centre-inner_radius-.14,target_centre-target_frame_radius-.06))
	var transition_right: float = minf(source_box.end.x,maxf(door_centre+inner_radius+.14,target_centre+target_frame_radius+.06))
	var profile: Dictionary = {"centre":door_centre,"target_centre":target_centre,"plane":float(row[1]),"width":source_width,"door_height":source_height,"floor":floor_y,"base":source_box.position.y,"floor_scale":floor_scale,"door_factor":door_factor,"inner_radius":inner_radius,"transition_left":transition_left,"transition_right":transition_right}
	var statistics: Dictionary = {"surfaces":0,"triangles_before":0,"triangles_after":0,"vertices":0,"door_before":AABB(),"door_after":AABB(),"door_samples":0}
	refine_node(visual,Transform3D.IDENTITY,profile,statistics)
	var gain: float = (floor_y-source_box.position.y)*(floor_scale-1.0)*scale_factor
	var result: Dictionary = {"applied":true,"asset":asset_path,"height":source_box.size.y*scale_factor+gain,"floor_gain":gain,"floor_boundary_source":floor_y,"source_door_centre":[door_centre,source_box.position.y,float(row[1])],"refined_door_centre":[target_centre,source_box.position.y,float(row[1])],"door_inward_correction":(target_centre-door_centre)*scale_factor,"source_door_size":[source_width,source_height],"source_panel_bounds":box_data(statistics.door_before),"refined_panel_bounds":box_data(statistics.door_after),"door_samples":statistics.door_samples,"door_width":(statistics.door_after as AABB).size.x*scale_factor,"door_height":(statistics.door_after as AABB).size.y*scale_factor,"triangles_before":statistics.triangles_before,"triangles_after":statistics.triangles_after,"surfaces":statistics.surfaces}
	visual.set_meta("human_scale_frontage",result)
	return result

static func box_data(box: AABB) -> Dictionary:
	return {"min":[box.position.x,box.position.y,box.position.z],"size":[box.size.x,box.size.y,box.size.z]}

static func warped(point: Vector3,profile: Dictionary) -> Vector3:
	var result: Vector3 = point
	var dx: float = point.x-float(profile.centre)
	var inner: float = float(profile.inner_radius)
	var left: float = float(profile.transition_left)
	var right: float = float(profile.transition_right)
	var expanded_x: float = float(profile.target_centre)+dx*float(profile.door_factor)
	if dx < -inner:
		expanded_x=lerpf(left,float(profile.target_centre)-inner*float(profile.door_factor),clampf((point.x-left)/(float(profile.centre)-inner-left),0.0,1.0))
	elif dx > inner:
		expanded_x=lerpf(float(profile.target_centre)+inner*float(profile.door_factor),right,clampf((point.x-float(profile.centre)-inner)/(right-float(profile.centre)-inner),0.0,1.0))
	var width_weight: float = 1.0-smoothstep(float(profile.door_height)+.03,float(profile.floor),point.y)
	# Only the original door and its immediate facade bay are widened. Deep
	# recessed doors (building-b) use their real plane, not the roof's AABB.
	width_weight*=1.0-smoothstep(.055,.14,absf(point.z-float(profile.plane)))
	if point.x>left and point.x<right:
		result.x+=(expanded_x-point.x)*width_weight
	var height_above_base: float = maxf(0.0,point.y-float(profile.base))
	var floor_height: float = float(profile.floor)-float(profile.base)
	result.y=point.y+minf(height_above_base,floor_height)*(float(profile.floor_scale)-1.0)
	return result

static func refine_node(node: Node,accumulated: Transform3D,profile: Dictionary,statistics: Dictionary) -> void:
	var spatial: Node3D = node as Node3D
	var transform: Transform3D = accumulated*spatial.transform if spatial!=null else accumulated
	var instance: MeshInstance3D = node as MeshInstance3D
	if instance!=null and instance.mesh!=null:
		var refined: ArrayMesh = ArrayMesh.new()
		refined.resource_name=instance.mesh.resource_name+" HumanScaleGroundFloor"
		var inverse: Transform3D = transform.affine_inverse()
		for surface: int in range(instance.mesh.get_surface_count()):
			assert(instance.mesh.surface_get_primitive_type(surface)==Mesh.PRIMITIVE_TRIANGLES)
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if ids.is_empty():
				for index: int in range(vertices.size()):
					ids.append(index)
			var output: SurfaceTool = SurfaceTool.new()
			output.begin(Mesh.PRIMITIVE_TRIANGLES)
			output.set_material(instance.get_active_material(surface))
			for index: int in range(0,ids.size(),3):
				var triangle: Array[Dictionary] = []
				for corner: int in range(3):
					triangle.append(read_vertex(arrays,ids[index+corner],transform))
				# Walls can span several storeys in the original mesh. Cut at the
				# floor band so interpolation cannot stretch upper-floor triangles.
				var below: Array[Dictionary] = clip_floor(triangle,float(profile.floor),true)
				var above: Array[Dictionary] = clip_floor(triangle,float(profile.floor),false)
				for polygon: Array[Dictionary] in [below,above]:
					for fan: int in range(1,polygon.size()-1):
						var points: Array[Dictionary] = [polygon[0],polygon[fan],polygon[fan+1]]
						for vertex: Dictionary in points:
							emit_vertex(output,vertex,profile,inverse)
						statistics.triangles_after+=1
				statistics.triangles_before+=1
			# Measure actual source panel vertices, rather than reporting the
			# desired parameters as if a real geometry measurement had passed.
			for point: Vector3 in vertices:
				measure_panel(transform*point,profile,statistics)
			output.index()
			output.commit(refined)
			statistics.surfaces+=1
		instance.mesh=refined
		# Existing per-surface material overrides still apply to the same indices.
	for child: Node in node.get_children():
		refine_node(child,transform,profile,statistics)

static func read_vertex(arrays: Array,index: int,transform: Transform3D) -> Dictionary:
	var result: Dictionary = {"position":transform*(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[index]}
	if arrays[Mesh.ARRAY_NORMAL]!=null and (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size()>index:
		result.normal=(transform.basis.inverse().transposed()*(arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[index]).normalized()
	if arrays[Mesh.ARRAY_TEX_UV]!=null and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size()>index:
		result.uv=(arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[index]
	if arrays[Mesh.ARRAY_TEX_UV2]!=null and (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size()>index:
		result.uv2=(arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[index]
	if arrays[Mesh.ARRAY_COLOR]!=null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size()>index:
		result.color=(arrays[Mesh.ARRAY_COLOR] as PackedColorArray)[index]
	if arrays[Mesh.ARRAY_TANGENT]!=null and (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size()>index*4+3:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		result.tangent=Plane((transform.basis*Vector3(tangents[index*4],tangents[index*4+1],tangents[index*4+2])).normalized(),tangents[index*4+3])
	return result

static func interpolated(a: Dictionary,b: Dictionary,weight: float) -> Dictionary:
	var result: Dictionary = {}
	for key: String in a:
		if key=="tangent":
			var first: Plane = a[key]
			var last: Plane = b[key]
			result[key]=Plane(first.normal.lerp(last.normal,weight).normalized(),first.d)
		else:
			result[key]=a[key].lerp(b[key],weight)
	return result

static func clip_floor(points: Array[Dictionary],height: float,below: bool) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	# Coplanar ledges belong to one half only; duplicating them would z-fight.
	var coplanar: bool = true
	for point: Dictionary in points:
		if absf((point.position as Vector3).y-height)>.000001:
			coplanar=false
	if coplanar:
		return points if below else output
	for index: int in range(points.size()):
		var a: Dictionary = points[index]
		var b: Dictionary = points[(index+1)%points.size()]
		var ay: float = (a.position as Vector3).y
		var by: float = (b.position as Vector3).y
		var inside_a: bool = ay<=height if below else ay>=height
		var inside_b: bool = by<=height if below else by>=height
		if inside_a:
			output.append(a)
		if inside_a!=inside_b:
			output.append(interpolated(a,b,(height-ay)/(by-ay)))
	return output

static func emit_vertex(output: SurfaceTool,vertex: Dictionary,profile: Dictionary,inverse: Transform3D) -> void:
	var source: Vector3 = vertex.position
	var point: Vector3 = warped(source,profile)
	var epsilon: float = .0001
	var derivative: Basis = Basis((warped(source+Vector3.RIGHT*epsilon,profile)-point)/epsilon,(warped(source+Vector3.UP*epsilon,profile)-point)/epsilon,(warped(source+Vector3.BACK*epsilon,profile)-point)/epsilon)
	var normal: Vector3 = Vector3.UP
	if vertex.has("normal"):
		normal=(inverse.basis.inverse().transposed()*derivative.inverse().transposed()*(vertex.normal as Vector3)).normalized()
		output.set_normal(normal)
	if vertex.has("uv"):
		output.set_uv(vertex.uv)
	if vertex.has("uv2"):
		output.set_uv2(vertex.uv2)
	if vertex.has("color"):
		output.set_color(vertex.color)
	if vertex.has("tangent"):
		var original: Plane = vertex.tangent
		var tangent: Vector3 = (inverse.basis*derivative*original.normal).normalized()
		tangent=(tangent-normal*normal.dot(tangent)).normalized()
		output.set_tangent(Plane(tangent,original.d))
	output.add_vertex(inverse*point)

static func measure_panel(point: Vector3,profile: Dictionary,statistics: Dictionary) -> void:
	if absf(point.z-float(profile.plane))>.00025 or absf(point.x-float(profile.centre))>float(profile.width)*.5+.00015 or point.y<float(profile.base)-.0001 or point.y>float(profile.door_height)+.0001:
		return
	var modified: Vector3 = warped(point,profile)
	if int(statistics.door_samples)==0:
		statistics.door_before=AABB(point,Vector3.ZERO)
		statistics.door_after=AABB(modified,Vector3.ZERO)
	else:
		statistics.door_before=(statistics.door_before as AABB).expand(point)
		statistics.door_after=(statistics.door_after as AABB).expand(modified)
	statistics.door_samples+=1
