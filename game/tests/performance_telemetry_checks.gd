extends SceneTree

class Probe:
	extends "res://scripts/performance_telemetry.gd"
	func _ready() -> void:
		pass
	func snapshot() -> Dictionary:
		return {}

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(description: String, passed: bool) -> void:
	if passed:
		print("PASS ", description)
	else:
		failures += 1
		push_error(description)

func run() -> void:
	var probe: Probe = Probe.new()
	root.add_child(probe)
	probe._record_frame(1000000)
	probe._record_frame(1033333)
	probe._record_frame(1533333)
	probe._record_frame(2033333)
	check("Wall-clock sampling preserves 500 ms stalls", is_equal_approx(float(probe.latest.get("frame_ms_max", 0.0)), 500.0))
	check("Long foreground frames are counted", int(probe.latest.get("frames_over_100_ms", 0)) == 2 and int(probe.latest.get("frame_intervals", 0)) == 3)
	check("Published window is based on elapsed clock time", is_equal_approx(float(probe.latest.get("frame_sample_window_ms", 0.0)), 1033.333))
	probe._set_foreground(false)
	probe._record_frame(90000000)
	check("Background intervals are excluded and old sample is invalid", probe.frames == 0 and not bool(probe.latest.get("frame_sample_valid", true)))
	probe._set_foreground(true)
	probe._record_frame(120000000)
	for index: int in range(1, 32):
		probe._record_frame(120000000 + index * 33334)
	check("Resuming excludes the hidden minute", is_equal_approx(float(probe.latest.get("frame_ms_max", 0.0)), 33.334) and int(probe.latest.get("frames_over_100_ms", -1)) == 0)
	root.remove_child(probe)
	check("Detached world invalidates its previous sample", not bool(probe.latest.get("frame_sample_valid", true)))
	root.add_child(probe)
	probe._record_frame(300000000)
	check("Reattached world starts a new timing baseline", probe.frames == 0)
	probe.free()
	quit(1 if failures > 0 else 0)
