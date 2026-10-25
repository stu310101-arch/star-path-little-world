extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const OutdoorScale = preload("res://scripts/outdoor_scale.gd")
const OUTPUT: String = "res://data/minimap_geometry.json"

func encode(points: PackedVector3Array) -> Array:
	var result: Array = []
	for point: Vector3 in points:
		result.append([point.x, point.y, point.z])
	return result

func build() -> bool:
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var layout: Dictionary = OutdoorScale.authoring_layout(JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary)
	var result: Dictionary = {"version": 1, "source": "Generated district foundation meshes and marina map_polygons; normalized planet coordinates.", "districts_sha256": FileAccess.get_sha256("res://data/districts.json"), "layout_sha256": FileAccess.get_sha256("res://data/world_layout.json"), "radius": float(layout.radius), "districts": {}, "platforms": []}
	var count: int = 0
	for index: int in range(districts.size()):
		var row: Dictionary = districts[index]
		var source: String = "res://generated/districts/" + str(row.station) + ".tscn"
		var district: Node3D = (load(source) as PackedScene).instantiate() as Node3D
		var normal: Array = layout.stations[index].normal
		var up: Vector3 = Vector3(normal[0], normal[1], normal[2])
		var buildings: Array = []
		var used: Array[Node] = []
		for spec: Dictionary in row.urban_buildings:
			var target: Vector3 = Geo.surface(up, Vector2(spec.offset[0], spec.offset[1]), float(layout.radius)).normalized()
			var nearest: Node3D
			var distance: float = INF
			for child: Node in district.get_children():
				if child in used or not child is Node3D or not child.has_node("Foundation"):
					continue
				var candidate: Node3D = child as Node3D
				var error: float = candidate.position.normalized().distance_to(target)
				if error < distance:
					distance = error
					nearest = candidate
			assert(nearest != null and distance < .0001, "Missing actual foundation for " + str(row.station) + " " + str(spec.offset))
			used.append(nearest)
			var foundation: MeshInstance3D = nearest.get_node("Foundation") as MeshInstance3D
			var bounds: AABB = foundation.mesh.get_aabb()
			var transform: Transform3D = district.transform * nearest.transform * foundation.transform
			var corners: Array[Vector3] = [Vector3(bounds.position.x, bounds.end.y, bounds.position.z), Vector3(bounds.end.x, bounds.end.y, bounds.position.z), Vector3(bounds.end.x, bounds.end.y, bounds.end.z), Vector3(bounds.position.x, bounds.end.y, bounds.end.z)]
			var footprint: PackedVector3Array = PackedVector3Array()
			for edge: int in range(4):
				var a: Vector3 = transform * corners[edge]
				var b: Vector3 = transform * corners[(edge + 1) % 4]
				var steps: int = maxi(1, ceili(a.distance_to(b) / .8))
				for step: int in range(steps):
					footprint.append(a.lerp(b, float(step) / steps).normalized())
			buildings.append({"asset": str(spec.asset), "offset": spec.offset, "points": encode(footprint)})
			count += 1
		var marina: Node3D = district.get_node_or_null("Marina") as Node3D
		if marina != null:
			for polygon: PackedVector3Array in marina.get_meta("map_polygons", []):
				result.platforms.append(encode(polygon))
		result.districts[str(row.station)] = {"source": source, "buildings": buildings}
		district.free()
	var output: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	output.store_string(JSON.stringify(result))
	output.close()
	print("MINIMAP_GEOMETRY_BAKED buildings=", count, " platforms=", result.platforms.size())
	return true
