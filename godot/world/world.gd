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
			_monsters.append({
				"id": "%s_%d" % [kind.id, _monsters.size()],
				"kind": kind.id,
				"x": spot.x,
				"z": spot.z,
				"r": radius,
				"scale": scale,
				"color": kind.get("bodyColor", "#888888"),
				"boss": bool(kind.get("boss", false)),
				"level": int(kind.get("level", 1)),
				"max_hp": int(kind.get("maxHp", 1)),
				"hp": int(kind.get("maxHp", 1)),
				"defense": float(kind.get("defense", 0)),
				"exp_reward": float(kind.get("expReward", 0)),
				"respawn_ms": float(pack.get("respawnMs", 10000)),
				# 죽어 있는 동안 다시 나올 시각. 0 이면 살아 있다
				"respawn_at": 0,
			})


func join(player_id: String) -> void:
	var spawn: Array = zone.get("spawns", {}).get("default", [0, 0])
	var kept: Dictionary = _players.get(player_id, {})
	var level := int(kept.get("level", 1))
	var stats := Combat.stats_for(DEFAULT_JOB, level)
	_players[player_id] = {
		"x": float(spawn[0]),
		"z": float(spawn[1]),
		"rot": 0.0,
		"last_seq": -1,
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
func step(_delta: float) -> void:
	_respawn(Time.get_ticks_msec())
	_check_gate()


## 차원문에 들어가면 존을 옮긴다.
##
## **임시다.** 진짜 게임은 차원문에서 사냥터 20곳을 골라 고르게 되어 있는데
## (웹 클라의 ui/zoneGate.ts), 그 화면은 UI 단계에서 만든다. 지금은 마을과
## 첫 사냥터를 오가기만 한다 — 몬스터를 보려면 사냥터로 가야 하기 때문이다.
func _check_gate() -> void:
	var gate: Dictionary = zone.get("gate", {})
	if gate.is_empty():
		return
	var position: Array = gate.get("position", [0, 0])
	var radius := float(gate.get("radius", 2.6))
	var fields := GameData.field_order()
	var target: String = GameData.start_zone() if zone_id != GameData.start_zone() else (
		str(fields[0]) if not fields.is_empty() else ""
	)
	if target.is_empty():
		return

	for id in _players:
		var player: Dictionary = _players[id]
		var gap := Vector2(player.x - float(position[0]), player.z - float(position[1])).length()
		if gap <= radius:
			open(target)
			for who in _players:
				join(who)
			return


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
	if player.is_empty():
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
