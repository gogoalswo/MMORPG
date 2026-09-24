class_name Skills
extends RefCounted

## packages/shared/src/skills.ts 의 판정 함수 이식본.
##
## **스킬 내용(34종)은 다시 만들기로 했다.** 여기 있는 것은 내용과 무관한 규칙뿐이고,
## 표(`data/skills.json`)가 바뀌어도 그대로 돈다.
##
## 테스트 스위치 두 개가 표에 같이 들어 있다 — 켜져 있으면 쿨타임이 0 이고
## 요구 레벨·스킬 포인트를 안 본다. 끄면 곧바로 다시 잠긴다.

static func _table() -> Dictionary:
	return GameData.load_table("skills")


static func all() -> Dictionary:
	return _table().get("skills", {})


static func for_job(job: String) -> Array:
	return _table().get("byJob", {}).get(job, [])


## **이 직업이 실제로 가진 스킬인지 — 판정하는 쪽이 반드시 확인해야 한다**
static func get_skill(job: String, skill_id: String) -> Dictionary:
	var skill: Dictionary = all().get(skill_id, {})
	if skill.is_empty() or str(skill.get("job", "")) != job:
		return {}
	return skill


## 스킬 강화 하나 (`SKILL_UPGRADES`). 없으면 빈 사전
static func upgrade(skill_id: String, upgrade_id: String) -> Dictionary:
	for entry in _table().get("upgrades", []):
		if str(entry.get("skill", "")) == skill_id and str(entry.get("id", "")) == upgrade_id:
			return entry
	return {}


## 스킬 경험치북 표 (`SKILL_EXP_BOOKS`) — 하급·중급·상급 순
static func exp_books() -> Array:
	return _table().get("expBooks", [])


## 이 스킬의 강화들 — **표 순서가 곧 1번·2번** 이다 (스킬창의 강화 칸 순서)
static func upgrades_of(skill_id: String) -> Array:
	var out: Array = []
	for entry in _table().get("upgrades", []):
		if str(entry.get("skill", "")) == skill_id:
			out.append(entry)
	return out


## 붙은 강화들의 판정 사거리 배율. 여럿이면 곱한다
static func range_mul(skill_id: String, upgrade_ids: Array) -> float:
	var out := 1.0
	for id in upgrade_ids:
		out *= float(upgrade(skill_id, str(id)).get("rangeMul", 1.0))
	return out


## 붙은 강화들의 **더하는** 값 합 — `arcAdd`(부채꼴 각, rad) · `extraHits`(다단 히트)
static func upgrade_sum(skill_id: String, upgrade_ids: Array, key: String) -> float:
	var out := 0.0
	for id in upgrade_ids:
		out += float(upgrade(skill_id, str(id)).get(key, 0.0))
	return out


## 붙은 강화들이 맞은 몬스터를 세우는 시간(ms). 여럿이면 긴 쪽이다
static func stun_ms(skill_id: String, upgrade_ids: Array) -> int:
	var out := 0
	for id in upgrade_ids:
		out = maxi(out, int(upgrade(skill_id, str(id)).get("stunMs", 0)))
	return out


static func cooldown_off() -> bool:
	return bool(_table().get("cooldownOff", false))


static func unlock_all() -> bool:
	return bool(_table().get("unlockAll", false))


## 테스트 스위치를 켜고 끈다. **World 만 부른다** (화면 단추는 요청을 보낼 뿐이다).
## 표는 메모리에 한 벌이라 판정과 화면이 같이 따라온다. 파일은 안 바꾸므로
## 다시 켜면 `skills.json` 의 값으로 돌아간다
const SWITCHES := ["cooldownOff", "unlockAll"]


static func set_switch(name: String, on: bool) -> bool:
	if not (name in SWITCHES):
		return false
	_table()[name] = on
	return true


## 실제로 적용할 쿨타임(ms) — 테스트 스위치가 켜져 있으면 0
static func cooldown_of(skill: Dictionary) -> int:
	return 0 if cooldown_off() else int(skill.get("cooldown", 0))


## 배울 수 있나. **직업은 스위치와 무관하게 본다** —
## 남의 직업 스킬은 배워 봐야 쓸 수가 없다
static func can_learn(skill: Dictionary, job: String, level: int) -> bool:
	if str(skill.get("job", "")) != job:
		return false
	return unlock_all() or level >= int(skill.get("reqLevel", 1))


static func point_cost() -> int:
	return 0 if unlock_all() else 1


## 날아가는 것이 보이는 스킬인가. 따로 필드를 두지 않고 projectile 로 가른다 —
## 필드를 하나 더 만들면 두 값이 어긋난 스킬이 반드시 생긴다
static func is_ranged(skill: Dictionary) -> bool:
	return str(skill.get("projectile", "")) != ""


## 원거리 스킬이 **타겟 자리에서** 터질 때의 판정 반경.
##
## 사거리를 그대로 쓰면 안 된다 — 원거리기는 사거리가 10~14 라 타겟을 중심으로
## 그만큼 잡으면 화면 전체가 범위가 된다. 단일기는 몸 하나 크기만 본다
static func blast_radius(skill: Dictionary) -> float:
	var c := GameData.combat()
	var minimum := float(c.get("skillBlastMin", 0.6))
	if int(skill.get("maxTargets", 1)) <= 1:
		return minimum
	return minf(
		float(c.get("skillBlastMax", 6.0)),
		maxf(minimum, float(skill.get("range", 0)) * float(c.get("skillBlastRatio", 0.35))),
	)


## 스킬창 설명에 붙이는 피해 줄. "데미지 : 260%", 연타는 "데미지 : 56% * 5연타".
##
## World 가 한 대마다 `공격력 × power` 를 넣고 `hits` 대를 치므로 그 두 값을
## 그대로 적는다. 회복기는 공격 판정을 안 하므로 빈 글자
static func damage_text(skill: Dictionary) -> String:
	if skill.is_empty() or float(skill.get("selfHeal", 0.0)) > 0.0:
		return ""
	var text := "데미지 : %d%%" % roundi(float(skill.get("power", 1.0)) * 100.0)
	var hits := int(skill.get("hits", 1))
	if hits > 1:
		text += " * %d연타" % hits
	return text
