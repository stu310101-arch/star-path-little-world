extends RefCounted
## Public display-only transport. No account identifiers or credentials cross it.
const CHANNEL: String = "starpath-forum"
const ZONES: Array[String] = ["university", "major", "career", "high_school", "campus"]
const IDENTITIES: Array[String] = ["high_school", "graduate", "university", "professional"]
const MAX_BYTES: int = 4096

static func valid_id(value: Variant) -> bool:
	if not value is String or value.length() < 1 or value.length() > 80:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

static func sanitize_packet(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("channel") != CHANNEL or value.get("version") != 1:
		return {}
	if JSON.stringify(value).to_utf8_buffer().size() > MAX_BYTES or not valid_id(value.get("requestId")):
		return {}
	if value.get("zone") not in ZONES or not (value.get("sessionGeneration") is int or value.get("sessionGeneration") is float):
		return {}
	var kind: String = str(value.get("type", ""))
	var clean: Dictionary = {"channel":CHANNEL,"version":1,"type":kind,"requestId":value.requestId,"sessionGeneration":int(value.sessionGeneration),"zone":value.zone}
	match kind:
		"page-begin":
			var count: int = int(value.get("itemCount", value.get("count", -1)))
			if count < 0 or count > 8:
				return {}
			clean["itemCount"] = count
			if value.has("devicePage"):
				if not (value.devicePage is int or value.devicePage is float) or float(value.devicePage) != floorf(float(value.devicePage)) or float(value.devicePage) < 0 or float(value.devicePage) > 999999:
					return {}
				clean["devicePage"] = int(value.devicePage)
		"page-empty":
			if not valid_id(value.get("threadId")) or not (value.get("index") is int or value.get("index") is float) or float(value.index) != floorf(float(value.index)) or int(value.index) < 0 or int(value.index) >= 8:
				return {}
			clean["index"] = int(value.index)
			clean["threadId"] = value.threadId
		"page-item":
			if not valid_id(value.get("threadId")) or not value.get("preview") is String or value.preview.length() > 120 or not value.get("authorName") is String or value.authorName.length() > 80 or not value.get("anonymous") is bool:
				return {}
			if value.get("identity") not in IDENTITIES:
				return {}
			var index: int = int(value.get("index", -1))
			if index < 0 or index >= 8:
				return {}
			for key: String in ["threadId", "preview", "anonymous"]:
				clean[key] = value[key]
			clean["index"] = index
			clean["authorName"] = "匿名" if value.anonymous else value.authorName
			clean["identity"] = str(value.get("identity", ""))
			clean["deleted"] = value.get("deleted", false) == true
			clean["createdAtMillis"] = int(value.get("createdAtMillis", 0))
			clean["updatedAtMillis"] = int(value.get("updatedAtMillis", 0))
		"page-end":
			if not value.get("hasNext") is bool or not value.get("hasPrevious") is bool:
				return {}
			clean["hasNext"] = value.hasNext
			clean["hasPrevious"] = value.hasPrevious
			clean["count"] = int(value.get("count", -1))
		"page-error":
			clean["code"] = str(value.get("code", "unavailable")).left(80)
		_:
			return {}
	return clean
