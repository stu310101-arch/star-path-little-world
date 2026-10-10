extends Node
## Verified page-lifetime packs; the browser optionally caches their transfers.
signal pack_ready(id: String)
signal pack_failed(id: String, message: String)

const MANIFEST: String = "res://data/web_packs.json"
const DOWNLOAD_BYTES_PER_FRAME: int = 4194304
# A 2 ms budget limited the measured Web path to one 256 KiB chunk per
# rendered frame, even after the entire network transfer had completed.
# Entry is gated on the avatar and target district; allow bounded 8 ms ingestion while
# preserving overview input/rendering and the separate 4 MiB frame ceiling.
const DOWNLOAD_WORK_BUDGET_USEC: int = 8000
const READ_CHUNK_BYTES: int = 262144
const DOWNLOAD_TIMEOUT_MS: int = 600000
var _packs: Dictionary = {}
var _resources: Dictionary = {}
var _states: Dictionary = {}
var _queue: Dictionary = {}
var _errors: Dictionary = {}
var _client: HTTPClient
var _web_transport: JavaScriptObject
var _web_requested: Dictionary = {}
var _web_status: Dictionary = {}
var _web_status_ms: int = -1000
var _download_file: FileAccess
var _request_target: String = ""
var _request_sent: bool = false
var _response_started: bool = false
var _downloaded_bytes: int = 0
var _download_started_ms: int = 0
var _max_download_frame_bytes: int = 0
var _base_url: String = ""
var _directory: String = ""
var _current: String = ""
var _hasher: HashingContext
var _hashed_bytes: int = 0
var _max_download_work_ms: float = 0.0
var _completed: Dictionary = {}
var _mount_pending: bool = false
var _enabled: bool = false
var _received: int = 0
var _mounted_bytes: int = 0
var _all_requested: bool = false
var _total_bytes: int = 0
var _startup_bytes: int = 0
var _startup_ids: Array[String] = []
var _startup_notified: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web") or not FileAccess.file_exists(MANIFEST):
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary
	configure(manifest, str(JavaScriptBridge.eval("new URL('.', location.href).href")), "/tmp/little-world-packs")

func configure(manifest: Dictionary, base_url: String, directory: String) -> void:
	_enabled = true
	_packs = manifest.get("packs", {}) as Dictionary
	_total_bytes = 0
	_startup_bytes = 0
	_startup_ids.clear()
	for id: String in _packs:
		var pack: Dictionary = _packs[id]
		_total_bytes += int(pack.bytes)
		if bool(pack.get("startup", true)):
			_startup_ids.append(id)
			_startup_bytes += int(pack.bytes)
	_resources = manifest.get("resources", {}) as Dictionary
	_base_url = base_url
	_directory = directory
	DirAccess.make_dir_recursive_absolute(directory)
	_client = HTTPClient.new()
	_client.blocking_mode_enabled = false
	_client.read_chunk_size = READ_CHUNK_BYTES
	if OS.has_feature("web"):
		_web_transport = JavaScriptBridge.get_interface("LittleWorldBackgroundPacks")
		if _web_transport != null:
			_web_transport.configure(base_url)

func request_resource(path: String, priority: int = 0) -> void:
	if _enabled and _resources.has(path):
		_request_pack(str(_resources[path]), priority)

func start_all_downloads() -> void:
	if not _enabled or _all_requested:
		return
	_all_requested = true
	for id: String in _startup_ids:
		_request_pack(id, 20 if id == "avatar" else 0)

func all_resources_ready() -> bool:
	if not _enabled:
		return true
	if not _all_requested:
		return false
	for id: String in _startup_ids:
		if _states.get(id, "") != "ready":
			return false
	return true

func startup_error() -> String:
	for id: String in _startup_ids:
		var message: String = _pack_error(id)
		if not message.is_empty():
			return message
	return ""

func get_resource_progress(path: String) -> Dictionary:
	var id: String = str(_resources.get(path, ""))
	if not _enabled or id.is_empty():
		return {"phase":"ready", "received_bytes":0, "total_bytes":0, "ready":true, "error":""}
	var phase: String = str(_states.get(id, "queued" if _queue.has(id) else "idle"))
	var received: int = int(_packs[id].bytes) if phase in ["ready", "mounting"] else (_downloaded_bytes if _current == id else 0)
	if _web_transport != null and phase not in ["ready", "mounting"]:
		var status: JavaScriptObject = _web_transport.status(id)
		received = int(status.received)
	return {"phase":"error" if phase == "failed" else phase, "received_bytes":received, "total_bytes":int(_packs[id].bytes), "ready":phase == "ready", "error":_pack_error(id)}

func _request_pack(id: String, priority: int) -> void:
	# Mounting has already released its browser job. Reprioritizing it would
	# enqueue another HTTP download between verification and the next frame.
	if not _packs.has(id) or _states.get(id, "") in ["ready", "mounting", "failed"]:
		return
	for dependency: String in _packs[id].get("dependencies", []):
		_request_pack(dependency, priority + 1)
	if id != _current:
		_queue[id] = maxi(int(_queue.get(id, priority)), priority)
	# Submit the network queue immediately. It can continue while Godot's rAF
	# is suspended in another tab; scene creation still uses foreground frames.
	if _web_transport != null and (not _web_requested.has(id) or priority > int(_web_requested[id])):
		_web_requested[id] = priority
		_web_transport.enqueue(id, str(_packs[id].url), int(_packs[id].bytes), priority)

func is_resource_ready(path: String) -> bool:
	return not _enabled or not _resources.has(path) or _states.get(str(_resources[path]), "") == "ready"

func resource_error(path: String) -> String:
	return _pack_error(str(_resources.get(path, ""))) if _enabled else ""

func _pack_error(id: String) -> String:
	if _errors.has(id):
		return str(_errors[id])
	if _packs.has(id):
		for dependency: String in _packs[id].get("dependencies", []):
			var message: String = _pack_error(dependency)
			if not message.is_empty():
				return message
	return ""

func retry_failed() -> void:
	for id: String in _errors.keys():
		_states.erase(id)
		_queue[id] = 100
		if _web_transport != null:
			_web_requested.erase(id)
			_request_pack(id, 100)
	_errors.clear()

func retry_resource(path: String) -> void:
	var id: String = str(_resources.get(path, ""))
	_retry_pack(id)

func _retry_pack(id: String) -> void:
	if not _packs.has(id):
		return
	for dependency: String in _packs[id].get("dependencies", []):
		_retry_pack(dependency)
	if _errors.has(id):
		_errors.erase(id)
		_states.erase(id)
		_web_requested.erase(id)
		_request_pack(id, 100)

func _process(_delta: float) -> void:
	if not _enabled:
		return
	if _mount_pending:
		_mount_pending = false
		if not ProjectSettings.load_resource_pack(_local_path(_current), false):
			_fail("無法開啟下載內容，請重試。")
			return
		var id: String = _current
		_states[id] = "ready"
		_completed[id]["ready_ms"] = Time.get_ticks_msec()
		_mounted_bytes += int(_packs[id].bytes)
		_current = ""
		pack_ready.emit(id)
		if OS.has_feature("web") and not _startup_notified and all_resources_ready():
			_startup_notified = true
			JavaScriptBridge.eval("window.planetAllResourcesReady = true; window.dispatchEvent(new Event('planet-content-ready'));")
		return
	if not _current.is_empty():
		_download_step()
		return
	var selected: String = ""
	var priority: int = -2147483648
	for id: String in _queue:
		# Select a started browser job before reserving its MEMFS file. Otherwise
		# a newly reprioritized queued pack can wait on a bounded stream which
		# only Godot can drain, deadlocking mobile backpressure.
		if _web_transport != null:
			var browser_state: String = str(_web_transport.status(id).state)
			if browser_state not in ["downloading", "downloaded", "failed"]:
				continue
		var dependencies_ready: bool = true
		for dependency: String in _packs[id].get("dependencies", []):
			dependencies_ready = dependencies_ready and _states.get(dependency, "") == "ready"
		if dependencies_ready and int(_queue[id]) > priority:
			priority = int(_queue[id])
			selected = id
	if selected.is_empty():
		return
	_queue.erase(selected)
	_current = selected
	_states[selected] = "downloading"
	_begin_download(_base_url + str(_packs[selected].url))

func _local_path(id: String) -> String:
	return _directory.path_join(str(_packs[id].url).get_file())

func _begin_download(url: String) -> void:
	# Own the file rather than HTTPRequest.download_file: in Godot 4.7.2 its
	# unknown-length EOF success path deletes that file before request_completed.
	# Web HTTPClient reports length=-1 even when Content-Length is present.
	if not _open_download_file():
		return
	if _web_transport != null:
		return
	var expression: RegEx = RegEx.new()
	expression.compile("^(https?)://(\\[[^\\]]+\\]|[^/:?#]+)(?::([0-9]+))?([^#]*)$")
	var parts: RegExMatch = expression.search(url)
	if parts == null:
		_fail("下載網址無效，請重新開啟遊戲。")
		return
	var secure: bool = parts.get_string(1) == "https"
	var host: String = parts.get_string(2)
	var port: int = int(parts.get_string(3)) if not parts.get_string(3).is_empty() else (443 if secure else 80)
	_request_target = parts.get_string(4)
	if _request_target.is_empty():
		_request_target = "/"
	var tls: TLSOptions = TLSOptions.client() if secure else null
	if _client.connect_to_host(host, port, tls) != OK:
		_fail("無法開始下載，請檢查連線後重試。")

func _open_download_file() -> bool:
	_downloaded_bytes = 0
	_hashed_bytes = 0
	_hasher = HashingContext.new()
	_hasher.start(HashingContext.HASH_SHA256)
	_request_sent = false
	_response_started = false
	_download_started_ms = Time.get_ticks_msec()
	_completed[_current] = {"started_ms": _download_started_ms, "bytes": int(_packs[_current].bytes)}
	_download_file = FileAccess.open(_local_path(_current), FileAccess.WRITE)
	if _download_file == null:
		_fail("無法建立下載暫存，請重新開啟遊戲。")
		return false
	return _preallocate_download_file() if OS.has_feature("web") else true

func _preallocate_download_file() -> bool:
	# Web's MEMFS otherwise grows by 12.5% repeatedly, copying the preceding
	# contents. Reserve the known length once; received/hash counts, not this
	# allocated length, remain the proof that every byte actually arrived.
	if _download_file.resize(int(_packs[_current].bytes)) != OK:
		_fail("無法配置下載暫存，請關閉其他遊戲分頁後重試。")
		return false
	_download_file.seek(0)
	return true

func _download_step() -> void:
	if _web_transport != null:
		_web_download_step()
		return
	if Time.get_ticks_msec() - _download_started_ms > DOWNLOAD_TIMEOUT_MS:
		_fail("下載逾時，請檢查連線後重試。")
		return
	var status: HTTPClient.Status = _client.get_status()
	# A final read may change Web's status directly to DISCONNECTED. Complete
	# from our own byte count, not the inconsistent Web Content-Length header.
	if _response_started and status in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
		_finish_download()
		return
	if status != HTTPClient.STATUS_DISCONNECTED:
		_client.poll() # Web permits progress only once per browser frame.
	status = _client.get_status()
	if status in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
		_fail("下載連線中斷（狀態 %d），請重試。" % status)
		return
	if status == HTTPClient.STATUS_DISCONNECTED:
		if _response_started:
			_finish_download()
		else:
			_fail("下載連線中斷，請重試。")
		return
	if status == HTTPClient.STATUS_CONNECTED:
		if _request_sent:
			# No-body responses can transition directly to CONNECTED on native.
			if not _begin_response():
				return
			_finish_download()
		else:
			var headers: PackedStringArray = PackedStringArray()
			# Fetch handles gzip/Brotli decoding in Web. Native fixtures request
			# identity because HTTPClient itself does not decompress the body.
			if not OS.has_feature("web"):
				headers.append("Accept-Encoding: identity")
			if _client.request(HTTPClient.METHOD_GET, _request_target, headers) != OK:
				_fail("無法送出下載要求，請重試。")
				return
			_request_sent = true
		return
	if status != HTTPClient.STATUS_BODY:
		return
	if not _response_started and not _begin_response():
		return
	var frame_bytes: int = 0
	var work_started: int = Time.get_ticks_usec()
	while _client.get_status() == HTTPClient.STATUS_BODY and frame_bytes < DOWNLOAD_BYTES_PER_FRAME:
		var chunk: PackedByteArray = _client.read_response_body_chunk()
		if chunk.is_empty():
			break
		if _downloaded_bytes + chunk.size() > int(_packs[_current].bytes):
			_fail("下載內容超過預期大小，請重試。")
			return
		_download_file.store_buffer(chunk)
		if _download_file.get_error() != OK:
			_fail("無法儲存下載內容，請重試。")
			return
		# Hash exactly the successfully written bytes while receiving them. A
		# second whole-file sweep imposed another 98+ rendered frames on the
		# avatar pack. Final size and SHA are still required before mounting.
		_hasher.update(chunk)
		_hashed_bytes += chunk.size()
		_downloaded_bytes += chunk.size()
		frame_bytes += chunk.size()
		if Time.get_ticks_usec() - work_started >= DOWNLOAD_WORK_BUDGET_USEC:
			break
	_max_download_frame_bytes = maxi(_max_download_frame_bytes, frame_bytes)
	_max_download_work_ms = maxf(_max_download_work_ms, float(Time.get_ticks_usec() - work_started) / 1000.0)
	status = _client.get_status()
	if status in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
		_finish_download()
	elif status == HTTPClient.STATUS_CONNECTION_ERROR:
		_fail("下載連線中斷，請重試。")

func _web_download_step() -> void:
	var status: JavaScriptObject = _web_transport.status(_current)
	if str(status.state) == "failed":
		_fail(str(status.error))
		return
	if not str(status.state) in ["downloading", "downloaded"]:
		return
	var started: int = Time.get_ticks_usec()
	var frame_bytes: int = 0
	var available: int = int(status.received)
	while _downloaded_bytes < available and frame_bytes < DOWNLOAD_BYTES_PER_FRAME:
		var buffer: JavaScriptObject = _web_transport.read(_current, _downloaded_bytes, READ_CHUNK_BYTES)
		var chunk: PackedByteArray = JavaScriptBridge.js_buffer_to_packed_byte_array(buffer)
		if chunk.is_empty():
			break
		_download_file.store_buffer(chunk)
		if _download_file.get_error() != OK:
			_fail("無法儲存下載內容，請重試。")
			return
		_hasher.update(chunk)
		_hashed_bytes += chunk.size()
		_downloaded_bytes += chunk.size()
		frame_bytes += chunk.size()
		_web_transport.consume(_current, _downloaded_bytes)
		if Time.get_ticks_usec() - started >= DOWNLOAD_WORK_BUDGET_USEC:
			break
	_max_download_frame_bytes = maxi(_max_download_frame_bytes, frame_bytes)
	_max_download_work_ms = maxf(_max_download_work_ms, float(Time.get_ticks_usec() - started) / 1000.0)
	if str(status.state) == "downloaded" and _downloaded_bytes == int(_packs[_current].bytes):
		_completed[_current]["browser_network_started_ms"] = float(status.started)
		_completed[_current]["browser_network_finished_ms"] = float(status.finished)
		_web_transport.release(_current)
		_finish_download()

func _begin_response() -> bool:
	if not _client.has_response():
		_fail("伺服器沒有回應，請重試。")
		return false
	var code: int = _client.get_response_code()
	if code != 200:
		_fail("找不到遊戲內容（HTTP 404），請重新整理後再試。" if code == 404 else "下載失敗（HTTP %d），請重試。" % code)
		return false
	_response_started = true
	_completed[_current]["response_started_ms"] = Time.get_ticks_msec()
	return true

func _finish_download() -> void:
	_close_network()
	if _downloaded_bytes != int(_packs[_current].bytes):
		_fail("下載不完整（%d / %d bytes），請重試。" % [_downloaded_bytes, int(_packs[_current].bytes)])
		return
	var written: FileAccess = FileAccess.open(_local_path(_current), FileAccess.READ)
	if written == null or written.get_length() != int(_packs[_current].bytes) or _hashed_bytes != _downloaded_bytes:
		_fail("下載不完整，請重試。")
		return
	written.close()
	_completed[_current]["received_ms"] = Time.get_ticks_msec()
	var actual: String = _hasher.finish().hex_encode()
	_hasher = null
	if actual != str(_packs[_current].sha256):
		_fail("下載內容驗證失敗，請重試。")
		return
	_received += _downloaded_bytes
	_completed[_current]["verified_ms"] = Time.get_ticks_msec()
	_states[_current] = "mounting"
	_mount_pending = true

func _close_network() -> void:
	if _client != null:
		_client.close()
	if _download_file != null:
		_download_file.close()
		_download_file = null

func _fail(message: String) -> void:
	var id: String = _current
	_close_network()
	_hasher = null
	_mount_pending = false
	# Verification counted this file, but a mount failure discards it. Remove
	# those bytes so a retry cannot report the same pack as received twice.
	if _states.get(id, "") == "mounting":
		_received -= int(_packs[id].bytes)
	_states[id] = "failed"
	_errors[id] = message
	if _web_transport != null:
		_web_transport.invalidate(id)
		_web_transport.release(id)
		_web_requested.erase(id)
	DirAccess.remove_absolute(_local_path(id))
	_current = ""
	pack_failed.emit(id, message)

func _exit_tree() -> void:
	_close_network()
	_hasher = null
	if _web_transport != null:
		_web_transport.close()
	if not _current.is_empty():
		DirAccess.remove_absolute(_local_path(_current))

func get_status() -> Dictionary:
	var loaded: int = 0
	for state: String in _states.values():
		if state == "ready":
			loaded += 1
	var current_bytes: int = _downloaded_bytes if not _current.is_empty() else 0
	var expected: int = int(_packs[_current].bytes) if not _current.is_empty() else 0
	if _web_transport != null and Time.get_ticks_msec() - _web_status_ms >= 100:
		_web_status = JSON.parse_string(str(_web_transport.snapshotJson())) as Dictionary
		_web_status_ms = Time.get_ticks_msec()
	var startup_received: int = 0
	for id: String in _startup_ids:
		if _states.get(id, "") in ["ready", "mounting"]:
			startup_received += int(_packs[id].bytes)
	var network_bytes: int = startup_received
	if _web_transport != null:
		for job: Dictionary in _web_status.get("jobs", []):
			if str(job.id) in _startup_ids and not _states.get(str(job.id), "") in ["ready", "mounting"]:
				network_bytes += int(job.received)
	else:
		if _current in _startup_ids and _states.get(_current, "") == "downloading":
			network_bytes += current_bytes
	return {"enabled":_enabled, "current":_current, "state":_states.get(_current, "idle"), "downloaded_bytes":current_bytes, "expected_bytes":expected, "ready_packs":loaded, "queued_packs":_queue.size(), "received_bytes":_received, "mounted_bytes":_mounted_bytes, "errors":_errors.duplicate(), "transport":"background_fetch" if _web_transport != null else "http_client", "background":_web_status, "max_download_frame_bytes":_max_download_frame_bytes, "hashed_bytes":_hashed_bytes, "max_download_work_ms":_max_download_work_ms, "download_work_budget_ms":float(DOWNLOAD_WORK_BUDGET_USEC)/1000.0, "pack_timings":_completed.duplicate(true), "all_requested":_all_requested, "all_ready":all_resources_ready(), "total_packs":_packs.size(), "startup_packs":_startup_ids.size(), "all_pack_bytes":_total_bytes, "total_bytes":_startup_bytes, "network_received_bytes":mini(network_bytes, _startup_bytes)}
