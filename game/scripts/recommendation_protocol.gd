extends RefCounted
## The host owns account identity and evaluation. This channel carries bounded display data.
const CHANNEL: String = "starpath-recommendations"
const MAX_BYTES: int = 65536
const Base = preload("res://scripts/interest_protocol.gd")
const TYPES: Dictionary = {"bootstrap":"bootstrap","listExams":"exams","query":"results","page":"results","detail":"detail","saveSettings":"settings","listFavorites":"favorites","setFavorite":"favorite"}
const STATUSES: Array[String] = ["all","passed","failed","pending","explore","extension"]
const ITEM_KEYS: Array[String] = ["programRef","year","programCode","schoolId","schoolName","programName","universityId","groupIds","categories","matchLevel","matchKind","status","statusLabel","priorityTier","reasons","missing","gapSummary","favorite","favoriteRevision"]

static func expected_type(action: String) -> String:
	return str(TYPES.get(action,""))

static func program_ref(value: Variant) -> bool:
	if not value is String or value.length()!=10 or value.substr(0,4) not in ["113:","114:","115:"]:
		return false
	for character: String in value.substr(4):
		if character not in "0123456789": return false
	return true

static func optional_id(value: Variant) -> bool:
	return value is String and (value.is_empty() or Base.identifier(value))

static func text_list(value: Variant, maximum: int = 128) -> bool:
	if not value is Array or value.size()>maximum:
		return false
	for item: Variant in value:
		if not Base.bounded_text(item,2048):
			return false
	return true

static func cursor(value: Variant) -> bool:
	return value == null or (value is String and value.length()>=1 and Base.bounded_text(value,2048))

static func settings(value: Variant) -> bool:
	if not value is Dictionary or not Base.exact(value,["source","manual","examId","mode","year","applicantGender","filters"]):
		return false
	if value.source not in ["activeReport","manual"] or value.mode not in ["balanced","interest","academic"] or value.year != "115" or value.applicantGender not in ["","male","female"] or not optional_id(value.examId):
		return false
	if not value.manual is Array or value.manual.size()>128:
		return false
	for row: Variant in value.manual:
		if not row is Dictionary or not Base.exact(row,["groupId","category","level"]) or row.groupId not in Base.GROUPS or not Base.bounded_text(row.category,80) or row.category.strip_edges().is_empty() or (not Base.revision(row.level) or int(row.level) not in [1,2]):
			return false
	return value.filters is Dictionary and Base.exact(value.filters,["keyword","category","status"]) and Base.bounded_text(value.filters.keyword,80) and Base.bounded_text(value.filters.category,80) and value.filters.status in STATUSES

static func sanitize_command(value: Dictionary, generation: int) -> Dictionary:
	var clean: Dictionary = value.duplicate(true)
	clean["sessionGeneration"] = generation
	if not Base.identifier(clean.get("requestId")) or not Base.revision(generation) or JSON.stringify(clean).to_utf8_buffer().size()>MAX_BYTES:
		return {}
	var keys: Array = ["requestId","sessionGeneration","action"]
	match str(clean.get("action","")):
		"bootstrap": pass
		"listExams","listFavorites":
			keys.append("cursor")
			if not cursor(clean.get("cursor")): return {}
		"query","saveSettings":
			keys.append("settings")
			if not settings(clean.get("settings")): return {}
			if clean.action=="saveSettings":
				keys.append("expectedRevision")
				if not Base.revision(clean.get("expectedRevision")): return {}
		"page","detail":
			keys.append("queryId")
			if not Base.identifier(clean.get("queryId")): return {}
			if clean.action=="page":
				keys.append("cursor")
				if clean.get("cursor")==null or not cursor(clean.get("cursor")): return {}
			else:
				keys.append("programRef")
				if not program_ref(clean.get("programRef")): return {}
		"setFavorite":
			keys.append_array(["programRef","value","expectedRevision"])
			if not program_ref(clean.get("programRef")) or not clean.get("value") is bool or not Base.revision(clean.get("expectedRevision")): return {}
		_: return {}
	return clean if Base.exact(clean,keys) else {}

static func _safe(value: Variant, depth: int = 0) -> bool:
	if depth>10: return false
	if value is Dictionary:
		if value.size()>80: return false
		for key: Variant in value:
			if not key is String or key in ["uid","token","idToken","accessToken","refreshToken","password","credential","customToken","path","__proto__","constructor","prototype"] or not _safe(value[key],depth+1): return false
	elif value is Array:
		if value.size()>1024: return false
		for child: Variant in value:
			if not _safe(child,depth+1): return false
	elif value is String:
		return Base.bounded_text(value,8192)
	elif value is float:
		return is_finite(value)
	elif value != null and not value is int and not value is bool:
		return false
	return true

static func report(value: Variant) -> bool:
	return value==null or (value is Dictionary and Base.exact(value,["recordId","revision","selectionRevision","title"]) and Base.identifier(value.recordId) and Base.revision(value.revision) and Base.revision(value.selectionRevision) and Base.bounded_text(value.title,80))

static func item(value: Variant) -> bool:
	if not value is Dictionary or not Base.exact(value,ITEM_KEYS) or not program_ref(value.programRef) or value.year not in ["113","114","115"] or not Base.bounded_text(value.programCode,6) or not Base.bounded_text(value.schoolId,12): return false
	if value.programRef!=value.year+":"+value.programCode or not Base.bounded_text(value.schoolName,160) or not Base.bounded_text(value.programName,200) or not Base.bounded_text(value.universityId,3): return false
	if not text_list(value.groupIds,18) or not text_list(value.categories,128) or (not Base.revision(value.matchLevel) or int(value.matchLevel) not in [0,1,2]) or value.matchKind not in ["exact","extension","none"] or value.status not in STATUSES or value.status=="all": return false
	return Base.bounded_text(value.statusLabel,240) and (value.priorityTier==null or Base.revision(value.priorityTier)) and text_list(value.reasons) and text_list(value.missing) and Base.bounded_text(value.gapSummary,2048) and value.favorite is bool and Base.revision(value.favoriteRevision)

static func sanitize_packet(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("channel")!=CHANNEL or value.get("version")!=1 or not Base.identifier(value.get("requestId")) or not Base.revision(value.get("sessionGeneration")) or JSON.stringify(value).to_utf8_buffer().size()>MAX_BYTES or not _safe(value): return {}
	var keys: Array = ["channel","version","requestId","sessionGeneration","type"]
	match str(value.get("type","")):
		"error":
			keys.append_array(["code","message"])
			if not Base.bounded_text(value.get("code"),80) or not Base.bounded_text(value.get("message"),240): return {}
		"bootstrap":
			keys.append_array(["settings","settingsRevision","activeReport","catalog","years","algorithmVersion","dataVersion"])
			if not settings(value.get("settings")) or not Base.revision(value.get("settingsRevision")) or not report(value.get("activeReport")) or not value.get("catalog") is Array or value.catalog.size()>512 or not text_list(value.get("years"),3): return {}
			for row: Variant in value.catalog:
				if not row is Dictionary or not Base.exact(row,["groupId","groupLabel","category"]) or row.groupId not in Base.GROUPS or not Base.bounded_text(row.groupLabel,80) or not Base.bounded_text(row.category,80): return {}
			if not Base.bounded_text(value.get("algorithmVersion"),80) or not Base.bounded_text(value.get("dataVersion"),160): return {}
		"exams","favorites":
			keys.append_array(["items","nextCursor"])
			if not value.get("items") is Array or value.items.size()>20 or not cursor(value.get("nextCursor")): return {}
			for row: Variant in value.items:
				if not row is Dictionary: return {}
				if value.type=="exams":
					if not Base.exact(row,["id","title","examDate","kind","summary","updatedAtMillis"]) or not Base.identifier(row.id) or not Base.bounded_text(row.title,160) or not Base.bounded_text(row.examDate,32) or not Base.bounded_text(row.kind,40) or not Base.bounded_text(row.summary,2048) or not Base.revision(row.updatedAtMillis): return {}
				else:
					if not Base.exact(row,["programRef","schoolName","programName","universityId","revision","updatedAtMillis"]) or not program_ref(row.programRef) or not Base.bounded_text(row.schoolName,160) or not Base.bounded_text(row.programName,200) or not Base.bounded_text(row.universityId,3) or not Base.revision(row.revision) or not Base.revision(row.updatedAtMillis): return {}
		"results":
			keys.append_array(["queryId","items","nextCursor","total","counts","inputs","warnings"])
			if not Base.identifier(value.get("queryId")) or not value.get("items") is Array or value.items.size()>20 or not cursor(value.get("nextCursor")) or not Base.revision(value.get("total")) or not text_list(value.get("warnings")): return {}
			for row: Variant in value.items:
				if not item(row): return {}
			if not value.get("counts") is Dictionary or not Base.exact(value.counts,["passed","failed","pending","explore","extension"]): return {}
			for total: Variant in value.counts.values():
				if not Base.revision(total): return {}
			var inputs: Variant = value.get("inputs")
			if not inputs is Dictionary or not Base.exact(inputs,["settings","report","exam","algorithmVersion","dataVersion"]) or not settings(inputs.settings) or not report(inputs.report): return {}
			if inputs.exam!=null:
				if not inputs.exam is Dictionary or not Base.exact(inputs.exam,["id","title","examDate","updatedAtMillis","summary"]) or not Base.identifier(inputs.exam.id) or not Base.bounded_text(inputs.exam.title,160) or not Base.bounded_text(inputs.exam.examDate,32) or not Base.revision(inputs.exam.updatedAtMillis) or not Base.bounded_text(inputs.exam.summary,2048): return {}
		"detail":
			keys.append_array(["queryId","item","details"])
			if not Base.identifier(value.get("queryId")) or not item(value.get("item")) or not value.get("details") is Dictionary: return {}
			var detail: Dictionary = value.details
			if not Base.exact(detail,["matchReasons","academicStatus","missing","rules","boostPlans","sources","history","reportSummary","fitEvidence","mappingNote"]) or not text_list(detail.matchReasons) or not text_list(detail.missing) or not Base.bounded_text(detail.academicStatus,80) or not Base.bounded_text(detail.mappingNote,2048): return {}
			for field: String in ["rules","boostPlans","sources","history","fitEvidence"]:
				if not detail[field] is Array: return {}
			if detail.rules.size()>128 or detail.boostPlans.size()>5 or detail.sources.size()>16 or detail.history.size()!=3: return {}
			for rule: Variant in detail.rules:
				if not rule is Dictionary or not Base.exact(rule,["label","actual","required","passed"]) or not Base.bounded_text(rule.label,240) or (rule.passed!=null and not rule.passed is bool): return {}
				for key: String in ["actual","required"]:
					if not Base.bounded_text(rule[key],512) and not (rule[key] is int or rule[key] is float): return {}
			for plan: Variant in detail.boostPlans:
				if not plan is Dictionary or not Base.exact(plan,["summary","changes"]) or not Base.bounded_text(plan.summary,2048) or not plan.changes is Array or plan.changes.size()>12: return {}
				for change: Variant in plan.changes:
					if not change is Dictionary or not Base.exact(change,["subject","from","to"]) or not Base.bounded_text(change.subject,40) or not Base.revision(change.from) or not Base.revision(change.to): return {}
			for link: Variant in detail.sources:
				if not link is Dictionary or not Base.exact(link,["label","url"]) or not Base.bounded_text(link.label,200) or not Base.bounded_text(link.url,4096): return {}
			for year: Variant in detail.history:
				if not year is Dictionary or not Base.exact(year,["year","programRef","status","label"]) or year.year not in ["113","114","115"] or (year.programRef!=null and not program_ref(year.programRef)) or year.status not in ["passed","failed","pending","explore","unmapped"] or not Base.bounded_text(year.label,240): return {}
			for fit: Variant in detail.fitEvidence:
				if not fit is Dictionary or not Base.exact(fit,["groupId","category","level","z"]) or fit.groupId not in Base.GROUPS or not Base.bounded_text(fit.category,80) or not Base.revision(fit.level) or int(fit.level) not in [1,2] or not Base.bounded_text(fit.z,32): return {}
			if detail.reportSummary!=null:
				if not detail.reportSummary is Dictionary or not Base.exact(detail.reportSummary,["riasec","knowledge"]): return {}
				for field: String in ["riasec","knowledge"]:
					if not detail.reportSummary[field] is Dictionary: return {}
					for score: Variant in detail.reportSummary[field].values():
						if not Base.bounded_text(score,32): return {}
		"settings":
			keys.append_array(["settings","settingsRevision"])
			if not settings(value.get("settings")) or not Base.revision(value.get("settingsRevision")): return {}
		"favorite":
			keys.append_array(["programRef","value","revision"])
			if not program_ref(value.get("programRef")) or not value.get("value") is bool or not Base.revision(value.get("revision")): return {}
		_: return {}
	return value.duplicate(true) if Base.exact(value,keys) else {}
