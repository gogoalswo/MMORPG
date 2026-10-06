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
	"diamonds", "proteins", "fitness", "codex", "sandbag", "dungeon_entries", "loot_slots", "loot_options",
	"codex_auto", "codex_auto_options", "codex_new",
	# PT 트레이너 (docs/features/trainers.md) — `{ id: 개수 }` · 동행 id
	"trainers", "trainer_active",
	# 옛 습득 칸(전 등급 공통 끄기) — 읽어서 `loot_slots` · `loot_options` 로 옮긴다. 새로 정하면 지운다
	"loot_skip", "loot_skip_slots", "loot_skip_options",
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
		# 던전 하루 입장 (docs/features/dungeons.md "하루 한 번") — `{ 종류 id: {day, count} }`
		"dungeon_entries": {},
		# 주울 장비 `{ "등급": [부위, …] }` · `{ "등급": [1차 옵션 종류, …] }` — 설정 창 "아이템 → 습득"
		# (`set_loot_grade` · `set_loot_options`). 등급이 없으면 전부 줍는다 · 부위가 비면 그 등급을 끈 것.
		# 새 계정은 일곱 등급 다 전부 — 기기의 join 과 같은 모양이어야 한다(server_test)
		"loot_slots": loot_slots({}),
		"loot_options": loot_options({}),
		# 도감 자동 등록 `{ "등급": [넣을 부위, …] }` — 도감 창 "자동 등록 설정" (`set_codex_auto_grade`).
		# 등급이 없으면 그 등급은 끔. 비어 있으면 다 끔
		"codex_auto": {},
		# 자동 등록할 1차 옵션 `{ "등급": [종류, …] }` — 그 등급에서 **이 옵션이 붙은 장비만** 넣는다
		# (`set_codex_auto_options`). 등급이 없으면 전 옵션
		"codex_auto_options": {},
		# 자동 등록으로 새로 찬 칸 `{ 아이템 id: 강화 비트 }` — 도감 빨간 점. 그 탭을 보고 나오면 지운다(`codex_seen`)
		"codex_new": {},
		# PT 트레이너 `{ id: 뽑은 개수 }` · 동행 id ("" 이면 없음) — 상점 뽑기(`trainer_draw`) · 트레이너 창(`trainer_pick`)
		"trainers": {},
		"trainer_active": "",
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
	# 같은 등급 창이 이어지는 뒤 사냥터일수록 윗등급이 잘 나온다 — 종의 `dropStep` (items.gd `drop_weights`)
	var loot := Items.roll_drop(int(target.level), str(p.job), rng, drop_bonus, int(kind.get("dropStep", 0)))
	p.gold = int(p.gold) + int(loot.gold)
	var event := {"type": "loot", "gold": loot.gold}
	# 설정에서 끈 등급·부위·옵션은 **가방에 넣지 않는다** (2026-10-02 요청: "습득할 아이템도 설정할 수 있는 옵션",
	# 같은 날 "등급만 있는데, 부위와 옵션도 설정할 수 있게끔" → "도감에 자동 등록 설정 참고해서 비슷하게" — 등급마다).
	# 굴림은 그대로 다 한다 — 거른다고 굴림 순서가 바뀌면 같은 씨앗에서 다른 것이 나온다
	var got_at := -1
	if loot.has("item") and loot_wanted(p, loot.item) and give(p, loot.item):
		event["item"] = loot.item
		got_at = p.bag.size() - 1  # 장비는 늘 맨 뒤에 붙는다 — 뒤에 오는 크리스탈도 번호를 밀지 않는다
	# 크리스탈은 장비와 따로 떨어진다 — 가방에서는 한 칸에 겹친다
	if loot.has("crystal"):
		var crystal := {"id": Items.crystal_id(), "count": int(loot.crystal)}
		if give(p, crystal):
			event["crystal"] = int(loot.crystal)
	events.append(event)
	# 도감 자동 등록 — 켜 둔 등급이면 주운 그 자리에서 넣는다 (모자란 강화는 두드려 올린다).
	# 도감에 들어갔거나 두드리다 부서져 **가방에 안 남았으면** `kept: false` — 화면이 가방 빨간 점을 켜지 않는다
	# (2026-10-02 요청 "실제 인벤토리에 안 들어오면 레드닷 띄우지마"). 이벤트는 아직 안 나갔다 — 같은 사전을 고친다
	if got_at >= 0 and _codex_auto(p, got_at):
		event["kept"] = false

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
	# 토벌은 보스를 잡으면 클리어 — 오늘 입장을 쓴다 (시련의 보스는 클리어가 아니다 — `trial_clear` 가 센다)
	if int(stage.get("kills", 0)) <= 0:
		dungeon_cleared(p, str(target.get("zone", "")))
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
	# 통과가 클리어다 — 가방이 꽉 차 크리스탈을 못 받아도 깬 것은 깬 것이다
	dungeon_cleared(p, zone_id)
	if not give(p, {"id": Items.crystal_id(), "count": count}):
		_notice("가방이 가득 차 크리스탈을 받지 못했습니다")
		return
	events.append({"type": "trialReward", "stage": int(stage.stage), "crystal": count})


## --- 샌드백 랭킹전 (docs/features/sandbag.md) ---
##
## 장부에 남는 것은 `sandbag = {week, best, unpaid?, days?}` 하나다 — **그 주의 최고 기록**과, 주가 바뀌어
## 정산됐는데 가방이 꽉 차 못 받은 보상 `{week, rank, best, crystals}`, 그리고 **날짜별 최고** `[{day, best}]`
## (최근 7일 · 주가 바뀌어도 이어진다 — `Sandbag.add_day`).
## 순위는 장부가 모른다 — 로컬은 혼자라 1위(`World`), 서버는 모든 계정을 줄 세워 넘겨준다(`LedgerServer`)

## 지금 몇째 주인가 — 판정하는 쪽의 시계. 테스트는 바꿔 끼워 주를 넘긴다
var unix_now: Callable = func() -> float: return Time.get_unix_time_from_system()


func sandbag_week() -> int:
	return Sandbag.week(float(unix_now.call()))


## 오늘이 며칠째인가 — 날짜별 기록의 날 (한국 0시)
func sandbag_day() -> int:
	return Sandbag.day(float(unix_now.call()))


## --- 던전 하루 입장 --- (docs/features/dungeons.md "하루 한 번")
## 장부에 남는 것은 `dungeon_entries = { 종류 id: {day, count} }` — 마지막으로 들어간 날과 그날 들어간 수.
## 날이 바뀌면 그 칸은 저절로 0 으로 읽힌다 (지우지 않는다)

## 오늘이 며칠째인가 — 한국 시각 5시에 하나 오른다 (`dungeons.ts` 의 `dungeonDay` 와 같은 식)
func dungeon_day() -> int:
	return day_of(float(unix_now.call()))


static func day_of(unix_seconds: float) -> int:
	var t: Dictionary = GameData.zones().get("dungeonDay", {})
	return floori((unix_seconds + float(t.get("shift", 14400))) / float(t.get("seconds", 86400)))


## 오늘 이 존(던전 단계)에 몇 번 더 들어갈 수 있나. **횟수 제한이 없는 존은 -1** (사냥터 · 마을 · 샌드백)
static func dungeon_entries_left(p: Dictionary, zone_id: String, day: int) -> int:
	var type := GameData.dungeon_type_of(zone_id)
	var limit := int(type.get("daily", 0))
	if limit <= 0:
		return -1
	var mine: Dictionary = p.get("dungeon_entries", {}).get(str(type.id), {})
	var used := int(mine.get("count", 0)) if int(mine.get("day", -1)) == day else 0
	return maxi(0, limit - used)


## 던전에 들어가도 되나 — 오늘 입장이 남았으면 true, 다 썼으면 알리고 false. 제한이 없는 존은 늘 true.
## **들어갈 때는 세지 않는다** — 세는 것은 클리어할 때다(`dungeon_cleared`, 2026-10-06 요청
## "던전을 클리어 했을 때만 입장권 차감 되도록"). 쓰러지거나 시간이 다 되거나 나가면 입장은 그대로 남는다
func dungeon_enter(p: Dictionary, zone_id: String) -> bool:
	if dungeon_entries_left(p, zone_id, dungeon_day()) != 0:
		return true
	var type := GameData.dungeon_type_of(zone_id)
	_notice("%s 은(는) 오늘 이미 클리어했습니다 — 5시에 다시 열립니다" % str(type.get("name", "던전")))
	return false


## 던전을 깼다 — 오늘 입장을 하나 쓴다. 토벌은 보스 처치(`_check_dungeon_clear`), 시련은 통과(`trial_clear`).
## 제한이 없는 존은 세지 않는다
func dungeon_cleared(p: Dictionary, zone_id: String) -> void:
	var day := dungeon_day()
	if dungeon_entries_left(p, zone_id, day) < 0:
		return
	var type := GameData.dungeon_type_of(zone_id)
	if not p.has("dungeon_entries") or not p.dungeon_entries is Dictionary:
		p["dungeon_entries"] = {}
	var mine: Dictionary = p.dungeon_entries.get(str(type.id), {})
	var used := int(mine.get("count", 0)) if int(mine.get("day", -1)) == day else 0
	p.dungeon_entries[str(type.id)] = {"day": day, "count": used + 1}


## 이번 판의 기록을 남긴다 — 그 주 최고보다 높으면 갈아 끼운다. 주가 지났으면 **정산을 먼저 해야 한다**
## (부르는 쪽 몫 — 여기서 지난 기록을 버리면 보상이 사라진다). 지난 기록이 0 이면 그냥 새 주로 넘긴다
func sandbag_record(p: Dictionary, damage: int) -> void:
	var now := sandbag_week()
	var mine: Dictionary = p.get("sandbag", {})
	if int(mine.get("week", -1)) != now:
		var unpaid: Variant = mine.get("unpaid")
		var days: Variant = mine.get("days")
		mine = {"week": now, "best": 0}
		if unpaid != null:
			mine["unpaid"] = unpaid
		if days != null:
			mine["days"] = days
	mine["days"] = Sandbag.add_day(mine.get("days", []), sandbag_day(), damage)
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
	if mine.has("days"):
		closed["days"] = mine.days  # 날짜별 기록은 주를 넘어 이어진다
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
## **옵션 줄(1·2·3차 합)이 가장 적은 것**을 넣는다 (좋은 것을 남긴다). 겹친 칸이면 하나만 뗀다.
## **잠근 것은 안 넣는다** — 고른 칸이 잠겼으면 거절, -1 이면 잠근 것을 건너뛴다
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
		if Items.is_locked(p.bag[pick]):
			_notice("잠근 장비는 도감에 넣을 수 없습니다")
			return
	for at in p.bag.size() if index < 0 else 0:
		var stack: Dictionary = p.bag[at]
		if str(stack.get("id", "")) != item_id or int(stack.get("enhance", 0)) != enhance \
				or Items.is_locked(stack):
			continue
		if pick < 0 or Items.option_lines(stack) < Items.option_lines(p.bag[pick]):
			pick = at
	if pick < 0:
		_notice("가방에 %s 이 없습니다" % label)
		return
	var got := _codex_take(p, codex, pick)
	_notice("도감 등록 — %s · %s +%s%%" % [label, Codex.stat_name(str(got.stat)), String.num(float(got.gain), 2)])
	_inventory_changed(p)


## 도감 창의 **자동 등록** — 가방에서 넣을 수 있는 칸을 **등급 가리지 않고 전부** 채운다 (2026-10-02 요청
## "도감에 자동 등록 버튼 만들어"). 칸마다 하나, 같은 칸의 장비가 여럿이면 옵션 줄이 가장 적은 것
## (`Codex.auto_picks` — 확인 창이 늘어놓는 것과 같은 셈). 알림은 한 줄로 모은다
func codex_register_all(p: Dictionary) -> void:
	var codex: Dictionary = p.get("codex", {})
	var picks := Codex.auto_picks(codex, p.bag)
	if picks.is_empty():
		_notice("도감에 넣을 장비가 가방에 없습니다")
		return
	# 뒤 번호부터 뗀다 — 앞에서 떼면 뒤 번호가 밀린다
	picks.reverse()
	var gains := {}
	for at in picks:
		var got := _codex_take(p, codex, int(at))
		gains[got.stat] = float(gains.get(got.stat, 0.0)) + float(got.gain)
	var parts := PackedStringArray()
	for stat in gains:
		parts.append("%s +%s%%" % [Codex.stat_name(str(stat)), String.num(float(gains[stat]), 2)])
	_notice("도감 자동 등록 — %d칸 · %s" % [picks.size(), " · ".join(parts)])
	_inventory_changed(p)


## 가방 `at` 번 장비 하나를 떼어(겹쳤으면 개수만) 그 칸을 채우고 `codexResult` 를 낸다 → `{stat, gain}`.
## `auto` 면 주울 때 자동 등록이다 — 새로 찬 칸(`codex_new`)에 적어 빨간 점을 켠다
func _codex_take(p: Dictionary, codex: Dictionary, at: int, auto: bool = false) -> Dictionary:
	var stack: Dictionary = p.bag[at]
	var item_id := str(stack.get("id", ""))
	var enhance := int(stack.get("enhance", 0))
	var item := Items.get_item(item_id)
	var count := int(stack.get("count", 1))
	if count > 1:
		stack.count = count - 1
	else:
		p.bag.remove_at(at)
	codex[item_id] = int(codex.get(item_id, 0)) | (1 << enhance)
	p.codex = codex
	if auto:
		var marks := codex_new(p)
		marks[item_id] = int(marks.get(item_id, 0)) | (1 << enhance)
		p.codex_new = marks
	var stat := Codex.slot_stat(str(item.slot))
	var gain := Codex.cell_value(int(item.grade), enhance)
	events.append({
		"type": "codexResult", "id": item_id, "enhance": enhance, "stat": stat, "gain": gain, "auto": auto,
	})
	return {"stat": stat, "gain": gain}


## **주울 때 자동 등록** — 켜 둔 등급(`codex_auto`)의 장비를 주우면 바로 넣는다 (2026-10-02 요청: "아이템을
## 습득했는데 도감에 등록할 수 있으면 바로 등록하고, 강화 수치가 부족하면 1단계부터 쭉 강화해서 해당 단계까지
## 강화 성공하면 등록"). 노리는 칸은 **지금 강화 이상에서 가장 낮은 빈 칸**(`Codex.next_empty`) — 비었으면 그대로
## 넣고, 찼으면 그 단계까지 **한 단계씩** 두드린다. 강화와 같은 판정(`_roll_once`)이라 **실패하면 부서진다.**
## 빈 칸이 없으면 가방에 그대로 둔다. 잠근 것 · 겹친 칸은 건드리지 않는다 → codex.md "주울 때 자동 등록".
## 돌려주는 값: 그 장비가 **가방에서 빠졌나**(넣었거나 부서졌다) — 줍기의 가방 빨간 점을 끈다
func _codex_auto(p: Dictionary, at: int) -> bool:
	var stack: Dictionary = p.bag[at]
	var item_id := str(stack.get("id", ""))
	var item := Items.get_item(item_id)
	# 켠 등급의 **고른 종류(부위)만** (2026-10-02 요청 "등급마다 아이템 종류도 선택할 수 있게")
	if item.is_empty() or not (str(item.slot) in codex_auto_slots(p, int(item.grade))) or Items.is_locked(stack) \
			or int(stack.get("count", 1)) > 1:
		return false
	# 그 등급에서 고른(활성화된) 1차 옵션이 붙은 것만 넣는다 (2026-10-02 요청 "치명타 옵션이 있을 경우 등록 안 되게"
	# → "등급마다 옵션 설정할 수 있게" → "옵션도 활성화 된 옵션만 자동등록하는걸로 바꿔")
	var allowed := codex_auto_option_kinds(p, int(item.grade))
	for option in stack.get("options", []):
		if option is Dictionary and not (str(option.get("kind", "")) in allowed):
			return false
	var codex: Dictionary = p.get("codex", {})
	var level := int(stack.get("enhance", 0))
	var goal := Codex.next_empty(codex, item_id, level)
	if goal < 0:
		return false
	var tries := 0
	while level < goal:
		var result := _roll_once(p, item, level)
		if result == "short":
			break
		tries += 1
		if result == "destroy":
			p.bag.remove_at(at)
			_notice("도감 자동 강화 실패 — %s +%d 에서 부서졌습니다" % [item.name, level])
			_codex_auto_log("destroy", item, level, tries)
			_inventory_changed(p)
			return true
		if result == "success":
			level += 1
	stack.enhance = level
	if level < goal:
		_notice("도감 자동 강화 — 골드가 모자라 %s +%d 에서 멈췄습니다" % [item.name, level])
		_codex_auto_log("short", item, level, tries)
		_inventory_changed(p)
		return false
	var got := _codex_take(p, codex, at, true)
	var climbed := " (강화 %d번)" % tries if tries > 0 else ""
	_notice("도감 자동 등록 — %s +%d%s · %s +%s%%" % [
		item.name, level, climbed, Codex.stat_name(str(got.stat)), String.num(float(got.gain), 2)])
	_codex_auto_log("register", item, level, tries, got)
	_inventory_changed(p)
	return true


## 주울 때 자동 등록의 결과 — 채팅창에 남길 한 줄 (`game.gd` `codexAuto`). `notice` 는 위 한 줄만 바꾸고 사라진다
## (2026-10-02 지적 "자동 강화해서 등록하면 채팅창에 기록 안 남는거 같은데")
func _codex_auto_log(result: String, item: Dictionary, level: int, tries: int, got: Dictionary = {}) -> void:
	events.append({
		"type": "codexAuto", "result": result, "name": str(item.name), "level": level, "tries": tries,
		"stat": str(got.get("stat", "")), "gain": float(got.get("gain", 0.0)),
	})


## 도감 자동 등록 — **등급 하나**의 넣을 종류(부위) 목록을 정한다. 비면 그 등급을 끈다.
## 표에 있는 등급 · 부위만, 부위는 표 순서로 (도감 창 "자동 등록 설정" 의 등급 줄)
func set_codex_auto_grade(p: Dictionary, grade: int, slots: Array) -> void:
	if grade < 1 or grade > int(Items._t().get("gradeMax", 7)):
		return
	var table := codex_auto(p)
	var kept := clean_slots(slots)
	if kept.is_empty():
		table.erase(str(grade))
	else:
		table[str(grade)] = kept
	p.codex_auto = table


## 자동 등록할 1차 옵션 — **등급 하나**의 종류 목록을 정한다. **비어도 그대로 둔다**(그 등급은 옵션이 붙은 장비를
## 하나도 안 넣는다). 표에 있는 종류만, 겹치지 않게, 표 순서로 (도감 "자동 등록 설정" 창의 그 등급 탭)
func set_codex_auto_options(p: Dictionary, grade: int, kinds: Array) -> void:
	if grade < 1 or grade > int(Items._t().get("gradeMax", 7)):
		return
	var table := codex_auto_options(p)
	table[str(grade)] = clean_option_kinds(kinds)
	p.codex_auto_options = table
	p.erase("codex_auto_block")


## 자동 등록할 1차 옵션 표 `{ "등급": [종류, …] }` (다듬은 새 사전). **등급이 없으면 전 옵션**이다.
## 옛 칸 `codex_auto_block`(같은 날 낮 — 막을 옵션, `[종류]` 전 등급 공통 또는 `{등급: [종류]}`)만 있으면
## **전 옵션 − 막은 것**으로 읽는다
static func codex_auto_options(p: Dictionary) -> Dictionary:
	var out := {}
	var top := int(Items._t().get("gradeMax", 7))
	var raw: Variant = p.get("codex_auto_options", null)
	if raw is Dictionary:
		for key in raw:
			var grade := int(str(key)) if str(key).is_valid_int() else 0
			if grade >= 1 and grade <= top:
				out[str(grade)] = clean_option_kinds(raw[key])
		return out
	var old: Variant = p.get("codex_auto_block", {})
	var every: Array = clean_option_kinds(Items._t().get("optionKinds", []))
	for grade in range(1, top + 1):
		var blocked: Array = []
		if old is Array:
			blocked = clean_option_kinds(old)
		elif old is Dictionary:
			blocked = clean_option_kinds(old.get(str(grade), []))
		if not blocked.is_empty():
			out[str(grade)] = every.filter(func(kind: String) -> bool: return not (kind in blocked))
	return out


## 그 등급에서 자동 등록할 1차 옵션 종류 — 정하지 않았으면 전 옵션
static func codex_auto_option_kinds(p: Dictionary, grade: int) -> Array:
	return codex_auto_options(p).get(str(grade), clean_option_kinds(Items._t().get("optionKinds", [])))


static func clean_option_kinds(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	var asked: Array = raw.map(func(each: Variant) -> String: return str(each))
	for kind in Items._t().get("optionKinds", []):
		if str(kind) in asked:
			out.append(str(kind))
	return out


## 자동 등록 표 `{ "등급": [부위, …] }` (다듬은 새 사전) — 옛 계정·옛 저장에는 칸이 없다(빈 사전 = 다 끔)
static func codex_auto(p: Dictionary) -> Dictionary:
	return clean_codex_auto(p.get("codex_auto", {}))


## 그 등급에서 자동 등록할 부위 — 끈 등급이면 빈 목록
static func codex_auto_slots(p: Dictionary, grade: int) -> Array:
	return codex_auto(p).get(str(grade), [])


## 자동 등록 표를 다듬는다. **옛 모양(켠 등급 목록 `[3, 5]`, 2026-10-02 첫 판)은 그 등급의 전 부위**로 읽는다
static func clean_codex_auto(raw: Variant) -> Dictionary:
	var out := {}
	if raw is Array:
		for grade in clean_grades(raw):
			out[str(grade)] = Items.slots().duplicate()
		return out
	if not raw is Dictionary:
		return out
	var top := int(Items._t().get("gradeMax", 7))
	for key in raw:
		var grade := int(str(key)) if str(key).is_valid_int() else 0
		var slots := clean_slots(raw[key])
		if grade >= 1 and grade <= top and not slots.is_empty():
			out[str(grade)] = slots
	return out


## 표에 있는 부위만, 겹치지 않게, 표 순서로
static func clean_slots(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	var asked: Array = raw.map(func(each: Variant) -> String: return str(each))
	for slot in Items.slots():
		if str(slot) in asked:
			out.append(str(slot))
	return out


## 자동 등록으로 새로 찬 칸 `{ 아이템 id: 강화 비트 }` — 도감 빨간 점 (옛 장부는 빈 사전)
static func codex_new(p: Dictionary) -> Dictionary:
	var raw: Variant = p.get("codex_new", {})
	return raw if raw is Dictionary else {}


## 도감 창에서 그 등급 탭을 보고 나왔다 — 그 등급의 새 칸 표시(빨간 점)를 지운다. 0 이면 전부
func codex_seen(p: Dictionary, grade: int) -> void:
	var marks := codex_new(p)
	for id in marks.keys():
		if grade == 0 or int(Items.get_item(str(id)).get("grade", 0)) == grade:
			marks.erase(id)
	p.codex_new = marks


## --- 유료 재화 (docs/features/server.md "유료 재화") ---

## 다이아를 넣는다. **서버가 결제 영수증을 확인한 뒤에만 부른다** (`LedgerServer._finish_purchase`) —
## 기기가 부를 수 있는 요청(`LedgerServer.OPS`)에는 없다
func credit_diamonds(p: Dictionary, amount: int, product: String) -> void:
	if amount <= 0:
		return
	p.diamonds = int(p.get("diamonds", 0)) + amount
	events.append({"type": "diamonds", "gain": amount, "total": p.diamonds, "product": product})
	_notice("다이아 %d개를 받았습니다" % amount)


## --- PT 트레이너 (docs/features/trainers.md) ---

## 상점의 **트레이너 뽑기** — `times` 번(1 또는 10) 굴린다. 한 번에 다이아 `drawCost` 개.
## 모자라면 아무것도 안 한다. 같은 트레이너가 또 나오면 개수만 는다 (지금은 쓰임이 없다).
## **동행이 없으면** 이번에 나온 것 중 가장 높은 등급을 바로 데리고 다닌다 — 첫 뽑기부터 같이 싸운다
func trainer_draw(p: Dictionary, times: int) -> void:
	if times != 1 and times != Trainers.draw_multi():
		return
	var cost := Trainers.draw_cost() * times
	var have := int(p.get("diamonds", 0))
	if have < cost:
		_notice("다이아가 %d개 모자랍니다" % (cost - have))
		return
	p.diamonds = have - cost
	var owned: Dictionary = p.get("trainers", {})
	var got: Array = []
	var fresh: Array = []
	var best := ""
	for i in times:
		var id := Trainers.roll(rng)
		if id == "":
			continue
		fresh.append(int(owned.get(id, 0)) == 0)
		owned[id] = int(owned.get(id, 0)) + 1
		got.append(id)
		if best == "" or int(Trainers.trainer(id).grade) > int(Trainers.trainer(best).grade):
			best = id
	p.trainers = owned
	if str(p.get("trainer_active", "")) == "" and best != "":
		p.trainer_active = best
	events.append({"type": "trainerDraw", "got": got, "new": fresh, "diamonds": p.diamonds})


## 트레이너 창의 **동행** — 갖고 있는 트레이너만. `id` 가 "" 면 돌려보낸다
func trainer_pick(p: Dictionary, id: String) -> void:
	if id != "" and int(p.get("trainers", {}).get(id, 0)) <= 0:
		return
	p.trainer_active = id
	events.append({"type": "trainerPick", "id": id})
	if id != "":
		_notice("%s와 함께합니다" % str(Trainers.trainer(id).name))


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


## 잠금을 뒤집는다 (2026-10-02 요청). where 는 "bag"(가방 번호) · "equip"(슬롯 이름).
## 잠근 것은 판매·강화(단일·다중)·도감 등록이 거절한다. 장비만 잠근다 — 재료는 칸이 겹쳐서
## 새로 들어온 것까지 잠겨 버린다. 겹친 칸은 통째로 잠근다 (같은 물건이라 나눌 까닭이 없다)
func toggle_lock(p: Dictionary, where: String, key: Variant) -> void:
	var stack: Dictionary = {}
	if where == "equip":
		stack = p.equipped.get(str(key), {})
	elif where == "bag" and int(key) >= 0 and int(key) < p.bag.size():
		stack = p.bag[int(key)]
	var item := Items.get_item(str(stack.get("id", "")))
	if item.is_empty():
		return
	if Items.is_locked(stack):
		stack.erase("locked")
		_notice("%s 잠금 해제" % item.name)
	else:
		stack.locked = true
		_notice("%s 잠금" % item.name)
	_inventory_changed(p)


## 주울 부위 — **등급 하나**의 목록을 정한다. 비면 그 등급의 장비는 안 줍는다 (설정 창 "아이템 → 습득" 의 등급 탭.
## 도감 자동 등록 설정과 같은 모양 — 2026-10-02 요청 "도감에 자동 등록 설정 참고해서 비슷하게 만들어")
func set_loot_grade(p: Dictionary, grade: int, slots: Array) -> void:
	if grade < 1 or grade > int(Items._t().get("gradeMax", 7)):
		return
	_own_loot_tables(p)
	p.loot_slots[str(grade)] = clean_slots(slots)


## 주울 1차 옵션 — **등급 하나**의 종류 목록. 비면 그 등급은 옵션이 붙은 장비를 안 줍는다
func set_loot_options(p: Dictionary, grade: int, kinds: Array) -> void:
	if grade < 1 or grade > int(Items._t().get("gradeMax", 7)):
		return
	_own_loot_tables(p)
	p.loot_options[str(grade)] = clean_option_kinds(kinds)


## 두 표를 일곱 등급이 다 든 새 칸으로 적고 옛 칸을 지운다 — 옛 칸은 **둘 다 옮긴 뒤에** 지워야 한다
## (부위만 정할 때 옵션 칸을 안 옮기고 지우면 꺼 둔 옵션이 되살아난다)
func _own_loot_tables(p: Dictionary) -> void:
	p.loot_slots = loot_slots(p)
	p.loot_options = loot_options(p)
	for key in ["loot_skip", "loot_skip_slots", "loot_skip_options"]:
		p.erase(key)


## 주울 부위 표 `{ "등급": [부위, …] }` — 일곱 등급이 다 든 새 사전. 표에 없는 등급은 **전 부위**(처음은 다 줍는다),
## 빈 목록은 그 등급을 끈 것. 칸이 없는 옛 계정·옛 저장은 옛 칸에서 읽는다 —
## `loot_skip`(끈 등급) · `loot_skip_slots`(끈 부위, 전 등급 공통)
static func loot_slots(p: Dictionary) -> Dictionary:
	var raw: Variant = p.get("loot_slots", null)
	var every: Array = Items.slots().duplicate()
	var off_grades := clean_grades(p.get("loot_skip", []))
	var off_slots := clean_slots(p.get("loot_skip_slots", []))
	var out := {}
	for grade in range(1, int(Items._t().get("gradeMax", 7)) + 1):
		var key := str(grade)
		if raw is Dictionary:
			out[key] = clean_slots(raw[key]) if raw.has(key) else every.duplicate()
		elif grade in off_grades:
			out[key] = []
		else:
			out[key] = every.filter(func(slot: Variant) -> bool: return not (str(slot) in off_slots))
	return out


## 주울 1차 옵션 표 `{ "등급": [종류, …] }` — 위와 같다. 옛 칸은 `loot_skip_options`(끈 옵션, 전 등급 공통)
static func loot_options(p: Dictionary) -> Dictionary:
	var raw: Variant = p.get("loot_options", null)
	var every := clean_option_kinds(Items._t().get("optionKinds", []))
	var off := clean_option_kinds(p.get("loot_skip_options", []))
	var out := {}
	for grade in range(1, int(Items._t().get("gradeMax", 7)) + 1):
		var key := str(grade)
		if raw is Dictionary:
			out[key] = clean_option_kinds(raw[key]) if raw.has(key) else every.duplicate()
		else:
			out[key] = every.filter(func(kind: String) -> bool: return not (kind in off))
	return out


## 이 장비를 주울까 — 그 등급에서 **고른 부위**이고, 붙은 1차 옵션이 **전부 고른 옵션**이어야 줍는다
## (도감 자동 등록과 같은 판정 — 드랍은 1차 한 줄이라 그 줄이 정한다). 옵션이 없는 장비는 옵션으로 거르지 않는다
static func loot_wanted(p: Dictionary, item: Dictionary) -> bool:
	var grade := str(int(item.get("grade", 0)))
	if not (str(Items.get_item(str(item.get("id", ""))).get("slot", "")) in loot_slots(p).get(grade, [])):
		return false
	var allowed: Array = loot_options(p).get(grade, [])
	for option in Items.shown_options(item.get("options", [])):
		if not (str(option.get("kind", "")) in allowed):
			return false
	return true


static func clean_grades(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	var top := int(Items._t().get("gradeMax", 7))
	for each in raw:
		if not (each is int or each is float):
			continue
		var grade := int(each)
		if grade >= 1 and grade <= top and not (grade in out):
			out.append(grade)
	out.sort()
	return out


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
		str(p.job), int(p.level), equipped, p.get("passives", {}), p.get("fitness", {}), p.get("codex", {}),
		p.get("trainers", {})
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
	if Items.is_locked(stack):
		_notice("잠근 장비는 팔 수 없습니다")
		return

	var price := Items.sell_price(item, int(stack.get("grade", 1)))
	p.bag.remove_at(index)
	p.gold = int(p.gold) + price
	_notice("%s 판매 — %d G" % [item.name, price])
	_inventory_changed(p)


## 버린다 — 가방 번호 목록 (2026-10-02 요청: 가방의 버리기 창). **장비만** 버린다 — 재료(크리스탈)는
## 창에 안 나오고 여기서도 건너뛴다. **잠근 것은 담겨 와도 건너뛴다** (`Items.is_locked`).
## 겹친 칸은 통째로 버린다. 받을 것이 없다 — 판매와 달리 골드도 안 준다
func discard(p: Dictionary, indices: Array) -> void:
	var chosen: Array = []
	for value in indices:
		var at := int(value)
		if at < 0 or at >= p.bag.size() or chosen.has(at):
			continue
		var stack: Dictionary = p.bag[at]
		if Items.get_item(str(stack.get("id", ""))).is_empty() or Items.is_material(str(stack.get("id", ""))):
			continue
		if Items.is_locked(stack):
			continue
		chosen.append(at)
	if chosen.is_empty():
		_notice("버릴 장비가 없습니다")
		return
	chosen.sort()
	chosen.reverse()  # 뒤에서부터 — 앞 칸 번호가 안 밀린다
	var pieces := 0
	for at in chosen:
		pieces += int(p.bag[at].get("count", 1))
		p.bag.remove_at(at)
	_notice("장비 %d개를 버렸습니다" % pieces)
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
	if Items.is_locked(stack):
		_notice("잠근 장비는 강화할 수 없습니다")
		return

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
		if Items.get_item(str(stack.get("id", ""))).is_empty() or Items.is_locked(stack):
			continue  # 잠근 것은 담겨 와도 두드리지 않는다
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
