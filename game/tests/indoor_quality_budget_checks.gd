extends SceneTree

## Exercise real room creation and shared-setting signals without downloading
## detail models. Light construction must obey the profile before those arrive.
const OUTPUT: String = "res://../deliverables/low-end/indoor-quality-budget-checks.json"

class SettingsFixture:
	extends Node
	signal state_changed
	var profile: String = "standard"
	var pressured: bool = false
	func is_low_quality() -> bool:
		return profile in ["mobile", "balanced", "low"]
	func is_constrained_runtime() -> bool:
		return pressured
	func select(value: String) -> void:
		profile = value
		state_changed.emit()

var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": label, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func light_state(room: Node3D, names: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for name: String in names:
		var light: Light3D = room.get_node_or_null(name) as Light3D
		result[name] = {"exists": light != null, "shadow": light.shadow_enabled if light != null else false,
			"energy": light.light_energy if light != null else 0.0, "color": str(light.light_color) if light != null else ""}
	return result

func run() -> void:
	var settings: SettingsFixture = SettingsFixture.new()
	root.add_child(settings)
	for spec: Dictionary in [
		{"script": "res://scripts/admissions_room.gd", "lights": ["WindowDaylight", "StudioCeilingFill"]},
		{"script": "res://scripts/training_room.gd", "lights": ["DownwardCeilingLight"]},
		{"script": "res://scripts/university_hall.gd", "lights": ["LibraryDaylight", "ExhibitInspectionLight"]},
	]:
		settings.select("standard")
		var room: Node3D = (load(str(spec.script)) as Script).new() as Node3D
		room.set("graphics_settings", settings)
		room.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(room)
		var names: Array[String] = []
		names.assign(spec.lights)
		var original: Dictionary = light_state(room, names)
		for name: String in names:
			check(str(spec.script) + " creates standard shadow " + name, bool(original[name].exists) and bool(original[name].shadow), original[name])
		for profile: String in ["mobile", "balanced", "low", "standard"]:
			settings.select(profile)
			var state: Dictionary = light_state(room, names)
			for name: String in names:
				check(str(spec.script) + " applies " + profile + " to " + name, bool(state[name].shadow) == (profile == "standard"), state[name])
				check(str(spec.script) + " preserves authored light in " + profile + ": " + name, state[name].energy == original[name].energy and state[name].color == original[name].color, state[name])
		settings.pressured = true
		settings.select("standard")
		var pressured_state: Dictionary = light_state(room, names)
		for name: String in names:
			check(str(spec.script) + " runtime pressure removes shadow " + name, not bool(pressured_state[name].shadow), pressured_state[name])
		settings.pressured = false
		settings.select("standard")
		# Independently opened rooms must use the root viewport's full profile
		# vocabulary when no shared settings service was supplied.
		settings.disconnect("state_changed", Callable(room, "_apply_quality"))
		room.set("graphics_settings", null)
		for profile: String in ["mobile", "balanced", "low", "standard"]:
			root.set_meta("graphics_quality_profile", profile)
			room.call("_apply_quality")
			var state: Dictionary = light_state(room, names)
			for name: String in names:
				check(str(spec.script) + " standalone " + profile + ": " + name, bool(state[name].shadow) == (profile == "standard"), state[name])
		room.set("graphics_settings", settings)
		settings.connect("state_changed", Callable(room, "_apply_quality"))
		root.remove_child(room)
		check(str(spec.script) + " releases settings listener on exit", settings.get_signal_connection_list("state_changed").is_empty())
		room.free()
	root.remove_meta("graphics_quality_profile")
	settings.free()
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	FileAccess.open(OUTPUT, FileAccess.WRITE).store_string(JSON.stringify({"passed": failures == 0, "failed": failures, "checks": checks}, "\t"))
	print("INDOOR_QUALITY_BUDGET_CHECKS checks=", checks.size(), " failures=", failures)
	quit(1 if failures > 0 else 0)
