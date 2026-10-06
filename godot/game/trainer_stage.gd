class_name TrainerStage
extends Control

## 트레이너 창 오른쪽의 **3D 모델 무대** (2026-10-06 요청: "여기에 이미지로 나오는데, 3D 모델이 나오도록 변경해").
## 창 안에 작은 `SubViewport` 를 하나 두고 고른 트레이너의 모델(`trainer_<id>.glb`)을 세워 **대기 동작**을 튼다.
## 가만히 두면 천천히 돌고, **끌면 손으로 돌린다.** 모델 파일이 없으면 원화 그림으로 대신한다 → docs/features/trainers.md
##
## 카드 53장은 그림 그대로다 — 53개를 다 3D 로 띄우면 폰에서 무겁다. 무대는 하나뿐이고 창이 보일 때만 그린다.

## 가만히 둘 때 도는 빠르기 (라디안/초)
const SPIN := 0.35
## 끈 거리(px) → 회전(라디안)
const DRAG_TURN := 0.012
## 끈 뒤 이만큼(초) 지나면 다시 저절로 돈다
const DRAG_REST := 2.0
## 카메라 화각(도) — 좁게 잡아 원근을 죽인다 (게임 카메라와 같은 결)
const FOV := 26.0

var _box: SubViewportContainer
var _view: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _rig: Rig
var _fallback: TextureRect
var _shown := ""
var _dragging := false
var _rest := 0.0


static func make(size: Vector2) -> TrainerStage:
	var stage := TrainerStage.new()
	stage._build(size)
	return stage


func _build(size: Vector2) -> void:
	name = "stage"
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = SubViewportContainer.new()
	_box.stretch = true
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_box)
	_view = SubViewport.new()
	_view.name = "view"
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_box.add_child(_view)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.72, 0.66)
	environment.ambient_light_energy = 0.9
	env.environment = environment
	_view.add_child(env)
	# 왼쪽 위 앞에서 오는 빛 + 뒤에서 테두리를 살리는 빛
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -30, 0)
	key.light_energy = 1.3
	_view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 0.6
	_view.add_child(rim)

	_pivot = Node3D.new()
	_pivot.name = "pivot"
	_view.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.current = true
	_view.add_child(_camera)

	# 모델이 없으면(에셋을 안 받은 사람) 원화를 그 자리에 깐다
	_fallback = TextureRect.new()
	_fallback.name = "art"
	_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fallback.visible = false
	add_child(_fallback)


## 트레이너 하나를 세운다. 같은 트레이너면 다시 짓지 않는다 (돌던 각도도 그대로). `owned` 가 아니면 어둡게
func show_trainer(id: String, art: Texture2D, owned: bool) -> void:
	modulate = Color.WHITE if owned else Color(0.35, 0.35, 0.35)
	if id == _shown:
		return
	_shown = id
	if _rig != null:
		_rig.queue_free()
		_rig = null
	var info := Trainers.trainer(id)
	var height := float(info.get("height", Rig.HUMAN_HEIGHT))
	_rig = Rig.create(Trainers.look(id), height)
	_fallback.visible = _rig == null
	_box.visible = _rig != null
	_fallback.texture = art
	if _rig == null:
		return
	_pivot.add_child(_rig)
	_pivot.rotation.y = 0.0
	_rig.play("Idle")
	# 발끝부터 머리까지 화면 세로의 90% — 키가 달라도 같은 크기로 담는다
	var half := height * 0.5
	var distance := half / tan(deg_to_rad(FOV * 0.5)) / 0.9
	_camera.position = Vector3(0.0, half, distance)
	_camera.look_at(Vector3(0.0, half, 0.0))


## 지금 서 있는 모델 — 테스트가 본다 (없으면 null)
func rig() -> Rig:
	return _rig


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _rig == null:
		return
	if _dragging:
		return
	_rest = maxf(0.0, _rest - delta)
	if _rest <= 0.0:
		_pivot.rotation.y += SPIN * delta


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not event.pressed:
			_rest = DRAG_REST
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pivot.rotation.y += event.relative.x * DRAG_TURN
		accept_event()
