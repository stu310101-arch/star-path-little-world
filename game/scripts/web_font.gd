extends Node
## Static text uses a generated subset; unseen dynamic text requests the full
## authored font once. Native builds retain their original complete font.
var font: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const FULL_FONT: String = "res://assets/fonts/web/NotoSansTC-full.ttf"
var _labels: Array[WeakRef] = []
var _seen: Dictionary = {}
var _requested: bool = false
var _complete: bool = false
var _clock: float = 0.0
var _ranges: Array = []
var _retry_seconds: float = 0.0
var _retries: int = 0

func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	_ranges = (JSON.parse_string(FileAccess.get_file_as_string("res://data/web_font.json")) as Dictionary).supported_ranges
	get_tree().node_added.connect(_node_added)
	_watch_tree(get_tree().root)

func _watch_tree(node: Node) -> void:
	_node_added(node)
	for child: Node in node.get_children():
		_watch_tree(child)

func _node_added(node: Node) -> void:
	if node is Label or node is Label3D or node is Button or node is RichTextLabel or node is LineEdit:
		_labels.append(weakref(node))

func ensure_text(text: String) -> void:
	if _requested or _complete:
		return
	for index: int in range(text.length()):
		var code: int = text.unicode_at(index)
		if _seen.has(code):
			continue
		_seen[code] = true
		if code < 32 or font.has_char(code):
			continue
		for bounds: Array in _ranges:
			if code >= int(bounds[0]) and code <= int(bounds[1]):
				_requested = true
				get_node("/root/WebPacks").call("request_resource", FULL_FONT, 100)
				return

func _process(delta: float) -> void:
	_clock += delta
	if _clock < 1.0:
		return
	_clock = 0.0
	if _requested:
		var packs: Node = get_node("/root/WebPacks")
		if bool(packs.call("is_resource_ready", FULL_FONT)):
			font.fallbacks = [load(FULL_FONT) as Font]
			_complete = true
			_labels.clear()
			_seen.clear()
			set_process(false)
		elif not str(packs.call("resource_error", FULL_FONT)).is_empty() and _retries < 3:
			_retry_seconds += 1.0
			if _retry_seconds >= pow(2.0, _retries + 1):
				_retry_seconds = 0.0
				_retries += 1
				packs.call("retry_resource", FULL_FONT)
		return
	var live: Array[WeakRef] = []
	for reference: WeakRef in _labels:
		var node: Node = reference.get_ref()
		if node == null:
			continue
		live.append(reference)
		if (node is CanvasItem and (node as CanvasItem).is_visible_in_tree()) or (node is Node3D and (node as Node3D).is_visible_in_tree()):
			ensure_text(str(node.get("text")))
	_labels = live
