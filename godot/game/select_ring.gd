class_name SelectRing
extends Node3D

## 골라 둔 몬스터 발밑에서 도는 고리.
##
## **에셋을 쓰지 않는다.** 피격 이펙트(`hit_fx.gd`)와 같은 이유로 코드로 짓는다 —
## 에셋을 안 받은 사람도 보여야 하고, 색·두께·도는 속도가 상수라 고쳐서 바로 본다.
##
## **판정에는 쓰지 않는다.** 누구를 맞출지는 `World._pick_target` 이 정한다
## (docs/features/godot-migration.md 의 "대상은 서버가 고른다"). 이 고리는
## "지금 이놈을 눌러 뒀다" 는 표시일 뿐이다.

## 몸 반지름 바깥으로 이만큼 더 나간다. 몸에 딱 붙이면 모델 발에 가려진다
const MARGIN := 0.35
## 고리 두께(m). 카메라가 화면 세로 14.3m 를 보므로 720p 에서 1m = 41px →
## 0.22m 는 9px 다. 이보다 얇으면 폰에서 안 보인다 (hit_fx.gd 와 같은 환산)
const THICKNESS := 0.22
## 바닥에서 띄우는 높이. 차원문 원반(0.04)·보스 예고 원(0.06)보다 위에 둔다
const HEIGHT := 0.08
## 도는 속도(rad/s). 돌지 않으면 바닥 무늬처럼 보여서 눈에 안 띈다
const SPIN := 1.2
## 커졌다 작아지는 폭과 속도
const PULSE := 0.06
const PULSE_SPEED := 4.0

## 보스 예고 원은 빨강, 차원문은 파랑이라 겹치지 않는 금색을 쓴다
const COLOR := Color("#ffcf5a")

var _ring: MeshInstance3D
var _radius := -1.0
var _t := 0.0


## 고리를 세운다. 자리는 `follow` 가 잡으므로 여기서는 안 정한다
static func create(parent: Node3D) -> SelectRing:
	var node := SelectRing.new()
	parent.add_child(node)
	node._build()
	return node


func _build() -> void:
	_ring = MeshInstance3D.new()
	_ring.mesh = TorusMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(COLOR, 0.9)
	mat.emission_enabled = true
	mat.emission = COLOR
	mat.emission_energy_multiplier = 1.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = mat
	add_child(_ring)


## 고른 놈 발밑으로 옮기고 돌린다. `radius` 는 몬스터 몸 반지름이다.
##
## **두께는 몬스터 크기를 따라가지 않는다** — 노드를 통째로 키우면 큰 보스에서는
## 굵고 작은 놈에서는 실처럼 가늘어진다. 그래서 반지름은 메시에 넣고(바뀔 때만),
## 커졌다 작아지는 것만 scale 로 한다
func follow(at: Vector3, radius: float, delta: float) -> void:
	if not is_equal_approx(radius, _radius):
		_radius = radius
		var torus: TorusMesh = _ring.mesh
		torus.outer_radius = radius + MARGIN
		torus.inner_radius = maxf(torus.outer_radius - THICKNESS, 0.05)

	# at.y 는 발밑 땅 높이다 (지형이 없는 존은 0)
	position = Vector3(at.x, at.y + HEIGHT, at.z)
	_t += delta
	_ring.rotation.y = _t * SPIN
	var pulse := 1.0 + PULSE * sin(_t * PULSE_SPEED)
	_ring.scale = Vector3(pulse, 1.0, pulse)
