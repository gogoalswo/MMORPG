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
			})


func join(player_id: String) -> void:
	var spawn: Array = zone.get("spawns", {}).get("default", [0, 0])
	_players[player_id] = {
		"x": float(spawn[0]),
		"z": float(spawn[1]),
		"rot": 0.0,
		"last_seq": -1,
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

	# 몬스터를 뚫고 못 지나간다. 미는 쪽은 언제나 움직이는 쪽이다
	Movement.apply_move(player, dx, dz, dt, half_size, _run_speed, _monsters)
	player.last_seq = seq

	if sqrt(dx * dx + dz * dz) > 1e-4:
		player.rot = atan2(dx, dz)


## 한 틱. 전투가 들어올 자리다 (5단계).
func step(_delta: float) -> void:
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
