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


func _ready() -> void:
	_transport = LocalTransport.new()
	add_child(_transport)
	var zone_id := GameData.start_zone()
	_transport.open(zone_id)

	var zone := GameData.zone(zone_id)
	_half_size = Movement.zone_half_size(float(zone.get("size", 92)))
	_build(zone)


func _build(zone: Dictionary) -> void:
	var env: Dictionary = zone.get("env", {})
	var size := float(zone.get("size", 92))

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
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = float(env.get("sunIntensity", 2.7))
	sun.rotation_degrees = Vector3(-50, -35, 0)
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(env.get("groundTint", "#6a665c"))
	ground.material_override = ground_mat
	add_child(ground)

	# 존 경계 — 여기까지만 걸어갈 수 있다 (Movement.zone_half_size)
	var edge := MeshInstance3D.new()
	var edge_mesh := PlaneMesh.new()
	edge_mesh.size = Vector2(_half_size * 2.0, _half_size * 2.0)
	edge.mesh = edge_mesh
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(env.get("grassDark", "#5c6a3c"))
	edge.material_override = edge_mat
	edge.position.y = 0.01
	add_child(edge)

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
	if _target == Vector3.INF:
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
	var players: Dictionary = _transport.snapshot().get("players", {})
	var me: Dictionary = players.get(_transport.my_id(), {})
	if me.is_empty():
		return

	_player.position = Vector3(me.x, 0.9, me.z)
	_player.rotation.y = me.rot

	# 뒤 위에서 내려다본다. 지금은 고정 각도다
	_camera.position = _player.position + Vector3(0, 14, 12)
	_camera.look_at(_player.position, Vector3.UP)

	_label.text = "zone %s  x %.1f  z %.1f  edge %.0f  %d fps" % [
		_transport.snapshot().get("zone", "?"),
		me.x,
		me.z,
		_half_size,
		Engine.get_frames_per_second(),
	]
