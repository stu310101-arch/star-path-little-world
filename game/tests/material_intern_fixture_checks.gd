extends SceneTree

const Fixture = preload("res://tests/material_intern_fixture.gd")
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func visual(parent: Node, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = BoxMesh.new()
	node.material_override = material
	parent.add_child(node)
	return node

func run() -> void:
	var tree: Node3D = Node3D.new()
	var fixture: RefCounted = Fixture.new()
	var original: StandardMaterial3D = StandardMaterial3D.new()
	original.resource_name = "Diagnostic fixture material"
	original.roughness = .63
	var same: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	var a: MeshInstance3D = visual(tree, original)
	var b: MeshInstance3D = visual(tree, same)
	var different: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	different.roughness = .63001
	var c: MeshInstance3D = visual(tree, different)
	var local: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	local.resource_local_to_scene = true
	var local_node: MeshInstance3D = visual(tree, local)
	var alpha: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	alpha.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var alpha_node: MeshInstance3D = visual(tree, alpha)
	var overlay_node: MeshInstance3D = visual(tree, same)
	overlay_node.material_overlay = original
	var linked: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	linked.next_pass = original
	var linked_node: MeshInstance3D = visual(tree, linked)
	var old_surface: StandardMaterial3D = StandardMaterial3D.new()
	b.set_surface_override_material(0, old_surface)
	var mesh: Mesh = b.mesh
	var old_vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var scripted: Node3D = Node3D.new()
	var script: GDScript = GDScript.new()
	script.source_code = "extends Node3D\n"
	check(script.reload() == OK, "script fixture compiles")
	scripted.set_script(script)
	tree.add_child(scripted)
	var scripted_node: MeshInstance3D = visual(scripted, same)
	var hidden: Node3D = Node3D.new()
	hidden.visible = false
	tree.add_child(hidden)
	var hidden_node: MeshInstance3D = visual(hidden, same)
	var stats: Dictionary = fixture.apply(tree)
	check(a.get_active_material(0) == original and b.get_active_material(0) == original, "identical full properties share identity")
	check(b.material_override == null and b.get_surface_override_material(0) == original, "only geometry overrides change")
	check(c.get_active_material(0) == different, "a small float difference remains distinct")
	check(local_node.material_override == local, "local-to-scene material stays independent")
	check(alpha_node.material_override == alpha, "transparent material is skipped")
	check(overlay_node.material_override == same and overlay_node.material_overlay == original, "overlay geometry is skipped")
	check(linked_node.material_override == linked, "next-pass material is skipped")
	check(scripted_node.material_override == same and hidden_node.material_override == same, "scripted and hidden branches skipped")
	check(b.mesh == mesh and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == old_vertices, "mesh and geometry bytes untouched")
	check(stats.redundant_material_identities == 1 and stats.changed_meshes == 1, "one identity duplicate is measured")
	var restored: Dictionary = fixture.restore()
	check(b.material_override == same and b.get_surface_override_material(0) == old_surface, "original override hierarchy restored")
	check(restored.restored_meshes == 1 and restored.pending_restore_meshes == 0, "all changed geometry restored")
	check(fixture.stats().pending_restore_meshes == 0, "fixture can be reused after restore")
	# Resource-valued metadata is compared by object identity, including nesting.
	var meta_a: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	var meta_b: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	meta_a.set_meta("nested", {"values": [Resource.new()]})
	meta_b.set_meta("nested", {"values": [Resource.new()]})
	check(fixture._signature(meta_a) != fixture._signature(meta_b), "nested resources preserve identity")
	tree.free()
	print("MATERIAL_INTERN_FIXTURE_CHECKS_OK ", checks)
	quit()
