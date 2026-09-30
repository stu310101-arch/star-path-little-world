extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Plan = preload("res://scripts/sakura_routes.gd")
const Garden = preload("res://tools/sakura_garden.gd")

var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,description: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(description)

func run() -> void:
	# Only the sign_node and its font are instantiated, not the garden or world.
	var grove: Node3D=Node3D.new()
	root.add_child(grove)
	Garden.build_entry_sign(self,grove,Plan.grove_up(),48.0)
	var sign_node: Node3D=grove.get_node("GardenArrivalSign") as Node3D
	var board: MeshInstance3D=sign_node.get_node("GardenNameBoard") as MeshInstance3D
	var panel: BoxMesh=board.mesh as BoxMesh
	var front: Label3D=sign_node.get_node("BridgeFacingLettering") as Label3D
	var back: Label3D=sign_node.get_node("GardenFacingLettering") as Label3D
	check(front.text=="櫻花庭園" and back.text==front.text,"Both sides need the same upright garden name")
	for label: Label3D in [front,back]:
		check(label.font!=null and label.font.resource_path=="res://assets/fonts/NotoSansTC.ttf","Use the shipped Traditional Chinese font")
		for index: int in range(label.text.length()):
			check(label.font.has_char(label.text.unicode_at(index)),"The font must contain each garden-name glyph")
		var letters: Vector2=label.font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size)*label.pixel_size
		check(letters.x<panel.size.x-.12 and letters.y<panel.size.y-.08,"Lettering must fit within the physical board")
		var gap: float=absf(label.position.z)-panel.size.z*.5
		check(gap>.001 and gap<.005,"Lettering must sit just above the board surface")
		check(is_equal_approx(label.position.y,board.position.y),"Lettering must be centred on the panel")
		check(label.billboard==BaseMaterial3D.BILLBOARD_DISABLED and not label.double_sided,"Each physical side uses outward-facing lettering")
		check(not label.no_depth_test,"The panel lettering must respect world depth")
	check(front.global_basis.z.dot(back.global_basis.z)<-.999,"Reverse face must point out from the back, not through the board")
	for progress: float in [.0,.3,.6]:
		var reader: Vector3=Plan.bridge_finish().slerp(Plan.bridge_start(),progress).normalized()*48.0
		var toward: Vector3=(reader-sign_node.position).slide(sign_node.basis.y).normalized()
		print("SIGN_READER ",progress," facing cosine=",sign_node.basis.z.dot(toward))
		check(sign_node.basis.z.dot(toward)>.70,"The front face must remain readable across the final bridge approach")
	print("GARDEN_SIGN_CHECKS ",checks," checks, ",failures," failures")
	grove.free()
	quit(1 if failures>0 else 0)

func small_box(parent: Node3D,node_name: String,position: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var mesh: BoxMesh=BoxMesh.new()
	mesh.size=size
	var node: MeshInstance3D=Geo.mesh_node(parent,node_name,mesh,Geo.material(color))
	node.position=position
	return node
