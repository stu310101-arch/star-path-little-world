extends SceneTree

const PlayerScript: Script = preload("res://scripts/planet_player.gd")
const MusicScript: Script = preload("res://scripts/world_music.gd")
const HudScript: Script = preload("res://scripts/world_hud.gd")

class MusicHost:
	extends Node3D
	var music: Node

const OUTPUT: String = "res://../deliverables/startup-packs/lazy-avatar-music-checks.json"
var checks: Array[Dictionary] = []
var failures: int = 0
var fixture_directory: String

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": label, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var player: PlanetPlayer = PlayerScript.new() as PlanetPlayer
	player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(player)
	check("Ready creates collision and pivot without an avatar", player.visual != null and player.visual.get_child_count() == 0 and player.get_child_count() == 2)
	check("Neither original avatar is cached during initial overview", not ResourceLoader.has_cached(PlanetPlayer.WALK_MODEL) and not ResourceLoader.has_cached(PlanetPlayer.JUMP_MODEL))
	player.begin_prepare_visuals()
	check("Beginning preparation still creates no avatar", not player.visuals_ready() and player.visual.get_child_count() == 0)
	var expected_models: Array[int] = [0, 1, 1, 2, 2]
	for index: int in range(5):
		player.step_prepare_visuals()
		check("Preparation stage has bounded model construction " + str(index + 1), player.visual.get_child_count() == expected_models[index], player.get_visual_preparation_state())
		await process_frame
	check("External preparation works while player processing is disabled", player.visuals_ready() and player.process_mode == Node.PROCESS_MODE_DISABLED and player.visuals_error().is_empty())
	check("Walking and jump animation players are present", player.locomotion_animator != null and player.jump_animator != null)
	check("Landing recovery retains mapped skeleton bones", player.recovery_bones.size() > 0 and player.locomotion_skeleton != null and player.jump_skeleton != null, player.recovery_bones.size())
	for clip: StringName in [&"Walk", &"Run", &"JumpStart", &"JumpAir", &"JumpLand", &"Idle"]:
		player.set_clip(clip)
		var jumping: bool = clip in [&"JumpStart", &"JumpAir", &"JumpLand"]
		check("Original animation and visibility retained: " + String(clip), player.active_clip == clip and player.jump_model.visible == jumping and player.locomotion_model.visible != jumping)
	var before: int = player.visual.get_child_count()
	player.begin_prepare_visuals()
	player.step_prepare_visuals()
	check("Repeated preparation does not duplicate model nodes", before == player.visual.get_child_count())
	player.begin_entry()
	player.sample_entry(0.7)
	player.finish_entry()
	check("Entry and restoration preserve avatar materials and controls state", not player.entering and player.visual.visible and player.active_clip == &"Idle" and not player.entry_materials.is_empty())
	await check_music()
	world.queue_free()
	player = null
	world = null
	await process_frame
	await process_frame
	var result: Dictionary = {"passed": failures == 0, "failed": failures, "checks": checks}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var output: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	for filename: String in DirAccess.get_files_at(fixture_directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_directory.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_directory))
	print("LAZY_AVATAR_MUSIC_CHECKS ", JSON.stringify(result))
	quit(0 if failures == 0 else 1)

func check_music() -> void:
	fixture_directory = "user://lazy-music-tests-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_directory))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = 8000
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(16000)
	for index: int in range(8000):
		samples.encode_s16(index * 2, int(3000.0 * sin(TAU * 220.0 * float(index) / 8000.0)))
	stream.data = samples
	var manifest: Dictionary = {}
	for context_id: String in ["world", "counseling", "admissions", "recommendations", "wordking"]:
		var path: String = fixture_directory.path_join(context_id + ".tres")
		check("Audio fixture saved: " + context_id, ResourceSaver.save(stream, path) == OK)
		manifest[context_id] = {"title": context_id, "path": path}
	var manifest_path: String = fixture_directory.path_join("tracks.json")
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	var music: Node = MusicScript.new() as Node
	music.set("manifest_path", manifest_path)
	music.set("settings_path", fixture_directory.path_join("settings.cfg"))
	root.add_child(music)
	music.set_process(false)
	var initial: Dictionary = music.call("get_state") as Dictionary
	check("Music ready reads only manifest and settings", (initial.available_ids as Array).is_empty() and (initial.voices as Dictionary).is_empty())
	music.call("_process", 0.1)
	check("Frames before explicit startup gate do not load music", (music.call("get_state").available_ids as Array).is_empty())
	music.call("begin_prepare_music")
	check("Opening music gate queues without synchronous audio loading", (music.call("get_state").available_ids as Array).is_empty())
	music.call("_process", 0.1)
	var first: Dictionary = music.call("get_state") as Dictionary
	check("Only the selected world track is loaded", first.available_ids == ["world"] and first.context == "world" and (first.voices as Dictionary).size() == 1)
	music.call("_process", 2.0)
	await create_timer(0.06).timeout
	var starts: int = int(music.call("get_state").voices.world.starts)
	for _index: int in range(5):
		music.call("set_context", "world")
		music.call("unlock")
	check("Repeated context does not restart existing playback", int(music.call("get_state").voices.world.starts) == starts)
	music.call("set_context", "admissions")
	var waiting: Dictionary = music.call("get_state") as Dictionary
	check("Changing context preserves old audio until new stream is ready", waiting.context == "world" and waiting.pending_context == "admissions" and (waiting.available_ids as Array).size() == 1)
	music.call("_process", 0.1)
	var second: Dictionary = music.call("get_state") as Dictionary
	check("Next frame loads one requested stream and begins crossfade", second.context == "admissions" and (second.available_ids as Array).size() == 2 and bool(second.transitioning))
	music.call("_process", 2.0)
	await create_timer(0.06).timeout
	check("Completed fade retires prior voice", not bool(music.call("get_state").voices.world.playing) and bool(music.call("get_state").voices.admissions.playing))
	music.call("set_context", "counseling")
	music.call("set_context", "wordking")
	music.call("_process", 0.1)
	check("Rapid context change avoids loading superseded track", not (music.call("get_state").available_ids as Array).has("counseling") and music.call("get_state").context == "wordking")
	music.call("set_context", "recommendations")
	music.call("set_background_paused", true)
	music.call("_process", 0.1)
	check("Background suspension defers stream construction", not (music.call("get_state").available_ids as Array).has("recommendations"))
	music.call("set_background_paused", false)
	music.call("_process", 0.1)
	check("Returning foreground prepares the pending context", music.call("get_state").context == "recommendations")
	music.call("set_context", "unknown")
	check("Unknown context reuses already loaded world fallback", music.call("get_state").context == "world" and bool(music.call("get_state").fallback))
	check_music_retry_controls(music)
	music.queue_free()
	music = null
	await process_frame
	await create_timer(0.08).timeout

func check_music_retry_controls(music: Node) -> void:
	# Reproduce a failed district download followed by a healthy cached track.
	# The music fixture remains deterministic; no network failure is simulated.
	var errors: Dictionary = music.get("_load_errors") as Dictionary
	errors["counseling"] = "Fixture: prior district download failed"
	music.call("set_muted", false)
	var host: MusicHost = MusicHost.new()
	host.music = music
	var hud: CanvasLayer = HudScript.new() as CanvasLayer
	hud.set("world", host)
	var music_button: Button = Button.new()
	hud.set("music_button", music_button)
	hud.add_child(music_button)
	for field: String in ["music_title", "music_percent"]:
		var text_label: Label = Label.new()
		hud.set(field, text_label)
		hud.add_child(text_label)
	var slider: HSlider = HSlider.new()
	hud.set("music_slider", slider)
	hud.add_child(slider)
	music_button.pressed.connect(Callable(hud, "_activate_music_button"))
	hud.call("refresh_music_controls")
	check("Historical district music error does not replace healthy mute control", music_button.text == "音樂：開" and music.call("get_state").pending_context == "")
	music_button.pressed.emit()
	check("Healthy track can still be muted after another district failed", bool(music.call("get_state").muted) and errors.has("counseling"))
	music.call("set_context", "counseling")
	hud.call("refresh_music_controls")
	check("Currently pending failed music exposes retry control", music_button.text == "重試音樂" and music.call("get_state").pending_context == "counseling")
	music_button.pressed.emit()
	hud.call("refresh_music_controls")
	check("Retry clears only pending failure without changing mute preference", not errors.has("counseling") and bool(music.call("get_state").muted) and music_button.text == "音樂：靜音")
	hud.free()
	host.free()
