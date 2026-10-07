extends SceneTree

const Stub: Script = preload("res://tests/staged_room_pack_stub.gd")
const Fixture: Script = preload("res://tests/startup_fixture.gd")
var checks: Array[Dictionary] = []
var failures: int = 0
var room: Node3D
var stub: Node

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": label, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(label)

func create_room() -> Node3D:
	var result: Node3D = (load("res://scenes/training_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(result)
	current_scene = result
	return result

func tick(count: int) -> void:
	for index: int in range(count):
		await process_frame

func run() -> void:
	var real_packs: Node = root.get_node_or_null("WebPacks")
	if real_packs != null:
		real_packs.name = "OriginalPacks"
	stub = Stub.new()
	stub.name = "WebPacks"
	root.add_child(stub)
	check("No room detail request exists before room entry", int(stub.get("requests")) == 0)
	room = create_room()
	check("Room entry requests only its details", int(stub.get("requests")) == 1)
	check("Light room can finish player preparation while detail is pending", await Fixture.wait_room(room, self))
	var art: Node3D = room.get("room_model") as Node3D
	check("Detail stays pending instead of loading from local source", str(room.get("detail_state")) == "waiting")
	check("Basic floor and wall collision already exists", room.get_node_or_null("Floor") != null and room.get_node_or_null("WestWall") != null)
	var player: CharacterBody3D = room.get("player") as CharacterBody3D
	await tick(30)
	check("Player is supported in lightweight scene", player.is_on_floor())
	var props: Node = room.get("furniture_actions") as Node
	check("Painting inspection has a lightweight texture", props.call("_painting_texture") != null)
	var router: Node = room.get("interactions") as Node
	var count: int = (router.get("targets") as Array).size()
	check("Interaction identities are available before detailed pack", count > 10, count)
	stub.set("failed", true)
	await tick(4)
	check("Failure retains usable light room", str(room.get("detail_state")) == "error" and bool(room.get("ready_for_play")))
	room.call("_retry_details")
	await tick(4)
	check("Retry preserves safe scene and resumes loading", str(room.get("detail_state")) == "waiting" and not bool(stub.get("failed")))
	var original_nodes: Dictionary = {}
	for node: Node in art.find_children("*", "MeshInstance3D", true, false):
		original_nodes[node.get_instance_id()] = (node as Node3D).global_transform
	stub.set("pack_complete", true)
	var deadline: int = Time.get_ticks_msec() + 30000
	while str(room.get("detail_state")) not in ["ready", "error"] and Time.get_ticks_msec() < deadline:
		await process_frame
	check("Full meshes finish progressively", str(room.get("detail_state")) == "ready", room.get("detail_error"))
	var same: bool = true
	for node: Node in art.find_children("*", "MeshInstance3D", true, false):
		same = same and original_nodes.has(node.get_instance_id()) and (node as Node3D).global_transform.is_equal_approx(original_nodes.get(node.get_instance_id(), Transform3D.IDENTITY) as Transform3D)
	check("Replacement retains node IDs and transforms", same)
	check("Replacement retains interaction identities", count == (router.get("targets") as Array).size())
	check("Replacement releases light mesh lookup and pending references", (room.get("detail_nodes") as Dictionary).is_empty() and room.get("pending_mesh") == null)
	var first_id: int = room.get_instance_id()
	room.queue_free()
	await tick(3)
	check("Leaving frees the entire room instance", not is_instance_id_valid(first_id))
	stub.set("pack_complete", false)
	room = create_room()
	await tick(4)
	var late_id: int = room.get_instance_id()
	room.queue_free()
	await tick(3)
	stub.set("pack_complete", true)
	await tick(8)
	check("Late completion cannot apply into the removed room", not is_instance_id_valid(late_id))
	room = create_room()
	await Fixture.wait_room(room, self)
	deadline = Time.get_ticks_msec() + 30000
	while str(room.get("detail_state")) != "ready" and Time.get_ticks_msec() < deadline:
		await process_frame
	check("Reentry reuses mounted data without a new network job", int(stub.get("requests")) == 1 and str(room.get("detail_state")) == "ready")
	var result: Dictionary = {"passed": failures == 0, "failures": failures, "checks": checks, "note": "Native lifecycle test with controlled pack readiness. Browser request timing is separately tested in final exported Web build."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/low-memory"))
	var file: FileAccess = FileAccess.open("res://../deliverables/low-memory/staged-room-checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("STAGED_ROOM_CHECKS checks=", checks.size(), " failures=", failures)
	quit(1 if failures > 0 else 0)
