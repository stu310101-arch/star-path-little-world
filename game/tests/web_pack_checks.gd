extends SceneTree

const Loader = preload("res://scripts/web_packs.gd")

# Exercise the same FileAccess allocation on native without spoofing Web.
# The framing cases below must still reject short/oversize/corrupted bodies
# even though the temporary file already has the expected final length.
class PreallocatingLoader extends Loader:
	var allocations: Array[Dictionary] = []

	func _open_download_file() -> bool:
		if not super._open_download_file():
			return false
		if not _preallocate_download_file():
			return false
		allocations.append({"length": _download_file.get_length(), "expected": int(_packs[_current].bytes), "position": _download_file.get_position(), "received": _downloaded_bytes, "hashed": _hashed_bytes})
		return true

# Native cannot construct the browser's JavaScriptObject. Trace recursive
# requests to verify that a mounting pack returns before dependency/network
# reprioritization; the headed browser suite checks actual request counts.
class RequestTracingLoader extends PreallocatingLoader:
	var requests: Array[String] = []

	func _request_pack(id: String, priority: int) -> void:
		requests.append(id)
		super._request_pack(id, priority)

# Exercise actual HTTPClient wire framing, especially EOF without Content-Length.
# Web uses that mode even when Fetch receives a Content-Length response header.
class FramingServer extends Node:
	var server: TCPServer = TCPServer.new()
	var routes: Dictionary = {}
	var peers: Array[Dictionary] = []

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			peers.append({"peer": server.take_connection(), "request": "", "response": PackedByteArray(), "offset": 0})
		for index: int in range(peers.size() - 1, -1, -1):
			var state: Dictionary = peers[index]
			var peer: StreamPeerTCP = state.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				peers.remove_at(index)
				continue
			if (state.response as PackedByteArray).is_empty():
				var available: int = peer.get_available_bytes()
				if available > 0:
					var incoming: Array = peer.get_data(available)
					state.request += (incoming[1] as PackedByteArray).get_string_from_utf8()
				if not str(state.request).contains("\r\n\r\n"):
					continue
				var target: String = str(state.request).split(" ")[1]
				state.response = response(routes.get(target, {"code": 404, "body": PackedByteArray()}) as Dictionary)
			var bytes: PackedByteArray = state.response
			var sent: Array = peer.put_partial_data(bytes.slice(int(state.offset), mini(int(state.offset) + 65536, bytes.size())))
			state.offset = int(state.offset) + int(sent[1])
			if int(sent[0]) != OK or int(state.offset) == bytes.size():
				peer.disconnect_from_host()
				peers.remove_at(index)

	func response(route: Dictionary) -> PackedByteArray:
		var body: PackedByteArray = route.body
		var code: int = int(route.get("code", 200))
		if bool(route.get("chunked", false)):
			var bytes: PackedByteArray = ("HTTP/1.1 %d Fixture\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n" % code).to_utf8_buffer()
			for offset: int in range(0, body.size(), 4096):
				var chunk: PackedByteArray = body.slice(offset, mini(offset + 4096, body.size()))
				bytes.append_array(("%x\r\n" % chunk.size()).to_utf8_buffer())
				bytes.append_array(chunk)
				bytes.append_array("\r\n".to_utf8_buffer())
			bytes.append_array("0\r\n\r\n".to_utf8_buffer())
			return bytes
		var bytes: PackedByteArray = ("HTTP/1.0 %d Fixture\r\nConnection: close\r\n\r\n" % code).to_utf8_buffer()
		bytes.append_array(body)
		return bytes

	func _exit_tree() -> void:
		for state: Dictionary in peers:
			(state.peer as StreamPeerTCP).disconnect_from_host()
		peers.clear()
		server.stop()

var checks: int = 0
var failures: Array[String] = []
var fixture_dir: String

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func make_pack(name: String, resource: String, repetitions: int = 300000) -> Dictionary:
	var source: String = fixture_dir.path_join(name + ".txt")
	var file: FileAccess = FileAccess.open(source, FileAccess.WRITE)
	file.store_string(name.repeat(repetitions))
	file.close()
	var target: String = fixture_dir.path_join(name + ".pck")
	var pack: PCKPacker = PCKPacker.new()
	check(pack.pck_start(target) == OK, "start pack " + name)
	check(pack.add_file(resource, source) == OK, "add resource " + name)
	check(pack.flush() == OK, "flush pack " + name)
	return {"url": name + ".pck", "bytes": FileAccess.get_file_as_bytes(target).size(), "sha256": FileAccess.get_sha256(target), "dependencies": []}

func wait_pack(loader: Node, resource: String, expect_error: bool = false) -> void:
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if bool(loader.call("is_resource_ready", resource)) or not str(loader.call("resource_error", resource)).is_empty():
			break
		await process_frame
	check(not str(loader.call("resource_error", resource)).is_empty() if expect_error else bool(loader.call("is_resource_ready", resource)), "completion: " + resource)

func run() -> void:
	fixture_dir = ProjectSettings.globalize_path("res://../build/pack-fixtures")
	DirAccess.make_dir_recursive_absolute(fixture_dir)
	var a: String = "res://pack_fixture/base.txt"
	var b: String = "res://pack_fixture/dependent.txt"
	var c: String = "res://pack_fixture/bad.txt"
	var manifest: Dictionary = {"version": 1, "resources": {a: "base", b: "dependent", c: "bad"}, "packs": {}}
	manifest.packs.base = make_pack("base", a)
	manifest.packs.dependent = make_pack("dependent", b)
	manifest.packs.dependent.dependencies = ["base"]
	manifest.packs.bad = make_pack("bad", c)
	var expected: PackedByteArray = FileAccess.get_file_as_bytes(fixture_dir.path_join("bad.pck"))
	var corrupt: FileAccess = FileAccess.open(fixture_dir.path_join("bad.pck"), FileAccess.READ_WRITE)
	corrupt.seek(128)
	corrupt.store_8(corrupt.get_8() ^ 255)
	corrupt.close()
	var loader: PreallocatingLoader = PreallocatingLoader.new()
	root.add_child(loader)
	loader.call("configure", manifest, "http://127.0.0.1:8947/build/pack-fixtures/", fixture_dir.path_join("downloads"))
	check(not bool(loader.call("is_resource_ready", b)), "deferred resource starts unavailable")
	check(not bool(loader.call("all_resources_ready")), "complete game remains gated before startup download")
	check(bool(loader.call("is_resource_ready", "res://boot.txt")), "boot path is ready")
	loader.call("request_resource", b, 10)
	await wait_pack(loader, b)
	check(FileAccess.file_exists(a) and FileAccess.file_exists(b), "dependency and requested resource both mounted")
	var received: int = int((loader.call("get_status") as Dictionary).received_bytes)
	loader.call("request_resource", b, 10)
	for frame: int in range(5):
		await process_frame
	check(int((loader.call("get_status") as Dictionary).received_bytes) == received, "repeat requests do not redownload")
	loader.call("request_resource", c)
	await wait_pack(loader, c, true)
	check(not FileAccess.file_exists(c), "corrupt pack is never mounted")
	var restored: FileAccess = FileAccess.open(fixture_dir.path_join("bad.pck"), FileAccess.WRITE)
	restored.store_buffer(expected)
	restored.close()
	loader.call("retry_failed")
	await wait_pack(loader, c)
	check(FileAccess.file_exists(c), "retry mounts validated pack")
	check(int((loader.call("get_status") as Dictionary).ready_packs) == 3, "three packs mounted exactly once")
	check(int((loader.call("get_status") as Dictionary).max_download_frame_bytes) <= 4194304, "download writes remain bounded to 4 MiB per frame")
	loader.call("start_all_downloads")
	check(bool(loader.call("all_resources_ready")), "startup readiness requires every pack mounted")
	var timings: Dictionary = (loader.call("get_status") as Dictionary).pack_timings
	for id: String in timings:
		check(int(timings[id].verified_ms) - int(timings[id].received_ms) < 100, "incremental SHA needs no second full-file frame sweep for " + id)
	check_preallocation(loader)
	loader.queue_free()
	await process_frame
	await check_mounting_retry()
	await check_http_framing()
	check_indoor_startup_partition()
	print("WEB_PACK_CHECKS ", checks - failures.size(), "/", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func check_indoor_startup_partition() -> void:
	var loader: Loader = Loader.new()
	root.add_child(loader)
	loader.set_process(false)
	var manifest: Dictionary = {"packs":{"outside":{"url":"outside.pck", "bytes":100, "dependencies":[]}, "training_room":{"url":"inside.pck", "bytes":200, "dependencies":["outside"], "startup":false}}, "resources":{"res://inside.res":"training_room"}}
	loader.configure(manifest, "http://127.0.0.1:8947/", fixture_dir.path_join("partition"))
	loader.start_all_downloads()
	check(loader._queue.has("outside") and not loader._queue.has("training_room"), "startup excludes complete indoor pack")
	loader._states["outside"] = "ready"
	check(loader.all_resources_ready(), "unrequested indoor detail does not block roaming")
	loader._errors["training_room"] = "fixture failure"
	check(loader.startup_error().is_empty(), "indoor failure does not block outdoor play")
	loader._errors.clear()
	loader.request_resource("res://inside.res", 200)
	check(loader._queue.has("training_room"), "indoor entry requests its complete pack")
	check(int(loader.get_status().total_bytes) == 100 and int(loader.get_status().all_pack_bytes) == 300, "startup progress excludes on-demand bytes")
	check(str(loader.get_resource_progress("res://inside.res").phase) == "queued", "indoor progress distinguishes queued phase")
	loader.free()

func check_mounting_retry() -> void:
	var base: String = "res://pack_fixture/retry_base.txt"
	var target: String = "res://pack_fixture/retry_target.txt"
	var manifest: Dictionary = {"version": 1, "resources": {base: "retry_base", target: "retry_target"}, "packs": {}}
	manifest.packs.retry_base = make_pack("retry_base", base, 2000)
	manifest.packs.retry_target = make_pack("retry_target", target, 2000)
	manifest.packs.retry_target.dependencies = ["retry_base"]
	var total: int = int(manifest.packs.retry_base.bytes) + int(manifest.packs.retry_target.bytes)
	var loader: RequestTracingLoader = RequestTracingLoader.new()
	root.add_child(loader)
	# Drive the real download state machine manually so the fixture can stop
	# exactly after SHA verification, before the next-frame mount attempt.
	loader.set_process(false)
	loader.configure(manifest, "http://127.0.0.1:8947/build/pack-fixtures/", fixture_dir.path_join("mount-retry-downloads"))
	loader.start_all_downloads()
	for attempt: int in range(2):
		var deadline: int = Time.get_ticks_msec() + 15000
		while loader._states.get("retry_target", "") != "mounting" and Time.get_ticks_msec() < deadline:
			loader._process(0.0)
			await process_frame
		if loader._states.get("retry_target", "") != "mounting":
			check(false, "HTTP retry reaches verified mounting boundary")
			loader.queue_free()
			await process_frame
			return
		check(int(loader.get_status().received_bytes) == total, "verified bytes count each pack once before mount attempt %d" % attempt)
		check(not loader.all_resources_ready(), "verified but unmounted content keeps play gated")
		loader.requests.clear()
		loader.request_resource(target, 1000 + attempt)
		check(loader.requests == ["retry_target"] and loader._queue.is_empty(), "higher priority cannot resubmit a mounting pack or its dependencies")
		# Inject the same failure transition used by load_resource_pack(false),
		# with real verified bytes. The next attempt uses real HTTP and mounting.
		loader._fail("Injected mount failure")
		check(int(loader.get_status().received_bytes) == int(manifest.packs.retry_base.bytes), "mount failure removes only its discarded verified bytes")
		check(not loader.all_resources_ready() and not loader.resource_error(target).is_empty(), "mount failure remains retryable and keeps play gated")
		loader.retry_failed()
		check(loader.resource_error(target).is_empty(), "retry clears the mount failure")
	loader.set_process(true)
	await wait_pack(loader, target)
	var status: Dictionary = loader.get_status()
	check(loader.all_resources_ready() and int(status.ready_packs) == 2, "retried content mounts and releases the startup gate")
	check(int(status.received_bytes) == total and int(status.network_received_bytes) == total and int(status.mounted_bytes) == total, "two mount retries never inflate download or mounted byte totals")
	check_preallocation(loader)
	loader.queue_free()
	await process_frame

func check_preallocation(loader: PreallocatingLoader) -> void:
	check(not loader.allocations.is_empty(), "fixture exercised download preallocation")
	for allocation: Dictionary in loader.allocations:
		check(int(allocation.length) == int(allocation.expected) and int(allocation.position) == 0 and int(allocation.received) == 0 and int(allocation.hashed) == 0, "preallocation reserves exact length at cursor zero without claiming received/hashed bytes")

func check_http_framing() -> void:
	var server: FramingServer = FramingServer.new()
	root.add_child(server)
	var result: Error = server.server.listen(18948, "127.0.0.1")
	check(result == OK, "local framing fixture listens")
	if result != OK:
		server.queue_free()
		await process_frame
		return
	var manifest: Dictionary = {"version": 1, "resources": {}, "packs": {}}
	for name: String in ["eof", "chunked", "short", "oversize", "missing"]:
		var resource: String = "res://pack_fixture/" + name + ".txt"
		manifest.resources[resource] = name
		manifest.packs[name] = make_pack(name, resource, 2000)
		var body: PackedByteArray = FileAccess.get_file_as_bytes(fixture_dir.path_join(name + ".pck"))
		if name == "short":
			body.resize(body.size() - 17)
		elif name == "oversize":
			body.append_array("unexpected bytes".to_utf8_buffer())
		server.routes["/" + name + ".pck"] = {"body": body, "chunked": name == "chunked", "code": 404 if name == "missing" else 200}
	var loader: PreallocatingLoader = PreallocatingLoader.new()
	root.add_child(loader)
	var directory: String = fixture_dir.path_join("framing-downloads")
	loader.call("configure", manifest, "http://127.0.0.1:18948/", directory)
	for name: String in ["eof", "chunked"]:
		var resource: String = "res://pack_fixture/" + name + ".txt"
		loader.call("request_resource", resource)
		await wait_pack(loader, resource)
		check(FileAccess.file_exists(resource), name + " response mounts the validated pack")
		check(FileAccess.get_sha256(directory.path_join(name + ".pck")) == str(manifest.packs[name].sha256), name + " final file survives HTTP connection close")
	for name: String in ["short", "oversize", "missing"]:
		var resource: String = "res://pack_fixture/" + name + ".txt"
		loader.call("request_resource", resource)
		await wait_pack(loader, resource, true)
		check(not FileAccess.file_exists(resource), name + " response is never mounted")
		check(not FileAccess.file_exists(directory.path_join(name + ".pck")), name + " partial file is removed")
		if name == "missing":
			check(str(loader.call("resource_error", resource)).contains("請重新整理"), "404 recommends refreshing stale page")
		server.routes["/" + name + ".pck"] = {"body": FileAccess.get_file_as_bytes(fixture_dir.path_join(name + ".pck"))}
	loader.call("retry_failed")
	for name: String in ["short", "oversize", "missing"]:
		await wait_pack(loader, "res://pack_fixture/" + name + ".txt")
	check(int((loader.call("get_status") as Dictionary).ready_packs) == 5, "all framing and failed-response retries mount exactly once")
	check_preallocation(loader)
	loader.queue_free()
	server.queue_free()
	await process_frame
