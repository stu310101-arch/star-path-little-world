extends SceneTree

const PlayerScript = preload("res://scripts/planet_player.gd")
const IndoorScript = preload("res://scripts/indoor_player.gd")
const DT: float = 1.0 / 60.0
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func fixture(script: Script) -> PlanetPlayer:
	# Minimal real AnimationPlayers isolate timing/selection from asset loading.
	# The separate animation_sampling_checks exercise delivered bones and cloth.
	var actor: PlanetPlayer = script.new() as PlanetPlayer
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(actor)
	actor.locomotion_model = Node3D.new()
	actor.visual.add_child(actor.locomotion_model)
	actor.locomotion_animator = AnimationPlayer.new()
	actor.locomotion_model.add_child(actor.locomotion_animator)
	actor.locomotion_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library: AnimationLibrary = AnimationLibrary.new()
	for label: StringName in [&"Idle", &"Walk", &"Run"]:
		var animation: Animation = Animation.new()
		animation.length = 1.2 if label == &"Walk" else 0.8 if label == &"Run" else 1.0
		animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(label, animation)
	actor.locomotion_animator.add_animation_library(&"", library)
	actor._cache_animation_parts(actor.locomotion_model, actor.locomotion_animator, actor._locomotion_meshes, actor._locomotion_clips)
	actor.jump_model = Node3D.new()
	actor.visual.add_child(actor.jump_model)
	actor.jump_animator = AnimationPlayer.new()
	actor.jump_model.add_child(actor.jump_animator)
	actor.jump_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var jump_library: AnimationLibrary = AnimationLibrary.new()
	for label: StringName in [&"JumpStart", &"JumpAir", &"JumpLand"]:
		var animation: Animation = Animation.new()
		animation.length = 1.2
		jump_library.add_animation(label, animation)
	actor.jump_animator.add_animation_library(&"", jump_library)
	actor._cache_animation_parts(actor.jump_model, actor.jump_animator, actor._jump_meshes, actor._jump_clips)
	actor.recovery_bones.append(Vector2i(0, 0))
	actor.set_clip(&"Idle")
	return actor

func run() -> void:
	var actor: PlanetPlayer = fixture(PlayerScript)
	actor.speed_matched_locomotion = true
	actor.walk_speed = 9.5
	actor.run_speed = 13.5
	actor.update_motion_animation(DT, actor.walk_speed, false)
	check(actor.active_clip == &"Run", "Outdoor ordinary travel selects Run without holding the run button")
	check(is_equal_approx(actor.animation_clock, DT * 9.5 / 3.8), "Outdoor normal travel advances the authored run stride at 2.5x without the old cap")
	var before: float = actor.animation_clock
	actor.update_motion_animation(DT, actor.run_speed, true)
	check(is_equal_approx(actor.animation_clock - before, DT * 13.5 / 3.8), "Faster running uses actual travelled speed and the Run calibration")
	actor.update_motion_animation(DT, 0.0, true)
	check(actor.active_clip == &"Idle", "A blocked character idles even with run held")
	actor.update_motion_animation(DT, actor.walk_speed * 0.25, false)
	check(actor.active_clip == &"Walk", "Quarter joystick travel retains Walk")
	check(is_equal_approx(actor.animation_clock, DT * 2.375 / 2.2), "Low analog travel retains proportional walk playback")
	actor.update_motion_animation(DT, 2.375, true)
	check(actor.active_clip == &"Walk", "Actual low travel speed controls gait even while run is held")
	actor.update_motion_animation(DT, 4.75, false)
	check(actor.active_clip == &"Run", "Half outdoor joystick selects the faster gait")
	actor.update_motion_animation(DT, 4.1, false)
	check(actor.active_clip == &"Run", "Gait hysteresis retains Run during small deceleration")
	actor.update_motion_animation(DT, 3.7, false)
	check(actor.active_clip == &"Walk", "Deceleration below the exit threshold restores Walk")
	actor.update_motion_animation(DT, 4.1, false)
	check(actor.active_clip == &"Walk", "Gait hysteresis retains Walk during small acceleration")
	actor.animation_clock = 0.6
	actor.update_motion_animation(0.0, 9.5, false)
	check(is_equal_approx(actor.animation_clock, 0.4), "Changing gait preserves half-stride phase across different loop lengths")
	actor.jump_state = &"landing"
	actor.landing_clock = 0.6
	actor.update_motion_animation(DT, 9.5, false)
	check(actor.active_clip == &"JumpLand" and actor.recovery_clip == &"Run", "Landing keeps its cloth clip and recovers into the actual outdoor gait")
	check(is_equal_approx(actor.recovery_clock, DT * 9.5 / 3.8), "Landing body recovery uses the same uncapped run stride speed")
	actor.recovery_clock = 0.4
	actor.update_motion_animation(0.0, 2.2, false)
	check(actor.recovery_clip == &"Walk" and is_equal_approx(actor.recovery_clock, 0.6), "Landing gait changes retain stride phase")
	actor.update_motion_animation(0.0, 9.5, false)
	before = actor.recovery_clock
	actor.jump_state = &"grounded"
	actor.update_motion_animation(DT, 9.5, false)
	check(actor.active_clip == &"Run" and is_equal_approx(actor.animation_clock, before + DT * 9.5 / 3.8), "Finishing landing retains recovery phase at the faster speed")
	actor.jump_state = &"airborne"
	actor.jump_clock = 0.5
	actor.flip_progress = 0.35
	actor.update_motion_animation(DT, 13.5, true)
	check(actor.active_clip == &"JumpAir" and is_equal_approx(actor._animation_sample_time, 0.42), "Fast traversal does not retime the physics-driven flip")
	actor.free()
	var indoor: PlanetPlayer = fixture(IndoorScript)
	check(not indoor.speed_matched_locomotion and indoor.walk_speed == 3.8 and indoor.run_speed == 6.4, "Indoor defaults remain unchanged")
	indoor.update_motion_animation(DT, 3.8, false)
	check(indoor.active_clip == &"Walk" and is_equal_approx(indoor.animation_clock, DT * 3.8 / 2.2), "Indoor ordinary gait and playback remain unchanged")
	indoor.update_motion_animation(DT, 0.5, true)
	check(indoor.active_clip == &"Run" and is_equal_approx(indoor.animation_clock, DT * 0.5 / 3.8), "Indoor run input retains its previous selection at low analog speed")
	before = indoor.animation_clock
	indoor.update_motion_animation(DT, 20.0, true)
	check(is_equal_approx(indoor.animation_clock - before, DT * 2.2), "Indoor keeps the original defensive animation cap")
	indoor.free()
	print("OUTDOOR_LOCOMOTION_CHECKS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
