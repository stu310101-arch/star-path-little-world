extends SceneTree

const Quality=preload("res://scripts/mobile_render_quality.gd")
class MovingActor:
	extends Node3D

var failures: int=0
var checks: Array[Dictionary]=[]
var world: Node3D
var globe: Node3D
var helper: RefCounted

func _initialize() -> void: call_deferred("run")

func check(label: String, passed: bool, evidence: Variant=null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures+=1
		push_error(label+": "+str(evidence))

func visual(parent: Node3D, label: String, at: Vector3, shadow: int=0) -> MeshInstance3D:
	var node: MeshInstance3D=MeshInstance3D.new()
	node.name=label
	node.mesh=BoxMesh.new()
	node.layers=5
	node.cast_shadow=shadow as GeometryInstance3D.ShadowCastingSetting
	parent.add_child(node)
	node.position=at
	return node

func triangle(z: float) -> ArrayMesh:
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-.5,0,z),Vector3(.5,0,z),Vector3(0,1,z)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.UP])
	var mesh: ArrayMesh=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func run() -> void:
	world=Node3D.new()
	root.add_child(world)
	globe=Node3D.new()
	globe.name="Globe"
	world.add_child(globe)
	var front: MeshInstance3D=visual(globe,"Front",Vector3(0,0,11))
	var rear: MeshInstance3D=visual(globe,"Rear",Vector3(0,0,-11))
	var caster: MeshInstance3D=visual(globe,"RearCaster",Vector3(0,0,-12),1)
	var double_caster: MeshInstance3D=visual(globe,"DoubleSided",Vector3(0,0,-13),2)
	var child: MeshInstance3D=visual(rear,"FrontChild",Vector3(0,0,23))
	var hidden_branch: Node3D=Node3D.new()
	hidden_branch.visible=false
	globe.add_child(hidden_branch)
	var authoring: MeshInstance3D=visual(hidden_branch,"PreservedSource",Vector3(0,0,-12))
	var actor: Node3D=MovingActor.new()
	globe.add_child(actor)
	var animated: MeshInstance3D=visual(actor,"Animated",Vector3(0,0,-12))
	var batch: MeshInstance3D=visual(globe,"ExactBatch",Vector3.ZERO,1)
	batch.mesh=triangle(11)
	var material: StandardMaterial3D=StandardMaterial3D.new()
	material.albedo_color=Color("186c72")
	batch.material_override=material
	batch.set_meta("mobile_render_tiles",[triangle(11),triangle(-11)] as Array[Mesh])
	helper=Quality.new()
	helper.call("configure",world,10.0)
	helper.call("update_visibility",Vector3(0,0,15),false)
	check("Standard profile enables exact partitions independently of mobile shading",not helper.get("enabled") and helper.call("metrics").exact_tiles_active)
	check("Near-side geometry keeps its authored layers",front.layers==5)
	check("Fully occulted geometry is absent from the color pass",rear.layers==0)
	check("Occlusion preserves parent visibility and its front-side child",rear.visible and child.visible and child.layers==5)
	check("A hidden caster still projects shadows",caster.visible and caster.layers==5 and caster.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	check("Two-sided casters retain their exact casting mode",double_caster.layers==5 and double_caster.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED)
	check("Authoring-only and independently animated branches are never rewritten",authoring.layers==5 and animated.layers==5)
	var tiles: Array=helper.get("_tile_sources")[0].children
	check("Exact tiles replace source geometry without a duplicate draw",batch.layers==0 and (tiles[0] as MeshInstance3D).visible)
	check("Tiles retain runtime art material identity",tiles[0].material_override==material and tiles[1].material_override==material)
	check("Partition preserves casting on both visible and occulted geometry",tiles[0].cast_shadow==1 and tiles[1].cast_shadow==3)
	helper.call("set_enabled",true)
	check("Mobile quality still applies its own material",tiles[0].get_active_material(0)!=material)
	helper.call("set_enabled",false)
	check("Standard restores the exact material while keeping exact partitions",tiles[0].get_active_material(0)==material and batch.layers==0)
	helper.call("update_visibility",Vector3(0,0,-15),false)
	check("Opposite-side camera restores geometry in the same frame",rear.layers==5 and front.layers==0 and caster.cast_shadow==1)
	helper.call("update_visibility",Vector3(0,0,-15),true)
	check("Overview restores authored batch and disables partition draw",batch.layers==5 and not tiles[0].visible and not tiles[1].visible)
	helper.call("update_visibility",Vector3.ZERO,true)
	check("Inside the conservative occluder all geometry is restored",front.layers==5 and rear.layers==5 and caster.cast_shadow==1)
	var chunk: Node3D=Node3D.new()
	world.add_child(chunk)
	chunk.visible=false
	var detail: MeshInstance3D=visual(chunk,"Detail",Vector3(0,0,-12),1)
	var before: int=helper.call("metrics").occlusion_candidates
	helper.call("register_chunk",chunk)
	helper.call("update_visibility",Vector3(0,0,15),true)
	check("Static streamed children are indexed even before parent activation",helper.call("metrics").occlusion_candidates==before+1 and detail.cast_shadow==3 and not chunk.visible)
	helper.call("unregister_chunk",chunk)
	chunk.free()
	check("Unloading removes weak visibility records immediately",helper.call("metrics").occlusion_candidates==before)
	verify_tangent_boundary()
	verify_sampled_visibility()
	var folder: String=ProjectSettings.globalize_path("res://../deliverables/render-budget")
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("planet-visibility-checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"checks":checks},"\t"))
	print("PLANET_VISIBILITY checks=",checks.size()," failures=",failures)
	world.free()
	quit(1 if failures else 0)

func verify_tangent_boundary() -> void:
	# At z=0 and eye z=15, the exact tangent to an occluder of radius 9.4
	# lies at x≈12.07. A bounding sphere that straddles it must stay visible.
	var chunk: Node3D=Node3D.new()
	world.add_child(chunk)
	var tangent_x: float=15.0*9.4/sqrt(225.0-9.4*9.4)
	var horizon: MeshInstance3D=visual(chunk,"Horizon",Vector3(tangent_x,0,0))
	var behind: MeshInstance3D=visual(chunk,"BehindHorizon",Vector3(tangent_x-2.0,0,0))
	helper.call("register_chunk",chunk)
	helper.call("update_visibility",Vector3(0,0,15),false)
	check("Tangent-straddling bounds remain visible while fully hidden bounds cull",horizon.layers==5 and behind.layers==0)
	helper.call("unregister_chunk",chunk)
	chunk.free()

func verify_sampled_visibility() -> void:
	var chunk: Node3D=Node3D.new()
	world.add_child(chunk)
	var random: RandomNumberGenerator=RandomNumberGenerator.new()
	random.seed=771415
	for index: int in range(220):
		var direction: Vector3=Vector3(random.randf_range(-1,1),random.randf_range(-1,1),random.randf_range(-1,1)).normalized()
		var node: MeshInstance3D=visual(chunk,"Sample_"+str(index),direction*random.randf_range(9.6,18.0))
		node.scale=Vector3.ONE*random.randf_range(.1,1.5)
	helper.call("register_chunk",chunk)
	var violations: int=0
	var culled: int=0
	var rays: int=0
	var cache_hits: int=int(helper.call("metrics").visibility_cache_hits)
	for eye: Vector3 in [Vector3(0,0,15),Vector3(.10,0,15),Vector3(0,-.10,15),Vector3(25,9,-14),Vector3(25,9.08,-14.02),Vector3(-13,4,5),Vector3(-13.05,4.04,5.05)]:
		helper.call("update_visibility",eye,false)
		for node: MeshInstance3D in chunk.get_children():
			if node.layers!=0: continue
			culled+=1
			var bounds: AABB=node.global_transform*node.get_aabb()
			var extent: float=bounds.size.length()*.5
			# Independent ray/sphere intersection oracle on 64 boundary points.
			for index: int in range(64):
				var y: float=1.0-2.0*(float(index)+.5)/64.0
				var r: float=sqrt(1.0-y*y)
				var point: Vector3=bounds.get_center()+Vector3(cos(index*2.399963)*r,y,sin(index*2.399963)*r)*extent
				var offset: Vector3=point-eye
				var distance: float=offset.length()
				var ray: Vector3=offset/distance
				var projection: float=eye.dot(ray)
				var discriminant: float=projection*projection-(eye.length_squared()-9.4*9.4)
				var entry: float=-projection-sqrt(maxf(0.0,discriminant))
				if discriminant<0.0 or entry<0.0 or entry>=distance: violations+=1
				rays+=1
	check("Every sampled culled bounding sphere is behind the opaque planet",violations==0 and culled>50,{"culled_bounds":culled,"sampled_rays":rays,"false_occlusions":violations})
	check("Conservative eye cache also passes independent ray visibility oracle",int(helper.call("metrics").visibility_cache_hits)-cache_hits==4)
	helper.call("unregister_chunk",chunk)
	chunk.free()
