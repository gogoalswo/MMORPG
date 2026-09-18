class_name LightningFx
extends Node3D

## 낙뢰(`thunder_fall`) 스킬 연출. **한 지점에 번개가 세 번 겹쳐 떨어지고**,
## 떨어진 자리에서 **땅이 갈라지며 파편이 튄다.** 줄기는 **시전자 뒤 위쪽에서
## 앞으로** 내리꽂힌다 (2026-09-18 지시).
##
## ## 줄기는 파티클이 아니라 **리본 메시**다 ★
##
## 처음에는 가닥 메시를 `CPUParticles3D` 로 방출했다. 파티클이 정하는 것은
## "어디로 얼마나 빨리"뿐이라 **선의 모양을 자리마다 바꿀 수가 없고**, 화면에서
## 다발로 뭉친 실이 됐다 ("다른 프로젝트에서는 금방 잘 만드는데 넌 너무 엉뚱하게
## 만들고 있어", 2026-09-18). 지금은 **경로를 잡고 그 위에 리본을 깎아** 그린다:
##
## - **경로**(`trail`) — 시작점에서 꽂히는 자리까지, 중간을 누적 난수로 흩어
##   굽이치게 만든다. 양 끝은 제자리다
## - **리본**(`ribbon`) — 경로를 따라 폭을 주는데, **시선에 수직**으로 준다.
##   그래야 카메라가 어디서 보든 화면에서 같은 굵기로 보인다
## - **두 겹** — 굵은 파란 halo 위에 얇은 흰 코어. 한 겹 가산 혼합은 밝은
##   바닥에서 흰색으로 날아가 색이 아예 안 보인다
## - **매 프레임 다시 만든다**(`FLICK` 마다) — 지글거리는 것이 곧 번개다.
##   가만히 서 있는 판이 아니므로 "이미지 붙여 놓은 것 같다" 가 되지 않는다
##
## **알갱이인 것만 파티클이다** — 튀는 흙 파편 하나뿐이다
## → [hit-effects.md](../../docs/features/hit-effects.md) 의 "파티클로 만들 것과
## 메시로 만들 것".
##
## **판정을 하지 않는다.** `World` 가 낸 `skill` 이벤트를 받아 그리기만 한다.

## 번개가 몇 번 치나. **순차적으로 겹쳐서** 친다
const STRIKES := 3
## 다음 번개가 들어오는 간격
const STRIKE_GAP := 0.18
## 뒤로 갈수록 굵어진다 — 마지막 한 방이 가장 크다
const STRIKE_SWELL := 0.16
## 세 번이 **완전히 같은 자리**면 두 번째·세 번째가 안 보인다. 난수가 아니라
## 상수라 테스트가 같은 값을 읽는다
const JITTER: Array[Vector2] = [Vector2.ZERO, Vector2(0.3, -0.2), Vector2(-0.24, 0.28)]

## 떨어지는 자리 — 시전자가 보는 쪽 앞 몇 m. 스킬 사거리(4m)보다 짧아야
## "번개는 저기 떨어졌는데 안 맞았다" 가 안 된다 (`skills.ts` 의 `thunder_fall`)
const AHEAD := 2.8
## 줄기가 시작하는 높이 (720p 에서 266px — 캐릭터 키의 네 배)
const SKY := 7.0
## 시작점이 떨어지는 자리보다 얼마나 뒤인가. `AHEAD` 보다 크므로
## **시작점은 캐릭터보다 2.2m 뒤**다 — 그래서 번개가 뒤에서 앞으로 지나간다
const BEHIND := 5.0

## 경로를 몇 토막으로 나누나. 잘게 나눌수록 잔 떨림이 는다
## 토막이 잘면 **폭보다 짧아져** 꺾인 자리가 겹친다. 8.6m 를 열둘로 나누면
## 토막 0.7m 로 halo(0.95m)와 비슷해 이음새가 자연스럽다
const SEGMENTS := 12
## 주 줄기 몇 가닥. 하나면 심심하고, 셋 넘으면 다발로 뭉친다. 둘은 서로
## 조금 떨어진 자리에서 시작해 한 점으로 모인다
const BOLTS := 2
const BOLT_APART := 1.8
## 굽이치는 폭(m). 크면 번개가 아니라 리본이 나부낀다
const WOBBLE := 0.9
## **굵어야 번개다.** 코어 0.18m = 7px, halo 0.5m = 19px 이고 끝으로 갈수록
## 가늘어진다. 얇게 깎았더니 실이 됐다 (2026-09-18 에 두 번 헛돌았다) —
## 뭉쳐 보이는 원인은 굵기가 아니라 **가닥 수**였다
## **얇게** (2026-09-18 지시). 굵은 리본은 번개가 아니라 띠로 보인다 —
## 다만 파티클로 만들던 때처럼 3px 까지 깎지는 않는다. 그때 실이 된 것은
## 굵기가 아니라 **가닥이 뭉쳐서**였다
const CORE_WIDTH := 0.11
## halo 는 코어를 감싸는 **번짐**이다. 가장자리가 투명해지므로 굵어도 선이
## 지지 않는다
const HALO_WIDTH := 0.45
## 줄기가 살아 있는 시간과 **지글거리는 주기.** 45ms 마다 경로를 다시 만든다
const BOLT_LIFE := 0.3
const FLICK := 0.045
## 주 줄기에서 갈라지는 곁가지. 허공에서 끝난다
const FORKS := 2
const FORK_LENGTH := 2.4

## 갈라지는 땅. **중심에서 가지를 치며 뻗고 가늘어진다** — 파티클로 방사했더니
## 고른 별표가 됐다 (2026-09-18). 갈래마다 한 번 더 갈라진다
const CRACKS := 7
const CRACK_LENGTH := 3.2
## 금은 **한 겹이다.** 둘레에 밝은 돌빛을 한 겹 깔아 봤더니 갈라진 틈이 아니라
## **테두리를 두른 그림**이 됐다 (2026-09-18 에 지적받았다) — 가장자리는
## 그라디언트로만 죈다
const CRACK_WIDTH := 0.34
const CRACK_SEGMENTS := 5
## 금이 자라는 시간 — 0.14초에 걸쳐 중심에서 바깥으로 뻗는다.
## 한 번에 다 그리면 갈라진 것이 아니라 그려진 그림이다
const CRACK_GROW := 0.14
const CRACK_LIFE := 0.6

## 금과 파편이 나는 높이. 0 으로 두면 지면과 같은 면이라 깜빡인다
const GROUND := 0.05

## 튀는 흙 파편 — **여기만 파티클이다.** 위로 솟아 중력으로 떨어진다
const DEBRIS_COUNT := 10
const DEBRIS_SIZE := 0.2
const DEBRIS_SPEED_MIN := 6.0
const DEBRIS_SPEED_MAX := 13.0
const DEBRIS_SPREAD := 52.0
const DEBRIS_LIFE := 0.55
const DEBRIS_GRAVITY := -16.0

## **치는 순간 주위가 번쩍인다.** 번개로 읽게 하는 것은 줄기 모양만이 아니다
const LIGHT_RANGE := 9.0
const LIGHT_ENERGY := 7.0
const LIGHT_LIFE := 0.16

## 코어는 흰빛, halo 는 파랑, 금과 파편은 흙이다. 할퀴기(자홍)·피해 숫자(연노랑)·
## 치명타(주황)·피격(붉은색)과 한 화면에서 갈려야 한다
const COLOR_CORE := Color("#ffffff")
const COLOR_HALO := Color("#4a90ff")
const COLOR_CRACK := Color("#241a12")
const COLOR_DEBRIS := Color("#9c8163")

var _t := 0.0
var _span := 0.0


## 낙뢰를 떨어뜨린다.
##
## `at` 은 시전자 발밑(월드 좌표), `facing` 은 시전자가 보는 쪽(rad, `player.rot`).
static func bolt(parent: Node3D, at: Vector3, facing: float) -> LightningFx:
	var fx := LightningFx.new()
	# 떨어지는 자리는 **화면이 아니라 캐릭터가 보는 쪽** 앞이다
	fx.position = at + Vector3(sin(facing) * AHEAD, 0.0, cos(facing) * AHEAD)
	# **회전은 주지 않는다.** 번개는 하늘에서 땅으로 오는 것이라 월드 기준이어야
	# 하고, 리본의 폭도 월드 기준 시선으로 잰다. 보는 쪽은 시작점 좌표에 넣는다
	parent.add_child(fx)
	fx._build(facing)
	return fx


func _build(facing: float) -> void:
	for i in STRIKES:
		var strike := Strike.new()
		strike.plan(i, 1.0 + float(i) * STRIKE_SWELL, float(i) * STRIKE_GAP,
			JITTER[i % JITTER.size()], facing)
		add_child(strike)
		_span = maxf(_span, strike.at + strike.span())


func _process(delta: float) -> void:
	_t += delta
	if _t >= _span:
		queue_free()


## 카메라가 보는 쪽(월드). 요 45°·피치 42° 로 고정이라 상수에서 바로 나온다
## (`CameraRig.follow` 의 offset 을 뒤집은 것). **리본의 폭을 여기에 수직으로
## 줘야** 카메라 각이 어떻든 화면에서 같은 굵기로 보인다
static func view_dir() -> Vector3:
	var pitch := deg_to_rad(CameraRig.PITCH)
	return -Vector3(
		cos(pitch) * sin(CameraRig.YAW),
		sin(pitch),
		cos(pitch) * cos(CameraRig.YAW)
	).normalized()


## `from` 에서 `to` 까지 굽이치는 경로. **양 끝은 제자리다** — 시작점과 꽂히는
## 자리는 정해져 있고, 흔들리는 것은 중간뿐이다.
##
## 누적 난수(random walk)를 쓴다. 점마다 따로 흩으면 톱니가 되고, 누적하면
## **이어진 굽이**가 된다 — 실제 번개가 그렇게 생겼다
## `flat` 이면 **지면 안에서만** 흩어진다 — 금이 위아래로 굽으면 갈라진 자국이
## 아니라 솟아오른 뿌리가 된다 (헤드리스 테스트가 1.23m 솟은 것을 잡았다)
static func trail(from: Vector3, to: Vector3, segments: int, wobble: float,
		rng: RandomNumberGenerator, flat := false) -> PackedVector3Array:
	var span := to - from
	var along := span.normalized()
	var side := along.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var other := Vector3.ZERO if flat else along.cross(side).normalized()

	var path := PackedVector3Array()
	var drift_a := 0.0
	var drift_b := 0.0
	for i in segments + 1:
		var t := float(i) / float(segments)
		drift_a += rng.randfn(0.0, 0.5)
		drift_b += rng.randfn(0.0, 0.5)
		# 끝에서 0 으로 죈다 — 안 죄면 꽂히는 자리가 흔들린다
		var hold := sin(t * PI)
		path.append(from + span * t + (side * drift_a + other * drift_b) * wobble * hold)
	return path


## 경로 앞쪽 `grow`(0~1) 만큼만 남긴다 — 금이 **자라나게** 하는 데 쓴다
static func cut(path: PackedVector3Array, grow: float) -> PackedVector3Array:
	if grow >= 1.0:
		return path
	var last := float(path.size() - 1) * clampf(grow, 0.0, 1.0)
	var whole := int(floor(last))
	var out := PackedVector3Array()
	for i in whole + 1:
		out.append(path[i])
	if whole + 1 < path.size():
		out.append(path[whole].lerp(path[whole + 1], last - float(whole)))
	return out


## 경로들을 리본 한 장으로 깎는다. `head` 에서 `tail` 로 가늘어진다.
##
## `flat` 이면 폭을 **지면 안에서** 준다 (금). 아니면 **시선에 수직**으로 준다
## (줄기) — 그래야 카메라가 어디 있든 화면에서 같은 굵기다
static func ribbon(paths: Array, head: float, tail: float, flat: bool) -> ArrayMesh:
	var view := view_dir()
	var axis := Vector3.UP if flat else view
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drawn := 0
	for entry in paths:
		var path: PackedVector3Array = entry[0]
		var scale: float = entry[1]
		if path.size() < 2:
			continue
		var last := path.size() - 1

		# **폭 방향은 점마다 구한다 — 이웃한 두 토막의 평균으로.**
		# 토막마다 따로 사각형을 만들면 꺾인 자리에서 이음새가 벌어져
		# 화면에서 **판자 조각이 흩어진 것**처럼 보인다. 폭이 토막 길이보다
		# 굵을 때 특히 그렇다 (2026-09-18 캡처 — halo 0.95m 가 그랬다)
		var across: Array = []
		for i in path.size():
			var along: Vector3
			if i == 0:
				along = path[1] - path[0]
			elif i == last:
				along = path[last] - path[last - 1]
			else:
				along = path[i + 1] - path[i - 1]
			if along.length() < 1e-5:
				along = Vector3.FORWARD
			var side := axis.cross(along.normalized())
			if side.length() < 1e-4:
				side = Vector3.RIGHT
			across.append(side.normalized())

		for i in last:
			var wa: Vector3 = across[i] * lerpf(head, tail, float(i) / float(last)) * scale * 0.5
			var wb: Vector3 = across[i + 1] * lerpf(head, tail, float(i + 1) / float(last)) * scale * 0.5
			var a := path[i]
			var b := path[i + 1]
			# **가운데는 진하고 가장자리로 갈수록 투명하다.** 폭 전체를 같은
			# 알파로 채우면 양쪽에 또렷한 선이 생겨 **테두리를 두른 것**처럼
			# 보인다 (2026-09-18 에 지적받았다). 그래서 한 토막을 좌우 반으로
			# 나눠 바깥 꼭짓점의 알파를 0 으로 둔다
			_half(tool, a - wa, a, b - wb, b)
			_half(tool, a + wa, a, b + wb, b)
			drawn += 1
	if drawn == 0:
		return ArrayMesh.new()
	return tool.commit()


## 리본 한 토막의 반쪽. `edge` 쪽 꼭짓점은 투명하고 `mid` 쪽은 진하다 —
## 이 그라디언트가 **테두리를 지운다**. 앞뒤 어느 쪽에서 봐도 보여야 하므로
## 재질에서 컬링을 끈다
static func _half(tool: SurfaceTool, a_edge: Vector3, a_mid: Vector3,
		b_edge: Vector3, b_mid: Vector3) -> void:
	var clear := Color(1.0, 1.0, 1.0, 0.0)
	var solid := Color(1.0, 1.0, 1.0, 1.0)
	tool.set_color(clear)
	tool.add_vertex(a_edge)
	tool.set_color(solid)
	tool.add_vertex(a_mid)
	tool.set_color(clear)
	tool.add_vertex(b_edge)
	tool.set_color(clear)
	tool.add_vertex(b_edge)
	tool.set_color(solid)
	tool.add_vertex(a_mid)
	tool.set_color(solid)
	tool.add_vertex(b_mid)


## 조명을 안 받는 가산 혼합. 겹칠수록 밝아지고 어두운 사냥터에서도 같게 읽힌다.
## **깊이 검사를 끈다** — 몸 앞을 지나므로 켜 두면 몸통이 가린다.
## 꼭짓점 알파로 가장자리를 죄므로 `vertex_color_use_as_albedo` 를 켠다
static func glow(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	return mat


## 조명을 안 받는 **불투명** 재질. 금과 파편은 빛이 아니라 흙이다 —
## 가산 혼합으로 뿌렸더니 흰 꽃과 노란 알갱이 무리가 됐다 (2026-09-18 캡처)
static func dirt(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	return mat


## 한 번의 낙뢰 — 줄기 두 겹 · 금 · 파편 · 번쩍임을 한 자리에서 함께 쓴다
class Strike:
	extends Node3D

	## 언제 치나 (이펙트가 선 뒤 몇 초)
	var at := 0.0
	## 뒤에 오는 것일수록 굵다
	var swell := 1.0

	var _rng := RandomNumberGenerator.new()
	var _t := 0.0
	var _flick := 0.0
	var _from := Vector3.ZERO
	var _halo: MeshInstance3D
	var _core: MeshInstance3D
	var _crack: MeshInstance3D
	var _crack_paths: Array = []
	var _light: OmniLight3D
	var _debris: CPUParticles3D

	## 몇 초짜리인가
	func span() -> float:
		return maxf(LightningFx.BOLT_LIFE, maxf(LightningFx.CRACK_LIFE, LightningFx.DEBRIS_LIFE)) + 0.1

	func plan(order: int, swell_: float, at_: float, shake: Vector2, facing: float) -> void:
		# **씨앗을 박아 둔다** — 같은 낙뢰가 늘 같은 모양이어야 테스트가 읽는다
		_rng.seed = 20260918 + order * 9779
		swell = swell_
		at = at_
		position = Vector3(shake.x, 0.0, shake.y)
		# 시작점은 **캐릭터 뒤 위쪽**이다 (보는 쪽의 반대로 BEHIND 만큼)
		_from = Vector3(
			-sin(facing) * LightningFx.BEHIND,
			LightningFx.SKY,
			-cos(facing) * LightningFx.BEHIND
		)

		_halo = _sheet(LightningFx.glow(LightningFx.COLOR_HALO))
		_core = _sheet(LightningFx.glow(LightningFx.COLOR_CORE))
		_crack = _sheet(LightningFx.dirt(LightningFx.COLOR_CRACK))
		_crack.position = Vector3(0.0, LightningFx.GROUND, 0.0)
		_crack_paths = _plan_cracks()

		_light = OmniLight3D.new()
		_light.position = Vector3(0.0, 1.2, 0.0)
		_light.omni_range = LightningFx.LIGHT_RANGE
		_light.light_color = LightningFx.COLOR_HALO
		_light.visible = false
		add_child(_light)

		_debris = _make_debris()
		_debris.emitting = false
		add_child(_debris)

		visible = false

	func _sheet(mat: StandardMaterial3D) -> MeshInstance3D:
		var node := MeshInstance3D.new()
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		return node

	## 금은 **한 번 정해 두고 자라기만 한다** — 매 프레임 다시 흩으면 갈라진
	## 자국이 꿈틀거린다. 갈래마다 한 번 더 갈라져 나뭇가지가 된다
	func _plan_cracks() -> Array:
		var out: Array = []
		var turn := TAU / float(LightningFx.CRACKS)
		for i in LightningFx.CRACKS:
			var angle := turn * float(i) + _rng.randf_range(-turn * 0.35, turn * 0.35)
			var reach := LightningFx.CRACK_LENGTH * _rng.randf_range(0.6, 1.2) * swell
			var tip := Vector3(sin(angle), 0.0, cos(angle)) * reach
			var path := LightningFx.trail(Vector3.ZERO, tip, LightningFx.CRACK_SEGMENTS,
				reach * 0.16, _rng, true)
			out.append([path, 1.0])
			# 갈라진 가지 — 중간쯤에서 옆으로 벌어져 더 가늘게 뻗는다
			var mid := path[int(path.size() * 0.5)]
			var away := angle + _rng.randf_range(0.5, 1.0) * (1.0 if _rng.randf() > 0.5 else -1.0)
			var branch := mid + Vector3(sin(away), 0.0, cos(away)) * reach * 0.5
			out.append([LightningFx.trail(mid, branch, 3, reach * 0.1, _rng, true), 0.5])
		return out

	func _make_debris() -> CPUParticles3D:
		var debris := CPUParticles3D.new()
		debris.amount = LightningFx.DEBRIS_COUNT
		debris.lifetime = LightningFx.DEBRIS_LIFE
		debris.one_shot = true
		debris.explosiveness = 1.0
		var chunk := BoxMesh.new()
		var size := LightningFx.DEBRIS_SIZE * swell
		chunk.size = Vector3(size, size, size)
		debris.mesh = chunk
		debris.position = Vector3(0.0, LightningFx.GROUND, 0.0)
		debris.direction = Vector3(0.0, 1.0, 0.0)
		debris.spread = LightningFx.DEBRIS_SPREAD
		debris.initial_velocity_min = LightningFx.DEBRIS_SPEED_MIN
		debris.initial_velocity_max = LightningFx.DEBRIS_SPEED_MAX
		debris.gravity = Vector3(0.0, LightningFx.DEBRIS_GRAVITY, 0.0)
		# 흙덩이는 날아가는 쪽으로 정렬하지 않는다 — 구르며 흩어진다
		debris.angle_min = -180.0
		debris.angle_max = 180.0
		debris.angular_velocity_min = -420.0
		debris.angular_velocity_max = 420.0
		debris.scale_amount_min = 0.6
		debris.scale_amount_max = 1.3
		debris.color = LightningFx.COLOR_DEBRIS
		debris.material_override = LightningFx.dirt(LightningFx.COLOR_DEBRIS)
		return debris

	func _process(delta: float) -> void:
		_t += delta
		if _t < at:
			return
		var age := _t - at
		if not visible:
			visible = true
			_debris.emitting = true
			_reshape()

		_show_bolt(age)
		_show_crack(age)
		_show_light(age)

	## 줄기는 **지글거리며 꺼진다.** 45ms 마다 경로를 새로 잡는다 —
	## 가만히 서 있으면 붙여 놓은 그림과 다를 게 없다
	func _show_bolt(age: float) -> void:
		var left := 1.0 - age / LightningFx.BOLT_LIFE
		if left <= 0.0:
			_halo.visible = false
			_core.visible = false
			return
		_flick += get_process_delta_time()
		if _flick >= LightningFx.FLICK:
			_flick = 0.0
			_reshape()
		# 켤 때는 바로, 끌 때는 남은 만큼 — 처음부터 옅어지면 가장 굵은 순간이
		# 가장 투명한 순간과 겹친다
		var fade := clampf(left * 1.6, 0.0, 1.0)
		_halo.material_override.albedo_color = Color(
			LightningFx.COLOR_HALO.r, LightningFx.COLOR_HALO.g, LightningFx.COLOR_HALO.b, fade * 0.75)
		_core.material_override.albedo_color = Color(1.0, 1.0, 1.0, fade)

	func _reshape() -> void:
		var paths: Array = []
		for b in LightningFx.BOLTS:
			# 가닥마다 시작점을 옆으로 벌린다 — 같은 자리에서 시작하면 겹쳐서
			# 한 가닥으로 보인다. 꽂히는 자리는 같으니 아래로 갈수록 모인다
			var apart := (float(b) - float(LightningFx.BOLTS - 1) * 0.5) * LightningFx.BOLT_APART
			var from := _from + Vector3(apart, 0.0, apart * 0.5)
			var path := LightningFx.trail(from, Vector3.ZERO, LightningFx.SEGMENTS,
				LightningFx.WOBBLE * swell, _rng)
			paths.append([path, 1.0 if b == 0 else 0.8])
			# 곁가지 — 주 줄기 중간에서 갈라져 허공에서 끝난다. 줄기만 있으면
			# 막대가 떨어진 것 같다
			for f in LightningFx.FORKS:
				var at_i := int(path.size() * _rng.randf_range(0.25, 0.7))
				var root: Vector3 = path[at_i]
				var away := (Vector3.ZERO - from).normalized().rotated(
					Vector3.UP, _rng.randf_range(-1.1, 1.1))
				var tip := root + away * LightningFx.FORK_LENGTH * _rng.randf_range(0.6, 1.0)
				paths.append([LightningFx.trail(root, tip, 5, 0.35, _rng), 0.45])
		_halo.mesh = LightningFx.ribbon(paths, LightningFx.HALO_WIDTH * swell,
			LightningFx.HALO_WIDTH * 0.25 * swell, false)
		_core.mesh = LightningFx.ribbon(paths, LightningFx.CORE_WIDTH * swell,
			LightningFx.CORE_WIDTH * 0.2 * swell, false)

	## 금은 **중심에서 바깥으로 자란다.** 다 그려 놓고 띄우면 갈라진 것이
	## 아니라 그려진 그림이다
	func _show_crack(age: float) -> void:
		if age >= LightningFx.CRACK_LIFE:
			_crack.visible = false
			return
		var grow := clampf(age / LightningFx.CRACK_GROW, 0.0, 1.0)
		if grow < 1.0 or _crack.mesh == null:
			var cut: Array = []
			for entry in _crack_paths:
				cut.append([LightningFx.cut(entry[0], grow), entry[1]])
			_crack.mesh = LightningFx.ribbon(cut, LightningFx.CRACK_WIDTH * swell,
				LightningFx.CRACK_WIDTH * 0.15 * swell, true)
		# 끝에서만 옅어진다 — 금은 남는 자국이라 오래 버틴다
		var left := 1.0 - age / LightningFx.CRACK_LIFE
		var fade := clampf(left * 3.0, 0.0, 1.0)
		_crack.material_override.albedo_color = Color(
			LightningFx.COLOR_CRACK.r, LightningFx.COLOR_CRACK.g, LightningFx.COLOR_CRACK.b, fade)

	## 번쩍임은 **세게 켜고 빠르게 죈다.** 일정하게 켜 두면 조명이 하나 놓인 것이다
	func _show_light(age: float) -> void:
		if age >= LightningFx.LIGHT_LIFE:
			_light.visible = false
			return
		_light.visible = true
		_light.light_energy = LightningFx.LIGHT_ENERGY * (1.0 - age / LightningFx.LIGHT_LIFE)
