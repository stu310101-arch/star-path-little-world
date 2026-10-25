extends SceneTree

var stage: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size=Vector2i(1536,1024)
	stage=Node3D.new()
	root.add_child(stage)
	var environment: WorldEnvironment=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("607c85")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("bfd1dc")
	environment.environment.ambient_light_energy=.36
	environment.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var sunlight: DirectionalLight3D=DirectionalLight3D.new()
	sunlight.rotation_degrees=Vector3(-42,-36,0)
	sunlight.light_energy=.45
	sunlight.shadow_enabled=true
	sunlight.directional_shadow_max_distance=110
	sunlight.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	stage.add_child(sunlight)
	var water: MeshInstance3D=MeshInstance3D.new()
	var plane: PlaneMesh=PlaneMesh.new()
	plane.size=Vector2(300,300)
	water.mesh=plane
	water.position.y=-.05
	var mat: StandardMaterial3D=StandardMaterial3D.new()
	mat.albedo_color=Color("466c76")
	mat.roughness=.85
	mat.metallic_specular=.15
	water.material_override=mat
	stage.add_child(water)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=400
	stage.add_child(camera)
	camera.make_current()
	var folder: String=ProjectSettings.globalize_path("res://../deliverables/vessels")
	DirAccess.make_dir_recursive_absolute(folder)
	for id: String in ["fishing_boat","tugboat","liner"]:
		var vessel: Node3D=(load("res://assets/vessels/"+id+".glb") as PackedScene).instantiate() as Node3D
		stage.add_child(vessel)
		var length_m: float={"fishing_boat":7.8,"tugboat":17.0,"liner":36.0}[id]
		for side: String in ["bow","stern"]:
			camera.size=length_m*.96
			camera.position=Vector3(length_m*.87,length_m*.63,length_m*(.98 if side=="bow" else -.98))
			camera.look_at(Vector3(0,length_m*.085,0),Vector3.UP)
			for frame: int in range(8): await process_frame
			await RenderingServer.frame_post_draw
			var screenshot: Image=root.get_texture().get_image()
			assert(screenshot.save_png(folder+"/"+id+"-godot-"+side+".png")==OK)
			print("VESSEL_CAPTURE "+id+" "+side)
		vessel.free()
	quit()
