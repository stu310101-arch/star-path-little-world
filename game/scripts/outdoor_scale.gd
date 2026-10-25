extends RefCounted

# Keep editable geometry and animation metadata in authored metres. Only the
# exported outdoor scene hierarchy is reduced; player and interior nodes never
# pass through these helpers.
static func authored_radius(layout: Dictionary) -> float:
	return float(layout.get("authoring_radius", layout.get("radius", 48.0)))

static func physical_radius(layout: Dictionary) -> float:
	return float(layout.get("physical_radius", layout.get("radius", 48.0)))

static func factor(layout: Dictionary) -> float:
	return float(layout.get("outdoor_scale", physical_radius(layout) / authored_radius(layout)))

static func authoring_layout(raw: Dictionary) -> Dictionary:
	var result: Dictionary = raw.duplicate(true)
	result["physical_radius"] = physical_radius(raw)
	result["radius"] = authored_radius(raw)
	return result

static func authored_to_physical(point: Vector3, layout: Dictionary) -> Vector3:
	return point * factor(layout)

static func apply_to_root(node: Node3D, scale_factor: float) -> void:
	var previous: float = float(node.get_meta("outdoor_scale_applied", 1.0))
	assert(previous > 0.0 and scale_factor > 0.0)
	if not is_equal_approx(previous, scale_factor):
		var conversion: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (scale_factor / previous)), Vector3.ZERO)
		node.transform = conversion * node.transform
	node.set_meta("outdoor_scale_applied", scale_factor)

static func apply_to_children(container: Node3D, scale_factor: float) -> void:
	# world.gd deliberately resets its three top-level containers to identity.
	# Bake beneath those containers so that reset cannot undo outdoor scaling.
	var previous: float = float(container.get_meta("outdoor_children_scale_applied", 1.0))
	assert(previous > 0.0 and scale_factor > 0.0)
	if not is_equal_approx(previous, scale_factor):
		var conversion: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (scale_factor / previous)), Vector3.ZERO)
		for child: Node in container.get_children():
			if child is Node3D:
				(child as Node3D).transform = conversion * (child as Node3D).transform
	container.set_meta("outdoor_children_scale_applied", scale_factor)
