extends SceneTree
const Protocol = preload("res://scripts/interest_protocol.gd")
const Session = preload("res://scripts/account_session.gd")
const Native = preload("res://scripts/account_native_host.gd")
var failures: int = 0
var received: Array[Dictionary] = []

class FakeNative:
	extends Node
	var commands: Array[Dictionary] = []
	func request_interest(command: Dictionary) -> bool:
		commands.append(command.duplicate(true))
		return true

class FakeWebView:
	extends Control
	var scripts: Array[String] = []
	func eval(source: String) -> void:
		scripts.append(source)

func check(label: String, passed: bool) -> void:
	print("INTEREST_BRIDGE_CHECK ",label," passed=",passed)
	if not passed:
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var profile: Dictionary = {"schemaVersion":1,"catalogVersion":1,"title":"秋季興趣量表","riasecDate":"","knowledgeDate":"","riasec":{},"knowledge":{},"bestFits":[],"suitableFits":[]}
	for id: String in Protocol.RIASEC:
		profile.riasec[id] = "0"
	for index: int in range(1,34):
		profile.knowledge["k%02d"%index] = "18"
	for index: int in range(60):
		profile.bestFits.append({"groupId":"arts","category":"藝術創作與設計 %d"%index,"z":"-0.3"})
	var command: Dictionary = {"requestId":"save1","action":"complete","recordId":"one","expectedRevision":0,"profile":profile}
	var sanitized: Dictionary = Protocol.sanitize_command(command,4)
	check("Large complete payload crosses only interest channel", not sanitized.is_empty() and JSON.stringify(sanitized).to_utf8_buffer().size()>4096)
	var forbidden: Dictionary = command.duplicate(true)
	forbidden["uid"] = "other"
	check("Caller cannot choose an account",Protocol.sanitize_command(forbidden,4).is_empty())
	var incomplete: Dictionary = profile.duplicate(true)
	incomplete.riasec.R = "-"
	check("Temporary numeric text remains a draft string",not Protocol.profile(incomplete).is_empty())
	var packet: Dictionary = {"channel":Protocol.CHANNEL,"version":1,"type":"state","requestId":"save1","sessionGeneration":4,"recordId":"one","revision":1,"profile":profile,"hasCompleted":true,"hasDraft":false,"activeRecordId":"one","selectionRevision":1,"updatedAtMillis":1,"uid":"never_cross"}
	var clean_packet: Dictionary = Protocol.sanitize_packet(packet)
	check("Reply copies only allowed fields",not clean_packet.is_empty() and not clean_packet.has("uid") and clean_packet.profile.bestFits.size()==60)
	var native: Node = Native.new()
	var webview: FakeWebView = FakeWebView.new()
	native.add_child(webview)
	native.set("webview",webview)
	native.set("host_ready",true)
	native.set("trusted_document",true)
	native.set("session_generation",4)
	check("Native hidden host accepts score command",not bool(native.get("opened")) and bool(native.call("request_interest",sanitized)) and webview.scripts.size()==1)
	native.connect("interest_message",func(value: Dictionary) -> void: received.append(value))
	native.call("_receive_message",JSON.stringify(packet))
	check("Native accepts bounded score reply over4096bytes",received.size()==1)
	native.set("trusted_document",false)
	native.call("_receive_message",JSON.stringify(packet))
	check("Native navigation trust gates score replies",received.size()==1 and not bool(native.call("request_interest",sanitized)))
	native.free()
	var session: Node = Session.new()
	var adapter: FakeNative = FakeNative.new()
	session.add_child(adapter)
	session.set("native_host",adapter)
	session.set("user",{"signedIn":true,"profileReady":true,"sessionGeneration":4})
	received.clear()
	session.connect("interest_message",func(value: Dictionary) -> void: received.append(value))
	check("Root session accepts a pure Godot form",bool(session.call("request_interest",command)))
	check("An identical timed-out request can retry safely",bool(session.call("request_interest",command)) and adapter.commands.size()==2)
	var changed: Dictionary = command.duplicate(true)
	changed.profile.title = "另一份內容"
	check("Same pending ID cannot change its payload",not bool(session.call("request_interest",changed)))
	var other: Dictionary = clean_packet.duplicate(true)
	other.recordId = "two"
	session.call("_interest_message",other)
	check("Wrong record cannot satisfy pending request",received.is_empty())
	session.call("_interest_message",clean_packet)
	check("Matching response reaches form once",received.size()==1)
	session.call("_interest_message",clean_packet)
	check("Duplicate response is ignored",received.size()==1)
	command.requestId = "save2"
	session.call("request_interest",command)
	session.call("_update_user",{})
	clean_packet.requestId = "save2"
	session.call("_interest_message",clean_packet)
	check("Sign-out drops in-flight private data",received.size()==1 and not bool(session.call("request_interest",command)))
	session.free()
	print("INTEREST_BRIDGE_CHECKS failures=",failures)
	quit(1 if failures else 0)
