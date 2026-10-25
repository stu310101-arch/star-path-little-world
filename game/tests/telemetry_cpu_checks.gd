extends SceneTree

const Telemetry = preload("res://scripts/performance_telemetry.gd")
const Packs = preload("res://scripts/web_packs.gd")

class StateNode:
	extends Node
	var values: Dictionary = {}
	func metrics() -> Dictionary:
		return values.duplicate(true)
	func stats() -> Dictionary:
		return values.duplicate(true)
	func get_state() -> Dictionary:
		return values.duplicate(true)

class MapStub:
	extends Control
	func metrics() -> Dictionary:
		return {"map_draws":20,"last_draw_ms":3.2}

class HudStub:
	extends Control
	var minimap: Control
	var graphics_settings: StateNode
	var destination_card: Control
	func is_settings_open() -> bool:
		return false
	func is_full_map_open() -> bool:
		return false

class WorldStub:
	extends Node3D
	var hud: HudStub
	var player: PlanetPlayer
	var music: Node
	var streaming: StateNode
	var camera_obstruction: StateNode
	var overview: bool = false
	var paused: bool = false
	var entering: bool = false
	var preparing_roam: bool = false
	var nearest_id: String = ""

class TimerProbe:
	extends "res://scripts/performance_telemetry.gd"
	var snapshots: int = 0
	func _ready() -> void:
		set_process(false)
	func snapshot() -> Dictionary:
		snapshots += 1
		return {}

var failures: int = 0
var checks: Array[Dictionary] = []
var report: Dictionary = {"scope":"Native headless CPU only. Representative 60-button HUD fixture; no GPU synchronization, browser JS execution, real transport or avatar animation cost measured."}

func _initialize() -> void:
	call_deferred("run")

func check(title: String, passed: bool) -> void:
	checks.append({"test":title,"passed":passed})
	if not passed:
		failures += 1
		push_error(title)

func measure(label: String, callback: Callable, iterations: int) -> void:
	var samples: Array[int] = []
	for batch: int in range(9):
		var started: int = Time.get_ticks_usec()
		for repeat: int in range(iterations):
			callback.call()
		samples.append(Time.get_ticks_usec() - started)
	samples.sort()
	report[label] = {"batches":samples.size(),"iterations_per_batch":iterations,"median_usec_per_call":float(samples[4])/iterations,"max_usec_per_call":float(samples.back())/iterations}

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Use --headless; this probe must not initialize a GPU.")
		quit(1)
		return
	root.size = Vector2i(1280,800)
	var world: WorldStub = WorldStub.new()
	world.player = PlanetPlayer.new()
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(world.player)
	world.music = Node.new()
	world.add_child(world.music)
	world.streaming = StateNode.new()
	world.add_child(world.streaming)
	world.camera_obstruction = StateNode.new()
	world.add_child(world.camera_obstruction)
	world.hud = HudStub.new()
	world.add_child(world.hud)
	world.hud.minimap = MapStub.new()
	world.hud.minimap.size = Vector2(246,180)
	world.hud.add_child(world.hud.minimap)
	world.hud.graphics_settings = StateNode.new()
	world.hud.graphics_settings.values = {"ui_pixels":[1280,800],"internal_3d_pixels":[1280,800],"scaling_3d_scale":1.0,"applied_msaa":1}
	world.hud.add_child(world.hud.graphics_settings)
	world.hud.destination_card = Control.new()
	world.hud.add_child(world.hud.destination_card)
	var container: Control = world.hud
	for depth: int in range(4):
		var next: Control = Control.new()
		next.size = Vector2(1280,800)
		next.clip_contents = true
		container.add_child(next)
		container = next
	for index: int in range(60):
		var button: Button = Button.new()
		button.name = "Action" + str(index)
		button.text = "工作桌 " + str(index)
		button.position = Vector2((index%6)*150,(index/6)*45)
		button.size = Vector2(140,40)
		container.add_child(button)
	root.add_child(world)
	var telemetry: Node = Telemetry.new()
	world.add_child(telemetry)
	telemetry.set_process(false)
	check("Non-opt-in telemetry starts disabled", not bool(telemetry.enabled))
	check("Non-opt-in startup does not query adapter metadata", (telemetry.get("_renderer_metadata") as Dictionary).is_empty())
	var first: Dictionary = telemetry.call("snapshot")
	check("Snapshot identifies rendering method/driver/adapter without extra JS", (first.renderer as Dictionary).has_all(["method","driver","adapter_name","adapter_vendor","adapter_api_version","display_server"]))
	check("Headless empty adapter is reported, not relabeled as a real GPU", str(first.renderer.display_server) == "headless" and str(first.renderer.adapter_name).is_empty())
	first.renderer["adapter_name"] = "caller mutation"
	check("Returned renderer metadata does not mutate its static cache", str((telemetry.call("renderer_metadata") as Dictionary).adapter_name).is_empty())
	world.hud.graphics_settings.values = {"ui_pixels":[960,600],"internal_3d_pixels":[720,450],"scaling_3d_scale":.75,"applied_msaa":2}
	var changed: Dictionary = telemetry.call("snapshot")
	check("Resize/scale/MSAA remain live while adapter metadata stays cached", changed.render_target.ui_pixels == [960,600] and changed.render_target.scale == .75 and changed.render_target.msaa == 2 and changed.renderer == (telemetry.call("renderer_metadata") as Dictionary))
	measure("full_snapshot", telemetry.snapshot,100)
	measure("snapshot_json_encoding", func(): JSON.stringify(changed),100)
	measure("cached_renderer_metadata", telemetry.renderer_metadata,1000)
	var timer: TimerProbe = TimerProbe.new()
	root.add_child(timer)
	var sample_clock: Array[int] = [1000000]
	measure("frame_sampler_with_1hz_empty_snapshot",func():
		sample_clock[0] += 16667
		timer._record_frame(sample_clock[0]),1000)
	var packs: Node = Packs.new()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../build/web/index.packs.json")) as Dictionary
	check("CPU pack fixture uses an existing export manifest", not (manifest.get("packs",{}) as Dictionary).is_empty())
	packs.set("_packs",manifest.get("packs",{}))
	var startup_ids: Array[String] = []
	var states: Dictionary = {}
	var completed: Dictionary = {}
	for id: String in manifest.get("packs",{}):
		states[id] = "ready"
		if bool(manifest.packs[id].get("startup",true)):
			startup_ids.append(id)
		completed[id] = {"started_ms":10,"ready_ms":200,"hash_ms":4,"bytes":manifest.packs[id].bytes}
	packs.set("_states",states)
	packs.set("_startup_ids",startup_ids)
	packs.set("_completed",completed)
	measure("completed_pack_get_status_without_web_bridge",packs.get_status,100)
	report["pack_count"] = states.size()
	report["telemetry_json_bytes"] = JSON.stringify(changed).to_utf8_buffer().size()
	report["renderer"] = telemetry.call("renderer_metadata")
	report["source_sha256"] = FileAccess.get_sha256("res://scripts/performance_telemetry.gd")
	report["checks"] = checks
	report["failures"] = failures
	var output: FileAccess = FileAccess.open("res://../deliverables/performance-20261020/telemetry-cpu.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print("TELEMETRY_CPU ", JSON.stringify(report))
	packs.free()
	timer.free()
	world.free()
	quit(0 if failures == 0 else 1)
