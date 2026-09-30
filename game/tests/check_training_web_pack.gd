extends SceneTree

func _initialize() -> void:
	var layout_path: String = "res://assets/training_room/layout.json"
	var source_layout: String = FileAccess.get_file_as_string(layout_path)
	var pack_path: String = ProjectSettings.globalize_path("res://../build/web/index.pck")
	var mounted: bool = ProjectSettings.load_resource_pack(pack_path, true)
	var packed_layout: String = FileAccess.get_file_as_string(layout_path)
	var data: Dictionary = JSON.parse_string(packed_layout) as Dictionary
	var corner: Dictionary = {}
	for seat: Dictionary in data.get("seats", []):
		if str(seat.id) == "sofa_corner":
			corner = seat
	var matches: bool = source_layout.sha256_text() == packed_layout.sha256_text()
	var report: Dictionary = {
		"passed": mounted and matches,
		"pack_mounted": mounted,
		"layout_matches_final_source": matches,
		"source_layout_sha256": source_layout.sha256_text(),
		"packed_layout_sha256": packed_layout.sha256_text(),
		"seat_count": (data.get("seats", []) as Array).size(),
		"book_count": (data.get("books", []) as Array).size(),
		"corner_seat": corner,
	}
	var output: FileAccess = FileAccess.open(ProjectSettings.globalize_path("res://../deliverables/training-room/web-pack-checks.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("TRAINING_WEB_PACK ", JSON.stringify(report))
	quit(0 if report.passed else 1)
