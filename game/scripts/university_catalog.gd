extends RefCounted
signal progress_changed
## The source text is editorial content, never executable instructions.

const DATA_PATH: String = "res://data/universities.json"
const SAVE_PATH: String = "user://university_exploration.json"
const PAGE_SIZE: int = 8
const REGION_IDS: Array[String] = ["north", "central", "south", "east", "islands"]
const REGION_NAMES: Array[String] = ["北部", "中部", "南部", "東部", "離島"]
const SECTION_IDS: Array[String] = ["location", "surroundings", "food", "reviews", "culture"]
const SECTION_NAMES: Array[String] = ["位置與交通", "周邊生活", "特色美食", "學生評價", "校園風氣"]

var entries: Array[Dictionary] = []
var by_id: Dictionary = {}
var visited: Dictionary = {}
var favorites: Dictionary = {}
var source_note: String = ""
var source_date: String = "2026-10-09"
var error: String = ""
var save_error: String = ""
var save_path: String = SAVE_PATH
var cloud: Node
var cloud_revision: int = -1
var cloud_generation: int = -1
var cloud_serial: int = 0
var cloud_requests: Dictionary = {}

func configure_cloud(service: Node) -> bool:
	if service == null or not service.has_method("request_progress"):
		return false
	cloud = service
	cloud.connect("progress_message",_cloud_packet)
	cloud.connect("state_changed",_cloud_account_changed)
	cloud_generation = int((cloud.get("user") as Dictionary).get("sessionGeneration",-1))
	return true

func detach_cloud() -> void:
	if is_instance_valid(cloud):
		if cloud.is_connected("progress_message",_cloud_packet):
			cloud.disconnect("progress_message",_cloud_packet)
		if cloud.is_connected("state_changed",_cloud_account_changed):
			cloud.disconnect("state_changed",_cloud_account_changed)
	cloud = null
	cloud_requests.clear()

func _cloud_account_changed(user: Dictionary) -> void:
	if int(user.get("sessionGeneration",-1))==cloud_generation and user.get("profileReady",false)==true:
		return
	cloud_generation = int(user.get("sessionGeneration",-1))
	cloud_revision = -1
	cloud_requests.clear()
	visited.clear()
	favorites.clear()
	progress_changed.emit()
	if user.get("profileReady",false)==true:
		_cloud_send("university-get")

func _cloud_send(action: String, extra: Dictionary = {}) -> bool:
	cloud_serial += 1
	var request_id: String = "university_"+str(get_instance_id())+"_"+str(cloud_serial)
	var command: Dictionary = {"requestId":request_id,"action":action}
	command.merge(extra)
	cloud_requests[request_id] = action
	if not is_instance_valid(cloud) or not bool(cloud.call("request_progress",command)):
		cloud_requests.erase(request_id)
		save_error = "星途探索紀錄尚未連線；請重試同步。"
		return false
	save_error = "正在同步星途探索紀錄…"
	return true

func refresh_cloud() -> void:
	if is_instance_valid(cloud):
		_cloud_send("university-get")

func _cloud_packet(packet: Dictionary) -> void:
	if not cloud_requests.has(str(packet.get("requestId",""))) or int(packet.get("sessionGeneration",-1))!=cloud_generation:
		return
	cloud_requests.erase(str(packet.requestId))
	if packet.get("type")=="error":
		save_error = "探索紀錄未能同步，請重試；尚未寫入雲端。"
		progress_changed.emit()
		return
	var revision: int = int(packet.get("revision",0))
	if revision < cloud_revision:
		return
	cloud_revision = revision
	visited.clear()
	favorites.clear()
	for id: Variant in packet.get("explored",[]):
		if by_id.has(str(id)):
			visited[str(id)] = true
	for id: Variant in packet.get("favorites",{}):
		if by_id.has(str(id)) and packet.favorites[id]==true:
			favorites[str(id)] = true
	save_error = ""
	progress_changed.emit()

func has_legacy_progress() -> bool:
	return is_instance_valid(cloud) and FileAccess.file_exists(save_path)

func import_legacy_progress() -> bool:
	if not has_legacy_progress():
		return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not value is Dictionary or value.get("schema_version")!=1:
		save_error = "舊裝置紀錄格式無法讀取，原檔案保留。"
		return false
	var command: Dictionary = {}
	for field: String in ["visited_ids","favorite_ids"]:
		var ids: Array[String] = []
		if value.get(field) is Array:
			for id: Variant in value[field]:
				if by_id.has(str(id)) and str(id) not in ids:
					ids.append(str(id))
		command[field] = ids
	return _cloud_send("university-import",command)

func load_content(path: String = DATA_PATH) -> bool:
	error = ""
	entries.clear()
	by_id.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("entries") is Array:
		error = "大學資料尚未準備完成。"
		return false
	source_note = str(parsed.get("source_note", ""))
	source_date = str(parsed.get("source_date", source_date))
	for record: Variant in parsed.entries:
		if not record is Dictionary:
			continue
		var id: String = str(record.get("id", ""))
		if id.is_empty() or by_id.has(id) or str(record.get("region", "")) not in REGION_IDS:
			error = "大學資料識別或展區不完整。"
			return false
		for section: String in SECTION_IDS:
			if str(record.get("sections", {}).get(section, "")).is_empty():
				error = "大學資料有缺少的閱讀內容。"
				return false
		entries.append(record)
		by_id[id] = record
	if entries.size() != 138:
		error = "大學資料尚未完整載入（%d / 138）。" % entries.size()
		return false
	return true

func load_progress() -> void:
	visited.clear()
	favorites.clear()
	save_error = ""
	if is_instance_valid(cloud):
		_cloud_send("university-get")
		return
	if not FileAccess.file_exists(save_path):
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var version: Variant = value.get("schema_version") if value is Dictionary else null
	if not (version is int or version is float) or version != 1:
		save_error = "探索紀錄無法讀取，本次仍可自由探索。"
		return
	for field: String in ["visited_ids", "favorite_ids"]:
		var ids: Variant = value.get(field, [])
		if not ids is Array:
			continue
		var target: Dictionary = visited if field == "visited_ids" else favorites
		for id: Variant in ids:
			if by_id.has(str(id)):
				target[str(id)] = true

func save_progress() -> bool:
	if is_instance_valid(cloud):
		return false # Cloud mutations are explicit set/visit operations, never a stale full snapshot.
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		save_error = "目前無法儲存探索紀錄；本次收藏仍可使用。"
		return false
	file.store_string(JSON.stringify({"schema_version":1, "visited_ids":visited.keys(), "favorite_ids":favorites.keys()}))
	file.flush()
	var result: Error = file.get_error()
	file.close()
	save_error = "" if result == OK else "探索紀錄未能完整儲存。"
	return result == OK

func visit(id: String) -> void:
	if by_id.has(id) and not visited.has(id):
		visited[id] = true
		if is_instance_valid(cloud):
			_cloud_send("university-explored",{"id":id})
		else:
			save_progress()

func toggle_favorite(id: String) -> void:
	if not by_id.has(id):
		return
	if favorites.has(id):
		favorites.erase(id)
	else:
		favorites[id] = true
	if is_instance_valid(cloud):
		_cloud_send("university-favorite",{"id":id,"value":favorites.has(id)})
	else:
		save_progress()

func region_entries(region: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if str(entry.region) == region:
			result.append(entry)
	return result

func page_entries(region: String, page: int) -> Array[Dictionary]:
	var all: Array[Dictionary] = region_entries(region)
	var result: Array[Dictionary] = []
	for index: int in range(page * PAGE_SIZE, mini((page + 1) * PAGE_SIZE, all.size())):
		if index >= 0:
			result.append(all[index])
	return result

func page_count(region: String) -> int:
	return maxi(1, ceili(float(region_entries(region).size()) / PAGE_SIZE))

func locate(id: String) -> Dictionary:
	if not by_id.has(id):
		return {}
	var region: String = str(by_id[id].region)
	var list: Array[Dictionary] = region_entries(region)
	for index: int in range(list.size()):
		if str(list[index].id) == id:
			return {"region":region, "page":index / PAGE_SIZE, "slot":index % PAGE_SIZE}
	return {}

static func normalized(text_value: String) -> String:
	return text_value.to_lower().replace("台", "臺").replace(" ", "").strip_edges()

func search(query: String = "", region: String = "", mode: String = "all") -> Array[Dictionary]:
	var needle: String = normalized(query)
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var id: String = str(entry.id)
		if not region.is_empty() and str(entry.region) != region:
			continue
		if mode == "favorites" and not favorites.has(id):
			continue
		if mode == "visited" and not visited.has(id):
			continue
		var searchable: String = str(entry.name) + " " + " ".join(entry.get("aliases", [])) + " " + str(entry.get("campus_info", "")) + " " + " ".join(entry.get("tags", []))
		if needle.is_empty() or normalized(searchable).contains(needle):
			result.append(entry)
	return result

static func region_label(region: String) -> String:
	var index: int = REGION_IDS.find(region)
	return REGION_NAMES[index] if index >= 0 else "全部地區"
