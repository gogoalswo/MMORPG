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


## 붙은 강화들의 스킬 피해 배율. 여럿이면 곱한다 (할퀴기 "위력")
static func power_mul(skill_id: String, upgrade_ids: Array) -> float:
	var out := 1.0
	for id in upgrade_ids:
		out *= float(upgrade(skill_id, str(id)).get("powerMul", 1.0))
	return out


## 붙은 강화들의 **더하는** 값 합 — `extraHits`(다단 히트)
static func upgrade_sum(skill_id: String, upgrade_ids: Array, key: String) -> float:
	var out := 0.0
	for id in upgrade_ids:
		out += float(upgrade(skill_id, str(id)).get(key, 0.0))
	return out


## 기절이 어떻게 보이나 — 붙은 강화 중 `stunLook` 이 있으면 그것 (`ice`), 없으면 ""
static func stun_look(skill_id: String, upgrade_ids: Array) -> String:
	for id in upgrade_ids:
		var look := str(upgrade(skill_id, str(id)).get("stunLook", ""))
		if look != "":
			return look
	return ""


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


## 자동 사냥이 스킬을 볼 순서 (`World._auto_cast`). **쿨타임이 긴 것부터** (같으면 칸 순서).
## 사람이 순서를 정하던 설정 창은 2026-10-02 에 걷었다 ("설정 버튼 제거하고, 기능 지워").
##
## 칸 순서를 그대로 쓰던 때는 1번 칸 할퀴기(쿨타임 1초 = 동작 1초)가 시전이 끝날 때마다
## 돌아와 있어서 **할퀴기만 썼다** (2026-09-27 지적). 긴 것부터 보면 짧은 것은 긴 것이
## 도는 사이를 메운다. 쿨타임은 표의 값으로 잰다 — 테스트 스위치(쿨타임 0)가 켜져도
## 순서는 그대로다
static func auto_order(job: String, bar: Array) -> Array:
	var rest: Array = []
	for id in bar:
		if not (str(id) in rest):
			rest.append(str(id))
	# sort_custom 은 안정 정렬이 아니라 쿨타임이 같으면 칸 번호로 가른다
	rest.sort_custom(func(a: String, b: String) -> bool:
		var cool_a := int(get_skill(job, a).get("cooldown", 0))
		var cool_b := int(get_skill(job, b).get("cooldown", 0))
		if cool_a != cool_b:
			return cool_a > cool_b
		return bar.find(a) < bar.find(b)
	)
	return rest


## 배울 수 있나. **직업은 스위치와 무관하게 본다** — 남의 직업 스킬은 배워 봐야 쓸 수가 없다.
## 전직 잠금은 2026-09-29 에 전직째로 없앴다 (docs/features/job-advance.md)
static func can_learn(skill: Dictionary, job: String, level: int) -> bool:
	if str(skill.get("job", "")) != job:
		return false
	return unlock_all() or level >= int(skill.get("reqLevel", 1))


static func point_cost() -> int:
	return 0 if unlock_all() else 1


## 그 직업에 **보이는 액티브 스킬**이 있나. 없으면 화면이 퀵슬롯 스킬 칸 · 스킬창 장착 줄 ·
## 강화 칸 · 던전의 스킬 경험치를 숨긴다 (2026-09-29 — 격투가는 평타만 쓴다)
static func actives_shown(job: String) -> bool:
	return not for_job(job).is_empty()


## --- 패시브 (`skills.ts` 의 `PASSIVES` → docs/features/passives.md) ---

## 그 직업의 패시브들 — 표 순서
static func passives_for(job: String) -> Array:
	var out: Array = []
	for p in _table().get("passives", []):
		if str(p.get("job", "")) == job:
			out.append(p)
	return out


## 스킬·패시브의 아이콘 이름 (`skill_<이름>.png`) — 패시브는 표의 `icon`(철각 계열이 철각 그림을 같이 쓴다), 없으면 id
static func icon_of(id: String) -> String:
	return str(passive(id).get("icon", id))


## id 로 하나. 없으면 빈 사전
static func passive(id: String) -> Dictionary:
	for p in _table().get("passives", []):
		if str(p.get("id", "")) == id:
			return p
	return {}


## 그 레벨까지 열린 단계 수 — Lv.10 에 1 (`passiveRankOpen` 과 같은 식)
static func passive_open(p: Dictionary, level: int) -> int:
	var every := maxi(1, int(p.get("everyLevels", 10)))
	return clampi(level / every, 0, int(p.get("maxRank", 0)))


## 앞 단계(`requires`)를 끝까지 배웠나 — 없으면 참. 스킬창 나무에서 그 칸 위로 이어진 것
## (2026-09-30 요청: "그 전 단계를 습득해야 다음 단계도 습득할 수 있게")
static func passive_ready(p: Dictionary, ranks: Dictionary) -> bool:
	var need := str(p.get("requires", ""))
	return need == "" or int(ranks.get(need, 0)) >= int(passive(need).get("maxRank", 1))


## 그 패시브의 다음 단계를 지금 배울 수 있나 — 레벨이 열렸고 앞 단계를 배웠다
static func passive_can_learn(p: Dictionary, level: int, ranks: Dictionary) -> bool:
	return int(ranks.get(str(p.id), 0)) < passive_open(p, level) and passive_ready(p, ranks)


## 지금 [습득] 을 누를 수 있는 패시브가 있나 — HUD 스킬 아이콘·스킬창 버튼의 **레드닷**
static func passive_learnable(job: String, level: int, ranks: Dictionary) -> bool:
	for p in passives_for(job):
		if passive_can_learn(p, level, ranks):
			return true
	return false


## 패시브가 올리는 스탯의 이름 — 스킬창·알림이 "공격력 +30%" 로 적는다
const PASSIVE_STAT_NAMES := {
	"attackSpeed": "공격 속도", "attack": "공격력", "moveSpeed": "이동 속도",
	"crit": "치명타 확률", "critDamage": "치명타 피해", "penetration": "방어력 관통",
}


## 그 단계의 효과 한 마디 — "공격 속도 +62%" (2026-09-30, 레벨 도달 패시브가 생겨 스탯 이름을 표에서 읽는다)
static func passive_effect(p: Dictionary, rank: int) -> String:
	var stat := str(p.get("stat", ""))
	return "%s +%d%%" % [
		str(PASSIVE_STAT_NAMES.get(stat, stat)), roundi(rank * float(p.get("perRank", 0.0)) * 100.0)
	]


## 나무 칸 하나의 이름 — 레벨 패시브는 표의 이름("철각 2단"), 여러 단계인 것(질풍각)은 "질풍각 N단"
## (2026-09-30 요청: "000 1단 이런식으로 이름 붙여")
static func passive_title(p: Dictionary, step: int) -> String:
	return str(p.get("name", "")) if passive_once(p) else "%s %d단" % [str(p.get("name", "")), step]


## 한 번 배우면 끝인 패시브인가 — 레벨 도달 패시브(`maxRank` 1). `everyLevels` 가 곧 여는 레벨이다
static func passive_once(p: Dictionary) -> bool:
	return int(p.get("maxRank", 0)) == 1


## 배운 패시브가 스탯에 더하는 양 `{ 스탯: 합 }` — `World.stats_of` 가 더한다
static func passive_bonus(job: String, ranks: Dictionary) -> Dictionary:
	var out := {}
	for p in passives_for(job):
		var rank := clampi(int(ranks.get(str(p.id), 0)), 0, int(p.get("maxRank", 0)))
		var stat := str(p.get("stat", ""))
		out[stat] = float(out.get(stat, 0.0)) + rank * float(p.get("perRank", 0.0))
	return out


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
