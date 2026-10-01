extends RefCounted

# Static bounds are inserted once, not rediscovered by a world scan per frame.
# Query the whole padded eye-to-target corridor, including shoulder/head rays.
var cell_size: float = 12.0
var _cells: Dictionary = {}
var _entries: Dictionary = {}
var _query_seen: Dictionary = {}
var _query_result: Array[int] = []

func insert(id: int, bounds: AABB) -> void:
	remove(id)
	var occupied: Array[Vector3i] = []
	var first: Vector3i = _cell(bounds.position)
	var last: Vector3i = _cell(bounds.end)
	for x: int in range(first.x,last.x+1):
		for y: int in range(first.y,last.y+1):
			for z: int in range(first.z,last.z+1):
				var key: Vector3i = Vector3i(x,y,z)
				if not _cells.has(key):
					_cells[key] = []
				(_cells[key] as Array).append(id)
				occupied.append(key)
	_entries[id] = {"cells":occupied,"bounds":bounds}

func remove(id: int) -> void:
	if not _entries.has(id):
		return
	for key: Vector3i in _entries[id].cells:
		var bucket: Array = _cells[key]
		bucket.erase(id)
		if bucket.is_empty():
			_cells.erase(key)
	_entries.erase(id)

func query(eye: Vector3, aim: Vector3, padding: float) -> Array[int]:
	_query_seen.clear()
	_query_result.clear()
	var corridor: AABB = AABB(eye,Vector3.ZERO).expand(aim).grow(padding)
	var first: Vector3i = _cell(corridor.position)
	var last: Vector3i = _cell(corridor.end)
	for x: int in range(first.x,last.x+1):
		for y: int in range(first.y,last.y+1):
			for z: int in range(first.z,last.z+1):
				var key: Vector3i = Vector3i(x,y,z)
				if not _cells.has(key):
					continue
				for id: int in _cells[key]:
					if _query_seen.has(id):
						continue
					_query_seen[id] = true
					var bounds: AABB = _entries[id].bounds
					if bounds.intersects(corridor) or bounds.has_point(eye):
						_query_result.append(id)
	return _query_result

func clear() -> void:
	_cells.clear()
	_entries.clear()
	_query_seen.clear()
	_query_result.clear()

func size() -> int:
	return _entries.size()

func _cell(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x/cell_size),floori(point.y/cell_size),floori(point.z/cell_size))
