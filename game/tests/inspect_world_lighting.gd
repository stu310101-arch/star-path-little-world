extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world.tscn") as PackedScene
	var state: SceneState = packed.get_state()
	var result: Dictionary = {}
	for index: int in range(state.get_node_count()):
		var node_name: String = str(state.get_node_name(index))
		if node_name not in ["Sun", "Fill", "Environment"]:
			continue
		var properties: Dictionary = {}
		for property_index: int in range(state.get_node_property_count(index)):
			var key: String = str(state.get_node_property_name(index, property_index))
			var value: Variant = state.get_node_property_value(index, property_index)
			if value is Environment:
				properties[key] = {"ambient_color": (value as Environment).ambient_light_color, "ambient_energy": (value as Environment).ambient_light_energy, "tonemap": (value as Environment).tonemap_mode}
			else:
				properties[key] = str(value)
		result[node_name] = properties
	print("WORLD_LIGHTING ", JSON.stringify(result))
	quit()
