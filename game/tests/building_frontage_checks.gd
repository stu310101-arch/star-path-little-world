extends SceneTree

const Frontage = preload("res://tools/building_frontages.gd")
const SourceProbe = preload("res://tools/probe_building_scale.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var results: Array[Dictionary] = []
	var previews: Array[Dictionary] = []
	var seen: Dictionary = {}
	var probe: SceneTree = SourceProbe.new()
	for district: Dictionary in districts:
		for index: int in range(district.urban_buildings.size()):
			var row: Dictionary = district.urban_buildings[index]
			var asset: String = str(row.asset)
			var packed: PackedScene = load("res://assets/kenney/"+asset) as PackedScene
			var model: Node3D = packed.instantiate() as Node3D
			var original_box: AABB = bounds(model)
			var scale_factor: float = minf(float(row.height)/original_box.size.y,minf(float(row.max_width)/original_box.size.x,float(row.max_depth)/original_box.size.z))
			var original_positions: PackedVector3Array = positions(model)
			var result: Dictionary = Frontage.refine(model,original_box,scale_factor,asset)
			result.station=district.station
			result.index=index
			result.scale_factor=scale_factor
			var refined_box: AABB = bounds(model)
			var refined_positions: PackedVector3Array = positions(model)
			var key: String = asset.get_file().get_basename()
			var profile: Array = Frontage.ENTRANCES[key]
			var target_width: float = maxf(float(profile[2])*scale_factor,Frontage.DOOR_MIN_WIDTH)
			var target_height: float = maxf(float(profile[3])*scale_factor,Frontage.DOOR_HEIGHT)
			var target_centre: float = float(result.refined_door_centre[0])
			var physical_panel: AABB = AABB()
			var sample_count: int = 0
			var corners: Array[bool] = [false,false,false,false]
			for point: Vector3 in refined_positions:
				if absf(point.z-float(profile[1]))>.00025 or absf(point.x-target_centre)>target_width/scale_factor*.5+.0002 or point.y<-.0001 or point.y>target_height/scale_factor+.0002:
					continue
				physical_panel=AABB(point,Vector3.ZERO) if sample_count==0 else physical_panel.expand(point)
				sample_count+=1
				for side: int in range(2):
					for vertical: int in range(2):
						var expected: Vector3 = Vector3(target_centre+(-.5 if side==0 else .5)*target_width/scale_factor,float(vertical)*target_height/scale_factor,float(profile[1]))
						if point.distance_to(expected)<.0004:
							corners[side*2+vertical]=true
			var label: String = str(district.station)+"/"+str(index)+" "+key
			check(bool(result.applied),label+" missing audited profile")
			check(corners.all(func(value: bool) -> bool: return value),label+" missing a measured door-panel corner "+str(corners))
			check(absf(physical_panel.size.x*scale_factor-target_width)<.004,label+" incorrect actual door width")
			check(absf(physical_panel.size.y*scale_factor-target_height)<.004,label+" incorrect actual door height")
			check(absf(refined_box.position.x-original_box.position.x)<.0002 and absf(refined_box.end.x-original_box.end.x)<.0002 and absf(refined_box.position.z-original_box.position.z)<.0002 and absf(refined_box.end.z-original_box.end.z)<.0002,label+" changed building footprint")
			check(absf(refined_box.size.y*scale_factor-float(result.height))<.002,label+" height report differs from real mesh")
			var moved_upper: Dictionary = {}
			for point: Vector3 in refined_positions:
				var bucket: String = point_key(point)
				if not moved_upper.has(bucket):
					moved_upper[bucket]=[]
				(moved_upper[bucket] as Array).append(point)
			var upper_missing: int = 0
			for point: Vector3 in original_positions:
				if point.y>=float(profile[4])-.000001 and not contains_position(moved_upper,point+Vector3.UP*float(result.floor_gain)/scale_factor):
					upper_missing+=1
			check(upper_missing==0,label+" modified upper-storey shape: "+str(upper_missing))
			var fresh: Node3D = packed.instantiate() as Node3D
			check(bounds(fresh).is_equal_approx(original_box),label+" mutated shared source mesh")
			fresh.free()
			result.actual_panel_width=physical_panel.size.x*scale_factor
			result.actual_panel_height=physical_panel.size.y*scale_factor
			result.actual_panel_samples=sample_count
			result.actual_panel_corners=corners
			result.actual_height=refined_box.size.y*scale_factor
			result.upper_vertices_changed=upper_missing
			result.actual_footprint=[refined_box.size.x*scale_factor,refined_box.size.z*scale_factor]
			results.append(result)
			if not seen.has(asset):
				seen[asset]=true
				previews.append({"asset":asset,"size":[refined_box.size.x,refined_box.size.y,refined_box.size.z],"min":[refined_box.position.x,refined_box.position.y,refined_box.position.z],"parts":probe.call("mesh_parts",model),"scale_factor":scale_factor})
			model.free()
	probe.free()
	var output: FileAccess = FileAccess.open("res://../deliverables/building-frontage-geometry-results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"buildings_checked":results.size(),"models_checked":seen.size(),"failures":failures,"results":results},"\t"))
	var preview: FileAccess = FileAccess.open("res://../deliverables/building-frontage-mesh-probe.json",FileAccess.WRITE)
	preview.store_string(JSON.stringify(previews))
	print("BUILDING_FRONTAGE_GEOMETRY ",JSON.stringify({"buildings":results.size(),"models":seen.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func check(condition: bool,message: String) -> void:
	if not condition:
		failures.append(message)

func point_key(point: Vector3) -> String:
	return "%d/%d/%d" % [roundi(point.x*10000),roundi(point.y*10000),roundi(point.z*10000)]

func contains_position(buckets: Dictionary,point: Vector3) -> bool:
	# Imported/rebuilt float32 positions can land on opposite sides of a hash
	# rounding boundary. Compare real distances in the adjacent bins as well.
	for x: int in range(-1,2):
		for y: int in range(-1,2):
			for z: int in range(-1,2):
				var key: String = point_key(point+Vector3(x,y,z)*.0001)
				if buckets.has(key):
					for candidate: Vector3 in buckets[key]:
						if candidate.distance_squared_to(point)<.0000000001:
							return true
	return false

func positions(node: Node,accumulated: Transform3D = Transform3D.IDENTITY) -> PackedVector3Array:
	var transform: Transform3D = accumulated*(node as Node3D).transform if node is Node3D else accumulated
	var output: PackedVector3Array = PackedVector3Array()
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				output.append(transform*point)
	for child: Node in node.get_children():
		output.append_array(positions(child,transform))
	return output

func bounds(node: Node) -> AABB:
	var points: PackedVector3Array = positions(node)
	var result: AABB = AABB(points[0],Vector3.ZERO)
	for point: Vector3 in points:
		result=result.expand(point)
	return result
