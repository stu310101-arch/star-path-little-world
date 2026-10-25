extends SceneTree

const Furniture = preload("res://scripts/world_street_furniture.gd")
var failures: int = 0
var checks: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error(label+": "+str(detail))

func run() -> void:
	var kit: RefCounted = Furniture.new()
	var ids: Array[String] = ["counseling","admissions","recommendations","universities","life","wordking","stations"]
	for id: String in ids:
		var path: String = "res://generated/stations.tscn" if id=="stations" else "res://generated/districts/"+id+".tscn"
		var scene: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(scene)
		var shapes: Dictionary = {}
		for shape: CollisionShape3D in scene.find_children("*","CollisionShape3D",true,false): shapes[shape.get_instance_id()] = [shape.shape,shape.global_transform]
		var count: int = int(kit.call("apply",scene))
		var old_planters_visible: bool = false
		for old: Node in scene.find_children("planter","Node3D",true,false):
			if old.get_class()=="Node3D" and (old as Node3D).is_visible_in_tree(): old_planters_visible = true
		check("Restyle all verified street furniture: "+id,count >= 6 and not old_planters_visible,count)
		check("Applying street style twice is idempotent: "+id,int(kit.call("apply",scene)) == 0)
		var unchanged: bool = shapes.size() == scene.find_children("*","CollisionShape3D",true,false).size()
		for shape: CollisionShape3D in scene.find_children("*","CollisionShape3D",true,false):
			var before: Array = shapes.get(shape.get_instance_id(),[])
			unchanged = unchanged and before.size()==2 and before[0]==shape.shape and (before[1] as Transform3D).is_equal_approx(shape.global_transform)
		check("Furniture preserves exact existing collision: "+id,unchanged)
		if id=="stations":
			var grounded_signs: bool = true
			var aligned_labels: bool = true
			for station: Node3D in scene.get_children():
				grounded_signs = grounded_signs and not (station.get_node("Beacon") as Node3D).visible and not (station.get_node("LuminousRing") as Node3D).visible and station.has_node("EntranceWayfinding/MarkerFoot") and station.has_node("EntranceWayfinding/MarkerPost") and station.has_node("Arrival") and (station.get_node("StationLabel") as Label3D).visible
				var sign: Node3D = station.get_node("EntranceWayfinding") as Node3D
				var label: Label3D = station.get_node("StationLabel") as Label3D
				aligned_labels = aligned_labels and (sign.transform.affine_inverse()*label.position).is_equal_approx(Vector3(0,1.54,.048)) and label.billboard==BaseMaterial3D.BILLBOARD_DISABLED and label.text.split("\n").size()==3 and station.has_node("StationLabelReverse")
			check("All six arrivals retain physical signs, labels and unobstructed markers",grounded_signs)
			check("Destination names sit on both faces of the physical marker",aligned_labels)
		scene.free()
	var out: String = "res://../deliverables/world-revision/street-furniture-checks.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"failures":failures,"checks":checks,"planters":kit.get("planter_count"),"stations":kit.get("station_count")},"\t"))
	print("STREET_FURNITURE_CHECKS checks=",checks.size()," failures=",failures)
	quit(1 if failures>0 else 0)
