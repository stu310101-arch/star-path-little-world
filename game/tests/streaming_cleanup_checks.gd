extends SceneTree

const Cleanup = preload("res://tools/streaming_export_cleanup.gd")
var failures: int = 0

func _initialize() -> void:
	var canonical: Node3D = Node3D.new()
	var old: MeshInstance3D = MeshInstance3D.new()
	old.name = "OriginalFacade"
	old.mesh = BoxMesh.new()
	old.visible = false
	old.set_meta("world_architecture_source_preserved", true)
	canonical.add_child(old)
	var door: MeshInstance3D = MeshInstance3D.new()
	door.name = "CurrentlyHiddenInteractiveDoor"
	door.mesh = BoxMesh.new()
	door.visible = false
	canonical.add_child(door)
	var current: MeshInstance3D = MeshInstance3D.new()
	current.name = "VisibleMarkedSource"
	current.mesh = BoxMesh.new()
	current.set_meta("street_furniture_source_preserved", true)
	canonical.add_child(current)
	var copy: Node3D = canonical.duplicate(7) as Node3D
	var cleanup: RefCounted = Cleanup.new()
	cleanup.call("prune_copy", copy)
	check("obsolete hidden export source removed", not copy.has_node("OriginalFacade"))
	check("canonical source preserved", canonical.has_node("OriginalFacade"))
	check("ordinary hidden gameplay node preserved", copy.has_node("CurrentlyHiddenInteractiveDoor"))
	check("visible marked source preserved", copy.has_node("VisibleMarkedSource"))
	check("only obsolete geometry counted", cleanup.get("removed_nodes") == 1 and cleanup.get("removed_triangles") == 12)
	copy.free()
	canonical.free()
	print("STREAMING_CLEANUP_CHECKS failures=", failures)
	quit(0 if failures == 0 else 1)

func check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		push_error(label)
