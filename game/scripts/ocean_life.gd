extends Node3D

var elapsed: float = 0.0
var quality_update_interval: float = 0.0
var _quality_accumulator: float = 0.0
var radius: float = 36.0

func _ready() -> void:
	radius = float(get_meta("radius",36.0))
	update_life(0.0)

func _process(delta: float) -> void:
	elapsed += delta
	_quality_accumulator += delta
	if _quality_accumulator < quality_update_interval:
		return
	update_life(elapsed)
	_quality_accumulator = 0.0

func update_life(time: float) -> void:
	for child: Node in get_children():
		var actor: Node3D = child as Node3D
		if actor == null:
			continue
		var centre: Vector3 = actor.get_meta("centre",Vector3.UP) as Vector3
		var frame: Basis = PlanetGeometry.frame(centre)
		var phase: float = float(actor.get_meta("phase",0.0))
		if actor.get_meta("kind","") == "boat":
			var travel: float = float(actor.get_meta("travel",3.0))
			var angle: float = phase + time * 0.075
			var normal: Vector3 = (centre*radius+frame.x*cos(angle)*travel+frame.z*sin(angle)*travel*0.6).normalized()
			var forward: Vector3 = (-frame.x*sin(angle)+frame.z*cos(angle)*0.6).slide(normal).normalized()
			actor.transform = Transform3D(Basis(normal.cross(forward).normalized(),normal,forward),normal*(radius+0.08+sin(time*1.7+phase)*0.045))
			actor.rotate_object_local(Vector3.FORWARD,sin(time*1.2+phase)*0.025)
		elif actor.get_meta("kind","") == "fish":
			var t: float = fposmod(time+phase,6.2)/1.7
			actor.visible = t < 1.0
			if not actor.visible:
				continue
			var lane: float = float(actor.get_meta("lane",0.0))
			var normal: Vector3 = (centre*radius+frame.x*(t-0.5)*4.2+frame.z*lane).normalized()
			var forward: Vector3 = (frame.x+normal*cos(t*PI)*1.1).normalized()
			var side: Vector3 = normal.cross(forward).normalized()
			actor.transform = Transform3D(Basis(side,forward.cross(side).normalized(),forward),normal*(radius-0.3+sin(t*PI)*1.8))
		elif actor.get_meta("kind","") == "ripple":
			var pulse: float = fposmod(time+phase,3.1)/3.1
			actor.transform = Transform3D(frame.scaled(Vector3.ONE*(0.4+pulse*1.3)),centre*(radius+0.035))
			actor.visible = pulse < 0.9
		elif actor is MultiMeshInstance3D:
			var petals: MultiMesh = (actor as MultiMeshInstance3D).multimesh
			for i: int in range(petals.instance_count):
				var seed_value: float = float(i)
				var x: float = sin(seed_value*7.1)*7.0 + sin(time*0.7+seed_value)*0.55
				var z: float = cos(seed_value*4.3)*6.0 + sin(time*.43+seed_value*2.0)*.7
				var up: Vector3 = PlanetGeometry.surface(centre,Vector2(x,z),radius).normalized()
				var height: float = 0.24+fposmod(seed_value*0.73-time*(.22+fposmod(seed_value*.137,.23)),4.5)
				petals.set_instance_transform(i,Transform3D((PlanetGeometry.frame(up)*Basis(Vector3.UP,time*.55+seed_value)*Basis(Vector3.RIGHT,sin(time*1.7+seed_value)*.85)*Basis(Vector3.FORWARD,time*.35+seed_value)).scaled(Vector3.ONE*(.7+fposmod(seed_value*.31,.7))),up*(radius+height)))
