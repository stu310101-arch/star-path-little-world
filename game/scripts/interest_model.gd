extends RefCounted
## Values stay as text while drafting: an empty score is never a zero score.
const CATALOG_PATH: String = "res://data/interest_catalog.json"
const INITIAL_ROWS: int = 25
const MAX_ROWS: int = 512
const SCORE_KEYS: Array[String] = ["R", "I", "A", "S", "E", "C"]

static func catalog() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return data if data is Dictionary else {}

static func empty_row() -> Dictionary:
	return {"groupId":"", "category":"", "z":""}

static func new_profile() -> Dictionary:
	var profile: Dictionary = {"schemaVersion":1,"catalogVersion":1,"title":"","riasecDate":"","knowledgeDate":"","riasec":{},"knowledge":{},"bestFits":[],"suitableFits":[]}
	for key: String in SCORE_KEYS:
		profile.riasec[key] = ""
	for index: int in range(1,34):
		profile.knowledge["k%02d" % index] = ""
	for section: String in ["bestFits","suitableFits"]:
		for index: int in range(INITIAL_ROWS):
			profile[section].append(empty_row())
	return profile

static func for_editing(source: Dictionary) -> Dictionary:
	var profile: Dictionary = new_profile()
	for key: String in ["title","riasecDate","knowledgeDate"]:
		profile[key] = str(source.get(key,""))
	for section: String in ["riasec","knowledge"]:
		var supplied: Dictionary = source.get(section,{})
		for key: String in profile[section]:
			profile[section][key] = str(supplied.get(key,""))
	for section: String in ["bestFits","suitableFits"]:
		profile[section] = []
		for value: Variant in source.get(section,[]):
			if value is Dictionary:
				profile[section].append({"groupId":str(value.get("groupId","")),"category":str(value.get("category","")),"z":str(value.get("z",""))})
		while profile[section].size() < INITIAL_ROWS:
			profile[section].append(empty_row())
	return profile

static func is_blank_row(row: Dictionary) -> bool:
	return str(row.get("groupId","")).strip_edges().is_empty() and str(row.get("category","")).strip_edges().is_empty() and str(row.get("z","")).strip_edges().is_empty()

static func integer_score(value: String, maximum: int) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9]+$")
	var trimmed: String = value.strip_edges()
	return trimmed.length() <= 32 and pattern.search(trimmed) != null and trimmed.to_float() >= 0.0 and trimmed.to_float() <= maximum

static func signed_decimal(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)$")
	var trimmed: String = value.strip_edges()
	return trimmed.length() <= 32 and pattern.search(trimmed) != null and is_finite(trimmed.to_float())

static func validate(profile: Dictionary) -> Dictionary:
	var errors: Dictionary = {}
	if str(profile.get("title","")).length() > 80:
		errors["title"] = "名稱請在 80 字以內。"
	for section: String in ["riasec","knowledge"]:
		var keys: Array[String] = []
		if section == "riasec":
			keys.assign(SCORE_KEYS)
		if section == "knowledge":
			for index: int in range(1,34):
				keys.append("k%02d" % index)
		var maximum: int = 90 if section == "riasec" else 18
		var values: Dictionary = profile.get(section,{})
		for key: String in keys:
			var text: String = str(values.get(key,""))
			if not integer_score(text,maximum):
				errors[section+"."+key] = "請填寫 0–%d 的整數；0 分請輸入 0。" % maximum
	var group_ids: Array[String] = []
	for item: Dictionary in catalog().get("groups",[]):
		group_ids.append(str(item.id))
	var seen: Dictionary = {}
	for section: String in ["bestFits","suitableFits"]:
		var rows: Array = profile.get(section,[])
		for index: int in range(rows.size()):
			var row: Dictionary = rows[index]
			if is_blank_row(row):
				continue
			var prefix: String = section+"."+str(index)+"."
			var group: String = str(row.get("groupId",""))
			var category: String = str(row.get("category","")).strip_edges()
			if group not in group_ids:
				errors[prefix+"groupId"] = "請選擇學群。"
			if category.is_empty() or category.length() > 80:
				errors[prefix+"category"] = "請依報告填寫學類，最多 80 字。"
			if not signed_decimal(str(row.get("z",""))):
				errors[prefix+"z"] = "請填寫 Z 分數，可有負號與小數。"
			if not group.is_empty() and not category.is_empty():
				var identity: String = group+"|"+category.to_lower()
				if seen.has(identity):
					errors[prefix+"category"] = "這個學群與學類已填寫，兩個程度之間也不可重複。"
				else:
					seen[identity] = true
	return errors

static func normalized(profile: Dictionary) -> Dictionary:
	var result: Dictionary = profile.duplicate(true)
	result.title = str(result.get("title","")).strip_edges()
	if result.title.is_empty():
		result.title = "興趣量表紀錄"
	# Legacy dates remain opaque version-one compatibility data, never form input.
	for section: String in ["riasec","knowledge"]:
		for key: String in result[section]:
			result[section][key] = str(str(result[section][key]).strip_edges().to_int())
	for section: String in ["bestFits","suitableFits"]:
		var clean: Array = []
		for row: Dictionary in result[section]:
			if not is_blank_row(row):
				clean.append({"groupId":str(row.groupId),"category":str(row.category).strip_edges(),"z":str(row.z).strip_edges()})
		result[section] = clean
	return result

static func filled_count(profile: Dictionary) -> int:
	var count: int = 0
	for section: String in ["riasec","knowledge"]:
		for value: Variant in profile.get(section,{}).values():
			if not str(value).strip_edges().is_empty():
				count += 1
	return count
