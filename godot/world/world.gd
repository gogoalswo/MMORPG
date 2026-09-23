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
## 밖으로 내보낼 일들 (맞았다·죽었다·레벨 올랐다). Transport 가 비워 간다
var _events: Array = []
## 아직 안 들어간 연타 (`hits` 가 2 이상인 스킬의 둘째 대부터).
## `{player, target, attack, skill, at}` — `step` 이 때가 된 것부터 넣는다
var _combos: Array = []

## 어느 직업으로 시작하나. 만드는 화면이 없어서 당분간 고정이다
const DEFAULT_JOB := "fighter"

## NPC 와 말할 수 있는 거리 (m). **거리는 여기서 다시 잰다** —
## 창이 열려 있다고 살 수 있는 게 아니다
const NPC_REACH := 4.5

## 몇 초마다 저장하나
const SAVE_EVERY_MS := 10000

## --- 순찰 ---
## 쫓을 사람이 없는 몬스터는 집 주변을 서성인다. 가만히 선 무리는 살아 있는 것처럼
## 보이지 않아서다. 값은 **어그로(보통 9m)보다 작게** 잡는다 — 순찰 때문에
## 사람에게 먼저 닿으면 "가만히 있었는데 맞았다"가 된다
const PATROL_RADIUS := 4.0
## 걷는 것처럼 보이게 제 속도의 이만큼으로만 움직인다
const PATROL_SPEED := 0.35
## 목적지에 이만큼 붙으면 도착으로 본다
const PATROL_ARRIVE := 0.3
## 한 다리 걷고 쉬는 시간. 무리가 한꺼번에 움직이지 않게 놈마다 다르게 뽑는다.
## 쉬는 동안은 idle 이라 **매 프레임 미는 것도 쉬어 간다** (폰 부담)
const PATROL_REST_MIN_MS := 2000
const PATROL_REST_MAX_MS := 6000

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
	# 떠난 존의 몬스터를 붙잡은 연타가 새 존에서 들어가면 안 된다
	_combos.clear()
	_spawn_monsters()


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
		# --- 자동 사냥 ---
		# **존을 옮기면 꺼진다** (join 을 다시 타므로). 앵커가 지난 존의 자리라
		# 남겨 두면 켜 둔 채로 엉뚱한 데를 향해 걷는다
		"auto": false,
		"auto_x": float(spawn[0]),
		"auto_z": float(spawn[1]),
		"auto_target": "",
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
		"skills": kept.get("skills", []).duplicate(),
		"skill_points": int(kept.get("skill_points", level - 1)),
		"skill_bar": kept.get("skill_bar", []).duplicate(),
		# 스킬별 다음에 쓸 수 있는 시각
		"skill_ready_at": {},
		# --- 아이템 ---
		"bag": kept.get("bag", []).duplicate(true),
		"equipped": kept.get("equipped", {}).duplicate(true),
	}
	_refresh_stats(_players[player_id])


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
		player, dx, dz, dt, half_size, _run_speed, _solids_near(player.x, player.z)
	)
	player.last_seq = seq

	if sqrt(dx * dx + dz * dz) > 1e-4:
		player.rot = atan2(dx, dz)
		# **걸어간 자리가 새 사냥터다.** 앵커를 안 옮기면 손을 떼는 순간 자동
		# 사냥이 원래 자리로 도로 끌고 간다 — 조작이 이긴 것처럼 보이지 않는다
		if bool(player.get("auto", false)):
			_anchor_here(player)


## 한 틱. 전투가 들어올 자리다 (5단계).
func step(delta: float) -> void:
	var now := Time.get_ticks_msec()
	_respawn(now)
	_run_combos(now)
	_step_monsters(delta, now)
	_drive_auto(delta, now)
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
	open(target)
	for who in _players:
		join(who)
	_events.append({"type": "zone", "zone": target})


## 밖으로 내보내는 상태. 읽기 전용으로 쓴다.
func snapshot() -> Dictionary:
	return {
		"zone": zone_id,
		"size": zone.get("size", 66),
		"players": _players,
		"monsters": _monsters,
		"gate": zone.get("gate", {}),
		"npcs": zone.get("npcs", []),
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

	var stats: Dictionary = player.stats
	var cooldown := Combat.effective_cooldown(stats.attackCooldown, stats.attackSpeed)
	player.next_attack_at = now + cooldown
	var root := Combat.attack_root_ms(cooldown)
	player.rooted_until = now + root
	# 휘두르는 동안 못 움직인다는 통보. 화면이 이 값만큼 동작을 튼다
	_events.append({"type": "swing", "id": player_id, "root_ms": root})

	var picked := _pick_targets(player, float(stats.attackRange), _attack_arc(), 1)
	if picked.is_empty():
		return
	var target: Dictionary = picked[0]

	_hit_monster(player, target, float(stats.attack), "")


## 맞을 놈들을 고른다. **가까운 순서로 max_targets 만큼.**
##
## origin 이 주어지면 그 자리를 중심으로 한 **원**으로 본다 (원거리 스킬이 날아가
## 터진 것). 날아가 터진 것에 "시전자 정면"은 의미가 없다. origin 이 없으면
## 시전자 자리에서 정면 부채꼴로 본다 — 등 뒤는 맞지 않는다.
func _pick_targets(
	player: Dictionary,
	reach: float,
	arc: float,
	max_targets: int,
	origin: Dictionary = {},
) -> Array:
	if max_targets <= 0:
		return []
	var from_x: float = origin.get("x", player.x)
	var from_z: float = origin.get("z", player.z)
	var facing_x := sin(float(player.rot))
	var facing_z := cos(float(player.rot))
	var half_arc := arc / 2.0
	var use_arc := origin.is_empty() and arc < TAU

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
		if out.size() >= max_targets:
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

		var target := _pick_hunt_target(player)
		if target.is_empty():
			# 아무도 없다. 앵커 주변을 서성이며 기다린다
			player.auto_target = ""
			_patrol_auto(player, delta, now)
			continue

		player.auto_target = str(target.id)
		# 사거리를 꽉 채우고 서면 상대가 조금만 움직여도 빠진다. 안쪽으로 붙는다
		var reach := float(player.stats.attackRange)
		_walk_auto(player, float(target.x), float(target.z), delta, now, reach * HUNT_STANDOFF)
		# 치기 전에 그쪽을 본다. 판정 부채꼴이 rot 를 보기 때문이다 —
		# 안 돌리면 마지막으로 걷던 쪽으로 헛친다 (attack 은 정면에서 다시 고른다)
		player.rot = atan2(float(target.x) - player.x, float(target.z) - player.z)
		# 휘두르는 중에는 다음 것을 넣지 않는다. 스킬 경직 중에 기본 공격이 끼면
		# 스킬 동작이 끊기고, 쿨타임이 0 인 테스트 스위치에서는 스킬이 매 틱 나간다
		if now < int(player.rooted_until):
			continue
		var gap := Vector2(float(target.x) - player.x, float(target.z) - player.z).length()
		# 스킬이 먼저다. 돌아온 스킬이 있으면 기본 공격 대신 그걸 쓴다
		if _auto_cast(player, id, gap, now):
			continue
		# **사거리 안일 때만 휘두른다.** 멀리서 헛휘두르면 그때마다 경직(400ms)이
		# 걸려 한 발짝도 못 나간다 — 붙기 전에 제자리에서 팔만 돌게 된다
		if gap <= reach:
			attack(id)


## 자동 사냥의 스킬. 액션바 **칸 순서대로** 보고, 쿨타임이 돈 것 중 대상이 그 스킬
## 사거리 안에 든 첫 것을 쓴다 — 칸 순서가 곧 우선순위다.
##
## 쏘는 것은 사람이 누를 때와 **같은 `cast`** 다. 쿨타임·액션바·조준 검증을 두 벌
## 만들면 반드시 어긋난다. 나갔는지는 경직이 새로 걸렸는지로 본다 — 쿨타임으로
## 보면 테스트 스위치(쿨타임 0)에서 나갔는데도 안 나간 것으로 읽힌다.
func _auto_cast(player: Dictionary, id: String, gap: float, now: int) -> bool:
	var ready_at: Dictionary = player.skill_ready_at
	for skill_id in player.skill_bar:
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
		cast(id, str(skill_id))
		if int(player.rooted_until) > now:
			return true
	return false


## 앵커 반경 안에서 **가장 가까운** 산 몬스터. 잡고 있던 놈은 리쉬까지 봐준다 —
## 반경과 같으면 경계에 걸친 놈을 잡았다 놓았다 반복하고, 놓을 때마다 앵커로
## 걸어 돌아가려다 다시 붙는 그림이 된다.
func _pick_hunt_target(player: Dictionary) -> Dictionary:
	var anchor := Vector2(float(player.auto_x), float(player.auto_z))
	var current := str(player.get("auto_target", ""))
	var best: Dictionary = {}
	var best_gap := INF

	for monster in _monsters:
		if int(monster.hp) <= 0:
			continue
		var from_anchor := Vector2(monster.x - anchor.x, monster.z - anchor.y).length()
		# 잡고 있던 놈이면 리쉬 안까지 계속 잡는다 (대상을 바꾸지 않는다)
		if str(monster.id) == current:
			if from_anchor <= HUNT_LEASH:
				return monster
			continue
		if from_anchor > HUNT_RADIUS:
			continue
		var gap := Vector2(monster.x - player.x, monster.z - player.z).length()
		if gap < best_gap:
			best_gap = gap
			best = monster

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
		player, dir.x, dir.y, delta, half_size, _run_speed, _solids_near(player.x, player.z)
	)
	player.rot = atan2(dir.x, dir.y)


func _kill(player: Dictionary, target: Dictionary, now: int) -> void:
	target.respawn_at = now + int(target.respawn_ms)

	# 보상을 굴린다. **굴리는 쪽은 언제나 판정하는 쪽이다**
	var loot := Items.roll_drop(int(target.level), str(player.job), _rng)
	player.gold = int(player.gold) + int(loot.gold)
	var event := {"type": "loot", "gold": loot.gold}
	if loot.has("item") and _give(player, loot.item):
		event["item"] = loot.item
	# 크리스탈은 장비와 따로 떨어진다 — 가방에서는 한 칸에 겹친다
	if loot.has("crystal"):
		var crystal := {"id": Items.crystal_id(), "count": int(loot.crystal)}
		if _give(player, crystal):
			event["crystal"] = int(loot.crystal)
	_events.append(event)

	var gained := Combat.exp_reward(int(target.level), int(player.level), float(target.exp_reward))
	var before := int(player.level)
	var grown := Combat.apply_exp(before, int(player.exp), gained)
	player.level = grown.level
	player.exp = grown.exp
	_events.append({"type": "reward", "exp": gained})

	if grown.level > before:
		# 레벨이 오르면 스탯을 다시 만들고 체력을 채운다
		_refresh_stats(player)
		player.hp = player.stats.maxHp
		var per_level := int(GameData.combat().get("skillPointPerLevel", 1))
		player.skill_points = int(player.skill_points) + (grown.level - before) * per_level
		_events.append({"type": "levelUp", "level": grown.level})


## 죽은 몬스터를 제 시간에 되살린다
func _respawn(now: int) -> void:
	for monster in _monsters:
		if int(monster.hp) > 0 or int(monster.respawn_at) == 0:
			continue
		if now < int(monster.respawn_at):
			continue
		monster.hp = monster.max_hp
		monster.respawn_at = 0
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
		if int(monster.hp) <= 0:
			continue

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
			_move_monster(monster, target.x, target.z, float(monster.speed), delta)
			continue

		monster.state = "attack"
		monster.rot = atan2(target.x - monster.x, target.z - monster.z)
		if now >= int(monster.next_attack_at):
			monster.next_attack_at = now + int(monster.attack_cooldown)
			monster.rooted_until = now + Combat.monster_root_ms(float(monster.attack_cooldown))
			_hit_player(target, monster)


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


## attack 을 따로 받는 것은 범위 공격이 평타의 power 배로 때리기 때문이다
func _hit_player(player: Dictionary, monster: Dictionary, attack: float = -1.0) -> void:
	var power := float(monster.attack) if attack < 0.0 else attack
	# **공격자 레벨로 K 를 뽑는다** — 높은 사냥터 몬스터가 때리면 내 방어력 효율이
	# 자동으로 떨어진다. 레벨차 보정 시스템이 따로 필요 없는 이유다 (설계 1장)
	var damage := roundi(Stats.damage(power, int(monster.get("level", 1)), float(player.stats.defense)))
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
		"level": int(kind.get("level", 1)),
		"max_hp": int(kind.get("maxHp", 1)),
		"hp": int(kind.get("maxHp", 1)),
		"defense": float(kind.get("defense", 0)),
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
		# 정확히 겹쳤을 때 밀려날 방향. **서로 달라야 풀린다**
		"push_angle": push_angle,
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
	if all.has(zone_saved) and zone_saved != zone_id:
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
	var bar: Array = []
	for id in saved.get("skill_bar", []):
		if str(id) in learned:
			bar.append(str(id))
	player.skill_bar = bar

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
		_events.append({
			"type": "npc",
			"name": npc_name,
			"role": role,
			"title": str(npc.get("title", "")),
			"items": listed,
		})
		return


## 기본 공격이 닿는 정면 각도(라디안). 등 뒤의 적은 맞지 않는다
func _attack_arc() -> float:
	return float(GameData.combat().get("attackArc", PI * 0.6))


## 스킬을 배운다. **직업·레벨·포인트를 여기서 다시 본다.**
func learn_skill(player_id: String, skill_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var skill := Skills.get_skill(str(player.job), skill_id)
	if skill.is_empty():
		_events.append({"type": "notice", "text": "쓸 수 없는 스킬입니다"})
		return
	if skill_id in player.skills:
		return
	if not Skills.can_learn(skill, str(player.job), int(player.level)):
		_events.append({"type": "notice", "text": "%d레벨에 배웁니다" % int(skill.get("reqLevel", 1))})
		return
	var cost := Skills.point_cost()
	if int(player.skill_points) < cost:
		_events.append({"type": "notice", "text": "스킬 포인트가 모자랍니다"})
		return

	player.skill_points = int(player.skill_points) - cost
	player.skills.append(skill_id)
	_events.append({"type": "skills", "learned": player.skills.duplicate()})


## 테스트 스위치(쿨타임 0 · 레벨 잠금 해제)를 켜고 끈다. 이름은 Skills.SWITCHES 만 받는다
func set_test_switch(name: String, on: bool) -> void:
	if not Skills.set_switch(name, on):
		return
	var label := "쿨타임 0" if name == "cooldownOff" else "레벨 잠금 해제"
	_events.append({"type": "notice", "text": "%s %s" % [label, "켬" if on else "끔"]})


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


## 테스트 단추 — 크리스탈을 가방에 넣는다. 한 칸에 겹친다 (`_give`)
func debug_crystals(player_id: String, count: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or count <= 0:
		return
	if not _give(player, {"id": Items.crystal_id(), "count": count}):
		return
	_inventory_changed(player)
	_notice("테스트: 크리스탈 %d개를 넣었다" % count)


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
		equipped[slot] = {"id": str(best.id), "grade": 1, "enhance": step, "options": []}
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
func cast(player_id: String, skill_id: String) -> void:
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
	var aim: Dictionary = {}
	if int(skill.get("maxTargets", 1)) > 0:
		var near := _pick_targets(player, float(skill.range), TAU, 1)
		if not near.is_empty():
			aim = near[0]
			player.rot = atan2(aim.x - player.x, aim.z - player.z)

	# 스킬도 같은 공격 모션을 쓰므로 같은 동안 발이 묶인다.
	# **기본 공격 간격으로 자른다** — 스킬 쿨타임(수 초)으로 자르면 걷지도 못하고,
	# 테스트 스위치로 쿨타임이 0 이 되면 경직까지 0 이 된다
	var root := Combat.attack_root_ms(
		Combat.effective_cooldown(stats.attackCooldown, stats.attackSpeed)
	)
	player.rooted_until = now + root
	_events.append({"type": "skill", "id": player_id, "skill": skill_id, "root_ms": root})

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

	# **겨눈 놈이 있으면 원거리 스킬은 그 자리에서 터진다.** 근접기는 내 몸이
	# 중심이다 — 내 앞을 베는 동작인데 판정만 저쪽에서 나면 이펙트와 어긋난다
	var origin: Dictionary = {}
	var reach := float(skill.range)
	if not aim.is_empty() and Skills.is_ranged(skill):
		origin = {"x": aim.x, "z": aim.z}
		reach = Skills.blast_radius(skill)

	var attack := float(stats.attack) * float(skill.get("power", 1.0))
	var arc := float(skill.arc)
	var cap := int(skill.get("maxTargets", 1))
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
		"max_targets": cap,
		"hits": picked.size(),
	})

	for target in picked:
		_hit_monster(player, target, attack, skill_id)

	# **연타는 첫 대에서 고른 대상에게 간격을 두고 들어간다.** 한꺼번에 넣으면
	# 피해 숫자가 한 자리에 겹쳐 한 대로 보이고, 이펙트의 다섯 줄기와 박자가 안 맞는다.
	# 대마다 다시 고르지 않는 이유 — 첫 대에 죽은 놈 자리를 옆 놈이 채우면 "다섯 번"
	# 이 대상마다 제각각이 된다
	var gap := int(skill.get("hitGap", 80))
	for n in range(1, int(skill.get("hits", 1))):
		for target in picked:
			_combos.append({
				"player": player_id, "target": target, "attack": attack,
				"skill": skill_id, "at": now + gap * n,
			})


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
	var crit := Combat.roll_crit(float(stats.crit), _rng.randf())
	if crit:
		damage = roundi(damage * float(stats.critDamage))

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
	if target.hp <= 0:
		_kill(player, target, Time.get_ticks_msec())


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
	var stats := Combat.stats_for(str(player.job), int(player.level))
	var gear := Items.equipment_stats(player.equipped)
	stats.attack = maxi(1, roundi(float(stats.attack) * (1.0 + float(gear.attack) / 100.0)))
	stats.defense = maxi(0, roundi(float(stats.defense) * (1.0 + float(gear.defense) / 100.0)))
	stats.maxHp = maxi(1, roundi(float(stats.maxHp) * (1.0 + float(gear.maxHp) / 100.0)))
	# **상한이 없다** ★ (2026-09-23 지시: "상한 없애."). 치확 100% 면 늘 치명타,
	# 공속은 `cooldown / (1 + 공속)` 이라 얼마든 올라가도 0 으로 안 나뉜다.
	stats.crit = maxf(float(stats.crit) + gear.crit, 0.0)
	stats.critDamage += gear.critDamage
	stats.attackSpeed = maxf(float(stats.attackSpeed) + gear.attackSpeed, 0.0)
	# **쿨감·관통만 90% 에서 멈춘다** ★ (2026-09-23 지시). 수치를 더 주고 싶으면
	# 이 줄이 아니라 옵션 최대치(`OPTION_MAX_VALUE`)를 올린다
	var c := GameData.combat()
	stats["cooldown"] = clampf(float(gear.get("cooldown", 0.0)), 0.0, float(c.get("cooldownCap", 0.9)))
	stats["penetration"] = clampf(
		float(gear.get("penetration", 0.0)), 0.0, float(c.get("penetrationCap", 0.9))
	)
	player.stats = stats
	player.hp = mini(int(player.hp), int(stats.maxHp))


## 가방에 넣는다. 꽉 찼으면 못 넣는다
func _give(player: Dictionary, stack: Dictionary) -> bool:
	# 재료는 **이미 있는 칸에 겹친다** — 크리스탈이 칸을 하나씩 먹으면 가방이 금방 찬다
	if Items.is_material(str(stack.get("id", ""))):
		for held in player.bag:
			if str(held.get("id", "")) == str(stack.id):
				held.count = int(held.get("count", 1)) + int(stack.get("count", 1))
				return true
	if player.bag.size() >= Items.bag_size():
		_events.append({"type": "notice", "text": "가방이 가득 찼습니다"})
		return false
	player.bag.append(stack)
	return true


## 가방의 물건을 낀다. **낄 수 있는지 여기서 다시 본다**
func equip(player_id: String, index: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or index < 0 or index >= player.bag.size():
		return
	var stack: Dictionary = player.bag[index]
	var item := Items.get_item(str(stack.id))
	if not Items.can_equip(item, str(player.job), int(player.level)):
		_events.append({"type": "notice", "text": "낄 수 없는 장비입니다"})
		return

	var slot := str(item.slot)
	player.bag.remove_at(index)
	# 끼고 있던 것은 가방으로 돌아간다
	var before: Dictionary = player.equipped.get(slot, {})
	if not before.is_empty():
		player.bag.append(before)
	player.equipped[slot] = stack

	_refresh_stats(player)
	_events.append({"type": "inventory", "bag": player.bag, "equipped": player.equipped})


## 가방을 정렬한다 — 높은 등급이 앞, 같은 등급이면 슬롯 순서(무기 → 반지),
## 그다음 강화가 높은 것. 순서만 바뀌고 물건은 그대로다
func sort_bag(player_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var order: Array = Items.slots()
	player.bag.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
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
	_events.append({"type": "inventory", "bag": player.bag, "equipped": player.equipped})


func unequip(player_id: String, slot: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var stack: Dictionary = player.equipped.get(slot, {})
	if stack.is_empty():
		return
	if not _give(player, stack):
		return  # 가방이 꽉 찼으면 벗지 않는다 — 벗다가 잃으면 안 된다
	player.equipped.erase(slot)
	_refresh_stats(player)
	_events.append({"type": "inventory", "bag": player.bag, "equipped": player.equipped})


## --- 크리스탈 ---

## 크리스탈로 **2차 옵션을 통째로 다시 굴린다** (2026-09-23). 처음 쓰면 붙고, 다시 쓰면
## 바뀐다. 가방(`where = "bag"`, `key` = 가방 번호)과 끼고 있는 것(`"equip"`, `key` = 슬롯)
## 둘 다 된다 — 끼고 있는 걸 벗어야 굴릴 수 있으면 번거롭기만 하다.
## NPC 가 필요 없다. **굴림은 판정하는 쪽이 한다**
func use_crystal(player_id: String, where: String, key: Variant) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty():
		return
	var target: Dictionary = {}
	if where == "equip":
		target = player.equipped.get(str(key), {})
	elif where == "bag" and int(key) >= 0 and int(key) < player.bag.size():
		target = player.bag[int(key)]
	var item := Items.get_item(str(target.get("id", "")))
	if item.is_empty():
		return  # 장비에만 붙는다

	var crystal := -1
	for index in player.bag.size():
		if str(player.bag[index].get("id", "")) == Items.crystal_id():
			crystal = index
			break
	if crystal < 0:
		_notice("크리스탈이 없습니다")
		return

	# 먼저 굴리고 나서 크리스탈을 뺀다 — 빼다가 칸이 비면 가방 번호가 당겨진다
	target.options2 = Items.roll_tier_options(2, int(target.get("grade", 1)), _rng)
	var left := int(player.bag[crystal].get("count", 1)) - 1
	if left > 0:
		player.bag[crystal].count = left
	else:
		player.bag.remove_at(crystal)
	if where == "equip":
		_refresh_stats(player)

	var lines: Array = []
	for option in target.options2:
		lines.append(Items.describe_option(option))
	_notice("%s 2차 옵션 — %s" % [item.name, ", ".join(lines)])
	_inventory_changed(player)


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

## 산다. **파는 목록에 있는 것만** — 화면이 보낸 id 를 믿지 않는다
func npc_buy(player_id: String, item_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not _npc_near(player, "shop"):
		return
	if not (item_id in Items.shop_stock(str(player.job), int(player.level))):
		return
	var item := Items.get_item(item_id)
	if item.is_empty():
		return

	var price := int(item.price)
	if int(player.gold) < price:
		_notice("골드가 %d 모자랍니다" % (price - int(player.gold)))
		return
	if player.bag.size() >= Items.bag_size():
		_notice("가방이 가득 찼습니다")
		return

	player.gold = int(player.gold) - price
	# 옵션은 **판정하는 쪽이 굴린다.** 물건이 생기는 자리마다 굴려야 빠지는 곳이 없다
	player.bag.append({
		"id": item_id, "grade": 1, "enhance": 0, "options": Items.roll_options(item, 1, _rng)
	})
	_notice("%s 구입 — %d G" % [item.name, price])
	_inventory_changed(player)


func npc_sell(player_id: String, index: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not _npc_near(player, "shop"):
		return
	if index < 0 or index >= player.bag.size():
		return
	var stack: Dictionary = player.bag[index]
	var item := Items.get_item(str(stack.id))
	if item.is_empty():
		return

	var price := Items.sell_price(item, int(stack.get("grade", 1)))
	player.bag.remove_at(index)
	player.gold = int(player.gold) + price
	_notice("%s 판매 — %d G" % [item.name, price])
	_inventory_changed(player)


## --- 대장간 ---

## 제작(새로 만들기·등급 올리기)은 2026-09-20 에 걷었다 — 장비는 사냥으로만 나온다

## 강화 — 골드만 쓴다. 성공 / 유지 / 파괴. **굴림은 판정하는 쪽이 한다**
func npc_enhance(player_id: String, index: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not _npc_near(player, "smith"):
		return
	if index < 0 or index >= player.bag.size():
		return
	var stack: Dictionary = player.bag[index]
	var item := Items.get_item(str(stack.id))
	if item.is_empty():
		return

	var level := int(stack.get("enhance", 0))
	if not Items.can_enhance(level):
		_notice("더 두드릴 수 없습니다")
		return
	var cost := Items.enhance_cost(item, level)
	if int(player.gold) < cost:
		_notice("골드가 %d 모자랍니다" % (cost - int(player.gold)))
		return

	player.gold = int(player.gold) - cost
	var result := Items.roll_enhance(level, _rng.randf())
	match result:
		"success":
			stack.enhance = level + 1
			_notice("%s +%d 성공" % [item.name, stack.enhance])
		"keep":
			_notice("%s +%d 유지" % [item.name, level])
		"destroy":
			player.bag.remove_at(index)
			_notice("%s 가 부서졌습니다" % item.name)
	_events.append({"type": "enhanceResult", "result": result, "level": stack.get("enhance", level)})
	_inventory_changed(player)
