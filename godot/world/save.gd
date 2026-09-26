class_name Save
extends RefCounted

## 캐릭터를 `user://` 에 저장한다.
##
## 웹에서는 고도가 `user://` 를 IndexedDB 로 잡아 주므로 같은 코드가 돈다
## (브라우저·기기마다 따로 남는다 — 웹 클라이언트의 로컬 모드와 같은 한계다).
##
## **판정에 쓰는 값만 저장한다.** 화면이 만들어 내는 것(카메라·이펙트)은 넣지
## 않는다. 몬스터 체력도 넣지 않는다 — 다시 들어오면 새로 스폰되는 게 맞다.
##
## 서버를 붙이면 이 자리는 서버 DB(packages/server/src/db.ts) 로 간다.
## 그때까지는 혼자 노는 저장이다.

const PATH := "user://save.json"
const VERSION := 1


static func write(zone_id: String, player: Dictionary) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("저장 못 함: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({
		"version": VERSION,
		"zone": zone_id,
		"x": player.x,
		"z": player.z,
		"level": player.level,
		# 전직 단계 (0 = 전직 전) — 없던 칸이라 옛 저장은 0 으로 읽힌다
		"job_tier": player.get("job_tier", 0),
		"exp": player.exp,
		"hp": player.hp,
		"dead": player.get("dead", false),
		"gold": player.get("gold", 0),
		"skills": player.get("skills", []),
		"skill_points": player.get("skill_points", 0),
		"skill_bar": player.get("skill_bar", []),
		"bag": player.get("bag", []),
		"equipped": player.get("equipped", {}),
		# 한 번만 주는 것을 받았다는 표시 — 없던 칸이라 옛 저장은 빈 목록으로 읽힌다
		"granted": player.get("granted", []),
		# 스킬 강화 `{ 스킬 id: [강화 id, …] }` — 없던 칸이라 옛 저장은 빈 사전으로 읽힌다
		"skill_upgrades": player.get("skill_upgrades", {}),
		# 붙기 전까지 쌓인 경험치 `{ 스킬 id: { 강화 id: 경험치 } }` — 이것도 없던 칸이다
		"skill_upgrade_exp": player.get("skill_upgrade_exp", {}),
		# 물약을 저절로 마시는 기준(HP %) — 없던 칸이라 옛 저장은 처음 값(50)으로 읽힌다
		"potion_pct": player.get("potion_pct", 50),
	}, "\t"))
	file.close()


## 없거나 낡았으면 빈 것을 준다 — 부르는 쪽이 기본값으로 시작한다
static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var text := FileAccess.get_file_as_string(PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("저장이 깨졌다 — 새로 시작한다")
		return {}
	if int(parsed.get("version", 0)) != VERSION:
		# 칸이 바뀌면 그냥 버린다. 혼자 노는 저장이라 되살릴 값이 없다
		return {}
	return parsed


static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
