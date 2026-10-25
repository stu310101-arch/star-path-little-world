extends Node
func _ready() -> void:
	await get_node("/root/ResourceProfile").call("prepare_entry")
	get_node("/root/AccountGate").call_deferred("start")
