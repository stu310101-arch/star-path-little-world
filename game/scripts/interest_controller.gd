extends Node
## Account-scoped document state. Nothing is written to a local shared save file.
signal changed
signal document_loaded
signal saved(action: String)
signal account_reset

const Model = preload("res://scripts/interest_model.gd")
var profile: Dictionary = Model.new_profile()
var baseline: Dictionary = profile.duplicate(true)
var record_id: String = ""
var revision: int = 0
var has_completed: bool = false
var has_draft: bool = false
var records: Array = []
var next_cursor: Variant = null
var active_record_id: String = ""
var selection_revision: int = 0
var status: String = ""
var error: bool = false
var timeout_seconds: float = 20.0
var account: Node
var generation: int = -1
var pending: Dictionary = {}
var retry_command: Dictionary = {}
var serial: int = 0
var edit_version: int = 0
var timer: Timer
var _auto_open: bool = true
var _retry_edit_version: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_timed_out)
	add_child(timer)

func configure(service: Node) -> void:
	if account == service and is_instance_valid(service) and generation == int((service.get("user") as Dictionary).get("sessionGeneration",-1)):
		return
	detach()
	records.clear()
	next_cursor = null
	active_record_id = ""
	selection_revision = 0
	account = service
	if is_instance_valid(account):
		account.connect("interest_message",_packet)
		account.connect("state_changed",_account_changed)
		generation = int((account.get("user") as Dictionary).get("sessionGeneration",-1))
	new_record()
	_auto_open = true

func detach() -> void:
	if is_instance_valid(account):
		if account.is_connected("interest_message",_packet):
			account.disconnect("interest_message",_packet)
		if account.is_connected("state_changed",_account_changed):
			account.disconnect("state_changed",_account_changed)
	account = null
	pending.clear()
	retry_command.clear()
	if timer != null:
		timer.stop()

func _exit_tree() -> void:
	detach()

func ready_account() -> bool:
	return is_instance_valid(account) and (account.get("user") as Dictionary).get("profileReady",false) == true

func is_dirty() -> bool:
	return profile != baseline

func busy() -> bool:
	return not pending.is_empty()

func edited() -> void:
	edit_version += 1
	changed.emit()

func new_record() -> void:
	if busy():
		return
	serial += 1
	_auto_open = false
	record_id = "interest_%d_%d_%d" % [int(Time.get_unix_time_from_system()),get_instance_id(),serial]
	profile = Model.new_profile()
	baseline = profile.duplicate(true)
	revision = 0
	has_completed = false
	has_draft = false
	edit_version += 1
	status = "新紀錄已準備好，可以慢慢填寫。"
	error = false
	retry_command.clear()
	document_loaded.emit()
	changed.emit()

func discard() -> void:
	profile = baseline.duplicate(true)
	edit_version += 1
	document_loaded.emit()
	changed.emit()

func refresh_history(more: bool = false) -> bool:
	var command: Dictionary = {"action":"list"}
	if more and next_cursor is Dictionary:
		command["cursor"] = next_cursor.duplicate(true)
	return _send(command)

func open_record(id: String) -> bool:
	return _send({"action":"get","recordId":id})

func save(complete: bool = false) -> bool:
	if complete and not Model.validate(profile).is_empty():
		return false
	var snapshot: Dictionary = Model.normalized(profile) if complete else profile.duplicate(true)
	return _send({"action":"complete" if complete else "saveDraft","recordId":record_id,"expectedRevision":revision,"profile":snapshot})

func select_active(id: String) -> bool:
	return _send({"action":"setActive","recordId":id,"expectedSelectionRevision":selection_revision})

func retry() -> bool:
	if retry_command.is_empty():
		return false
	return _send(retry_command.duplicate(true),_retry_edit_version)

func _send(command: Dictionary, snapshot_version: int = -1) -> bool:
	if busy():
		return false
	if command.has("profile") and JSON.stringify(command.profile).to_utf8_buffer().size() > 61440:
		status = "這份紀錄的內容較多，請刪除不需要的列或縮短文字後再儲存。目前輸入已保留。"
		error = true
		retry_command.clear()
		changed.emit()
		return false
	if not ready_account() or not account.has_method("request_interest"):
		status = "帳號尚未連線，填寫內容會留在目前畫面；請稍後重試。"
		error = true
		retry_command = command.duplicate(true)
		_retry_edit_version = edit_version if snapshot_version < 0 else snapshot_version
		changed.emit()
		return false
	serial += 1
	var request_id: String = str(command.get("requestId","interest_%d_%d" % [get_instance_id(),serial]))
	var outbound: Dictionary = command.duplicate(true)
	outbound["requestId"] = request_id
	pending = {"requestId":request_id,"command":outbound.duplicate(true),"editVersion":edit_version if snapshot_version < 0 else snapshot_version,"generation":generation}
	retry_command.clear()
	status = "正在讀取帳號紀錄…" if command.action in ["list","get"] else "正在儲存至帳號…"
	error = false
	timer.start(timeout_seconds)
	changed.emit()
	if not bool(account.call("request_interest",outbound)):
		_fail("尚未連上帳號資料，輸入內容已保留。請重試。",true)
		return false
	return true

func _timed_out() -> void:
	if not pending.is_empty():
		_fail("連線等候逾時，輸入內容已保留。可重試；若提示版本不同，請到我的紀錄重新開啟確認。",true)

func _fail(message: String, allow_retry: bool) -> void:
	if allow_retry:
		retry_command = pending.get("command",{}).duplicate(true)
		_retry_edit_version = int(pending.get("editVersion",edit_version))
	else:
		retry_command.clear()
	pending.clear()
	timer.stop()
	status = message
	error = true
	changed.emit()

func _packet(packet: Dictionary) -> void:
	if pending.is_empty() or str(packet.get("requestId","")) != str(pending.requestId) or int(packet.get("sessionGeneration",-2)) != generation:
		return
	if packet.get("type") == "error":
		var code: String = str(packet.get("code",""))
		var message: String = str(packet.get("message","帳號資料暫時無法存取。"))
		if code == "cloud-revision-conflict":
			message = "這份紀錄已有更新。目前輸入已保留；可先複製為新紀錄並儲存，或到我的紀錄重新開啟最新版本。"
		_fail(message,code in ["unavailable","network-error",""])
		return
	var request: Dictionary = pending.duplicate(true)
	var action: String = str(request.command.action)
	var expected_type: String = "list" if action == "list" else ("active" if action == "setActive" else "state")
	if packet.get("type") != expected_type:
		return
	if expected_type == "state" and str(packet.get("recordId","")) != str(request.command.get("recordId","")):
		return
	if action == "get" and int(request.editVersion) != edit_version:
		pending.clear()
		timer.stop()
		error = false
		status = "讀取期間有新的修改，目前內容已保留。請先儲存，再開啟其他紀錄。"
		changed.emit()
		return
	pending.clear()
	timer.stop()
	error = false
	retry_command.clear()
	active_record_id = str(packet.get("activeRecordId",active_record_id))
	selection_revision = int(packet.get("selectionRevision",selection_revision))
	if action == "list":
		if not request.command.has("cursor"):
			records.clear()
		for value: Variant in packet.get("records",[]):
			if value is Dictionary:
				var replaced: bool = false
				for index: int in range(records.size()):
					if records[index].id == value.id:
						records[index] = value
						replaced = true
				if not replaced:
					records.append(value)
		next_cursor = packet.get("nextCursor")
		status = "已讀取帳號中的 %d 筆紀錄。" % records.size()
		if _auto_open and not is_dirty() and revision == 0:
			_auto_open = false
			var first_id: String = active_record_id
			if first_id.is_empty() and not records.is_empty():
				first_id = str(records[0].id)
			if not first_id.is_empty():
				_open_initial.call_deferred(first_id,edit_version)
	elif action == "setActive":
		status = "已設定之後分析推薦使用的紀錄。"
	else:
		record_id = str(packet.get("recordId",record_id))
		revision = int(packet.get("revision",revision))
		has_completed = bool(packet.get("hasCompleted",false))
		has_draft = bool(packet.get("hasDraft",false))
		var received: Dictionary = packet.get("profile",{}) if packet.get("profile") is Dictionary else request.command.get("profile",{})
		baseline = Model.for_editing(received)
		if action == "get" or int(request.editVersion) == edit_version:
			profile = baseline.duplicate(true)
			document_loaded.emit()
		status = "已開啟紀錄，修改後可以儲存草稿。" if action == "get" else ("已完成並儲存至帳號。" if action == "complete" else "草稿已儲存至帳號。")
		if has_completed and has_draft:
			status += " 原本完成的版本仍可用於之後分析。"
		if action in ["saveDraft","complete"]:
			saved.emit(action)
	changed.emit()

func _open_initial(id: String, expected_version: int) -> void:
	if expected_version == edit_version and not is_dirty() and revision == 0 and not busy():
		open_record(id)

func duplicate_current() -> void:
	if busy():
		return
	var copy: Dictionary = profile.duplicate(true)
	new_record()
	profile = copy
	profile.title = str(profile.title).left(75)+"（副本）"
	status = "已建立副本，請確認後儲存至帳號。"
	edited()
	document_loaded.emit()

func _account_changed(user: Dictionary) -> void:
	var next_generation: int = int(user.get("sessionGeneration",-1))
	if next_generation == generation and user.get("profileReady",false) == true:
		return
	generation = next_generation
	pending.clear()
	retry_command.clear()
	timer.stop()
	records.clear()
	next_cursor = null
	active_record_id = ""
	selection_revision = 0
	new_record()
	_auto_open = true
	status = "帳號已切換，請重新開啟這個帳號的紀錄。"
	account_reset.emit()
	changed.emit()
