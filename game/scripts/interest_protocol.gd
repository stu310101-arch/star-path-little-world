extends RefCounted
## Private score data only. Credentials, account IDs and arbitrary paths are forbidden.
const CHANNEL: String = "starpath-interest"
const MAX_BYTES: int = 65536
const PROFILE_MAX_BYTES: int = 61440
const PROFILE_KEYS: Array[String] = ["schemaVersion","catalogVersion","title","riasecDate","knowledgeDate","riasec","knowledge","bestFits","suitableFits"]
const RIASEC: Array[String] = ["R","I","A","S","E","C"]
const GROUPS: Array[String] = ["information","engineering","math-chemistry","health-medicine","life-science","bio-resources","earth-environment","architecture-design","arts","social-psychology","mass-communication","foreign-languages","literature-history-philosophy","education","law-politics","management","finance-economics","recreation-sports"]

static func identifier(value: Variant) -> bool:
	if not value is String or value.length() < 1 or value.length() > 64:
		return false
	for character: String in value:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true

static func revision(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 9007199254740991 and floorf(float(value)) == float(value)

static func exact(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true

static func bounded_text(value: Variant, maximum: int) -> bool:
	if not value is String or value.length() > maximum:
		return false
	for index: int in range(value.length()):
		var point: int = value.unicode_at(index)
		if point < 32 and point not in [9,10,13]:
			return false
	return true

static func profile(value: Variant) -> Dictionary:
	if not value is Dictionary or not exact(value, PROFILE_KEYS) or value.get("schemaVersion") != 1 or value.get("catalogVersion") != 1 or JSON.stringify(value).to_utf8_buffer().size() > PROFILE_MAX_BYTES:
		return {}
	if not bounded_text(value.title,80) or not bounded_text(value.riasecDate,32) or not bounded_text(value.knowledgeDate,32):
		return {}
	var knowledge: Array[String] = []
	for index: int in range(1,34):
		knowledge.append("k%02d" % index)
	for field: String in ["riasec","knowledge"]:
		var keys: Array[String] = RIASEC if field == "riasec" else knowledge
		if not value[field] is Dictionary or not exact(value[field],keys):
			return {}
		for key: String in keys:
			if not bounded_text(value[field][key],32):
				return {}
	for field: String in ["bestFits","suitableFits"]:
		if not value[field] is Array or value[field].size() > 512:
			return {}
		for row: Variant in value[field]:
			if not row is Dictionary or not exact(row,["groupId","category","z"]) or not bounded_text(row.groupId,40) or not bounded_text(row.category,80) or not bounded_text(row.z,32):
				return {}
			if row.groupId != "" and row.groupId not in GROUPS:
				return {}
	return value.duplicate(true)

static func cursor(value: Variant) -> bool:
	return value is Dictionary and exact(value,["createdAtMillis","id"]) and revision(value.createdAtMillis) and identifier(value.id)

static func sanitize_command(value: Dictionary, generation: int) -> Dictionary:
	var clean: Dictionary = value.duplicate(true)
	clean["sessionGeneration"] = generation
	if not identifier(clean.get("requestId")) or not revision(generation) or JSON.stringify(clean).to_utf8_buffer().size() > MAX_BYTES:
		return {}
	var keys: Array[String] = ["requestId","sessionGeneration","action"]
	var action: String = str(clean.get("action",""))
	if action == "list":
		if clean.has("cursor"):
			keys.append("cursor")
			if not cursor(clean.cursor):
				return {}
	elif action in ["get","saveDraft","complete","setActive"]:
		keys.append("recordId")
		if not identifier(clean.get("recordId")):
			return {}
		if action in ["saveDraft","complete"]:
			keys.append_array(["expectedRevision","profile"])
			if not revision(clean.get("expectedRevision")) or profile(clean.get("profile")).is_empty():
				return {}
		elif action == "setActive":
			keys.append("expectedSelectionRevision")
			if not revision(clean.get("expectedSelectionRevision")):
				return {}
	else:
		return {}
	return clean if exact(clean,keys) else {}

static func sanitize_packet(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("channel") != CHANNEL or value.get("version") != 1 or not identifier(value.get("requestId")) or not revision(value.get("sessionGeneration")) or JSON.stringify(value).to_utf8_buffer().size() > MAX_BYTES:
		return {}
	var kind: String = str(value.get("type",""))
	var clean: Dictionary = {"channel":CHANNEL,"version":1,"requestId":value.requestId,"sessionGeneration":int(value.sessionGeneration),"type":kind}
	if kind == "error":
		if not bounded_text(value.get("code"),80) or not bounded_text(value.get("message"),240):
			return {}
		clean.merge({"code":value.code,"message":value.message})
		return clean
	if not value.get("activeRecordId") is String or (value.activeRecordId != "" and not identifier(value.activeRecordId)) or not revision(value.get("selectionRevision")):
		return {}
	clean.merge({"activeRecordId":value.activeRecordId,"selectionRevision":int(value.selectionRevision)})
	if kind == "active":
		return clean
	if kind == "state":
		if not identifier(value.get("recordId")) or not revision(value.get("revision")) or not revision(value.get("updatedAtMillis")) or not value.get("hasCompleted") is bool or not value.get("hasDraft") is bool:
			return {}
		var contents: Variant = null
		if value.get("profile") != null:
			contents = profile(value.profile)
			if contents.is_empty():
				return {}
		elif value.hasCompleted or value.hasDraft or int(value.revision) != 0:
			return {}
		clean.merge({"recordId":value.recordId,"revision":int(value.revision),"profile":contents,"hasCompleted":value.hasCompleted,"hasDraft":value.hasDraft,"updatedAtMillis":int(value.updatedAtMillis)})
		return clean
	if kind != "list" or not value.get("records") is Array or value.records.size() > 20 or (value.get("nextCursor") != null and not cursor(value.nextCursor)):
		return {}
	var records: Array[Dictionary] = []
	for row: Variant in value.records:
		if not row is Dictionary or not identifier(row.get("id")) or not bounded_text(row.get("title"),80) or not bounded_text(row.get("riasecDate"),32) or not bounded_text(row.get("knowledgeDate"),32) or not revision(row.get("revision")) or not revision(row.get("createdAtMillis")) or not revision(row.get("updatedAtMillis")) or not row.get("hasCompleted") is bool or not row.get("hasDraft") is bool:
			return {}
		var item: Dictionary = {}
		for field: String in ["id","title","riasecDate","knowledgeDate","revision","createdAtMillis","updatedAtMillis","hasCompleted","hasDraft"]:
			item[field] = row[field]
		records.append(item)
	clean.merge({"records":records,"nextCursor":value.get("nextCursor")})
	return clean
