extends RefCounted

# Wait on the production preparation contract rather than guessing frame counts.
# A few camera/physics fixtures intentionally disable world processing; only
# those fixtures manually advance its normal preparation function while waiting.
static func prepare_player(player: Node, tree: SceneTree, timeout_ms: int = 60000) -> bool:
	if not player.has_method("begin_prepare_visuals"):
		return true
	var previous_mode: Node.ProcessMode = player.process_mode
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.call("begin_prepare_visuals")
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not bool(player.call("visuals_ready")):
		var error: String = str(player.call("visuals_error"))
		if not error.is_empty() or Time.get_ticks_msec() > deadline:
			push_error("Fixture avatar preparation failed: " + error)
			player.process_mode = previous_mode
			return false
		player.call("step_prepare_visuals")
		await tree.process_frame
	player.process_mode = previous_mode
	return true

static func wait_roaming(world: Node, tree: SceneTree, timeout_ms: int = 60000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while bool(world.get("overview")) or bool(world.get("preparing_roam")):
		if Time.get_ticks_msec() > deadline:
			push_error("Fixture timed out waiting for roaming preparation")
			return false
		if not world.is_processing():
			world.call("_process", 1.0 / 60.0)
		await tree.process_frame
	var player: Node = world.get("player") as Node
	if player.has_method("visuals_ready") and not bool(player.call("visuals_ready")):
		push_error("Roaming became active before avatar readiness")
		return false
	return true

static func wait_room(room: Node, tree: SceneTree, timeout_ms: int = 60000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not bool(room.get("ready_for_play")):
		if Time.get_ticks_msec() > deadline:
			push_error("Fixture timed out waiting for indoor readiness")
			return false
		await tree.process_frame
	return true

static func wait_room_scene(tree: SceneTree, timeout_ms: int = 60000) -> Node3D:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() <= deadline:
		var scene: Node = tree.current_scene
		if is_instance_valid(scene):
			var script: Script = scene.get_script() as Script
			if script != null and script.resource_path == "res://scripts/training_room.gd":
				if await wait_room(scene, tree, maxi(1, deadline - Time.get_ticks_msec())):
					return scene as Node3D
				return null
		await tree.process_frame
	push_error("Fixture timed out waiting for indoor scene")
	return null
