class_name World
extends RefCounted

## 판정하는 곳. packages/server/src/ZoneRoom.ts 의 자리다.
##
## **네트워크 얘기는 한 줄도 넣지 않는다.** 입력을 받아 판정하고 상태를 내놓을 뿐이다.
## 지금은 로컬에서 직접 불리고, 나중에 고도 헤드리스 서버가 같은 코드를 돌린다.
## 그래서 판정이 한 벌로 유지된다 → docs/features/godot-migration.md
##
## 화면 코드는 이 클래스를 직접 만지지 않는다. 반드시 Transport 를 거친다.
## 어기면 서버를 붙일 때 그 자리가 전부 터진다.

var zone_id: String = ""
var zone: Dictionary = {}
var half_size: float = 0.0

var _run_speed: float = 4.6
## id -> {x, z, rot, last_seq}
var _players: Dictionary = {}
## [{id, kind, x, z, r, scale, color}, ...] — 스폰 자리는 서버(여기)가 정한다
var _monsters: Array = []
## 몬스터 격자 — 칸(`NEAR` m) → 그 칸의 살아 있는 몬스터. `_fill_grid` 가 채운다
var _grid: Dictionary = {}
## 서로 미는 이웃을 찾는 거리(m)이자 격자 한 칸의 크기
const NEAR := 4.0
## 스폰을 매번 같은 자리에 놓는다. 자리를 정하는 건 언제나 판정하는 쪽이다
var _rng := RandomNumberGenerator.new()
## 장부 판정(드롭·경험치·가방·강화·스킬) — `_ledger_call` 로만 부른다 (docs/features/server.md).
## 굴림은 `_rng` 를 같이 쓴다 — 테스트가 그 씨앗으로 결과를 고정한다
var _ledger := Ledger.new(_rng)
## **서버에 붙어 있으면** 장부 요청을 이리로 보낸다 (`ServerLedger` — `request(op, args)`).
## null 이면 `_ledger` 가 이 자리에서 판정한다 (테스트 모드 · 서버 주소가 없을 때).
## 서버의 답은 `apply_ledger` 로 돌아온다
var remote: Object = null
## 밖으로 내보낼 일들 (맞았다·죽었다·레벨 올랐다). Transport 가 비워 간다
var _events: Array = []
## 아직 안 들어간 연타 (`hits` 가 2 이상인 스킬의 둘째 대부터).
## `{player, target, attack, skill, at}` — `step` 이 때가 된 것부터 넣는다
var _combos: Array = []
## 남아 있는 피해 지대 (천붕각 "균열 지대" 강화). `{player, x, z, reach, cap, attack,
## skill, next_at, until, tick}` — `step` 이 `tick` 마다 범위 안에 피해를 넣는다
var _zones: Array = []
## 아직 안 떨어진 스킬 (`delayMs` 가 있는 스킬 — 천붕각이 뛰어올랐다 내려찍는다).
## `{player, skill, upgrades, range, aim, at}` — `step` 이 때가 되면 `_land` 로 넣는다
var _landings: Array = []
## **던전 한 판** — 이 존이 던전 단계면 `{zone, dungeon, name, stage, result, …}`, 아니면 빈 사전.
## `dungeon` 은 "raid"(보스를 잡으면 성공) · "trial"(`ends_at` 안에 `need` 마리 — `kills` 를 센다).
## 둘 다 **죽으면 실패**다. `result` 는 ""(도는 중) · "clear" · "fail" — 정해지면 더 바뀌지 않고,
## 정해지는 순간 `dungeonResult` 이벤트 하나가 나가 결과창이 뜬다 → docs/features/dungeons.md "결과창"
var _run: Dictionary = {}

## 어느 직업으로 시작하나. 만드는 화면이 없어서 당분간 고정이다
const DEFAULT_JOB := "fighter"

## NPC 와 말할 수 있는 거리 (m). **거리는 여기서 다시 잰다** —
## 창이 열려 있다고 살 수 있는 게 아니다
const NPC_REACH := 4.5

## `_pick_targets` 에 넘기면 명수 상한 없이 범위 안을 전부 고른다
const ALL_TARGETS := -1
## 끌어당기기(무적파쇄권 흡인)의 도착점 — 주먹 앞 `PULL_AHEAD` m 둘레, 온 쪽으로 `PULL_SPREAD` m
## 까지 남긴다. 한 점에 겹쳐 쌓이지 않으면서도 앞 반원 5.5m 판정 안에 다 들어온다
const PULL_AHEAD := 2.2
const PULL_SPREAD := 1.2

## 몇 초마다 저장하나
const SAVE_EVERY_MS := 10000

## --- 순찰 ---
## 쫓을 사람이 없는 몬스터는 집 주변을 서성인다. 가만히 선 무리는 살아 있는 것처럼
## 보이지 않아서다. 값은 **어그로(3m)보다 작게** 잡는다 — 순찰 때문에
## 사람에게 먼저 닿으면 "가만히 있었는데 맞았다"가 된다.
## 4 → 1 (2026-09-29): 사냥터 몬스터가 8m 간격으로 한 마리씩 서는데, 둘이 서로 쪽으로
## 걸어 나오면 한 놈 옆에서 싸울 때 이웃이 알아챈다 (packages/shared/src/zones.ts `fieldSpots`)
const PATROL_RADIUS := 1.0
## 걷는 것처럼 보이게 제 속도의 이만큼으로만 움직인다
const PATROL_SPEED := 0.35
## 목적지에 이만큼 붙으면 도착으로 본다
const PATROL_ARRIVE := 0.3
## 휘두르는 동안 사람이 물러나도 맞는 여유(m). 손이 닿는 0.2초 동안 달리기(4.6m/s)로 0.9m 를
## 가므로, 절반쯤 빠져나가면 빗나간다 — 보고 피할 수는 있되 한 발짝에 다 피하지는 못한다
const SWING_REACH_SLACK := 0.5
## 한 다리 걷고 쉬는 시간. 무리가 한꺼번에 움직이지 않게 놈마다 다르게 뽑는다.
## 쉬는 동안은 idle 이라 **매 프레임 미는 것도 쉬어 간다** (폰 부담)
const PATROL_REST_MIN_MS := 2000
const PATROL_REST_MAX_MS := 6000

## --- 우회 (쫓는 길이 막혔을 때) ---
## 앞 놈 바로 뒤에 선 놈은 곧장 가려다 밀려 제자리에 굳는다 — 몬스터를 막는 건
## 다른 몬스터뿐이고, 정면으로 밀리면 옆으로 미끄러질 방향이 없어서다.
## 한 걸음이 이 비율만큼도 못 나아가면 막힌 것으로 보고 옆으로 돈다.
## 비스듬히 닿으면 밀려서 미끄러지며 저절로 돌아가므로(약 33° 까지) 그건 건드리지 않는다
const DETOUR_BLOCKED := 0.3
## 옆으로 도는 "한 칸". 몬스터 한 몸(지름 0.76 + 틈 0.2)쯤이다.
## 한 칸을 다 가기 전에는 곧장 가기를 다시 시도하지 않는다 — 매 프레임 다시 고르면
## 막힌 자리와 옆 자리 사이를 오가며 떤다
const DETOUR_STEP := 1.0
## 돌아가는 각도. 목표 쪽에 가까운 것부터 대 본다
const DETOUR_TURNS := [PI * 0.25, PI * 0.5, PI * 0.75]

## --- 자동 사냥 ---
## 켠 자리(앵커)에서 이만큼 안의 몬스터만 잡는다.
##
## **한 무리가 통째로 들어오는 크기다.** 사냥터의 무리는 반지름 13m 원에 50마리가
## 흩어져 있고(zones.json 의 `monsters[].radius`), 무리끼리는 32m 떨어져 있다. 무리
## 안 어디에 서서 켜도 그 무리 전체가 들어오려면 13 × 2 = 26 이 필요하고, 여유를
## 얹어 27 로 잡았다. 맵을 줄인 뒤(2026-09-23)로는 옆 무리 가장자리가 6m 밖에
## 있어 **옆 무리도 끌려온다** — 무리를 붙이기로 하면서 받아들인 것이다
const HUNT_RADIUS := 27.0
## 잡고 있던 놈은 이 거리까지는 계속 잡는다. 반경과 같으면 경계에 걸친 놈을
## 잡았다 놓았다 반복한다
const HUNT_LEASH := HUNT_RADIUS + 6.0
## 잡고 있던 놈이 살아 있어도 이 간격마다 다시 훑어 **더 가까운 놈으로 갈아탄다**
## (2026-09-29 "멀리 있는 타겟을 잡았다가 근처에 스폰되면 근처 몬스터를 먼저").
## 매 틱 훑으면 거리가 비슷한 두 놈 사이에서 대상이 떨린다
const HUNT_RESCAN_MS := 1000
## 사거리를 꽉 채우고 서면 몬스터가 조금만 움직여도 빠진다. 이만큼 안으로 붙는다
const HUNT_STANDOFF := 0.7
## 목적지에 이만큼 붙으면 도착으로 본다
const HUNT_ARRIVE := 0.5
## 잡을 것이 없을 때 앵커 주변을 서성이는 반경. **무리가 흩어져 있는 만큼**(8m)만
## 돈다 — 더 넓게 돌면 리스폰을 기다리다 옆 무리까지 걸어가 끌고 온다
const HUNT_PATROL_RADIUS := 8.0
## 한 다리 걷고 쉬는 시간. 몬스터 순찰(2~6초)보다 짧다 — 사람 캐릭터가 오래
## 멈춰 서 있으면 자동 사냥이 멈춘 것처럼 보인다
const HUNT_PATROL_REST_MS := 1200
## 사람이 조작하면 이만큼 자동 사냥이 손을 뗀다. 이동 입력은 매 프레임 오므로
## 손을 떼면 곧바로(0.4초) 자동 사냥이 이어받는다 —
## 화면이 멈춰서 입력이 끊긴 것과 손을 뗀 것을 구별할 방법이 없고, 구별할 필요도
## 없다. 둘 다 "사람이 안 몰고 있다"이다
const MANUAL_HOLD_MS := 400

## 날라차기 (2026-09-29 요청: "평타 사용 시 몬스터와 거리가 어느정도 떨어져 있으면 뛰어가는 게
## 아니라 날라차기 하면서 보간해서 빠른속도로 이동하면서 붙도록"). 평타 대상이 `LUNGE_MIN` 보다
## 멀고 `LUNGE_MAX` 안이면 달려가지 않고 날아 차며 붙는다 — 더 멀면 여기까지 달려와서 난다.
## 사거리 안쪽(`HUNT_STANDOFF`)까지 `LUNGE_SPEED` 로 나는데, 짧아도 `LUNGE_MIN_S`·길어도
## `LUNGE_MAX_S` 로 자른다. **도착하는 순간 평타와 같은 판정으로 맞는다** (`_run_lunges`)
const LUNGE_MIN := 4.0
const LUNGE_MAX := 10.0
const LUNGE_SPEED := 16.0
const LUNGE_MIN_S := 0.22
const LUNGE_MAX_S := 0.45
## 클립(`FlyingKick`)에서 발이 닿는 키. 화면은 나는 시간이 이것이 되게 클립 배속을 바꾼다 —
## `scripts/blender/fighter_moves.py` 의 `FK_IMPACT` 키와 같이 고친다
const LUNGE_HIT_S := 0.45
## 내려앉는 동안 발이 묶인다 — 안 묶으면 차자마자 다음 걸음이 나가 착지 자세가 끊긴다
const LUNGE_LAND_MS := 300
## 사거리가 이보다 긴 직업(원거리)은 날지 않는다 — 활·마법을 쏘러 몬스터 코앞으로 날아가면 안 된다
const LUNGE_REACH := 3.0
## 나는 동안 거는 잠금(경직·시전·공격). **끝은 벽시계가 아니라 `step` 의 시간으로 본다** —
## 헤드리스 테스트는 프레임만 돌려 벽시계가 거의 안 간다. 넉넉히 걸어 두고 착지에서 다시 잡는다
const LUNGE_HOLD_MS := 5000
## 캐릭터를 막는 몸을 훑는 반경. ZoneRoom.ts 의 SOLID_SCAN_RANGE 와 같은 값이다
const SOLID_SCAN_RANGE := 4.0

var _next_save_at := 0


## 그 자리에서 캐릭터를 막는 몸들. **죽은 것은 빼고 4m 안만** 본다.
##
## 시체를 안 빼면 화면에서 사라진 놈이 보이지 않는 벽으로 남아 "왜 안 가지" 가
## 된다 (docs/features/collision.md 의 "죽은 것은 지나간다"). 몬스터끼리는
## `_move_monster` 가 이미 빼고 있었는데 **캐릭터 이동만 통째로 넘기고 있었다.**
## ZoneRoom.ts 의 solidsNear 와 같은 순서·같은 조건이다
func _solids_near(x: float, z: float) -> Array:
	var near: Array = []
	for monster in _monsters:
		if int(monster.hp) <= 0:
			continue
		var dx: float = float(monster.x) - x
		var dz: float = float(monster.z) - z
		if dx * dx + dz * dz > SOLID_SCAN_RANGE * SOLID_SCAN_RANGE:
			continue
		near.append(monster)
	return near


func open(id: String) -> void:
	zone_id = id
	zone = GameData.zone(id)
	half_size = Movement.zone_half_size(float(zone.get("size", 66)))
	_run_speed = float(GameData.constants().get("runSpeed", 4.6))
	# 떠난 존의 몬스터를 붙잡은 연타가 새 존에서 들어가면 안 된다 (지대도 같다)
	_combos.clear()
	_zones.clear()
	_spawn_monsters()
	_start_run()
	# 서버에 붙어 있으면 어느 존에 들어왔는지 알린다 — 처치 보고를 그 존의 명단에 대 본다
	if remote != null:
		remote.request(&"enter", [id])


## 존의 **몬스터 명단** `{id: {kind, respawn_ms}}` — 자리 없이 id·종류·되살아나는 시간만.
## 서버가 처치 보고를 대 보는 표다 (`LedgerServer`). id 는 `_spawn_monsters` 와 **같은 규칙**
## (`<종류>_<번호>`, 번호는 무리를 건너며 이어진다)이어야 해서 `server_test` 가 둘을 대 본다
static func roster(zone_id: String) -> Dictionary:
	var out := {}
	for pack in GameData.zone(zone_id).get("monsters", []):
		var kinds: Dictionary = GameData.load_table("monsters").get("kinds", {})
		if not kinds.has(str(pack.get("kind", ""))):
			continue
		for i in int(pack.get("count", 0)):
			out["%s_%d" % [str(pack.kind), out.size()]] = {
				"kind": str(pack.kind), "respawn_ms": float(pack.get("respawnMs", 10000)),
			}
	return out


## 존이 정한 무리대로 몬스터를 놓는다. 서로 겹치지 않는 자리를 골라 준다.
func _spawn_monsters() -> void:
	_monsters.clear()
	# 같은 존이면 언제나 같은 자리에 나오게 한다 (테스트도 이것에 기댄다)
	_rng.seed = hash(zone_id)

	for pack in zone.get("monsters", []):
		var kind := GameData.monster_kind(str(pack.get("kind", "")))
		if kind.is_empty():
			continue
		var scale := float(kind.get("scale", 1.0))
		var radius := Movement.monster_radius(scale)
		for i in int(pack.get("count", 0)):
			var spot := Movement.scatter_spawn(
				float(pack.get("x", 0.0)),
				float(pack.get("z", 0.0)),
				float(pack.get("radius", 1.0)),
				radius + Movement.MONSTER_GAP,
				_monsters,
				half_size,
				_rng,
			)
			_monsters.append(make_monster(
				"%s_%d" % [kind.id, _monsters.size()],
				kind,
				spot.x,
				spot.z,
				float(pack.get("respawnMs", 10000)),
				float(_monsters.size()) * 0.7,
			))


func join(player_id: String) -> void:
	var spawn: Array = zone.get("spawns", {}).get("default", [0, 0])
	var kept: Dictionary = _players.get(player_id, {})
	var level := int(kept.get("level", 1))
	var stats := Combat.stats_for(DEFAULT_JOB, level)
	# 새 캐릭터는 직업의 첫 스킬을 배운 채 퀵슬롯 1번에 올려 두고 시작한다 (2026-09-26 요청).
	# 1레벨은 스킬 포인트가 0 이라 안 주면 아무것도 못 쓴다. 이어하기는 `restore` 가 저장으로 덮는다
	var starter: Array = []
	if kept.is_empty():
		for id in Skills.for_job(DEFAULT_JOB).slice(0, 1):
			starter.append(str(id))
	_players[player_id] = {
		"id": player_id,
		"x": float(spawn[0]),
		"z": float(spawn[1]),
		"rot": 0.0,
		"last_seq": -1,
		"dead": bool(kept.get("dead", false)),
		"job": DEFAULT_JOB,
		"level": level,
		# 존을 옮겨도 성장은 따라간다
		"exp": int(kept.get("exp", 0)),
		"hp": int(kept.get("hp", stats.maxHp)),
		"gold": int(kept.get("gold", 0)),
		"stats": stats,
		"next_attack_at": 0,
		"rooted_until": 0,
		# 스킬 시전이 끝나는 시각 — 그때까지 **다른 스킬을 못 쓴다** (`cast`)
		"cast_until": 0,
		# --- 자동 사냥 ---
		# **존을 옮기면 꺼진다** (join 을 다시 타므로). 앵커가 지난 존의 자리라
		# 남겨 두면 켜 둔 채로 엉뚱한 데를 향해 걷는다
		"auto": false,
		"auto_x": float(spawn[0]),
		"auto_z": float(spawn[1]),
		"auto_target": "",
		# 다음에 대상을 다시 훑는 시각 (`HUNT_RESCAN_MS`)
		"auto_scan_at": 0,
		# --- 테스트: 무적 --- 켜면 몬스터에게 맞아도 HP 가 안 준다.
		# 존을 옮겨도 유지한다 (테스트 중에 존마다 다시 켜면 번거롭다)
		"invincible": bool(kept.get("invincible", false)),
		# 잡을 것이 없을 때 서성이는 자리와 쉬는 시각
		"auto_patrol_x": float(spawn[0]),
		"auto_patrol_z": float(spawn[1]),
		"auto_rest_until": 0,
		# 사람이 몰고 있는 동안은 자동 사냥이 손을 뗀다
		"manual_until": 0,
		# --- 스킬 ---
		"skills": kept.get("skills", starter).duplicate(),
		"skill_points": int(kept.get("skill_points", level - 1)),
		# 배운 패시브 단계 `{ id: 단계 }` — 스킬창 [습득] 으로 오른다 (`learn_passive`)
		"passives": kept.get("passives", {}).duplicate(),
		"skill_bar": kept.get("skill_bar", starter).duplicate(),
		# 스킬별 다음에 쓸 수 있는 시각
		"skill_ready_at": {},
		# --- 물약 (`drink_potion`) --- 개수는 세지 않고 쿨타임(10초)만 막는다.
		# 존을 옮겨도 쿨타임은 이어진다 — 안 그러면 차원문을 오가며 연달아 마신다
		"potion_ready_at": int(kept.get("potion_ready_at", 0)),
		# HP 가 이 % 이하로 떨어지면 저절로 마신다. 0 이면 끔. 저장에 남는다
		"potion_pct": int(kept.get("potion_pct", _potion_rule("potionAutoDefault", 90))),
		# 스킬 강화 — `{ 스킬 id: [강화 id, …] }`. 스킬창에서 스킬 경험치로 채우면 붙는다 (`feed_upgrade`)
		"skill_upgrades": kept.get("skill_upgrades", {}).duplicate(true),
		# 아직 안 넣은 **스킬 경험치** — 던전을 깨면 쌓이고(`_check_dungeon_clear`) 스킬창에서
		# 고른 강화에 넣는다. 모든 스킬·강화에 공용이다
		"skill_exp": int(kept.get("skill_exp", 0)),
		# 붙기 전까지 쌓인 경험치 — `{ 스킬 id: { 강화 id: 경험치 } }` (`feed_upgrade`)
		"skill_upgrade_exp": kept.get("skill_upgrade_exp", {}).duplicate(true),
		# --- 아이템 ---
		"bag": kept.get("bag", []).duplicate(true),
		"equipped": kept.get("equipped", {}).duplicate(true),
		# 한 번만 주는 것을 받았다는 표시 (`grant_once`) — 저장에 남는다
		"granted": kept.get("granted", []).duplicate(),
		# 캐릭터 이름 (`Names` 규칙). 시작 화면이 정하고(`set_name`) 저장에 남는다. 판정에는 안 쓴다
		"name": str(kept.get("name", "")),
		# 유료 재화 — 서버가 결제를 확인해야만 는다. 혼자 노는 판에서는 늘 0 이다
		"diamonds": int(kept.get("diamonds", 0)),
		# --- 헬스 (docs/features/fitness.md) --- 던전을 깨면 쌓이는 프로틴 `{power, defense, health}` 과
		# 운동 단계 `{bench, deadlift, squat}`. 헬스 창에서 프로틴을 넣어 단계를 올린다 (`fitness_up`)
		"proteins": kept.get("proteins", {}).duplicate(),
		"fitness": kept.get("fitness", {}).duplicate(),
		# --- 장비 도감 (docs/features/codex.md) --- `{ 아이템 id: 채운 강화 비트 }`. 도감 창에서 가방의
		# 장비를 넣어 채운다 (`codex_register`)
		"codex": kept.get("codex", {}).duplicate(),
		# 샌드백 랭킹전 `{week, best, unpaid?}` — 그 주 최고 기록 (docs/features/sandbag.md)
		"sandbag": kept.get("sandbag", {}).duplicate(true),
		# 던전 하루 입장 `{ 종류 id: {day, count} }` (docs/features/dungeons.md "하루 한 번")
		"dungeon_entries": kept.get("dungeon_entries", {}).duplicate(true),
	}
	_refresh_stats(_players[player_id])
	# 샌드백 랭킹전 — 들어오면 샌드백을 보고 선다. 평타는 정면 부채꼴 안만 치므로 등을 지고 서면 헛손질한다
	for monster in _monsters:
		if bool(monster.get("dummy", false)):
			var me: Dictionary = _players[player_id]
			me.rot = atan2(float(monster.x) - float(me.x), float(monster.z) - float(me.z))
			break


func leave(player_id: String) -> void:
	_players.erase(player_id)


## 이동 입력. ZoneRoom.handleInput 과 같은 순서로 거른다.
func input_move(player_id: String, seq: int, dx: float, dz: float, dt: float) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return

	# 순번이 역행하면 지연 도착한 중복이다
	if seq <= int(player.last_seq):
		return

	# 죽어 있으면 위치는 고정하되 순번은 갱신한다
	if bool(player.dead):
		player.last_seq = seq
		return

	var now := Time.get_ticks_msec()
	# **사람이 몰면 사람이 이긴다.** 자동 사냥은 손을 뗀다 (_take_manual).
	# 휘두르는 중이라 발이 묶여 있어도 먼저 잡는다 — 안 그러면 경직(400ms)마다
	# 자동 사냥이 한 번씩 끼어들어 조작하던 방향과 다른 데로 몸이 돈다
	if sqrt(dx * dx + dz * dz) > 1e-4:
		_take_manual(player, now)

	# 휘두르는 중이면 발을 묶는다. **순번은 갱신하고 위치만 안 옮긴다** —
	# 안 갱신하면 나중에 서버를 붙였을 때 클라이언트 보정이 이 구간 내내 멈춘다
	if now < int(player.rooted_until):
		player.last_seq = seq
		return

	# 몬스터를 뚫고 못 지나간다. 미는 쪽은 언제나 움직이는 쪽이다.
	# **시체는 빼고 넘긴다** — 넣으면 보이지 않는 벽이 된다 (_solids_near)
	Movement.apply_move(
		player, dx, dz, dt, half_size, _speed_of(player), _solids_near(player.x, player.z)
	)
	player.last_seq = seq

	if sqrt(dx * dx + dz * dz) > 1e-4:
		# **시전 중에는 제자리에서 돌지 않는다** (2026-09-27 "스킬 쓰는 방향으로 몸이 안
		# 돌아가"). 쫓던 놈 앞에서 화면은 `dt` 0 으로 매 프레임 그쪽을 보게 보내는데,
		# 경직이 풀리자마자 스킬 동작 도중에 몸이 그놈 쪽으로 돌아갔다. 실제로 걸으면
		# 동작이 끊기므로(`_play_player_clip` 의 `cut`) 그때는 걷는 쪽을 본다
		if dt > 0.0 or now >= int(player.get("cast_until", 0)):
			player.rot = atan2(dx, dz)
		# **걸어간 자리가 새 사냥터다.** 앵커를 안 옮기면 손을 떼는 순간 자동
		# 사냥이 원래 자리로 도로 끌고 간다 — 조작이 이긴 것처럼 보이지 않는다
		if bool(player.get("auto", false)):
			_anchor_here(player)


## 한 틱. 전투가 들어올 자리다 (5단계).
func step(delta: float) -> void:
	var now := Time.get_ticks_msec()
	_respawn(now)
	_check_run_time(now)
	_check_sandbag_week(now)
	_run_landings(now)
	_run_lunges(delta, now)
	_run_combos(now)
	_run_zones(now)
	_step_monsters(delta, now)
	_drive_sandbag_auto(now)
	_drive_auto(delta, now)
	_drive_potions(now)
	_check_gate()

	# 주기적으로 남긴다. 탭이 갑자기 닫혀도 최근 것은 지킨다
	if now >= _next_save_at:
		_next_save_at = now + SAVE_EVERY_MS
		for id in _players:
			save(id)


## 차원문 안에 서 있으면 **고르는 화면을 띄우라고 알린다.** 어디로 갈지는
## 사람이 고른다 (웹 클라의 ui/zoneGate.ts 와 같은 자리).
##
## 매 프레임 알리면 화면이 깜빡이므로, 문을 벗어날 때까지 한 번만 알린다.
func _check_gate() -> void:
	var gate: Dictionary = zone.get("gate", {})
	if gate.is_empty():
		return
	var position: Array = gate.get("position", [0, 0])
	var radius := float(gate.get("radius", 2.6))

	for id in _players:
		var player: Dictionary = _players[id]
		if bool(player.get("dead", false)):
			continue
		var gap := Vector2(player.x - float(position[0]), player.z - float(position[1])).length()
		var inside := gap <= radius
		if inside and not bool(player.get("at_gate", false)):
			_events.append({"type": "gate"})
		player["at_gate"] = inside


## 고른 곳으로 옮긴다. **있는 존인지 여기서 다시 본다** — 화면이 보내는 건 요청이다
func travel(player_id: String, target: String) -> void:
	if not _players.has(player_id):
		return
	var all: Dictionary = GameData.zones().get("zones", {})
	if not all.has(target) or target == zone_id:
		return
	if not _use_dungeon_entry(_players[player_id], target):
		return
	_move_to(target)


## 하루 한 번인 던전이면 오늘 입장을 쓴다. 다 썼으면 알리고 false (docs/features/dungeons.md "하루 한 번").
## 서버에 붙어 있으면 **기기는 막기만 하고 세는 것은 서버다** — `enter` 를 받은 `LedgerServer._enter` 가
## 장부에 적고, 답이 오면 `apply_ledger` 가 덮는다
func _use_dungeon_entry(player: Dictionary, target: String) -> bool:
	if remote == null:
		var ok := _ledger.dungeon_enter(player, target)
		_after_ledger(player, int(player.level), _ledger.take_events())
		return ok
	if Ledger.dungeon_entries_left(player, target, _ledger.dungeon_day()) != 0:
		return true
	var type := GameData.dungeon_type_of(target)
	_events.append({"type": "notice", "text": "%s 은(는) 오늘 이미 들어갔습니다 — 5시에 다시 열립니다" % str(type.get("name", "던전"))})
	return false


## 존을 옮긴다. 있는 존인지는 부르는 쪽이 봤다
func _move_to(target: String) -> void:
	open(target)
	for who in _players:
		join(who)
	_events.append({"type": "zone", "zone": target})
	_check_sandbag_week(Time.get_ticks_msec(), true)


## 밖으로 내보내는 상태. 읽기 전용으로 쓴다.
func snapshot() -> Dictionary:
	return {
		"zone": zone_id,
		"size": zone.get("size", 66),
		"players": _players,
		"monsters": _monsters,
		"gate": zone.get("gate", {}),
		"npcs": zone.get("npcs", []),
		"dungeon": _run,
	}


## 기본 공격. **대상은 서버(여기)가 고른다** — 클라이언트가 대상 id 를 보내게 하면
## 사거리 밖이나 벽 너머의 적을 지정할 수 있다.
## 정면 부채꼴 안에서 가장 가까운 하나를 친다 (server/combat.ts 의 resolvePlayerAttack).
func attack(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or bool(player.dead):
		return

	var now := Time.get_ticks_msec()
	if now < int(player.next_attack_at):
		return
	# 샌드백 랭킹전의 카운트 동안은 못 친다 — 시작 신호 전에 넣은 피해는 세지 않으니 헛손질이다
	if _counting_down(now):
		return
	# **스킬 시전 중에는 기본 공격도 못 한다** (2026-09-24 요청). 경직(0.4초)이 풀려도
	# 스킬 동작은 1초 넘게 남는데, 그 틈에 휘두르면 동작이 끊긴다 (`cast` 의 `cast_until`)
	if now < int(player.get("cast_until", 0)):
		return

	var stats: Dictionary = player.stats
	var cooldown := Combat.effective_cooldown(stats.attackCooldown, stats.attackSpeed)
	player.next_attack_at = now + cooldown
	var root := Combat.attack_root_ms(cooldown)
	player.rooted_until = now + root
	# 휘두르는 동안 못 움직인다는 통보. 화면이 이 값만큼 동작을 튼다.
	# `speed` 는 발차기를 트는 배속 — 기본 간격 / 지금 간격 (공속 +800% 면 9배, Lv.200)
	_events.append({
		"type": "swing", "id": player_id, "root_ms": root,
		"speed": float(stats.attackCooldown) / maxf(1.0, float(cooldown)),
		# 다음 대까지의 간격 — 화면이 "이어 차기" 인지 가린다 (`game.gd` `_kick_clip`)
		"ms": cooldown,
	})

	var picked := _pick_targets(player, float(stats.attackRange), _attack_arc(), 1)
	if picked.is_empty():
		return
	var target: Dictionary = picked[0]

	_hit_monster(player, target, float(stats.attack), "")


## 맞을 놈들을 고른다. **가까운 순서로 max_targets 만큼** — `ALL_TARGETS` 면 범위 안
## 전부다 (스킬은 이것만 쓴다. 한 마리만 치는 건 평타뿐이다).
##
## origin 이 주어지면 그 자리를 중심으로 한 **원**으로 본다 (원거리 스킬이 날아가
## 터진 것). 날아가 터진 것에 "시전자 정면"은 의미가 없다. origin 이 없으면
## 시전자 자리에서 정면 부채꼴로 본다 — 등 뒤는 맞지 않는다.
##
## `facing` 을 주면 origin 이 있어도 **그 쪽 부채꼴**로 본다 — 뒤따르는 한 대(파천장 "연파")가
## 시전한 자리·보던 쪽을 기억해 두고 나중에 다시 고를 때다. 그 사이 몸을 돌려도 안 바뀐다
func _pick_targets(
	player: Dictionary,
	reach: float,
	arc: float,
	max_targets: int,
	origin: Dictionary = {},
	facing: float = NAN,
) -> Array:
	if max_targets == 0:
		return []
	var from_x: float = origin.get("x", player.x)
	var from_z: float = origin.get("z", player.z)
	var rot := float(player.rot) if is_nan(facing) else facing
	var facing_x := sin(rot)
	var facing_z := cos(rot)
	var half_arc := arc / 2.0
	var use_arc := arc < TAU and (origin.is_empty() or not is_nan(facing))

	var found: Array = []
	for monster in _monsters:
		if int(monster.hp) <= 0:
			continue
		var dx: float = monster.x - from_x
		var dz: float = monster.z - from_z
		var dist := sqrt(dx * dx + dz * dz)
		if dist > reach:
			continue
		if use_arc and dist >= 1e-3:
			var dot := (dx / dist) * facing_x + (dz / dist) * facing_z
			if acos(clampf(dot, -1.0, 1.0)) > half_arc:
				continue
		found.append({"monster": monster, "dist": dist})

	# 가까운 순서로 — 범위기라도 눈앞의 적부터 맞는 게 자연스럽다
	found.sort_custom(func(a, b): return a.dist < b.dist)

	var out: Array = []
	for entry in found:
		if max_targets > 0 and out.size() >= max_targets:
			break
		out.append(entry.monster)
	return out


## 자동 사냥을 켜고 끈다. **켠 자리를 앵커로 잡는다** — 앵커가 없으면 몬스터를
## 따라 맵 끝까지 끌려간다.
func set_auto(player_id: String, on: bool) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	player.auto = on
	player.auto_target = ""
	if on:
		_anchor_here(player)


## 앵커를 지금 서 있는 자리로 잡는다 (켤 때와 사람이 몰고 다닌 뒤).
func _anchor_here(player: Dictionary) -> void:
	player.auto_x = player.x
	player.auto_z = player.z
	player.auto_patrol_x = player.x
	player.auto_patrol_z = player.z
	player.auto_target = ""
	player.auto_rest_until = 0


## 사람이 몰기 시작했다. **조작이 자동 사냥보다 먼저다** — 켜 둔 채로 잠깐
## 자리를 옮기거나 위험한 놈을 피하는 것이 가장 흔한 조작이라, 그때마다 끄게
## 하면 단추를 두 번 더 눌러야 한다.
##
## 앵커를 옮기는 것은 **발을 옮긴 뒤**다 (input_move 끝) — 걸어간 자리가 새
## 사냥터이기 때문이다. 여기서 같이 옮기면 한 프레임씩 뒤처진다.
func _take_manual(player: Dictionary, now: int) -> void:
	player.manual_until = now + MANUAL_HOLD_MS


## 자동 사냥 한 틱. 고르고 → 붙고 → 친다. 잡을 것이 없으면 앵커 주변을 서성인다.
## **사람이 몰고 있는 동안은 통째로 쉰다** (조작이 먼저다).
##
## **판정하는 쪽(여기)이 몬다.** 화면(`_process`)이 몰면 탭을 옮기거나 폰 화면이
## 꺼지는 순간 0~1Hz 로 떨어져 캐릭터가 그 자리에 선다
## → docs/features/auto-hunt-and-targeting.md 의 "왜 자동 사냥은 서버가 하나"
func _drive_auto(delta: float, now: int) -> void:
	for id in _players:
		var player: Dictionary = _players[id]
		if not bool(player.get("auto", false)) or bool(player.get("dead", false)):
			continue
		# 사람이 몰고 있는 동안은 손을 뗀다. 둘이 같이 밀면 캐릭터가 두 목적지
		# 사이에서 떨고, 조작한 쪽이 진 것처럼 보인다
		if now < int(player.get("manual_until", 0)):
			continue

		var target := _pick_hunt_target(player, now)
		if target.is_empty():
			# 아무도 없다. 앵커 주변을 서성이며 기다린다
			player.auto_target = ""
			_patrol_auto(player, delta, now)
			continue

		player.auto_target = str(target.id)
		# 사거리를 꽉 채우고 서면 상대가 조금만 움직여도 빠진다. 안쪽으로 붙는다
		var reach := float(player.stats.attackRange)
		_walk_auto(player, float(target.x), float(target.z), delta, now, reach * HUNT_STANDOFF)
		_auto_strike(player, id, target, now)


## 자동 사냥 중인 사람이 대상에게 넣는 한 수 — 스킬이 먼저, 없으면 사거리 안일 때만
## 기본 공격. 자동 사냥 한 틱(`_drive_auto`)과 몬스터를 눌러 쫓을 때(`strike`)가 같이 쓴다.
func _auto_strike(player: Dictionary, id: String, target: Dictionary, now: int) -> void:
	# 휘두르는 중에는 다음 것을 넣지 않는다. 스킬 경직 중에 기본 공격이 끼면
	# 스킬 동작이 끊기고, 쿨타임이 0 인 테스트 스위치에서는 스킬이 매 틱 나간다.
	# **스킬 시전이 끝날 때까지도 기다린다** — 경직(0.4초)이 풀려도 동작은 1초 넘게
	# 남는데, 그 사이 다음 스킬은 막혀 있으니 평타가 끼어 동작을 끊는다
	#
	# **몸도 그동안은 돌리지 않는다** (2026-09-27). 돌리는 줄이 이 위에 있어서, 스킬이
	# 가까운 놈 쪽으로 나가고 바로 다음 틱에 몸이 자동 사냥 대상 쪽으로 되돌아갔다 —
	# 화면에서는 몸이 스킬 쪽을 한 번도 안 봤다
	if now < maxi(int(player.rooted_until), int(player.get("cast_until", 0))):
		return
	# 치기 전에 그쪽을 본다. 판정 부채꼴이 rot 를 보기 때문이다 —
	# 안 돌리면 마지막으로 걷던 쪽으로 헛친다 (attack 은 정면에서 다시 고른다)
	player.rot = atan2(float(target.x) - player.x, float(target.z) - player.z)
	var gap := Vector2(float(target.x) - player.x, float(target.z) - player.z).length()
	# 스킬이 먼저다. 돌아온 스킬이 있으면 기본 공격 대신 그걸 쓴다
	if _auto_cast(player, id, str(target.id), gap, now):
		return
	# **사거리 안일 때만 휘두른다.** 멀리서 헛휘두르면 그때마다 경직(400ms)이
	# 걸려 한 발짝도 못 나간다 — 붙기 전에 제자리에서 팔만 돌게 된다
	if gap <= float(player.stats.attackRange):
		attack(id)
		return
	# 멀면 날아 차며 붙는다. **거리로 가린다** (2026-09-29 "스킬 거리가 안 닿으면 날라차기 먼저") —
	# 여기까지 왔으면 사거리가 닿는 스킬이 없다는 뜻이다(`_auto_cast` 가 사거리를 본다).
	# 돌아온 스킬이 있어도 날아 붙고, 착지하면 그 스킬이 나간다
	_lunge(player, id, target, now)


## 몬스터를 눌러 쫓는 동안 화면이 보내는 한 수 (game.gd `_chase_and_hit`).
## 쫓는 동안은 이동 입력이 매 프레임 와서 자동 사냥이 통째로 쉬므로(`manual_until`),
## 예전처럼 `attack` 만 보내면 **자동 사냥을 켜 둬도 평타만 나갔다** (2026-09-26 지적).
## 켜 둔 사람은 자동 사냥과 같은 `_auto_strike` 로 스킬부터 쓴다. 끈 사람은 기본 공격이다.
##
## 누른 놈 id 는 **어느 쪽을 볼지와 스킬 사거리를 재는 데만** 쓴다 — 맞는지는
## `cast` · `attack` 이 정면에서 다시 고른다.
func strike(player_id: String, mob_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or bool(player.dead):
		return
	var auto := bool(player.get("auto", false))
	for monster in _monsters:
		if str(monster.id) == mob_id and int(monster.hp) > 0:
			if auto:
				_auto_strike(player, player_id, monster, Time.get_ticks_msec())
			# 끈 사람은 평타다 — 멀면 날아 차며 붙고(`_lunge`), 사거리 안이면 그 자리에서 친다.
			# 그 사이(사거리 ~ `LUNGE_MIN`)는 화면이 걸어서 붙인다 — 여기서 치면 헛휘둘러 발이 묶인다
			elif not _lunge(player, player_id, monster, Time.get_ticks_msec()):
				var gap := Vector2(float(monster.x) - player.x, float(monster.z) - player.z).length()
				if gap <= float(player.stats.attackRange):
					attack(player_id)
			return
	if not auto:
		attack(player_id)


## 날라차기를 건다 — 평타를 칠 수 있을 때, 대상이 `LUNGE_MIN` 보다 멀고 `LUNGE_MAX` 안이면.
## 건 순간부터 착지까지 발·스킬·평타가 다 묶이고, 움직임은 `_run_lunges` 가 한다.
## 나갔으면 true
func _lunge(player: Dictionary, id: String, target: Dictionary, now: int) -> bool:
	var reach := float(player.stats.attackRange)
	if reach > LUNGE_REACH or player.has("lunge"):
		return false
	if now < maxi(int(player.next_attack_at), maxi(int(player.rooted_until), int(player.get("cast_until", 0)))):
		return false
	var to := Vector2(float(target.x) - player.x, float(target.z) - player.z)
	var gap := to.length()
	if gap <= LUNGE_MIN or gap > LUNGE_MAX:
		return false
	var secs := clampf((gap - reach * HUNT_STANDOFF) / LUNGE_SPEED, LUNGE_MIN_S, LUNGE_MAX_S)
	player.lunge = {
		"target": str(target.id), "from_x": player.x, "from_z": player.z,
		"to_x": player.x, "to_z": player.z, "t": 0.0, "secs": secs,
	}
	player.rot = atan2(to.x, to.y)
	player.rooted_until = now + LUNGE_HOLD_MS
	player.cast_until = now + LUNGE_HOLD_MS
	player.next_attack_at = now + LUNGE_HOLD_MS
	# 화면은 이것을 받고 날라차기 동작을 튼다. 발이 닿는 키가 도착에 오게 배속을 준다
	_events.append({
		"type": "lunge", "id": id, "target": str(target.id),
		"ms": roundi(secs * 1000.0) + LUNGE_LAND_MS, "speed": LUNGE_HIT_S / secs,
	})
	return true


## 날고 있는 사람을 한 틱 옮긴다. **대상이 움직이면 도착점도 따라간다** — 나는 0.2~0.45초에
## 몬스터도 한두 걸음 간다. 가는 길의 다른 몸은 넘어간다(날고 있다). 부딪힘은 착지에서 한 번 민다.
##
## 보간은 `k²(2-k)` — 제자리에서 차고 올라(속도 0) 가운데서 빨라지고, **닿는 순간에도 속도가
## 남는다.** 끝에서 0 으로 줄이면(smoothstep) 발을 뻗은 채 둥실 떠서 닿는 것처럼 보인다
func _run_lunges(delta: float, now: int) -> void:
	for id in _players:
		var player: Dictionary = _players[id]
		if not player.has("lunge"):
			continue
		var lunge: Dictionary = player.lunge
		if bool(player.dead):
			player.erase("lunge")
			player.rooted_until = now
			player.cast_until = now
			player.next_attack_at = now
			continue
		var target := {}
		for monster in _monsters:
			if str(monster.id) == str(lunge.target) and int(monster.hp) > 0:
				target = monster
				break
		if not target.is_empty():
			var from := Vector2(float(lunge.from_x), float(lunge.from_z))
			var at := Vector2(float(target.x), float(target.z))
			var stop := from.direction_to(at) * float(player.stats.attackRange) * HUNT_STANDOFF
			lunge.to_x = at.x - stop.x
			lunge.to_z = at.y - stop.y
		lunge.t = float(lunge.t) + delta
		var k := clampf(float(lunge.t) / float(lunge.secs), 0.0, 1.0)
		var e := k * k * (2.0 - k)
		player.x = clampf(lerpf(float(lunge.from_x), float(lunge.to_x), e), -half_size, half_size)
		player.z = clampf(lerpf(float(lunge.from_z), float(lunge.to_z), e), -half_size, half_size)
		if k < 1.0:
			continue

		# 닿았다 — 겹친 몸을 밀어내고 평타와 같은 판정으로 찬다
		player.erase("lunge")
		Movement.push_out_of_solids(player, _solids_near(player.x, player.z), half_size)
		var stats: Dictionary = player.stats
		player.next_attack_at = now + Combat.effective_cooldown(stats.attackCooldown, stats.attackSpeed)
		player.rooted_until = now + LUNGE_LAND_MS
		player.cast_until = now
		if not target.is_empty():
			player.rot = atan2(float(target.x) - player.x, float(target.z) - player.z)
		var picked := _pick_targets(player, float(stats.attackRange), _attack_arc(), 1)
		if not picked.is_empty():
			_hit_monster(player, picked[0], float(stats.attack), "")


## 자동 사냥의 스킬. **쿨타임이 긴 것부터**(`Skills.auto_order`) 보고, 쿨타임이 돈 것 중
## 대상이 그 스킬 사거리 안에 든 첫 것을 쓴다.
## 칸 순서를 우선순위로 쓰던 때는 1번 칸 할퀴기만 나갔다 (2026-09-27 지적).
##
## 쏘는 것은 사람이 누를 때와 **같은 `cast`** 다. 쿨타임·액션바·조준 검증을 두 벌
## 만들면 반드시 어긋난다. 나갔는지는 경직이 새로 걸렸는지로 본다 — 쿨타임으로
## 보면 테스트 스위치(쿨타임 0)에서 나갔는데도 안 나간 것으로 읽힌다.
func _auto_cast(player: Dictionary, id: String, aim_id: String, gap: float, now: int) -> bool:
	var ready_at: Dictionary = player.skill_ready_at
	var order := Skills.auto_order(str(player.job), player.skill_bar)
	for skill_id in order:
		if now < int(ready_at.get(skill_id, 0)):
			continue
		var skill := Skills.get_skill(str(player.job), str(skill_id))
		if skill.is_empty():
			continue
		var heal := float(skill.get("selfHeal", 0.0))
		if heal > 0.0:
			# 회복기는 채울 만큼 빠졌을 때만 쓴다. 가득 찬 채로 쓰면 쿨타임만 버린다
			var max_hp := float(player.stats.maxHp)
			if max_hp - float(player.hp) < max_hp * heal:
				continue
		elif gap > float(skill.range):
			continue
		cast(id, str(skill_id), aim_id)
		if int(player.rooted_until) > now:
			return true
	return false


## 앵커 반경 안에서 **가장 가까운** 산 몬스터. 잡고 있던 놈은 리쉬까지 봐준다 —
## 반경과 같으면 경계에 걸친 놈을 잡았다 놓았다 반복하고, 놓을 때마다 앵커로
## 걸어 돌아가려다 다시 붙는 그림이 된다.
##
## 잡고 있던 놈은 **`HUNT_RESCAN_MS`(1초) 동안만** 그대로 둔다. 그 뒤에는 다시 훑어
## 더 가까운 놈이 있으면 갈아탄다 — 멀리 있는 놈을 쫓는 사이 옆에 리스폰된 놈을
## 두고 계속 걸어가지 않게 한다.
func _pick_hunt_target(player: Dictionary, now: int) -> Dictionary:
	var anchor := Vector2(float(player.auto_x), float(player.auto_z))
	var current := str(player.get("auto_target", ""))
	var rescan := now >= int(player.get("auto_scan_at", 0))
	var best: Dictionary = {}
	var best_gap := INF

	for monster in _monsters:
		if int(monster.hp) <= 0:
			continue
		var from_anchor := Vector2(monster.x - anchor.x, monster.z - anchor.y).length()
		if str(monster.id) == current:
			# 잡고 있던 놈은 리쉬 안까지 봐준다. 훑을 때가 아니면 그대로 잡는다
			if from_anchor > HUNT_LEASH:
				continue
			if not rescan:
				return monster
		elif from_anchor > HUNT_RADIUS:
			continue
		var gap := Vector2(monster.x - player.x, monster.z - player.z).length()
		if gap < best_gap:
			best_gap = gap
			best = monster

	player.auto_scan_at = now + HUNT_RESCAN_MS
	return best


## 잡을 것이 없을 때. 앵커 주변에서 한 다리 걷고 잠시 쉰다 — 몬스터 순찰(`_patrol`)과
## 같은 모양이다.
##
## **선 채로 기다리지 않는 이유**는 두 가지다. 가만히 서 있으면 자동 사냥이 멈춘
## 것처럼 보이고, 리스폰을 기다리는 동안 한 발짝도 안 움직이면 무리 반대편에 새로
## 나온 놈을 사거리 안에 두는 데 그만큼 더 걸린다.
func _patrol_auto(player: Dictionary, delta: float, now: int) -> void:
	var anchor := Vector2(float(player.auto_x), float(player.auto_z))
	var here := Vector2(player.x, player.z)

	# 쫓다가 반경 밖까지 나와 있으면 먼저 앵커 쪽으로 돌아온다.
	# 안 돌아가면 마지막으로 쫓던 자리에 눌러앉아 무리 밖에서 서성인다
	if here.distance_to(anchor) > HUNT_PATROL_RADIUS:
		player.auto_rest_until = 0
		_walk_auto(player, anchor.x, anchor.y, delta, now, HUNT_PATROL_RADIUS * 0.5)
		return

	if now < int(player.auto_rest_until):
		return

	var goal := Vector2(float(player.auto_patrol_x), float(player.auto_patrol_z))
	if here.distance_to(goal) > HUNT_ARRIVE:
		_walk_auto(player, goal.x, goal.y, delta, now, HUNT_ARRIVE)
		return

	# 다 걸었다. 앵커 반경 안에서 다음 자리를 뽑고 쉰다
	var angle := _rng.randf() * TAU
	var reach := _rng.randf_range(HUNT_PATROL_RADIUS * 0.4, HUNT_PATROL_RADIUS)
	player.auto_patrol_x = clampf(anchor.x + sin(angle) * reach, -half_size, half_size)
	player.auto_patrol_z = clampf(anchor.y + cos(angle) * reach, -half_size, half_size)
	player.auto_rest_until = now + HUNT_PATROL_REST_MS


## 자동 사냥이 발을 옮기는 자리. 사람이 모는 입력(`input_move`)과 **같은 규칙**으로
## 움직인다 — 경계와 몬스터 충돌은 Movement 가 본다.
func _walk_auto(
	player: Dictionary, tx: float, tz: float, delta: float, now: int, stop_at: float
) -> void:
	# 휘두르는 동안에는 발을 멈춘다. 안 막으면 자동 사냥만 미끄러지면서 친다
	# (사람이 모는 쪽은 input_move 가 같은 자리에서 막는다)
	if now < int(player.rooted_until):
		return
	var to := Vector2(tx - player.x, tz - player.z)
	if to.length() <= stop_at:
		return
	var dir := to.normalized()
	Movement.apply_move(
		player, dir.x, dir.y, delta, half_size, _speed_of(player), _solids_near(player.x, player.z)
	)
	player.rot = atan2(dir.x, dir.y)


func _kill(player: Dictionary, target: Dictionary, now: int) -> void:
	# 하루 한 번인 던전의 몬스터는 **되살아나지 않는다** — 안에서 기다렸다 보스를 또 잡으면 하루 한 번이
	# 아니게 된다 (`respawn_at` 0 = 되살릴 것 없음, `_respawn` 이 건너뛴다). 서버도 같은 개체를 두 번 안 받는다
	var daily_dungeon := int(GameData.dungeon_type_of(zone_id).get("daily", 0)) > 0
	target.respawn_at = 0 if daily_dungeon else now + int(target.respawn_ms)

	# 보상(드롭·골드·경험치·레벨·전직 시험)은 장부가 굴린다 — `Ledger.kill`.
	# **종류·존·개체 id 만 보낸다** — 수치는 장부가 표에서 찾고, 서버는 id 를 제 명단에 대 본다
	_ledger_call(player, &"kill", [{"kind": str(target.kind), "zone": zone_id, "id": str(target.id)}])
	_count_run_kill(player, target, now)


## --- 던전 한 판 --- (docs/features/dungeons.md "결과창")

## 존을 열 때 — 던전 단계면 판을 연다. 시련은 들어온 순간부터 시계가 돈다 (서버도 `enter` 부터 센다)
func _start_run() -> void:
	_run = {}
	if zone_id == Sandbag.zone():
		_start_sandbag()
		return
	var stage := GameData.dungeon_stage(zone_id)
	if stage.is_empty():
		return
	var type := GameData.dungeon_type_of(zone_id)
	_run = {
		"zone": zone_id,
		"dungeon": str(type.get("id", "")),
		"name": str(type.get("name", "")),
		"stage": int(stage.get("stage", 0)),
		"skill_exp": int(stage.get("skillExp", 0)),
		"crystals": int(stage.get("crystals", 0)),
		"protein": int(stage.get("protein", 0)),
		"result": "",
	}
	if int(stage.get("kills", 0)) > 0:
		_run["dungeon"] = "trial"
		_run["need"] = int(stage.kills)
		_run["kills"] = 0
		_run["ends_at"] = Time.get_ticks_msec() + int(float(stage.get("seconds", 30)) * 1000.0)


## 한 마리 잡았다 — 토벌은 보스면 성공(스킬 경험치는 `Ledger.kill` 이 이미 줬다), 시련은 시간 안이면
## 세고 다 채우면 성공(크리스탈은 장부에 청한다)
func _count_run_kill(player: Dictionary, target: Dictionary, now: int) -> void:
	if _run.is_empty() or str(_run.result) != "" or str(_run.dungeon) == "sandbag":
		return
	if str(_run.dungeon) != "trial":
		if bool(target.get("boss", false)):
			_finish_run("clear")
		return
	if now >= int(_run.ends_at):
		return
	_run.kills = int(_run.kills) + 1
	if int(_run.kills) < int(_run.need):
		return
	_ledger_call(player, &"trial_clear", [zone_id])
	_finish_run("clear")


## 시련의 시간이 다 됐는데 못 채웠으면 실패
func _check_run_time(now: int) -> void:
	if _run.is_empty() or str(_run.result) != "" or not _run.has("ends_at") or now < int(_run.ends_at):
		return
	if str(_run.dungeon) == "sandbag":
		_finish_sandbag()
		return
	_finish_run("fail")


## --- 샌드백 랭킹전 --- (docs/features/sandbag.md)

## 존을 열 때 — 들어온 순간부터 카운트(3초)가 돌고, 끝나면 재는 시간(15초)이 돈다
func _start_sandbag() -> void:
	var now := Time.get_ticks_msec()
	var starts := now + Sandbag.countdown_ms()
	_run = {
		"zone": zone_id,
		"dungeon": "sandbag",
		"name": str(zone.get("name", "샌드백 랭킹전")),
		"stage": 0,
		"skill_exp": 0, "crystals": 0, "protein": 0,
		"damage": 0,
		"starts_at": starts,
		"ends_at": starts + Sandbag.play_ms(),
		"result": "",
	}


## 재는 시간 동안은 **저절로 친다** (2026-10-02 요청 "카운트 끝나면 자동으로 공격하도록") — 샌드백 존에는
## 자동사냥 단추가 없으므로 판정이 켠다. 매 틱 보는 것은 늦게 들어온 사람도 켜 주기 위해서다.
## 끄는 것은 `_finish_sandbag`, 존을 옮기면 `join` 이 끈다
func _drive_sandbag_auto(now: int) -> void:
	if str(_run.get("dungeon", "")) != "sandbag" or str(_run.result) != "" or now < int(_run.starts_at):
		return
	for id in _players:
		if not bool(_players[id].get("auto", false)):
			set_auto(id, true)


## 카운트 중인가 — 이 동안은 평타·스킬이 막힌다
func _counting_down(now: int) -> bool:
	return str(_run.get("dungeon", "")) == "sandbag" and str(_run.result) == "" and now < int(_run.starts_at)


## 샌드백에 넣은 피해를 센다 — 재는 시간 안에 들어간 것만
func _count_sandbag_damage(damage: int, now: int) -> void:
	if str(_run.get("dungeon", "")) != "sandbag" or str(_run.result) != "":
		return
	if now < int(_run.starts_at) or now >= int(_run.ends_at):
		return
	_run.damage = int(_run.damage) + damage


## 재는 시간이 끝났다 — 기록을 장부에 남기고 결과창을 띄운다. 실패는 없다(얼마를 넣든 기록이다).
## 장부가 기록을 남기기 전에 주가 지났는지 먼저 본다 — 지난 기록을 정산하지 않고 덮으면 보상이 사라진다
func _finish_sandbag() -> void:
	var damage := int(_run.damage)
	_check_sandbag_week(Time.get_ticks_msec(), true)
	var best := damage
	var new_best := false
	for id in _players:
		var mine: Dictionary = _players[id].get("sandbag", {})
		var before := int(mine.get("best", 0)) if int(mine.get("week", -1)) == _ledger.sandbag_week() else 0
		new_best = damage > before
		_ledger_call(_players[id], &"sandbag_record", [damage])
		# 로컬은 장부가 바로 고쳤다. 서버에 붙어 있으면 아직 옛 값이라 큰 쪽을 적는다 — 답(`sandbagRecord`)이 오면 창이 고친다
		best = maxi(maxi(before, damage), int(_players[id].get("sandbag", {}).get("best", 0)))
	_run.result = "clear"
	# 결과창 뒤로 계속 치지 않게 저절로 치던 것을 끈다 (`_drive_sandbag_auto`)
	for id in _players:
		set_auto(id, false)
	_events.append({
		"type": "dungeonResult", "dungeon": "sandbag", "name": _run.name, "stage": 0,
		"result": "clear", "kills": 0, "need": 0, "skill_exp": 0, "crystals": 0, "protein": 0,
		"damage": damage, "best": best, "new_best": new_best,
	})


var _next_week_check := 0

## 지금 주 번호 — 장부의 시계로 (테스트가 바꿔 끼운다)
func sandbag_week() -> int:
	return _ledger.sandbag_week()


## 장부의 시계를 바꿔 끼운다 (테스트 — 주를 넘긴다)
func set_unix_clock(clock: Callable) -> void:
	_ledger.unix_now = clock

## **주가 바뀌었으면 지난주를 정산한다** (로컬만) — 혼자 노는 판이라 순위는 늘 1위다.
## 서버에 붙어 있으면 서버가 모든 계정을 줄 세워 정산하므로 여기서는 안 한다 (`LedgerServer`).
## 1초에 한 번만 본다. `force` 면 바로 — 못 받은 보상(가방이 꽉 찼던 것) 다시 넣기도 이때만 해 본다
## (매초 해 보면 "가방이 가득 차…" 가 매초 뜬다). 존을 옮길 때·불러올 때·판이 끝날 때 부른다
func _check_sandbag_week(now: int, force := false) -> void:
	if remote != null or (not force and now < _next_week_check):
		return
	_next_week_check = now + 1000
	var week := _ledger.sandbag_week()
	for id in _players:
		var player: Dictionary = _players[id]
		var mine: Dictionary = player.get("sandbag", {})
		if not mine.is_empty() and int(mine.get("week", week)) < week:
			_ledger_call(player, &"sandbag_close_week", [1])
		elif force and mine.has("unpaid"):
			_ledger_call(player, &"sandbag_pay")


## 던전에서 쓰러졌다 — 어느 던전이든 실패
func _fail_run_on_death() -> void:
	if not _run.is_empty() and str(_run.result) == "":
		_finish_run("fail")


## 결과를 굳히고 결과창이 그릴 것을 내보낸다 — 보상은 성공일 때만(실패면 0)
func _finish_run(result: String) -> void:
	_run.result = result
	var clear := result == "clear"
	_events.append({
		"type": "dungeonResult", "dungeon": _run.dungeon, "name": _run.name, "stage": _run.stage,
		"result": result, "kills": int(_run.get("kills", 0)), "need": int(_run.get("need", 0)),
		"skill_exp": int(_run.skill_exp) if clear else 0,
		"crystals": int(_run.crystals) if clear else 0,
		# 프로틴 세 종 **각각** 이만큼 — 토벌은 `Ledger._check_dungeon_clear`, 시련은 `trial_clear` 가 이미 줬다
		"protein": int(_run.protein) if clear else 0,
	})


## 죽은 몬스터를 제 시간에 되살린다
func _respawn(now: int) -> void:
	for monster in _monsters:
		if int(monster.hp) > 0 or int(monster.respawn_at) == 0:
			continue
		if now < int(monster.respawn_at):
			continue
		monster.hp = monster.max_hp
		monster.respawn_at = 0
		monster.stunned_until = 0
		monster.pull_until = 0
		monster.hit_at = 0
		# **죽기 전 대상을 잊는다** (2026-09-29). 안 비우면 대상 유지 조건이 "리쉬 안" 이라
		# 어그로(3m) 밖에 선 죽인 사람에게 되살아나자마자 달려간다
		monster.target = ""
		monster.state = "idle"
		# 죽은 자리에서 다시 선다. 집에서 멀면 다음 틱의 리쉬 검사가 도로 켠다
		monster.leashing = false


## Transport 가 비워 간다. 여기서 비우지 않으면 계속 쌓인다
func drain_events() -> Array:
	var out := _events
	_events = []
	return out


## 몬스터 상태 기계: idle -> (사람이 다가옴) chase -> (사거리 도달) attack.
## server/src/combat.ts 의 stepMonsters 이식본이다.
##
## 보스의 범위 공격(aoe)은 아직 안 옮겼다 — 예고 원을 그리는 화면이 필요해서
## UI 단계와 같이 한다.
func _step_monsters(delta: float, now: int) -> void:
	_fill_grid()
	for monster in _monsters:
		if int(monster.hp) <= 0 or bool(monster.get("dummy", false)):
			continue

		# --- 휘두른 손이 닿는 순간 --- 휘두르기를 알린 뒤 `MONSTER_HIT_DELAY_MS` 가 지나야 피해가
		# 들어간다 (화면의 할퀴기 정점과 같은 순간). 기절·끌려오기에 걸리면 아래에서 취소된다
		if int(monster.get("hit_at", 0)) != 0 and now >= int(monster.hit_at):
			monster.hit_at = 0
			_land_swing(monster)

		# --- 범위 공격을 예고해 둔 상태 ---
		# 예고한 뒤에는 **그 자리에 선다.** 원은 시전을 시작한 자리에 고정돼 있으므로
		# 여기서 따라 움직이면 표시와 터지는 자리가 어긋나 붙어 있는 쪽은 피할 방법이
		# 없다. 리쉬·대상 재탐색보다 먼저 보는 이유도 같다 — 한번 예고한 것은 대상이
		# 도망가든 죽든 그대로 터진다.
		if int(monster.burst_at) != 0:
			monster.state = "cast"
			if now >= int(monster.burst_at):
				monster.burst_at = 0
				monster.rooted_until = now + Combat.monster_root_ms(float(monster.attack_cooldown))
				_burst_aoe(monster)
			continue

		# **끌려오는 중** (무적파쇄권 흡인) — 못 움직이고 못 때린다. 기절처럼 예고한 범위 공격
		# 뒤에 본다 (예고한 놈은 `_pull_in` 이 애초에 안 끈다). 마지막 틱에 도착점에 딱 놓는다
		if int(monster.get("pull_until", 0)) != 0:
			var span := maxf(1.0, float(int(monster.pull_until) - int(monster.pull_start)))
			var t := clampf(float(now - int(monster.pull_start)) / span, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			monster.x = lerpf(float(monster.pull_from_x), float(monster.pull_to_x), t)
			monster.z = lerpf(float(monster.pull_from_z), float(monster.pull_to_z), t)
			if now < int(monster.pull_until):
				monster.state = "stun"
				monster.hit_at = 0
				continue
			monster.pull_until = 0

		# **기절** — 못 움직이고 못 때린다. 예고한 범위 공격(위)보다 뒤에 본다:
		# 한번 예고한 것은 그대로 터진다는 규칙을 기절도 깨지 않는다
		if now < int(monster.get("stunned_until", 0)):
			monster.state = "stun"
			# 휘두르다 기절하면 그 한 대는 안 들어간다
			monster.hit_at = 0
			continue

		# 휘두르는 동안은 못 움직인다. 화면이 공격 클립을 보여 주는 창과 같은 길이다
		if now < int(monster.rooted_until):
			continue

		var home_gap := Vector2(monster.x - monster.home_x, monster.z - monster.home_z).length()

		# --- 집으로 돌아가는 중 ---
		# **도착할 때까지 아무도 안 쫓는다.** 한 걸음 걷고 리쉬 안으로 들어오자마자
		# 대상을 다시 찾으면 경계에서 앞뒤로 떤다 (2026-09-20 에 지적받았다)
		if bool(monster.get("leashing", false)):
			if home_gap <= PATROL_ARRIVE:
				monster.leashing = false
				monster.state = "idle"
				continue
			monster.state = "chase"
			_move_monster(monster, monster.home_x, monster.home_z, float(monster.speed), delta)
			continue

		# 집에서 너무 멀어졌으면 쫓기를 포기하고 **체력을 채워** 돌아간다.
		# 깎아 놓고 도망친 놈을 다음에 만났을 때 반피로 서 있으면, 리쉬 밖에서
		# 때렸다 빠지기를 되풀이해 위험 없이 잡을 수 있다
		if home_gap > float(monster.leash):
			monster.leashing = true
			monster.target = ""
			monster.hp = monster.max_hp
			monster.state = "chase"
			_move_monster(monster, monster.home_x, monster.home_z, float(monster.speed), delta)
			continue

		var target: Dictionary = _players.get(str(monster.target), {})
		if not target.is_empty():
			var gap := Vector2(target.x - monster.x, target.z - monster.z).length()
			if bool(target.get("dead", false)) or gap > float(monster.leash):
				target = {}
				monster.target = ""
		if target.is_empty():
			target = _nearest_player(monster.x, monster.z, float(monster.aggro))
			monster.target = str(target.get("id", ""))

		if target.is_empty():
			_patrol(monster, home_gap, delta, now)
			continue

		var dist := Vector2(target.x - monster.x, target.z - monster.z).length()

		# --- 범위 공격 걸기 (보스) ---
		# 평타 사거리가 아니라 **원 안**에 들어오면 건다. 그래야 "보스 7m 안은
		# 위험하다"는 한 줄로 설명되고, 멀리서 쏘는 직업은 자기 사거리를 지키는
		# 것만으로 자연히 피한다.
		var aoe: Dictionary = monster.aoe
		if not aoe.is_empty() and now >= int(monster.next_aoe_at) and dist <= float(aoe.radius):
			monster.next_aoe_at = now + int(aoe.cooldownMs)
			monster.burst_at = now + int(aoe.windupMs)
			monster.aoe_x = monster.x
			monster.aoe_z = monster.z
			monster.state = "cast"
			monster.rot = atan2(target.x - monster.x, target.z - monster.z)
			_events.append({
				"type": "aoe",
				"id": monster.id,
				"x": monster.aoe_x,
				"z": monster.aoe_z,
				"radius": float(aoe.radius),
				"delay_ms": int(aoe.windupMs),
			})
			continue

		if dist > float(monster.attack_range):
			monster.state = "chase"
			_chase_monster(monster, target.x, target.z, delta)
			continue

		monster.state = "attack"
		monster.rot = atan2(target.x - monster.x, target.z - monster.z)
		if now >= int(monster.next_attack_at):
			monster.next_attack_at = now + int(monster.attack_cooldown)
			monster.rooted_until = now + Combat.monster_root_ms(float(monster.attack_cooldown))
			# 휘두르기부터 알리고 **피해는 손이 닿는 순간에** (위 `hit_at`) — 전에는 여기서 바로
			# 때려서 화면의 할퀴기보다 숫자가 0.2초 먼저 떴다 (2026-09-30)
			monster.hit_at = now + Combat.monster_hit_delay_ms()
			monster.hit_target = str(target.get("id", ""))
			_events.append({"type": "mobSwing", "id": monster.id})


## 쫓을 사람이 없을 때. 집 주변에서 한 다리 걷고 잠시 쉰다 (idle ↔ patrol).
##
## 돌아다니게 한 이유는 **선 채로 굳어 있으면 죽은 것처럼 보이기** 때문이다.
## 반경을 어그로보다 작게 둔 것은 순찰이 사람을 먼저 찾아가지 않게 하려는 것이고,
## 쉬는 시간을 놈마다 다르게 뽑는 것은 무리가 한 몸처럼 움직이지 않게 하려는 것이다.
func _patrol(monster: Dictionary, home_gap: float, delta: float, now: int) -> void:
	# 쫓다가 대상을 잃고 멀리 나와 있으면 먼저 집으로 걸어 돌아온다.
	# 서성이는 속도로 오면 한참 걸려서 반 속도로 온다
	if home_gap > PATROL_RADIUS:
		monster.state = "patrol"
		monster.patrol_x = monster.home_x
		monster.patrol_z = monster.home_z
		monster.patrol_rest_until = 0
		_move_monster(monster, monster.home_x, monster.home_z, float(monster.speed) * 0.5, delta)
		return

	if now < int(monster.patrol_rest_until):
		monster.state = "idle"
		return

	var gap := Vector2(float(monster.patrol_x) - monster.x, float(monster.patrol_z) - monster.z).length()
	if gap > PATROL_ARRIVE:
		monster.state = "patrol"
		_move_monster(monster, monster.patrol_x, monster.patrol_z, float(monster.speed) * PATROL_SPEED, delta)
		return

	# 다 걸었다. 집 반경 안에서 다음 자리를 뽑고 쉰다
	var angle := _rng.randf() * TAU
	var reach := _rng.randf_range(PATROL_RADIUS * 0.4, PATROL_RADIUS)
	monster.patrol_x = clampf(float(monster.home_x) + sin(angle) * reach, -half_size, half_size)
	monster.patrol_z = clampf(float(monster.home_z) + cos(angle) * reach, -half_size, half_size)
	monster.patrol_rest_until = now + _rng.randi_range(PATROL_REST_MIN_MS, PATROL_REST_MAX_MS)
	monster.state = "idle"


## 어그로 범위 안에서 가장 가까운 산 사람
func _nearest_player(x: float, z: float, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := reach
	for id in _players:
		var player: Dictionary = _players[id]
		if bool(player.get("dead", false)):
			continue
		var dist := Vector2(player.x - x, player.z - z).length()
		if dist <= best_dist:
			best_dist = dist
			best = player
			best["id"] = id
	return best


## 사람을 쫓는 한 걸음. 길이 막혔으면 **옆으로 한 칸씩** 돌아간다.
##
## 1. 우회 중이면 정해 둔 방향으로 한 칸(`DETOUR_STEP`)을 마저 간다.
## 2. 아니면 곧장 한 걸음. 밀려서 거의 못 나갔으면 막힌 것이다.
## 3. 막혔으면 45° → 90° → 135° 순으로 옆 방향을 대 보고, 처음 뚫린 쪽으로
##    한 칸 우회를 시작한다. **돌던 쪽(`detour_side`)을 먼저 본다** — 줄지어 선 무리를
##    돌 때 왼쪽·오른쪽을 번갈아 고르면 그 앞에서 지그재그만 한다.
## 4. 사방이 다 막혔으면 예전처럼 사람 쪽으로 밀어 본다 (둘러싸였을 때).
##
## 순찰·귀환에는 안 쓴다 — 거기서는 좀 밀려 늦게 도착해도 티가 나지 않는다
func _chase_monster(monster: Dictionary, tx: float, tz: float, delta: float) -> void:
	var ahead := Vector2(tx - monster.x, tz - monster.z)
	if ahead.length() < 1e-3:
		return
	ahead = ahead.normalized()
	var step_len := float(monster.speed) * delta

	if float(monster.get("detour_left", 0.0)) > 0.0:
		var way := Vector2(float(monster.detour_x), float(monster.detour_z))
		if _try_step(monster, way, delta):
			monster.detour_left = float(monster.detour_left) - step_len
			return
		# 돌던 길도 막혔다 — 아래에서 다시 고른다
		monster.detour_left = 0.0
	elif _try_step(monster, ahead, delta):
		return

	# 처음 막혔으면 놈마다 다른 쪽을 먼저 본다. 한 사람에게 몰린 무리가
	# 전부 같은 쪽으로 돌면 그쪽에서 또 막힌다
	var side := int(monster.get("detour_side", 0))
	if side == 0:
		side = 1 if sin(float(monster.push_angle)) >= 0.0 else -1
	for s in [side, -side]:
		for turn in DETOUR_TURNS:
			var way := ahead.rotated(s * float(turn))
			if _try_step(monster, way, delta):
				monster.detour_side = s
				monster.detour_x = way.x
				monster.detour_z = way.y
				monster.detour_left = DETOUR_STEP - step_len
				return

	_move_monster(monster, tx, tz, float(monster.speed), delta)


## `way` 쪽으로 한 걸음 가 본다. 밀려서 `DETOUR_BLOCKED` 만큼도 못 나갔으면
## **제자리로 되돌리고** false. 미는 것은 이 놈 자신뿐이라 되돌리기가 깨끗하다
func _try_step(monster: Dictionary, way: Vector2, delta: float) -> bool:
	var x0: float = monster.x
	var z0: float = monster.z
	var rot0: float = monster.rot
	var step_len := float(monster.speed) * delta
	_move_monster(monster, x0 + way.x * DETOUR_STEP, z0 + way.y * DETOUR_STEP, float(monster.speed), delta)
	var moved := Vector2(float(monster.x) - x0, float(monster.z) - z0)
	if moved.dot(way) >= step_len * DETOUR_BLOCKED:
		return true
	monster.x = x0
	monster.z = z0
	monster.rot = rot0
	return false


## 몬스터끼리도 통과하지 않는다. **미는 쪽은 지금 움직인 이 놈**이다 —
## 캐릭터 충돌과 같은 규칙이라 서 있는 놈은 제자리를 지킨다
func _move_monster(monster: Dictionary, tx: float, tz: float, speed: float, delta: float) -> void:
	var dx: float = tx - monster.x
	var dz: float = tz - monster.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 1e-3:
		return

	var step_len := minf(dist, speed * delta)
	monster.x = clampf(monster.x + (dx / dist) * step_len, -half_size, half_size)
	monster.z = clampf(monster.z + (dz / dist) * step_len, -half_size, half_size)
	monster.rot = atan2(dx, dz)

	# 움직인 놈만 민다. 서 있는 80마리까지 매 프레임 밀면 폰에서 버겁다.
	# 이웃은 **격자에서 둘레 아홉 칸만** 본다 (`_fill_grid`)
	var near: Array = []
	var cx := floori(float(monster.x) / NEAR)
	var cz := floori(float(monster.z) / NEAR)
	for gx in range(cx - 1, cx + 2):
		for gz in range(cz - 1, cz + 2):
			for other in _grid.get(Vector2i(gx, gz), []):
				if is_same(other, monster) or int(other.hp) <= 0:
					continue
				if absf(other.x - monster.x) > NEAR or absf(other.z - monster.z) > NEAR:
					continue
				near.append(other)
	Movement.push_out_of_solids(
		monster, near, half_size, float(monster.r), float(monster.push_angle)
	)


## 살아 있는 몬스터를 `NEAR` 크기 칸에 나눠 담는다 — 몬스터 틱마다 한 번.
##
## 움직이는 놈마다 서로 밀어내려고 이웃을 찾는데, 예전에는 **사냥터 전체(201마리)를
## 매번 훑었다.** 무리 한가운데서 그것만 프레임당 1.1ms 였다 (2026-09-23 재 보니
## 몬스터 틱 1.7ms 중). 옛 서버의 `spatialGrid.ts` 와 같은 생각이다.
## 칸은 프레임 처음 자리로 나누지만 한 프레임에 움직이는 거리는 수 cm 이고,
## 미는 판정은 1m 안팎이라 찾는 범위(4m) 안에서 빠지는 놈이 없다
func _fill_grid() -> void:
	_grid.clear()
	for monster in _monsters:
		if int(monster.hp) <= 0:
			continue
		var cell := Vector2i(floori(float(monster.x) / NEAR), floori(float(monster.z) / NEAR))
		var bucket: Array = _grid.get_or_add(cell, [])
		bucket.append(monster)


## 휘두른 손이 닿았다. 대상이 그새 죽었거나 사거리(+`SWING_REACH_SLACK`) 밖으로 빠졌으면 빗나간다
func _land_swing(monster: Dictionary) -> void:
	var target: Dictionary = _players.get(str(monster.get("hit_target", "")), {})
	if target.is_empty() or bool(target.get("dead", false)):
		return
	var gap := Vector2(target.x - monster.x, target.z - monster.z).length()
	if gap > float(monster.attack_range) + SWING_REACH_SLACK:
		return
	_hit_player(target, monster)


## attack 을 따로 받는 것은 범위 공격이 평타의 power 배로 때리기 때문이다
func _hit_player(player: Dictionary, monster: Dictionary, attack: float = -1.0) -> void:
	var power := float(monster.attack) if attack < 0.0 else attack
	# **공격자 레벨로 K 를 뽑는다** — 높은 사냥터 몬스터가 때리면 내 방어력 효율이
	# 자동으로 떨어진다. 레벨차 보정 시스템이 따로 필요 없는 이유다 (설계 1장)
	# 맞는 쪽 K(`damage_taken`) — 후반 감소율이 90% 대까지 올라 방어가 생존을 맡는다
	var damage := roundi(Stats.damage_taken(power, int(monster.get("level", 1)), float(player.stats.defense)))
	if bool(player.get("invincible", false)):
		damage = 0
	player.hp = maxi(0, int(player.hp) - damage)
	_events.append({
		"type": "hit",
		"target": str(player.get("id", "")),
		"target_kind": "player",
		"source": monster.id,
		"amount": damage,
		"crit": false,
		"killed": int(player.hp) <= 0,
		"x": player.x,
		"z": player.z,
	})

	if int(player.hp) <= 0:
		# **시간이 지나도 저절로 살아나지 않는다.** 사람이 사망 화면을 눌러야 한다 —
		# 5초 뒤 제자리에서 일으켜 세우면 죽은 걸 읽기도 전에 화면이 사라진다
		player["dead"] = true
		monster.target = ""
		_events.append({"type": "died"})
		_fail_run_on_death()


## 사망 화면을 눌렀다. 마을에서 되살아난다
func revive(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not bool(player.get("dead", false)):
		return
	if zone_id != GameData.start_zone():
		open(GameData.start_zone())
	join(player_id)
	var player_now: Dictionary = _players[player_id]
	player_now["dead"] = false
	player_now["hp"] = player_now.stats.maxHp
	_events.append({"type": "revived"})


## 예고해 둔 원이 터진다. **원 안에 서 있는 사람만** 맞는다 —
## 예고를 보고 뛰어나갔으면 안 맞아야 하고, 화면에 그린 원과 판정이 같아야 한다
func _burst_aoe(monster: Dictionary) -> void:
	var aoe: Dictionary = monster.aoe
	if aoe.is_empty():
		return
	var radius := float(aoe.radius)
	var power := float(aoe.power)
	for id in _players:
		var player: Dictionary = _players[id]
		if bool(player.get("dead", false)):
			continue
		var gap := Vector2(player.x - float(monster.aoe_x), player.z - float(monster.aoe_z)).length()
		if gap > radius:
			continue
		_hit_player(player, monster, roundi(float(monster.attack) * power))
	# 터지는 순간 휘두른다 (평타와 같은 할퀴기)
	_events.append({"type": "mobSwing", "id": monster.id})


## 몬스터 한 마리를 만든다. **스폰과 테스트가 같은 함수를 쓴다** —
## 테스트가 손으로 만들면 여기 칸을 더할 때마다 조용히 어긋난다 (실제로 그랬다).
static func make_monster(
	id: String,
	kind: Dictionary,
	x: float,
	z: float,
	respawn_ms: float,
	push_angle: float,
) -> Dictionary:
	var scale := float(kind.get("scale", 1.0))
	return {
		"id": id,
		"kind": kind.id,
		"x": x,
		"z": z,
		"rot": 0.0,
		"r": Movement.monster_radius(scale),
		"scale": scale,
		"color": kind.get("bodyColor", "#888888"),
		"boss": bool(kind.get("boss", false)),
		# 과녁(샌드백) — 안 죽고 안 움직이고 안 때린다. 맞은 피해는 판이 센다 (`_hit_monster`)
		"dummy": bool(kind.get("dummy", false)),
		"level": int(kind.get("level", 1)),
		"max_hp": int(kind.get("maxHp", 1)),
		"hp": int(kind.get("maxHp", 1)),
		"defense": float(kind.get("defense", 0)),
		# 치명타 저항 — 때리는 쪽 치확에서 뺀다 (100레벨 사냥터부터, 보스도 같은 값)
		"crit_resist": float(kind.get("critResist", 0.0)),
		"exp_reward": float(kind.get("expReward", 0)),
		"respawn_ms": respawn_ms,
		# 죽어 있는 동안 다시 나올 시각. 0 이면 살아 있다
		"respawn_at": 0,
		# --- 반격 ---
		"attack": float(kind.get("attack", 1)),
		"attack_range": float(kind.get("attackRange", 1.9)),
		"attack_cooldown": float(kind.get("attackCooldown", 1200)),
		"aggro": float(kind.get("aggroRange", 9)),
		"leash": float(kind.get("leashRange", 22)),
		"speed": float(kind.get("moveSpeed", 3.6)),
		# 집. 너무 멀어지면 여기로 돌아온다
		"home_x": x,
		"home_z": z,
		# 집으로 돌아가는 중인가. 돌아가는 동안은 아무도 안 쫓는다 (_step_monsters)
		"leashing": false,
		"target": "",
		"state": "idle",
		# --- 순찰 --- 쫓을 사람이 없을 때 걸어갈 자리와, 다음 다리를 시작할 시각.
		# 처음에는 제자리·0 이라 첫 판정에서 곧바로 목적지를 뽑고 쉬기 시작한다
		"patrol_x": x,
		"patrol_z": z,
		"patrol_rest_until": 0,
		"next_attack_at": 0,
		"rooted_until": 0,
		# 휘두른 손이 닿는 시각과 그때 맞을 사람. 0 이면 휘두르는 중이 아니다 (`_land_swing`)
		"hit_at": 0,
		"hit_target": "",
		# 기절이 풀리는 시각 (스킬 강화 — 낙뢰 기절). 그때까지 못 움직이고 못 때린다
		"stunned_until": 0,
		# 끌려오는 중 (무적파쇄권 흡인) — 이 시각까지 `pull_*` 의 두 점 사이를 옮겨진다 (`_pull_in`)
		"pull_until": 0,
		# 기절이 어떻게 보이나 — `ice` 면 화면이 몸을 얼음빛으로 굳힌다 (빙주각 빙결)
		"stun_look": "",
		# 정확히 겹쳤을 때 밀려날 방향. **서로 달라야 풀린다**
		"push_angle": push_angle,
		# --- 우회 --- 쫓는 길이 막혔을 때 옆으로 도는 방향과 남은 거리,
		# 돌던 쪽(+1/-1, 0 은 아직 안 막혀 봤다). `_chase_monster` 가 쓴다
		"detour_x": 0.0,
		"detour_z": 0.0,
		"detour_left": 0.0,
		"detour_side": 0,
		# --- 보스 범위 공격 (없는 몬스터는 aoe 가 비어 있다) ---
		"aoe": kind.get("aoe", {}),
		"next_aoe_at": 0,
		# 예고해 둔 것이 터질 시각. 0 이면 시전 중이 아니다
		"burst_at": 0,
		"aoe_x": 0.0,
		"aoe_z": 0.0,
	}


## 저장한 것이 있으면 그 자리에서 이어서 시작한다.
## **없으면 아무 일도 하지 않는다** — 부르는 쪽이 이미 기본값으로 만들어 뒀다.
func restore(player_id: String) -> bool:
	var saved := Save.read()
	if saved.is_empty():
		return false

	var zone_saved := str(saved.get("zone", ""))
	var all: Dictionary = GameData.zones().get("zones", {})
	# **하루 한 번인 던전 안에서 끝냈으면 그 자리로 돌아가지 않는다** — 다시 열면 몬스터가 새로 서서
	# 입장을 안 쓰고 한 판을 더 하게 된다. 그 판은 들어갈 때 이미 셌다 (dungeons.md "하루 한 번")
	var daily_dungeon := int(GameData.dungeon_type_of(zone_saved).get("daily", 0)) > 0
	if all.has(zone_saved) and zone_saved != zone_id and not daily_dungeon:
		open(zone_saved)
	join(player_id)

	var player: Dictionary = _players[player_id]
	player.level = int(saved.get("level", 1))
	player.stats = Combat.stats_for(str(player.job), player.level)
	player.exp = int(saved.get("exp", 0))
	player.hp = clampi(int(saved.get("hp", player.stats.maxHp)), 0, int(player.stats.maxHp))
	player.gold = int(saved.get("gold", 0))
	player["dead"] = bool(saved.get("dead", false))
	# 배운 스킬은 표가 바뀌어도 살아남게 **지금 있는 것만** 되살린다 —
	# 스킬을 다시 만드는 중이라 없어진 id 가 저장에 남아 있을 수 있다
	var known := Skills.all()
	var learned: Array = []
	for id in saved.get("skills", []):
		if known.has(str(id)):
			learned.append(str(id))
	player.skills = learned
	player.skill_points = int(saved.get("skill_points", 0))
	# 패시브도 **지금 있는 것만**, 끝 단계 안으로 되살린다
	var ranks := {}
	var raw_passives = saved.get("passives", {})
	if raw_passives is Dictionary:
		for p in Skills.passives_for(str(player.job)):
			var rank := clampi(int(raw_passives.get(str(p.id), 0)), 0, int(p.maxRank))
			if rank > 0:
				ranks[str(p.id)] = rank
	player.passives = ranks
	# 숨긴 스킬(`hidden`, 직업 목록에 없는 것)은 액션바에서만 뺀다 — 배운 기록은 남겨 둬서
	# 숨김을 풀면 스킬창에서 다시 올리면 된다
	var listed := Skills.for_job(str(player.job))
	var bar: Array = []
	for id in saved.get("skill_bar", []):
		if str(id) in learned and str(id) in listed:
			bar.append(str(id))
	player.skill_bar = bar
	player.granted = saved.get("granted", []).duplicate()
	player.name = str(saved.get("name", "")) if Names.valid(str(saved.get("name", ""))) else ""
	# 강화도 **지금 표에 있는 것만** 되살린다 — 없던 칸이라 옛 저장은 빈 사전이다
	var upgraded: Dictionary = {}
	var raw_upgrades = saved.get("skill_upgrades", {})
	if typeof(raw_upgrades) == TYPE_DICTIONARY:
		for skill_id in raw_upgrades:
			var kept_ids: Array = []
			for id in raw_upgrades[skill_id]:
				if not Skills.upgrade(str(skill_id), str(id)).is_empty() and not (str(id) in kept_ids):
					kept_ids.append(str(id))
			if not kept_ids.is_empty():
				upgraded[str(skill_id)] = kept_ids
	player.skill_upgrades = upgraded
	# 쌓인 경험치도 **지금 표에 있고 아직 안 붙은 것만** — 없던 칸이라 옛 저장은 빈 사전
	var progress: Dictionary = {}
	var raw_exp = saved.get("skill_upgrade_exp", {})
	if typeof(raw_exp) == TYPE_DICTIONARY:
		for skill_id in raw_exp:
			if typeof(raw_exp[skill_id]) != TYPE_DICTIONARY:
				continue
			for id in raw_exp[skill_id]:
				var amount := int(raw_exp[skill_id][id])
				if amount > 0 and not Skills.upgrade(str(skill_id), str(id)).is_empty() \
						and not (str(id) in upgraded.get(str(skill_id), [])):
					progress.get_or_add(str(skill_id), {})[str(id)] = amount
	player.skill_upgrade_exp = progress
	# 아직 안 넣은 스킬 경험치 — 없던 칸이라 옛 저장은 0. 옛 경험치북은 표에 없어 가방에서 버려진다
	player.skill_exp = maxi(0, int(saved.get("skill_exp", 0)))
	# 헬스 — 없던 칸이라 옛 저장은 빈 사전. **지금 표에 있는 운동·프로틴만**, 단계는 끝 단계 안으로
	var raw_proteins = saved.get("proteins", {})
	var raw_fitness = saved.get("fitness", {})
	var proteins := {}
	var stages := {}
	for kind in Fitness.kinds():
		if raw_proteins is Dictionary and int(raw_proteins.get(str(kind.protein), 0)) > 0:
			proteins[str(kind.protein)] = int(raw_proteins[str(kind.protein)])
		if raw_fitness is Dictionary and int(raw_fitness.get(str(kind.id), 0)) > 0:
			stages[str(kind.id)] = clampi(int(raw_fitness[str(kind.id)]), 0, Fitness.max_stage())
	player.proteins = proteins
	player.fitness = stages
	# 장비 도감 — 없던 칸이라 옛 저장은 빈 사전. 표에 있는 장비 id 만, 비트는 +0 ~ +9 안으로
	player.codex = Codex.clean(saved.get("codex", {}))
	# 샌드백 랭킹전 — 없던 칸이라 옛 저장은 빈 사전. 주가 지났으면 `_check_sandbag_week` 가 정산한다
	var raw_sandbag: Variant = saved.get("sandbag", {})
	player.sandbag = Ledger.from_json(raw_sandbag) if raw_sandbag is Dictionary else {}
	# 던전 하루 입장 — 없던 칸이라 옛 저장은 빈 사전
	var raw_entries: Variant = saved.get("dungeon_entries", {})
	player.dungeon_entries = Ledger.from_json(raw_entries) if raw_entries is Dictionary else {}
	# 물약을 저절로 마시는 기준 — 없던 칸이라 옛 저장은 처음 값으로 읽힌다
	set_potion_pct(player_id, int(saved.get("potion_pct", player.potion_pct)))

	# 가방·장비도 되살린다. **옛 id 는 지금 id 로 옮긴다** (2026-09-21 에 단계 축을
	# 없앴다) — 갈 자리가 없는 것만 버린다. 등급은 아이템이 들고 있으므로
	# 저장값이 아니라 표에서 가져온다
	var bag: Array = []
	for stack in saved.get("bag", []):
		var moved := _restore_stack(stack)
		if not moved.is_empty():
			bag.append(moved)
	player.bag = bag
	var worn: Dictionary = {}
	for slot in saved.get("equipped", {}):
		var moved := _restore_stack(saved.equipped[slot])
		if not moved.is_empty():
			worn[str(slot)] = moved
	player.equipped = worn
	# 장비까지 넣고 나서 스탯을 만든다. 체력 상한이 장비에 걸려 있다
	_refresh_stats(player)
	player.hp = clampi(int(saved.get("hp", player.stats.maxHp)), 0, int(player.stats.maxHp))

	# 죽은 채로 저장됐으면 자리는 스폰으로 둔다 — 시체 자리에서 시작할 이유가 없다
	if not player.dead:
		player.x = clampf(float(saved.get("x", player.x)), -half_size, half_size)
		player.z = clampf(float(saved.get("z", player.z)), -half_size, half_size)
	# 꺼 둔 사이 주가 바뀌었으면 지난주 샌드백 기록을 정산한다 (로컬만)
	_check_sandbag_week(Time.get_ticks_msec(), true)
	return true


## 저장된 물건 하나를 지금 표에 맞춘다. 갈 자리가 없으면 빈 사전을 준다
func _restore_stack(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var stack: Dictionary = (raw as Dictionary).duplicate(true)
	# 재료(크리스탈)는 id 와 개수만 있다
	if Items.is_material(str(stack.get("id", ""))):
		var count := int(stack.get("count", 0))
		return {"id": str(stack.id), "count": count} if count > 0 else {}
	var id := Items.migrate_id(str(stack.get("id", "")))
	if id.is_empty():
		return {}
	stack.id = id
	stack.grade = int(Items.get_item(id).get("grade", 1))
	Items.clamp_options(stack)
	return stack


func save(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if not player.is_empty():
		Save.write(zone_id, player)


## NPC 에게 말을 건다. **거리는 여기서 다시 잰다.**
## 화면이 창을 열어 뒀다고 되는 게 아니다 (NPC_REACH).
func npc_open(player_id: String, npc_name: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or bool(player.dead):
		return

	for npc in zone.get("npcs", []):
		if str(npc.get("name", "")) != npc_name:
			continue
		var gap := Vector2(player.x - float(npc.x), player.z - float(npc.z)).length()
		if gap > NPC_REACH:
			_events.append({"type": "notice", "text": "너무 멉니다"})
			return
		var role := str(npc.get("role", ""))
		var listed: Array = []
		match role:
			"shop":
				listed = Items.shop_stock(str(player.job), int(player.level))
		var event := {
			"type": "npc",
			"name": npc_name,
			"role": role,
			"title": str(npc.get("title", "")),
			"items": listed,
		}
		_events.append(event)
		return


## 기본 공격이 닿는 정면 각도(라디안). 등 뒤의 적은 맞지 않는다
func _attack_arc() -> float:
	return float(GameData.combat().get("attackArc", PI * 0.6))


## 스킬을 배운다. **직업·레벨·포인트를 여기서 다시 본다.**
func learn_skill(player_id: String, skill_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"learn_skill", [skill_id])


## 패시브 한 단계를 배운다 (스킬창 [습득]). **직업·레벨·끝 단계를 장부가 다시 본다** —
## 값은 없다. 스탯은 `_after_ledger` 가 다시 만든다 (공속이 곧바로 붙는다)
func learn_passive(player_id: String, passive_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"learn_passive", [passive_id])


## 테스트 스위치(쿨타임 0 · 레벨 잠금 해제)를 켜고 끈다. 이름은 Skills.SWITCHES 만 받는다
func set_test_switch(name: String, on: bool) -> void:
	if not Skills.set_switch(name, on):
		return
	var label := "쿨타임 0" if name == "cooldownOff" else "레벨 잠금 해제"
	_events.append({"type": "notice", "text": "%s %s" % [label, "켬" if on else "끔"]})


## 물약 수치 — `combat.json` 의 `potion*` (shared `combat.ts`)
func _potion_rule(key: String, fallback: float) -> float:
	return float(GameData.combat().get(key, fallback))


## 물약을 마신다 — 물약 칸을 누르거나(`auto` 거짓) HP 가 기준 아래로 내려갔을 때(`_drive_potions`).
## 쿨타임(10초) 중이거나 HP 가 가득하면 안 마신다 — 가득 찬 채 마시면 쿨타임만 버린다
func drink_potion(player_id: String, auto := false) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or bool(player.dead):
		return
	var now := Time.get_ticks_msec()
	if now < int(player.get("potion_ready_at", 0)):
		if not auto:
			_events.append({"type": "notice", "text": "물약 쿨타임 %.1f초" % ((int(player.potion_ready_at) - now) / 1000.0)})
		return
	var max_hp := int(player.stats.maxHp)
	var before := int(player.hp)
	if before >= max_hp:
		if not auto:
			_events.append({"type": "notice", "text": "HP 가 가득 찼습니다"})
		return
	player.hp = mini(max_hp, before + maxi(1, roundi(max_hp * _potion_rule("potionHealRatio", 0.1))))
	player.potion_ready_at = now + int(_potion_rule("potionCooldownMs", 10000))
	# 회복기와 같은 "hit"(heal) 로 알린다 — 화면이 초록 숫자를 띄운다
	_events.append({
		"type": "hit",
		"target": player_id,
		"target_kind": "player",
		"amount": int(player.hp) - before,
		"heal": true,
		"crit": false,
		"killed": false,
		"x": player.x,
		"z": player.z,
	})
	_events.append({"type": "potion", "id": player_id, "auto": auto})


## 자동으로 마시는 기준(HP %). 설정 폭(10)에 맞춰 0 ~ 90 으로 자른다. 0 이면 끔
func set_potion_pct(player_id: String, pct: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var step := maxi(1, int(_potion_rule("potionAutoStep", 10)))
	player.potion_pct = clampi(roundi(float(pct) / step) * step, 0, int(_potion_rule("potionAutoMax", 90)))


## HP 가 기준 이하로 떨어진 사람에게 물약을 먹인다. 자동 사냥과 같이 **서버에서** 돈다 —
## 화면이 꺼져도(모바일) 마셔야 한다
func _drive_potions(now: int) -> void:
	for id in _players:
		var player: Dictionary = _players[id]
		var pct := int(player.get("potion_pct", 0))
		if pct <= 0 or bool(player.dead) or now < int(player.get("potion_ready_at", 0)):
			continue
		if float(player.hp) * 100.0 <= float(player.stats.maxHp) * pct:
			drink_potion(id, true)


## 테스트용 무적. 맞는 판정·이벤트는 그대로 두고 피해만 0 으로 만든다 (`_hit_player`)
func set_invincible(player_id: String, on: bool) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	player.invincible = on
	_events.append({"type": "notice", "text": "무적 %s" % ("켬" if on else "끔")})


## **디버그 — 시뮬레이터와 같은 조건을 게임에서 세운다.** ★
##
## 설계 문서 9장 5번이 요구한 것이다. 레벨과 "등급 g 풀세트 + 강화 n" 을 강제로
## 맞춰 놓으면, 화면에 찍히는 그룹 정리 시간·HP 손실을 설계표와 바로 대조할 수 있다.
## 수치로만 맞다고 믿었다가 화면이 다른 적이 여러 번이라, 재현 수단이 있어야 한다.
##
## 등급은 착용 레벨(1/31/61/…)에 가장 가까운 **단계**로 옮긴다 — 지금 카탈로그가
## 단계 20개 축이기 때문이다(설계의 56종 표로 갈아끼우면 이 변환이 사라진다).
## **테스트 — 무기(건틀릿)를 등급마다 하나씩 가방에 넣는다** (2026-09-23 요청).
## 등급별 아이콘이 제대로 붙는지 보려는 것이다. 옵션은 그 등급대로 굴린다
func debug_gauntlets(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var added := 0
	for grade in range(1, Stats.grade_count() + 1):
		var item := Items.get_item(Items.item_id(grade, "weapon"))
		if item.is_empty():
			continue
		# 강화도 등급 따라 +0 ~ +9 로 달리 준다 — 칸 오른쪽 아래 `+N` 을 보려고
		var stack := {
			"id": str(item.id), "grade": grade,
			"enhance": mini(Items.max_enhance(), roundi((grade - 1) * 1.5)),
			"options": Items.roll_options(item, grade, _rng),
		}
		if not _give(player, stack):
			break
		added += 1
	_events.append({"type": "inventory", "bag": player.bag, "equipped": player.equipped})
	_events.append({"type": "notice", "text": "테스트: 건틀릿 %d개를 넣었다" % added})


## **테스트 — 가방의 빈칸을 장비로 꽉 채운다** (2026-09-24 요청: "테스트하기 위해서 아이템을
## 인벤토리에 채워"). 강화 팝업의 다중 강화를 시험하려는 것이라 **같은 아이템이 여러 개**,
## 같은 등급에 부위가 여럿, **강화 단계가 섞여** 있어야 한다 — 42종(등급 7 × 부위 6)을
## 돌아가며 넣고, 한 바퀴 돌 때마다 강화를 한 단계씩(+0 ~ +4) 올린다. 옵션은 그 등급대로 굴린다
func debug_fill_bag(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var slots: Array = Items.slots()
	var kinds := Stats.grade_count() * slots.size()
	var added := 0
	while player.bag.size() < Items.bag_size():
		var grade := 1 + (added / slots.size()) % Stats.grade_count()
		var item := Items.get_item(Items.item_id(grade, str(slots[added % slots.size()])))
		if not item.is_empty():
			player.bag.append({
				"id": str(item.id), "grade": grade, "enhance": (added / kinds) % 5,
				"options": Items.roll_options(item, grade, _rng),
			})
		added += 1
		if added > Items.bag_size() * 2:
			break  # 표가 비어도 끝없이 돌지 않게
	_events.append({"type": "inventory", "bag": player.bag, "equipped": player.equipped})
	_events.append({"type": "notice", "text": "테스트: 가방을 채웠다 (%d칸)" % player.bag.size()})


## 한 번만 준다 — 받았으면 `granted` 에 `key` 가 남아 다음 접속에는 안 준다.
## 2026-09-23 요청 "가방에 30개 넣어" 로 크리스탈 30개를 이걸로 준다 (`LocalTransport.open`)
## 캐릭터 이름을 정한다 — 규칙(`Names`)에 안 맞으면 그대로 둔다. 서버에 붙으면 서버가 다시 거른다
func set_name(player_id: String, name: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if not player.is_empty() and Names.valid(name):
		player.name = name


func grant_once(player_id: String, key: String, stack: Dictionary) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"grant_once", [key, stack])


## **시작 장비** — 새 캐릭터에게 일반(1등급) 무기와 갑옷을 **끼운 채로** 준다 (2026-09-26 요청:
## "처음 캐릭터 생성시 일반 등급 무기랑 갑옷 지급해"). 부르는 쪽(`LocalTransport.open`)이
## **저장이 없을 때만** 부른다 — 이미 키우던 캐릭터에게는 안 준다. `granted` 의 `starterGear`
## 로 한 번만 준다. +0 이고 옵션은 드랍처럼 1등급대로 굴린다. 그 부위에 이미 낀 게 있으면 가방으로
func grant_starter_gear(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or "starterGear" in player.get("granted", []):
		return
	_ledger_call(player, &"grant_starter_gear")
	# 갑옷만큼 최대 HP 가 늘었다 — 새 캐릭터는 가득 찬 채로 시작한다
	if "starterGear" in player.granted:
		player.hp = int(player.stats.maxHp)


## **테스트 모드 꾸러미** — 모든 장비를 등급별로 하나씩(등급 7 × 부위 6 = 42개, 전부 +0)과
## 크리스탈 300개 (2026-09-26 요청: "테스트 모드에서는 인벤토리에서 모든 장비 등급별로 하나씩
## 넣어. 0강으로. 크리스탈로 300개 넣고"). 테스트 모드로 들어올 때 부른다(`game.gd` 의
## `_apply_play_mode`). **한 번만** 준다 — 매번 주면 들어올 때마다 가방이 42칸씩 는다.
## 가방에 다 안 들어가면 아무것도 안 넣고 다음에 다시 준다. 옵션은 드랍처럼 그 등급대로 굴린다
func grant_test_kit(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or "testKit" in player.get("granted", []):
		return
	var gear: Array = []
	for grade in range(1, Stats.grade_count() + 1):
		for slot in Items.slots():
			var item := Items.get_item(Items.item_id(grade, str(slot)))
			if not item.is_empty():
				gear.append({
					"id": str(item.id), "grade": grade, "enhance": 0,
					"options": Items.roll_options(item, grade, _rng),
				})
	var has_crystal: bool = player.bag.any(func(held: Dictionary) -> bool:
		return str(held.get("id", "")) == Items.crystal_id())
	if player.bag.size() + gear.size() + (0 if has_crystal else 1) > Items.bag_size():
		_notice("가방이 모자라 테스트 장비를 못 넣었다 — 비우고 다시 들어오면 넣는다")
		return
	player.bag.append_array(gear)
	_give(player, {"id": Items.crystal_id(), "count": 300})
	player.granted.append("testKit")
	_inventory_changed(player)
	_notice("테스트: 장비 %d개(+0)와 크리스탈 300개를 넣었다" % gear.size())


## **테스트 모드 기본 레벨** — 200 (2026-09-26 요청: "테스트모드 일 경우 기본적으로 200 레벨로
## 만들어"). 레벨만 올린다 — 장비는 꾸러미가, 스킬은 `grant_test_skills` 가 맡는다. **한 번만** 올린다
## (`granted` 의 `testLevel`) — 설계 창으로 50레벨에 맞춰 두고 다시 들어왔는데 200으로
## 되돌아가면 "버튼 안 눌렀는데 세팅이 바뀐다" 가 된다. 다시 받으려면 저장을 지운다
const TEST_LEVEL := 200

func grant_test_level(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or "testLevel" in player.get("granted", []):
		return
	player.granted.append("testLevel")
	var level := mini(TEST_LEVEL, Stats.max_level())
	if int(player.level) >= level:
		return
	player.level = level
	player.exp = 0
	_refresh_stats(player)
	player.hp = int(player.stats.maxHp)
	_notice("테스트: Lv%d 로 시작한다" % level)


## **테스트 모드 스킬** — 모든 스킬을 배우고 전직도 끝까지 올린다 (2026-09-28 요청: "테스트
## 모드에서는 … 모든 스킬을 습득한 상태로 만들어"). 치트 단추와 같은 일(`debug_learn_all`)이다.
## **한 번만** 한다 (`granted` 의 `testSkills`) — 레벨처럼, 액션바를 바꿔 두고 다시 들어왔는데
## 빈 칸이 도로 채워지면 "안 눌렀는데 세팅이 바뀐다" 가 된다. 다시 받으려면 저장을 지운다
func grant_test_skills(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or "testSkills" in player.get("granted", []):
		return
	player.granted.append("testSkills")
	# **패시브는 비워 둔다** — Lv.200 으로 시작하니 스킬창 [습득] 과 레드닷을 곧바로 눌러 본다.
	# 끝까지 올리려면 치트 "스킬 모두 배우기"
	debug_learn_all(player_id, false)


## --- 스킬 강화 ---

## 스킬창에서 **고른 강화에 모아 둔 스킬 경험치를 넣는다** — 그 스킬의 `slot` 번째(0 부터)
## 강화에 **모자란 만큼만** 들어가고(남으면 그대로 남는다), 필요 경험치(`exp`)에 닿으면
## 강화가 붙는다 (2026-09-23 요청: "어떤 타입을 강화할지 선택해서 경험치를 넣을 수 있으면
## 좋겠어" · 2026-09-28 에 경험치북 대신 던전 경험치로). 이미 붙었거나 경험치가 없거나
## 남의 직업 스킬이면 안 넣는다
func feed_upgrade(player_id: String, skill_id: String, slot: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"feed_upgrade", [skill_id, slot])


## --- 헬스 --- (docs/features/fitness.md)

## 헬스 창의 **강화** · **자동** — 운동 하나의 다음 단계를 확률로 두드린다. 판정은 `Ledger.fitness_up`
func fitness_up(player_id: String, kind_id: String, auto: bool) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"fitness_up", [kind_id, 1 if auto else 0])


## --- 장비 도감 --- (docs/features/codex.md)

## 도감 창의 **등록** — 가방의 그 장비(등급·부위·강화) 하나를 넣어 칸을 채운다. `index` 는 창에서 고른 가방 번호
## (-1 이면 옵션이 가장 적은 것). 판정은 `Ledger.codex_register`
func codex_register(player_id: String, item_id: String, enhance: int, index: int = -1) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"codex_register", [item_id, enhance, index])


## 도감 창의 **자동 등록** — 넣을 수 있는 칸을 전부 채운다. 판정은 `Ledger.codex_register_all`
func codex_register_all(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"codex_register_all")


## 테스트 단추 — 프로틴 세 종을 `DEBUG_PROTEIN` 개씩 넣는다 (던전을 안 돌고 헬스를 볼 때)
const DEBUG_PROTEIN := 10000


func debug_protein(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var have: Dictionary = player.get("proteins", {})
	for kind in Fitness.kinds():
		have[str(kind.protein)] = int(have.get(str(kind.protein), 0)) + DEBUG_PROTEIN
	player.proteins = have
	_events.append({"type": "protein", "gain": {}, "total": have.duplicate()})
	_notice("테스트: 프로틴 세 종 +%d" % DEBUG_PROTEIN)


## 테스트 단추 — 스킬 경험치를 `DEBUG_SKILL_EXP` 만큼 넣는다 (던전을 안 돌고 강화를 볼 때)
const DEBUG_SKILL_EXP := 100000


func debug_skill_exp(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	player.skill_exp = int(player.get("skill_exp", 0)) + DEBUG_SKILL_EXP
	_events.append({"type": "skillExp", "gain": DEBUG_SKILL_EXP, "total": player.skill_exp})
	_notice("테스트: 스킬 경험치 +%d" % DEBUG_SKILL_EXP)


## **테스트: 스킬 모두 배우기** (2026-09-26 요청). 레벨·포인트는 안 본다(치트다).
## 액션바 빈 칸은 배운 순서대로 채운다 — 4칸이 차 있으면 그대로.
## **패시브도 끝 단계까지 올린다** (2026-09-29 — 격투가는 보이는 스킬이 없고 패시브 하나다)
func debug_learn_all(player_id: String, passives := true) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	if passives:
		var ranks: Dictionary = player.get("passives", {})
		for p in Skills.passives_for(str(player.job)):
			ranks[str(p.id)] = int(p.maxRank)
		player.passives = ranks
		_refresh_stats(player)
		_events.append({"type": "passives", "passives": ranks.duplicate()})
	for id in Skills.for_job(str(player.job)):
		if not (str(id) in player.skills):
			player.skills.append(str(id))
	var size := int(GameData.combat().get("skillBarSize", 4))
	for id in player.skills:
		if player.skill_bar.size() >= size:
			break
		if not (id in player.skill_bar):
			player.skill_bar.append(id)
	_events.append({"type": "skills", "learned": player.skills.duplicate()})
	_events.append({"type": "skillBar", "bar": player.skill_bar.duplicate()})
	_notice("테스트: 스킬 %d개 · 패시브 끝 단계까지 배웠다" % player.skills.size())


## 강화를 붙이고, 그 강화에 쌓이던 경험치를 지운다 (붙은 뒤에는 더 못 넣는다)
func _add_upgrade(player: Dictionary, skill_id: String, upgrade_id: String) -> void:
	_ledger.add_upgrade(player, skill_id, upgrade_id)


## 테스트 단추 — 이 직업의 **모든 스킬에 `slot` 번째 강화를 경험치북 없이** 붙인다
## ("모든 스킬 1번 강화" · "2번 강화", 2026-09-23 요청). 그 번호 강화가 없는 스킬은 건너뛴다
func debug_upgrade_all(player_id: String, slot: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var count := 0
	for skill_id in Skills.for_job(str(player.job)):
		var list := Skills.upgrades_of(str(skill_id))
		if slot >= 0 and slot < list.size():
			_add_upgrade(player, str(skill_id), str(list[slot].id))
			count += 1
	_inventory_changed(player)
	_notice("테스트: 스킬 %d개에 %d번 강화" % [count, slot + 1])


## 테스트 단추 — 붙은 강화를 전부 뗀다. 쌓인 경험치도 지우고, 쓴 경험치북은 돌려주지 않는다
func debug_reset_upgrades(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	player.skill_upgrades = {}
	player.skill_upgrade_exp = {}
	_inventory_changed(player)
	_notice("테스트: 스킬 강화를 전부 뗐다")


## 테스트 단추 — 크리스탈을 가방에 넣는다. 한 칸에 겹친다 (`_give`).
## `material` 이 옐로우 크리스탈이면 그것을 (2026-10-02 — 랭킹전 보상으로만 들어와서 시험할 길이 없다)
func debug_crystals(player_id: String, count: int, material: String = "") -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or count <= 0:
		return
	if not Items.is_material(material):
		material = Items.crystal_id()
	if not _give(player, {"id": material, "count": count}):
		return
	_inventory_changed(player)
	_notice("테스트: %s %d개를 넣었다" % [Items.stack_name({"id": material}), count])


## **설계 창의 레벨 단추** — 레벨만 맞추고 **장비는 건드리지 않는다** (2026-09-26 요청:
## "설계버튼 누르면 장비를 자동 장착하는데 이 부분 없애"). 예전에는 창이 `debug_gear` 를
## 불러 여섯 칸을 등급 N 풀세트로 갈아입혔다. 체력은 새 최대치로 채운다
func debug_level(player_id: String, level: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	player.level = clampi(level, 1, Stats.max_level())
	player.exp = 0
	_refresh_stats(player)
	player.hp = int(player.stats.maxHp)
	_events.append({"type": "notice", "text": "디버그: Lv%d" % player.level})


## 테스트 전용 — 레벨과 "등급 N 풀세트 + 강화 n" 을 강제로 세운다 (`gear_test`·`stats_test`).
## 화면(설계 창)은 더 이상 부르지 않는다 — 위 `debug_level` 을 쓴다
func debug_gear(player_id: String, level: int, grade: int, enhance: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	player.level = clampi(level, 1, Stats.max_level())
	player.exp = 0

	var want_level := Stats.equip_level(clampi(grade, 1, Stats.grade_count()))
	var step := clampi(enhance, 0, Items.max_enhance())
	# 그 착용 레벨에 가장 가까운 단계의 물건으로 여섯 칸을 채운다
	var equipped := {}
	for slot in Items.slots():
		var best := {}
		var best_gap := 1 << 30
		for id in Items.all():
			var item: Dictionary = Items.all()[id]
			if str(item.get("slot", "")) != slot:
				continue
			if item.has("job") and str(item.job) != str(player.job):
				continue
			var gap: int = absi(int(item.get("level", 1)) - want_level)
			if gap < best_gap:
				best_gap = gap
				best = item
		if best.is_empty():
			continue
		# 등급은 고른 물건의 것 — 1 로 두면 장비 스킨(`Armor`)이 늘 1등급으로 보인다
		equipped[slot] = {"id": str(best.id), "grade": int(best.get("grade", 1)), "enhance": step, "options": []}
	player.equipped = equipped
	_refresh_stats(player)
	player.hp = int(player.stats.maxHp)
	_events.append({
		"type": "notice",
		"text": "디버그: Lv%d · 등급%d 풀세트 · 강화 +%d" % [player.level, grade, step],
	})


## 액션바를 정한다. 배운 것만, 칸 수만큼만 올라간다
func set_skill_bar(player_id: String, ids: Array) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var size := int(GameData.combat().get("skillBarSize", 4))
	var bar: Array = []
	for id in ids:
		if bar.size() >= size:
			break
		if str(id) in player.skills:
			bar.append(str(id))
	player.skill_bar = bar
	_events.append({"type": "skillBar", "bar": bar.duplicate()})


## 스킬을 쓴다. 판정은 전부 여기서 한다 — 화면이 보내는 건 "쓰고 싶다" 뿐이다.
##
## `aim_id` 는 **자동 사냥이 고른 놈**이다 (`_auto_cast`). 그놈이 사거리 안이면 그쪽으로
## 나간다 — 안 넘기면 가장 가까운 놈 쪽으로 나가서, 자동 사냥이 대상 쪽으로 몸을
## 되돌리는 순간 스킬과 몸이 갈린다. 화면이 누르는 단추는 넘기지 않는다
## (docs/features/godot-migration.md 의 "대상은 서버가 고른다").
func cast(player_id: String, skill_id: String, aim_id := "") -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or bool(player.dead):
		return

	# 없는 스킬이거나 다른 직업 스킬
	var skill := Skills.get_skill(str(player.job), skill_id)
	if skill.is_empty():
		return

	# 배워서 액션바에 올린 것만 쓸 수 있다.
	# **테스트 스위치가 켜져 있으면 액션바를 안 본다** — 스킬창에서 바로 쏴 보려고.
	# 직업과 쿨타임은 그대로 본다
	if not Skills.unlock_all() and not (skill_id in player.skill_bar):
		return

	var now := Time.get_ticks_msec()
	if _counting_down(now):
		return  # 샌드백 랭킹전 카운트 중 (`attack` 과 같다)
	# **시전 중에는 다른 스킬을 못 쓴다** (2026-09-24 요청). 쿨타임은 스킬마다 따로라
	# 막지 않으면 연달아 눌러 앞 동작을 끊고, 판정도 동작 하나에 둘이 겹친다.
	# 쿨타임을 돌리기 전에 거른다 — 거절된 스킬의 쿨타임이 돌면 안 된다
	if now < int(player.get("cast_until", 0)):
		return
	var ready_at: Dictionary = player.skill_ready_at
	if now < int(ready_at.get(skill_id, 0)):
		return
	var stats: Dictionary = player.stats
	# **스킬 쿨타임 감소** — 옵션으로만 붙는다. 이 설계는 범위 스킬로 무리를
	# 정리하는 사냥이라 쿨감은 사실상 DPS 다 (그래서 옵션 하나의 값어치를
	# 공속과 같은 "DPS +1%" 로 맞춰 뒀다)
	# `_refresh_stats` 가 이미 상한에 걸어 두지만, 저장값이 바로 들어오는 길이
	# 생겨도 안전하도록 여기서 한 번 더 자른다
	var cut := clampf(
		float(stats.get("cooldown", 0.0)), 0.0,
		float(GameData.combat().get("cooldownCap", 0.9))
	)
	ready_at[skill_id] = now + roundi(Skills.cooldown_of(skill) * (1.0 - cut))

	# 겨눈 놈 쪽으로 몸을 돌리는 것은 **쿨타임을 돌리기 전이 아니라** 여기서 한다.
	# 회복기도 대상을 향해 서야 이펙트가 엉뚱한 쪽을 보지 않는다
	# 붙은 강화 — 사거리 배율(범위)은 겨누기부터 판정까지 같은 값을 쓴다
	var upgrades: Array = player.get("skill_upgrades", {}).get(skill_id, [])
	var range_now := float(skill.range) * Skills.range_mul(skill_id, upgrades)
	var aim: Dictionary = {}
	if int(skill.get("maxTargets", 1)) > 0:
		aim = _aimed(player, aim_id, range_now)
		if aim.is_empty():
			var near := _pick_targets(player, range_now, TAU, 1)
			if not near.is_empty():
				aim = near[0]
		if not aim.is_empty():
			player.rot = atan2(aim.x - player.x, aim.z - player.z)

	# 스킬도 같은 공격 모션을 쓰므로 같은 동안 발이 묶인다.
	# **기본 공격 간격으로 자른다** — 스킬 쿨타임(수 초)으로 자르면 걷지도 못하고,
	# 테스트 스위치로 쿨타임이 0 이 되면 경직까지 0 이 된다
	var root := Combat.attack_root_ms(
		Combat.effective_cooldown(stats.attackCooldown, stats.attackSpeed)
	)
	# 늦게 떨어지는 스킬은 떨어질 때까지 묶는다 — 공중에서 걸어가면 착지 자리가 어긋난다
	var delay := int(skill.get("delayMs", 0))
	root = maxi(root, delay)
	player.rooted_until = now + root
	# 시전 시간 — 동작 길이(`castMs`)까지. 없는 스킬(동작이 없는 직업)은 경직과 같다.
	# 연타 강화로 대 수가 늘어 마지막 대가 동작보다 늦으면 그때까지 늘린다
	var combo_ms := int(skill.get("hitGap", 80)) * (
		int(skill.get("hits", 1)) - 1 + roundi(Skills.upgrade_sum(skill_id, upgrades, "extraHits"))
	)
	player.cast_until = now + maxi(maxi(root, int(skill.get("castMs", 0))), combo_ms)
	# 붙은 강화도 싣는다 — 화면이 이펙트를 고른다 (기절이면 붉은 번개, 범위면 좌우 두 번 더).
	# `delay_ms` 가 있으면 화면은 동작만 먼저 틀고 이펙트는 그만큼 뒤에 세운다
	_events.append({
		"type": "skill", "id": player_id, "skill": skill_id, "root_ms": root,
		"upgrades": upgrades.duplicate(), "delay_ms": delay,
	})

	# **끌어당기기** (무적파쇄권 흡인) — 기를 모으는 동안 둘레의 놈을 주먹 앞으로 모은다.
	# 판정(`delayMs`)보다 먼저 끝나서, 모인 놈이 터지는 앞 반원에 든다
	var pull := Skills.upgrade_sum(skill_id, upgrades, "pullRadius")
	if pull > 0.0:
		_pull_in(player, pull, roundi(Skills.upgrade_sum(skill_id, upgrades, "pullMs")), now)

	# 회복형은 공격 판정을 하지 않는다
	var heal := float(skill.get("selfHeal", 0.0))
	if heal > 0.0:
		var before := int(player.hp)
		player.hp = mini(int(stats.maxHp), before + roundi(float(stats.maxHp) * heal))
		_events.append({
			"type": "hit",
			"target": player_id,
			"target_kind": "player",
			"amount": int(player.hp) - before,
			"heal": true,
			"crit": false,
			"killed": false,
			"x": player.x,
			"z": player.z,
		})
		return

	if delay > 0:
		_landings.append({
			"player": player_id, "skill": skill_id, "upgrades": upgrades.duplicate(),
			"range": range_now, "aim": aim, "at": now + delay,
		})
		return
	_land(player, skill, skill_id, upgrades, range_now, aim, now)


## 끌어당기기 — 반경 안의 산 몬스터마다 출발점·도착점·시각을 달아 두면 `_step_monsters` 가 옮긴다.
## 도착점은 주먹 앞(`PULL_AHEAD`) 둘레에 **온 쪽으로 조금 남긴다**(`PULL_SPREAD`) — 뒤에서 끌려온
## 놈도 캐릭터 앞 1m 에 서서 앞 반원 판정에 든다. 보스 범위 공격을 예고한 놈은 안 끈다
## ("한번 예고한 원은 그 자리에서 터진다")
func _pull_in(player: Dictionary, radius: float, ms: int, now: int) -> void:
	var me := Vector2(player.x, player.z)
	var facing := Vector2(sin(float(player.rot)), cos(float(player.rot)))
	var center := me + facing * PULL_AHEAD
	for monster in _monsters:
		if int(monster.hp) <= 0 or int(monster.burst_at) != 0:
			continue
		var at := Vector2(monster.x, monster.z)
		if at.distance_to(me) > radius:
			continue
		var off := at - center
		var to := center + off.limit_length(PULL_SPREAD)
		monster.pull_from_x = at.x
		monster.pull_from_z = at.y
		monster.pull_to_x = to.x
		monster.pull_to_z = to.y
		monster.pull_start = now
		monster.pull_until = now + maxi(1, ms)
		monster.state = "stun"


## 때가 된 늦은 스킬을 떨어뜨린다. 그 사이 죽었거나 떠난 사람 것은 버린다
func _run_landings(now: int) -> void:
	if _landings.is_empty():
		return
	var left: Array = []
	for landing in _landings:
		if now < int(landing.at):
			left.append(landing)
			continue
		var player: Dictionary = _players.get(str(landing.player), {})
		if player.is_empty() or bool(player.dead):
			continue
		var skill := Skills.get_skill(str(player.job), str(landing.skill))
		if skill.is_empty():
			continue
		_land(player, skill, str(landing.skill), landing.upgrades, float(landing.range), landing.aim, now)
	_landings = left


## 겨눈 놈 — `id` 인 산 몬스터가 사거리 안이면 그놈, 아니면 빈 것 (`cast` 가 쓴다).
## 사거리 밖이면 잡지 않는다 — 날아가지도 않을 놈 쪽으로 몸만 돈다
func _aimed(player: Dictionary, id: String, reach: float) -> Dictionary:
	if id == "":
		return {}
	for monster in _monsters:
		if str(monster.id) != id or int(monster.hp) <= 0:
			continue
		var gap := Vector2(monster.x - player.x, monster.z - player.z).length()
		return monster if gap <= reach else {}
	return {}


## 스킬이 **떨어지는 순간** — 대상을 고르고 때리고, 지대·연타를 건다.
## 보통은 누르는 순간이고, `delayMs` 가 있으면 그만큼 뒤다 (대상도 그때 다시 고른다)
func _land(player: Dictionary, skill: Dictionary, skill_id: String, upgrades: Array,
		range_now: float, aim: Dictionary, now: int) -> void:
	var player_id := str(player.id)
	var stats: Dictionary = player.stats
	# **겨눈 놈이 있으면 원거리 스킬은 그 자리에서 터진다.** 근접기는 내 몸이
	# 중심이다 — 내 앞을 베는 동작인데 판정만 저쪽에서 나면 이펙트와 어긋난다
	var origin: Dictionary = {}
	var reach := range_now
	if not aim.is_empty() and Skills.is_ranged(skill):
		origin = {"x": aim.x, "z": aim.z}
		reach = Skills.blast_radius(skill)

	# 위력 강화는 한 대를 키운다 — 연타·뒤따르는 한 대도 이 값에서 나간다
	var attack := float(stats.attack) * float(skill.get("power", 1.0)) * Skills.power_mul(skill_id, upgrades)
	var arc := float(skill.arc)
	# **범위에 들어온 놈은 전부 맞는다** — 명수 상한이 없다 (2026-09-24 지시:
	# "스킬 범위에 들어오면 모두 피격되게. 명수 제한 없애"). `maxTargets` 는 이제
	# 때리느냐(0 은 회복기)와 단일기 착탄 반경(`Skills.blast_radius`)만 가른다
	var cap := ALL_TARGETS if int(skill.get("maxTargets", 1)) > 0 else 0
	var picked := _pick_targets(player, reach, arc, cap, origin)

	# **판정이 쓴 모양을 그대로 알린다** — 화면이 다시 계산하면 두 값이 갈라져서
	# "표시는 맞는데 안 맞는" 일이 생긴다. `_pick_targets` 가 부채꼴을 쓰는 조건
	# (착탄점이 없고 각이 한 바퀴 미만)까지 여기서 풀어 보내므로, 화면은 받은
	# 각으로 한 가지 모양만 그리면 된다 → docs/features/skills.md "범위 표시"
	_events.append({
		"type": "skillRange",
		"id": player_id,
		"skill": skill_id,
		"x": float(origin.get("x", player.x)),
		"z": float(origin.get("z", player.z)),
		"reach": reach,
		"arc": arc if (origin.is_empty() and arc < TAU) else TAU,
		"facing": float(player.rot),
		"hits": picked.size(),
	})

	# **기절은 첫 대에서 건다** — 살아남은 놈만. 연타가 있어도 다시 걸지 않는다
	var stun := Skills.stun_ms(skill_id, upgrades)
	var look := Skills.stun_look(skill_id, upgrades)
	for target in picked:
		_hit_monster(player, target, attack, skill_id)
		if stun > 0 and int(target.hp) > 0:
			target.stunned_until = now + stun
			target.stun_look = look
			target.state = "stun"

	# **뒤따르는 한 대** (빙주각 파쇄) — 정해 둔 때에 **그 순간 범위 안에 있는 놈 전부**에게
	# 한 번 더. 처음엔 첫 대로 맞은 놈에게만 예약했는데 "처음 맞은 몬스터가 아니면 데미지가
	# 안 들어가" 는 지적을 받았다 (2026-09-25) — 부서지는 기둥에 새로 걸어 들어온 놈도 맞아야
	# 한다. 그래서 **한 번만 터지는 지대**(`_zones`)로 건다: 같은 중심·반경, 그때 다시 고른다.
	# 모양은 판정과 같다 — 부채꼴이면 **시전 순간의 자리·보던 쪽** 부채꼴이다 (파천장 "연파").
	# `followAhead`·`followRadius` 가 있으면 보던 쪽으로 옮긴 자리의 원이다 (파천장 "기폭")
	for id in upgrades:
		var up := Skills.upgrade(skill_id, str(id))
		var follow := int(up.get("followMs", 0))
		if follow <= 0:
			continue
		var fx := float(origin.get("x", player.x))
		var fz := float(origin.get("z", player.z))
		var follow_reach := reach
		var follow_arc := arc if origin.is_empty() else TAU
		if up.has("followRadius"):
			var ahead := float(up.get("followAhead", 0.0))
			fx += sin(float(player.rot)) * ahead
			fz += cos(float(player.rot)) * ahead
			follow_reach = float(up.followRadius)
			follow_arc = TAU
		_zones.append({
			"player": player_id, "x": fx, "z": fz,
			"reach": follow_reach, "cap": cap, "arc": follow_arc, "facing": float(player.rot),
			"attack": attack * float(up.get("followPower", 1.0)),
			"skill": skill_id, "next_at": now + follow, "until": now + follow, "tick": follow,
		})

	# 균열 지대 — 판정 모양 그대로 땅에 남는다
	_open_zone(player, skill_id, upgrades,
		float(origin.get("x", player.x)), float(origin.get("z", player.z)), reach, cap, now)

	# **연타는 첫 대에서 고른 대상에게 간격을 두고 들어간다.** 한꺼번에 넣으면
	# 피해 숫자가 한 자리에 겹쳐 한 대로 보이고, 이펙트의 다섯 줄기와 박자가 안 맞는다.
	# 대마다 다시 고르지 않는 이유 — 첫 대에 죽은 놈 자리를 옆 놈이 채우면 "다섯 번"
	# 이 대상마다 제각각이 된다
	var gap := int(skill.get("hitGap", 80))
	# 연타 강화는 대 수를 늘린다
	var hits := int(skill.get("hits", 1)) + roundi(Skills.upgrade_sum(skill_id, upgrades, "extraHits"))
	for n in range(1, hits):
		for target in picked:
			_combos.append({
				"player": player_id, "target": target, "attack": attack,
				"skill": skill_id, "at": now + gap * n,
			})


## 피해 지대를 건다 — 붙은 강화 중 `zoneMs` 가 있는 것 (천붕각 "균열 지대").
## **판정 모양과 같은 자리·반경·대상 수**를 쓴다 — 진폭이 같이 붙으면 9m 다.
## 공격력은 **건 순간의 값**이다 (지대가 남아 있는 동안 장비를 바꿔도 안 변한다)
func _open_zone(player: Dictionary, skill_id: String, upgrades: Array,
		x: float, z: float, reach: float, cap: int, now: int) -> void:
	for id in upgrades:
		var upgrade := Skills.upgrade(skill_id, str(id))
		var span := int(upgrade.get("zoneMs", 0))
		if span <= 0:
			continue
		var tick := maxi(100, int(upgrade.get("zoneTickMs", 500)))
		_zones.append({
			"player": str(player.id), "x": x, "z": z, "reach": reach, "cap": cap,
			"attack": float(player.stats.attack) * float(upgrade.get("zonePower", 0.0)),
			"skill": skill_id, "next_at": now + tick, "until": now + span, "tick": tick,
		})


## 때가 된 지대 틱을 넣는다. **틱마다 대상을 다시 고른다** — 땅에 남은 것이라 걸어
## 들어온 놈도 맞고 나간 놈은 안 맞는다. 쓴 사람이 죽거나 떠나면 지대도 사라진다.
## 틱이 밀려 있으면(탭을 내렸다 올림) 밀린 만큼 한꺼번에 넣지 않고 한 번만 넣는다 —
## 한 틱에 여섯 대가 겹쳐 뜨면 피해 숫자가 한 자리에 쌓인다
func _run_zones(now: int) -> void:
	if _zones.is_empty():
		return
	var left: Array = []
	for zone_hit in _zones:
		var player: Dictionary = _players.get(str(zone_hit.player), {})
		if player.is_empty() or bool(player.dead):
			continue
		if now >= int(zone_hit.next_at) and int(zone_hit.next_at) <= int(zone_hit.until):
			var origin := {"x": float(zone_hit.x), "z": float(zone_hit.z)}
			# 부채꼴(연파)은 건 순간의 보던 쪽으로 — 균열 지대·파쇄는 원이다 (`arc` 가 없거나 한 바퀴)
			var zone_arc := float(zone_hit.get("arc", TAU))
			var zone_facing := float(zone_hit.get("facing", NAN)) if zone_arc < TAU else NAN
			for target in _pick_targets(player, float(zone_hit.reach), zone_arc, int(zone_hit.cap), origin, zone_facing):
				_hit_monster(player, target, float(zone_hit.attack), str(zone_hit.skill))
			while int(zone_hit.next_at) <= now:
				zone_hit.next_at = int(zone_hit.next_at) + int(zone_hit.tick)
		if int(zone_hit.next_at) <= int(zone_hit.until):
			left.append(zone_hit)
	_zones = left


## 때가 된 연타를 넣는다. 그 사이 죽은 쪽(때린 쪽이든 맞는 쪽이든)은 건너뛴다
func _run_combos(now: int) -> void:
	if _combos.is_empty():
		return
	var left: Array = []
	for combo in _combos:
		if now < int(combo.at):
			left.append(combo)
			continue
		var player: Dictionary = _players.get(str(combo.player), {})
		var target: Dictionary = combo.target
		if player.is_empty() or bool(player.dead) or int(target.hp) <= 0:
			continue
		_hit_monster(player, target, float(combo.attack), str(combo.skill))
	_combos = left


## 몬스터 하나를 때린다. 기본 공격과 스킬이 같은 자리를 쓴다
func _hit_monster(player: Dictionary, target: Dictionary, attack: float, skill_id: String) -> void:
	var stats: Dictionary = player.stats
	# **방어력 관통** — 상대 방어력을 그만큼 없는 셈 치고 때린다 (옵션으로만 붙는다)
	var pierced: float = float(target.defense) * (1.0 - float(stats.get("penetration", 0.0)))
	var damage := roundi(Stats.damage(attack, int(player.level), pierced))
	# **치명타 저항은 확률에서 뺀다** (2026-09-30) — 치확 128% 로 저항 36.5% 몹을 치면 91.5%.
	# 상한 없이 넘친 치확이 여기서 쓰인다
	var crit := Combat.roll_crit(float(stats.crit) - float(target.get("crit_resist", 0.0)), _rng.randf())
	# **치명타 데미지는 더하는 %다** (2026-09-27 요청) — 100% 면 기본 피해에 100% 를 더해 ×2.
	# 맨몸이 1.0(100%) 이라 그냥 곱하면 치명타가 떠도 평타와 같았다
	if crit:
		damage = roundi(damage * (1.0 + float(stats.critDamage)))

	# **샌드백은 안 죽는다** — 체력은 그대로 두고 넣은 피해만 센다 (docs/features/sandbag.md)
	var dummy := bool(target.get("dummy", false))
	if dummy:
		_count_sandbag_damage(damage, Time.get_ticks_msec())
	else:
		target.hp = maxi(0, int(target.hp) - damage)
	_events.append({
		"type": "hit",
		"target": target.id,
		"target_kind": "monster",
		"amount": damage,
		"crit": crit,
		"killed": target.hp <= 0,
		"skill": skill_id,
		"x": target.x,
		"z": target.z,
	})
	if dummy:
		return
	if target.hp <= 0:
		_kill(player, target, Time.get_ticks_msec())
	# **맞으면 때린 사람을 쫓는다** (2026-09-29) — 어그로를 3m 로 좁혀서, 이게 없으면 멀리서
	# 쏘는 동안 몬스터가 가만히 서 있다. 이미 쫓는 대상이 있거나 집으로 돌아가는 중이면 그대로 둔다
	elif str(target.get("target", "")) == "" and not bool(target.get("leashing", false)):
		target.target = str(player.id)


## 맨몸 스탯에 장비를 **곱한다**. 장비가 바뀔 때마다 다시 만든다 —
## 어딘가에 합쳐 둔 값을 들고 있으면 반드시 어긋난다.
##
## **더하기가 아니라 곱하기다** (2026-09-20). 설계에서 장비는 절대 수치가 아니라
## 기본 스탯에 곱하는 **%** 다:
##
##     총 공격력 = 기본공격력(레벨) × (1 + 장비 % 합계)
##
## 축마다 계수가 다른 것(공 ×1.0 / 방 ×0.6 / HP ×0.35)은 `gear.ts` 가 이미 반영해
## 내려보내므로 여기서는 그대로 곱하기만 한다. 생존을 레벨 쪽에 묶어 둬야
## 저레벨 캐릭이 고등급 장비를 껴도 상위 사냥터에서 죽어 **게이팅이 자동으로 걸린다**
func _refresh_stats(player: Dictionary) -> void:
	player.stats = stats_of(
		str(player.job), int(player.level), player.equipped, player.get("passives", {}), player.get("fitness", {}),
		player.get("codex", {})
	)
	player.hp = mini(int(player.hp), int(player.stats.maxHp))


## 그 캐릭터의 달리기 속도 — 이동 속도 패시브(경공, 2026-09-30)만큼 곱한다
func _speed_of(player: Dictionary) -> float:
	return _run_speed * (1.0 + maxf(float(player.get("stats", {}).get("moveSpeed", 0.0)), 0.0))


## 스탯 계산 알맹이 — 서버의 처치 검증(`KillCheck`)도 같은 값을 쓴다
## `passives` 는 배운 패시브 단계 `{ id: 단계 }` — **공속은 여기서만 온다** (질풍각, 2026-09-29)
## `fitness` 는 헬스 운동 단계 `{ id: 단계 }` — 공격력·방어력·체력에 **장비 % 와 따로 곱한다** (fitness.md)
## `codex` 는 장비 도감 `{ 아이템 id: 채운 강화 비트 }` — 헬스와 같은 셋에 **또 따로 곱한다** (codex.md)
static func stats_of(
	job: String, level: int, equipped: Dictionary, passives: Dictionary = {}, fitness: Dictionary = {},
	codex: Dictionary = {}
) -> Dictionary:
	var stats := Combat.stats_for(job, level)
	var gear := Items.equipment_stats(equipped)
	# 캐릭터 정보 창이 패시브 몫을 따로 적는다 — 더하기 전 값을 `passive_*` 로 같이 내린다.
	# 레벨 도달 패시브(2026-09-30)는 **장비 몫에 더한다** — 공격력은 % 합계에, 나머지는 비율에
	var passive := Skills.passive_bonus(job, passives)
	for key in ["attack", "attackSpeed", "moveSpeed", "crit", "critDamage", "penetration"]:
		stats["passive_" + key] = float(passive.get(key, 0.0))
	# 캐릭터 정보 창이 **기본 → 증가 % → 최종** 을 풀어 적는다 (2026-09-25 요청). 화면이
	# 공식을 다시 돌리지 않게 곱하기 전 값과 장비 % 합계를 같이 내려보낸다
	for key in ["attack", "defense", "maxHp"]:
		stats["base_" + key] = int(stats[key])
		stats["gear_" + key] = float(gear[key])
	stats.attack = maxi(1, roundi(
		float(stats.attack) * (1.0 + float(gear.attack) / 100.0 + float(stats.passive_attack))
	))
	stats.defense = maxi(0, roundi(float(stats.defense) * (1.0 + float(gear.defense) / 100.0)))
	stats.maxHp = maxi(1, roundi(float(stats.maxHp) * (1.0 + float(gear.maxHp) / 100.0)))
	# 헬스 — 장비 % 에 더하지 않고 **곱한다.** 더하면 태초 풀셋(+856%) 앞에서 +50% 가 +5% 로 준다.
	# 캐릭터 정보 창이 몫을 따로 적도록 % 를 같이 내린다 (`fitness_attack` …)
	var fit := Fitness.stat_bonus(fitness)
	for key in ["attack", "defense", "maxHp"]:
		stats["fitness_" + key] = float(fit[key])
		if float(fit[key]) > 0.0:
			stats[key] = maxi(0 if key == "defense" else 1, roundi(float(stats[key]) * (1.0 + float(fit[key]) / 100.0)))
	# 장비 도감 — 헬스와 같은 방식으로 **따로 곱한다** (`codex_*` 는 캐릭터 정보 창용)
	var book := Codex.stat_bonus(codex)
	for key in ["attack", "defense", "maxHp"]:
		stats["codex_" + key] = float(book[key])
		if float(book[key]) > 0.0:
			stats[key] = maxi(0 if key == "defense" else 1, roundi(float(stats[key]) * (1.0 + float(book[key]) / 100.0)))
	# **상한이 없다** ★ (2026-09-23 지시: "상한 없애."). 치확 100% 면 늘 치명타,
	# 공속은 `cooldown / (1 + 공속)` 이라 얼마든 올라가도 0 으로 안 나뉜다.
	# 가방 옆 장비 창은 **장비 몫만** 적는다 (2026-09-28 요청) — 더하기 전 장비 합계를 같이 내린다
	for key in ["crit", "critDamage", "attackSpeed"]:
		stats["gear_" + key] = float(gear[key])
	stats.crit = maxf(float(stats.crit) + gear.crit + stats.passive_crit, 0.0)
	stats.critDamage += gear.critDamage + stats.passive_critDamage
	# 이동 속도는 달리기 속도의 배율 — `_run_speed × (1 + moveSpeed)` (`_speed_of`)
	stats["moveSpeed"] = stats.passive_moveSpeed
	stats.attackSpeed = maxf(float(stats.attackSpeed) + gear.attackSpeed + stats.passive_attackSpeed, 0.0)
	# **쿨감·관통만 90% 에서 멈춘다** ★ (2026-09-23 지시). 수치를 더 주고 싶으면
	# 이 줄이 아니라 옵션 최대치(`OPTION_MAX_VALUE`)를 올린다
	var c := GameData.combat()
	stats["cooldown"] = clampf(float(gear.get("cooldown", 0.0)), 0.0, float(c.get("cooldownCap", 0.9)))
	stats["penetration"] = clampf(
		float(gear.get("penetration", 0.0)) + stats.passive_penetration, 0.0,
		float(c.get("penetrationCap", 0.9))
	)
	# 아이템 드랍률 — 상한 없음 (확률이 100% 를 넘으면 `Items.with_drop_bonus` 가 자른다).
	# 판정은 `Ledger.kill` 이 장부의 장비로 따로 센다. 여기 값은 캐릭터 정보 창이 적는 것이다
	stats["dropRate"] = float(gear.get("dropRate", 0.0))
	return stats


## --- 장부 --- (docs/features/server.md)

## **장부를 바꾸는 단 하나의 길.** 판정은 `Ledger`(`ledger.gd`)가 하고, 여기서는 그 결과를
## 화면으로 흘리고 스탯을 다시 만든다. 서버를 붙이면 이 자리가 요청을 서버로 보낸다 —
## 그래서 **장부를 바꾸는 코드를 World 에 새로 넣지 않는다** (`ledger.gd` 에 넣는다).
## 스탯은 늘 다시 만든다 — 장비·레벨이 그대로면 같은 값이 나온다
func _ledger_call(player: Dictionary, op: StringName, args: Array = []) -> void:
	if remote != null:
		# 기기는 판정하지 않는다 — 답이 오면 `apply_ledger` 가 장부를 통째로 덮는다
		remote.request(op, args)
		return
	var before := int(player.level)
	_ledger.callv(op, [player] + args)
	_after_ledger(player, before, _ledger.take_events())


## 서버의 답 — **장부 칸을 통째로 덮는다.** 기기가 먼저 바꿔 둔 것이 없으니 되돌릴 것도 없다
func apply_ledger(player_id: String, ledger: Dictionary, events: Array) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var before := int(player.level)
	for key in Ledger.KEYS:
		if ledger.has(key):
			player[key] = ledger[key]
	_after_ledger(player, before, events)


func _after_ledger(player: Dictionary, before: int, events: Array) -> void:
	_events.append_array(events)
	_refresh_stats(player)
	# 레벨이 오르면 체력을 채운다 — 체력은 장부가 아니라 전투 쪽 값이다
	if int(player.level) > before:
		player.hp = int(player.stats.maxHp)


## 가방에 넣는다 — 치트·테스트가 쓰는 지름길. 판정은 `Ledger.give`
func _give(player: Dictionary, stack: Dictionary) -> bool:
	var ok := _ledger.give(player, stack)
	_events.append_array(_ledger.take_events())
	return ok


## 가방의 물건을 낀다 (`Ledger.equip`)
func equip(player_id: String, index: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"equip", [index])


## 가방을 정렬한다 (`Ledger.sort_bag`)
func sort_bag(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"sort_bag")


## 부위마다 가장 좋은 것으로 낀다 (`Ledger.auto_equip`)
func auto_equip(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"auto_equip")


## 장비 잠금을 뒤집는다 (`Ledger.toggle_lock`) — where 는 "bag"(가방 번호) · "equip"(슬롯)
func toggle_lock(player_id: String, where: String, key: Variant) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"toggle_lock", [where, key])


func unequip(player_id: String, slot: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"unequip", [slot])


## --- 크리스탈 ---

## 크리스탈로 **2차 옵션을 통째로 다시 굴린다** (`Ledger.use_crystal`). 가방(`where = "bag"`,
## `key` = 가방 번호)과 끼고 있는 것(`"equip"`, `key` = 슬롯) 둘 다 된다. NPC 가 필요 없다.
## `tier` 3 이면 옐로우 크리스탈로 **3차**를 굴린다 (2026-10-02)
func use_crystal(player_id: String, where: String, key: Variant, tier: int = 2) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"use_crystal", [where, key, tier])


## 그 역할의 NPC 가 닿는 거리에 있나. **살 때마다 다시 잰다** —
## 창을 열어 두고 걸어 나가면 살 수 없어야 한다
func _npc_near(player: Dictionary, role: String) -> bool:
	for npc in zone.get("npcs", []):
		if str(npc.get("role", "")) != role:
			continue
		if Vector2(player.x - float(npc.x), player.z - float(npc.z)).length() <= NPC_REACH:
			return true
	return false


func _notice(text: String) -> void:
	_events.append({"type": "notice", "text": text})


func _inventory_changed(player: Dictionary) -> void:
	_events.append({"type": "inventory", "bag": player.bag, "equipped": player.equipped})


## --- 상점 ---

## 산다 (`Ledger.buy`). **NPC 곁인지는 여기서** — 자리는 기기에만 있다
func npc_buy(player_id: String, item_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not _npc_near(player, "shop"):
		return
	_ledger_call(player, &"buy", [item_id])


func npc_sell(player_id: String, index: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not _npc_near(player, "shop"):
		return
	_ledger_call(player, &"sell", [index])


## --- 대장간 ---

## 제작(새로 만들기·등급 올리기)은 2026-09-20 에 걷었다 — 장비는 사냥으로만 나온다

## 대장간 강화 — 대장간 곁에서 가방의 것을 두드린다. 알맹이는 `enhance_item` 과 같다
func npc_enhance(player_id: String, index: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not _npc_near(player, "smith"):
		return
	_ledger_call(player, &"enhance", ["bag", index])


## 상세 창의 "강화" — **NPC 없이** 가방에 든 것과 끼고 있는 것 둘 다 두드린다 (`Ledger.enhance`).
## **한 요청 = 한 번.** 자동 강화는 팝업이 한 번씩 되풀이해 보낸다 — 한 단계씩 보여 주고
## 중간에 멈출 수 있어야 해서다 (2026-09-24 "한 단계씩 연출 넣어")
func enhance_item(player_id: String, where: String, key: Variant) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"enhance", [where, key])


## 다중 강화 — 가방에서 고른 칸들을 한 개씩 한 번 두드린다 (`Ledger.enhance_many`)
func enhance_many(player_id: String, indices: Array, cap: int = -1) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	_ledger_call(player, &"enhance_many", [indices, cap])
