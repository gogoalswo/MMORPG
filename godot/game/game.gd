extends Node3D

## 화면. 상태는 Transport 에서만 받아 그린다 — World 를 직접 만지지 않는다.
##
## 씬 파일 대신 코드로 짓는 이유: 에디터를 못 쓰는 환경에서 .tscn 을 손으로
## 쓰면 틀리기 쉽고, 이 화면은 존 데이터(바닥 크기·하늘색·안개)에서 나오는
## 것이라 어차피 코드가 정한다. 모델·UI 가 들어오는 단계에서 씬으로 옮긴다.
##
## 지금은 **예측/보정이 없다.** 로컬이라 지연이 0 이므로 스냅샷을 그대로 그려도
## 매끄럽다. 서버를 붙이는 단계에서 넣는다 → docs/features/networking-state.md

const STOP_DISTANCE := 0.15

var _transport: Transport
var _player: Node3D
## 기둥은 가운데가 원점이라 반만큼 띄워야 하고, 모델은 발이 원점이다
var _player_y := 0.9
## 이번 프레임에 걸었나 (달리기·대기 동작을 고르는 데 쓴다)
var _moving := false
## 공격 동작을 언제까지 트나 (서버가 준 경직 시간)
var _swing_until := 0
var _camera: Camera3D
var _label: Label
var _marker: MeshInstance3D

var _target: Vector3 = Vector3.INF
var _seq := 0
var _half_size := 0.0
## 존마다 다시 짓는 것들(바닥·하늘·몬스터·차원문)은 여기 아래에 둔다.
## 캐릭터·카메라·UI 는 존이 바뀌어도 그대로라 밖에 있다
var _zone_node: Node3D
var _shown_zone := ""
## 눌러 둔 몬스터. 사거리에 들 때까지 걸어가서 계속 친다
var _target_mob := ""
## 몬스터 id -> 그려 둔 몸. 죽으면 감추고 살아나면 다시 보인다
var _mob_nodes: Dictionary = {}
## 마지막으로 일어난 일 한 줄 (맞았다·레벨 올랐다)
var _last_event := ""
var _ui_root: Control
var _hp_bar: ProgressBar
var _gate_panel: PanelContainer


func _ready() -> void:
	_transport = LocalTransport.new()
	add_child(_transport)
	_transport.open(GameData.start_zone())
	_transport.event.connect(_on_event)
	_build_persistent()


## 판정이 낸 일. 지금은 글자 한 줄로만 보여준다 — 피격 연출은 UI 단계다
func _on_event(name: StringName, payload: Dictionary) -> void:
	match name:
		&"hit":
			var who := "맞음" if payload.get("target_kind", "") == "player" else "피해"
			_last_event = "%s %d%s%s" % [
				who,
				payload.get("amount", 0),
				" 치명타!" if payload.get("crit", false) else "",
				"  처치!" if payload.get("killed", false) else "",
			]
		&"levelUp":
			_last_event = "레벨 %d 이 되었습니다" % payload.get("level", 0)
		&"swing":
			# 휘두르는 동안 발이 묶인다는 통보. 그 시간만큼 공격 동작을 튼다
			_swing_until = Time.get_ticks_msec() + int(payload.get("root_ms", 400))
		&"died":
			_last_event = "쓰러졌습니다 — 아무 데나 눌러 마을에서 되살아나기"
			_target = Vector3.INF
			_target_mob = ""
			_marker.visible = false
			_gate_panel.visible = false
		&"revived":
			_last_event = "마을에서 되살아났습니다"
		&"gate":
			# 차원문에 섰다. 어디로 갈지는 사람이 고른다
			_gate_panel.visible = true
		&"zone":
			_last_event = "%s 에 도착했습니다" % GameData.zone(str(payload.get("zone", ""))).get("name", "")


## 존이 바뀌어도 살아 있는 것들
func _build_persistent() -> void:
	# 모델이 있으면 모델, 없으면 기둥. npm run sync:godot 을 안 돌렸을 수도 있다
	var rig := Rig.create("varco_knight", Rig.HUMAN_HEIGHT)
	if rig != null:
		_player = rig
		_player_y = 0.0
	else:
		var capsule := MeshInstance3D.new()
		var body := CapsuleMesh.new()
		body.radius = Movement.PLAYER_RADIUS
		body.height = 1.8
		capsule.mesh = body
		var body_mat := StandardMaterial3D.new()
		body_mat.albedo_color = Color("#e8d7b0")
		capsule.material_override = body_mat
		_player = capsule
		_player_y = 0.9
	add_child(_player)

	# 어디를 눌렀는지 보여주는 표시 (웹 클라의 클릭 이동 표시와 같은 역할)
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.35
	ring.outer_radius = 0.5
	_marker.mesh = ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("#4aa8ff")
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("#4aa8ff")
	_marker.material_override = ring_mat
	_marker.visible = false
	add_child(_marker)

	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)

	var ui := CanvasLayer.new()
	add_child(ui)

	# 한글 폰트를 테마로 깐다. 고도 기본 폰트에는 한글 글리프가 없어서
	# 안 깔면 "마을" 이 네모로 나온다 (npm run sync:godot 이 복사해 둔다)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 화면 아무 데나 눌러 걸어야 하므로 UI 바탕은 터치를 먹지 않는다.
	# 단추는 제 몫을 따로 먹는다
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = _make_theme()
	ui.add_child(_ui_root)

	_label = Label.new()
	_label.position = Vector2(24, 24)
	_ui_root.add_child(_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(24, 150)
	_hp_bar.size = Vector2(360, 34)
	_hp_bar.show_percentage = false
	_ui_root.add_child(_hp_bar)

	_build_gate_panel()


func _make_theme() -> Theme:
	var theme := Theme.new()
	var path := "res://assets/fonts/NotoSansKR-subset.ttf"
	if ResourceLoader.exists(path):
		theme.default_font = load(path)
	theme.default_font_size = 28
	return theme


## 차원문에 서면 뜨는 사냥터 목록. 웹 클라의 ui/zoneGate.ts 와 같은 자리다
func _build_gate_panel() -> void:
	_gate_panel = PanelContainer.new()
	_gate_panel.set_anchors_preset(Control.PRESET_CENTER)
	_gate_panel.visible = false
	_ui_root.add_child(_gate_panel)

	var rows := VBoxContainer.new()
	_gate_panel.add_child(rows)

	var title := Label.new()
	title.text = "어디로 갈까요"
	rows.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	rows.add_child(grid)

	# 마을 + 사냥터 20곳. 순서는 데이터가 정한다 (zones.json 의 fieldOrder)
	var ids: Array = [GameData.start_zone()]
	ids.append_array(GameData.field_order())
	for id in ids:
		var zone := GameData.zone(str(id))
		var button := Button.new()
		button.text = str(zone.get("name", id))
		button.pressed.connect(_on_gate_pick.bind(str(id)))
		grid.add_child(button)

	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(func() -> void: _gate_panel.visible = false)
	rows.add_child(close)


func _on_gate_pick(zone_id: String) -> void:
	_gate_panel.visible = false
	_target = Vector3.INF
	_target_mob = ""
	_marker.visible = false
	_transport.send(&"travel", {"zone": zone_id})


## 존 하나를 짓는다. 차원문으로 옮기면 통째로 버리고 다시 짓는다
func _build_zone(zone_id: String) -> void:
	if _zone_node != null:
		_zone_node.queue_free()
	_zone_node = Node3D.new()
	add_child(_zone_node)
	_shown_zone = zone_id

	var zone := GameData.zone(zone_id)
	var env: Dictionary = zone.get("env", {})
	var size := float(zone.get("size", 92))
	_half_size = Movement.zone_half_size(size)
	_target = Vector3.INF
	_marker.visible = false

	var world_env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(env.get("skyColor", "#b9c9d8"))
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(env.get("skyColor", "#b9c9d8"))
	e.ambient_light_energy = float(env.get("hemiIntensity", 1.1))
	e.fog_enabled = true
	e.fog_light_color = Color(env.get("fogColor", "#c2c8b8"))
	e.fog_density = 0.006
	world_env.environment = e
	_zone_node.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = float(env.get("sunIntensity", 2.7))
	sun.rotation_degrees = Vector3(-50, -35, 0)
	_zone_node.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(env.get("groundTint", "#6a665c"))
	ground.material_override = ground_mat
	_zone_node.add_child(ground)

	# 존 경계 — 여기까지만 걸어갈 수 있다 (Movement.zone_half_size)
	var edge := MeshInstance3D.new()
	var edge_mesh := PlaneMesh.new()
	edge_mesh.size = Vector2(_half_size * 2.0, _half_size * 2.0)
	edge.mesh = edge_mesh
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(env.get("grassDark", "#5c6a3c"))
	edge.material_override = edge_mat
	edge.position.y = 0.01
	_zone_node.add_child(edge)

	# 차원문. 여기 들어가면 존이 바뀐다 (World._check_gate)
	var gate: Dictionary = zone.get("gate", {})
	if not gate.is_empty():
		var gate_pos: Array = gate.get("position", [0, 0])
		var portal := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = float(gate.get("radius", 2.6))
		disc.bottom_radius = disc.top_radius
		disc.height = 0.08
		portal.mesh = disc
		var gate_mat := StandardMaterial3D.new()
		gate_mat.albedo_color = Color(gate.get("color", "#4aa8ff"))
		gate_mat.emission_enabled = true
		gate_mat.emission = Color(gate.get("color", "#4aa8ff"))
		portal.material_override = gate_mat
		portal.position = Vector3(float(gate_pos[0]), 0.04, float(gate_pos[1]))
		_zone_node.add_child(portal)

	# 몬스터. 자리는 World 가 정했고 여기서는 그리기만 한다.
	# 모델이 있는 look 만 모델이고 나머지는 기둥이다 (웹 클라도 같은 규칙)
	_mob_nodes.clear()
	for monster in _transport.snapshot().get("monsters", []):
		var kind := GameData.monster_kind(monster.kind)
		var look := str(kind.get("look", ""))
		var height := GameData.beast_height(look, float(monster.scale))
		var node: Node3D = Rig.create(look, height)
		var foot := 0.0
		if node == null:
			var body := MeshInstance3D.new()
			var shape := CapsuleMesh.new()
			shape.radius = monster.r
			shape.height = maxf(monster.r * 2.0 + 0.1, height)
			body.mesh = shape
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(monster.color)
			if monster.boss:
				mat.emission_enabled = true
				mat.emission = Color(monster.color) * 0.6
			body.material_override = mat
			node = body
			foot = shape.height * 0.5
		node.position = Vector3(monster.x, foot, monster.z)
		_zone_node.add_child(node)
		_mob_nodes[monster.id] = node


func _unhandled_input(event: InputEvent) -> void:
	# 터치는 기본 설정이 마우스로 바꿔 주므로 이 한 줄이 폰도 덮는다
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 죽어 있으면 어딜 눌러도 부활 요청이다
		if _am_dead():
			_transport.send(&"revive", {})
			return
		var hit := _ground_point(event.position)
		if hit == Vector3.INF:
			return
		# 몬스터를 눌렀으면 그놈을 잡으러 간다. 아니면 그 자리로 걸어간다
		var mob := _mob_at(hit)
		if mob != "":
			_target_mob = mob
			_target = Vector3.INF
			_marker.visible = false
		else:
			_target_mob = ""
			_target = hit
			_marker.position = hit + Vector3(0, 0.05, 0)
			_marker.visible = true


## 바닥의 그 자리에 산 몬스터가 있나. 손가락은 굵으니 반지름에 여유를 준다
func _mob_at(point: Vector3) -> String:
	var best := ""
	var best_gap := INF
	for monster in _transport.snapshot().get("monsters", []):
		if int(monster.hp) <= 0:
			continue
		var gap: float = Vector2(point.x - monster.x, point.z - monster.z).length() - monster.r
		if gap < 0.8 and gap < best_gap:
			best_gap = gap
			best = monster.id
	return best


## 화면의 한 점이 바닥의 어디인지
func _ground_point(screen: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.INF
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	return hit if hit != null else Vector3.INF


func _process(delta: float) -> void:
	_moving = false
	_send_input(delta)
	_draw_state()


## 눌러 둔 자리로 향하는 방향을 만들어 보낸다. **요청일 뿐이고 판정은 World 가 한다.**
func _am_dead() -> bool:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	return bool(me.get("dead", false))


func _send_input(delta: float) -> void:
	if _zone_node == null or _am_dead():
		return
	if _target_mob != "":
		_chase_and_hit(delta)
		return
	if _target == Vector3.INF:
		return
	var me := _my_position()
	var to := Vector2(_target.x - me.x, _target.z - me.z)
	if to.length() <= STOP_DISTANCE:
		_target = Vector3.INF
		_marker.visible = false
		return
	_move(to.normalized(), delta)


## 눌러 둔 몬스터에게 걸어가서 사거리에 들면 계속 친다.
## 때릴 수 있는지는 **World 가 다시 본다** — 여기서 보내는 건 요청일 뿐이다
func _chase_and_hit(delta: float) -> void:
	var snap := _transport.snapshot()
	var me: Dictionary = snap.get("players", {}).get(_transport.my_id(), {})
	var mob := _find_mob(snap, _target_mob)
	if me.is_empty() or mob.is_empty() or int(mob.hp) <= 0:
		_target_mob = ""
		return

	var to := Vector2(mob.x - me.x, mob.z - me.z)
	var dir := to.normalized()
	var reach: float = float(me.stats.attackRange)
	if to.length() > reach:
		_move(dir, delta)
		return
	# 사거리 안이다. 제자리에서 그쪽을 보고(dt 0) 친다
	_move(dir, 0.0)
	_transport.send(&"attack", {})


func _move(dir: Vector2, delta: float) -> void:
	_seq += 1
	_moving = delta > 0.0
	_transport.send(&"input", {"seq": _seq, "dx": dir.x, "dz": dir.y, "dt": delta})


## 죽음 > 공격 > 달리기 > 대기 순으로 고른다.
##
## 공격 클립은 5.07초짜리라 통째로 틀면 한 번 휘두르는 데 5초가 걸린다.
## 웹 클라이언트는 0.8~1.60초 구간만 1.6배로 트는데(`modelRig` 의 ATTACK_CLIPS),
## 여기서도 같은 자리에서 시작한다. **정확한 구간 맞추기는 아직 안 했다** —
## 발이 미끄러지거나 동작이 어긋나면 그때 재서 고친다.
func _play_player_clip(me: Dictionary) -> void:
	if not _player is Rig:
		return
	var rig: Rig = _player
	if bool(me.get("dead", false)):
		rig.play("Death")
		return
	if Time.get_ticks_msec() < _swing_until:
		rig.play("Attack", 1.6, 0.8)
		return
	rig.play("Run" if _moving else "Idle")


func _find_mob(snap: Dictionary, id: String) -> Dictionary:
	for monster in snap.get("monsters", []):
		if monster.id == id:
			return monster
	return {}


func _my_position() -> Vector3:
	var players: Dictionary = _transport.snapshot().get("players", {})
	var me: Dictionary = players.get(_transport.my_id(), {})
	if me.is_empty():
		return Vector3.ZERO
	return Vector3(me.x, 0, me.z)


func _draw_state() -> void:
	var snap := _transport.snapshot()
	# 차원문으로 옮겼으면 존을 통째로 다시 짓는다
	var zone_now := str(snap.get("zone", ""))
	if zone_now != "" and zone_now != _shown_zone:
		_build_zone(zone_now)

	var players: Dictionary = snap.get("players", {})
	var me: Dictionary = players.get(_transport.my_id(), {})
	if me.is_empty():
		return

	_player.position = Vector3(me.x, _player_y, me.z)
	_player.rotation.y = me.rot
	_play_player_clip(me)

	# 뒤 위에서 내려다본다. 지금은 고정 각도다
	_camera.position = _player.position + Vector3(0, 14, 12)
	_camera.look_at(_player.position, Vector3.UP)

	# 쫓아오는 놈들이 실제로 움직인다. 자리는 World 가 정하고 여기서는 따라 그린다
	for monster in snap.get("monsters", []):
		var node: Node3D = _mob_nodes.get(monster.id)
		if node == null:
			continue
		node.visible = int(monster.hp) > 0
		if not node.visible:
			continue
		node.position.x = monster.x
		node.position.z = monster.z
		node.rotation.y = monster.get("rot", 0.0)
		if node is Rig:
			var state := str(monster.get("state", "idle"))
			if state == "chase":
				node.play("Run")
			elif state == "attack":
				node.play("Attack")
			else:
				node.play("Idle")

	var alive := 0
	for monster in snap.get("monsters", []):
		if int(monster.hp) > 0:
			alive += 1
	_player.visible = not bool(me.get("dead", false))

	_hp_bar.max_value = me.stats.maxHp
	_hp_bar.value = me.hp

	_label.text = "%s   %d레벨   체력 %d/%d   경험치 %d/%d\n몬스터 %d/%d   %d fps\n%s" % [
		GameData.zone(zone_now).get("name", zone_now),
		me.level,
		me.hp,
		me.stats.maxHp,
		me.exp,
		Combat.exp_to_next(int(me.level)),
		alive,
		snap.get("monsters", []).size(),
		Engine.get_frames_per_second(),
		_last_event,
	]
