extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")

static func apply(globe: Node3D,layout: Dictionary,districts: Array) -> Dictionary:
	var radius: float = float(layout.radius)
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/water_ecology.json")) as Dictionary
	var report: Dictionary = {"districts":[],"fish":0,"plant_clusters":0,"walkable_water":false}
	# Keep shader resources alive until all their old geometry instances are gone.
	# This also permits repeat builds with Godot's headless dummy renderer.
	var retained_materials: Array[Material] = []
	preload("res://tools/open_freshwater_basins.gd").apply(globe,layout,districts)
	for index: int in range(districts.size()):
		var data: Dictionary = districts[index]
		var settings: Dictionary = {}
		for row: Dictionary in plan.districts:
			if str(row.station)==str(data.station):
				settings=row
		assert(not settings.is_empty())
		var u: Array = layout.stations[index].normal
		var up: Vector3 = Vector3(u[0],u[1],u[2])
		var reserve: Node3D = globe.get_node("EcologicalReserves/Reserve_"+str(data.station)) as Node3D
		var old: Node = reserve.get_node_or_null("AquaticHabitat")
		if old!=null:
			for mesh: MeshInstance3D in old.find_children("*","MeshInstance3D",true,false):
				for s: int in range(mesh.mesh.get_surface_count()):
					retained_materials.append(mesh.get_active_material(s))
			reserve.remove_child(old)
			old.free()
		var habitat: Node3D = Node3D.new()
		habitat.name="AquaticHabitat"
		habitat.set_script(load("res://scripts/lake_life.gd"))
		habitat.set_meta("district_up",up)
		habitat.set_meta("radius",radius)
		habitat.set_meta("description",settings.description)
		reserve.add_child(habitat)
		var surface: MeshInstance3D = reserve.get_node("FreshwaterContours") as MeshInstance3D
		var water_mat: ShaderMaterial = ShaderMaterial.new()
		water_mat.shader=load("res://shaders/lake_water.gdshader") as Shader
		water_mat.set_shader_parameter("water_color",Color("42776c") if index==5 else Color("367e80"))
		surface.material_override=water_mat
		# The bed reuses the exact clipped shoreline vertices. It is visual only,
		# so the existing no-walking-on-water physics remains intact.
		var bed_st: SurfaceTool = SurfaceTool.new()
		bed_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var arrays: Array = surface.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var axes: Basis = Geo.frame(up)
		for point: Vector3 in points:
			var tangent: Vector2 = Vector2(point.dot(axes.x),point.dot(axes.z))*radius/point.dot(up)
			var depth: float = lerpf(.12,.60,smoothstep(0.0,1.5,-Waterfront.water_distance(tangent,data)))
			bed_st.set_normal(point.normalized())
			bed_st.add_vertex(point.normalized()*(radius-depth))
		var bed_mat: ShaderMaterial = ShaderMaterial.new()
		bed_mat.shader=load("res://shaders/lake_bed.gdshader") as Shader
		bed_mat.set_shader_parameter("bed_color",Color("4e6950") if index==5 else Color("698c76"))
		# Outside the before/after visibility container to keep comparison water consistent.
		var prior_bed: Node = reserve.get_node_or_null("ShallowWaterBed")
		if prior_bed!=null:
			reserve.remove_child(prior_bed)
			prior_bed.free()
		var bed: MeshInstance3D = Geo.mesh_node(reserve,"ShallowWaterBed",bed_st.commit(),bed_mat)
		bed.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var batches: Dictionary = {}
		for plant: Dictionary in settings.plants:
			var kind: String = str(plant.kind)
			if not batches.has(kind):
				batches[kind]=[]
			var p: Vector2 = Vector2(plant.point[0],plant.point[1])
			var normal: Vector3 = Geo.surface(up,p,radius).normalized()
			var basis: Basis = (Geo.frame(normal)*Basis(Vector3.UP,float(plant.yaw))).scaled(Vector3.ONE*float(plant.scale))
			(batches[kind] as Array).append(Transform3D(basis,normal*(radius+float(plant.height))))
		for kind: String in batches:
			plant_batch(habitat,kind,batches[kind])
		var fish_count: int = 0
		for path: Dictionary in settings.fish_paths:
			for i: int in range(3):
				var fish: Node3D = (load("res://assets/scenery/fish_1.glb") as PackedScene).instantiate() as Node3D
				fish.name="LakeFish_"+str(fish_count)
				fish.set_meta("swim_path",path)
				fish.set_meta("phase",float(path.get("phase",0.0))+float(i)*1.5)
				fish.set_meta("size_factor",.85+float(i)*.12)
				for mesh: MeshInstance3D in fish.find_children("*","MeshInstance3D",true,false):
					mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					for surface_index: int in range(mesh.mesh.get_surface_count()):
						var source: StandardMaterial3D = mesh.get_active_material(surface_index) as StandardMaterial3D
						var fish_mat: ShaderMaterial = ShaderMaterial.new()
						fish_mat.shader=load("res://shaders/lake_fish.gdshader") as Shader
						var color: Color = source.albedo_color
						if source.resource_name=="Top":
							color=Color("d28a38") if i%2==0 else Color("b96040")
							if index in [1,3,5]:
								color=Color("819e98") if i%2==0 else Color("b7ad71")
						fish_mat.set_shader_parameter("fish_color",color)
						fish_mat.set_shader_parameter("stroke_phase",float(fish_count)*1.5)
						mesh.set_surface_override_material(surface_index,fish_mat)
				habitat.add_child(fish)
				fish_count+=1
		report.fish+=fish_count
		report.plant_clusters+=(settings.plants as Array).size()
		report.districts.append({"station":data.station,"description":settings.description,"fish":fish_count,"plant_clusters":(settings.plants as Array).size()})
	return report

static func plant_batch(habitat: Node3D,kind: String,placements: Array) -> void:
	var asset: Node3D = (load("res://assets/ecology/"+kind+".glb") as PackedScene).instantiate() as Node3D
	for source: MeshInstance3D in asset.find_children("*","MeshInstance3D",true,false):
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name=kind+"_"+str(source.name)
		node.multimesh=MultiMesh.new()
		node.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		var mesh: Mesh=source.mesh.duplicate() as Mesh
		# The botanical source assets store their colour in vertex attributes.
		# Restore that material flag explicitly for MultiMesh, as the land plants do.
		if kind in ["cattail","bank_stones","fern"]:
			for surface_index: int in range(mesh.get_surface_count()):
				var mat: StandardMaterial3D=source.get_active_material(surface_index).duplicate() as StandardMaterial3D
				mat.vertex_color_use_as_albedo=true
				mat.albedo_color=Color.WHITE
				mat.cull_mode=BaseMaterial3D.CULL_DISABLED
				mat.roughness=1.0
				mesh.surface_set_material(surface_index,mat)
		node.multimesh.mesh=mesh
		var transforms: Array[Transform3D] = []
		for placement: Transform3D in placements:
			transforms.append(placement*source.transform)
		node.set_meta("placements",transforms)
		node.set_meta("aquatic_kind",kind)
		node.set_script(load("res://scripts/ecology_instances.gd"))
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		habitat.add_child(node)
	asset.free()

