class_name Trainers
extends RefCounted

## PT 트레이너 표 읽기 — `trainers.json` (원본은 packages/shared/src/trainers.ts).
## 판정은 장부(`Ledger.trainer_draw` · `trainer_pick`), 동행 전투는 `World._step_buddies`,
## 창은 `TrainerPanel` → docs/features/trainers.md
##
## 장부 칸 둘:
##   `trainers`       = { 트레이너 id: 뽑은 개수 }  — 하나라도 있으면 보유 (보유 효과가 붙는다)
##   `trainer_active` = 동행 트레이너 id — 없으면 ""


static func table() -> Dictionary:
	return GameData.load_table("trainers")


## 명단 53명 — 등급 순서 그대로 (일반 → 전설)
static func all() -> Array:
	return table().get("trainers", [])


static func trainer(id: String) -> Dictionary:
	for each in all():
		if str(each.get("id", "")) == id:
			return each
	return {}


## 등급 한 줄 `{grade, name, inherit, owned, chance, count}` — 없으면 빈 사전
static func grade(g: int) -> Dictionary:
	for each in table().get("grades", []):
		if int(each.get("grade", 0)) == g:
			return each
	return {}


static func grades() -> Array:
	return table().get("grades", [])


static func of_grade(g: int) -> Array:
	var out: Array = []
	for each in all():
		if int(each.get("grade", 0)) == g:
			out.append(each)
	return out


static func stat_name(stat: String) -> String:
	return str(table().get("statNames", {}).get(stat, stat))


static func draw_cost() -> int:
	return int(table().get("drawCost", 100))


static func draw_multi() -> int:
	return int(table().get("drawMulti", 10))


## 동행 트레이너의 계승 비율(0 ~ 1) — 갖고 있지 않거나 없으면 0
static func inherit_of(owned: Dictionary, active: String) -> float:
	if active == "" or int(owned.get(active, 0)) <= 0:
		return 0.0
	return float(trainer(active).get("inherit", 0)) / 100.0


## 보유 효과 합 — `{attack, defense, maxHp}` 는 %, `{crit, critDamage}` 는 **비율**(0.08 = 8%p)
static func owned_bonus(owned: Dictionary) -> Dictionary:
	var sum := {"attack": 0.0, "defense": 0.0, "maxHp": 0.0, "crit": 0.0, "critDamage": 0.0}
	for id in owned:
		if int(owned[id]) <= 0:
			continue
		var info := trainer(str(id))
		if info.is_empty():
			continue
		var stat := str(info.stat)
		var value := float(info.owned)
		sum[stat] = float(sum[stat]) + (value / 100.0 if stat in ["crit", "critDamage"] else value)
	return sum


## 한 번 굴린다 — 등급을 확률로 고르고 그 등급 안에서 고르게. 굴리는 쪽은 장부다
static func roll(rng: RandomNumberGenerator) -> String:
	var r := rng.randf() * 100.0
	var pick := 1
	var acc := 0.0
	for each in grades():
		acc += float(each.chance)
		pick = int(each.grade)
		if r < acc:
			break
	var pool := of_grade(pick)
	if pool.is_empty():
		return ""
	return str(pool[rng.randi_range(0, pool.size() - 1)].id)


## 저장에서 되살린다 — 표에 있는 id 만, 개수는 1 이상
static func clean(raw: Variant) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for id in raw:
			if int(raw[id]) > 0 and not trainer(str(id)).is_empty():
				out[str(id)] = int(raw[id])
	return out


## 모델·원화 파일 이름 — `trainer_<id>.glb` · `trainer_<id>.jpg` (godot/assets)
static func look(id: String) -> String:
	return "trainer_" + id
