extends SceneTree

class PacksFixture:
	extends Node
	var requests: int = 0
	var retries: int = 0
	var available: bool = false
	var error: String = ""
	func request_resource(_path: String, _priority: int) -> void:
		requests += 1
	func is_resource_ready(_path: String) -> bool:
		return available
	func resource_error(_path: String) -> String:
		return error
	func retry_resource(_path: String) -> void:
		retries += 1

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(description: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", description)

func run() -> void:
	var original: Node = root.get_node("WebPacks")
	original.name = "OriginalWebPacks"
	var packs: PacksFixture = PacksFixture.new()
	packs.name = "WebPacks"
	root.add_child(packs)
	var watcher: Node = load("res://scripts/web_font.gd").new()
	root.add_child(watcher)
	watcher.font = load("res://assets/fonts/web/LittleWorldTC.ttf").duplicate()
	watcher._ranges = JSON.parse_string(FileAccess.get_file_as_string("res://data/web_font.json")).supported_ranges
	watcher.ensure_text("星途 開始漫遊 0123456789")
	check("Existing game text keeps the full font deferred", packs.requests == 0)
	var full: Font = load("res://assets/fonts/web/NotoSansTC-full.ttf")
	var missing: String = ""
	for code: int in range(0x4e00, 0x9fff):
		if full.has_char(code) and not watcher.font.has_char(code):
			missing = String.chr(code)
			break
	check("Fixture finds an authored character absent from the subset", not missing.is_empty())
	watcher.ensure_text(missing)
	watcher.ensure_text(missing)
	check("Unseen text requests the fallback only once", packs.requests == 1)
	packs.error = "fixture outage"
	for second: int in range(35):
		watcher._process(1.0)
	check("Font outages retry with a finite budget", packs.retries == 3)
	check("An outage never installs an invalid font", watcher.font.fallbacks.is_empty())
	packs.error = ""
	packs.available = true
	watcher._process(1.0)
	check("A completed retry restores the authored missing glyph", watcher.font.has_char(missing.unicode_at(0)))
	check("Completed fallback stops polling", watcher._complete and not watcher.is_processing())
	watcher.free()
	packs.free()
	original.name = "WebPacks"
	print("WEB_FONT_CHECKS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
