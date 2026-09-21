class_name SkillRange
extends Node3D

## **스킬이 실제로 훑은 자리**를 땅에 한 번 그린다 (테스트 단추로 켠다).
##
## 2026-09-21 에 만들었다. 설계(stat-balance.md 5장)는 "범위 스킬로 무리를
## 정리한다"가 전제라 **반경·각이 곧 사냥 속도**인데, 스킬마다 범위가 다르고
## 숫자(`range`·`arc`·`maxTargets`)만 봐서는 화면에서 얼마나 덮는지 알 수 없다.
##
## **모양을 화면이 다시 계산하지 않는다.** ★ `World.cast` 가 `_pick_targets` 에
## 넘긴 값 그대로를 `skillRange` 이벤트로 보내고, 여기서는 받은 대로만 그린다.
## 화면이 `skills.json` 을 다시 읽어 그리면 판정이 바뀔 때 조용히 갈라져서
## **"표시는 맞는데 안 맞는"** 최악의 디버그 도구가 된다.
##
## 판정이 보내는 모양은 한 가지뿐이다 — 중심 `(x, z)` · 반지름 `reach` ·
## `facing` 을 가운데로 한 각 `arc` 의 부채꼴. 원거리기가 날아가 터진 것은
## 중심이 착탄점이고 `arc` 가 한 바퀴(TAU)로 와서 같은 코드가 원을 그린다.
##
## 에셋을 쓰지 않는 이유는 `select_ring.gd` 와 같다 — 코드로 지어야 안 받은
## 사람에게도 보이고, 색·두께를 고쳐서 바로 본다.

## 테두리 두께(m). 카메라가 화면 세로 14.3m 를 보므로 720p 에서 1m = 41px →
## 0.3m 는 12px 다 (select_ring.gd 와 같은 환산)
const THICKNESS := 0.3
## 바닥에서 띄우는 높이. 보스 예고 원(0.06)·고른 표시 고리(0.08)보다 위에 둔다 —
## 겹쳤을 때 이게 가려지면 도구 구실을 못 한다
const HEIGHT := 0.11
## 몇 초 동안 보이나. 스킬 쿨타임보다 짧아야 다음 시전과 겹치지 않는다
const LIFE := 1.1
## 마지막 이만큼은 사라지며 흐려진다
const FADE := 0.45

## 보스 예고 원은 빨강, 차원문은 파랑, 고른 표시는 금색이라 겹치지 않는 청록을 쓴다
const COLOR := Color("#46e0d8")
const FILL_ALPHA := 0.18
const EDGE_ALPHA := 0.95

## 부채꼴을 몇 토막으로 자르나 — 한 바퀴 기준. 각이 좁으면 그만큼 적게 쓴다
const SEGMENTS := 72

var _fill: MeshInstance3D
var _edge: MeshInstance3D
var _age := 0.0


## 판정이 보낸 `skillRange` 이벤트 하나를 그린다
static func show_cast(parent: Node3D, payload: Dictionary) -> SkillRange:
	var node := SkillRange.new()
	parent.add_child(node)
	node.position = Vector3(
		float(payload.get("x", 0.0)), HEIGHT, float(payload.get("z", 0.0))
	)
	node._build(
		maxf(float(payload.get("reach", 1.0)), 0.1),
		clampf(float(payload.get("arc", TAU)), 0.05, TAU),
		float(payload.get("facing", 0.0))
	)
	return node


func _build(reach: float, arc: float, facing: float) -> void:
	var half := arc / 2.0
	var from := facing - half
	var to := facing + half

	_fill = _layer(_sector(reach, 0.0, from, to, arc), FILL_ALPHA)
	# 테두리는 **호와 두 변을 따로** 만든다. 호만 그리면 부채꼴인지 원인지
	# 구별이 안 되고, 각이 좁을수록 어느 쪽을 보고 있는지가 안 읽힌다
	var edge := _sector(reach, reach - THICKNESS, from, to, arc)
	if arc < TAU - 0.01:
		_spoke(edge, reach, from)
		_spoke(edge, reach, to)
	_edge = _layer(edge, EDGE_ALPHA)


## 두 반지름 사이의 띠. 안쪽 반지름이 0 이면 꽉 찬 부채꼴이 된다
func _sector(outer: float, inner: float, from: float, to: float, arc: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var steps := maxi(3, roundi(SEGMENTS * arc / TAU))
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a0 := lerpf(from, to, float(i) / steps)
		var a1 := lerpf(from, to, float(i + 1) / steps)
		_quad(
			mesh,
			_at(a0, maxf(inner, 0.0)), _at(a1, maxf(inner, 0.0)),
			_at(a1, outer), _at(a0, outer)
		)
	mesh.surface_end()
	return mesh


## 부채꼴의 곧은 변 하나 — 가운데에서 호까지 뻗는 굵기 `THICKNESS` 의 막대
func _spoke(mesh: ImmediateMesh, reach: float, a: float) -> void:
	var dir := Vector3(sin(a), 0.0, cos(a))
	var side := Vector3(dir.z, 0.0, -dir.x) * (THICKNESS * 0.5)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(mesh, -side, side, dir * reach + side, dir * reach - side)
	mesh.surface_end()


func _at(a: float, r: float) -> Vector3:
	return Vector3(sin(a) * r, 0.0, cos(a) * r)


## 네 점을 삼각형 둘로. 안쪽 반지름이 0 이면 두 점이 겹쳐 삼각형 하나가 찌그러지는데,
## 넓이가 0 이라 그려지지 않을 뿐 탈은 안 난다
func _quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		mesh.surface_add_vertex(point)


func _layer(mesh: ImmediateMesh, alpha: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(COLOR, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 땅에 눕힌 면이라 위아래 중 어느 쪽이 앞인지 따질 것이 없다. 잘라내기를
	# 켜 두면 삼각형을 감은 방향에 따라 반쪽이 사라진다
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	add_child(node)
	return node


## 시간을 재고, 수명이 다했으면 true. `game.gd` 가 목록을 돌며 넘겨 준다
func tick(delta: float) -> bool:
	_age += delta
	if _age >= LIFE:
		return true
	var left := LIFE - _age
	var fade := 1.0 if left >= FADE else left / FADE
	_fill.material_override.albedo_color = Color(COLOR, FILL_ALPHA * fade)
	_edge.material_override.albedo_color = Color(COLOR, EDGE_ALPHA * fade)
	return false
