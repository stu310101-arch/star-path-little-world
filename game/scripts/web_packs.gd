extends Node
## Page-lifetime resource packs. No Service Worker, Cache Storage or IDB files.
signal pack_ready(id: String)
signal pack_failed(id: String, message: String)

const MANIFEST: String = "res://data/web_packs.json"
const VERIFY_BYTES_PER_FRAME: int = 524288
const DOWNLOAD_BYTES_PER_FRAME: int = 524288
const READ_CHUNK_BYTES: int = 65536
const DOWNLOAD_TIMEOUT_MS: int = 600000
var _packs: Dictionary = {}
var _resources: Dictionary = {}
var _states: Dictionary = {}
var _queue: Dictionary = {}
var _errors: Dictionary = {}
var _client: HTTPClient
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
var _verify_file: FileAccess
var _hasher: HashingContext
var _mount_pending: bool = false
var _enabled: bool = false
var _received: int = 0
var _mounted_bytes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web") or not FileAccess.file_exists(MANIFEST):
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary
	configure(manifest, str(JavaScriptBridge.eval("new URL('.', location.href).href")), "/tmp/little-world-packs")

func configure(manifest: Dictionary, base_url: String, directory: String) -> void:
	_enabled = true
	_packs = manifest.get("packs", {}) as Dictionary
	_resources = manifest.get("resources", {}) as Dictionary
	_base_url = base_url
	_directory = directory
	DirAccess.make_dir_recursive_absolute(directory)
	_client = HTTPClient.new()
	_client.blocking_mode_enabled = false
	_client.read_chunk_size = READ_CHUNK_BYTES

func request_resource(path: String, priority: int = 0) -> void:
	if _enabled and _resources.has(path):
		_request_pack(str(_resources[path]), priority)

func _request_pack(id: String, priority: int) -> void:
	if not _packs.has(id) or _states.get(id, "") in ["ready", "failed"]:
		return
	for dependency: String in _packs[id].get("dependencies", []):
		_request_pack(dependency, priority + 1)
	if id != _current:
		_queue[id] = maxi(int(_queue.get(id, priority)), priority)

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
	_errors.clear()

func _process(_delta: float) -> void:
	if not _enabled:
		return
	if _verify_file != null:
		var remaining: int = _verify_file.get_length() - _verify_file.get_position()
		if remaining > 0:
			_hasher.update(_verify_file.get_buffer(mini(remaining, VERIFY_BYTES_PER_FRAME)))
			return
		_verify_file = null
		var actual: String = _hasher.finish().hex_encode()
		_hasher = null
		if actual != str(_packs[_current].sha256):
			_fail("下載內容驗證失敗，請重試。")
		else:
			_mount_pending = true
		return
	if _mount_pending:
		_mount_pending = false
		if not ProjectSettings.load_resource_pack(_local_path(_current), false):
			_fail("無法開啟下載內容，請重試。")
			return
		var id: String = _current
		_states[id] = "ready"
		_mounted_bytes += int(_packs[id].bytes)
		_current = ""
		pack_ready.emit(id)
		return
	if not _current.is_empty():
		_download_step()
		return
	var selected: String = ""
	var priority: int = -2147483648
	for id: String in _queue:
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
	_downloaded_bytes = 0
	_request_sent = false
	_response_started = false
	_download_started_ms = Time.get_ticks_msec()
	_download_file = FileAccess.open(_local_path(_current), FileAccess.WRITE)
	if _download_file == null:
		_fail("無法建立下載暫存，請重新開啟遊戲。")
		return
	var tls: TLSOptions = TLSOptions.client() if secure else null
	if _client.connect_to_host(host, port, tls) != OK:
		_fail("無法開始下載，請檢查連線後重試。")

func _download_step() -> void:
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
		_downloaded_bytes += chunk.size()
		frame_bytes += chunk.size()
	_max_download_frame_bytes = maxi(_max_download_frame_bytes, frame_bytes)
	status = _client.get_status()
	if status in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
		_finish_download()
	elif status == HTTPClient.STATUS_CONNECTION_ERROR:
		_fail("下載連線中斷，請重試。")

func _begin_response() -> bool:
	if not _client.has_response():
		_fail("伺服器沒有回應，請重試。")
		return false
	var code: int = _client.get_response_code()
	if code != 200:
		_fail("找不到遊戲內容（HTTP 404），請重新整理後再試。" if code == 404 else "下載失敗（HTTP %d），請重試。" % code)
		return false
	_response_started = true
	return true

func _finish_download() -> void:
	_close_network()
	if _downloaded_bytes != int(_packs[_current].bytes):
		_fail("下載不完整（%d / %d bytes），請重試。" % [_downloaded_bytes, int(_packs[_current].bytes)])
		return
	_verify_file = FileAccess.open(_local_path(_current), FileAccess.READ)
	if _verify_file == null or _verify_file.get_length() != int(_packs[_current].bytes):
		_verify_file = null
		_fail("下載不完整，請重試。")
		return
	_received += _verify_file.get_length()
	_states[_current] = "verifying"
	_hasher = HashingContext.new()
	_hasher.start(HashingContext.HASH_SHA256)

func _close_network() -> void:
	if _client != null:
		_client.close()
	if _download_file != null:
		_download_file.close()
		_download_file = null

func _fail(message: String) -> void:
	var id: String = _current
	_close_network()
	_verify_file = null
	_hasher = null
	_mount_pending = false
	_states[id] = "failed"
	_errors[id] = message
	DirAccess.remove_absolute(_local_path(id))
	_current = ""
	pack_failed.emit(id, message)

func _exit_tree() -> void:
	_close_network()
	_verify_file = null
	if not _current.is_empty():
		DirAccess.remove_absolute(_local_path(_current))

func get_status() -> Dictionary:
	var loaded: int = 0
	for state: String in _states.values():
		if state == "ready":
			loaded += 1
	var current_bytes: int = _downloaded_bytes if not _current.is_empty() else 0
	var expected: int = int(_packs[_current].bytes) if not _current.is_empty() else 0
	return {"enabled":_enabled, "current":_current, "state":_states.get(_current, "idle"), "downloaded_bytes":current_bytes, "expected_bytes":expected, "ready_packs":loaded, "queued_packs":_queue.size(), "received_bytes":_received, "mounted_bytes":_mounted_bytes, "errors":_errors.duplicate(), "transport":"http_client", "max_download_frame_bytes":_max_download_frame_bytes}
