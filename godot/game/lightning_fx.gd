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

## **범위 강화("범위")가 붙으면** — 가운데 세 번 뒤에 **캐릭터 기준 좌우 살짝 옆**에서
## 한 번씩 더 내리친다 (2026-09-23 요청: "지금처럼 가운데 하나 떨어지고 살짝 옆으로
## 양쪽에서 내려치면"). 판정 사거리가 1.5배(4 → 6m)라 금·그을림·지면 전기도 1.5배다.
## 줄기 굵기는 그대로 둔다 — 굵은 리본은 번개가 아니라 띠로 보인다 (얇은 쪽이 낫다)
const SIDE_STRIKES := 2
## 옆 번개가 가운데에서 떨어진 거리(m). 캐릭터 키(1.8m) 남짓 — "살짝 옆"
const SIDE_GAP := 1.9
## 넓어질 때 땅에 남는 것(금·그을림·지면 전기)의 배율 — 판정 사거리 배율과 같다
const WIDE := 1.5

## 떨어지는 자리 — **시전자가 선 자리**다 (2026-09-18 지시: "스킬이 내 앞에서
## 떨어지는데 내 위치에서 떨어지도록 해"). 앞 2.8m 에 떨어뜨렸더니 내가 부른
## 것이 아니라 저쪽에 떨어진 것으로 보였다. 0 이 아닌 값을 주면 그만큼 앞이다
const AHEAD := 0.0
## 줄기가 시작하는 높이 (720p 에서 342px — 캐릭터 키의 다섯 배)
const SKY := 9.0
## 시작점이 얼마나 멀리 있나. 높이와 합쳐 **화면 밖**이 되어야 한다
const BEHIND := 6.5
## 화면에서 **가로로 미는 정도.** 0 이면 화면에서 수직으로 내려와 캐릭터와
## 겹쳐 기둥으로 보인다 — 최소한 이만큼은 기울어야 한다
const LEAN := 0.55
## 보는 쪽에 따라 기울기를 더 흔드는 폭. 늘 똑같은 대각선이면 그것대로 심심하다
const SWAY := 0.35

## 경로를 몇 토막으로 나누나. 잘게 나눌수록 잔 떨림이 는다
## 토막이 잘면 **폭보다 짧아져** 꺾인 자리가 겹친다. 8.6m 를 열둘로 나누면
## 토막 0.7m 로 halo(0.95m)와 비슷해 이음새가 자연스럽다
const SEGMENTS := 12
## **주 줄기는 하나다.** 둘을 따로 세웠더니 한 줄기가 여러 줄로 갈라져 보였다 —
## 굵게 보이려면 가닥을 늘리는 게 아니라 **폭만 다른 겹**을 쌓는다
## ([effect-rules.md](../../docs/features/effect-rules.md) 의 5절)
const BOLTS := 1
## 굽이치는 폭(m). 크면 번개가 아니라 리본이 나부낀다
const WOBBLE := 0.9
## **굵어야 번개다.** 코어 0.18m = 7px, halo 0.5m = 19px 이고 끝으로 갈수록
## 가늘어진다. 얇게 깎았더니 실이 됐다 (2026-09-18 에 두 번 헛돌았다) —
## 뭉쳐 보이는 원인은 굵기가 아니라 **가닥 수**였다
## **얇게** (2026-09-18 지시). 굵은 리본은 번개가 아니라 띠로 보인다 —
## 다만 파티클로 만들던 때처럼 3px 까지 깎지는 않는다. 그때 실이 된 것은
## 굵기가 아니라 **가닥이 뭉쳐서**였다
const CORE_WIDTH := 0.09
## halo 는 코어를 감싸는 **번짐**이다. 가장자리가 투명해지므로 굵어도 선이
## 지지 않는다
const HALO_WIDTH := 0.5
## 가운데 **색 빛** — 헤일로와 흰 심 사이. 한 줄기를 굵게 보이려면
## **폭만 다른 3겹**(넓은 헤일로 + 색 빛 + 가는 흰 심)으로 쌓는다
const SHEEN_WIDTH := 0.2
## 줄기가 살아 있는 시간과 **지글거리는 주기.** 45ms 마다 경로를 다시 만든다
const BOLT_LIFE := 0.3
const FLICK := 0.045
## 곁줄기 — **따로 기울이지 않는다.** 따로 기울였더니 한 줄기가 세 줄로 갈라져
## 보이고, 길게 뻗은 가지는 별개의 번개처럼 화면을 가로질렀다. **같은 길을 조금
## 더 흔든 것**이라야 한 줄기가 굵어 보인다 (규칙 5절)
const FORKS := 2
## 곁줄기가 주 줄기에서 얼마나 어긋나나(m). **조금이어야 한다** — 주 줄기의
## 1.7배로 새로 뽑았더니 규칙이 경고한 그대로 한 줄기가 세 줄로 갈라졌다
## (2026-09-18 캡처). 0.22m 는 화면에서 8px 다
const FORK_DRIFT := 0.22

## 갈라지는 땅. **중심에서 가지를 치며 뻗고 가늘어진다** — 파티클로 방사했더니
## 고른 별표가 됐다 (2026-09-18). 갈래마다 한 번 더 갈라진다
const CRACKS := 7
## **캐릭터 키(1.8m)의 1.5~4배** 여야 한다 (규칙 3절). 갈래마다 0.85~1.35 를
## 곱하고 연타마다 굵어지므로 2.7~5.7m 가 된다
const CRACK_LENGTH := 3.2
## 금은 **한 겹이다.** 둘레에 밝은 돌빛을 한 겹 깔아 봤더니 갈라진 틈이 아니라
## **테두리를 두른 그림**이 됐다 (2026-09-18 에 지적받았다) — 가장자리는
## 그라디언트로만 죈다
const CRACK_WIDTH := 0.34
const CRACK_SEGMENTS := 5
## 금이 자라는 시간 — 0.14초에 걸쳐 중심에서 바깥으로 뻗는다.
## 한 번에 다 그리면 갈라진 것이 아니라 그려진 그림이다
const CRACK_GROW := 0.14
## 자국은 **오래 남다가 마지막 0.8초에 흐려진다** (규칙 3절)
const CRACK_LIFE := 1.5
const CRACK_FADE := 0.8

## 금과 파편이 나는 높이. 0 으로 두면 지면과 같은 면이라 깜빡인다
const GROUND := 0.05

## 터지는 **전기 불똥** — 흙 알갱이를 대신한다 (2026-09-19 지시: "바닥에 먼지가
## 아니라 번개가 터지는 이펙트로"). 흙이 아니라 빛이라 **가산 혼합**이고
## **거의 안 떨어진다** — 중력을 세게 주면 흙처럼 보인다.
## 카메라를 마주 보는 둥근 점(`FxTex.glow`)이라 모서리가 없다
const SPARK_COUNT := 30
const SPARK_SIZE := 0.17
## 느리면 섬광 안에 머물러 안 보인다
const SPARK_SPEED_MIN := 9.0
const SPARK_SPEED_MAX := 20.0
const SPARK_SPREAD := 72.0
const SPARK_LIFE := 0.32
const SPARK_GRAVITY := -3.0

## 지면을 타고 뻗는 **전기 가닥** — 먼지를 대신한다. 줄기와 같은 리본 메시라
## 알갱이가 아니고, 금(`_crack`)과 달리 **밝고 지글거리다 빨리 꺼진다**
const ARCS := 6
const ARC_LENGTH := 2.8
const ARC_SEGMENTS := 5
const ARC_CORE := 0.09
const ARC_HALO := 0.45
const ARC_LIFE := 0.26
## 지면에서 띄우는 높이. 금(`GROUND`)보다 위라야 안 묻힌다
const ARC_HEIGHT := 0.09

## 꽂힌 자리의 섬광 판. **퍼지지 않고 제자리에서 사그라든다** (규칙 3절) —
## 살짝만 부푼다. 1.6m = 61px
const FLARE_SIZE := 1.7
const FLARE_SWELL := 1.25
const FLARE_LIFE := 0.3

## 지면 그을림. 금보다 조금 넓게 깔리고 **금과 함께 마지막 0.8초에 흐려진다**
const STAIN_SIZE := 4.4
const STAIN_ALPHA := 0.45

## **치는 순간 주위가 번쩍인다.** 번개로 읽게 하는 것은 줄기 모양만이 아니다
const LIGHT_RANGE := 9.0
const LIGHT_ENERGY := 7.0
const LIGHT_LIFE := 0.16

## 코어는 흰빛, halo 는 파랑, 금과 파편은 흙이다. 할퀴기(자홍)·피해 숫자(연노랑)·
## 치명타(주황)·피격(붉은색)과 한 화면에서 갈려야 한다
const COLOR_CORE := Color("#ffffff")
const COLOR_HALO := Color("#4a90ff")
const COLOR_SHEEN := Color("#9fd0ff")
const COLOR_CRACK := Color("#241a12")
const COLOR_STAIN := Color("#2a2118")
## **밝은 바닥과 섬광 위에서 보이려면 어두워야 한다** — 밝은 흙빛으로 뿌렸더니
## 섬광에 묻혀 사라졌다 (2026-09-18 캡처)
## 전기 불똥은 줄기와 같은 빛이다 — 흙빛(`#5f4c36`)에서 바꿨다
const COLOR_SPARK := Color("#8fc8ff")

## 빛의 색 한 벌 — 헤일로 · 색 빛 · 불똥. **심(흰빛)과 금·그을림(흙)은 안 바뀐다**:
## 가장 밝은 자리가 희어야 빛으로 읽히고, 땅은 번개 색과 상관없이 흙이다
const PALETTE_BLUE := {"halo": COLOR_HALO, "sheen": COLOR_SHEEN, "spark": COLOR_SPARK}
## **붉은 번개** — 낙뢰에 "기절" 강화가 붙으면 (2026-09-23 요청: "스턴 3초 강화하면
## 이펙트 색상이 붉은색으로"). 푸른 벌과 밝기 순서를 맞췄다 — 헤일로가 가장 짙고
## 색 빛이 옅다. 피격 붉힘(몸에 입히는 붉은색)과는 모양이 달라 섞이지 않는다
const PALETTE_RED := {"halo": Color("#ff2a1a"), "sheen": Color("#ffa090"), "spark": Color("#ff8a70")}

var _t := 0.0
var _span := 0.0


## 낙뢰를 떨어뜨린다.
##
## `at` 은 시전자 발밑(월드 좌표), `facing` 은 시전자가 보는 쪽(rad, `player.rot`).
## 풀(`FxPool`)에 쉬는 것이 있으면 되감아 쓴다 — 새로 만들지 않는다.
## `red` 면 붉은 번개다 (낙뢰 "기절" 강화). 풀은 한 벌을 같이 쓰고 색만 다시 칠한다.
## `wide` 면 좌우로 두 번 더 치고 땅의 흔적이 1.5배다 (낙뢰 "범위" 강화). 둘은 따로 논다
static func bolt(parent: Node3D, at: Vector3, facing: float, red := false, wide := false) -> LightningFx:
	var fx := FxPool.take(parent, &"bolt") as LightningFx
	if fx == null:
		fx = LightningFx.new()
		parent.add_child(fx)
		fx._build()
	fx._start(at, facing, PALETTE_RED if red else PALETTE_BLUE, wide)
	return fx


## 노드를 만든다 — 한 번만. 되감기는 `_start`.
## **옆 번개 둘까지 늘 만들어 둔다** — 넓힘이 없을 때는 쉬게 한다(`rest`). 풀이 한 벌이라
## 넓은 낙뢰가 처음 나올 때 새로 만들면 그 순간 멈칫한다
func _build() -> void:
	for i in STRIKES + SIDE_STRIKES:
		var strike := Strike.new()
		# 옆 번개는 가운데 마지막 것과 같은 굵기다
		strike.make(1.0 + float(mini(i, STRIKES - 1)) * STRIKE_SWELL)
		add_child(strike)


## 처음으로 되감는다. 번개의 모양은 씨앗이 정하므로 매번 같다
func _start(at: Vector3, facing: float, pal: Dictionary = PALETTE_BLUE, wide := false) -> void:
	# 떨어지는 자리는 **화면이 아니라 캐릭터가 보는 쪽** 앞이다
	position = at + Vector3(sin(facing) * AHEAD, 0.0, cos(facing) * AHEAD)
	# **회전은 주지 않는다.** 번개는 하늘에서 땅으로 오는 것이라 월드 기준이어야
	# 하고, 리본의 폭도 월드 기준 시선으로 잰다. 보는 쪽은 시작점 좌표에 넣는다
	_t = 0.0
	_span = 0.0
	# 캐릭터의 오른쪽 (보는 쪽에 수직, 지면 안)
	var side := Vector2(cos(facing), -sin(facing))
	var reach := WIDE if wide else 1.0
	var i := 0
	for strike in get_children():
		if i >= STRIKES and not wide:
			strike.rest()
			i += 1
			continue
		var spot: Vector2 = JITTER[i % JITTER.size()]
		if i >= STRIKES:
			# 왼쪽 먼저, 그다음 오른쪽 — 가운데 세 번과 같은 간격으로 이어진다
			spot = side * SIDE_GAP * (-1.0 if i == STRIKES else 1.0)
		strike.plan(i, float(i) * STRIKE_GAP, spot, facing, reach)
		strike.paint(pal)
		_span = maxf(_span, strike.at + strike.span())
		i += 1


func _process(delta: float) -> void:
	_t += delta
	if _t >= _span:
		finish()


## 끝낸다 — 풀로 돌아간다 (풀 밖이면 지운다)
func finish() -> void:
	FxPool.give(self, &"bolt")


## 번개가 오는 쪽(수평, 월드). **화면 위쪽 밖**이다.
##
## 캐릭터가 보는 쪽의 반대에 두었더니 **방향에 따라 번개가 엄청 짧아지거나
## 시작점이 화면 안에 보였다** (2026-09-18 지적). 카메라가 고정각이라,
## 캐릭터가 카메라 쪽을 보면 시작점이 화면 **아래**로 내려온다.
##
## 카메라에서 **멀어지는** 수평 방향이 곧 화면에서 위쪽이므로 그쪽에 둔다.
## 규칙 문서(3절)의 "방향은 캐릭터 기준" 과 어긋나 보이지만, 거기서 거절된 것은
## **늘 왼쪽→오른쪽으로 보이는** 것이었다 — 여기서는 보는 쪽에 따라 `SWAY`
## 만큼 좌우로 트니 매번 같은 대각선은 아니다
static func from_dir(facing: float) -> Vector3:
	var away := Vector3(-sin(CameraRig.YAW), 0.0, -cos(CameraRig.YAW)).normalized()
	# 화면 가로 방향 — 이쪽으로 밀어야 화면에서 대각선이 된다
	var side := away.cross(Vector3.UP).normalized()
	return (away + side * (LEAN + sin(facing) * SWAY)).normalized()


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


## **같은 길을 조금 흔든** 사본. 새로 뽑으면 다른 번개가 되어 화면을 가로지른다 —
## 곁줄기는 주 줄기를 따라가며 살짝 어긋나기만 해야 한 줄기가 굵어 보인다
## ([effect-rules.md](../../docs/features/effect-rules.md) 의 5절)
static func jitter(path: PackedVector3Array, amount: float,
		rng: RandomNumberGenerator) -> PackedVector3Array:
	var out := PackedVector3Array()
	var drift := Vector3.ZERO
	var last := maxi(path.size() - 1, 1)
	for i in path.size():
		drift += Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * amount * 0.4
		# 양 끝은 주 줄기와 붙어 있어야 한 줄기로 읽힌다
		out.append(path[i] + drift * sin(float(i) / float(last) * PI))
	return out


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
## (줄기) — 그래야 카메라가 어디 있든 화면에서 같은 굵기다.
##
## `into` 를 주면 **그 메시를 비우고 다시 채운다.** 줄기는 45ms 마다 새로 깎는데,
## 그때마다 `ArrayMesh` 를 새로 만들면 메시 자원을 만들고 버리는 값이 붙는다
static func ribbon(paths: Array, head: float, tail: float, flat: bool,
		into: ArrayMesh = null) -> ArrayMesh:
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
			_half(tool, a - wa, a, b - wb, b, 0.0)
			_half(tool, a + wa, a, b + wb, b, 1.0)
			drawn += 1
	var mesh := into if into != null else ArrayMesh.new()
	mesh.clear_surfaces()
	if drawn == 0:
		return mesh
	return tool.commit(mesh)


## 리본 한 토막의 반쪽. `edge` 쪽 꼭짓점은 투명하고 `mid` 쪽은 진하다 —
## 이 그라디언트가 **테두리를 지운다**. 앞뒤 어느 쪽에서 봐도 보여야 하므로
## 재질에서 컬링을 끈다
static func _half(tool: SurfaceTool, a_edge: Vector3, a_mid: Vector3,
		b_edge: Vector3, b_mid: Vector3, edge_u: float) -> void:
	# **가장자리를 죄는 것은 이제 텍스처다** (`FxTex.streak`). 꼭짓점 알파로
	# 죄면 삼각형 안에서 직선으로 줄어들어 가운데 심이 각져 보인다 —
	# 텍스처는 감쇠 곡선을 그대로 준다
	tool.set_uv(Vector2(edge_u, 0.0))
	tool.add_vertex(a_edge)
	tool.set_uv(Vector2(0.5, 0.0))
	tool.add_vertex(a_mid)
	tool.set_uv(Vector2(edge_u, 1.0))
	tool.add_vertex(b_edge)
	tool.set_uv(Vector2(edge_u, 1.0))
	tool.add_vertex(b_edge)
	tool.set_uv(Vector2(0.5, 0.0))
	tool.add_vertex(a_mid)
	tool.set_uv(Vector2(0.5, 1.0))
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
	# 폭 방향으로 가운데가 진하고 양끝이 사라지는 띠 — 테두리를 지우는 자리다
	mat.albedo_texture = FxTex.streak()
	mat.albedo_color = color
	return mat


## 조명을 안 받는 **불투명** 재질. 금과 파편은 빛이 아니라 흙이다 —
## 가산 혼합으로 뿌렸더니 흰 꽃과 노란 알갱이 무리가 됐다 (2026-09-18 캡처)
static func dirt(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = FxTex.streak()
	mat.albedo_color = color
	return mat


## 흙 알갱이·먼지용 — **카메라를 마주 보는 둥근 점.** 모서리가 없어야 한다
## (`BoxMesh` 를 굴렸더니 "사각사각하다" 는 말을 들었다, 2026-09-18).
## 빛이 아니라 흙이라 가산이 아닌 알파 혼합이다
## `additive` 면 **빛**이다 — 전기 불똥처럼 겹칠수록 밝아지고 깊이 검사를 끈다.
## 아니면 흙이라 알파 혼합이다
static func mote(color: Color, additive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = FxTex.glow()
	mat.albedo_color = color
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.no_depth_test = true
	return mat


## 제 색으로 떠 있다가 **끝에서만** 사라진다. `peak` 로 진하기를 정한다 —
## 먼지는 옅어야 구름이 아니라 흙먼지로 보인다
static func fade_ramp(color: Color, peak := 1.0) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, peak))
	ramp.set_offset(1, 0.55)
	ramp.set_color(1, Color(color.r, color.g, color.b, peak * 0.85))
	ramp.add_point(1.0, Color(color.r, color.g, color.b, 0.0))
	return ramp


## 튀어 오를 때 굵고 떨어지며 잦아든다
static func fade_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.65, 0.8))
	curve.add_point(Vector2(1.0, 0.35))
	return curve


## 피어오르며 `to` 배까지 커진다
static func grow_curve(to: float) -> Curve:
	var curve := Curve.new()
	curve.max_value = maxf(to, 1.0)
	curve.add_point(Vector2(0.0, 0.45))
	curve.add_point(Vector2(1.0, to))
	return curve


## 섬광 판 — **카메라를 늘 마주 본다.** 방사형 글로우라 가장자리가 없다.
## 규칙(3절)대로 **퍼지지 않고 제자리에서 사그라든다**
static func flare(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = FxTex.glow()
	mat.albedo_color = color
	return mat


## 지면 그을림 — **불규칙한 얼룩**이라 동그란 고리로 안 보인다
static func stain(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = FxTex.scorch()
	mat.albedo_color = color
	return mat


## 한 번의 낙뢰 — 줄기 두 겹 · 금 · 파편 · 번쩍임을 한 자리에서 함께 쓴다
class Strike:
	extends Node3D

	## 언제 치나 (이펙트가 선 뒤 몇 초)
	var at := 0.0
	## 빛의 색 한 벌 (`PALETTE_BLUE` · `PALETTE_RED`). 매 프레임 여기서 읽는다
	var _pal: Dictionary = LightningFx.PALETTE_BLUE
	## 뒤에 오는 것일수록 굵다
	var swell := 1.0

	var _rng := RandomNumberGenerator.new()
	var _t := 0.0
	var _flick := 0.0
	var _from := Vector3.ZERO
	var _halo: MeshInstance3D
	var _sheen: MeshInstance3D
	var _core: MeshInstance3D
	var _crack: MeshInstance3D
	var _crack_paths: Array = []
	var _flare: MeshInstance3D
	var _stain: MeshInstance3D
	var _light: OmniLight3D
	var _sparks: CPUParticles3D
	var _arc_halo: MeshInstance3D
	var _arc_core: MeshInstance3D
	var _arc_flick := 0.0
	## 금이 다 자랐나 — 다 자라면 더 깎지 않는다
	var _crack_done := false
	## 이번에 치나 — 넓힘이 없으면 옆 번개는 쉰다 (`rest`)
	var active := true
	## 땅에 남는 것(금·그을림·지면 전기)의 배율 — 넓힘이면 `LightningFx.WIDE`
	var ground_mul := 1.0

	## 몇 초짜리인가
	func span() -> float:
		return maxf(LightningFx.BOLT_LIFE, maxf(LightningFx.CRACK_LIFE,
			maxf(LightningFx.SPARK_LIFE, LightningFx.ARC_LIFE))) + 0.1

	## 되감는다 — **아무것도 만들지 않는다.** 씨앗·시각·시작점만 다시 넣는다
	func plan(order: int, at_: float, shake: Vector2, facing: float, reach_ := 1.0) -> void:
		active = true
		ground_mul = reach_
		_stain.scale = Vector3(ground_mul, 1.0, ground_mul)
		# **씨앗을 박아 둔다** — 같은 낙뢰가 늘 같은 모양이어야 테스트가 읽는다
		_rng.seed = 20260918 + order * 9779
		at = at_
		position = Vector3(shake.x, 0.0, shake.y)
		# 시작점은 **화면 위쪽 밖**이다 — 캐릭터가 어느 쪽을 보든 같다
		_from = LightningFx.from_dir(facing) * LightningFx.BEHIND + Vector3.UP * LightningFx.SKY
		_crack_paths = _plan_cracks()
		_crack_done = false
		_t = 0.0
		_flick = 0.0
		_arc_flick = 0.0
		# 지난번 끝에 꺼 둔 것들 — 이 번개 자체(`visible`)는 칠 때까지 꺼져 있다
		for node in [_halo, _sheen, _core, _crack, _stain, _flare, _arc_halo, _arc_core]:
			node.visible = true
		_light.visible = false
		visible = false

	## 색을 칠한다 — 되감을 때마다. 리본·섬광은 매 프레임 `_pal` 을 읽으므로
	## 만들 때 굳는 것(빛·불똥)만 여기서 바꾼다. 같은 색이면 아무것도 안 한다
	func paint(pal: Dictionary) -> void:
		if pal == _pal:
			return
		_pal = pal
		_light.light_color = pal.halo
		_sparks.color = pal.spark
		_sparks.color_ramp = LightningFx.fade_ramp(pal.spark, 1.0)
		_sparks.material_override.albedo_color = pal.spark
		for node in [_halo, _arc_halo]:
			node.material_override.albedo_color = pal.halo
		_sheen.material_override.albedo_color = pal.sheen
		_flare.material_override.albedo_color = pal.sheen

	## 노드를 만든다 — 한 번만. 뒤에 오는 것일수록 굵다(`swell_`)
	func make(swell_: float) -> void:
		swell = swell_
		# 넓은 헤일로 → 색 빛 → 가는 흰 심 순으로 쌓는다
		_halo = _sheet(LightningFx.glow(_pal.halo))
		_sheen = _sheet(LightningFx.glow(_pal.sheen))
		_core = _sheet(LightningFx.glow(LightningFx.COLOR_CORE))
		# 그을림을 먼저 깔고 그 위에 금을 얹는다 — 같은 높이면 서로 깜빡인다
		_stain = _sheet(LightningFx.stain(LightningFx.COLOR_STAIN))
		_stain.mesh = _flat_quad(LightningFx.STAIN_SIZE * swell)
		_stain.position = Vector3(0.0, LightningFx.GROUND, 0.0)
		_crack = _sheet(LightningFx.dirt(LightningFx.COLOR_CRACK))
		_crack.position = Vector3(0.0, LightningFx.GROUND + 0.01, 0.0)

		# 꽂힌 자리의 섬광 — 카메라를 늘 마주 보는 판이다
		_flare = _sheet(LightningFx.flare(_pal.sheen))
		var glare := QuadMesh.new()
		glare.size = Vector2(LightningFx.FLARE_SIZE, LightningFx.FLARE_SIZE) * swell
		_flare.mesh = glare
		_flare.position = Vector3(0.0, LightningFx.GROUND + 0.5, 0.0)

		_light = OmniLight3D.new()
		_light.position = Vector3(0.0, 1.2, 0.0)
		_light.omni_range = LightningFx.LIGHT_RANGE
		_light.light_color = _pal.halo
		_light.visible = false
		add_child(_light)

		_sparks = _make_sparks()
		_sparks.emitting = false
		add_child(_sparks)

		# 지면 전기 가닥 — 줄기와 같은 두 겹 리본이다
		_arc_halo = _sheet(LightningFx.glow(_pal.halo))
		_arc_halo.position = Vector3(0.0, LightningFx.ARC_HEIGHT, 0.0)
		_arc_core = _sheet(LightningFx.glow(LightningFx.COLOR_CORE))
		_arc_core.position = Vector3(0.0, LightningFx.ARC_HEIGHT + 0.01, 0.0)

		visible = false

	func _sheet(mat: StandardMaterial3D) -> MeshInstance3D:
		var node := MeshInstance3D.new()
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		return node

	## 지면에 눕는 판 — `QuadMesh` 는 세로로 서 있으므로 눕혀서 만든다
	func _flat_quad(side: float) -> QuadMesh:
		var quad := QuadMesh.new()
		quad.size = Vector2(side, side)
		quad.orientation = PlaneMesh.FACE_Y
		return quad

	## 금은 **한 번 정해 두고 자라기만 한다** — 매 프레임 다시 흩으면 갈라진
	## 자국이 꿈틀거린다. 갈래마다 한 번 더 갈라져 나뭇가지가 된다
	func _plan_cracks() -> Array:
		var out: Array = []
		var turn := TAU / float(LightningFx.CRACKS)
		for i in LightningFx.CRACKS:
			var angle := turn * float(i) + _rng.randf_range(-turn * 0.35, turn * 0.35)
			var reach := LightningFx.CRACK_LENGTH * _rng.randf_range(0.85, 1.35) * swell * ground_mul
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

	## 터지는 전기 불똥 — 사방으로 튀고 **거의 안 떨어진다.**
	##
	## 흙 알갱이였던 자리다 (2026-09-19 지시). 흙이면 중력으로 떨어져야 하지만
	## 빛은 그 자리에서 꺼진다 — 중력을 세게 주면 도로 흙으로 보인다.
	## **모서리가 없어야 한다** — 카메라를 마주 보는 둥근 점(`FxTex.glow`)이다
	func _make_sparks() -> CPUParticles3D:
		var sparks := _motes(LightningFx.SPARK_COUNT, LightningFx.SPARK_LIFE,
			LightningFx.SPARK_SIZE, _pal.spark, 1.0, true)
		sparks.direction = Vector3(0.0, 1.0, 0.0)
		sparks.spread = LightningFx.SPARK_SPREAD
		sparks.initial_velocity_min = LightningFx.SPARK_SPEED_MIN
		sparks.initial_velocity_max = LightningFx.SPARK_SPEED_MAX
		sparks.gravity = Vector3(0.0, LightningFx.SPARK_GRAVITY, 0.0)
		# 튈 때 굵고 꺼지며 잦아든다
		sparks.scale_amount_min = 0.55
		sparks.scale_amount_max = 1.25
		sparks.scale_amount_curve = LightningFx.fade_curve()
		return sparks

	## 지면을 타고 뻗는 전기 가닥의 **경로를 다시 잡는다.** 줄기와 같은 리본이라
	## 알갱이가 아니고, 금과 달리 **지글거린다** — 금은 남는 자국이라 한 번
	## 정해 두지만 전기는 살아 있는 동안 계속 흔들린다
	func _reshape_arcs() -> void:
		var paths: Array = []
		var turn := TAU / float(LightningFx.ARCS)
		for i in LightningFx.ARCS:
			var angle := turn * float(i) + _rng.randf_range(-turn * 0.4, turn * 0.4)
			var reach := LightningFx.ARC_LENGTH * _rng.randf_range(0.6, 1.25) * swell * ground_mul
			var tip := Vector3(sin(angle), 0.0, cos(angle)) * reach
			paths.append([LightningFx.trail(Vector3.ZERO, tip, LightningFx.ARC_SEGMENTS,
				reach * 0.2, _rng, true), 1.0])
		_arc_halo.mesh = LightningFx.ribbon(paths, LightningFx.ARC_HALO * swell,
			LightningFx.ARC_HALO * 0.2 * swell, true, _arc_halo.mesh)
		_arc_core.mesh = LightningFx.ribbon(paths, LightningFx.ARC_CORE * swell,
			LightningFx.ARC_CORE * 0.2 * swell, true, _arc_core.mesh)

	## 전기 가닥은 **지글거리다 빨리 꺼진다**
	func _show_arcs(age: float) -> void:
		if age >= LightningFx.ARC_LIFE:
			_arc_halo.visible = false
			_arc_core.visible = false
			return
		_arc_flick += get_process_delta_time()
		if _arc_flick >= LightningFx.FLICK:
			_arc_flick = 0.0
			_reshape_arcs()
		var fade := clampf((1.0 - age / LightningFx.ARC_LIFE) * 1.5, 0.0, 1.0)
		_arc_halo.material_override.albedo_color = Color(
			_pal.halo.r, _pal.halo.g, _pal.halo.b, fade * 0.6)
		_arc_core.material_override.albedo_color = Color(1.0, 1.0, 1.0, fade)

	## 둥근 점 방출기 한 벌 — 알갱이와 먼지가 같은 뼈대를 쓴다
	func _motes(count: int, life: float, size: float, color: Color, peak := 1.0,
			additive := false) -> CPUParticles3D:
		var motes := CPUParticles3D.new()
		motes.amount = count
		motes.lifetime = life
		motes.one_shot = true
		motes.explosiveness = 1.0
		var dot := QuadMesh.new()
		dot.size = Vector2(size, size) * swell
		motes.mesh = dot
		motes.position = Vector3(0.0, LightningFx.GROUND, 0.0)
		# 굴린다 — 같은 그림이 여럿이면 찍어낸 것으로 보인다
		motes.angle_min = -180.0
		motes.angle_max = 180.0
		motes.angular_velocity_min = -160.0
		motes.angular_velocity_max = 160.0
		motes.color = color
		motes.color_ramp = LightningFx.fade_ramp(color, peak)
		motes.material_override = LightningFx.mote(color, additive)
		return motes

	## 이번에는 안 친다 — 숨겨 두기만 한다 (옆 번개, 넓힘이 없을 때)
	func rest() -> void:
		active = false
		visible = false
		_light.visible = false
		_sparks.emitting = false

	func _process(delta: float) -> void:
		if not active:
			return
		_t += delta
		if _t < at:
			return
		var age := _t - at
		if not visible:
			visible = true
			# 되감아 쓰는 방출기라 켜기(`emitting`)가 아니라 처음부터 다시(`restart`)
			_sparks.restart()
			_reshape_arcs()
			_reshape()

		_show_bolt(age)
		_show_flare(age)
		_show_arcs(age)
		_show_crack(age)
		_show_light(age)

	## 섬광은 **살짝만 부풀고 제자리에서 꺼진다.** 크게 퍼뜨리면 규칙이 쓰지
	## 말라고 한 충격 파동 고리와 같은 것이 된다
	func _show_flare(age: float) -> void:
		if age >= LightningFx.FLARE_LIFE:
			_flare.visible = false
			return
		var t := age / LightningFx.FLARE_LIFE
		_flare.scale = Vector3.ONE * lerpf(0.75, LightningFx.FLARE_SWELL, sqrt(t))
		_flare.material_override.albedo_color = Color(
			_pal.sheen.r, _pal.sheen.g, _pal.sheen.b,
			pow(1.0 - t, 1.2))

	## 줄기는 **지글거리며 꺼진다.** 45ms 마다 경로를 새로 잡는다 —
	## 가만히 서 있으면 붙여 놓은 그림과 다를 게 없다
	func _show_bolt(age: float) -> void:
		var left := 1.0 - age / LightningFx.BOLT_LIFE
		if left <= 0.0:
			_halo.visible = false
			_sheen.visible = false
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
			_pal.halo.r, _pal.halo.g, _pal.halo.b, fade * 0.6)
		_sheen.material_override.albedo_color = Color(
			_pal.sheen.r, _pal.sheen.g, _pal.sheen.b, fade * 0.9)
		_core.material_override.albedo_color = Color(1.0, 1.0, 1.0, fade)

	## **한 줄기를 폭만 다른 3겹으로 쌓는다.** 가닥을 늘려 굵게 만들면 한 줄기가
	## 여러 줄로 갈라져 보인다 — 곁줄기도 따로 기울이지 않고 **같은 길을 조금 더
	## 흔든 것**으로 둔다 (`effect-rules.md` 5절)
	func _reshape() -> void:
		var paths: Array = []
		for b in LightningFx.BOLTS:
			var path := LightningFx.trail(_from, Vector3.ZERO, LightningFx.SEGMENTS,
				LightningFx.WOBBLE * swell, _rng)
			paths.append([path, 1.0])
			# 곁줄기 — **같은 길을 조금 흔든 사본**이다. 새로 뽑거나 따로
			# 기울이면 별개의 번개가 화면을 가로지른다
			for f in LightningFx.FORKS:
				paths.append([LightningFx.jitter(path, LightningFx.FORK_DRIFT * swell, _rng), 0.45])
		_halo.mesh = LightningFx.ribbon(paths, LightningFx.HALO_WIDTH * swell,
			LightningFx.HALO_WIDTH * 0.25 * swell, false, _halo.mesh)
		_sheen.mesh = LightningFx.ribbon(paths, LightningFx.SHEEN_WIDTH * swell,
			LightningFx.SHEEN_WIDTH * 0.25 * swell, false, _sheen.mesh)
		_core.mesh = LightningFx.ribbon(paths, LightningFx.CORE_WIDTH * swell,
			LightningFx.CORE_WIDTH * 0.2 * swell, false, _core.mesh)

	## 금은 **중심에서 바깥으로 자란다.** 다 그려 놓고 띄우면 갈라진 것이
	## 아니라 그려진 그림이다
	func _show_crack(age: float) -> void:
		if age >= LightningFx.CRACK_LIFE:
			_crack.visible = false
			_stain.visible = false
			return
		var grow := clampf(age / LightningFx.CRACK_GROW, 0.0, 1.0)
		if not _crack_done:
			var cut: Array = []
			for entry in _crack_paths:
				cut.append([LightningFx.cut(entry[0], grow), entry[1]])
			_crack.mesh = LightningFx.ribbon(cut, LightningFx.CRACK_WIDTH * swell,
				LightningFx.CRACK_WIDTH * 0.15 * swell, true, _crack.mesh)
			_crack_done = grow >= 1.0
		# **마지막 0.8초에만 흐려진다** — 금은 남는 자국이라 오래 버틴다 (규칙 3절)
		var fade := clampf((LightningFx.CRACK_LIFE - age) / LightningFx.CRACK_FADE, 0.0, 1.0)
		_crack.material_override.albedo_color = Color(
			LightningFx.COLOR_CRACK.r, LightningFx.COLOR_CRACK.g, LightningFx.COLOR_CRACK.b, fade)
		# 그을림은 금이 자라는 동안 같이 넓어진다 (규칙 3절)
		_stain.scale = Vector3.ONE * lerpf(0.5, 1.0, grow)
		_stain.material_override.albedo_color = Color(
			LightningFx.COLOR_STAIN.r, LightningFx.COLOR_STAIN.g, LightningFx.COLOR_STAIN.b,
			fade * LightningFx.STAIN_ALPHA)

	## 번쩍임은 **세게 켜고 빠르게 죈다.** 일정하게 켜 두면 조명이 하나 놓인 것이다
	func _show_light(age: float) -> void:
		if age >= LightningFx.LIGHT_LIFE:
			_light.visible = false
			return
		_light.visible = true
		_light.light_energy = LightningFx.LIGHT_ENERGY * (1.0 - age / LightningFx.LIGHT_LIFE)
