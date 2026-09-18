class_name PortalSwirl
extends Node3D

## 차원문 아치 **가운데에서 빨려들어가는 소용돌이.**
##
## 규칙(docs/features/effect-rules.md)대로 **고도에서 코드로** 짓는다 — 텍스처는
## `FxTex` 가 굽고, 띠는 파티클이 아니라 **직접 메시**(`LightningFx._half` 재사용)다.
##
## 빨려들어가 보이게 하는 것은 셋이다:
##
## 1. **로그 나선 팔** — 나선을 돌리면 각도마다 반지름이 밀려나므로, 돌리는 것만으로
##    무늬가 안쪽으로 흘러 보인다 (자기닮음 곡선이라 회전 = 축소와 같다). 돌아가는
##    방향이 반대면 뿜어 나오는 것으로 읽히니 부호를 바꾸지 않는다.
## 2. **끌려 들어가는 알갱이** — 안쪽으로 갈수록 빨라지고(각속도 ∝ 1/r) 작아진다.
##    가운데에 닿으면 바깥에서 다시 시작한다.
## 3. **가운데 빛** — 삼키는 구멍. 숨 쉬듯 미약하게만 흔들린다.
##
## **깊이 검사는 켠다.** 스킬 이펙트(`LightningFx.glow`)는 몸 앞을 스치고 사라지는
## 것이라 껐지만, 이건 월드에 계속 서 있는 것이라 끄면 앞을 지나는 캐릭터·몬스터를
## 뚫고 보인다.

## 소용돌이가 도는 빠르기(rad/s). 음수 방향으로 돌려야 안으로 빨려든다
const SPIN := 1.6

## 아치 구멍 가운데 — 모델 높이(= 반지름 × 2)의 비율. 1×1×1 정규화 모델이라
## 비율로 두면 문 크기가 바뀌어도 구멍 한가운데에 남는다
const CENTER := 0.47
## 소용돌이 반지름 — 같은 기준의 비율. 구멍 반너비가 0.26쯤이라 안쪽에 든다
const SPAN := 0.22

## 나선 팔
const ARMS := 5
## 팔 하나가 감기는 바퀴 수. 두 바퀴가 넘으면 실타래처럼 뭉친다
const TURNS := 1.15
const SEGMENTS := 28
## 안쪽 끝(바깥 반지름 대비). 0 이면 가운데에서 모든 팔이 한 점에 뭉쳐 별이 된다
const INNER := 0.12

## 한 팔은 **폭만 다른 3겹**이다 — 넓은 헤일로 + 색 빛 + 가는 흰 심
## (effect-rules.md 5절: 곁줄기를 따로 기울이면 세 줄로 갈라져 보인다)
const HALO_WIDTH := Vector2(0.55, 0.12)
const SHEEN_WIDTH := Vector2(0.19, 0.045)
const CORE_WIDTH := Vector2(0.05, 0.015)
## **색이 남아야 한다.** 흰 심을 굵게 얹었더니 소용돌이 전체가 하얘져서 문 색(#4aa8ff)이
## 사라졌다 (2026-09-18 캡처). 넓은 겹을 진하게, 흰 심은 가늘고 옅게 둔다
const HALO_ALPHA := 0.6
const SHEEN_ALPHA := 0.5
const CORE_ALPHA := 0.85
## 바깥 끝에서 **스며 나오듯** 옅어지는 구간(길이 비율). 0 이면 팔이 뚝 끊겨
## 소용돌이 둘레에 또렷한 원이 생긴다
const FADE_IN := 0.3

## 끌려 들어가는 알갱이
const MOTES := 18
const MOTE_SIZE := 0.22
## 반지름이 줄어드는 빠르기(바깥 반지름/초)
const MOTE_PULL := 0.85
## 가운데에서의 각속도 배수 — 1/r 이라 안쪽에서 빨라진다
const MOTE_SWIRL := 0.55
## 판 두께(앞뒤로 흩어지는 폭). 납작하면 종이에 그린 그림으로 보인다
const MOTE_DEPTH := 0.13

## 가운데 빛. 숨 쉬는 주기(초)와 흔들리는 폭
const CORE_SIZE := 0.7
const CORE_GLOW := 0.7
const BREATH := 1.7
const BREATH_AMOUNT := 0.12

## 문을 비추는 등. 밤 사냥터에서 문만 떠 있지 않게 바닥도 물들인다
const LIGHT_RANGE := 7.0
const LIGHT_ENERGY := 1.6

var _arms: Node3D
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _motes: Array[MeshInstance3D] = []
## 알갱이마다 [각도, 반지름, 앞뒤 자리]
var _mote_at: Array = []
var _rng := RandomNumberGenerator.new()
var _span := 1.0
var _t := 0.0


## 아치 구멍 가운데에 세운다. `radius` 는 문 판정 원(gate.radius), `color` 는 문 색,
## `facing` 은 모델이 바라보는 쪽(`Portal.create` 이 카메라 쪽으로 돌려 둔 각)
static func create(radius: float, color: Color, facing: float) -> PortalSwirl:
	var fx := PortalSwirl.new()
	fx.name = "Swirl"
	var model := radius * 2.0
	fx._span = model * SPAN
	# 구멍 한가운데, 아치와 같은 쪽을 본다 — 소용돌이는 문이 열린 **평면 안**에서 돈다
	fx.position = Vector3(0.0, model * CENTER, 0.0)
	fx.rotation.y = facing
	fx._build(color)
	return fx


func _build(color: Color) -> void:
	_rng.seed = 20260918

	_arms = Node3D.new()
	add_child(_arms)
	# 넓은 것부터 얹는다 — 가산 혼합이라 나중에 그린 가는 심이 가운데에서 더 밝다
	_arms.add_child(_layer(HALO_WIDTH, Color(color, HALO_ALPHA)))
	_arms.add_child(_layer(SHEEN_WIDTH, Color(color.lerp(Color.WHITE, 0.3), SHEEN_ALPHA)))
	_arms.add_child(_layer(CORE_WIDTH, Color(1.0, 1.0, 1.0, CORE_ALPHA)))

	_core = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(_span, _span) * CORE_SIZE
	_core.mesh = quad
	_core_mat = _dot_mat(Color(color.lerp(Color.WHITE, 0.45), CORE_GLOW))
	_core.material_override = _core_mat
	add_child(_core)

	var mote_mat := _dot_mat(color.lerp(Color.WHITE, 0.25))
	for i in MOTES:
		var mote := MeshInstance3D.new()
		var dot := QuadMesh.new()
		dot.size = Vector2(_span, _span) * MOTE_SIZE
		mote.mesh = dot
		mote.material_override = mote_mat
		add_child(mote)
		_motes.append(mote)
		# 처음부터 고르게 퍼져 있어야 한다 — 다 같이 바깥에서 출발하면 한 무리로 몰린다
		_mote_at.append([
			_rng.randf_range(0.0, TAU),
			_rng.randf_range(INNER, 1.0),
			_rng.randf_range(-MOTE_DEPTH, MOTE_DEPTH),
		])
	_place_motes()

	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = LIGHT_ENERGY
	lamp.omni_range = LIGHT_RANGE
	add_child(lamp)


func _process(delta: float) -> void:
	_t += delta
	# **음수로 돈다.** 로그 나선은 +로 돌리면 무늬가 바깥으로 밀려 뿜어 나오는 것이 된다
	_arms.rotation.z -= SPIN * delta
	for i in _motes.size():
		var at: Array = _mote_at[i]
		# 안쪽일수록 빠르다 — 각속도를 반지름으로 나눈다
		at[0] -= SPIN * MOTE_SWIRL / maxf(at[1], INNER) * delta
		at[1] -= MOTE_PULL * delta
		if at[1] <= INNER * 0.5:
			# 삼켜졌다 — 바깥에서 다시 들어온다
			at[0] = _rng.randf_range(0.0, TAU)
			at[1] = 1.0
			at[2] = _rng.randf_range(-MOTE_DEPTH, MOTE_DEPTH)
	_place_motes()
	var breath := 1.0 + sin(_t * TAU / BREATH) * BREATH_AMOUNT
	_core.scale = Vector3(breath, breath, 1.0)
	_core_mat.albedo_color.a = CORE_GLOW * breath


## 알갱이를 제 자리에 놓는다. 가운데로 갈수록 **작아지고 옅어진다** — 같은 크기로
## 사라지면 빨려드는 것이 아니라 그냥 꺼지는 것으로 보인다
func _place_motes() -> void:
	for i in _motes.size():
		var at: Array = _mote_at[i]
		var r: float = at[1]
		_motes[i].position = Vector3(cos(at[0]) * r * _span, sin(at[0]) * r * _span, at[2] * _span)
		var shrink: float = clampf(r, 0.0, 1.0)
		_motes[i].scale = Vector3.ONE * lerpf(0.35, 1.0, shrink)


## 나선 팔 ARMS 개를 한 겹으로 묶은 메시. 폭은 바깥(x)에서 안쪽(y)으로 좁아진다
func _layer(width: Vector2, color: Color) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for arm in ARMS:
		var path := _spiral(TAU * float(arm) / float(ARMS))
		for i in path.size() - 1:
			var t0 := float(i) / float(path.size() - 1)
			var t1 := float(i + 1) / float(path.size() - 1)
			# 폭 방향은 **소용돌이가 도는 평면 안**이다 — 평면 법선(z)과 진행 방향의 외적
			var side0 := _across(path, i) * lerpf(width.x, width.y, t0) * 0.5 * _span
			var side1 := _across(path, i + 1) * lerpf(width.x, width.y, t1) * 0.5 * _span
			# 바깥 끝은 옅게 — 꼭짓점 색으로 죈다 (`_glow_mat` 이 꼭짓점 색을 켜 둔다)
			tool.set_color(Color(1.0, 1.0, 1.0, smoothstep(0.0, FADE_IN, t0)))
			# 가장자리는 투명하고 가운데가 진한 반쪽 둘 — 테두리가 생기지 않는 자리다
			LightningFx._half(tool, path[i] - side0, path[i], path[i + 1] - side1, path[i + 1], 0.0)
			LightningFx._half(tool, path[i] + side0, path[i], path[i + 1] + side1, path[i + 1], 1.0)
	var node := MeshInstance3D.new()
	node.mesh = tool.commit()
	node.material_override = _glow_mat(color)
	return node


## 바깥에서 안으로 감기는 로그 나선. 반지름이 지수로 줄어야 **안쪽이 촘촘해진다** —
## 선형으로 줄이면 간격이 일정해서 소용돌이가 아니라 고리 뭉치로 보인다
func _spiral(start: float) -> PackedVector3Array:
	var path := PackedVector3Array()
	for i in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var angle := start + t * TURNS * TAU
		var r: float = pow(INNER, t) * _span
		path.append(Vector3(cos(angle) * r, sin(angle) * r, 0.0))
	return path


## 그 점에서의 폭 방향. 이웃한 두 토막의 평균으로 잡는다 —
## 토막마다 따로 잡으면 꺾인 자리에서 이음새가 벌어진다 (`LightningFx.ribbon` 과 같은 이유)
func _across(path: PackedVector3Array, i: int) -> Vector3:
	var last := path.size() - 1
	var along: Vector3
	if i == 0:
		along = path[1] - path[0]
	elif i == last:
		along = path[last] - path[last - 1]
	else:
		along = path[i + 1] - path[i - 1]
	if along.length() < 1e-6:
		return Vector3.RIGHT
	return Vector3.BACK.cross(along.normalized()).normalized()


## 조명을 안 받는 가산 혼합 띠. `LightningFx.glow` 와 같되 **깊이 검사를 켠다** —
## 월드에 계속 서 있는 것이라 끄면 앞을 지나는 캐릭터를 뚫고 보인다
func _glow_mat(color: Color) -> StandardMaterial3D:
	var mat := LightningFx.glow(color)
	mat.no_depth_test = false
	# 꼭짓점 색으로 바깥 끝을 죈다 — 켜지 않으면 `set_color` 가 통째로 무시된다
	mat.vertex_color_use_as_albedo = true
	return mat


## 가운데 빛·알갱이용 — 카메라를 마주 보는 둥근 점. 모서리가 없어야 한다
func _dot_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# **빌보드는 기본이 크기를 버린다** — 켜 두지 않으면 알갱이가 작아지지도,
	# 가운데 빛이 숨 쉬지도 않는다 (노드 scale 이 통째로 무시된다)
	mat.billboard_keep_scale = true
	mat.albedo_texture = FxTex.glow()
	mat.albedo_color = color
	return mat
