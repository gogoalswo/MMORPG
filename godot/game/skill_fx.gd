class_name SkillFx
extends Node3D

## 스킬을 쓸 때 시전자 앞에서 터지는 연출. 지금은 **할퀴기(`rising_kick`)** 하나다.
##
## **에셋을 쓰지 않는다.** 발톱 자국을 이미지로 굽지 않고 `ArrayMesh` 로 짓는다 —
## 피격 이펙트(`hit_fx.gd`)와 같은 이유다. 에셋을 안 받은 사람도 보여야 하고,
## 색·시간·크기가 전부 상수라 고쳐서 바로 확인할 수 있어야 한다 (2026-09-17 지시).
##
## **판정을 하지 않는다.** `World` 가 낸 `skill` 이벤트를 받아 그리기만 한다.
## 이펙트가 하나 빠져도 게임은 그대로 돈다.
##
## 스스로 `queue_free` 하므로 부르는 쪽이 목록을 들고 있을 필요가 없다.

## 발톱이 양쪽에서 들어온다 — 왼쪽에서 한 번, 오른쪽에서 한 번.
## **한 세트 안의 가닥은 나란하고, 두 세트는 서로 반대로 긋는다.** 각을 제각각
## 벌리면 할퀸 자국이 아니라 별표가 되고, 한쪽으로만 그으면 빗금이 된다.
const SETS := 2
const STROKES := 3

## 자국 하나의 크기. **미터가 아니라 px 로 정한다** — 카메라가 화면 세로 14.3m 를
## 보므로 720p 에서 1m 가 41px 다 ([hit-effects.md](../../docs/features/hit-effects.md)).
## 길이 1.6m = 66px, 폭 0.13m = 5px — 피격 파편(6px)만 한 굵기다.
## **폭은 길이의 1/12 쯤이어야 한다.** 더 굵으면 넓적한 마름모가 되고, 더 가늘면
## 이 카메라에서 3px 이라 배경에 묻힌다
const LENGTH := 1.6
const WIDTH := 0.13
## 곧기만 하면 빗금이라 살짝 휜다
const BOW := 0.14

## 긋는 각(rad). 두 세트가 +0.7 / -0.7 로 **X 로 엇갈린다**
const TILT := 0.7
## 같은 세트 안에서만 각을 이만큼 흔든다. 세트끼리 흔들면 나란한 맛이 사라진다
const JITTER := 0.07
## 가닥 사이 간격 — 자국에 **수직인 방향**으로 벌린다
const GAP := 0.3
## 세트가 좌우로 치우치는 양. 양쪽에서 들어와 가운데서 만나는 그림이다
const SPREAD := 0.26

## 두 번째 세트가 늦게 들어오는 시간. 동시에 그으면 X 가 한 번에 찍혀 손이
## 두 번 지나간 것으로 안 읽힌다
const SET_DELAY := 0.09
## 같은 세트 안에서 가닥이 조금씩 엇갈려 나오는 간격
const STROKE_DELAY := 0.02
## 한 가닥이 그어지는 시간. 이보다 길면 손톱이 아니라 자라나는 선이다
const DRAW := 0.1
## 한 가닥이 떠 있는 시간
const LIFE := 0.42

## 시전자 앞 얼마에 그리나. **화면이 아니라 캐릭터가 보는 쪽**이어야
## "내가 앞을 긁었다" 가 된다
const FORWARD := 1.1
## 가슴 높이. 발밑에 그리면 긁은 것으로 안 보인다
const HEIGHT := 1.05

## 손톱 자국 — 푸른 흰빛. 피해 숫자(연노랑)·치명타(주황)·피격(붉은색)과
## 한 화면에서 갈려야 해서 찬 색으로 골랐다 (`hit_fx.gd` 의 색 표)
const COLOR_CLAW := Color("#bfe4ff")

## [{node, mat, delay}, ...]
var _strokes: Array = []
var _t := 0.0
var _span := 0.0


## 할퀴기 자국을 터뜨린다.
##
## `at` 은 시전자 발밑(월드 좌표), `facing` 은 시전자가 보는 쪽(rad, `player.rot`).
static func claw(parent: Node3D, at: Vector3, facing: float) -> SkillFx:
	var fx := SkillFx.new()
	fx.position = at + Vector3(sin(facing) * FORWARD, HEIGHT, cos(facing) * FORWARD)
	# **자국은 화면을 정면으로 보게 세운다.** 월드 방향으로 세우면 카메라 각에 따라
	# 옆으로 누워 선 하나로 보인다. 카메라가 고정각이라(요 45·피치 42) 그 시선에
	# 수직인 평면을 그대로 만들 수 있다 — 로컬 X 가 화면 가로, 로컬 Y 가 화면 세로다
	fx.rotation = Vector3(-deg_to_rad(CameraRig.PITCH), CameraRig.YAW, 0.0)
	parent.add_child(fx)
	fx._build()
	return fx


func _build() -> void:
	var mesh := _slash_mesh()
	for s in SETS:
		# 0 = 왼쪽에서 들어오는 손, 1 = 오른쪽에서 되긁는 손
		var tilt := TILT if s == 0 else -TILT
		var from_x := -SPREAD if s == 0 else SPREAD
		for i in STROKES:
			var angle := tilt + randf_range(-JITTER, JITTER)
			# 벌리는 방향은 자국에 수직이어야 세 가닥이 나란해 보인다
			var across := Vector3(-sin(tilt), cos(tilt), 0.0) * (float(i) - float(STROKES - 1) * 0.5) * GAP
			var node := MeshInstance3D.new()
			node.mesh = mesh
			node.position = Vector3(from_x, 0.0, 0.0) + across
			node.rotation.z = angle
			var mat := _glow()
			node.material_override = mat
			node.visible = false
			add_child(node)
			var delay := float(s) * SET_DELAY + float(i) * STROKE_DELAY
			_strokes.append({"node": node, "mat": mat, "delay": delay})
			_span = maxf(_span, delay + LIFE)


func _process(delta: float) -> void:
	_t += delta
	for stroke in _strokes:
		var node: MeshInstance3D = stroke.node
		var t: float = _t - stroke.delay
		if t < 0.0:
			continue
		node.visible = t < LIFE
		# **그어지는 동안 길어진다.** 자국이 로컬 X 를 따라 뻗으므로 x 만 늘린다
		var drawn := clampf(t / DRAW, 0.0, 1.0)
		node.scale.x = lerpf(0.25, 1.0, drawn)
		# **빠르게 켜고 · 떠 있는 동안 유지하다 · 끝에서 끈다.** 처음부터 옅어지면
		# 가장 커지는 순간이 가장 투명한 순간과 겹쳐 어느 프레임에도 안 걸린다
		var mat: StandardMaterial3D = stroke.mat
		mat.albedo_color.a = clampf((LIFE - t) / (LIFE * 0.35), 0.0, 1.0)

	if _t >= _span:
		queue_free()


## 가운데가 굵고 양 끝이 뾰족하며 살짝 휜 띠. 폭이 일정한 막대면 끝이 뭉툭해서
## "막대를 놓았다" 로 보인다
static func _slash_mesh() -> ArrayMesh:
	var steps := 14
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var a := _edge(t0)
		var b := _edge(t1)
		# 앞뒤 어느 쪽에서 봐도 보여야 한다 (재질에서 컬링을 끈다)
		tool.add_vertex(a[0])
		tool.add_vertex(a[1])
		tool.add_vertex(b[0])
		tool.add_vertex(b[0])
		tool.add_vertex(a[1])
		tool.add_vertex(b[1])
	return tool.commit()


## 길이 방향 t(0~1) 에서 띠의 위·아래 점
static func _edge(t: float) -> Array:
	var x := (t - 0.5) * LENGTH
	# 휨 — 가운데가 위로 부푼다
	var bow := sin(t * PI) * BOW
	# 굵기 — 가운데가 가장 굵고 양 끝이 0 으로 모인다 (지수가 낮을수록 끝이 길게 뾰족)
	var half := pow(sin(t * PI), 0.65) * WIDTH * 0.5
	return [Vector3(x, bow + half, 0.0), Vector3(x, bow - half, 0.0)]


## 조명을 받지 않는 가산 혼합. 겹칠수록 밝아지고 어두운 사냥터에서도 같게 읽힌다.
## **깊이 검사를 끈다** — 몸 앞에서 터지므로 켜 두면 몸통이 자국을 가린다
static func _glow() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_CLAW
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	return mat
