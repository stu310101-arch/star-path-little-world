class_name PlanetGeometry
extends RefCounted

static func frame(up: Vector3) -> Basis:
	var back: Vector3 = Vector3.BACK.slide(up)
	if back.length_squared() < 0.01:
		back = Vector3.UP.slide(up)
	back = back.normalized()
	return Basis(up.cross(back).normalized(), up, back)

static func surface(up: Vector3, offset: Vector2, radius: float) -> Vector3:
	var axes: Basis = frame(up)
	return (up * radius + axes.x * offset.x + axes.z * offset.y).normalized() * radius

static func ground_probe(space: PhysicsDirectSpaceState3D,normal: Vector3,radius: float) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(normal*(radius+1.4),normal*(radius-.3),1)
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		return hit
	# Float32 concave triangles can reject a ray exactly on a shared edge.
	# Recover only when ALL four points 2 mm around it have real walkable
	# geometry. This cannot bridge a shore, a path edge, or a visible hole.
	var axes: Basis = frame(normal)
	var neighbour: Dictionary = {}
	for direction: Vector3 in [axes.x,-axes.x,axes.z,-axes.z]:
		var n: Vector3 = (normal*radius+direction*.002).normalized()
		query.from=n*(radius+1.4)
		query.to=n*(radius-.3)
		neighbour=space.intersect_ray(query)
		if neighbour.is_empty():
			return {}
	return neighbour

static func material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	if emission > 0.0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = emission
	return result

static func mesh_node(parent: Node3D, node_name: String, mesh: Mesh, mat: Material = null, collision: bool = false) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	if mat != null:
		node.material_override = mat
	parent.add_child(node)
	if collision:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "SurfaceCollision"
		node.add_child(body)
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
	return node

static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var outward: Vector3 = (a + b + c).normalized()
	# Godot front faces use clockwise winding.
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	for point: Vector3 in [a, b, c]:
		st.set_color(color)
		st.set_normal(point.normalized())
		st.add_vertex(point)

static func island(up: Vector3, radius: float, extent: Vector2, seed_value: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = 64
	var rings: int = 16
	for ring: int in range(rings):
		for i: int in range(segments):
			var points: Array[Vector3] = []
			for corner: Vector2i in [Vector2i(ring, i), Vector2i(ring + 1, i), Vector2i(ring + 1, i + 1), Vector2i(ring, i + 1)]:
				var angle: float = TAU * float(corner.y) / float(segments)
				var waviness: float = 1.0 + 0.12 * sin(angle * 3.0 + seed_value) + 0.07 * cos(angle * 5.0 - seed_value)
				var t: float = float(corner.x) / float(rings)
				points.append(surface(up, Vector2(cos(angle), sin(angle)) * extent * t * waviness, radius))
			var shade: float = 0.98 + 0.025 * sin(float(i * 7 + ring * 3))
			triangle(st, points[0], points[1], points[2], Color(shade, shade, shade))
			if ring > 0:
				triangle(st, points[0], points[2], points[3], Color(shade, shade, shade))
	return st.commit()

static func ribbon(a: Vector3, b: Vector3, radius: float, width: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side: Vector3 = a.cross(b).normalized()
	var count: int = ceili(a.angle_to(b) * radius / 0.4)
	var strips: int = maxi(1,ceili(width/0.4))
	for i: int in range(count):
		var n0: Vector3 = a.slerp(b, float(i) / count).normalized()
		var n1: Vector3 = a.slerp(b, float(i + 1) / count).normalized()
		# Subdivide across the width too. A wide chord otherwise sinks below
		# perpendicular sidewalks, exposing triangular patches at intersections.
		for j: int in range(strips):
			var left: float = width*(float(j)/strips-.5)
			var right: float = width*(float(j+1)/strips-.5)
			var p0: Vector3 = (n0 * radius + side * left).normalized() * radius
			var p1: Vector3 = (n0 * radius + side * right).normalized() * radius
			var p2: Vector3 = (n1 * radius + side * right).normalized() * radius
			var p3: Vector3 = (n1 * radius + side * left).normalized() * radius
			triangle(st, p0, p1, p2, Color.WHITE)
			triangle(st, p0, p2, p3, Color.WHITE)
	return st.commit()

static func path_sides(points: Array[Vector3], closed: bool = false) -> Array[Vector3]:
	# A shared miter at each vertex closes the outside of a bend. Independent
	# rectangular ribbons leave a triangular hole even when their centres meet.
	var sides: Array[Vector3] = []
	for i: int in range(points.size()):
		var n: Vector3 = points[i]
		var before: Vector3 = points[(i - 1 + points.size()) % points.size()]
		var after: Vector3 = points[(i + 1) % points.size()]
		var incoming: Vector3 = before.cross(n).normalized()
		var outgoing: Vector3 = n.cross(after).normalized()
		if not closed and i == 0:
			incoming = outgoing
		if not closed and i == points.size() - 1:
			outgoing = incoming
		var bisector: Vector3 = (incoming + outgoing).normalized()
		sides.append(bisector / maxf(bisector.dot(outgoing), 0.25))
	return sides

static func joined_strip(st: SurfaceTool, a: Vector3, b: Vector3, side_a: Vector3, side_b: Vector3, radius: float, width: float, cross_steps: int = 0) -> void:
	var count: int = maxi(1, ceili(a.angle_to(b) * radius / 0.4))
	var strips: int = cross_steps if cross_steps > 0 else maxi(1, ceili(width * maxf(side_a.length(), side_b.length()) / 0.4))
	for i: int in range(count):
		var t0: float = float(i) / count
		var t1: float = float(i + 1) / count
		var n0: Vector3 = a if i == 0 else a.slerp(b, t0).normalized()
		var n1: Vector3 = b if i == count - 1 else a.slerp(b, t1).normalized()
		var s0: Vector3 = side_a if i == 0 else side_a.lerp(side_b, t0)
		var s1: Vector3 = side_b if i == count - 1 else side_a.lerp(side_b, t1)
		for j: int in range(strips):
			var left: float = width * (float(j) / strips - 0.5)
			var right: float = width * (float(j + 1) / strips - 0.5)
			var p0: Vector3 = (n0 * radius + s0 * left).normalized() * radius
			var p1: Vector3 = (n0 * radius + s0 * right).normalized() * radius
			var p2: Vector3 = (n1 * radius + s1 * right).normalized() * radius
			var p3: Vector3 = (n1 * radius + s1 * left).normalized() * radius
			triangle(st, p0, p1, p2, Color.WHITE)
			triangle(st, p0, p2, p3, Color.WHITE)

static func path_ribbon(points: Array[Vector3], radius: float, width: float, closed: bool = false) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: Array[Vector3] = path_sides(points, closed)
	var max_miter: float = 1.0
	for side: Vector3 in sides:
		max_miter = maxf(max_miter,side.length())
	# Identical subdivisions on every shared edge avoid curved T-junction cracks.
	var cross_steps: int = maxi(1,ceili(width*max_miter/.4))
	for i: int in range(points.size() if closed else points.size() - 1):
		var next: int = (i + 1) % points.size()
		joined_strip(st, points[i], points[next], sides[i], sides[next], radius, width,cross_steps)
	return st.commit()

static func own_tree(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		# Bake a standalone editable tree. Retaining imported scene inheritance
		# alongside explicitly owned children can instantiate duplicate/orphan nodes.
		child.scene_file_path = ""
		child.owner = root
		own_tree(child, root)

static func save_scene(node: Node, path: String) -> void:
	own_tree(node, node)
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(node) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
