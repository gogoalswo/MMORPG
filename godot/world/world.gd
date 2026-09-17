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
## 스폰을 매번 같은 자리에 놓는다. 자리를 정하는 건 언제나 판정하는 쪽이다
var _rng := RandomNumberGenerator.new()
## 밖으로 내보낼 일들 (맞았다·죽었다·레벨 올랐다). Transport 가 비워 간다
var _events: Array = []

## 어느 직업으로 시작하나. 만드는 화면이 없어서 당분간 고정이다
const DEFAULT_JOB := "knight"

## NPC 와 말할 수 있는 거리 (m). **거리는 여기서 다시 잰다** —
## 창이 열려 있다고 살 수 있는 게 아니다
const NPC_REACH := 4.5

## 몇 초마다 저장하나
const SAVE_EVERY_MS := 10000

var _next_save_at := 0


func open(id: String) -> void:
	zone_id = id
	zone = GameData.zone(id)
	half_size = Movement.zone_half_size(float(zone.get("size", 92)))
	_run_speed = float(GameData.constants().get("runSpeed", 4.6))
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

	# 휘두르는 중이면 발을 묶는다. **순번은 갱신하고 위치만 안 옮긴다** —
	# 안 갱신하면 나중에 서버를 붙였을 때 클라이언트 보정이 이 구간 내내 멈춘다
	if Time.get_ticks_msec() < int(player.rooted_until):
		player.last_seq = seq
		return

	# 몬스터를 뚫고 못 지나간다. 미는 쪽은 언제나 움직이는 쪽이다
	Movement.apply_move(player, dx, dz, dt, half_size, _run_speed, _monsters)
	player.last_seq = seq

	if sqrt(dx * dx + dz * dz) > 1e-4:
		player.rot = atan2(dx, dz)


## 한 틱. 전투가 들어올 자리다 (5단계).
func step(delta: float) -> void:
	var now := Time.get_ticks_msec()
	_respawn(now)
	_step_monsters(delta, now)
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
		"size": zone.get("size", 92),
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


func _kill(player: Dictionary, target: Dictionary, now: int) -> void:
	target.respawn_at = now + int(target.respawn_ms)

	# 보상을 굴린다. **굴리는 쪽은 언제나 판정하는 쪽이다**
	var loot := Items.roll_drop(int(target.level), str(player.job), _rng)
	player.gold = int(player.gold) + int(loot.gold)
	if loot.has("item"):
		if _give(player, loot.item):
			_events.append({"type": "loot", "gold": loot.gold, "item": loot.item})
		else:
			_events.append({"type": "loot", "gold": loot.gold})
	else:
		_events.append({"type": "loot", "gold": loot.gold})

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

		# 집에서 너무 멀어졌으면 쫓기를 포기하고 돌아간다
		if home_gap > float(monster.leash):
			monster.target = ""
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
			# 집에서 벗어나 있으면 슬슬 돌아간다
			if home_gap > 1.5:
				monster.state = "chase"
				_move_monster(monster, monster.home_x, monster.home_z, float(monster.speed) * 0.5, delta)
			else:
				monster.state = "idle"
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

	# 움직인 놈만 민다. 서 있는 80마리까지 매 프레임 밀면 폰에서 버겁다
	var near: Array = []
	for other in _monsters:
		if other.id == monster.id or int(other.hp) <= 0:
			continue
		if absf(other.x - monster.x) > 4.0 or absf(other.z - monster.z) > 4.0:
			continue
		near.append(other)
	Movement.push_out_of_solids(
		monster, near, half_size, float(monster.r), float(monster.push_angle)
	)


## attack 을 따로 받는 것은 범위 공격이 평타의 power 배로 때리기 때문이다
func _hit_player(player: Dictionary, monster: Dictionary, attack: float = -1.0) -> void:
	var power := float(monster.attack) if attack < 0.0 else attack
	var damage := Combat.compute_damage(power, float(player.stats.defense))
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
		"target": "",
		"state": "idle",
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

	# 가방·장비도 되살린다. 표에 없는 id 는 버린다 — 아이템을 다시 만드는 중이라
	# 없어진 것이 저장에 남아 있을 수 있다
	var bag: Array = []
	for stack in saved.get("bag", []):
		if not Items.get_item(str(stack.get("id", ""))).is_empty():
			bag.append(stack)
	player.bag = bag
	var worn: Dictionary = {}
	for slot in saved.get("equipped", {}):
		var stack: Dictionary = saved.equipped[slot]
		if not Items.get_item(str(stack.get("id", ""))).is_empty():
			worn[str(slot)] = stack
	player.equipped = worn
	# 장비까지 넣고 나서 스탯을 만든다. 체력 상한이 장비에 걸려 있다
	_refresh_stats(player)
	player.hp = clampi(int(saved.get("hp", player.stats.maxHp)), 0, int(player.stats.maxHp))

	# 죽은 채로 저장됐으면 자리는 스폰으로 둔다 — 시체 자리에서 시작할 이유가 없다
	if not player.dead:
		player.x = clampf(float(saved.get("x", player.x)), -half_size, half_size)
		player.z = clampf(float(saved.get("z", player.z)), -half_size, half_size)
	return true


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
			"smith":
				# 만들 수 있는 것이 레벨을 따라 길어진다. 창 쪽에서 거른다
				listed = Items.forgeable_for(str(player.job), int(player.level))
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
	ready_at[skill_id] = now + Skills.cooldown_of(skill)

	var stats: Dictionary = player.stats

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
	for target in _pick_targets(
		player, reach, float(skill.arc), int(skill.get("maxTargets", 1)), origin
	):
		_hit_monster(player, target, attack, skill_id)


## 몬스터 하나를 때린다. 기본 공격과 스킬이 같은 자리를 쓴다
func _hit_monster(player: Dictionary, target: Dictionary, attack: float, skill_id: String) -> void:
	var stats: Dictionary = player.stats
	var damage := Combat.compute_damage(attack, target.defense)
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


## 직업 스탯에 장비를 더한다. **장비가 바뀔 때마다 다시 만든다** —
## 어딘가에 합쳐 둔 값을 들고 있으면 반드시 어긋난다
func _refresh_stats(player: Dictionary) -> void:
	var stats := Combat.stats_for(str(player.job), int(player.level))
	var gear := Items.equipment_stats(player.equipped)
	stats.attack += gear.attack
	stats.defense += gear.defense
	stats.maxHp += gear.maxHp
	# 상한이 있는 것들 — 옵션이 여덟 자리에 붙으므로 안 막으면 치명타 100% 가 나온다
	var c := GameData.combat()
	stats.crit = minf(float(stats.crit) + gear.crit, float(c.get("critCap", 0.75)))
	stats.critDamage += gear.critDamage
	stats.attackSpeed = minf(
		float(stats.attackSpeed) + gear.attackSpeed, float(c.get("attackSpeedCap", 1.0))
	)
	player.stats = stats
	player.hp = mini(int(player.hp), int(stats.maxHp))


## 가방에 넣는다. 꽉 찼으면 못 넣는다
func _give(player: Dictionary, stack: Dictionary) -> bool:
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


## 가방에 든 재료 수
func _material_count(player: Dictionary, material_id: String) -> int:
	var n := 0
	for stack in player.bag:
		if str(stack.get("id", "")) == material_id:
			n += 1
	return n


## 재료를 쓴다. 모자라면 아무것도 안 쓰고 false
func _spend_materials(player: Dictionary, material_id: String, count: int) -> bool:
	if _material_count(player, material_id) < count:
		return false
	var left := count
	for i in range(player.bag.size() - 1, -1, -1):
		if left <= 0:
			break
		if str(player.bag[i].get("id", "")) == material_id:
			player.bag.remove_at(i)
			left -= 1
	return true


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

## 새로 만들기 — 재료와 골드를 내고 1등급을 얻는다
func npc_forge(player_id: String, item_id: String) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not _npc_near(player, "smith"):
		return
	if not (item_id in Items.forgeable_for(str(player.job), int(player.level))):
		return
	var item := Items.get_item(item_id)
	var recipe := Items.forge_recipe(item)
	if recipe.is_empty():
		return

	if player.bag.size() >= Items.bag_size():
		_notice("가방이 가득 찼습니다")
		return
	if int(player.gold) < int(recipe.gold):
		_notice("골드가 %d 모자랍니다" % (int(recipe.gold) - int(player.gold)))
		return
	if _material_count(player, str(recipe.materialId)) < int(recipe.materialCount):
		_notice("%s 가 모자랍니다" % recipe.materialName)
		return

	_spend_materials(player, str(recipe.materialId), int(recipe.materialCount))
	player.gold = int(player.gold) - int(recipe.gold)
	player.bag.append({
		"id": item_id, "grade": 1, "enhance": 0, "options": Items.roll_options(item, 1, _rng)
	})
	_notice("%s 제작 완료" % item.name)
	_inventory_changed(player)


## 강화 — 골드만 쓴다. 성공 / 유지 / 파괴. **굴림은 판정하는 쪽이 한다**
func npc_enhance(player_id: String, index: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not _npc_near(player, "smith"):
		return
	if index < 0 or index >= player.bag.size():
		return
	var stack: Dictionary = player.bag[index]
	var item := Items.get_item(str(stack.id))
	if item.is_empty() or bool(item.get("material", false)):
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


## 등급 올리기 — 같은 단계 재료와 수수료. **옵션을 다시 굴린다**
func npc_craft(player_id: String, index: int) -> void:
	var player: Dictionary = _players.get(player_id, {})
	if player.is_empty() or not _npc_near(player, "smith"):
		return
	if index < 0 or index >= player.bag.size():
		return
	var stack: Dictionary = player.bag[index]
	var item := Items.get_item(str(stack.id))
	if item.is_empty():
		return

	var need := Items.craft_requirement(item, int(stack.get("grade", 1)))
	if need.is_empty():
		_notice("더 올릴 수 없습니다")
		return
	if int(player.gold) < int(need.gold):
		_notice("골드가 %d 모자랍니다" % (int(need.gold) - int(player.gold)))
		return
	if _material_count(player, str(need.materialId)) < int(need.materialCount):
		_notice("%s 가 %d개 필요합니다" % [need.materialName, need.materialCount])
		return

	_spend_materials(player, str(need.materialId), int(need.materialCount))
	player.gold = int(player.gold) - int(need.gold)
	stack.grade = int(need.targetGrade)
	stack.options = Items.roll_options(item, stack.grade, _rng)
	_notice("%s %d등급 완성" % [item.name, stack.grade])
	_inventory_changed(player)
