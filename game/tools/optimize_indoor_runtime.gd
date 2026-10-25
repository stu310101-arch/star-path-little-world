extends SceneTree
const Optimizer = preload("res://tools/indoor_runtime_optimizer.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var report: Dictionary = Optimizer.optimize(not OS.get_cmdline_user_args().has("--dry-run"))
	var before: int = 0
	var after: int = 0
	var culled: int = 0
	for row: Dictionary in report.surfaces:
		before += int(row.before)
		after += int(row.after)
		culled += int(bool(row.backface_culling_enabled))
	print("INDOOR_RUNTIME_OPTIMIZER ", JSON.stringify({"before": before, "after": after, "culled_surfaces": culled, "written": report.written}))
	quit()
