extends SceneTree

const Loader = preload("res://scripts/web_packs.gd")

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
	var loader: Node = Loader.new()
	root.add_child(loader)
	loader.call("configure", manifest, "http://127.0.0.1:8947/build/pack-fixtures/", fixture_dir.path_join("downloads"))
	check(not bool(loader.call("is_resource_ready", b)), "deferred resource starts unavailable")
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
	check(int((loader.call("get_status") as Dictionary).max_download_frame_bytes) <= 524288, "download writes stay within 512 KiB per frame")
	loader.queue_free()
	await process_frame
	await check_http_framing()
	print("WEB_PACK_CHECKS ", checks - failures.size(), "/", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

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
	var loader: Node = Loader.new()
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
	loader.queue_free()
	server.queue_free()
	await process_frame
