extends Node3D

const BEAM: Shader = preload("res://shaders/training_projection.gdshader")
const SCREEN: Shader = preload("res://shaders/training_hologram.gdshader")
const LENS: Shader = preload("res://shaders/training_lens_glow.gdshader")

func configure(model: Node3D, device_position: Vector3) -> void:
	name = "WordKingProjection"
	var emitter_position: Vector3 = device_position + Vector3(0, .495, 0)
	var optical_materials: Dictionary = {
		"Hologram_Beam": _field(BEAM, emitter_position),
		"Hologram_Glass": _field(SCREEN, emitter_position),
		"Hologram_Cyan": _light_material(Color("228bff"), 1.2),
		"Hologram_Type": _light_material(Color("9cdfff"), .55),
		"Hologram_Grid": _light_material(Color("1762bd"), .25),
		"Projector_Blue_Inlay": _light_material(Color("1784ff"), 1.0),
	}
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var source: Material = mesh_node.get_active_material(surface)
			if source == null:
				continue
			var key: String = source.resource_name.trim_prefix("MAT_Game_")
			if optical_materials.has(key):
				mesh_node.set_surface_override_material(surface, optical_materials[key] as Material)
				# Optical meshes are batched separately from the physical chassis.
				mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh_node.set_meta("projector_optical", true)
	var halo: MeshInstance3D = MeshInstance3D.new()
	halo.name = "EmitterHalo"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.15, 1.15)
	halo.mesh = quad
	halo.rotation.x = -PI * .5
	halo.position = emitter_position + Vector3.UP * .007
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lens_material: ShaderMaterial = ShaderMaterial.new()
	lens_material.shader = LENS
	halo.material_override = lens_material
	add_child(halo)
	var spill: OmniLight3D = OmniLight3D.new()
	spill.name = "BlueLensSpill"
	spill.position = device_position + Vector3(0, .65, 0)
	spill.light_color = Color("2684ff")
	spill.light_energy = .7
	spill.omni_range = 2.4
	spill.omni_attenuation = 1.8
	spill.shadow_enabled = false
	add_child(spill)

func _field(shader: Shader, emitter_position: Vector3) -> ShaderMaterial:
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = shader
	result.set_shader_parameter("emitter", emitter_position)
	return result

func _light_material(color: Color, energy: float) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.albedo_color = color
	result.emission_enabled = true
	result.emission = color
	result.emission_energy_multiplier = energy
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result
