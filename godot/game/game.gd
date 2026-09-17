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
var _player: MeshInstance3D
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


func _ready() -> void:
	_transport = LocalTransport.new()
	add_child(_transport)
	_transport.open(GameData.start_zone())
	_build_persistent()


## 존이 바뀌어도 살아 있는 것들
func _build_persistent() -> void:
	_player = MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = Movement.PLAYER_RADIUS
	body.height = 1.8
	_player.mesh = body
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color("#e8d7b0")
	_player.material_override = body_mat
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
	_label = Label.new()
	# ASCII 만 쓴다 — 고도 기본 폰트에 한글 글리프가 없다
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 28)
	ui.add_child(_label)


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
	# 모델은 5단계에서 붙인다 — 지금은 몸 반지름만큼의 기둥이다
	for monster in _transport.snapshot().get("monsters", []):
		var body := MeshInstance3D.new()
		var shape := CapsuleMesh.new()
		shape.radius = monster.r
		shape.height = maxf(monster.r * 2.0 + 0.1, 1.6 * monster.scale)
		body.mesh = shape
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(monster.color)
		if monster.boss:
			mat.emission_enabled = true
			mat.emission = Color(monster.color) * 0.6
		body.material_override = mat
		body.position = Vector3(monster.x, shape.height * 0.5, monster.z)
		_zone_node.add_child(body)


func _unhandled_input(event: InputEvent) -> void:
	# 터치는 기본 설정이 마우스로 바꿔 주므로 이 한 줄이 폰도 덮는다
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _ground_point(event.position)
		if hit != Vector3.INF:
			_target = hit
			_marker.position = hit + Vector3(0, 0.05, 0)
			_marker.visible = true


## 화면의 한 점이 바닥의 어디인지
func _ground_point(screen: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.INF
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	return hit if hit != null else Vector3.INF


func _process(delta: float) -> void:
	_send_input(delta)
	_draw_state()


## 눌러 둔 자리로 향하는 방향을 만들어 보낸다. **요청일 뿐이고 판정은 World 가 한다.**
func _send_input(delta: float) -> void:
	if _target == Vector3.INF or _zone_node == null:
		return
	var me := _my_position()
	var to := Vector2(_target.x - me.x, _target.z - me.z)
	if to.length() <= STOP_DISTANCE:
		_target = Vector3.INF
		_marker.visible = false
		return
	var dir := to.normalized()
	_seq += 1
	_transport.send(&"input", {"seq": _seq, "dx": dir.x, "dz": dir.y, "dt": delta})


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

	_player.position = Vector3(me.x, 0.9, me.z)
	_player.rotation.y = me.rot

	# 뒤 위에서 내려다본다. 지금은 고정 각도다
	_camera.position = _player.position + Vector3(0, 14, 12)
	_camera.look_at(_player.position, Vector3.UP)

	_label.text = "zone %s  x %.1f  z %.1f  mobs %d  %d fps" % [
		zone_now,
		me.x,
		me.z,
		snap.get("monsters", []).size(),
		Engine.get_frames_per_second(),
	]
