extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")

static func build(radius: float) -> ArrayMesh:
	# Keep roughly the same world-space tessellation as the original R=600
	# ocean. A compact globe needs fewer triangles; the freshwater cutter still
	# refines local boundaries independently.
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius*2.0
	var segments: int = clampi(ceili(radius/600.0*512.0/32.0)*32,128,512)
	sphere.radial_segments = segments
	sphere.rings = segments/2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,sphere.get_mesh_arrays())
	return mesh

