class_name TrainerPortraits
extends Node

## 트레이너 카드 그림을 **3D 모델로 찍는다** (2026-10-06 요청: "왼쪽 이미지도 3D 모델로 나오도록 설정해").
##
## 카드 53장마다 3D 를 띄워 두면 폰에서 무겁다 — 모델 53벌(한 벌 1MB)이 메모리에 같이 뜨고 매 프레임 그린다.
## 그래서 **보이지 않는 무대 하나**(`SubViewport`)에서 한 명씩 세워 대기 자세로 한 장 찍고, 그 그림을 카드에 쓴다.
## 빛·각도는 오른쪽 무대(`TrainerStage.build_world` · `frame`)와 같다. 찍은 그림은 **판이 끝날 때까지 기억**한다
## (`_cache` — 창을 다시 열면 바로 뜬다). 찍는 동안·못 찍는 곳(헤드리스 테스트)에서는 원화가 대신 선다.
## → docs/features/trainers.md "창"

## 한 장 찍었다 — 카드가 그림을 갈아 끼운다
signal baked(id: String, texture: Texture2D)

## 카드 그림 크기 (카드 칸 126×168 의 두 배 — 선명하게)
const SIZE := Vector2i(252, 336)

static var _cache: Dictionary = {}
## 찍어 봤는데 그림이 안 나온 것 — 다시 찍지 않는다 (헤드리스는 렌더러가 비어 있다)
static var _failed: Dictionary = {}

var _view: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _queue: Array = []
var _busy := false


func _ready() -> void:
	name = "TrainerPortraits"
	_view = SubViewport.new()
	_view.name = "portrait_view"
	_view.size = SIZE
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	var parts := TrainerStage.build_world(_view)
	_pivot = parts.pivot
	_camera = parts.camera


## 찍어 둔 그림 — 없으면 null
static func cached(id: String) -> Texture2D:
	return _cache.get(id, null)


## 찍을 것을 줄 세운다 (이미 찍었거나 못 찍은 것은 건너뛴다). 한 프레임에 한 명씩 찍는다
func request(ids: Array) -> void:
	for id in ids:
		if not _cache.has(id) and not _failed.has(id) and not (id in _queue):
			_queue.append(id)
	if not _busy and not _queue.is_empty():
		_run()


func pending() -> int:
	return _queue.size()


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		if not is_inside_tree():
			break
		var id: String = _queue.pop_front()
		var height := float(Trainers.trainer(id).get("height", Rig.HUMAN_HEIGHT))
		var rig := Rig.create(Trainers.look(id), height)
		if rig == null:
			_failed[id] = true
			continue
		_pivot.add_child(rig)
		rig.play("Idle")
		TrainerStage.frame(_camera, height)
		_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		# 동작이 뼈에 입혀지는 한 프레임 + 그려지는 한 프레임
		await get_tree().process_frame
		_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var image := _view.get_texture().get_image()
		rig.queue_free()
		if image == null or image.is_empty() or image.is_invisible():
			_failed[id] = true
			continue
		var texture := ImageTexture.create_from_image(image)
		_cache[id] = texture
		baked.emit(id, texture)
	_busy = false
