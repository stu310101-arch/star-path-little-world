extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const OUTPUT: String = "res://../deliverables/water-ecology/checks.json"
const WATER_HEIGHT: float = .055
const SAMPLE_STEP: float = .25
const SAMPLE_DURATION: float = 120.0
const FISH_VERTEX_DROP: float = .14
const FISH_TAIL_SWAY: float = .045

var checks: Array[Dictionary] = []
var failures: int = 0
var district_results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"test":label,"passed":passed,"detail":detail})
	if not passed:
		failures+=1
		push_error(label+": "+str(detail))

func finite_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite()

func local_point(position: Vector3, up: Vector3, radius: float) -> Vector2:
	var axes: Basis=Geo.frame(up)
	return Vector2(position.dot(axes.x),position.dot(axes.z))*radius/position.dot(up)

func no_collision_below(node: Node) -> bool:
	return not (node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D) and node.find_children("*","CollisionObject3D",true,false).is_empty() and node.find_children("*","CollisionShape3D",true,false).is_empty() and node.find_children("*","CollisionPolygon3D",true,false).is_empty()

func fish_bounds(fish: Node3D) -> Dictionary:
	var points: PackedVector3Array=[]
	var shaders_correct: bool=true
	var meshes: int=0
	for child: Node in fish.find_children("*","MeshInstance3D",true,false):
		var mesh: MeshInstance3D=child as MeshInstance3D
		if mesh==null or mesh.mesh==null:
			continue
		meshes+=1
		for surface_index: int in range(mesh.mesh.get_surface_count()):
			var material: ShaderMaterial=mesh.get_active_material(surface_index) as ShaderMaterial
			shaders_correct=shaders_correct and material!=null and material.shader!=null and material.shader.resource_path=="res://shaders/lake_fish.gdshader"
		var relative: Transform3D=fish.global_transform.affine_inverse()*mesh.global_transform
		var bounds: AABB=mesh.mesh.get_aabb()
		# A deformed vertex remains inside this expanded box for every tail phase.
		# Testing its corners gives a conservative upper radius for the whole mesh,
		# including the shader's local Y drop and the maximum lateral tail stroke.
		for corner: int in range(8):
			for sway: float in [-FISH_TAIL_SWAY,FISH_TAIL_SWAY]:
				var vertex: Vector3=bounds.get_endpoint(corner)+Vector3(sway,-FISH_VERTEX_DROP,0.0)
				points.append(relative*vertex)
	return {"points":points,"shaders_correct":shaders_correct,"meshes":meshes}

func check_ocean_geometry(ocean: MeshInstance3D, plan: Dictionary, layout: Dictionary, districts: Array, radius: float) -> void:
	var mesh: ArrayMesh=ocean.mesh as ArrayMesh
	check("Freshwater openings use an actual ocean ArrayMesh",mesh!=null)
	if mesh==null:
		return
	var body: StaticBody3D=StaticBody3D.new()
	body.name="WaterChecksOnlyOceanCollision"
	body.collision_layer=16
	body.collision_mask=0
	var collision: CollisionShape3D=CollisionShape3D.new()
	collision.shape=mesh.create_trimesh_shape()
	check("Ocean mesh produces test collision geometry",collision.shape!=null)
	if collision.shape==null:
		collision.free()
		body.free()
		return
	body.add_child(collision)
	ocean.add_child(body)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D=ocean.get_world_3d().direct_space_state
	# A surviving ocean triangle must be hittable. Without this positive control,
	# an unregistered/empty test collider would falsely pass every hole probe.
	var faces: PackedVector3Array=mesh.get_faces()
	var positive_hit: bool=false
	for face: int in range(0,mini(faces.size()-2,300),3):
		var a: Vector3=ocean.global_transform*faces[face]
		var b: Vector3=ocean.global_transform*faces[face+1]
		var c: Vector3=ocean.global_transform*faces[face+2]
		if (b-a).cross(c-a).length_squared()<.000001:
			continue
		var normal: Vector3=((a+b+c)/3.0).normalized()
		var query: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(normal*(radius+1.0),normal*(radius-.3),16)
		query.hit_back_faces=true
		var hit: Dictionary=space.intersect_ray(query)
		positive_hit=not hit.is_empty() and hit.get("collider")==body
		if positive_hit:
			break
	check("Test collider detects surviving opaque ocean triangles",positive_hit)
	for index: int in range(districts.size()):
		var station: String=str(districts[index].station)
		var settings: Dictionary={}
		for row: Dictionary in plan.get("districts",[]):
			if str(row.station)==station:
				settings=row
				break
		var normal: Array=layout.stations[index].normal
		var up: Vector3=Vector3(normal[0],normal[1],normal[2])
		var probes: int=0
		var occluded: int=0
		var first_hit: Array=[]
		for path: Dictionary in settings.get("fish_paths",[]):
			var center: Vector2=Vector2(path.center[0],path.center[1])
			var a: Vector2=Vector2(path.axes[0][0],path.axes[0][1])
			var b: Vector2=Vector2(path.axes[1][0],path.axes[1][1])
			for sample: int in range(24):
				var angle: float=TAU*float(sample)/24.0
				var point: Vector2=center+a*cos(angle)+b*sin(angle)
				var direction: Vector3=Geo.surface(up,point,radius).normalized()
				var query: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(direction*(radius+1.0),direction*(radius-.3),16)
				query.hit_back_faces=true
				var hit: Dictionary=space.intersect_ray(query)
				probes+=1
				if not hit.is_empty():
					occluded+=1
					if first_hit.is_empty():
						first_hit=[point.x,point.y]
		check("Opaque ocean mesh is absent beneath every fish route: "+station,probes>0 and occluded==0,{"ray_probes":probes,"occluded":occluded,"first_hit":first_hit})
	ocean.remove_child(body)
	body.free()
	await physics_frame

func run_checks() -> void:
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/water_ecology.json")) as Dictionary
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var districts: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var radius: float=float(layout.radius)
	check("Water ecology plan covers six districts",plan.get("districts",[]).size()==6 and districts.size()==6)
	check("Water height matches the authored surface",is_equal_approx(float(plan.get("water_height",WATER_HEIGHT)),WATER_HEIGHT))
	var packed: PackedScene=load("res://generated/globe.tscn") as PackedScene
	if packed==null:
		check("Generated globe loads",false)
		finish()
		return
	var globe: Node3D=packed.instantiate() as Node3D
	root.add_child(globe)
	current_scene=globe
	await physics_frame
	await physics_frame
	var ocean: MeshInstance3D=globe.get_node_or_null("Ocean") as MeshInstance3D
	var ocean_material: ShaderMaterial=ocean.material_override as ShaderMaterial if ocean!=null else null
	var geometric_openings: bool=ocean!=null and bool(ocean.get_meta("freshwater_openings",false))
	var shader_openings: bool=not geometric_openings and ocean_material!=null and bool(ocean_material.get_shader_parameter("freshwater_cutouts_enabled"))
	check("Ocean provides freshwater openings",geometric_openings or shader_openings)
	if geometric_openings:
		check("Geometry openings use the inexpensive ocean shader",ocean_material!=null and ocean_material.shader!=null and not ocean_material.shader.code.contains("over_freshwater("))
		await check_ocean_geometry(ocean,plan,layout,districts,radius)
	elif shader_openings:
		var ups: PackedVector3Array=ocean_material.get_shader_parameter("district_ups")
		var extents: PackedVector2Array=ocean_material.get_shader_parameter("district_extents")
		var shapes: PackedVector4Array=ocean_material.get_shader_parameter("lake_shapes")
		var river_spans: PackedVector4Array=ocean_material.get_shader_parameter("river_spans")
		var river_owners: PackedInt32Array=ocean_material.get_shader_parameter("river_districts")
		var cutouts_match: bool=ups.size()==6 and extents.size()==6 and shapes.size()==6
		var expected_rivers: int=0
		if cutouts_match:
			for index: int in range(districts.size()):
				var normal: Array=layout.stations[index].normal
				var data: Dictionary=districts[index]
				var water: Dictionary=data.water[0]
				cutouts_match=cutouts_match and ups[index].is_equal_approx(Vector3(normal[0],normal[1],normal[2])) and extents[index].is_equal_approx(Vector2(data.extent[0],data.extent[1]))
				if str(water.kind)=="lake":
					cutouts_match=cutouts_match and shapes[index].is_equal_approx(Vector4(water.center[0],water.center[1],water.size[0],water.size[1]))
				else:
					cutouts_match=cutouts_match and is_equal_approx(shapes[index].w,float(water.width))
					for segment: int in range(water.points.size()-1):
						if expected_rivers>=river_spans.size() or expected_rivers>=river_owners.size():
							cutouts_match=false
						else:
							var expected: Vector4=Vector4(water.points[segment][0],water.points[segment][1],water.points[segment+1][0],water.points[segment+1][1])
							cutouts_match=cutouts_match and river_spans[expected_rivers].is_equal_approx(expected) and river_owners[expected_rivers]==index
						expected_rivers+=1
		check("Ocean cutouts match all six actual water contours",cutouts_match and int(ocean_material.get_shader_parameter("river_count"))==expected_rivers)
		check("Ocean shader applies its cutout test",ocean_material.shader!=null and ocean_material.shader.code.contains("over_freshwater(world_point)"))
	for index: int in range(districts.size()):
		var data: Dictionary=districts[index]
		var station: String=str(data.station)
		var settings: Dictionary={}
		for row: Dictionary in plan.get("districts",[]):
			if str(row.station)==station:
				settings=row
				break
		check("Authored habitat plan: "+station,not settings.is_empty())
		if settings.is_empty():
			continue
		var reserve: Node3D=globe.get_node_or_null("EcologicalReserves/Reserve_"+station) as Node3D
		var habitat: Node3D=reserve.get_node_or_null("AquaticHabitat") as Node3D if reserve!=null else null
		check("Generated aquatic habitat: "+station,habitat!=null and habitat.has_method("update_life"))
		if habitat==null:
			continue
		habitat.set_process(false)
		var normal: Array=layout.stations[index].normal
		var up: Vector3=Vector3(normal[0],normal[1],normal[2])
		var bed: MeshInstance3D=reserve.get_node_or_null("ShallowWaterBed") as MeshInstance3D
		var water: MeshInstance3D=reserve.get_node_or_null("FreshwaterContours") as MeshInstance3D
		check("Bed and water remain visual geometry: "+station,bed!=null and water!=null and no_collision_below(bed) and no_collision_below(water) and no_collision_below(habitat))
		var water_material: ShaderMaterial=water.material_override as ShaderMaterial if water!=null else null
		check("Translucent freshwater shader: "+station,water_material!=null and water_material.shader!=null and water_material.shader.resource_path=="res://shaders/lake_water.gdshader" and water_material.shader.code.contains("ALPHA="))
		var bed_submerged: bool=bed!=null and bed.mesh!=null
		if bed_submerged:
			var bed_vertices: PackedVector3Array=bed.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			bed_submerged=not bed_vertices.is_empty()
			for vertex: Vector3 in bed_vertices:
				bed_submerged=bed_submerged and vertex.is_finite() and (bed.global_transform*vertex).length()<radius+WATER_HEIGHT
		check("Visible bed stays beneath its surface: "+station,bed_submerged)
		var expected_counts: Dictionary={}
		for plant: Dictionary in settings.plants:
			var kind: String=str(plant.kind)
			expected_counts[kind]=int(expected_counts.get(kind,0))+1
		var found_kinds: Dictionary={}
		var batches: int=0
		var placements_restored: bool=true
		var swimmers: Array[Dictionary]=[]
		var fish_materials_correct: bool=true
		for child: Node in habitat.get_children():
			if child is MultiMeshInstance3D:
				var batch: MultiMeshInstance3D=child as MultiMeshInstance3D
				var kind: String=str(batch.get_meta("aquatic_kind",""))
				var placements: Array=batch.get_meta("placements",[])
				batches+=1
				found_kinds[kind]=true
				placements_restored=placements_restored and not placements.is_empty() and placements.size()==int(expected_counts.get(kind,-1)) and batch.multimesh!=null and batch.multimesh.mesh!=null and batch.multimesh.instance_count==placements.size() and batch.get_script()!=null and (batch.get_script() as Script).resource_path=="res://scripts/ecology_instances.gd"
				for placement: Transform3D in placements:
					placements_restored=placements_restored and finite_transform(placement) and absf(placement.basis.determinant())>.00001
			elif child.has_meta("swim_path"):
				var fish: Node3D=child as Node3D
				var bounds: Dictionary=fish_bounds(fish)
				fish_materials_correct=fish_materials_correct and bool(bounds.shaders_correct) and int(bounds.meshes)>0
				swimmers.append({"node":fish,"bounds":bounds.points,"initial":fish.global_position,"previous":fish.global_position,"travel":0.0,"excursion":0.0})
		check("All authored plant batches restore placements: "+station,batches>0 and placements_restored and found_kinds.size()==expected_counts.size(),{"batches":batches,"kinds":found_kinds.size(),"clusters":settings.plants.size()})
		check("Fish models restore with underwater materials: "+station,not swimmers.is_empty() and swimmers.size()==settings.fish_paths.size()*3 and fish_materials_correct,swimmers.size())
		var review: Dictionary=settings.get("review",{}) as Dictionary
		var review_dry: bool=review.has("point")
		if review_dry:
			var point: Vector2=Vector2(review.point[0],review.point[1])
			var arrival: Vector3=Geo.surface(up,point,radius).normalized()
			review_dry=Waterfront.water_distance(point,data)>0.0 and not Geo.ground_probe(globe.get_world_3d().direct_space_state,arrival,radius).is_empty()
		check("Review arrival has actual dry ground: "+station,review_dry,review.get("point",[]))
		var finite: bool=true
		var wet: bool=true
		var underwater: bool=true
		var facing: bool=true
		var highest_radius: float=0.0
		var nearest_water_edge: float=-INF
		var least_alignment: float=1.0
		for step: int in range(int(SAMPLE_DURATION/SAMPLE_STEP)+1):
			habitat.call("update_life",float(step)*SAMPLE_STEP)
			for swimmer: Dictionary in swimmers:
				var fish: Node3D=swimmer.node as Node3D
				var transform: Transform3D=fish.global_transform
				finite=finite and finite_transform(transform) and absf(transform.basis.determinant())>.00001
				if not finite_transform(transform):
					continue
				var water_distance: float=Waterfront.water_distance(local_point(transform.origin,up,radius),data)
				nearest_water_edge=maxf(nearest_water_edge,water_distance)
				wet=wet and water_distance<0.0
				for corner: Vector3 in swimmer.bounds:
					var world_corner: Vector3=transform*corner
					highest_radius=maxf(highest_radius,world_corner.length())
					underwater=underwater and world_corner.length()<=radius+WATER_HEIGHT+.0001
					wet=wet and Waterfront.water_distance(local_point(world_corner,up,radius),data)<0.0
				var displacement: Vector3=transform.origin-(swimmer.previous as Vector3)
				if step>0 and displacement.length()>.00001:
					var alignment: float=transform.basis.z.normalized().dot(displacement.normalized())
					least_alignment=minf(least_alignment,alignment)
					facing=facing and alignment>.90 and transform.basis.y.normalized().dot(transform.origin.normalized())>.995
				swimmer.travel=float(swimmer.travel)+displacement.length()
				swimmer.excursion=maxf(float(swimmer.excursion),transform.origin.distance_to(swimmer.initial as Vector3))
				swimmer.previous=transform.origin
		var moving: bool=not swimmers.is_empty()
		var least_travel: float=INF
		var least_excursion: float=INF
		for swimmer: Dictionary in swimmers:
			least_travel=minf(least_travel,float(swimmer.travel))
			least_excursion=minf(least_excursion,float(swimmer.excursion))
			moving=moving and float(swimmer.travel)>1.0 and float(swimmer.excursion)>.3
		check("Fish transforms stay finite for 120 seconds: "+station,finite)
		check("Fish and mesh bounds remain inside real water: "+station,wet)
		check("Whole deformed fish remain below water for 120 seconds: "+station,underwater,{"highest_mesh_bound":highest_radius-radius,"surface":WATER_HEIGHT})
		check("Fish face their actual swimming direction: "+station,facing,least_alignment)
		check("Every fish actually travels: "+station,moving,{"minimum_travel":least_travel if is_finite(least_travel) else 0.0,"minimum_excursion":least_excursion if is_finite(least_excursion) else 0.0})
		district_results.append({"station":station,"plant_clusters":settings.plants.size(),"plant_batches":batches,"fish":swimmers.size(),"minimum_water_margin":-nearest_water_edge if is_finite(nearest_water_edge) else 0.0,"minimum_surface_clearance":radius+WATER_HEIGHT-highest_radius,"minimum_heading_alignment":least_alignment,"minimum_travel":least_travel if is_finite(least_travel) else 0.0})
	globe.free()
	finish()

func finish() -> void:
	var result: Dictionary={"passed":failures==0,"failed":failures,"checks_count":checks.size(),"simulation_seconds":SAMPLE_DURATION,"sample_step_seconds":SAMPLE_STEP,"mesh_envelope":"All mesh AABB corners include shader Y -= 0.14 and maximum X tail stroke +/- 0.045","districts":district_results,"checks":checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file: FileAccess=FileAccess.open(OUTPUT,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(result,"\t"))
		file.close()
	else:
		push_error("Could not write "+OUTPUT)
		failures+=1
	print(JSON.stringify({"passed":failures==0,"failed":failures,"checks":checks.size(),"districts":district_results,"output":OUTPUT}))
	quit(0 if failures==0 else 1)
