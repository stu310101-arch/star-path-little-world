extends Node3D
## One physical device owns a stable public thread address, even when empty.
const ZONE_CODES: Dictionary = {"university":"UN", "major":"MA", "career":"CA", "high_school":"HS", "campus":"CL"}
const INTERACTION_RADIUS: float = 2.8
var zone_id: String
var slot_index: int
var page_index: int = 0
var thread_id: String
var message: Dictionary = {}
var preview_label: Label3D
var _focused: bool = false

static func thread_for(zone: String, page: int, slot: int) -> String:
	if not ZONE_CODES.has(zone) or page < 0 or page > 999999 or slot < 0 or slot >= 8:
		return ""
	return "SPDEV%s%012d%d" % [ZONE_CODES[zone], page, slot]

func configure(zone: String, slot: int, label: Label3D) -> void:
	zone_id = zone
	slot_index = slot
	preview_label = label
	preview_label.double_sided = false
	preview_label.visibility_range_end = 8.0
	apply_slot(0, {})

func apply_slot(page: int, post: Dictionary) -> void:
	page_index = page
	thread_id = thread_for(zone_id, page_index, slot_index)
	message = post.duplicate() if post.get("type") == "page-item" else {}
	if preview_label != null:
		preview_label.text = "%02d\n%s" % [number(), str(message.get("preview", "在這裡\n留下想法")).left(24)]

func set_focused(value: bool) -> void:
	if _focused == value:
		return
	_focused = value
	if preview_label != null:
		preview_label.modulate = Color("163f49") if value else Color("45605d")

func number() -> int:
	return page_index * 8 + slot_index + 1

func context() -> Dictionary:
	return {"zone":zone_id, "deviceId":thread_id}

func distance_to_player(at: Vector3) -> float:
	if absf(at.y - global_position.y) > 2.0:
		return INF
	return Vector2(at.x, at.z).distance_to(Vector2(global_position.x, global_position.z))
