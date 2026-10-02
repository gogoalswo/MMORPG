class_name Ledger
extends RefCounted

## 장부 판정 한 벌 — **값이 생기고 없어지는 것**만 여기서 정한다 (docs/features/server.md).
## 드롭·경험치·레벨·골드·가방·장비·강화·크리스탈·스킬·스킬 강화·스킬 경험치·전직·한 번 주기·
## 헬스(프로틴·운동 단계)·장비 도감.
##
## 나중에 붙일 서버(고도 헤드리스)가 **이 파일을 그대로** 불러 판정한다. 그래서 여기에는
## 자리·체력·몬스터·NPC 거리 같은 **전투 쪽 값을 들이지 않는다** — 그건 기기에만 있다.
## NPC 곁인지는 부르는 쪽(`World`)이 먼저 본다.
##
## 받는 `p` 는 플레이어 사전이지만 **`KEYS` 칸만 읽고 쓴다.** 서버는 이 칸만 DB 에 둔다.
## 판정 결과는 `events` 에 쌓고, 부르는 쪽이 `take_events` 로 가져간다.
## 스탯을 다시 만드는 것(`World._refresh_stats`)도 부르는 쪽이 한다.

## 서버가 가질 칸. 여기 없는 칸은 이 파일이 만지지 않는다
const KEYS := [
	"job", "level", "exp", "gold", "skills", "skill_points", "passives",
	"skill_upgrades", "skill_upgrade_exp", "skill_exp", "bag", "equipped", "granted",
	"diamonds", "proteins", "fitness", "codex", "sandbag",
]

## **첫 선물** — 새 캐릭터가 한 번만 받는 것 `[[표시, 묶음], …]`. 로컬은 `LocalTransport.open` 이,
## 서버는 계정을 만들 때 준다 — 서버는 기기의 `grant_once` 를 받지 않으니 목록이 한 곳이어야 한다.
## 크리스탈 30개: 드랍이 0.1% 라 주워서는 시험해 볼 수 없다 (2026-09-23 요청 "가방에 30개 넣어")
static func welcome_gifts() -> Array:
	return [["crystal30", {"id": Items.crystal_id(), "count": 30}]]


## 시작 장비로 끼워 주는 부위 (`grant_starter_gear`)
const STARTER_SLOTS := ["weapon", "armor"]


## **새 계정의 장부** — 서버가 계정을 만들 때 쓴다. `World.join` 의 새 캐릭터 기본값과
## 같아야 한다 (`server_test` 가 둘을 대 본다). 시작 장비는 따로 `grant_starter_gear` 로 준다.
## 첫 스킬을 배운 채 시작한다 — 1레벨은 스킬 포인트가 0 이라 안 주면 아무것도 못 쓴다
static func fresh(job: String) -> Dictionary:
	var starter: Array = []
	for id in Skills.for_job(job).slice(0, 1):
		starter.append(str(id))
	return {
		"job": job, "level": 1, "exp": 0, "gold": 0,
		"skills": starter, "skill_points": 0, "passives": {},
		"skill_upgrades": {}, "skill_upgrade_exp": {}, "skill_exp": 0,
		"bag": [], "equipped": {}, "granted": [],
		"diamonds": 0,
		"proteins": {}, "fitness": {},
		"codex": {},
		# 샌드백 랭킹전 (docs/features/sandbag.md) — `{week, best, unpaid?}` 그 주 최고 기록과 못 받은 주간 보상
		"sandbag": {},
	}


## JSON 을 거친 장부를 되돌린다 — JSON 은 숫자를 전부 실수로 준다(`3` → `3.0`).
## **정수인 실수는 정수로** 바꾼다. 강화 `+3.0` 이나 `grade == 2` 비교가 어긋나지 않게.
## 서버가 계정 파일을 읽을 때, 기기가 서버 답을 받을 때 쓴다
static func from_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if value == floorf(value) and absf(value) < 9.0e15 else value
		TYPE_ARRAY:
			var list: Array = []
			for each in value:
				list.append(from_json(each))
			return list
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[key] = from_json(value[key])
			return out
	return value


## 장부 칸만 **복사해** 떼어 낸다 — 서버가 기기에 내려보내는 것. 복사라서 나중에 장부가
## 바뀌어도 이미 보낸(남겨 둔) 답은 그대로다
static func view(p: Dictionary) -> Dictionary:
	var out := {}
	for key in KEYS:
		var value = p.get(key)
		out[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return out

## 드롭·옵션·강화를 굴린다. **굴리는 쪽은 언제나 판정하는 쪽이다.**
## 로컬에서는 `World._rng` 를 같이 쓴다 — 테스트가 그 씨앗으로 결과를 고정한다
var rng: RandomNumberGenerator
var events: Array = []


func _init(shared_rng: RandomNumberGenerator = null) -> void:
	rng = shared_rng if shared_rng != null else RandomNumberGenerator.new()


func take_events() -> Array:
	var out := events
	events = []
	return out


func _notice(text: String) -> void:
	events.append({"type": "notice", "text": text})


func _inventory_changed(p: Dictionary) -> void:
	events.append({"type": "inventory", "bag": p.bag, "equipped": p.equipped})


## --- 처치 보상 ---

## 몬스터를 잡았다 → 드롭·골드·경험치·레벨·전직 시험·던전 클리어. `target` 은 `{kind, zone}` —
## **던전(토벌)에서는 스킬 경험치만 준다** — 드롭·골드·크리스탈·캐릭터 경험치 없음 (2026-09-29 요청).
## **레벨·경험치·보스 여부는 여기서 표로 찾는다.** 기기가 수치를 보내면 서버가 그 값을 믿어야 한다.
## 이 처치가 정말 있었는지(스폰 명부 · 최소 처치 시간)는 드롭 판정 단계에서 본다
func kill(p: Dictionary, target: Dictionary) -> void:
	var kinds: Dictionary = GameData.load_table("monsters").get("kinds", {})
	var kind: Dictionary = kinds.get(str(target.get("kind", "")), {})
	if kind.is_empty():
		return
	target = {
		"level": int(kind.get("level", 1)), "exp_reward": float(kind.get("expReward", 0)),
		"boss": bool(kind.get("boss", false)), "zone": str(target.get("zone", "")),
	}
	if not GameData.dungeon_stage(str(target.zone)).is_empty():
		_check_dungeon_clear(p, target)
		return
	# 보상을 굴린다. **굴리는 쪽은 언제나 판정하는 쪽이다**
	# 끼운 장비의 **아이템 드랍률** 옵션 합계를 건다 (2026-10-01) — 판정하는 쪽의 장부로 센다
	var drop_bonus := float(Items.equipment_stats(p.get("equipped", {})).get("dropRate", 0.0))
	var loot := Items.roll_drop(int(target.level), str(p.job), rng, drop_bonus)
	p.gold = int(p.gold) + int(loot.gold)
	var event := {"type": "loot", "gold": loot.gold}
	if loot.has("item") and give(p, loot.item):
		event["item"] = loot.item
	# 크리스탈은 장비와 따로 떨어진다 — 가방에서는 한 칸에 겹친다
	if loot.has("crystal"):
		var crystal := {"id": Items.crystal_id(), "count": int(loot.crystal)}
		if give(p, crystal):
			event["crystal"] = int(loot.crystal)
	events.append(event)

	var gained := Combat.exp_reward(int(target.level), int(p.level), float(target.exp_reward))
	var before := int(p.level)
	var grown := Combat.apply_exp(before, int(p.exp), gained)
	p.level = grown.level
	p.exp = grown.exp
	events.append({"type": "reward", "exp": gained})
	_check_dungeon_clear(p, target)

	if grown.level > before:
		# 체력을 채우는 것은 부르는 쪽이다 — 체력은 장부가 아니다
		var per_level := int(GameData.combat().get("skillPointPerLevel", 1))
		p.skill_points = int(p.skill_points) + (grown.level - before) * per_level
		events.append({"type": "levelUp", "level": grown.level})


## 던전 보스를 잡았다 → 그 단계의 **스킬 경험치**(`skillExp` = 단계 × 1000)가 `skill_exp` 에
## 쌓인다. 잡을 때마다 받는다 (2026-09-28 요청: "던전 깨면 알아서 경험치를 습득")
func _check_dungeon_clear(p: Dictionary, target: Dictionary) -> void:
	if not bool(target.get("boss", false)):
		return
	var stage := GameData.dungeon_stage(str(target.get("zone", "")))
	var gain := int(stage.get("skillExp", 0))
	if gain <= 0:
		return
	_give_proteins(p, Fitness.dungeon_reward(stage))
	p.skill_exp = int(p.get("skill_exp", 0)) + gain
	events.append({"type": "skillExp", "gain": gain, "total": p.skill_exp})
	# 보이는 스킬이 없으면 경험치는 말없이 쌓는다 (2026-09-29 요청: "던전의 스킬 경험치 숨김")
	if Skills.actives_shown(str(p.job)):
		_notice("던전 %d단계 클리어! 스킬 경험치 +%d" % [int(stage.stage), gain])
	else:
		_notice("던전 %d단계 클리어! 프로틴 +%d" % [int(stage.stage), int(stage.get("protein", 0))])


## 시련의 탑을 통과했다 → 그 단계의 **크리스탈**(`crystals` = 단계 × 1)을 준다.
## 시간 안에 몇 마리를 잡았는지는 부르는 쪽이 봤다 — 기기는 `World._trial`, 서버는
## `LedgerServer._check_trial` 이 제 명단으로 다시 센다 (docs/features/dungeons.md "시련의 탑")
func trial_clear(p: Dictionary, zone_id: String) -> void:
	var stage := GameData.dungeon_stage(zone_id)
	var count := int(stage.get("crystals", 0))
	if int(stage.get("kills", 0)) <= 0 or count <= 0:
		return
	if not give(p, {"id": Items.crystal_id(), "count": count}):
		_notice("가방이 가득 차 크리스탈을 받지 못했습니다")
		return
	events.append({"type": "trialReward", "stage": int(stage.stage), "crystal": count})


## --- 샌드백 랭킹전 (docs/features/sandbag.md) ---
##
## 장부에 남는 것은 `sandbag = {week, best, unpaid?}` 하나다 — **그 주의 최고 기록**과, 주가 바뀌어
## 정산됐는데 가방이 꽉 차 못 받은 보상 `{week, rank, best, crystals}`.
## 순위는 장부가 모른다 — 로컬은 혼자라 1위(`World`), 서버는 모든 계정을 줄 세워 넘겨준다(`LedgerServer`)

## 지금 몇째 주인가 — 판정하는 쪽의 시계. 테스트는 바꿔 끼워 주를 넘긴다
var unix_now: Callable = func() -> float: return Time.get_unix_time_from_system()


func sandbag_week() -> int:
	return Sandbag.week(float(unix_now.call()))


## 이번 판의 기록을 남긴다 — 그 주 최고보다 높으면 갈아 끼운다. 주가 지났으면 **정산을 먼저 해야 한다**
## (부르는 쪽 몫 — 여기서 지난 기록을 버리면 보상이 사라진다). 지난 기록이 0 이면 그냥 새 주로 넘긴다
func sandbag_record(p: Dictionary, damage: int) -> void:
	var now := sandbag_week()
	var mine: Dictionary = p.get("sandbag", {})
	if int(mine.get("week", -1)) != now:
		var unpaid: Variant = mine.get("unpaid")
		mine = {"week": now, "best": 0}
		if unpaid != null:
			mine["unpaid"] = unpaid
	var best := int(mine.get("best", 0))
	var new_best := damage > best
	if new_best:
		mine["best"] = damage
	p.sandbag = mine
	events.append({
		"type": "sandbagRecord", "damage": damage, "best": int(mine.best), "new_best": new_best, "week": now,
	})


## 지난주 기록을 닫는다 — `rank` 위 보상을 `unpaid` 에 얹고 새 주로 넘긴 뒤 바로 지급해 본다.
## 그 주에 기록이 없거나(0) 이미 이번 주면 아무것도 안 한다
func sandbag_close_week(p: Dictionary, rank: int) -> void:
	var mine: Dictionary = p.get("sandbag", {})
	var now := sandbag_week()
	if mine.is_empty() or int(mine.get("week", now)) >= now:
		return
	var closed := {"week": now, "best": 0}
	if int(mine.get("best", 0)) > 0 and rank > 0:
		closed["unpaid"] = {
			"week": int(mine.week), "rank": rank, "best": int(mine.best), "crystals": Sandbag.reward(rank),
		}
	elif mine.has("unpaid"):
		closed["unpaid"] = mine.unpaid  # 더 오래된 못 받은 것이 남아 있으면 지킨다
	p.sandbag = closed
	sandbag_pay(p)


## 못 받은 주간 보상을 가방에 넣는다 — 가방이 꽉 차 안 들어가면 그대로 두고 다음에 또 해 본다
func sandbag_pay(p: Dictionary) -> void:
	var mine: Dictionary = p.get("sandbag", {})
	var unpaid: Dictionary = mine.get("unpaid", {})
	if unpaid.is_empty():
		return
	var count := int(unpaid.get("crystals", 0))
	if count > 0 and not give(p, {"id": Items.yellow_crystal_id(), "count": count}):
		_notice("가방이 가득 차 샌드백 랭킹전 보상을 받지 못했습니다")
		return
	mine.erase("unpaid")
	p.sandbag = mine
	_inventory_changed(p)
	events.append({
		"type": "sandbagReward", "week": int(unpaid.get("week", 0)), "rank": int(unpaid.get("rank", 0)),
		"best": int(unpaid.get("best", 0)), "crystals": count,
	})


## --- 헬스 (docs/features/fitness.md) ---

## 프로틴을 넣는다 — `{프로틴 id: 개수}`. 가방이 아니라 장부의 수치라 가득 찰 일이 없다
func _give_proteins(p: Dictionary, gains: Dictionary) -> void:
	if gains.is_empty():
		return
	var have: Dictionary = p.get("proteins", {})
	for id in gains:
		have[str(id)] = int(have.get(str(id), 0)) + int(gains[id])
	p.proteins = have
	events.append({"type": "protein", "gain": gains, "total": have.duplicate()})


## 헬스 창의 **강화**(`auto` 0) · **자동**(`auto` 1) — 그 운동의 다음 단계를 확률로 두드린다
## (2026-09-30 요청: "강화 할 때 확률에 따라 강화"). 한 번마다 그 단계의 프로틴이 들고,
## **실패해도 단계는 안 내려간다.** 자동은 성공하거나 프로틴이 모자랄 때까지 되풀이한다.
## **굴리는 쪽은 판정하는 쪽이다** — 서버에서는 서버가 굴린다
func fitness_up(p: Dictionary, kind_id: String, auto: int = 0) -> void:
	var kind := Fitness.kind(kind_id)
	if kind.is_empty():
		return
	var stages: Dictionary = p.get("fitness", {})
	var have: Dictionary = p.get("proteins", {})
	var protein := str(kind.protein)
	var stage := int(stages.get(kind_id, 0))
	if stage >= Fitness.max_stage():
		_notice("%s는 이미 끝 단계입니다" % str(kind.name))
		return
	var step := Fitness.step(stage + 1)
	var cost := int(step.cost)
	if int(have.get(protein, 0)) < cost:
		_notice("%s이 %d개 모자랍니다" % [str(kind.proteinName), cost - int(have.get(protein, 0))])
		return
	var tries := 0
	var success := false
	while int(have.get(protein, 0)) >= cost:
		have[protein] = int(have[protein]) - cost
		tries += 1
		if rng.randf() * 100.0 < float(step.chance):
			success = true
			break
		if auto == 0:
			break
	if success:
		stage += 1
		stages[kind_id] = stage
	p.fitness = stages
	p.proteins = have
	events.append({
		"type": "fitnessResult", "kind": kind_id, "result": "success" if success else "fail",
		"stage": stage, "tries": tries, "spent": tries * cost,
	})
	if success:
		_notice("%s %d단계 성공! %s +%d%%" % [str(kind.name), stage, str(kind.statName), int(Fitness.bonus(stage))])
	elif tries > 1:
		_notice("%s %d번 두드렸지만 실패 — %s이 모자랍니다" % [str(kind.name), tries, str(kind.proteinName)])
	else:
		_notice("%s %d단계 실패" % [str(kind.name), stage + 1])


## --- 장비 도감 (docs/features/codex.md) ---

## 도감 창의 **등록** — 가방에서 `item_id`(등급·부위) +`enhance` 장비 **하나를 넣어(소모)** 그 칸을 채운다
## (2026-10-01 요청: "각 등급 0강부터 9강까지 등록할 수 있는 도감"). **끼고 있는 것은 안 받는다** —
## 가방만 뒤진다. `index` 는 도감 창에서 **고른 가방 번호** — 그 칸이 이 등급·부위·강화가 맞는지 다시 본다
## (2026-10-01 요청 "등록할 때 어떤 아이템 넣을건지 선택하는 UI"). -1 이면 같은 장비 중
## **옵션 줄(1·2·3차 합)이 가장 적은 것**을 넣는다 (좋은 것을 남긴다). 겹친 칸이면 하나만 뗀다
func codex_register(p: Dictionary, item_id: String, enhance: int, index: int = -1) -> void:
	var item := Items.get_item(item_id)
	if item.is_empty() or enhance < 0 or enhance > Codex.max_enhance():
		return
	var codex: Dictionary = p.get("codex", {})
	var label := "%s +%d" % [str(item.name), enhance]
	if Codex.has(codex, item_id, enhance):
		_notice("%s 은 이미 도감에 있습니다" % label)
		return
	var pick := -1
	if index >= 0:
		# 고른 칸 — 그사이 가방이 바뀌어 다른 것이 서 있으면 넣지 않는다
		if index < p.bag.size() and str(p.bag[index].get("id", "")) == item_id \
				and int(p.bag[index].get("enhance", 0)) == enhance:
			pick = index
		else:
			_notice("고른 %s 이 가방에 없습니다" % label)
			return
	for at in p.bag.size() if index < 0 else 0:
		var stack: Dictionary = p.bag[at]
		if str(stack.get("id", "")) != item_id or int(stack.get("enhance", 0)) != enhance:
			continue
		if pick < 0 or Items.option_lines(stack) < Items.option_lines(p.bag[pick]):
			pick = at
	if pick < 0:
		_notice("가방에 %s 이 없습니다" % label)
		return
	var count := int(p.bag[pick].get("count", 1))
	if count > 1:
		p.bag[pick].count = count - 1
	else:
		p.bag.remove_at(pick)
	codex[item_id] = int(codex.get(item_id, 0)) | (1 << enhance)
	p.codex = codex
	var stat := Codex.slot_stat(str(item.slot))
	var gain := Codex.cell_value(int(item.grade), enhance)
	events.append({
		"type": "codexResult", "id": item_id, "enhance": enhance, "stat": stat, "gain": gain,
	})
	_notice("도감 등록 — %s · %s +%s%%" % [label, Codex.stat_name(stat), String.num(gain, 2)])
	_inventory_changed(p)


## --- 유료 재화 (docs/features/server.md "유료 재화") ---

## 다이아를 넣는다. **서버가 결제 영수증을 확인한 뒤에만 부른다** (`LedgerServer._finish_purchase`) —
## 기기가 부를 수 있는 요청(`LedgerServer.OPS`)에는 없다
func credit_diamonds(p: Dictionary, amount: int, product: String) -> void:
	if amount <= 0:
		return
	p.diamonds = int(p.get("diamonds", 0)) + amount
	events.append({"type": "diamonds", "gain": amount, "total": p.diamonds, "product": product})
	_notice("다이아 %d개를 받았습니다" % amount)


## --- 스킬 ---

## 스킬을 배운다. **직업·레벨·포인트를 여기서 다시 본다.**
func learn_skill(p: Dictionary, skill_id: String) -> void:
	var skill := Skills.get_skill(str(p.job), skill_id)
	if skill.is_empty():
		_notice("쓸 수 없는 스킬입니다")
		return
	if skill_id in p.skills:
		return
	if not Skills.can_learn(skill, str(p.job), int(p.level)):
		_notice("%d레벨에 배웁니다" % int(skill.get("reqLevel", 1)))
		return
	var cost := Skills.point_cost()
	if int(p.skill_points) < cost:
		_notice("스킬 포인트가 모자랍니다")
		return

	p.skill_points = int(p.skill_points) - cost
	p.skills.append(skill_id)
	events.append({"type": "skills", "learned": p.skills.duplicate()})


## 패시브 한 단계를 배운다 (docs/features/passives.md). **직업·레벨·끝 단계를 여기서 다시 본다.**
## 값은 없다 — 레벨이 되면 공짜다 (2026-09-29 요청: "레벨 되면 공짜로 배울 수 있지만 습득 버튼을
## 만들어서 배우게"). 한 번에 한 단계만 오른다
func learn_passive(p: Dictionary, passive_id: String) -> void:
	var passive := Skills.passive(passive_id)
	if passive.is_empty() or str(passive.get("job", "")) != str(p.job):
		_notice("배울 수 없는 패시브입니다")
		return
	var ranks: Dictionary = p.get("passives", {})
	var rank := int(ranks.get(passive_id, 0))
	if rank >= int(passive.maxRank):
		_notice("%s 을(를) 끝까지 배웠습니다" % str(passive.name))
		return
	if rank >= Skills.passive_open(passive, int(p.level)):
		_notice("%d레벨에 배웁니다" % ((rank + 1) * int(passive.everyLevels)))
		return
	if not Skills.passive_ready(passive, ranks):
		_notice("%s 을(를) 먼저 습득해야 합니다" % str(Skills.passive(str(passive.requires)).name))
		return
	ranks[passive_id] = rank + 1
	p.passives = ranks
	events.append({"type": "passives", "passives": ranks.duplicate()})
	_notice("%s 습득 — %s" % [Skills.passive_title(passive, rank + 1), Skills.passive_effect(passive, 1)])


## 스킬창에서 **고른 강화에 모아 둔 스킬 경험치(`skill_exp`)를 넣는다** — 그 스킬의
## `slot` 번째(0 부터) 강화에 **모자란 만큼만** 들어가고(남으면 그대로 남는다), 필요
## 경험치(`exp`)에 닿으면 강화가 붙는다 (2026-09-28 에 경험치북 대신 던전 경험치로)
func feed_upgrade(p: Dictionary, skill_id: String, slot: int) -> void:
	var skill := Skills.get_skill(str(p.job), skill_id)
	var list := Skills.upgrades_of(skill_id)
	if skill.is_empty() or slot < 0 or slot >= list.size():
		return
	var upgrade: Dictionary = list[slot]
	if str(upgrade.id) in p.skill_upgrades.get(skill_id, []):
		_notice("이미 강화했습니다 — %s %s" % [skill.name, upgrade.name])
		return
	var pool := int(p.get("skill_exp", 0))
	if pool <= 0:
		_notice("스킬 경험치가 없습니다 — 던전을 깨면 얻습니다")
		return

	var need := int(upgrade.get("exp", 1))
	var progress: Dictionary = p.skill_upgrade_exp.get_or_add(skill_id, {})
	var have := int(progress.get(str(upgrade.id), 0))
	var gain := mini(pool, need - have)
	p.skill_exp = pool - gain
	var now_exp := have + gain
	if now_exp >= need:
		add_upgrade(p, skill_id, str(upgrade.id))
		_notice("%s 강화 완료 — %s" % [skill.name, upgrade.name])
	else:
		progress[str(upgrade.id)] = now_exp
		_notice("%s %s 경험치 %d / %d" % [skill.name, upgrade.name, now_exp, need])
	events.append({"type": "skillExp", "gain": -gain, "total": p.skill_exp})


func add_upgrade(p: Dictionary, skill_id: String, upgrade_id: String) -> void:
	var have: Array = p.skill_upgrades.get_or_add(skill_id, [])
	if not (upgrade_id in have):
		have.append(upgrade_id)
	var progress: Dictionary = p.skill_upgrade_exp.get(skill_id, {})
	progress.erase(upgrade_id)
	if progress.is_empty():
		p.skill_upgrade_exp.erase(skill_id)


## --- 한 번 주기 ---

func grant_once(p: Dictionary, key: String, stack: Dictionary) -> void:
	if key in p.get("granted", []):
		return
	if not give(p, stack.duplicate(true)):
		return  # 가방이 꽉 찼으면 다음 접속에 다시 준다
	p.granted.append(key)
	_inventory_changed(p)
	_notice("%s %d개를 가방에 넣었다" % [Items.stack_name(stack), int(stack.get("count", 1))])


## **시작 장비** — 일반(1등급) 무기와 갑옷을 **끼운 채로** 준다. `granted` 의 `starterGear`
## 로 한 번만. +0 이고 옵션은 드랍처럼 1등급대로 굴린다. 그 부위에 이미 낀 게 있으면 가방으로
func grant_starter_gear(p: Dictionary) -> void:
	if "starterGear" in p.get("granted", []):
		return
	for slot in STARTER_SLOTS:
		var item := Items.get_item(Items.item_id(1, slot))
		if item.is_empty():
			continue
		var stack := {
			"id": str(item.id), "grade": 1, "enhance": 0,
			"options": Items.roll_options(item, 1, rng),
		}
		if p.equipped.get(slot, {}).is_empty():
			p.equipped[slot] = stack
		elif not give(p, stack):
			return  # 가방이 꽉 찼으면 다음 접속에 다시 준다
	p.granted.append("starterGear")
	_inventory_changed(p)


## --- 가방·장비 ---

## 가방에 넣는다. 꽉 찼으면 못 넣는다
func give(p: Dictionary, stack: Dictionary) -> bool:
	# 재료는 **이미 있는 칸에 겹친다** — 크리스탈이 칸을 하나씩 먹으면 가방이 금방 찬다
	if Items.is_material(str(stack.get("id", ""))):
		for held in p.bag:
			if str(held.get("id", "")) == str(stack.id):
				held.count = int(held.get("count", 1)) + int(stack.get("count", 1))
				return true
	if p.bag.size() >= Items.bag_size():
		_notice("가방이 가득 찼습니다")
		return false
	p.bag.append(stack)
	return true


## 가방의 물건을 낀다. **낄 수 있는지 여기서 다시 본다**
func equip(p: Dictionary, index: int) -> void:
	if index < 0 or index >= p.bag.size():
		return
	var stack: Dictionary = p.bag[index]
	var item := Items.get_item(str(stack.id))
	if not Items.can_equip(item, str(p.job), int(p.level)):
		_notice("낄 수 없는 장비입니다")
		return

	var slot := str(item.slot)
	p.bag.remove_at(index)
	# 끼고 있던 것은 가방으로 돌아간다
	var before: Dictionary = p.equipped.get(slot, {})
	if not before.is_empty():
		p.bag.append(before)
	p.equipped[slot] = stack
	_inventory_changed(p)


func unequip(p: Dictionary, slot: String) -> void:
	var stack: Dictionary = p.equipped.get(slot, {})
	if stack.is_empty():
		return
	if not give(p, stack):
		return  # 가방이 꽉 찼으면 벗지 않는다 — 벗다가 잃으면 안 된다
	p.equipped.erase(slot)
	_inventory_changed(p)


## 가방을 정렬한다 — 높은 등급이 앞, 같은 등급이면 슬롯 순서(무기 → 반지),
## 그다음 강화가 높은 것. 순서만 바뀌고 물건은 그대로다
func sort_bag(p: Dictionary) -> void:
	var order: Array = Items.slots()
	p.bag.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# 재료는 장비 뒤로 — 장비끼리의 순서를 흐트러뜨리지 않는다
		var ma := Items.is_material(str(a.get("id", "")))
		var mb := Items.is_material(str(b.get("id", "")))
		if ma != mb:
			return mb
		if int(a.get("grade", 1)) != int(b.get("grade", 1)):
			return int(a.get("grade", 1)) > int(b.get("grade", 1))
		var sa := order.find(str(Items.get_item(str(a.get("id", ""))).get("slot", "")))
		var sb := order.find(str(Items.get_item(str(b.get("id", ""))).get("slot", "")))
		if sa != sb:
			return sa < sb
		if int(a.get("enhance", 0)) != int(b.get("enhance", 0)):
			return int(a.get("enhance", 0)) > int(b.get("enhance", 0))
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	_inventory_changed(p)


## --- 자동 장착 --- (docs/features/inventory-equipment.md "자동 장착")

## 가방과 낀 것 가운데 **부위마다 전투력(`gear_power`)이 가장 높아지는 것**을 낀다 (2026-10-02 요청).
## 옵션이 축을 넘나들어(목걸이에 체력 옵션 …) 한 부위를 바꾸면 다른 부위의 셈이 흔들리니,
## 바뀌는 것이 없을 때까지 몇 바퀴 돈다. **더 좋아질 때만 바꾼다** — 같으면 낀 것을 둔다.
## 착용 레벨이 모자란 것은 후보에서 빠진다. 벗은 것은 가방으로 돌아가고 가방을 정렬한다
func auto_equip(p: Dictionary) -> void:
	var worn: Dictionary = p.equipped.duplicate()
	var picks := {}  # 슬롯 → 고른 가방 번호 (-1 = 원래 끼고 있던 것)
	var job := str(p.job)
	var level := int(p.level)
	for _round in 3:
		var changed := false
		for slot in Items.slots():
			var best := gear_power(p, worn)
			# 원래 끼고 있던 것도 후보다 — 다른 부위가 바뀐 뒤 다시 나을 수 있다
			var candidates: Array = []
			if not p.equipped.get(slot, {}).is_empty():
				candidates.append(-1)
			for index in p.bag.size():
				var item := Items.get_item(str(p.bag[index].get("id", "")))
				if str(item.get("slot", "")) == slot and Items.can_equip(item, job, level):
					candidates.append(index)
			for index in candidates:
				var trial := worn.duplicate()
				trial[slot] = p.equipped[slot] if index < 0 else p.bag[index]
				var power := gear_power(p, trial)
				if power > best:
					best = power
					worn = trial
					picks[slot] = index
					changed = true
		if not changed:
			break

	var swaps := {}  # 슬롯 → 새로 낄 묶음
	var taken: Array = []
	for slot in picks:
		if int(picks[slot]) >= 0:
			swaps[slot] = p.bag[int(picks[slot])]
			taken.append(int(picks[slot]))
	if swaps.is_empty():
		_notice("이미 가장 좋은 장비를 끼고 있습니다")
		return
	# 번호가 밀리지 않게 뒤에서부터 뺀다. 빼는 수 ≥ 돌려놓는 수라 가방이 넘치지 않는다
	taken.sort()
	taken.reverse()
	for index in taken:
		p.bag.remove_at(index)
	for slot in swaps:
		var before: Dictionary = p.equipped.get(slot, {})
		if not before.is_empty():
			p.bag.append(before)
		p.equipped[slot] = swaps[slot]
	_notice("자동 장착 — %d부위를 바꿨습니다" % swaps.size())
	sort_bag(p)  # 벗은 것이 끝에 붙는다 — 창을 열 때처럼 정렬해 둔다 (`_inventory_changed` 도 여기서)


## 자동 장착이 견주는 값 — **공격 기대값 × 유효 체력** (같은 레벨 몬스터 기준).
## 공격 = 공격력 × (1 + 치확(100% 에서 자름) × 치피) × 관통이 몬스터 방어(감소 50%)를 뚫는 몫 `2 / (2 − 관통)`,
## 유효 체력 = 체력 ÷ 받는 피해 비율 `K / (K + 방어)` (`Stats.def_k_of`).
## **곱한다** — 더하면 축마다 무게를 따로 정해야 하고, 곱이면 어느 축이 몇 % 오르든 같은 무게다.
## 쿨타임 감소·드랍률은 전투력에 안 넣는다(격투가는 스킬이 없고, 드랍률은 싸움이 아니다)
static func gear_power(p: Dictionary, equipped: Dictionary) -> float:
	var s := World.stats_of(
		str(p.job), int(p.level), equipped, p.get("passives", {}), p.get("fitness", {}), p.get("codex", {})
	)
	var hit := float(s.attack) * (1.0 + clampf(float(s.crit), 0.0, 1.0) * float(s.critDamage))
	hit *= 2.0 / (2.0 - clampf(float(s.penetration), 0.0, 0.9))
	var k := Stats.def_k_of(int(p.level))
	return hit * float(s.maxHp) * (k + maxf(float(s.defense), 0.0)) / k


## --- 크리스탈 ---

## 크리스탈로 **2차 옵션을 통째로 다시 굴린다** (2026-09-23). 처음 쓰면 붙고, 다시 쓰면
## 바뀐다. 가방(`where = "bag"`, `key` = 가방 번호)과 끼고 있는 것(`"equip"`, `key` = 슬롯)
## 둘 다 된다 — 끼고 있는 걸 벗어야 굴릴 수 있으면 번거롭기만 하다. NPC 가 필요 없다
## `tier` — 2 = 크리스탈(2차), 3 = 옐로우 크리스탈(3차). 차수의 재료는 표(`optionTiers.material`)가 정한다
func use_crystal(p: Dictionary, where: String, key: Variant, tier: int = 2) -> void:
	var material := Items.tier_material(tier)
	if material == "":
		return  # 재료로 붙는 차수가 아니다 (1차는 드랍)
	var target: Dictionary = {}
	if where == "equip":
		target = p.equipped.get(str(key), {})
	elif where == "bag" and int(key) >= 0 and int(key) < p.bag.size():
		target = p.bag[int(key)]
	var item := Items.get_item(str(target.get("id", "")))
	if item.is_empty():
		return  # 장비에만 붙는다

	var crystal := -1
	for index in p.bag.size():
		if str(p.bag[index].get("id", "")) == material:
			crystal = index
			break
	if crystal < 0:
		_notice("%s이 없습니다" % str(Items.get_material(material).get("name", "크리스탈")))
		return

	# 먼저 굴리고 나서 크리스탈을 뺀다 — 빼다가 칸이 비면 가방 번호가 당겨진다
	var slot_key := str(Items.option_tier(tier).get("key", "options2"))
	target[slot_key] = Items.roll_tier_options(tier, int(target.get("grade", 1)), rng)
	var left := int(p.bag[crystal].get("count", 1)) - 1
	if left > 0:
		p.bag[crystal].count = left
	else:
		p.bag.remove_at(crystal)

	var lines: Array = []
	for option in target[slot_key]:
		lines.append(Items.describe_option(option))
	_notice("%s %d차 옵션 — %s" % [item.name, tier, ", ".join(lines)])
	_inventory_changed(p)


## --- 상점 --- (NPC 곁인지는 부르는 쪽이 본다)

## 산다. **파는 목록에 있는 것만** — 화면이 보낸 id 를 믿지 않는다
func buy(p: Dictionary, item_id: String) -> void:
	if not (item_id in Items.shop_stock(str(p.job), int(p.level))):
		return
	var item := Items.get_item(item_id)
	if item.is_empty():
		return

	var price := int(item.price)
	if int(p.gold) < price:
		_notice("골드가 %d 모자랍니다" % (price - int(p.gold)))
		return
	if p.bag.size() >= Items.bag_size():
		_notice("가방이 가득 찼습니다")
		return

	p.gold = int(p.gold) - price
	# 옵션은 **판정하는 쪽이 굴린다.** 물건이 생기는 자리마다 굴려야 빠지는 곳이 없다
	p.bag.append({
		"id": item_id, "grade": 1, "enhance": 0, "options": Items.roll_options(item, 1, rng)
	})
	_notice("%s 구입 — %d G" % [item.name, price])
	_inventory_changed(p)


func sell(p: Dictionary, index: int) -> void:
	if index < 0 or index >= p.bag.size():
		return
	var stack: Dictionary = p.bag[index]
	var item := Items.get_item(str(stack.id))
	if item.is_empty():
		return

	var price := Items.sell_price(item, int(stack.get("grade", 1)))
	p.bag.remove_at(index)
	p.gold = int(p.gold) + price
	_notice("%s 판매 — %d G" % [item.name, price])
	_inventory_changed(p)


## --- 강화 ---

## +level 에서 한 번 굴린다. 비용을 떼고 "success" · "keep" · "destroy", 모자라면 "short"
func _roll_once(p: Dictionary, item: Dictionary, level: int) -> String:
	var cost := Items.enhance_cost(item, level)
	if int(p.gold) < cost:
		return "short"
	p.gold = int(p.gold) - cost
	return Items.roll_enhance(level, rng.randf())


## 한 번 두드린다. where 는 "bag"(가방 번호) · "equip"(슬롯 이름). 확률은 설계표(90% → 10%),
## 실패하면 무조건 파괴다 → docs/features/stat-balance.md 4장. **한 요청 = 한 번.**
## **겹친 칸이면 한 개만 떼어서** 두드린다 — 통째로 두드리면 파괴 한 번에
## 여러 개가 사라지고, 성공 한 번에 여러 개가 오른다. 뗀 것은 성공하면 원래 칸 바로 뒤에 선다
func enhance(p: Dictionary, where: String, key: Variant) -> void:
	var stack: Dictionary = {}
	if where == "equip":
		stack = p.equipped.get(str(key), {})
	elif where == "bag" and int(key) >= 0 and int(key) < p.bag.size():
		stack = p.bag[int(key)]
	var item := Items.get_item(str(stack.get("id", "")))
	if item.is_empty():
		return  # 장비만 두드린다

	var level := int(stack.get("enhance", 0))
	if not Items.can_enhance(level):
		_notice("더 두드릴 수 없습니다")
		return
	var result := _roll_once(p, item, level)
	if result == "short":
		_notice("골드가 %d 모자랍니다" % (Items.enhance_cost(item, level) - int(p.gold)))
		return

	var count := int(stack.get("count", 1)) if where == "bag" else 1  # 끼운 것은 늘 하나
	match result:
		"success":
			if count > 1:
				stack.count = count - 1
				var one := stack.duplicate(true)
				one.erase("count")
				one.enhance = level + 1
				p.bag.insert(int(key) + 1, one)
			else:
				stack.enhance = level + 1
			_notice("%s +%d 성공" % [item.name, level + 1])
		"keep":
			_notice("%s +%d 유지" % [item.name, level])
		"destroy":
			if count > 1:
				stack.count = count - 1
			elif where == "equip":
				p.equipped.erase(str(key))
			else:
				p.bag.remove_at(int(key))
			_notice("%s +%d 강화 실패 — 부서졌습니다" % [item.name, level])
	var after := level + 1 if result == "success" else level
	events.append({
		"type": "enhanceResult", "result": result, "level": after, "from": level, "name": str(item.name),
	})
	_inventory_changed(p)


## 다중 강화 — 가방에서 **고른 칸들**(`indices`, 가방 번호)을 **한 개씩 한 번** 두드린다
## (2026-09-24 요청: 리니지M "다중 강화" 그림 — 오른쪽 목록에서 골라 왼쪽 칸에 담는다).
## `cap` 을 주면 +cap 아래인 칸만 든다 — 팝업은 목표를 cap 으로 넣어 한 바퀴씩 되풀이한다.
## 끼고 있는 것은 고를 수 없다 (가방 번호만 받는다) — 한 번에 여럿을 부수는 요청이 몸에 걸친
## 것까지 걸면 되돌릴 수 없다. 겹친 칸은 한 개씩 따로 굴리고, 남은 것은 **끝난 단계끼리 다시
## 겹쳐** 원래 자리에 선다. 가방 번호가 흔들리므로 **남은 칸의 새 번호(`picked`)** 를 돌려준다 —
## 팝업은 그것으로 담은 칸을 이어 간다
func enhance_many(p: Dictionary, indices: Array, cap: int = -1) -> void:
	var limit := clampi(cap, 1, Items.max_enhance()) if cap > 0 else Items.max_enhance()
	# 목표에 이미 닿은 칸도 받는다 — 두드리지는 않고 **새 번호만 따라가게** 한다
	# (팝업은 칸 자리를 그대로 두고 칸마다 연출한다)
	var chosen: Array = []
	var live := 0
	for value in indices:
		var at := int(value)
		if at < 0 or at >= p.bag.size() or chosen.has(at):
			continue
		var stack: Dictionary = p.bag[at]
		if Items.get_item(str(stack.get("id", ""))).is_empty():
			continue
		chosen.append(at)
		if int(stack.get("enhance", 0)) < limit:
			live += 1
	if live == 0:
		_notice("강화할 장비가 없습니다")
		return
	chosen.sort()
	chosen.reverse()  # 뒤에서부터 — 앞 칸 번호가 안 밀린다
	var total := {"pieces": 0, "success": 0, "destroyed": 0}
	var reached := {}  # 끝난 단계 → 남은 개수
	# 칸마다 {at: 원래 번호, from, to: [새 번호], success, destroyed} — 팝업이 칸별로 연출한다
	var results: Array = []
	for i in chosen:
		var stack: Dictionary = p.bag[i]
		var item := Items.get_item(str(stack.id))
		var start := int(stack.get("enhance", 0))
		var entry := {"at": i, "from": start, "to": [i], "success": 0, "destroyed": 0}
		if start >= limit:
			results.append(entry)
			continue
		var kept := {}
		for n in int(stack.get("count", 1)):
			var result := _roll_once(p, item, start)
			if result == "short":
				kept[start] = int(kept.get(start, 0)) + 1
				continue
			total.pieces += 1
			if result == "destroy":
				total.destroyed += 1
				entry.destroyed += 1
				continue
			var at := start + 1 if result == "success" else start
			if result == "success":
				total.success += 1
				entry.success += 1
			kept[at] = int(kept.get(at, 0)) + 1
		p.bag.remove_at(i)
		var levels := kept.keys()
		levels.sort()
		levels.reverse()  # 같은 자리에 높은 것부터 끼우면 낮은 것이 앞에 선다
		for at in levels:
			var one := stack.duplicate(true)
			one.enhance = int(at)
			one.erase("count")
			if int(kept[at]) > 1:
				one.count = int(kept[at])
			p.bag.insert(i, one)
			reached[int(at)] = int(reached.get(int(at), 0)) + int(kept[at])
		# 먼저 적은 번호(i 뒤)는 한 칸이 levels.size() 칸이 된 만큼 밀린다
		var grow := levels.size() - 1
		for done in results:
			done.to = (done.to as Array).map(func(v: int) -> int: return v + grow)
		entry.to = range(i, i + levels.size())
		results.append(entry)
	var picked: Array = []  # 남은 칸의 새 가방 번호
	for done in results:
		picked.append_array(done.to)
	picked.sort()
	_notice("다중 강화 %d개 — 성공 %d · 파괴 %d" % [total.pieces, total.success, total.destroyed])
	events.append({
		"type": "enhanceBatch", "cap": limit, "picked": picked, "results": results,
		"pieces": total.pieces, "success": total.success, "destroyed": total.destroyed,
		"reached": reached,
	})
	_inventory_changed(p)
