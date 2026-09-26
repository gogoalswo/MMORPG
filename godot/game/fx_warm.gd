class_name FxWarm
extends Node

## **이펙트 셰이더를 미리 굽는다** — 스킬을 처음 쓸 때 멈칫하지 않게.
##
## 고도는 재질을 **처음 그리는 순간** 셰이더를 컴파일한다. 가상 화면에서 재 보니
## 할퀴기는 처음 쓸 때 330ms, 낙뢰는 230ms 가 튀었다 (2026-09-23 "스킬 사용하면
## 히치가 걸려"). 웹(WebGL)은 컴파일이 특히 느리다.
##
## 그래서 게임을 열 때 **이펙트를 한 벌씩 실제로 띄워** 작은 `SubViewport` 에 그린다.
## 이펙트는 전용 레이어(`LAYER`)에만 두고 본 화면 카메라는 그 레이어를 안 보므로
## 사람 눈에는 아무것도 안 보인다.
##
## **구운 셰이더가 남으려면 같은 재질이 어딘가 살아 있어야 한다** ★ —
## `StandardMaterial3D` 는 같은 설정의 재질이 하나도 안 남으면 셰이더를 버린다.
## 여기서 띄운 것은 다 돌면 지워지므로, 그 재질을 붙드는 것은 게임이 미리 채워 둔
## 이펙트 풀(`FxPool.fill`)이다. 풀이 이것보다 **먼저** 차 있어야 한다 (2026-09-23 —
## 풀이 없을 때는 이펙트가 다 꺼질 때마다 셰이더를 다시 지었다).
##
## **실제 이펙트를 띄우는 이유** — 재질만 모아 그리면 파티클(멀티메시)·빌보드·
## 글자(Label3D)처럼 **그리는 방식마다 따로 컴파일되는 변형**을 놓친다.
## 새 이펙트를 만들면 `_spawn` 에 한 줄 더한다.

## 렌더 레이어 20 — 다른 곳에서 안 쓴다
const LAYER := 1 << 19
## 이펙트가 다 돌 만큼 (낙뢰가 가장 길다)
const HOLD := 1.6

static var _done := false

var _view: SubViewport
var _stage: Node3D
var _t := 0.0


## 한 게임에 한 번. `main_camera` 에서 레이어를 빼고 굽기 시작한다
static func run(parent: Node, main_camera: Camera3D, font: Font) -> void:
	if _done:
		return
	_done = true
	main_camera.cull_mask &= ~LAYER
	var warm := FxWarm.new()
	warm.name = "FxWarm"
	parent.add_child(warm)
	warm._start(font)


func _start(font: Font) -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(96, 96)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	# 멀리 떨어진 자리 — 본 화면 광원·그림자와 섞이지 않게
	_stage = Node3D.new()
	_stage.position = Vector3(0.0, -200.0, 0.0)
	_view.add_child(_stage)
	var cam := Camera3D.new()
	cam.cull_mask = LAYER
	_view.add_child(cam)
	cam.global_position = _stage.position + Vector3(0.0, 6.0, 8.0)
	cam.look_at(_stage.position + Vector3.UP, Vector3.UP)
	_spawn(font)
	_hide()


func _spawn(font: Font) -> void:
	SkillFx.claw(_stage, Vector3.ZERO, 0.0)
	LightningFx.bolt(_stage, Vector3.ZERO, 0.0)
	QuakeFx.slam(_stage, Vector3.ZERO, 0.0)
	# 강화 이펙트(토네이도·진흙 셰이더와 방출기)도 한 번 띄워 굽는다
	QuakeFx.slam(_stage, Vector3.ZERO, 0.0, true, true)
	IceFx.burst(_stage, Vector3.ZERO, 0.0)
	# 주먹 기운 — 태초가 모든 조각(빛무리·심·불티·불꽃·빛알·빛살)을 다 가진다.
	# 재질은 FistAura 가 등급마다 붙들고 있어 셰이더가 남는다
	_stage.add_child(FistAura.build(7, Items.max_enhance()))
	# 장비 스킨 — 무늬 셰이더 하나(등급은 uniform)와 오로라 한 겹. 처음 갑옷을 입을 때 굽지 않게
	var armor := MeshInstance3D.new()
	armor.mesh = SphereMesh.new()
	armor.material_override = Armor.material(7)
	_stage.add_child(armor)
	# 장비 오로라 — 태초가 모든 조각(빛·불티·불꽃·심·빛알)을 다 가진다
	var gear_aura := GearAura.new()
	gear_aura._grade = 7
	gear_aura._box = AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.2, 0.2))
	gear_aura._build()
	_stage.add_child(gear_aura)
	for crit in [false, true]:
		HitFx.spawn(_stage, Vector3.UP, {
			"amount": 1234, "crit": crit, "heal": false, "target_kind": "monster",
		}, font)


func _process(delta: float) -> void:
	# 이펙트가 도는 동안 새로 붙는 것(연타의 불꽃·낙뢰의 다음 번개)도 가려야 한다
	_hide()
	_t += delta
	if _t >= HOLD:
		queue_free()


## 무대 아래 모든 것을 전용 레이어로. 빛은 무대만 비추게 한다
func _hide() -> void:
	for node in _stage.find_children("*", "", true, false):
		if node is VisualInstance3D:
			node.layers = LAYER
		if node is Light3D:
			node.light_cull_mask = LAYER
