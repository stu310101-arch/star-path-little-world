extends SceneTree

const PlayerScript: Script = preload("res://scripts/planet_player.gd")
const IndoorScript: Script = preload("res://scripts/indoor_player.gd")
const DT: float = 1.0 / 60.0
const OUTPUT: String = "res://../deliverables/performance/animation-sampling-checks.json"
var checks: Array[Dictionary] = []
var failures: int = 0
var world: Node3D
var player: PlanetPlayer
var reference: PlanetPlayer

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": label, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func prepare(script: Script) -> PlanetPlayer:
	var actor: PlanetPlayer = script.new() as PlanetPlayer
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(actor)
	actor.begin_prepare_visuals()
	for index: int in range(5):
		actor.step_prepare_visuals()
	actor.sample_motion_animation()
	return actor

func advance_pair(speed: float, running: bool = false) -> void:
	player.update_motion_animation(DT, speed, running)
	reference.update_motion_animation(DT, speed, running)
	# The comparison applies every physics pose, as the original schedule did.
	reference.sample_motion_animation()

func compare_pose(label: String) -> void:
	player.sample_motion_animation()
	var error: float = 0.0
	# Only the rendered model must match; the inactive rig can retain an older pose.
	var target: Skeleton3D = player.jump_skeleton if player.jump_model.visible else player.locomotion_skeleton
	var source: Skeleton3D = reference.jump_skeleton if reference.jump_model.visible else reference.locomotion_skeleton
	for index: int in range(target.get_bone_count()):
		error = maxf(error, target.get_bone_pose_position(index).distance_to(source.get_bone_pose_position(index)))
		error = maxf(error, target.get_bone_pose_scale(index).distance_to(source.get_bone_pose_scale(index)))
		error = maxf(error, absf(1.0 - absf(target.get_bone_pose_rotation(index).dot(source.get_bone_pose_rotation(index)))))
	var target_meshes: Array[MeshInstance3D] = player._jump_meshes if player.jump_model.visible else player._locomotion_meshes
	var source_meshes: Array[MeshInstance3D] = reference._jump_meshes if reference.jump_model.visible else reference._locomotion_meshes
	for mesh_index: int in range(target_meshes.size()):
		for shape_index: int in range(target_meshes[mesh_index].get_blend_shape_count()):
			error = maxf(error, absf(target_meshes[mesh_index].get_blend_shape_value(shape_index) - source_meshes[mesh_index].get_blend_shape_value(shape_index)))
	var target_model: Node3D = player.jump_model if player.jump_model.visible else player.locomotion_model
	var source_model: Node3D = reference.jump_model if reference.jump_model.visible else reference.locomotion_model
	var target_rig: Node3D = player.jump_rig if player.jump_model.visible else player.locomotion_rig
	var source_rig: Node3D = reference.jump_rig if reference.jump_model.visible else reference.locomotion_rig
	var transforms_match: bool = target_model.transform.is_equal_approx(source_model.transform) and target_rig.transform.is_equal_approx(source_rig.transform)
	check(label, error < 0.0001 and player.active_clip == reference.active_clip and transforms_match, {"max_pose_error": error, "clip": player.active_clip, "root_transforms_match": transforms_match})

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	player = prepare(PlayerScript)
	reference = prepare(PlayerScript)
	check("Both fixtures prepare the delivered character and cloth assets", player.visuals_ready() and reference.visuals_ready())
	var before_seeks: int = player.animation_seek_calls
	var before_samples: int = player.animation_pose_samples
	var before_ticks: int = player.animation_physics_updates
	for tick: int in range(6):
		advance_pair(2.2)
	check("Six physics ticks preserve the full walk clock without sampling tracks", is_equal_approx(player.animation_clock, 6.0 * DT) and player.animation_seek_calls == before_seeks and player.animation_physics_updates - before_ticks == 6, player.animation_clock)
	compare_pose("One rendered walk pose equals the final physics pose, including cloth")
	check("Six ticks coalesce into one seek and one pose pass", player.animation_seek_calls - before_seeks == 1 and player.animation_pose_samples - before_samples == 1)
	player.sample_motion_animation()
	check("Repeated render calls without a pending pose do no animation work", player.animation_pose_samples - before_samples == 1)
	for actor: PlanetPlayer in [player, reference]:
		actor.set_clip(&"Run")
		actor.set_clip(&"Walk")
		actor.set_clip(&"Idle")
	reference.sample_motion_animation()
	before_seeks = player.animation_seek_calls
	compare_pose("Several clip changes before a draw retain the final Idle pose")
	check("Transient clips do not cause additional seeks", player.animation_seek_calls - before_seeks == 1)
	before_seeks = player.animation_seek_calls
	for tick: int in range(6):
		advance_pair(0.0)
	player._process(6.0 * DT)
	check("Idle physics ticks do not repeatedly resample an unchanged pose", player.animation_seek_calls == before_seeks)
	for actor: PlanetPlayer in [player, reference]:
		actor.jump_state = &"anticipation"
	for tick: int in range(6):
		player.jump_clock = float(tick + 1) * DT
		reference.jump_clock = player.jump_clock
		advance_pair(0.0)
	compare_pose("Jump anticipation keeps authored bone and cloth timing")
	for group: int in range(2):
		for tick: int in range(6):
			for actor: PlanetPlayer in [player, reference]:
				actor.jump_state = &"airborne"
				actor.jump_clock = PlanetPlayer.JUMP_START_DURATION + float(group * 6 + tick + 1) * DT
				actor.flip_progress = float(group * 6 + tick + 1) / 12.0
			advance_pair(0.0)
		compare_pose("Airborne pose uses latest physical flip progress " + str(group))
	for group: int in range(4):
		before_seeks = player.animation_seek_calls
		for tick: int in range(15):
			for actor: PlanetPlayer in [player, reference]:
				actor.jump_state = &"landing"
				actor.landing_clock = float(group * 15 + tick + 1) * DT
			advance_pair(2.2)
		compare_pose("Landing body recovery and cloth match at sparse render boundary " + str(group))
		check("Landing samples each needed rig once per draw " + str(group), player.animation_seek_calls - before_seeks <= 2)
	var previous_recovery: float = player.recovery_clock
	for actor: PlanetPlayer in [player, reference]:
		actor.jump_state = &"grounded"
	advance_pair(2.2)
	check("Finishing landing retains all recovery gait phase", is_equal_approx(player.animation_clock, previous_recovery + DT), {"before": previous_recovery, "after": player.animation_clock})
	compare_pose("Walking continues smoothly from the recovery pose")
	for actor: PlanetPlayer in [player, reference]:
		actor.jump_state = &"landing"
		actor.landing_clock = 0.6
	advance_pair(2.2)
	for actor: PlanetPlayer in [player, reference]:
		actor.jump_state = &"anticipation"
		actor.jump_clock = 0.0
	advance_pair(0.0)
	compare_pose("A repeat jump supersedes an unsampled landing pose")
	player.reset_jump_motion()
	player.set_clip(&"Idle")
	player.is_resting = true
	player.locomotion_model.visible = false
	player._process(DT)
	check("An Idle pose flush does not reveal the walking model during rest", not player.locomotion_model.visible and player.active_clip == &"Idle")
	player.is_resting = false
	player.active_clip = &""
	player.set_clip(&"Idle")
	player._process(DT)
	player.jump_state = &"airborne"
	player.jump_clock = 0.5
	player.flip_progress = 0.5
	player.update_motion_animation(DT, 0.0, false)
	player.teleport(Vector3.UP, 48.3)
	player._process(DT)
	check("Teleport discards a queued airborne pose and resets to Idle", player.active_clip == &"Idle" and is_zero_approx(player.animator.current_animation_position) and not player.jump_model.visible)
	player.begin_entry()
	before_seeks = player.animation_seek_calls
	player.sample_entry(0.2)
	player.sample_entry(0.7)
	player._process(DT)
	check("Entry keeps its latest authored phase with one sample", player.active_clip == &"JumpDown" and player.animation_seek_calls - before_seeks == 1 and is_equal_approx(player.animator.current_animation_position, minf(0.98, player.animator.current_animation_length)))
	player.finish_entry()
	player._process(DT)
	check("Entry completion restores the visible Idle pose", not player.entering and player.visual.visible and player.active_clip == &"Idle" and is_zero_approx(player.animator.current_animation_position))
	var unkeyed_mesh: MeshInstance3D = MeshInstance3D.new()
	var unkeyed_shapes: ArrayMesh = ArrayMesh.new()
	unkeyed_shapes.add_blend_shape(&"UnkeyedCloth")
	unkeyed_mesh.mesh = unkeyed_shapes
	player.locomotion_model.add_child(unkeyed_mesh)
	player._locomotion_meshes.append(unkeyed_mesh)
	unkeyed_mesh.set_blend_shape_value(0, 0.75)
	player.set_clip(&"Walk")
	player.finish_entry()
	player.reset_jump_motion()
	player.teleport(Vector3.UP, 48.3)
	player._process(DT)
	check("Repeated reset preserves an unsampled Idle morph clear", is_zero_approx(unkeyed_mesh.get_blend_shape_value(0)), unkeyed_mesh.get_blend_shape_value(0))
	var indoor: PlanetPlayer = prepare(IndoorScript)
	before_seeks = indoor.animation_seek_calls
	for tick: int in range(4):
		indoor.update_motion_animation(DT, 2.2, false)
	indoor.set_physics_process(false)
	indoor.process_mode = Node.PROCESS_MODE_INHERIT
	await process_frame
	await process_frame
	check("Indoor subclass inherits the normal render callback and coalesces pending ticks", indoor.animation_seek_calls - before_seeks == 1 and is_equal_approx(indoor.animation_clock, 4.0 * DT))
	var result: Dictionary = {"passed": failures == 0, "failed": failures, "checks": checks, "notes": "Headless scheduling and final bone/morph equivalence; not a rendered performance measurement or visual penetration check."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var output: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("ANIMATION_SAMPLING_CHECKS ", JSON.stringify(result))
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
