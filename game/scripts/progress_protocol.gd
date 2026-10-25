extends RefCounted
const CHANNEL: String = "starpath-progress"
const Ids = preload("res://scripts/forum_protocol.gd")
static func school_id(value: Variant) -> bool:
	return value is String and value.length()==3 and value.is_valid_int() and int(value)>=1 and int(value)<=138
static func sanitize_packet(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("channel")!=CHANNEL or value.get("version")!=1 or value.get("app")!="university" or not Ids.valid_id(value.get("requestId")) or JSON.stringify(value).to_utf8_buffer().size()>4096:
		return {}
	var kind: String = str(value.get("type",""))
	var clean: Dictionary = {"channel":CHANNEL,"version":1,"app":"university","requestId":value.requestId,"type":kind,"sessionGeneration":int(value.get("sessionGeneration",-1))}
	if kind=="error":
		clean["code"] = str(value.get("code","unavailable")).left(80)
		return clean
	if kind!="state" or not value.get("favorites") is Dictionary or not value.get("explored") is Array or value.favorites.size()>138 or value.explored.size()>138:
		return {}
	var favorites: Dictionary = {}
	var explored: Array[String] = []
	for id: Variant in value.favorites:
		if not school_id(id) or not value.favorites[id] is bool:
			return {}
		favorites[id] = value.favorites[id]
	for id: Variant in value.explored:
		if not school_id(id):
			return {}
		if id not in explored:
			explored.append(id)
	clean["favorites"] = favorites
	clean["explored"] = explored
	clean["revision"] = int(value.get("revision",0))
	return clean
