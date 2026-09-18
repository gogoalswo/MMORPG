class_name HpBar3D
extends Node3D

## 머리 위에 뜨는 체력 막대.
##
## **에셋을 쓰지 않는다.** 고리(`select_ring.gd`)·피격(`hit_fx.gd`)과 같은 이유로
## 코드로 짓는다 — 색·크기가 상수라 고쳐서 바로 보고, 에셋을 안 받은 사람도 보인다.
##
## **몸에 자식으로 달지 않는다.** 몬스터 노드 밑에 넣으면 피격 붉히기가
## `HitFx.meshes_of` 로 자식 메시를 전부 찾아 막대까지 빨갛게 칠하고, 머리 높이를
## 재는 AABB 에도 막대가 섞인다. 그래서 고리와 같이 **옆에 세우고 따라다니게** 한다.
##
## **판정에는 쓰지 않는다.** hp/max_hp 는 스냅샷 값을 그대로 그린다.

## 막대 크기(m). 카메라가 화면 세로 14.3m 를 보므로 720p 에서 1m = 41px →
## 가로 1.3m 는 53px, 세로 0.2m 는 8px 다 (hit_fx.gd 와 같은 환산).
## **몬스터 크기를 따라가지 않는다** — 보스에서만 커지면 "얼마나 남았나" 를
## 재는 자가 놈마다 달라진다. 고리 두께와 같은 이유다
const WIDTH := 1.3
const HEIGHT := 0.2
## 바탕이 채움보다 이만큼 밖으로 나온다 (테두리 겸 바닥판)
const BORDER := 0.05
## 머리 꼭대기에서 이만큼 더 띄운다. 붙이면 모델 머리·뿔에 걸린다
const GAP := 0.3

## 내 것은 초록, 몬스터는 붉은색 — 한 화면에 같이 떠도 갈린다.
## 금색 고리(#ffcf5a)·보스 예고 원(빨강 테두리)과 겹치지 않는 값이다
const COLOR_PLAYER := Color("#4fd964")
const COLOR_MOB := Color("#e8483c")
const COLOR_BACK := Color(0.06, 0.05, 0.05, 0.75)

var _back: MeshInstance3D
var _fill: MeshInstance3D
var _ratio := -1.0
## 바닥에서 머리 위까지의 높이. 만들 때 한 번만 재고 그 뒤로는 안 잰다 —
## 동작 중에 AABB 가 조금씩 흔들려 막대가 위아래로 떨린다
var _head := 0.0


## 막대를 세운다. `body` 는 따라다닐 몸(기둥이든 모델이든)이고,
## 높이는 여기서 한 번 잰다. 자리는 `follow` 가 잡는다
static func create(parent: Node3D, body: Node3D, color: Color) -> HpBar3D:
	var bar := HpBar3D.new()
	parent.add_child(bar)
	bar._head = head_height(body)
	bar._build(color)
	return bar


## 바닥에서 머리 꼭대기까지의 높이(m). 기둥은 원점이 가운데, 모델은 발이라
## 원점으로 재면 둘이 어긋난다 — **몸은 바닥(y=0)에 서 있으므로 월드에서 잰다**
static func head_height(body: Node3D, fallback := 1.8) -> float:
	if body == null or not is_instance_valid(body):
		return fallback + GAP
	var box := AABB()
	var first := true
	for mesh in HitFx.meshes_of(body):
		var world: AABB = mesh.global_transform * mesh.get_aabb()
		box = world if first else box.merge(world)
		first = false
	if first:
		return fallback + GAP
	return box.position.y + box.size.y + GAP


func _build(color: Color) -> void:
	_back = MeshInstance3D.new()
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(WIDTH + BORDER * 2.0, HEIGHT + BORDER * 2.0)
	_back.mesh = back_mesh
	_back.material_override = _material(COLOR_BACK, 0)
	add_child(_back)

	_fill = MeshInstance3D.new()
	_fill.mesh = QuadMesh.new()
	_fill.material_override = _material(color, 1)
	add_child(_fill)
	_set_ratio(1.0)


## 항상 카메라를 보고(billboard), 몸이나 바닥에 묻히지 않게 깊이 검사를 끈다.
## NPC 이름표(Label3D)와 같은 규칙이다
func _material(color: Color, priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = priority
	return mat


## 몸 머리 위로 옮기고 남은 체력을 그린다. `at` 은 발밑 자리, `ratio` 는 0~1.
## 자리를 **판정이 준 좌표에서** 받는 것은 고리(`select_ring.gd`)와 같다 —
## 그려 둔 몸에서 읽으면 그 몸을 옮기기 전인지 뒤인지에 따라 한 프레임 늦는다
func follow(at: Vector3, ratio: float) -> void:
	position = Vector3(at.x, _head, at.z)
	_set_ratio(ratio)


## 채움은 **왼쪽 끝을 붙잡고** 줄어든다.
##
## 노드를 옮겨서 맞추면 안 된다 — billboard 는 메시만 카메라 쪽으로 돌리므로
## 자식 노드를 월드 x 로 밀면 카메라가 돌 때 막대에서 떨어져 나간다.
## 그래서 `QuadMesh.center_offset` 으로 **메시 안에서** 민다
func _set_ratio(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _ratio):
		return
	_ratio = clamped
	var mesh: QuadMesh = _fill.mesh
	# 0 이면 그리지 않는다 (크기 0 인 메시는 고도가 경고를 낸다)
	_fill.visible = clamped > 0.0
	if not _fill.visible:
		return
	mesh.size = Vector2(WIDTH * clamped, HEIGHT)
	mesh.center_offset = Vector3(-WIDTH * 0.5 + WIDTH * clamped * 0.5, 0.0, 0.0)


func ratio() -> float:
	return _ratio
