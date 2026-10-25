extends SceneTree

const Probe = preload("res://tests/render_submission_probe.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func run() -> void:
	# Do not add the probe to the tree: this checks its pure diagnostic utilities.
	var probe: Node = Probe.new()
	var world: Node3D = Node3D.new()
	root.add_child(world)
	probe.world = world
	var district: Node3D = Node3D.new()
	district.name = "Detail_sakura_1"
	world.add_child(district)
	var fixtures: Dictionary = {
		"StreetLight_1": "other", "ArchitecturalEnvelope": "architecture",
		"Sidewalk": "terrain", "OceanLife_Fish": "traffic", "FineLeafStreetPlanter": "vegetation",
		"LakeFish_1": "traffic", "Unknown_1": "other", "ContouredBanksAndGround": "terrain",
	}
	for title: String in fixtures:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.name = title
		mesh.mesh = BoxMesh.new()
		district.add_child(mesh)
		check(probe.classify(mesh) == fixtures[title], "classification: " + title)
	var label: Label3D = Label3D.new()
	label.name = "StationLabel"
	district.add_child(label)
	check(probe.classify(label) == "labels", "3D labels separate from building category")
	var stones: MultiMeshInstance3D = MultiMeshInstance3D.new()
	stones.set_meta("aquatic_kind", "bank_stones")
	district.add_child(stones)
	check(probe.classify(stones) == "terrain", "ecology stones are not vegetation")
	var geometry: MeshInstance3D = district.get_node("Sidewalk") as MeshInstance3D
	geometry.layers = 5
	geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	probe.records.append({"node": geometry, "category": "terrain"})
	var saved: Array[Dictionary] = probe.disable_category("terrain")
	check(geometry.layers == 0, "geometry disabled")
	check(geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "no shadow property mutation")
	probe.restore(saved)
	check(geometry.layers == 5, "original layers restored exactly")
	var hud: CanvasLayer = CanvasLayer.new()
	world.add_child(hud)
	saved = probe.disable_category("ui")
	check(not hud.visible, "UI hidden")
	probe.restore(saved)
	check(hud.visible, "UI restored")
	var light: DirectionalLight3D = DirectionalLight3D.new()
	world.add_child(light)
	light.shadow_enabled = true
	saved = probe.disable_category("shadows")
	check(not light.shadow_enabled, "shadow ablation")
	probe.restore(saved)
	check(light.shadow_enabled, "shadow restored")
	print("SUBMISSION_PROBE_CHECKS ", checks, " failures=", failures)
	probe.free()
	world.free()
	quit(0 if failures.is_empty() else 1)
