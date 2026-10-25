extends SceneTree

const NativeHost = preload("res://scripts/account_native_host.gd")
const Startup = preload("res://tests/startup_fixture.gd")
const Terminal = preload("res://scripts/account_terminal_frame.gd")

class FakeAccount:
	extends Node
	signal state_changed(user: Dictionary)
	signal closed
	var user: Dictionary = {}
	var last_error: String = "測試：帳號服務無法開啟"
	var views: Array[String] = []
	var accept: bool = true
	func open_view(view: String) -> bool:
		views.append(view)
		return accept
	func close_view() -> void:
		closed.emit()
	func sign_out() -> void:
		user = {}
		state_changed.emit(user)

var failures: int = 0
func _initialize() -> void:
	run.call_deferred()

func check(label_text: String, passed: bool) -> void:
	print("ACCOUNT_CHECK ", label_text, " passed=", passed)
	if not passed:
		failures += 1

func run() -> void:
	var desktop: Rect2 = Terminal.panel_rect(Vector2(1440, 900))
	check("Desktop terminal leaves the 3D room visible", desktop.position.x > 200 and desktop.size.x < 1200 and desktop.size.y < 800)
	var phone: Rect2 = Terminal.panel_rect(Vector2(390, 844), true)
	check("Phone terminal keeps usable screen and a room perimeter", phone.size.x == 374 and phone.position.x == 8 and phone.size.y > 750)
	check("Native uses fixed HTTPS account host", NativeHost.allowed_host_url(NativeHost.HOST + "?platform=native&view=query"))
	for view: String in ["general", "special", "apcs"]:
		check("Native permits workbench " + view, NativeHost.allowed_host_url(NativeHost.HOST + "?platform=native&view=" + view))
	for url: String in ["https://evil.test/admissions/host/?platform=native&view=query", NativeHost.HOST + "?platform=web&view=account", NativeHost.HOST + "?platform=native&view=other"]:
		check("Reject untrusted host " + url, not NativeHost.allowed_host_url(url))
	check("Native handoff is permitted", NativeHost.allowed_external_url(NativeHost.ORIGIN + "/admissions/account/native/?request=test"))
	check("Official admissions reference opens externally", NativeHost.allowed_external_url("https://www.cac.edu.tw/apply115/system/ColQry_115xappLyfOrStu_Azd5gP29/TotalGsdShow.htm"))
	for url: String in ["https://www.cac.edu.tw.evil.test/", "https://www.cac.edu.tw@evil.test/", "https://evil.test@www.cac.edu.tw/", "https://www.cac.edu.tw:8443/", "http://www.cac.edu.tw/", "https://www.cac.edu.tw/\n", "https://www.cac.edu.tw/account/login", "https://www.cac.edu.tw/apply115/system/../elsewhere"]:
		check("Reject spoofed official origin " + url, not NativeHost.allowed_external_url(url))
	for url: String in ["https://evil.test/", NativeHost.ORIGIN + ".evil.test/admissions/account/native/", NativeHost.ORIGIN + "/admissions/account/native/../", NativeHost.ORIGIN + "/admissions/account/native/#secret"]:
		check("Reject external navigation " + url, not NativeHost.allowed_external_url(url))
	check("Only display fields survive IPC", NativeHost.sanitize_user({"signedIn":true, "uid":"student", "displayName":"星", "idToken":"secret"}) == {"signedIn":true, "displayName":"星"})
	check("UID without explicit sign-in state is rejected", NativeHost.sanitize_user({"uid":"student"}) == null)
	check("Malformed sign-in state is rejected", NativeHost.sanitize_user({"signedIn":1}) == null)
	check("Null user clears state", NativeHost.sanitize_user(null) == {})
	var service := FakeAccount.new()
	service.name = "StarPathAccount"
	root.add_child(service)
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	check("World uses shared root account", world.get("account") == service)
	world.call("set_overview", false)
	check("World becomes playable", await Startup.wait_roaming(world, self))
	var player: PlanetPlayer = world.get("player") as PlanetPlayer
	var hud: CanvasLayer = world.get("hud") as CanvasLayer
	var position: Vector3 = player.global_position
	var heading: Vector3 = player.heading
	var camera: Camera3D = world.get("camera") as Camera3D
	var camera_transform: Transform3D = camera.global_transform
	check("Account opens from anywhere", bool(world.call("open_account", "scores")))
	check("Account reveals world around terminal without HUD clutter", not hud.visible)
	check("Account stops movement", bool(world.get("paused")) and not player.controls_enabled)
	check("Account freezes other modals", (hud.get("settings_button") as Button).disabled)
	service.close_view()
	check("Close restores controls and location", not bool(world.get("paused")) and player.controls_enabled and player.global_position.is_equal_approx(position) and player.heading.is_equal_approx(heading))
	check("Anywhere account preserves camera and restores HUD", camera.global_transform.is_equal_approx(camera_transform) and hud.visible)
	service.user = {"signedIn":true, "displayName":"小星"}
	service.state_changed.emit(service.user)
	check("HUD reflects account without tokens", (hud.get("account_button") as Button).text == "帳號" and (hud.get("sign_out_button") as Button).visible)
	service.sign_out()
	check("Sign out updates HUD", (hud.get("account_button") as Button).text == "登入" and not (hud.get("sign_out_button") as Button).visible)
	world.call("teleport_to", "admissions")
	check("Admissions arrival becomes ready", await Startup.wait_roaming(world, self))
	position = player.global_position
	heading = player.heading
	world.call("open_station", "admissions")
	var deadline: int = Time.get_ticks_msec() + 6000
	while current_scene == world and Time.get_ticks_msec() < deadline:
		await process_frame
	var room: Node3D = current_scene as Node3D
	check("Admissions enters walkable room after animation", room != null and room != world and room.has_signal("request_return_to_world"))
	if room == null or room == world:
		quit(1)
		return
	check("Shared account stays alive outside suspended world", service.is_inside_tree() and not world.is_inside_tree())
	deadline = Time.get_ticks_msec() + 10000
	while room.get("ready_for_play") != true and Time.get_ticks_msec() < deadline:
		await process_frame
	var room_player: CharacterBody3D = room.get("player") as CharacterBody3D
	var room_camera: Camera3D = room.get("camera") as Camera3D
	var room_bridge: Node = room.get("account_bridge") as Node
	check("Room prepares a shared account workbench bridge", room_bridge != null and room.get("ready_for_play") == true)
	if room_bridge != null:
		for view: String in ["general", "special", "apcs", "scores", "account"]:
			var before_player: Transform3D = room_player.global_transform
			var before_camera: Transform3D = room_camera.global_transform
			var accepted: bool = bool(room_bridge.call("open_view", view))
			var view_count: int = service.views.size()
			deadline = Time.get_ticks_msec() + 2000
			while service.views.size() == view_count and Time.get_ticks_msec() < deadline:
				await process_frame
			check("Room opens " + view, accepted and not service.views.is_empty() and service.views.back() == view)
			check("Workbench freezes player " + view, room_player.process_mode == Node.PROCESS_MODE_DISABLED)
			service.close_view()
			check("Workbench restores player/camera " + view, room_player.global_transform.is_equal_approx(before_player) and room_camera.global_transform.is_equal_approx(before_camera) and not bool(room_bridge.call("is_open")))
	room.emit_signal("request_return_to_world")
	deadline = Time.get_ticks_msec() + 3000
	while current_scene != world and Time.get_ticks_msec() < deadline:
		await process_frame
	print("ACCOUNT_RETURN position_delta=", player.global_position.distance_to(position), " heading_delta=", player.heading.distance_to(heading))
	check("Station return restores entry position after physics settles", player.global_position.distance_to(position) < .02 and player.heading.distance_to(heading) < .001 and str(world.get("entry_station")).is_empty())
	service.accept = false
	check("Failed open is reported", not bool(world.call("open_account", "account")))
	check("Failed open restores controls", not bool(world.get("paused")) and player.controls_enabled)
	check("Failed open displays useful message", (hud.get("account_status") as Label).text.contains("無法開啟"))
	root.remove_child(world)
	check("Shared account survives world suspension", service.is_inside_tree())
	root.add_child(world)
	check("Restored world retains account instance", world.get("account") == service)
	world.queue_free()
	service.queue_free()
	await process_frame
	print("ACCOUNT_CHECKS failures=", failures)
	quit(0 if failures == 0 else 1)
