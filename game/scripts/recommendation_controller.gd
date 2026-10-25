extends Node
## Small account-scoped display cache. The TypeScript host is the sole ranking engine.
signal changed
signal response(action: String, packet: Dictionary)
signal account_reset
const Protocol = preload("res://scripts/recommendation_protocol.gd")
var account: Node
var generation: int = -1
var serial: int = 0
var query_epoch: int = 0
var query_id: String = ""
var pending: Dictionary = {}
var retry_commands: Array[Dictionary] = []
var status: String = ""
var error: bool = false
var timeout_seconds: float = 25.0
var timer: Timer

static func default_settings() -> Dictionary:
	return {"source":"activeReport","manual":[],"examId":"","mode":"balanced","year":"115","applicantGender":"","filters":{"keyword":"","category":"","status":"all"}}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	timer = Timer.new()
	timer.wait_time = .5
	timer.timeout.connect(_check_timeouts)
	add_child(timer)
	timer.start()

func setup(service: Node) -> void:
	if account==service and is_instance_valid(service): return
	detach()
	account = service
	if is_instance_valid(account):
		account.connect("recommendation_message",_packet)
		account.connect("state_changed",_account_changed)
		generation = int((account.get("user") as Dictionary).get("sessionGeneration",-1))

func detach() -> void:
	if is_instance_valid(account):
		if account.is_connected("recommendation_message",_packet): account.disconnect("recommendation_message",_packet)
		if account.is_connected("state_changed",_account_changed): account.disconnect("state_changed",_account_changed)
	account = null
	pending.clear()
	retry_commands.clear()
	query_id = ""
	query_epoch += 1

func _exit_tree() -> void:
	detach()

func ready_account() -> bool:
	return is_instance_valid(account) and (account.get("user") as Dictionary).get("profileReady",false)==true

func busy(action: String = "") -> bool:
	for record: Dictionary in pending.values():
		if action.is_empty() or record.command.action==action: return true
	return false

func invalidate_query() -> void:
	query_epoch += 1
	query_id = ""
	for request_id: String in pending.keys():
		if pending[request_id].command.action in ["query","page","detail"]: pending.erase(request_id)
	retry_commands = retry_commands.filter(func(command: Dictionary) -> bool: return command.action not in ["query","page","detail"])

func send(action: String, fields: Dictionary = {}, retry_id: String = "") -> bool:
	if not ready_account():
		status = "帳號尚未連線，請先登入後重試。"
		error = true
		changed.emit()
		return false
	if action=="query" and retry_id.is_empty(): invalidate_query()
	serial += 1
	var command: Dictionary = {"action":action,"requestId":retry_id if not retry_id.is_empty() else "rec_%d_%d"%[get_instance_id(),serial]}
	command.merge(fields)
	if Protocol.sanitize_command(command,generation).is_empty():
		status = "推薦資料格式不完整，請檢查選取內容。"
		error = true
		changed.emit()
		return false
	pending[command.requestId] = {"command":command.duplicate(true),"at":Time.get_ticks_msec(),"epoch":query_epoch}
	status = "正在儲存至帳號…" if action in ["saveSettings","setFavorite"] else "正在整理推薦資料…"
	error = false
	changed.emit()
	if not bool(account.call("request_recommendation",command)):
		pending.erase(command.requestId)
		_remember_retry(command)
		status = "連線尚未準備完成，選擇已保留。請重試連線。"
		error = true
		changed.emit()
		return false
	return true

func _remember_retry(command: Dictionary) -> void:
	for item: Dictionary in retry_commands:
		if item.requestId==command.requestId: return
	retry_commands.append(command.duplicate(true))

func retry() -> void:
	var commands: Array[Dictionary] = retry_commands.duplicate(true)
	retry_commands.clear()
	for command: Dictionary in commands:
		var fields: Dictionary = command.duplicate(true)
		fields.erase("action")
		fields.erase("requestId")
		send(str(command.action),fields,str(command.requestId))

func _check_timeouts() -> void:
	var expired: bool = false
	for request_id: String in pending.keys():
		if Time.get_ticks_msec()-int(pending[request_id].at)>timeout_seconds*1000:
			_remember_retry(pending[request_id].command)
			pending.erase(request_id)
			expired = true
	if expired:
		status = "連線等候逾時，選擇已保留；尚未確認儲存。可重試連線。"
		error = true
		changed.emit()

func _packet(raw: Dictionary) -> void:
	var packet: Dictionary = Protocol.sanitize_packet(raw)
	if packet.is_empty() or int(packet.sessionGeneration)!=generation or not pending.has(str(packet.requestId)): return
	var record: Dictionary = pending[packet.requestId]
	var command: Dictionary = record.command
	if command.action in ["query","page","detail"] and int(record.epoch)!=query_epoch: return
	if packet.type!="error":
		if packet.type!=Protocol.expected_type(command.action): return
		if command.action in ["page","detail"] and packet.queryId!=command.queryId: return
		if command.action=="detail" and packet.item.programRef!=command.programRef: return
		if command.action=="setFavorite" and packet.programRef!=command.programRef: return
	pending.erase(packet.requestId)
	if packet.type=="error":
		error = true
		status = str(packet.message)
		if packet.code in ["unavailable"]: _remember_retry(command)
		elif packet.code in ["query-expired","stale-user-session"]: invalidate_query()
	else:
		error = false
		if command.action=="query": query_id = str(packet.queryId)
		status = "已儲存至帳號。" if command.action in ["saveSettings","setFavorite"] else "推薦資料已更新。"
	response.emit(str(command.action),packet)
	changed.emit()

func _account_changed(user: Dictionary) -> void:
	var next_generation: int = int(user.get("sessionGeneration",-1))
	if next_generation==generation and user.get("profileReady",false)==true: return
	generation = next_generation
	pending.clear()
	retry_commands.clear()
	invalidate_query()
	status = "帳號已切換，請重新讀取推薦資料。"
	error = false
	account_reset.emit()
	changed.emit()
