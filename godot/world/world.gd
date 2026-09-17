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
		"stats": stats,
		"next_attack_at": 0,
		"rooted_until": 0,
	}


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

	var target := _pick_target(player, float(stats.attackRange))
	if target.is_empty():
		return

	var damage := Combat.compute_damage(float(stats.attack), target.defense)
	var crit := Combat.roll_crit(float(stats.crit), _rng.randf())
	if crit:
		damage = roundi(damage * float(stats.critDamage))

	target.hp = maxi(0, int(target.hp) - damage)
	_events.append({
		"type": "hit",
		"target": target.id,
		"amount": damage,
		"crit": crit,
		"killed": target.hp <= 0,
		"x": target.x,
		"z": target.z,
	})

	if target.hp <= 0:
		_kill(player, target, now)


## 정면 부채꼴 안에서 가장 가까운 산 몬스터
func _pick_target(player: Dictionary, attack_range: float) -> Dictionary:
	var facing_x := sin(float(player.rot))
	var facing_z := cos(float(player.rot))
	var half_arc := float(GameData.combat().get("attackArc", PI * 0.6)) / 2.0

	var best: Dictionary = {}
	var best_dist := INF
	for monster in _monsters:
		if int(monster.hp) <= 0:
			continue
		var dx: float = monster.x - player.x
		var dz: float = monster.z - player.z
		var dist := sqrt(dx * dx + dz * dz)
		if dist > attack_range:
			continue
		# 등 뒤는 맞지 않는다
		if dist >= 1e-3:
			var dot := (dx / dist) * facing_x + (dz / dist) * facing_z
			if acos(clampf(dot, -1.0, 1.0)) > half_arc:
				continue
		if dist < best_dist:
			best_dist = dist
			best = monster
	return best


func _kill(player: Dictionary, target: Dictionary, now: int) -> void:
	target.respawn_at = now + int(target.respawn_ms)

	var gained := Combat.exp_reward(int(target.level), int(player.level), float(target.exp_reward))
	var before := int(player.level)
	var grown := Combat.apply_exp(before, int(player.exp), gained)
	player.level = grown.level
	player.exp = grown.exp
	_events.append({"type": "reward", "exp": gained})

	if grown.level > before:
		# 레벨이 오르면 스탯을 다시 만들고 체력을 채운다
		player.stats = Combat.stats_for(str(player.job), grown.level)
		player.hp = player.stats.maxHp
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
