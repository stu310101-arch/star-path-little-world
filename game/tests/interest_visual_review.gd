extends SceneTree
## Render-only fixture. All values are synthetic; no user records or USB images.
const InterestPanel = preload("res://scripts/interest_panel.gd")
const OUTPUT: String = "res://../deliverables/counseling-room/visual/"
class Service:
	extends Node
	signal state_changed(user: Dictionary)
	signal interest_message(packet: Dictionary)
	var user: Dictionary = {"profileReady":true,"sessionGeneration":4}
	func request_interest(command: Dictionary) -> bool:
		if command.action == "list":
			var packet: Dictionary = {"type":"list","requestId":command.requestId,"sessionGeneration":4,"records":[],"activeRecordId":"","selectionRevision":0,"nextCursor":null}
			interest_message.emit.call_deferred(packet)
		return true
var panel: Control
func _initialize() -> void:
	run.call_deferred()
func capture(name: String) -> void:
	for index: int in range(6):
		await process_frame
	RenderingServer.force_draw(false)
	var result: Error = root.get_texture().get_image().save_png(OUTPUT+name+".png")
	print("INTEREST_VISUAL ",name," ",result)
func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var service := Service.new()
	root.add_child(service)
	panel = InterestPanel.new()
	root.add_child(panel)
	panel.call("configure",service)
	panel.call("open_panel")
	await capture("interest-desktop-riasec")
	(panel.get("tabs") as TabContainer).current_tab = 1
	await capture("interest-desktop-knowledge")
	(panel.get("tabs") as TabContainer).current_tab = 2
	await capture("interest-desktop-fit")
	(panel.get("tabs") as TabContainer).current_tab = 3
	await capture("interest-desktop-history")
	root.size = Vector2i(390,844)
	(panel.get("tabs") as TabContainer).current_tab = 0
	await capture("interest-mobile-riasec")
	(panel.get("tabs") as TabContainer).current_tab = 2
	await capture("interest-mobile-fit")
	(panel.get("tabs") as TabContainer).current_tab = 3
	await capture("interest-mobile-history")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(960,600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.gui_embed_subwindows = true
	(panel.get("tabs") as TabContainer).current_tab = 0
	await capture("interest-mobile-expanded-riasec")
	(panel.get("tabs") as TabContainer).current_tab = 2
	await capture("interest-mobile-expanded-fit")
	panel.call("_focus_field","bestFits.0.groupId")
	await process_frame
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	root.push_input(key)
	key = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = false
	root.push_input(key)
	await capture("interest-mobile-expanded-groups")
	(panel.get("inputs")["bestFits.0.groupId"] as OptionButton).get_popup().hide()
	panel.call("_input_changed","riasec.R","0")
	panel.call("request_close")
	await capture("interest-mobile-expanded-unsaved")
	(panel.get("dialog") as Window).hide()
	panel.queue_free()
	service.queue_free()
	await process_frame
	quit(0)
