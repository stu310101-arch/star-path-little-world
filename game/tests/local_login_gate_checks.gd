extends SceneTree
## Real local-emulator WebView signup through UI, not a forged Godot session.
const Native = preload("res://scripts/account_native_host.gd")
const Startup = preload("res://tests/startup_fixture.gd")
var failures: int = 0
var checks: Array[Dictionary] = []
var native: Node
var view: Control
var qa_events: Dictionary = {}
func _initialize() -> void:
	run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks.append({"test":label,"passed":passed})
	print("LOCAL_LOGIN_CHECK ",label," ",passed)
	if not passed:
		failures += 1
func wait_until(condition: Callable, timeout_ms: int = 20000) -> bool:
	var deadline: int = Time.get_ticks_msec()+timeout_ms
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	return condition.call()
func run() -> void:
	root.size = Vector2i(1280,800)
	root.title = "Star Path Local Login Gate QA"
	if Native.active_origin()==Native.ORIGIN or DisplayServer.get_name()=="headless":
		push_error("Requires visible Windows debug engine and explicit local emulator host")
		quit(2)
		return
	change_scene_to_file("res://scenes/login_entry.tscn")
	await process_frame
	await process_frame
	var account: Node = root.get_node("StarPathAccount")
	var gate: Node = root.get_node("AccountGate")
	native = account.get("native_host")
	check("Normal login entry pauses the game",paused and gate.get("locked"))
	check("Native local host sends trusted ready",await wait_until(func() -> bool: return is_instance_valid(native) and bool(native.get("host_ready")),35000))
	if not bool(native.get("host_ready")):
		quit(1)
		return
	view = native.get("webview")
	view.connect("ipc_message",func(payload: String) -> void:
		var data: Variant = JSON.parse_string(payload)
		if data is Dictionary and data.get("channel")=="garden-local-qa":
			qa_events[str(data.get("type",""))] = data.get("ok",false)
	)
	# This script sends no credentials or account IDs back to Godot. Test-only
	# email/password stay in the emulator UI realm and are never printed.
	view.call("eval","""
(async () => {
  if (!['127.0.0.1','localhost'].includes(location.hostname)) return;
  const runtime = await window.__starPathFirebase;
  if (!runtime?.auth?.emulatorConfig) return;
  await window.StarPathHost.signOut();
  window.StarPathHost.navigate('account');
  const deadline = Date.now()+18000;
  const start = () => {
    const frame = document.querySelector('iframe.host-content');
    const doc = frame?.contentDocument;
    const tab = Array.from(doc?.querySelectorAll('button[type="button"]')||[]).find(node => node.textContent.trim()==='建立帳號');
    if (!tab) { if(Date.now()<deadline)setTimeout(start,100); return; }
    tab.click();
    setTimeout(() => {
      const win = frame.contentWindow;
      const set = (selector,value) => {
        const input = doc.querySelector(selector);
        if(!input) return false;
        Object.getOwnPropertyDescriptor(win.HTMLInputElement.prototype,'value').set.call(input,value);
        input.dispatchEvent(new win.Event('input',{bubbles:true}));
        input.dispatchEvent(new win.Event('change',{bubbles:true}));
        return true;
      };
      set('input[autocomplete="nickname"]','本機視窗測試');
      set('input[type="email"]',`native-qa-${Date.now()}@example.invalid`);
      set('input[type="password"]','Only-Local-Emulator-123!');
      const identities=doc.querySelectorAll('input[name="register-identity"]');
      identities[2]?.click();
      setTimeout(()=>doc.querySelector('.account-form button[type="submit"]')?.click(),150);
    },150);
  };
  start();
})();
""")
	var admitted: bool = await wait_until(func() -> bool: return not paused and not gate.get("locked") and current_scene!=null and current_scene.has_method("teleport_to"),30000)
	check("Real native signup plus selected identity unlocks the world",admitted)
	check("Godot receives only a completed sanitized profile",(account.get("user") as Dictionary).get("identity")=="university" and (account.get("user") as Dictionary).get("profileReady")==true and not (account.get("user") as Dictionary).has("uid"))
	if admitted:
		if OS.get_cmdline_user_args().has("--garden"):
			await exercise_garden(account)
		# Delete only this session's temporary emulator account, then use the
		# normal host signout to test the root gate's real IPC path.
		view.call("eval","""
(async () => {
  const runtime = await window.__starPathFirebase;
  if (!['127.0.0.1','localhost'].includes(location.hostname) || !runtime?.auth?.emulatorConfig) return;
  const user = runtime.auth.currentUser;
  if (user?.email?.startsWith('native-qa-') && user.email.endsWith('@example.invalid')) {
    const idToken = await user.getIdToken();
    await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:delete?key=demo-key', {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({idToken})});
  }
  window.StarPathHost.signOut();
})();
""")
		check("Real native signout relocks the game",await wait_until(func() -> bool: return paused and gate.get("locked") and (account.get("user") as Dictionary).is_empty(),15000))
	print("LOCAL_LOGIN_RESULT failures=",failures)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/discussion-garden/qa"))
	var report := FileAccess.open("res://../deliverables/discussion-garden/qa/native-e2e-report.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"host_origin":Native.active_origin(),"backend":"local Auth and Firestore emulators; actual WRY host and repositories","garden_sha256":FileAccess.get_sha256("res://assets/discussion_garden/garden.glb")},"\t"))
	report.close()
	quit(0 if failures==0 else 1)

func exercise_garden(account: Node) -> void:
	var world: Node3D = current_scene as Node3D
	world.call("teleport_to","life")
	check("Fifth-station arrival finishes preparation",await Startup.wait_roaming(world,self))
	var entry_position: Vector3 = (world.get("player") as Node3D).global_position
	world.call("open_station","life")
	check("Fifth station opens the discussion scene through normal transition",await wait_until(func() -> bool: return current_scene!=null and current_scene!=world and current_scene.get_script().resource_path=="res://scripts/discussion_garden.gd",10000))
	var room: Node3D = current_scene as Node3D
	if room==world or room==null:
		return
	check("Five-zone art and avatar are ready through normal entry",await Startup.wait_room(room,self))
	view.call("eval","""
(async () => {
  try {
    const runtime = await window.__starPathFirebase;
    if (!['127.0.0.1','localhost'].includes(location.hostname) || !runtime.auth.emulatorConfig) return;
    const repo = runtime.forum(runtime.auth.currentUser.uid);
    const slots = await repo.listDevices('campus',0), slot = slots.findIndex(row=>!row);
    if (slot < 0) throw new Error('QA needs an empty campus device');
    const threadId = 'SPDEVCL000000000000'+slot, replyId = repo.newId();
    window.__gardenLocalQa = {repo,threadId,replyId};
    await repo.createThread(threadId,'campus','本機原生留言橋接測試',true);
    await repo.createReply(threadId,replyId,'本機原生回覆橋接測試',true);
    window.ipc.postMessage(JSON.stringify({channel:'garden-local-qa',type:'created',ok:true}));
  } catch (_) { window.ipc.postMessage(JSON.stringify({channel:'garden-local-qa',type:'created',ok:false})); }
})();
""")
	check("Local native host writes a real anonymous post and reply",await wait_until(func() -> bool: return qa_events.has("created")) and qa_events.get("created")==true)
	await wait_until(func() -> bool: return not (room.get("pending") as Dictionary).has("campus"))
	room.call("request_page","campus","refresh")
	var received: bool = await wait_until(func() -> bool:
		return (room.get("pages") as Dictionary).get("campus",{}).get("items",[]).any(func(item: Dictionary) -> bool: return item.get("preview")=="本機原生留言橋接測試")
	)
	check("Real native IPC delivers the post to a physical device page",received)
	if received:
		var items: Array = (room.get("pages") as Dictionary).campus.items
		var index: int = -1
		for i: int in range(items.size()):
			if items[i].get("preview")=="本機原生留言橋接測試":
				index = i
		check("Public native packet retains identity with anonymous name and no account ID",items[index].authorName=="匿名" and items[index].identity=="university" and not items[index].has("uid"))
		var device: Node3D = (room.get("zones") as Dictionary).campus.devices[index]
		var player: CharacterBody3D = room.get("player")
		player.call("place_at",device.position+device.basis.z*1.1,-device.basis.z)
		for frame: int in range(5):
			await physics_frame
			await process_frame
		room.call("refresh_nearest")
		room.call("activate_nearest")
		check("Physical device opens the real forum and freezes input",not (room.get("snapshot") as Dictionary).is_empty() and player.process_mode==Node.PROCESS_MODE_DISABLED)
		view.call("eval","""
(() => {
  const deadline = Date.now()+12000;
  const sample=()=>{
    const doc=document.querySelector('iframe.host-content')?.contentDocument;
    const bodies=Array.from(doc?.querySelectorAll('.forum-body')||[]).map(node=>node.textContent);
    const ok=bodies.includes('本機原生留言橋接測試') && bodies.includes('本機原生回覆橋接測試');
    if(ok || Date.now()>=deadline) window.ipc.postMessage(JSON.stringify({channel:'garden-local-qa',type:'opened',ok}));
    else setTimeout(sample,100);
  };
  sample();
})();
""")
		check("Device's hosted thread renders actual post and reply",await wait_until(func() -> bool: return qa_events.has("opened"),14000) and qa_events.get("opened")==true)
		account.call("close_view")
		check("Closing real thread restores garden controls",player.get("controls_enabled") and (room.get("snapshot") as Dictionary).is_empty())
	view.call("eval","""
(async()=>{
  const qa=window.__gardenLocalQa;
  try {if(qa){await qa.repo.remove(qa.threadId,qa.replyId);await qa.repo.remove(qa.threadId);}}
  finally {window.ipc.postMessage(JSON.stringify({channel:'garden-local-qa',type:'cleaned',ok:true}));}
})();
""")
	await wait_until(func() -> bool: return qa_events.has("cleaned"))
	room.call("return_to_world")
	check("Discussion exit restores the same world",await wait_until(func() -> bool: return current_scene==world,6000))
	check("Discussion exit restores fifth-station entry position",(world.get("player") as Node3D).global_position.distance_to(entry_position)<.04)
