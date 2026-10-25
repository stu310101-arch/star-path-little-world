extends SceneTree

## Run with a visible Windows window after publishing the /admissions/ host.
## Uses an isolated QA profile and reads only UI metadata, never credentials.
const NativeHost = preload("res://scripts/account_native_host.gd")
var host: Node
var failures: int = 0
var response: Dictionary = {}
var probe_id: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(label_text: String, passed: bool) -> void:
	print("ACCOUNT_NATIVE_SMOKE ", label_text, " passed=", passed)
	if not passed:
		failures += 1

func run() -> void:
	root.title = "Star Path - Account WebView QA"
	root.size = Vector2i(1280, 800)
	root.close_requested.connect(func() -> void: quit())
	host = NativeHost.new()
	host.set("data_directory", "user://qa/account-native-smoke")
	root.add_child(host)
	check("Open native remote host", bool(host.call("open_host", "query")))
	var deadline: int = Time.get_ticks_msec() + 35000
	while not bool(host.get("host_ready")) and Time.get_ticks_msec() < deadline:
		if not str(host.get("last_error")).is_empty():
			break
		await process_frame
	check("Remote host sends trusted ready", bool(host.get("host_ready")))
	if not bool(host.get("host_ready")):
		print("ACCOUNT_NATIVE_SMOKE host_error=", host.get("last_error"))
		finish()
		return
	var webview: Control = host.get("webview") as Control
	var instance_id: int = webview.get_instance_id()
	webview.connect("ipc_message", on_probe)
	var query: Dictionary = await probe(webview, "query")
	check("Remote host supports navigate and signOut", bool(query.get("api", false)))
	check("Native query path and context parameters", bool(query.get("requested_route", false)))
	check("Native query document and visible heading load", bool(query.get("loaded", false)))
	host.call("open_host", "scores")
	var scores: Dictionary = await probe(webview, "scores")
	check("Native eval navigates to scores with context", bool(scores.get("requested_route", false)))
	check("Native scores document and visible heading load", bool(scores.get("loaded", false)))
	check("Native terminal is bounded", not bool(webview.get("full_window_size")) and webview.size.x < root.size.x)
	webview.call("eval", "window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));")
	deadline = Time.get_ticks_msec() + 5000
	while bool(host.get("opened")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check("Host Escape closes through IPC", not bool(host.get("opened")))
	check("Close keeps account WebView alive and hidden", is_instance_valid(webview) and not webview.visible)
	host.call("open_host", "account")
	var account: Dictionary = await probe(webview, "account")
	check("Reopen keeps same account profile and WebView", (host.get("webview") as Control).get_instance_id() == instance_id)
	check("Reopen navigates to account with context", bool(account.get("requested_route", false)))
	check("Reopened account document and visible heading load", bool(account.get("loaded", false)))
	print("ACCOUNT_NATIVE_SMOKE setup_notice_visible=", account.get("setup", false))
	finish()

func probe(webview: Control, expected_view: String) -> Dictionary:
	probe_id += 1
	response = {}
	# Poll only public route metadata and fixed UI headings. No account state,
	# storage, input values, tokens, user IDs, or heading text enter the response.
	var script: String = """
(() => {
  const id = %d, view = %s, deadline = Date.now() + 14000;
  const years = ['113', '114', '115'];
  const routeMatches = (url) => {
    const parts = url.pathname.split('/').filter(Boolean);
    const pathMatches = view === 'query'
      ? parts.length === 3 && parts[0] === 'admissions' && years.includes(parts[1]) && parts[2] === 'query'
      : parts.length === 2 && parts[0] === 'admissions' && parts[1] === view;
    return url.origin === location.origin && pathMatches
      && url.searchParams.get('embedded') === 'native'
      && url.searchParams.get('desk') === (view === 'query' ? 'general' : 'passport')
      && (view === 'query' || years.includes(url.searchParams.get('year')));
  };
  const sample = () => {
    const result = {channel:'account-qa', id,
      api:typeof window.StarPathHost?.navigate === 'function' && typeof window.StarPathHost?.signOut === 'function',
      requested_route:false, document_route:false, heading_visible:false, loaded:false,
      load_state:'missing', setup:!!document.querySelector('.host-setup-note')};
    const frame = document.querySelector('iframe.host-content');
    try {
      const source = frame?.getAttribute('src');
      result.requested_route = !!source && routeMatches(new URL(source, location.href));
      const child = frame?.contentDocument;
      if (child) {
        result.load_state = child.readyState;
        result.document_route = routeMatches(new URL(child.location.href));
        const selector = view === 'query' ? '.query-intro h1'
          : view === 'scores' ? '.history-heading h1, #account-heading' : '#account-heading';
        result.heading_visible = Array.from(child.querySelectorAll(selector)).some((heading) =>
          heading.getClientRects().length > 0 && ['輸入成績與篩選校系', '我的成績', '我的帳號', '登入你的學習空間'].includes(heading.textContent.trim()));
        result.loaded = result.requested_route && result.document_route && result.heading_visible && child.readyState !== 'loading';
      }
    } catch (_) { result.load_state = 'inaccessible'; }
    if (result.loaded || Date.now() >= deadline) window.ipc.postMessage(JSON.stringify(result));
    else setTimeout(sample, 200);
  };
  sample();
})();
""" % [probe_id, JSON.stringify(expected_view)]
	webview.call("eval", script)
	var deadline: int = Time.get_ticks_msec() + 15000
	while response.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	print("ACCOUNT_NATIVE_SMOKE probe=", expected_view, " load_state=", response.get("load_state", "timeout"),
		" requested_route=", response.get("requested_route", false), " document_route=", response.get("document_route", false),
		" heading_visible=", response.get("heading_visible", false))
	return response

func on_probe(payload: String) -> void:
	var data: Variant = JSON.parse_string(payload)
	if data is Dictionary and data.get("channel") == "account-qa" and int(data.get("id", 0)) == probe_id:
		response = data

func finish() -> void:
	print("ACCOUNT_NATIVE_SMOKE failures=", failures)
	if OS.get_cmdline_user_args().has("--keep-open"):
		return
	host.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
