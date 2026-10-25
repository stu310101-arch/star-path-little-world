extends SceneTree

const Clip = preload("res://tests/minimap_stroke_clip_fixture.gd")
const MapScript = preload("res://scripts/world_minimap.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const OUTPUT: String = "res://../deliverables/performance-20261020/minimap-stroke-clip.json"

class TestWorld:
	extends Node3D
	var layout: Dictionary

var checks: Array[Dictionary] = []
var failures: int = 0
var commands: Array[Dictionary] = []
var map: Control

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"passed":passed})
	if not passed:
		failures += 1
		push_error(label)

func line(from: Vector2, step: Vector2, count: int) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for index: int in range(count):
		points.append(from + step * index)
	return points

func has_sequence(runs: Array[PackedVector2Array], sequence: PackedVector2Array) -> bool:
	for part: PackedVector2Array in runs:
		for start: int in range(part.size()-sequence.size()+1):
			if part.slice(start,start+sequence.size()) == sequence:
				return true
	return false

func all_original_slices(points: PackedVector2Array, runs: Array[PackedVector2Array]) -> bool:
	var previous_end: int = -1
	for part: PackedVector2Array in runs:
		var start: int = points.find(part[0])
		if start < 0 or start <= previous_end or part != points.slice(start,start+part.size()):
			return false
		previous_end = start + part.size() - 1
	return true

func intersects_rect(a: Vector2,b: Vector2,rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners: PackedVector2Array = [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	for side: int in range(4):
		if Geometry2D.segment_intersects_segment(a,b,corners[side],corners[(side+1)%4]) != null:
			return true
	return false

func correctness() -> void:
	var rect: Rect2 = Rect2(0,0,100,100)
	check("Empty and singleton inputs produce no invalid polyline",Clip.visible_runs([],rect,2).is_empty() and Clip.visible_runs([Vector2.ZERO],rect,2).is_empty())
	var short: PackedVector2Array = line(Vector2(-200,-200),Vector2(1,0),24)
	check("Short strokes preserve original array identity",is_same(Clip.visible_runs(short,rect,2)[0],short))
	var points: PackedVector2Array = line(Vector2(-500,50),Vector2(10,0),101)
	var before: PackedVector2Array = points.duplicate()
	var runs: Array[PackedVector2Array] = Clip.visible_runs(points,rect,2)
	check("Long crossing stroke sheds only offscreen tails",runs.size()==1 and runs[0].size()<points.size() and all_original_slices(points,runs))
	check("Every visible original vertex is retained",has_sequence(runs,points.slice(50,61)))
	check("Cut keeps neighbour before and after padded segment range",has_sequence(runs,points.slice(47,64)))
	check("Source points are unchanged",points==before)
	var inside: PackedVector2Array=line(Vector2(10,50),Vector2(1,0),80)
	check("Fully visible long stroke preserves original array identity",is_same(Clip.visible_runs(inside,rect,2)[0],inside))
	var leap: PackedVector2Array=line(Vector2(-1000,50),Vector2(10,0),30)
	leap.append(Vector2(500,50))
	leap.append_array(line(Vector2(510,50),Vector2(10,0),30))
	check("Crossing segment retained even when both endpoints are offscreen",has_sequence(Clip.visible_runs(leap,rect,2),leap.slice(28,32)))
	check("Entirely distant long stroke can be omitted",Clip.visible_runs(line(Vector2(-500,-100),Vector2(10,0),101),rect,2).is_empty())
	var grazes: PackedVector2Array = line(Vector2(-500,-8),Vector2(10,0),101)
	check("AA/miter near-edge stroke is kept outside centreline viewport",not Clip.visible_runs(grazes,rect,2).is_empty())
	var duplicate: PackedVector2Array = points.duplicate()
	duplicate[5] = duplicate[4]
	check("Zero-length direction-history case returns original whole stroke",is_same(Clip.visible_runs(duplicate,rect,2)[0],duplicate))
	check("Negative hairline width returns original whole stroke",is_same(Clip.visible_runs(points,rect,-1)[0],points))
	var not_finite: PackedVector2Array=points.duplicate()
	not_finite[80]=Vector2(INF,0)
	check("Nonfinite point after visible section conservatively returns whole stroke",is_same(Clip.visible_runs(not_finite,rect,2)[0],not_finite))
	check("Unknown width and invalid rectangle conservatively return whole stroke",is_same(Clip.visible_runs(points,rect,NAN)[0],points) and is_same(Clip.visible_runs(points,Rect2(),2)[0],points))
	var loop: PackedVector2Array = []
	for index: int in range(80):
		loop.append(Vector2(50,50)+Vector2(cos(TAU*index/80.0),sin(TAU*index/80.0))*150)
	loop.append(loop[0])
	var seam_rect: Rect2 = Rect2(180,30,40,40)
	check("Closed seam involvement returns original whole loop",is_same(Clip.visible_runs(loop,seam_rect,2)[0],loop))
	var almost_closed: PackedVector2Array=loop.duplicate()
	almost_closed[-1]+=Vector2(.00001,0)
	check("Approximate closure uses the renderer's seam fallback",is_same(Clip.visible_runs(almost_closed,seam_rect,2)[0],almost_closed))
	var middle_rect: Rect2 = Rect2(-120,20,40,60)
	var middle: Array[PackedVector2Array] = Clip.visible_runs(loop,middle_rect,2)
	check("Closed loop may retain an unchanged interior arc without joining seam",not middle.is_empty() and middle[0].size()<loop.size() and all_original_slices(loop,middle))
	var multi: PackedVector2Array = line(Vector2(-400,30),Vector2(10,0),100)
	multi.append_array(line(Vector2(590,400),Vector2(-10,0),100))
	multi.append_array(line(Vector2(-400,70),Vector2(10,0),100))
	var separate: Array[PackedVector2Array] = Clip.visible_runs(multi,rect,2)
	check("Disjoint visits remain original nonoverlapping slices",separate.size()==2 and all_original_slices(multi,separate))
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 412019
	var coverage: bool = true
	var neighbours: bool = true
	var original: bool = true
	for sample_index: int in range(100):
		var random_line: PackedVector2Array = []
		for index: int in range(80):
			random_line.append(Vector2(-400+index*12,random.randf_range(-180,280)))
		var chosen: Array[PackedVector2Array] = Clip.visible_runs(random_line,rect,5.5)
		original = original and all_original_slices(random_line,chosen)
		for index: int in range(random_line.size()-1):
			# Independent line/rectangle intersection oracle, not helper AABBs.
			if intersects_rect(random_line[index],random_line[index+1],rect):
				coverage = coverage and has_sequence(chosen,random_line.slice(index,index+2))
				neighbours = neighbours and has_sequence(chosen,random_line.slice(maxi(0,index-1),mini(random_line.size(),index+3)))
	check("100 deterministic polylines lose no visible segment",coverage)
	check("All oracle-visible segments keep both original join neighbours",neighbours)
	check("Randomized results never invent/reorder/resample vertices",original)
	var adjacent: PackedVector2Array=line(Vector2(-400,50),Vector2(10,0),100)
	adjacent[48]=Vector2(-20,150)
	adjacent[49]=Vector2(-10,150)
	var merged: Array[PackedVector2Array]=Clip.visible_runs(adjacent,rect,2)
	check("Expanded neighbour intervals merge without repeated AA segments",all_original_slices(adjacent,merged))

func stroke(points: PackedVector2Array,width: float,closed: bool=false) -> void:
	if closed:
		points=points.duplicate()
		points.append(points[0])
	commands.append({"points":points,"width":width})

func walk(points: PackedVector2Array,width: float,bridge: bool=false) -> void:
	var scale_width: float = float(map.source_scale())*float(map.map_scale())
	if map.compact_preview:
		stroke(points,maxf(1.3,width*scale_width))
		return
	stroke(points,maxf(2.4,(width+.65)*scale_width))
	stroke(points,maxf(1.8,width*scale_width))
	if bridge:
		stroke(points,.7)

func collect(normal: Vector3,compact: bool) -> void:
	commands.clear()
	map.compact_preview=compact
	map.size=Vector2(128,90) if compact else Vector2(246,180)
	map.update_map_frame(normal)
	map._projected_lines.clear()
	map._drawing_map=true
	var scale_width: float = float(map.source_scale())*float(map.map_scale())
	for patch: Dictionary in map.patches:
		if not map.line_visible(patch.coast):
			continue
		var coast: PackedVector2Array = map.project_line(patch.coast)
		if not compact:
			stroke(coast,5.5,true)
		stroke(coast,1.3,true)
		if not compact:
			for water: Dictionary in patch.water:
				if map.line_visible(water.points):
					stroke(map.project_line(water.points),.8,true)
		for road: PackedVector3Array in patch.roads:
			if map.line_visible(road):
				var projected: PackedVector2Array = map.project_line(road)
				if not compact:
					stroke(projected,maxf(1.6,6.3*scale_width))
				stroke(projected,maxf(1.0,4.2*scale_width))
		if not compact:
			for path: PackedVector3Array in patch.forecourts:
				if map.line_visible(path):
					stroke(map.project_line(path),maxf(1.1,1.4*scale_width))
		for path: PackedVector3Array in patch.paths:
			if map.line_visible(path):
				walk(map.project_line(path),float(patch.path_width))
		for path: PackedVector3Array in patch.get("boardwalks",[]):
			if map.line_visible(path):
				walk(map.project_line(path),Waterfront.WIDTH,true)
		for building: Dictionary in patch.buildings:
			if (not compact or bool(building.civic)) and map.line_visible(building.points):
				stroke(map.project_line(building.points),.6,true)
	for platform: PackedVector3Array in map.platforms:
		if map.line_visible(platform):
			stroke(map.project_line(platform),1.1,true)
	for bridge: PackedVector3Array in map.bridges:
		if map.line_visible(bridge):
			walk(map.project_line(bridge),2.4,true)
	map._drawing_map=false
	map._projected_lines.clear()

func native_clip(points: PackedVector2Array,rect: Rect2,width: float) -> Array[PackedVector2Array]:
	if points.size()<=Clip.SHORT_LINE_POINTS:
		return [points]
	var padded: Rect2 = rect.grow(maxf(width,1)*3+6)
	return Geometry2D.intersect_polyline_with_polygon(points,PackedVector2Array([padded.position,Vector2(padded.end.x,padded.position.y),padded.end,Vector2(padded.position.x,padded.end.y)]))

func measure(mode: String,canvas: RID,submit: bool) -> Dictionary:
	var samples: Array[int] = []
	var result_points: int = 0
	var result_runs: int = 0
	var rect: Rect2 = Rect2(Vector2.ZERO,map.size)
	var color: PackedColorArray = [Color.WHITE]
	for repeat: int in range(16):
		RenderingServer.canvas_item_clear(canvas)
		var started: int = Time.get_ticks_usec()
		var retained: int = 0
		var draws: int = 0
		for command: Dictionary in commands:
			var parts: Array[PackedVector2Array] = [command.points]
			if mode=="slices":
				parts=Clip.visible_runs(command.points,rect,float(command.width))
			elif mode=="native_clipper":
				parts=native_clip(command.points,rect,float(command.width))
			for part: PackedVector2Array in parts:
				retained+=part.size()
				draws+=1
				if submit:
					RenderingServer.canvas_item_add_polyline(canvas,part,color,float(command.width),true)
		if repeat>=4:
			samples.append(Time.get_ticks_usec()-started)
		result_points=retained
		result_runs=draws
	samples.sort()
	return {"median_ms":float(samples[samples.size()/2])/1000.0,"points":result_points,"runs":result_runs,"measured_iterations":samples.size()}

func run() -> void:
	if DisplayServer.get_name()!="headless":
		push_error("Use --headless; this is not a GPU probe.")
		quit(1)
		return
	correctness()
	var world: TestWorld=TestWorld.new()
	world.layout=JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json"))
	var stations: Node3D=Node3D.new()
	stations.name="Stations"
	world.add_child(stations)
	for row: Dictionary in world.layout.stations:
		var station: Node3D=Node3D.new()
		station.name=str(row.id)
		station.position=Vector3(row.normal[0],row.normal[1],row.normal[2])*float(world.layout.radius)
		stations.add_child(station)
	root.add_child(world)
	map=MapScript.new()
	map.world=world
	map.radius=float(world.layout.radius)
	map.build_cartography()
	var canvas: RID=RenderingServer.canvas_item_create()
	var rows: Array[Dictionary]=[]
	for compact: bool in [false,true]:
		for view: String in ["counseling","bridge"]:
			var normal: Vector3=Vector3.UP if view=="counseling" else Routes.directions()[0].slerp(Routes.directions()[1],.5)
			collect(normal,compact)
			var row: Dictionary={"view":view,"compact":compact,"size":[map.size.x,map.size.y],"commands":commands.size()}
			for mode: String in ["direct","slices","native_clipper"]:
				row[mode]={"helper_only":measure(mode,canvas,false),"helper_and_native_AA":measure(mode,canvas,true)}
			rows.append(row)
			print("STROKE_CLIP_SAMPLE ",JSON.stringify(row))
	RenderingServer.free_rid(canvas)
	map.free()
	world.free()
	var report: Dictionary={"passed":failures==0,"checks":checks,"samples":rows,"helper_sha256":FileAccess.get_sha256("res://tests/minimap_stroke_clip_fixture.gd"),"map_sha256":FileAccess.get_sha256("res://scripts/world_minimap.gd"),"method":"Headless CPU only, real production cartography projection and mirrored stroke widths; timings include native AA command construction but exclude GPU, actual rendered parity and Web. Native Clipper is a timing comparator, NOT contract-equivalent: it creates/quantizes vertices and PreserveCollinear(false) can remove original visible points. No product integration.","renderer_source":"build/engine-source/servers/rendering/renderer_canvas_cull.cpp; Godot 4.7.2 FEATHER_SIZE=1.25, miter clamp=3","short_line_points":Clip.SHORT_LINE_POINTS}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT).get_base_dir())
	var output: FileAccess=FileAccess.open(OUTPUT,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("MINIMAP_STROKE_CLIP_CHECKS ",checks.size()," failures=",failures," ",OUTPUT)
	quit(0 if failures==0 else 1)
