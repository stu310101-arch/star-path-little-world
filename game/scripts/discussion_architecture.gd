extends RefCounted
## Four structural connections for the frozen v4 environment export.
## Also authored in discussion_zones/major.py for the next complete asset build.
const NODE_NAME := "SM_Zone_major_RuntimeTrussBrackets"
const RADIUS := 0.065
const SIDES := 8

static func build(art: Node3D, layout: Dictionary) -> MeshInstance3D:
	var existing := art.get_node_or_null(NODE_NAME) as MeshInstance3D
	if existing != null:
		return existing
	# A future full Blender rebuild includes these supports, so never double them.
	if bool(layout.get("architecture", {}).get("major_truss_brackets_baked", false)):
		return null
	var major: Dictionary = {}
	for zone: Dictionary in layout.get("zones", []):
		if str(zone.get("id", "")) == "major":
			major = zone
			break
	if major.is_empty():
		return null
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for pair: Vector2 in [Vector2(-9.65, -9.68), Vector2(3.35, 2.98)]:
		for side: float in [-1.0, 1.0]:
			_append_rod(vertices, normals,
				Vector3(side * 5.0, 3.52, pair.y),
				Vector3(side * 4.94, 4.85, pair.x))
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(Color(0.075, 0.09, 0.095, 1.0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _steel(art))
	var instance := MeshInstance3D.new()
	instance.name = NODE_NAME
	instance.mesh = mesh
	var center: Array = major["center"]
	instance.position = Vector3(float(center[0]), float(center[1]), float(center[2]))
	instance.rotation.y = float(major["rotation_y"])
	instance.visibility_range_end = 55.0
	instance.visibility_range_end_margin = 4.0
	art.add_child(instance)
	return instance

static func _steel(art: Node3D) -> Material:
	for node: Node in art.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for index: int in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(index)
			if material != null and material.resource_name == "MAT_Garden_PaletteMetal":
				return material
	var material := StandardMaterial3D.new()
	material.resource_name = "GardenBracketSteel"
	material.vertex_color_use_as_albedo = true
	material.metallic = 0.74
	material.roughness = 0.38
	return material

static func _append_rod(vertices: Array[Vector3], normals: Array[Vector3], a: Vector3, b: Vector3) -> void:
	var axis := (b - a).normalized()
	var tangent := axis.cross(Vector3.FORWARD).normalized()
	var bitangent := axis.cross(tangent)
	for index: int in range(SIDES):
		var angle := TAU * float(index) / SIDES
		var next_angle := TAU * float(index + 1) / SIDES
		var n0 := tangent * cos(angle) + bitangent * sin(angle)
		var n1 := tangent * cos(next_angle) + bitangent * sin(next_angle)
		var a0 := a + n0 * RADIUS
		var a1 := a + n1 * RADIUS
		var b0 := b + n0 * RADIUS
		var b1 := b + n1 * RADIUS
		# Godot uses clockwise front faces. Cap normals remain flat.
		vertices.append_array([a0, b0, a1, a1, b0, b1, a, a0, a1, b, b1, b0])
		normals.append_array([n0, n0, n1, n1, n0, n1, -axis, -axis, -axis, axis, axis, axis])
