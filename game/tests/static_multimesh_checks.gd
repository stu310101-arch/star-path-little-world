extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Plan = preload("res://scripts/sakura_routes.gd")
const Garden = preload("res://tools/sakura_garden.gd")
const TEMP_SCENE: String="res://tests/static_multimesh_roundtrip.tscn"

var radius: float=48.0
var failures: int=0
var checks: int=0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,description: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(description)

func run() -> void:
	# Compile the actual flowers method without constructing its SceneTree
	# builder, whose _initialize would otherwise start a complete world build.
	var source: String=FileAccess.get_file_as_string("res://tools/build_world.gd")
	var method: String="func flowers("+source.get_slice("func flowers(",1).get_slice("func lamp(",0)
	var helper_script: GDScript=GDScript.new()
	helper_script.source_code="extends Node\nconst Geo = preload(\"res://scripts/planet_geometry.gd\")\n"+method
	check(helper_script.reload()==OK,"Actual flower builder must compile independently")
	var helper: Node=helper_script.new() as Node
	var fixture: Node3D=Node3D.new()
	fixture.name="StaticInstancesFixture"
	root.add_child(fixture)
	helper.call("flowers",fixture,Vector3(0,.48,0),Color("d198ac"))
	var grove: Node3D=Node3D.new()
	grove.name="SakuraGrove"
	fixture.add_child(grove)
	var life: Node3D=Node3D.new()
	life.name="OceanLife"
	fixture.add_child(life)
	Garden.petals(self,life,Plan.grove_up())
	await process_frame
	var paths: Array[String]=["FlowerBed","SakuraGrove/SettledBlossoms"]
	var saved_placements: Dictionary={}
	for path: String in paths:
		var node: MultiMeshInstance3D=fixture.get_node(path) as MultiMeshInstance3D
		var placements: Array=node.get_meta("placements",[]) as Array
		saved_placements[path]=placements.duplicate()
		check(placements.size()==(15 if path=="FlowerBed" else 180),"Preserve authored static instance counts")
		check((node.get_script() as Script).resource_path=="res://scripts/ecology_instances.gd","Static instances require the existing runtime uploader")
		check(node.multimesh.instance_count==placements.size(),"_ready must allocate every authored transform")
		for placement: Transform3D in placements:
			check(placement.origin.is_finite() and placement.basis.is_finite(),"Instance transform must remain finite")
			check(node.custom_aabb.encloses(placement*node.multimesh.mesh.get_aabb()),"Runtime bounds must enclose the real local instance geometry")
	var flowers: Array=saved_placements["FlowerBed"]
	check((flowers[0] as Transform3D).origin.is_equal_approx(Vector3(.13,.12,0)),"Preserve the original first flower anchor")
	var settled: Array=saved_placements["SakuraGrove/SettledBlossoms"]
	for placement: Transform3D in settled:
		check(placement.origin.length()>48.16 and placement.origin.length()<48.28,"Settled petals retain their authored spherical ground heights")
	var moving: MultiMeshInstance3D=life.get_node("SakuraPetals") as MultiMeshInstance3D
	check(moving.multimesh.instance_count==128 and not moving.has_meta("placements"),"Moving petals retain their per-frame update contract")
	Geo.own_tree(fixture,fixture)
	var packed: PackedScene=PackedScene.new()
	check(packed.pack(fixture)==OK,"Pack the minimal static-instance fixture")
	check(ResourceSaver.save(packed,TEMP_SCENE)==OK,"Save authored metadata through the headless builder")
	fixture.free()
	var restored: Node3D=(ResourceLoader.load(TEMP_SCENE,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	root.add_child(restored)
	await process_frame
	for path: String in paths:
		var node: MultiMeshInstance3D=restored.get_node(path) as MultiMeshInstance3D
		var placements: Array=node.get_meta("placements",[]) as Array
		var before: Array=saved_placements[path]
		check(placements.size()==before.size(),"Serialization must preserve the complete placement list")
		for i: int in range(placements.size()):
			check((placements[i] as Transform3D).is_equal_approx(before[i] as Transform3D),"Headless save/reload must preserve every authored matrix")
		check(node.multimesh.instance_count==before.size(),"Runtime script must rebuild the saved instance allocation")
	restored.free()
	helper.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SCENE))
	print("STATIC_MULTIMESH_CHECKS ",checks," checks, ",failures," failures; preserved 15 flower and 180 settled-petal transforms")
	quit(1 if failures>0 else 0)
