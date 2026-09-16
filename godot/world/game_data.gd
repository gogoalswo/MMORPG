class_name GameData
extends RefCounted

## godot/data/*.json 을 읽는다. 그 JSON 은 packages/shared 에서 내보낸 것이고
## 손으로 고치지 않는다 — 고치면 npm test 가 잡는다
## (scripts/export-shared.mjs, docs/features/godot-migration.md).

const DIR := "res://data/"

static var _cache: Dictionary = {}

static func load_table(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var text := FileAccess.get_file_as_string(DIR + name + ".json")
	if text.is_empty():
		push_error("데이터를 못 읽었다: %s.json" % name)
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON 이 아니다: %s.json" % name)
		return {}
	_cache[name] = parsed
	return parsed

static func zones() -> Dictionary:
	return load_table("zones")

static func zone(id: String) -> Dictionary:
	var table := zones()
	var all: Dictionary = table.get("zones", {})
	if not all.has(id):
		push_error("없는 존: %s" % id)
		return {}
	return all[id]

static func start_zone() -> String:
	return zones().get("start", "village")

static func constants() -> Dictionary:
	return load_table("constants")

static func combat() -> Dictionary:
	return load_table("combat")
