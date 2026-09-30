extends RefCounted

const Vegetation=preload("res://scripts/camera_vegetation.gd")
var vegetation: RefCounted=Vegetation.new()

# Keep the requested orbit radius. Nearby walls that obstruct the character
# fade briefly instead of forcing the camera to zoom toward the player.
var faded: Dictionary = {}
var canopy_meshes: Array[MeshInstance3D] = []
var canopy_groups: Dictionary = {}
var building_meshes: Array[MeshInstance3D] = []
var building_groups: Dictionary = {}
var indexed_world: int = 0

func restore_record(record: Dictionary) -> void:
	var mesh: MeshInstance3D = record.mesh as MeshInstance3D
	if not is_instance_valid(mesh):
		return
	mesh.material_override = record.override as Material
	mesh.visible=bool(record.visible)
	for slot: int in range((record.surfaces as Array).size()):
		mesh.set_surface_override_material(slot,record.surfaces[slot] as Material)

func reset() -> void:
	vegetation.call("reset")
	for record: Dictionary in faded.values():
		restore_record(record)
	faded.clear()

func add_mesh(mesh: MeshInstance3D) -> void:
	var id: int = mesh.get_instance_id()
	if faded.has(id) or mesh.mesh == null:
		return
	var record: Dictionary = {"mesh":mesh,"visible":mesh.visible,"override":mesh.material_override,"surfaces":[],"materials":[],"alpha":[],"opacity":1.0}
	for slot: int in range(mesh.mesh.get_surface_count()):
		record.surfaces.append(mesh.get_surface_override_material(slot))
		var original: BaseMaterial3D = mesh.get_active_material(slot) as BaseMaterial3D
		if original == null:
			return
		var material: BaseMaterial3D = original.duplicate() as BaseMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		record.materials.append(material)
		record.alpha.append(original.albedo_color.a)
	mesh.material_override = null
	for slot: int in range((record.materials as Array).size()):
		mesh.set_surface_override_material(slot,record.materials[slot] as Material)
	faded[id] = record

func update(world: Node3D,camera: Camera3D,aim: Vector3,delta: float) -> void:
	vegetation.call("update",world,camera,aim)
	var obstructing: Dictionary = {}
	if indexed_world!=world.get_instance_id():
		canopy_meshes.clear()
		canopy_groups.clear()
		building_meshes.clear()
		building_groups.clear()
		indexed_world=world.get_instance_id()
		var neighborhood: Node=world.get_node_or_null("Neighborhood")
		if neighborhood!=null:
			for district: Node in neighborhood.get_children():
				for building: Node in district.get_children():
					if not building.has_node("Foundation"):
						continue
					var members: Array[Node]=building.find_children("*","MeshInstance3D",true,false)
					for member: MeshInstance3D in members:
						building_meshes.append(member)
						building_groups[member.get_instance_id()]=members
		for tree: Node in world.find_children("SakuraTree_*","Node3D",true,false):
			var tree_meshes: Array[Node]=tree.find_children("*","MeshInstance3D",true,false)
			for node: Node in tree_meshes:
				var mesh: MeshInstance3D = node as MeshInstance3D
				for slot: int in range(mesh.mesh.get_surface_count()):
					var material: BaseMaterial3D = mesh.get_active_material(slot) as BaseMaterial3D
					if material!=null and material.albedo_texture!=null:
						canopy_meshes.append(mesh)
						canopy_groups[mesh.get_instance_id()]=tree_meshes
						break
	# Concave model collision has no solid interior. A ray that starts inside
	# a house can miss every outward-facing wall, even with hit_from_inside.
	# Detect the lens volume directly and fade the complete building shell.
	for mesh: MeshInstance3D in building_meshes:
		if mesh.get_aabb().grow(.12).has_point(mesh.to_local(camera.global_position)):
			for member: MeshInstance3D in building_groups[mesh.get_instance_id()]:
				add_mesh(member)
				obstructing[member.get_instance_id()]=true
	# Leaf cards have no player collision. Test their own local bounds so a
	# branch between the lens and the character cannot evade the trunk ray.
	for mesh: MeshInstance3D in canopy_meshes:
		if not is_instance_valid(mesh):
			continue
		var local_from: Vector3 = mesh.to_local(camera.global_position)
		for target: Vector3 in [aim,aim+camera.global_basis.y*.35]:
			if mesh.get_aabb().intersects_segment(local_from,mesh.to_local(target))!=null:
				# Fade the complete silhouette, including branches. Several layers
				# of faint flower cards otherwise accumulate into an opaque haze.
				for tree_mesh: MeshInstance3D in canopy_groups[mesh.get_instance_id()]:
					add_mesh(tree_mesh)
					obstructing[tree_mesh.get_instance_id()]=true
				break
	for offset: Vector3 in [Vector3.ZERO,camera.global_basis.x*.24,-camera.global_basis.x*.24,camera.global_basis.y*.35]:
		var excluded: Array[RID] = []
		for step: int in range(6):
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera.global_position,aim+offset,8)
			query.exclude = excluded
			query.hit_from_inside = true
			query.hit_back_faces = true
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty():
				break
			var collider: CollisionObject3D = hit.collider as CollisionObject3D
			excluded.append(collider.get_rid())
			var parent: Node = collider.get_parent()
			var meshes: Array[Node] = []
			if parent is MeshInstance3D:
				if building_groups.has(parent.get_instance_id()):
					meshes=building_groups[parent.get_instance_id()]
				else:
					meshes.append(parent)
			elif str(parent.name).begins_with("sakura_") or str(parent.name).begins_with("SakuraTree_"):
				meshes = parent.find_children("*","MeshInstance3D",true,false)
			for node: Node in meshes:
				var mesh: MeshInstance3D = node as MeshInstance3D
				add_mesh(mesh)
				obstructing[mesh.get_instance_id()] = true
	for id: int in faded.keys():
		var record: Dictionary = faded[id]
		if not is_instance_valid(record.mesh):
			faded.erase(id)
			continue
		var target: float = 0.0 if obstructing.has(id) else 1.0
		record.opacity = move_toward(float(record.opacity),target,delta*5.0)
		# Fully obscuring cards leave the render list after the brief fade. This
		# also avoids accumulating transparent layers and their hidden shadows.
		(record.mesh as MeshInstance3D).visible=bool(record.visible) and float(record.opacity)>.001
		for slot: int in range((record.materials as Array).size()):
			var material: BaseMaterial3D = record.materials[slot] as BaseMaterial3D
			var tint: Color = material.albedo_color
			tint.a = float(record.alpha[slot])*float(record.opacity)
			material.albedo_color = tint
		if is_equal_approx(float(record.opacity),1.0):
			restore_record(record)
			faded.erase(id)
