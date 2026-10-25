extends RefCounted

## Material/LOD swaps remain profile-specific. Exact spatial partitions and
## planet occlusion work in every profile without changing visible geometry.
const MobileSurface = preload("res://shaders/world_surface_mobile.gdshader")
const EYE_CACHE_RADIUS: float = .12
var enabled: bool = false
var radius: float = 24.0
var _base: Array[Node3D] = []
var _occludable: Array[Dictionary] = []
var _materials: Dictionary = {}
var _tile_sources: Array[Dictionary] = []
var _overview: bool = true
var _tiles_ready: bool = false
var culled_meshes: int = 0
var swapped_meshes: int = 0
var last_visibility_usec: int = 0
var max_visibility_usec: int = 0
var shadow_only_meshes: int = 0
var _last_eye: Vector3 = Vector3.INF
var _visibility_dirty: bool = true
var visibility_evaluations: int = 0
var visibility_cache_hits: int = 0

func configure(world: Node3D, physical_radius: float) -> void:
	radius=physical_radius
	for name: String in ["Globe","Neighborhood","Stations"]:
		var container: Node3D=world.get_node_or_null(name) as Node3D
		if container==null: continue
		_base.append(container)
		_register_branch(container,container.get_instance_id(),true)
	_ensure_tiles()
	if enabled:
		for node: Node3D in _base: apply_materials(node)

func set_enabled(value: bool) -> void:
	if enabled==value: return
	enabled=value
	for node: Node3D in _base: apply_materials(node)

func register_chunk(chunk: Node3D) -> void:
	# Register after art replacement. Animated actors, authoring-only hidden
	# branches and independently compacted vegetation buffers stay untouched.
	_register_branch(chunk,chunk.get_instance_id(),true)
	_prune_material_cache()
	_visibility_dirty=true

func unregister_chunk(chunk: Node3D) -> void:
	var id: int=chunk.get_instance_id()
	for index: int in range(_occludable.size()-1,-1,-1):
		if int(_occludable[index].root)==id: _occludable.remove_at(index)
	_visibility_dirty=true

func _register_branch(node: Node, root_id: int, is_root: bool=false) -> void:
	if not is_root and ((node is Node3D and not (node as Node3D).visible) or node.get_script()!=null):
		return
	if node is MeshInstance3D:
		var visual: MeshInstance3D=node as MeshInstance3D
		if visual.mesh!=null and visual.skin==null and str(visual.name)!="Ocean":
			_register_visual(visual,root_id,visual.has_meta("mobile_render_tiles"))
	for child: Node in node.get_children(): _register_branch(child,root_id)

func _register_visual(visual: MeshInstance3D, root_id: int, source: bool=false, tile: bool=false) -> void:
	var box: AABB=visual.global_transform*visual.get_aabb().grow(visual.extra_cull_margin)
	_occludable.append({"node":weakref(visual),"center":box.get_center(),"radius":box.size.length()*.5,
		"root":root_id,"source":source,"tile":tile,"layers":visual.layers,"shadow":visual.cast_shadow,"hidden":null})

func _ensure_tiles() -> void:
	if _tiles_ready or _base.is_empty(): return
	_tiles_ready=true
	for container: Node3D in _base:
		for node: Node in container.find_children("*","MeshInstance3D",true,false):
			var original: MeshInstance3D=node as MeshInstance3D
			if not original.has_meta("mobile_render_tiles"): continue
			var children: Array[MeshInstance3D]=[]
			for mesh: Mesh in original.get_meta("mobile_render_tiles") as Array:
				var tile: MeshInstance3D=MeshInstance3D.new()
				tile.name="MobileTile_"+str(children.size())
				tile.mesh=mesh
				# The batch may have a runtime art override newer than its
				# generated mesh material. Share that exact resource.
				tile.material_override=original.get_active_material(0)
				tile.material_overlay=original.material_overlay
				tile.cast_shadow=original.cast_shadow
				tile.layers=original.layers
				tile.extra_cull_margin=original.extra_cull_margin
				tile.transparency=original.transparency
				tile.lod_bias=original.lod_bias
				tile.visibility_range_begin=original.visibility_range_begin
				tile.visibility_range_end=original.visibility_range_end
				tile.visibility_range_begin_margin=original.visibility_range_begin_margin
				tile.visibility_range_end_margin=original.visibility_range_end_margin
				tile.visibility_range_fade_mode=original.visibility_range_fade_mode
				tile.visible=false
				original.add_child(tile)
				children.append(tile)
				_register_visual(tile,container.get_instance_id(),false,true)
			_tile_sources.append({"node":weakref(original),"layers":original.layers,"shadow":original.cast_shadow,"children":children})
	_set_tiles_active()

func _set_tiles_active() -> void:
	var active: bool=not _overview
	for record: Dictionary in _tile_sources:
		var original: MeshInstance3D=(record.node as WeakRef).get_ref() as MeshInstance3D
		if not is_instance_valid(original): continue
		original.layers=0 if active else int(record.layers)
		original.cast_shadow=int(record.shadow) as GeometryInstance3D.ShadowCastingSetting
		for tile: MeshInstance3D in record.children:
			tile.visible=active
			tile.layers=int(record.layers)
			tile.cast_shadow=int(record.shadow) as GeometryInstance3D.ShadowCastingSetting
	for record: Dictionary in _occludable: record.hidden=null
	_visibility_dirty=true

func apply_meshes(node: Node) -> void:
	if node.has_meta("mobile_render_mesh") and (enabled or node.has_meta("mobile_mesh_applied")) and (not node.has_meta("mobile_mesh_applied") or bool(node.get_meta("mobile_mesh_applied"))!=enabled):
		var source: Mesh
		if node is MeshInstance3D: source=(node as MeshInstance3D).mesh
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh!=null: source=(node as MultiMeshInstance3D).multimesh.mesh
		if source!=null:
			if not node.has_meta("mobile_original_mesh"): node.set_meta("mobile_original_mesh",source)
			var target: Mesh=node.get_meta("mobile_render_mesh" if enabled else "mobile_original_mesh") as Mesh
			if node is MeshInstance3D: (node as MeshInstance3D).mesh=target
			else:
				var visual: MultiMeshInstance3D=node as MultiMeshInstance3D
				# Runtime ecology already owns its buffer; other MultiMesh callers
				# can share one resource, so isolate it before the first swap.
				_unique_multimesh(visual)
				visual.multimesh.mesh=target
			node.set_meta("mobile_mesh_applied",enabled)
	for child: Node in node.get_children(): apply_meshes(child)

func _unique_multimesh(visual: MultiMeshInstance3D) -> void:
	if visual.has_meta("mobile_multimesh_unique"): return
	var source: MultiMesh=visual.multimesh
	var result: MultiMesh=MultiMesh.new()
	result.transform_format=source.transform_format
	result.use_colors=source.use_colors
	result.use_custom_data=source.use_custom_data
	result.mesh=source.mesh
	result.instance_count=source.instance_count
	# Dummy RenderingServer has no transform buffer. Do not Resource.duplicate
	# that empty buffer into an allocated MultiMesh (Godot reports size errors).
	var buffer: PackedFloat32Array=source.buffer
	if not buffer.is_empty(): result.buffer=buffer
	else:
		var placements: Array=visual.get_meta("placements",[]) as Array
		for index: int in range(source.instance_count):
			if source.transform_format==MultiMesh.TRANSFORM_3D:
				result.set_instance_transform(index,placements[index] as Transform3D if index<placements.size() else source.get_instance_transform(index))
			else: result.set_instance_transform_2d(index,source.get_instance_transform_2d(index))
	result.visible_instance_count=source.visible_instance_count
	result.custom_aabb=source.custom_aabb
	visual.multimesh=result
	visual.set_meta("mobile_multimesh_unique",true)

func apply_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var visual: MeshInstance3D=node as MeshInstance3D
		if visual.mesh!=null and visual.skin==null:
			if enabled and not visual.has_meta("mobile_material_sources"):
				var materials: Array[Material]=[]
				var overrides: Array[Material]=[]
				for index: int in range(visual.mesh.get_surface_count()):
					materials.append(visual.get_active_material(index))
					overrides.append(visual.get_surface_override_material(index))
				visual.set_meta("mobile_material_sources",materials)
				visual.set_meta("mobile_surface_overrides",overrides)
				visual.set_meta("mobile_material_override",visual.material_override)
			if visual.has_meta("mobile_material_sources"):
				var sources: Array=visual.get_meta("mobile_material_sources") as Array
				visual.material_override=null
				for index: int in range(mini(sources.size(),visual.mesh.get_surface_count())):
					visual.set_surface_override_material(index,mobile_material(sources[index] as Material) if enabled else (visual.get_meta("mobile_surface_overrides") as Array)[index] as Material)
				if not enabled:
					visual.material_override=visual.get_meta("mobile_material_override") as Material
					visual.remove_meta("mobile_material_sources")
					visual.remove_meta("mobile_material_override")
					visual.remove_meta("mobile_surface_overrides")
	elif node is MultiMeshInstance3D:
		var multi: MultiMeshInstance3D=node as MultiMeshInstance3D
		if multi.multimesh!=null and multi.multimesh.mesh!=null:
			# All authored ecology batches have one material. An override shares
			# the exact LOD vertex buffer instead of duplicating it just to tint.
			if multi.multimesh.mesh.get_surface_count()==1:
				if enabled and not multi.has_meta("mobile_multi_override"):
					multi.set_meta("mobile_multi_override",multi.material_override)
					multi.material_override=mobile_material(multi.material_override if multi.material_override!=null else multi.multimesh.mesh.surface_get_material(0))
				elif not enabled and multi.has_meta("mobile_multi_override"):
					multi.material_override=multi.get_meta("mobile_multi_override") as Material
					multi.remove_meta("mobile_multi_override")
				for child: Node in node.get_children(): apply_materials(child)
				return
			# Mesh data is shared between instances, but runtime copies keep the
			# authored and mobile resources immutable for future quality toggles.
			if enabled and not multi.has_meta("mobile_material_mesh_source"):
				_unique_multimesh(multi)
				var source: Mesh=multi.multimesh.mesh
				multi.set_meta("mobile_material_mesh_source",source)
				var copy: Mesh=source.duplicate(false) as Mesh
				for index: int in range(copy.get_surface_count()):
					copy.surface_set_material(index,mobile_material(source.surface_get_material(index)))
				multi.multimesh.mesh=copy
			elif not enabled and multi.has_meta("mobile_material_mesh_source"):
				multi.multimesh.mesh=multi.get_meta("mobile_original_mesh",multi.get_meta("mobile_material_mesh_source")) as Mesh
				multi.remove_meta("mobile_material_mesh_source")
	for child: Node in node.get_children(): apply_materials(child)

func mobile_material(source: Material) -> Material:
	if source==null: return null
	var key: int=source.get_instance_id()
	if _materials.has(key):
		var cached: Material=(_materials[key] as WeakRef).get_ref() as Material
		if cached!=null: return cached
	var result: Material=source
	if source is ShaderMaterial:
		var shader: ShaderMaterial=source as ShaderMaterial
		if shader.shader!=null and shader.shader.resource_path=="res://shaders/world_surface.gdshader":
			var copy: ShaderMaterial=shader.duplicate(false) as ShaderMaterial
			copy.shader=MobileSurface
			result=copy
	elif source is StandardMaterial3D and source.next_pass==null:
		var copy: StandardMaterial3D=source.duplicate(false) as StandardMaterial3D
		copy.shading_mode=BaseMaterial3D.SHADING_MODE_PER_VERTEX
		copy.normal_enabled=false
		copy.clearcoat_enabled=false
		copy.rim_enabled=false
		copy.anisotropy_enabled=false
		copy.heightmap_enabled=false
		copy.subsurf_scatter_enabled=false
		copy.metallic_specular=.12
		copy.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		result=copy
	# Nodes own their live material copies. A strong global cache would retain
	# every texture from every visited district after its chunks were unloaded;
	# CACHE_MODE_IGNORE also gives later visits new source IDs and new copies.
	_materials[key]=weakref(result)
	return result

func _prune_material_cache() -> void:
	for key: int in _materials.keys():
		if (_materials[key] as WeakRef).get_ref()==null:
			_materials.erase(key)

func update_visibility(eye: Vector3, overview: bool = false) -> void:
	if overview!=_overview:
		_overview=overview
		_set_tiles_active()
	# Check the current camera before rendering, including teleport/fast orbit.
	# A 150 ms streaming tick could otherwise retain stale horizon visibility.
	if not _visibility_dirty and eye.distance_squared_to(_last_eye)<=EYE_CACHE_RADIUS*EYE_CACHE_RADIUS:
		visibility_cache_hits+=1
		return
	_last_eye=eye
	_visibility_dirty=false
	var started: int=Time.get_ticks_usec()
	# Keep the existing 0.6 m shoreline inset. For cached eye motion, also
	# shrink the occluder and expand each candidate by the allowed eye radius.
	# Translating world coordinates by any cached eye delta leaves that smaller
	# sphere inside the real planet and every candidate inside its larger bound.
	var occluder: float=maxf(1.0,radius-.6-EYE_CACHE_RADIUS)
	var eye_distance: float=eye.length()
	var outside: bool=eye_distance>occluder
	var sine: float=occluder/eye_distance if outside else 0.0
	var cosine: float=sqrt(maxf(0.0,1.0-sine*sine))
	var tangent: float=sqrt(maxf(0.0,eye_distance*eye_distance-occluder*occluder))
	var toward_planet: Vector3=-eye/eye_distance if outside else Vector3.ZERO
	culled_meshes=0
	shadow_only_meshes=0
	visibility_evaluations+=1
	for record: Dictionary in _occludable:
		var visual: MeshInstance3D=(record.node as WeakRef).get_ref() as MeshInstance3D
		if not is_instance_valid(visual): continue
		if (bool(record.tile) and _overview) or (bool(record.source) and not _overview): continue
		var offset: Vector3=(record.center as Vector3)-eye
		var extent: float=float(record.radius)+EYE_CACHE_RADIUS
		var hidden: bool=false
		var far_distance: float=tangent+extent
		if outside and offset.length_squared()>far_distance*far_distance:
			var along: float=offset.dot(toward_planet)
			var sideways: float=sqrt(maxf(0.0,offset.length_squared()-along*along))
			# Signed distance to the tangent cone side, not its center ray:
			# the entire bounding sphere must clear the opaque planet.
			hidden=along*sine-sideways*cosine>extent+.001
		var shadow: int=int(record.shadow)
		# SHADOWS_ONLY cannot encode two-sided shadow casting; leave those
		# rare authored casters untouched rather than change their shadows.
		if shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED: hidden=false
		if hidden:
			culled_meshes+=1
			if shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON: shadow_only_meshes+=1
		if record.hidden==hidden: continue
		record.hidden=hidden
		# Never hide a Node3D parent (its children can extend past its AABB),
		# and never delete an offscreen caster needed by a visible receiver.
		visual.layers=0 if hidden and shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else int(record.layers)
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if hidden and shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON else shadow as GeometryInstance3D.ShadowCastingSetting
	last_visibility_usec=Time.get_ticks_usec()-started
	max_visibility_usec=maxi(max_visibility_usec,last_visibility_usec)

func metrics() -> Dictionary:
	_prune_material_cache()
	return {"mobile_render_enabled":enabled,"planet_culling_enabled":true,"planet_hidden_meshes":culled_meshes,"planet_shadow_only_meshes":shadow_only_meshes,"occlusion_candidates":_occludable.size(),"mobile_materials":_materials.size(),"mobile_tile_sources":_tile_sources.size(),"mobile_tiles_active":not _overview,"exact_tiles_active":not _overview,"visibility_tick_usec":last_visibility_usec,"max_visibility_tick_usec":max_visibility_usec,"visibility_evaluations":visibility_evaluations,"visibility_cache_hits":visibility_cache_hits,"eye_cache_radius":EYE_CACHE_RADIUS}
