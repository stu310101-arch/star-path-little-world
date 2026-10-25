extends Node
## Drain an abandoned threaded load after completion without blocking return.
var path: String = ""

func _process(_delta: float) -> void:
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		ResourceLoader.load_threaded_get(path)
	queue_free()
