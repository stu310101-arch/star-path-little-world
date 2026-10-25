extends SceneTree
const Host = preload("res://scripts/account_native_host.gd")
var failures: int = 0
func _initialize() -> void:
	check("Legacy signed-in host is diagnosed instead of silently locking",Host.legacy_auth_packet({"user":{"signedIn":true,"displayName":"星"}}))
	check("Signed-out host is not mistaken for a version mismatch",not Host.legacy_auth_packet({"user":null}))
	check("Current unfinished identity stays on its setup form",not Host.legacy_auth_packet({"sessionGeneration":8,"user":{"signedIn":true,"profileReady":false,"identity":"","sessionGeneration":8}}))
	for origin: String in ["http://127.0.0.1:4317","http://localhost:4317"]:
		check("Debug accepts explicit loopback origin",Host.resolve_origin(origin,true)==origin)
		check("Release ignores all development origins",Host.resolve_origin(origin,false)==Host.ORIGIN)
	for origin: String in ["https://evil.test","http://127.0.0.1.evil.test:4317","http://127.0.0.1:4317/path","http://127.0.0.1:4317?x=1","http://localhost:65536","http://user@localhost:4317","http://localhost:4317/"]:
		check("Reject non-exact development origin",Host.resolve_origin(origin,true)==Host.ORIGIN)
	var previous: String = OS.get_environment("STARPATH_DEV_HOST_ORIGIN")
	OS.set_environment("STARPATH_DEV_HOST_ORIGIN","http://127.0.0.1:4317")
	check("Local host navigation uses strict account path",Host.allowed_host_url("http://127.0.0.1:4317/admissions/host/?platform=native&view=account"))
	check("Local host rejects a different origin",not Host.allowed_host_url(Host.HOST+"?platform=native&view=account"))
	check("Local pairing stays within configured origin",Host.allowed_pairing_url("http://127.0.0.1:4317/admissions/account/native/"))
	OS.set_environment("STARPATH_DEV_HOST_ORIGIN",previous)
	print("LOCAL_ACCOUNT_HOST_RESULT failures=",failures)
	quit(0 if failures==0 else 1)
func check(label: String, passed: bool) -> void:
	print("LOCAL_ACCOUNT_HOST_CHECK ",label," ",passed)
	if not passed:
		failures += 1
