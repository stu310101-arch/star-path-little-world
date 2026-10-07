extends SceneTree

const Builder = preload("res://tools/streaming_world_builder.gd")
var builder: RefCounted = Builder.new()
var rows: Array[Dictionary] = []
var totals: Dictionary = {"source":0,"reduced":0,"protected":0,"meshes":0,"multimesh_instances":0}

func _initialize() -> void:
	call_deferred("run")

func inspect_node(node: Node, parent_transform: Transform3D, node_path: String) -> void:
	var transform: Transform3D = parent_transform * ((node as Node3D).transform if node is Node3D else Transform3D.IDENTITY)
	var mesh: Mesh = null
	var instances: int = 1
	var protected: bool = false
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
		protected = mesh != null and bool(builder.call("preserve_surface_geometry", node, transform))
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		mesh = (node as MultiMeshInstance3D).multimesh.mesh
		instances = (node as MultiMeshInstance3D).multimesh.instance_count
		totals.multimesh_instances += instances
	if mesh != null:
		var reduced: Mesh = mesh if protected else builder.call("reduced_mesh", mesh) as Mesh
		var source_count: int = 0
		var reduced_count: int = 0
		for surface: int in range(mesh.get_surface_count()):
			source_count += int(builder.call("triangle_count", mesh, surface)) * instances
			reduced_count += int(builder.call("triangle_count", reduced, surface)) * instances
		rows.append({"path":node_path,"source":source_count,"reduced":reduced_count,"protected":protected,"instances":instances,"mesh":mesh.resource_path})
		totals.source += source_count
		totals.reduced += reduced_count
		totals.protected += source_count if protected else 0
		totals.meshes += 1
	for child: Node in node.get_children():
		inspect_node(child, transform, node_path + "/" + str(child.name))

func run() -> void:
	var paths: Array[String] = ["res://generated/globe.tscn", "res://generated/stations.tscn"]
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	for station: Dictionary in layout.stations:
		paths.append("res://generated/districts/" + str(station.id) + ".tscn")
	for path: String in paths:
		var scene: Node = (load(path) as PackedScene).instantiate()
		inspect_node(scene, Transform3D.IDENTITY, path)
		scene.free()
		print("OVERVIEW_AUDIT_SOURCE ", path)
	rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.reduced)>int(b.reduced))
	var report: Dictionary = {"totals":totals,"meshes":rows}
	var output: String = ProjectSettings.globalize_path("res://").path_join("../build/low-end").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	var file: FileAccess = FileAccess.open(output.path_join("overview-source-audit.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("OVERVIEW_AUDIT_TOTAL ", JSON.stringify(totals))
	print("OVERVIEW_AUDIT_TOP ", JSON.stringify(rows.slice(0,30)))
	quit()
