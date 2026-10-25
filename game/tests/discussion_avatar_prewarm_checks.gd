extends SceneTree
const Prewarm = preload("res://scripts/discussion_avatar_prewarm.gd")
const Player = preload("res://scripts/indoor_player.gd")
class Choice:
	extends Node
	var _walk_model_path: String = ""
	var _jump_model_path: String = ""
var checks: int = 0
var failures: int = 0
func _initialize() -> void: run.call_deferred()
func check(title: String, passed: bool) -> void:
	checks += 1
	print("DISCUSSION_PREWARM_CHECK ",title," ",passed)
	if not passed: failures += 1
func run() -> void:
	Engine.max_fps = 0
	var player := Player.new()
	root.add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var prewarm := Prewarm.new()
	prewarm.configure(player,self)
	check("Prewarm keeps the player's existing walk and jump choices",prewarm.paths==[player.get("_walk_model_path"),player.get("_jump_model_path")])
	var deadline: int = Time.get_ticks_msec()+60000
	while not prewarm.step() and prewarm.error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check("Both PackedScenes finish without advancing the player",prewarm.error.is_empty() and prewarm.metrics().completed==2 and player.get("_visual_stage")==0)
	check("Warm scenes are retained as cache hits",ResourceLoader.has_cached(prewarm.paths[0]) and ResourceLoader.has_cached(prewarm.paths[1]) and prewarm.metrics().retained==2)
	player.begin_prepare_visuals()
	player.step_prepare_visuals()
	check("The shared player reads the same retained walk resource",player.get("_visual_packed")==prewarm.get("_retained")[0])
	while not player.visuals_ready() and Time.get_ticks_msec()<deadline:
		player.step_prepare_visuals()
		await process_frame
	check("Unchanged player preparation completes normally",player.visuals_ready())
	prewarm.release_completed()
	check("Prewarm releases its extra ownership after preparation",prewarm.metrics().retained==0 and player.visuals_ready())
	var file_path: String = "user://discussion-prewarm-cancel-%d.tscn" % Time.get_ticks_usec()
	var temporary := Node3D.new()
	var packed := PackedScene.new()
	packed.pack(temporary)
	ResourceSaver.save(packed,file_path)
	temporary.free()
	packed = null
	var choice := Choice.new()
	choice._walk_model_path = file_path
	choice._jump_model_path = file_path
	var pending := Prewarm.new()
	pending.configure(choice,self)
	pending.step()
	check("Duplicate resource choices are requested once",pending.paths.size()==1)
	pending.cancel()
	check("Cancellation releases ownership without a blocking get",pending.metrics().cancelled and pending.pending_path.is_empty() and pending.metrics().retained==0)
	for i: int in range(15): await process_frame
	check("Abandoned load reaper is drained and removed",root.find_children("DiscussionAvatarPendingLoad*","Node",false,false).is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	choice.free()
	player.queue_free()
	await process_frame
	print("DISCUSSION_PREWARM_RESULT ",checks," checks, ",failures," failures; ",JSON.stringify(prewarm.metrics()))
	quit(0 if failures==0 else 1)
