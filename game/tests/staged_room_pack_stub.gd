extends Node

var pack_complete: bool = false
var failed: bool = false
var requests: int = 0
var requested: bool = false

func request_resource(path: String, _priority: int = 0) -> void:
	if path.ends_with("detail_catalog.json") and not requested:
		requested = true
		requests += 1

func is_resource_ready(path: String) -> bool:
	return pack_complete if path.ends_with("detail_catalog.json") else true

func resource_error(path: String) -> String:
	return "測試下載失敗" if path.ends_with("detail_catalog.json") and failed else ""

func retry_failed() -> void:
	failed = false

func get_resource_progress(_path: String) -> Dictionary:
	return {"phase": "error" if failed else ("ready" if pack_complete else "downloading"), "received_bytes": 512, "total_bytes": 1024, "ready": pack_complete}
