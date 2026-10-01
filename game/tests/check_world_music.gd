extends SceneTree

const Music = preload("res://scripts/world_music.gd")
const OUTPUT: String = "res://../deliverables/music-integration/manager-tests.json"
const IDS: Array[String] = ["world", "counseling", "admissions", "recommendations", "wordking"]

var checks: Array[Dictionary] = []
var failures: int = 0
var temporary_directory: String = ""
var production_state: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": label, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func write_json(resource_path: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(resource_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))

func new_manager(manifest: String, settings: String) -> Node:
	var manager: Node = Music.new() as Node
	manager.set("manifest_path", manifest)
	manager.set("settings_path", settings)
	root.add_child(manager)
	manager.set_process(false)
	manager.call("begin_prepare_music")
	manager.call("_process", 0.0)
	return manager

func state(manager: Node) -> Dictionary:
	return manager.call("get_state") as Dictionary

func advance(manager: Node, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var step: float = minf(remaining, 1.0 / 60.0)
		manager.call("_process", step)
		remaining -= step

func gain_sum(snapshot: Dictionary) -> float:
	var total: float = 0.0
	for voice: Dictionary in (snapshot.voices as Dictionary).values():
		total += float(voice.gain)
	return total

func live_count(snapshot: Dictionary) -> int:
	var count: int = 0
	for voice: Dictionary in (snapshot.voices as Dictionary).values():
		if bool(voice.playing):
			count += 1
	return count

func gains_equal(first: Dictionary, second: Dictionary) -> bool:
	for context_id: String in first.voices:
		if not is_equal_approx(float(first.voices[context_id].gain), float(second.voices[context_id].gain)):
			return false
	return true

func create_fixture() -> String:
	temporary_directory = "user://music-tests-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temporary_directory))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = 16000
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(32000)
	for index: int in range(16000):
		samples.encode_s16(index * 2, int(3000.0 * sin(TAU * 220.0 * float(index) / 8000.0)))
	stream.data = samples
	var audio_path: String = temporary_directory + "/fixture.tres"
	check("Test fixture is saved", ResourceSaver.save(stream, audio_path) == OK)
	var catalog: Dictionary = {}
	for context_id: String in IDS:
		catalog[context_id] = {"title": context_id + " fixture", "path": audio_path}
	var catalog_path: String = temporary_directory + "/tracks.json"
	write_json(catalog_path, catalog)
	return catalog_path

func run() -> void:
	var manifest: String = create_fixture()
	var settings: String = temporary_directory + "/settings.cfg"
	var manager: Node = new_manager(manifest, settings)
	var first: Dictionary = state(manager)
	check("Native playback unlocks automatically", bool(first.unlocked))
	check("Default volume is 40 percent and not muted", is_equal_approx(float(first.volume), 0.4) and not bool(first.muted))
	check("Only initial context loads; remaining tracks stay lazy", (first.available_ids as Array) == ["world"] and (first.missing_ids as Array).is_empty())
	check("Only the world voice starts initially", str(first.context) == "world" and live_count(first) == 1)
	advance(manager, 2.0)
	for context_id: String in IDS:
		manager.call("set_context", context_id)
		advance(manager, 2.0)
		var mapped: Dictionary = state(manager)
		check("Context selects its own stream: " + context_id, str(mapped.context) == context_id and str(mapped.title) == context_id + " fixture" and not bool(mapped.fallback), mapped)
		check("Crossfade retires outgoing voices: " + context_id, live_count(mapped) == 1 and is_equal_approx(gain_sum(mapped), 1.0))
	manager.call("set_context", "world")
	advance(manager, 2.0)
	await create_timer(0.15).timeout
	var before_same: Dictionary = state(manager)
	for _count: int in range(30):
		manager.call("set_context", "world")
		manager.call("unlock")
	var after_same: Dictionary = state(manager)
	check("Repeated context/unlock never restart the track", int(before_same.voices.world.starts) == int(after_same.voices.world.starts) and not bool(after_same.transitioning), after_same.voices.world)
	check("Repeated context preserves the audio playback position", absf(float(before_same.voices.world.position) - float(after_same.voices.world.position)) < 0.03)
	var rapid_contexts: Array[String] = ["admissions", "wordking", "counseling", "recommendations", "world"]
	var continuous: bool = true
	var bounded_mix: bool = true
	var world_starts: int = int(after_same.voices.world.starts)
	for context_id: String in rapid_contexts:
		var prior: Dictionary = state(manager)
		manager.call("set_context", context_id)
		continuous = continuous and gains_equal(prior, state(manager))
		advance(manager, 0.18)
		bounded_mix = bounded_mix and gain_sum(state(manager)) <= 1.00001
	check("Rapid transitions rebase at existing audible gains", continuous)
	check("Rapid transitions do not build an over-full music mix", bounded_mix)
	check("Returning to a fading voice keeps its playback phase", int(state(manager).voices.world.starts) == world_starts)
	advance(manager, 2.0)
	check("Rapid transition converges to one current voice", live_count(state(manager)) == 1 and is_equal_approx(float(state(manager).voices.world.gain), 1.0))
	manager.call("set_muted", true)
	manager.call("unlock")
	var bus: int = AudioServer.get_bus_index("Music")
	var before_mute: Dictionary = state(manager)
	check("Mute controls only the Music bus", AudioServer.is_bus_mute(bus) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	check("Further interactions never undo an explicit mute", bool(before_mute.muted))
	manager.call("set_muted", false)
	check("Unmute does not restart the track", not AudioServer.is_bus_mute(bus) and int(state(manager).voices.world.starts) == int(before_mute.voices.world.starts))
	manager.call("set_music_volume", 0.0)
	check("Zero volume is silent with finite bus gain", AudioServer.is_bus_mute(bus) and is_finite(AudioServer.get_bus_volume_db(bus)))
	manager.call("set_music_volume", 0.23)
	check("Slider volume maps to logarithmic bus volume", not AudioServer.is_bus_mute(bus) and absf(db_to_linear(AudioServer.get_bus_volume_db(bus)) - 0.23) < 0.00001)
	manager.call("set_music_volume", NAN)
	check("Invalid slider values leave valid volume intact", is_equal_approx(float(state(manager).volume), 0.23))
	manager.call("set_music_volume", 2.0)
	check("Out-of-range slider values are safely clamped", is_equal_approx(float(state(manager).volume), 1.0))
	manager.call("set_music_volume", 0.23)
	manager.call("set_muted", true)
	manager.call("set_context", "admissions")
	advance(manager, 0.3)
	manager.call("set_background_paused", true)
	await create_timer(0.10).timeout
	var paused_before: Dictionary = state(manager)
	advance(manager, 5.0)
	await create_timer(0.12).timeout
	var paused_after: Dictionary = state(manager)
	var positions_stable: bool = true
	for context_id: String in paused_before.voices:
		positions_stable = positions_stable and absf(float(paused_before.voices[context_id].position) - float(paused_after.voices[context_id].position)) < 0.015
	check("Background suspension freezes both gains and playback", gains_equal(paused_before, paused_after) and positions_stable, {"before": paused_before, "after": paused_after})
	manager.call("set_context", "world")
	manager.call("set_context", "admissions")
	check("Context changes while backgrounded retain paused voice phases", int(state(manager).voices.world.starts) == int(paused_before.voices.world.starts) and int(state(manager).voices.admissions.starts) == int(paused_before.voices.admissions.starts))
	manager.call("set_background_paused", false)
	advance(manager, 2.0)
	check("Foreground resumes the interrupted fade without restart", int(state(manager).voices.admissions.starts) == int(paused_before.voices.admissions.starts) and live_count(state(manager)) == 1)
	manager.free()
	var restored: Node = new_manager(manifest, settings)
	check("Mute and volume survive manager recreation", bool(state(restored).muted) and is_equal_approx(float(state(restored).volume), 0.23) and int(state(restored).settings_error) == OK)
	restored.free()
	var missing_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest)) as Dictionary
	missing_catalog.admissions.path = temporary_directory + "/missing.ogg"
	var missing_manifest: String = temporary_directory + "/missing-tracks.json"
	write_json(missing_manifest, missing_catalog)
	var fallback: Node = new_manager(missing_manifest, settings)
	fallback.call("set_context", "admissions")
	advance(fallback, 0.05)
	var fallback_state: Dictionary = state(fallback)
	check("Missing track falls back honestly to the world stream", str(fallback_state.context) == "world" and str(fallback_state.requested_context) == "admissions" and bool(fallback_state.fallback) and "admissions" in (fallback_state.missing_ids as Array), fallback_state)
	fallback.call("set_context", "nonexistent")
	check("Unknown station IDs do not stop a valid fallback track", str(state(fallback).context) == "world")
	fallback.free()
	var empty_manifest: String = temporary_directory + "/empty.json"
	write_json(empty_manifest, {})
	var empty: Node = new_manager(empty_manifest, settings)
	empty.call("set_context", "wordking")
	advance(empty, 2.0)
	check("Absent catalog remains silent and reports every missing track", str(state(empty).context).is_empty() and live_count(state(empty)) == 0 and (state(empty).missing_ids as Array).size() == 5)
	empty.free()
	await check_production_assets()
	await create_timer(0.1).timeout
	finish()

func check_production_assets() -> void:
	var required: bool = OS.get_cmdline_user_args().has("--require-all-music")
	var manager: Node = new_manager("res://data/music_tracks.json", temporary_directory + "/production-settings.cfg")
	for context_id: String in IDS:
		manager.call("set_context", context_id)
		advance(manager, 0.05)
		if not (state(manager).available_ids as Array).has(context_id):
			continue
		# Let AudioServer consume the playback registration before teardown.
		# Starting and freeing every Ogg in one frame leaves pending mixers.
		await create_timer(0.06).timeout
		var snapshot: Dictionary = state(manager)
		var voice: AudioStreamPlayer = manager.get_node("Music_" + context_id) as AudioStreamPlayer
		var stream: AudioStreamOggVorbis = voice.stream as AudioStreamOggVorbis
		check("Production mapping uses its own Ogg: " + context_id, str(snapshot.context) == context_id and stream != null and str(snapshot.path).ends_with(".ogg"), snapshot.path)
		if stream == null:
			continue
		check("Production track is a full looping music cue: " + context_id, stream.loop and stream.get_length() >= 30.0, stream.get_length())
		var playback: AudioStreamPlayback = stream.instantiate_playback()
		playback.start(stream.get_length() - 0.02)
		var audio_frames: PackedVector2Array = playback.mix_audio(1.0, 8192)
		check("Actual Ogg decoder crosses its loop boundary: " + context_id, playback.get_loop_count() > 0 and audio_frames.size() == 8192, {"loops": playback.get_loop_count(), "position": playback.get_playback_position(), "frames": audio_frames.size()})
		playback.stop()
	production_state = state(manager)
	if required:
		check("All five real generated music assets load on demand", (production_state.available_ids as Array).size() == 5 and (production_state.missing_ids as Array).is_empty(), production_state)
	manager.free()

func finish() -> void:
	var result: Dictionary = {"passed": failures == 0, "failed": failures, "checks": checks, "production": production_state}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	write_json(OUTPUT, result)
	var temporary_absolute: String = ProjectSettings.globalize_path(temporary_directory)
	for filename: String in DirAccess.get_files_at(temporary_directory):
		DirAccess.remove_absolute(temporary_absolute.path_join(filename))
	DirAccess.remove_absolute(temporary_absolute)
	print(JSON.stringify(result))
	quit(0 if failures == 0 else 1)
