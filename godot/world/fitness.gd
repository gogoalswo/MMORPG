class_name Fitness
extends RefCounted

## 헬스 표 읽기 — `fitness.json` (원본은 packages/shared/src/fitness.ts).
## 판정은 장부(`Ledger.fitness_up`), 창은 `FitnessPanel` → docs/features/fitness.md
##
## 장부 칸 둘:
##   `proteins` = { "power": 개수, "defense": 개수, "health": 개수 }  — 던전을 깨면 쌓인다
##   `fitness`  = { "bench": 단계, "deadlift": 단계, "squat": 단계 } — 없으면 0 단계


static func table() -> Dictionary:
	return GameData.load_table("fitness")


## 운동 셋 — 탭 순서 그대로 (벤치프레스 · 데드리프트 · 스쿼트)
static func kinds() -> Array:
	return table().get("kinds", [])


static func kind(id: String) -> Dictionary:
	for each in kinds():
		if str(each.get("id", "")) == id:
			return each
	return {}


static func max_stage() -> int:
	return int(table().get("maxStage", 0))


## `stage` 단계로 **오르는** 한 번 — `{stage, chance, cost, gain, total}`. 없으면 빈 사전
static func step(stage: int) -> Dictionary:
	var steps: Array = table().get("steps", [])
	if stage < 1 or stage > steps.size():
		return {}
	return steps[stage - 1]


## `stage` 단계까지 모은 보너스(%) — 0 단계는 0
static func bonus(stage: int) -> float:
	if stage <= 0:
		return 0.0
	return float(step(mini(stage, max_stage())).get("total", 0))


## 지금 두드릴 수 있는 운동인가 — 끝 단계가 아니고 프로틴이 비용 이상. 헬스 창 탭과 HUD 헬스 아이콘의
## 빨간 점이 같이 쓴다 (`me` 는 스냅샷 — `fitness` · `proteins`)
static func can_up(me: Dictionary, id: String) -> bool:
	var info := kind(id)
	if info.is_empty():
		return false
	var stage := int(me.get("fitness", {}).get(id, 0))
	if stage >= max_stage():
		return false
	var cost := int(step(stage + 1).get("cost", 0))
	return cost > 0 and int(me.get("proteins", {}).get(str(info.protein), 0)) >= cost


## 하나라도 두드릴 수 있는 운동이 있나 — HUD 헬스 아이콘 · ≡ 의 빨간 점
static func any_up(me: Dictionary) -> bool:
	for each in kinds():
		if can_up(me, str(each.id)):
			return true
	return false


## 장부 `fitness` 사전 → 능력치별 보너스 `{attack, defense, maxHp}` (%) — `World.stats_of` 가 곱한다
static func stat_bonus(stages: Dictionary) -> Dictionary:
	var out := {"attack": 0.0, "defense": 0.0, "maxHp": 0.0}
	for each in kinds():
		out[str(each.stat)] = bonus(int(stages.get(str(each.id), 0)))
	return out


## 던전 단계(`GameData.dungeon_stage`)가 주는 프로틴 `{power: n, defense: n, health: n}` — 세 종 각각
static func dungeon_reward(stage: Dictionary) -> Dictionary:
	var count := int(stage.get("protein", 0))
	var out := {}
	if count <= 0:
		return out
	for each in kinds():
		out[str(each.protein)] = count
	return out
