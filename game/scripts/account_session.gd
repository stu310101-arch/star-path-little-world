extends Node

## Root-owned display session survives world suspension while visiting rooms.
## Credentials stay in the host. Only validated private interest profiles cross the score bridge.
signal state_changed(user: Dictionary)
signal session_checked(user: Dictionary)
signal closed
signal failed(message: String)
signal forum_message(packet: Dictionary)
signal progress_message(packet: Dictionary)
signal interest_message(packet: Dictionary)
signal recommendation_message(packet: Dictionary)

const NativeHost = preload("res://scripts/account_native_host.gd")
const ForumProtocol = preload("res://scripts/forum_protocol.gd")
const ProgressProtocol = preload("res://scripts/progress_protocol.gd")
const InterestProtocol = preload("res://scripts/interest_protocol.gd")
const RecommendationProtocol = preload("res://scripts/recommendation_protocol.gd")
var _recommendation_requests: Dictionary = {}
var _interest_requests: Dictionary = {}
var user: Dictionary = {}
var opened: bool = false
var last_error: String = ""
var native_host: Node
var poll_clock: float = 0.0
var _session_checked: bool = false
var _switching_account: bool = false
var _reported_bridge_error: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func resume_session() -> void:
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
		if bridge != null and bridge.resume != null:
			bridge.resume()
		else:
			_session_check({})
	else:
		_ensure_native_host()
		if not bool(native_host.call("resume_host")):
			_session_check({})

func _ensure_native_host() -> void:
	if native_host != null:
		return
	native_host = NativeHost.new()
	add_child(native_host)
	native_host.connect("closed", _closed)
	native_host.connect("state_changed", _update_user)
	native_host.connect("session_checked", _session_check)
	native_host.connect("failed", _failed)
	native_host.connect("forum_message", _forum_message)
	native_host.connect("progress_message", _progress_message)
	native_host.connect("interest_message", _interest_message)
	native_host.connect("recommendation_message", _recommendation_message)

func _session_check(value: Dictionary) -> void:
	if not _session_checked:
		_session_checked = true
		session_checked.emit(value)

func switch_account() -> void:
	_switching_account = true
	sign_out()

func open_view(view: String) -> bool:
	if view not in NativeHost.VIEWS:
		return false
	last_error = ""
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
		if bridge == null or not bool(bridge.open(view)):
			last_error = "星途帳號尚未準備完成，請重新整理或確認完整網站版本。"
			return false
	else:
		_ensure_native_host()
		if not bool(native_host.call("open_host", view)):
			last_error = str(native_host.get("last_error"))
			return false
	opened = true
	return true

func close_view() -> void:
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
		if bridge != null:
			bridge.close()
	elif is_instance_valid(native_host):
		native_host.call("close_host")
	_closed()

func sign_out() -> void:
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
		if bridge != null:
			bridge.signOut()
	elif is_instance_valid(native_host):
		native_host.call("sign_out")

func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	poll_clock += delta
	if poll_clock < .15:
		return
	poll_clock = 0.0
	var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
	if bridge == null:
		return
	var state: Variant = JSON.parse_string(str(bridge.stateJSON()))
	if state is Dictionary:
		var bridge_error: String = str(state.get("error", ""))
		if not bridge_error.is_empty() and bridge_error != _reported_bridge_error:
			_reported_bridge_error = bridge_error
			_failed(bridge_error)
		var clean: Variant = NativeHost.sanitize_user(state.get("user"))
		if clean != null:
			_update_user(clean as Dictionary)
			if bool(state.get("resolved", false)):
				_session_check(clean as Dictionary)
	if opened and not bool(bridge.isOpen()):
		_closed()
	if bridge.pollForumMessagesJSON != null:
		var messages: Variant = JSON.parse_string(str(bridge.pollForumMessagesJSON()))
		if messages is Array:
			for packet: Variant in messages:
				var clean: Dictionary = ForumProtocol.sanitize_packet(packet)
				if not clean.is_empty():
					_forum_message(clean)
	if bridge.pollProgressMessagesJSON != null:
		var messages: Variant = JSON.parse_string(str(bridge.pollProgressMessagesJSON()))
		if messages is Array:
			for packet: Variant in messages:
				var clean: Dictionary = ProgressProtocol.sanitize_packet(packet)
				if not clean.is_empty():
					_progress_message(clean)
	if bridge.pollInterestMessagesJSON != null:
		var messages: Variant = JSON.parse_string(str(bridge.pollInterestMessagesJSON()))
		if messages is Array:
			for packet: Variant in messages:
				var clean: Dictionary = InterestProtocol.sanitize_packet(packet)
				if not clean.is_empty():
					_interest_message(clean)

	if bridge.pollRecommendationMessagesJSON != null:
		var messages: Variant = JSON.parse_string(str(bridge.pollRecommendationMessagesJSON()))
		if messages is Array:
			for packet: Variant in messages:
				var clean: Dictionary = RecommendationProtocol.sanitize_packet(packet)
				if not clean.is_empty():
					_recommendation_message(clean)

func request_recommendation(command: Dictionary) -> bool:
	if user.get("profileReady",false) != true:
		return false
	var clean: Dictionary = RecommendationProtocol.sanitize_command(command,int(user.get("sessionGeneration",-1)))
	if clean.is_empty():
		return false
	var now: int = Time.get_ticks_msec()
	for request_id: String in _recommendation_requests.keys():
		if now - int(_recommendation_requests[request_id].at) > 60000:
			_recommendation_requests.erase(request_id)
	var previous: Dictionary = _recommendation_requests.get(clean.requestId,{})
	if (not previous.is_empty() and previous.command != clean) or (previous.is_empty() and _recommendation_requests.size() >= 8):
		return false
	_recommendation_requests[clean.requestId] = {"at":now,"command":clean}
	var accepted: bool = false
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
		accepted = bridge != null and bridge.recommendationCommand != null and bool(bridge.recommendationCommand(JSON.stringify(clean)))
	else:
		accepted = is_instance_valid(native_host) and bool(native_host.call("request_recommendation",clean))
	if not accepted:
		_recommendation_requests.erase(clean.requestId)
	return accepted

func _recommendation_message(packet: Dictionary) -> void:
	var request_id: String = str(packet.get("requestId",""))
	if not _recommendation_requests.has(request_id) or int(packet.get("sessionGeneration",-2)) != int(user.get("sessionGeneration",-1)) or user.get("profileReady",false) != true:
		return
	var command: Dictionary = _recommendation_requests[request_id].command
	if packet.type!="error":
		if packet.type!=RecommendationProtocol.expected_type(command.action):
			return
		if command.action in ["page","detail"] and packet.get("queryId")!=command.queryId:
			return
		if command.action=="detail" and (packet.get("item",{}) as Dictionary).get("programRef")!=command.programRef:
			return
		if command.action=="setFavorite" and packet.get("programRef")!=command.programRef:
			return
	_recommendation_requests.erase(request_id)
	recommendation_message.emit(packet)

func request_interest(command: Dictionary) -> bool:
	if user.get("profileReady",false) != true:
		return false
	var clean: Dictionary = InterestProtocol.sanitize_command(command,int(user.get("sessionGeneration",-1)))
	if clean.is_empty():
		return false
	var now: int = Time.get_ticks_msec()
	for request_id: String in _interest_requests.keys():
		if now - int(_interest_requests[request_id].at) > 60000:
			_interest_requests.erase(request_id)
	var previous: Dictionary = _interest_requests.get(clean.requestId,{})
	if (not previous.is_empty() and previous.command != clean) or (previous.is_empty() and _interest_requests.size() >= 8):
		return false
	_interest_requests[clean.requestId] = {"at":now,"command":clean}
	var accepted: bool = false
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
		accepted = bridge != null and bridge.interestCommand != null and bool(bridge.interestCommand(JSON.stringify(clean)))
	else:
		accepted = is_instance_valid(native_host) and bool(native_host.call("request_interest",clean))
	if not accepted:
		_interest_requests.erase(clean.requestId)
	return accepted

func _interest_message(packet: Dictionary) -> void:
	if not _interest_requests.has(str(packet.get("requestId",""))) or int(packet.get("sessionGeneration",-2)) != int(user.get("sessionGeneration",-1)) or user.get("profileReady",false) != true:
		return
	var command: Dictionary = _interest_requests[str(packet.requestId)].command
	if packet.type == "state" and packet.get("recordId") != command.get("recordId"):
		return
	if packet.type != "error" and str(packet.type) != ("list" if command.action == "list" else "active" if command.action == "setActive" else "state"):
		return
	_interest_requests.erase(str(packet.requestId))
	interest_message.emit(packet)

func _progress_message(packet: Dictionary) -> void:
	if int(packet.get("sessionGeneration", -2)) == int(user.get("sessionGeneration", -1)) and user.get("profileReady", false) == true:
		progress_message.emit(packet)

func request_progress(command: Dictionary) -> bool:
	if user.get("profileReady",false)!=true or command.get("action") not in ["university-get","university-favorite","university-explored","university-import"] or not ForumProtocol.valid_id(command.get("requestId")):
		return false
	var clean: Dictionary = {"requestId":command.requestId,"action":command.action,"sessionGeneration":int(user.get("sessionGeneration",-1))}
	if command.action in ["university-favorite","university-explored"]:
		if not ProgressProtocol.school_id(command.get("id")):
			return false
		clean["id"] = command.id
	if command.action=="university-favorite":
		if not command.get("value") is bool:
			return false
		clean["value"] = command.value
	if command.action=="university-import":
		for field: String in ["visited_ids","favorite_ids"]:
			if not command.get(field) is Array or command[field].size()>138:
				return false
			var ids: Array[String] = []
			for id: Variant in command[field]:
				if not ProgressProtocol.school_id(id):
					return false
				if id not in ids:
					ids.append(id)
			clean[field] = ids
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
		return bridge!=null and bool(bridge.progressCommand(JSON.stringify(clean)))
	return is_instance_valid(native_host) and bool(native_host.call("request_progress",clean))

func _forum_message(packet: Dictionary) -> void:
	if int(packet.get("sessionGeneration", -2)) == int(user.get("sessionGeneration", -1)) and user.get("profileReady", false) == true:
		forum_message.emit(packet)

func request_forum_page(command: Dictionary) -> bool:
	if user.get("profileReady", false) != true or command.get("zone") not in ForumProtocol.ZONES or command.get("direction") not in ["first", "next", "previous", "refresh"] or not ForumProtocol.valid_id(command.get("requestId")):
		return false
	var clean: Dictionary = {"requestId":command.requestId,"zone":command.zone,"direction":command.direction,"sessionGeneration":int(user.get("sessionGeneration", -1))}
	if command.get("devices",false) == true:
		clean["devices"] = true
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
		return bridge != null and bool(bridge.requestForumPage(JSON.stringify(clean)))
	return is_instance_valid(native_host) and bool(native_host.call("request_forum_page", clean))

func open_forum(context: Dictionary) -> bool:
	if user.get("profileReady", false) != true or context.get("zone") not in ForumProtocol.ZONES:
		return false
	var clean: Dictionary = {"zone":context.zone}
	if context.has("deviceId"):
		if not ForumProtocol.valid_id(context.deviceId) or context.has("threadId") or context.get("compose",false):
			return false
		clean["deviceId"] = context.deviceId
	if context.has("threadId"):
		if not ForumProtocol.valid_id(context.threadId):
			return false
		clean["threadId"] = context.threadId
	if context.get("compose", false) == true:
		clean["compose"] = true
	var accepted: bool = false
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldAccountBridge")
		accepted = bridge != null and bool(bridge.openForum(JSON.stringify(clean)))
	elif is_instance_valid(native_host):
		accepted = bool(native_host.call("open_forum", clean))
	if accepted:
		opened = true
	return accepted

func _update_user(next_user: Dictionary) -> void:
	if user != next_user:
		if int(user.get("sessionGeneration",-1)) != int(next_user.get("sessionGeneration",-1)) or next_user.get("profileReady",false) != true:
			_interest_requests.clear()
			_recommendation_requests.clear()
		user = next_user.duplicate()
		state_changed.emit(user.duplicate())
	if _switching_account and next_user.is_empty():
		_switching_account = false
		open_view.call_deferred("account")

func _closed() -> void:
	if not opened:
		return
	opened = false
	closed.emit()

func _failed(message: String) -> void:
	last_error = message
	failed.emit(message)
