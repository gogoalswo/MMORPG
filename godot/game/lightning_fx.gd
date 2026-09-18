class_name LightningFx
extends Node3D

## 낙뢰(`thunder_fall`) 스킬 연출. **한 지점에 번개가 세 번 겹쳐 떨어지고**,
## 떨어진 자리에서 **땅이 갈라지며 파편이 튄다.**
##
## **줄기는 시전자 뒤 위쪽에서 앞으로 내리꽂힌다** (2026-09-18 지시). 수직으로
## 떨어뜨리면 화면에서 캐릭터와 겹쳐 그냥 기둥이 서 있는 것처럼 보인다 — 뒤에서
## 앞으로 비스듬히 지나가야 캐릭터를 넘어 앞쪽 땅에 꽂히는 것으로 읽힌다.
##
## **파티클로 짓는다** (`CPUParticles3D`). 판 모양 메시를 세워 두면 텍스처를 안
## 썼어도 "이미지 붙여 놓은 것 같다" 가 된다 (2026-09-17, 할퀴기에서 지적받았다)
## → [hit-effects.md](../../docs/features/hit-effects.md). 번개도 마찬가지라
## 줄기·균열·파편이 전부 **뻗어 나가는** 알갱이다.
##
## `GPUParticles3D` 가 아닌 이유, 에셋을 안 쓰는 이유, 판정을 안 하는 이유는
## `skill_fx.gd` 와 같다. **모양을 짓는 도구(바늘 메시·가산 재질·곡선)도 거기
## 것을 그대로 쓴다** — 두 벌로 두면 한쪽만 고쳐져 색과 굵기가 갈린다.

## 번개가 몇 번 치나. **순차적으로 겹쳐서** 친다 — 앞의 것이 아직 꺼지기 전에
## 다음이 들어와야 한 번 크게 친 것이 아니라 세 번 때린 것으로 읽힌다
const STRIKES := 3
## 다음 번개가 들어오는 간격. 균열 수명(0.5s)보다 훨씬 짧아서 겹친다
const STRIKE_GAP := 0.2
## 뒤로 갈수록 커진다 — 마지막 한 방이 가장 굵어야 마무리로 보인다
const STRIKE_SWELL := 0.22
## 세 번이 **완전히 같은 자리**면 두 번째·세 번째가 안 보인다. 조금씩 흔들어
## 겹치되 어긋나게 둔다 (난수가 아니라 상수라 테스트가 같은 값을 읽는다)
const JITTER: Array[Vector2] = [Vector2.ZERO, Vector2(0.28, -0.18), Vector2(-0.22, 0.26)]

## 떨어지는 자리 — 시전자가 보는 쪽 앞 몇 m. 스킬 사거리(4m)보다 짧아야
## "번개는 저기 떨어졌는데 안 맞았다" 가 안 된다 (`skills.ts` 의 `thunder_fall`)
const AHEAD := 2.8
## 줄기가 시작하는 높이. 720p 에서 1m 가 38px 이라 **266px** 이다 —
## 캐릭터(68px)의 네 배 높이에서 내려온다
const SKY := 7.0
## 시작점이 떨어지는 자리보다 얼마나 뒤인가. `AHEAD`(3.2)보다 크므로
## **시작점은 캐릭터보다 1.8m 뒤**다 — 그래서 번개가 뒤에서 앞으로 지나간다
const BEHIND := 5.0

## 줄기 한 가닥은 **시작점에서 땅까지 전체를 잇는다** (8.6m 를 덮고 남게 8.9m).
## 화면에서 338px 짜리 대각선이다.
##
## 처음에는 짧은 바늘(2.6m)을 초속 62m 로 날려 내려보냈다. **화면에 아무것도
## 남지 않았다** — 8.6m 를 0.14초에 지나가니 프레임 사이로 사라진다 (2026-09-18
## 에 캡처해서 확인했다). 번개는 **날아가는 물건이 아니라 한순간 이어져 있는
## 것**이라, 전체를 잇는 가닥을 띄우고 **꺼뜨리는** 쪽이 맞다
const BOLT_LENGTH := 8.9
## **얇아야 번개다.** 0.26m(10px)로 잡았더니 가닥 여섯이 겹쳐 화면에서
## **구겨진 흰 띠**가 됐다 (2026-09-18 캡처). 3px 이면 배경에 묻힐 것 같지만,
## 길이가 338px 이라 선으로 충분히 읽힌다 — 굵기가 아니라 길이가 번개를 만든다
const BOLT_WIDTH := 0.07
## 꺾이는 횟수와 폭. **매끄러운 바늘은 번개가 아니라 창이다** — 좌우로 꺾여야
## 번개로 읽힌다 (`_bolt_mesh`). **잘게 떨어야 한다** — 0.8m(30px)씩 휘게 했더니
## 폭 3px 짜리 선이 크게 휘어 사다리가 됐다 (2026-09-18 캡처)
const BOLT_KINKS := 13
const BOLT_KINK := 0.11
## 가닥 묶음을 몇 번 갈아 끼우나. **깜빡임이 곧 번개다** — 한 벌을 띄워 두면
## 세워 놓은 그림이 된다. 묶음마다 꺾인 모양이 다르다
const BOLT_FLICKERS := 3
const BOLT_FLICKER_GAP := 0.06
## 한 묶음에 몇 가닥. 묶음이 셋이라 **한 번에 세 가닥**이 겹친다 —
## 여섯이면 뭉쳐서 한 덩어리가 된다
const BOLT_STRANDS := 1
## 살짝 미끄러지며 꺼진다 — 제자리에서 꺼지면 붙여 놓은 그림과 다를 게 없다.
## 빠르면 줄기가 땅을 뚫고 화면 아래까지 내려간다 (2026-09-18 캡처)
const BOLT_SPEED := 1.5
## 한 묶음이 짧게 살아야 **동시에 두 묶음까지만** 겹친다 — 셋이 겹치면 격자가 된다
const BOLT_LIFE := 0.12
## 가닥이 흩어지는 각(도). 좁게 둬야 한 줄기로 읽힌다
const BOLT_SPREAD := 2.0

## 줄기에서 갈라지는 잔가지. 굵은 줄기 하나만 있으면 막대가 떨어진 것 같다
const FORK_STRANDS := 4
const FORK_LENGTH := 2.2
const FORK_WIDTH := 0.07
const FORK_SPEED := 10.0
const FORK_LIFE := 0.16
const FORK_SPREAD := 22.0

## 줄기가 서고 나서 땅이 갈라지기까지. 줄기가 **이미 땅까지 이어져 있으므로**
## 거의 곧바로다 — 그래도 한 프레임은 뒤여야 번개가 원인으로 읽힌다
const IMPACT_DELAY := 0.05

## 닿는 순간의 섬광. 알갱이를 줄이고 면을 늘렸다 — 여섯 조각 구를 아홉 개
## 띄우면 화면에서 **흰 육각형 덩어리**가 된다 (2026-09-18 캡처)
const FLASH_COUNT := 5
const FLASH_SIZE := 0.6
const FLASH_LIFE := 0.24

## **치는 순간 주위가 번쩍인다.** 번개를 번개로 읽게 하는 것은 줄기 모양보다
## 이쪽이다 — 하늘에서 온 빛이 땅을 비춰야 한다. 0.14초만 켜고 끈다
const LIGHT_RANGE := 9.0
const LIGHT_ENERGY := 7.0
const LIGHT_LIFE := 0.14

## 갈라지는 땅 — 금이 사방으로 뻗는다. 길이 2.2m = 84px
##
## 처음에는 열둘을 청백색 가산 혼합으로 뿌렸더니 화면에서 **흰 꽃**이 됐다
## (2026-09-18 캡처). 지금은 **어두운 틈**이다 — 밝은 바닥에 어두운 금이라야
## 갈라진 것으로 보인다. 개수를 줄이고 `randomness` 로 고르지 않게 흩는다
const CRACK_COUNT := 9
const CRACK_LENGTH := 2.2
## **금도 얇아야 금이다.** 0.14m(5px)짜리 매끄러운 바늘을 검게 뿌렸더니
## 갈라진 땅이 아니라 **검은 대못**이 방사됐다 (2026-09-18 캡처).
## 얇게, 그리고 줄기처럼 꺾이게 짓는다
const CRACK_WIDTH := 0.06
## 뻗는 속도와 사는 시간. `damping` 으로 곧 멈춘다 — 금은 날아가는 것이
## 아니라 그 자리에 남는다. 1m 쯤 뻗어 반지름 3.2m 를 덮는다
const CRACK_SPEED := 6.0
const CRACK_LIFE := 0.5

## 튀는 파편. 위로 솟아 중력으로 떨어진다 — 안 떨어지면 불똥이지 파편이 아니다.
## **흙은 빛나지 않는다** — 가산 혼합으로 뿌렸더니 노란 알갱이 무리가 됐다
## (2026-09-18 캡처). 지금은 어두운 흙덩이가 불투명하게 튄다
const DEBRIS_COUNT := 10
const DEBRIS_SIZE := 0.16
## 느리면 낙뢰 자리에 뭉쳐 **검은 얼룩**이 된다 (2026-09-18 캡처)
const DEBRIS_SPEED_MIN := 6.0
const DEBRIS_SPEED_MAX := 12.0
const DEBRIS_SPREAD := 58.0
const DEBRIS_LIFE := 0.5
const DEBRIS_GRAVITY := -16.0

## 균열과 파편이 나는 높이. 0 으로 두면 지면과 같은 면이라 깜빡인다
const GROUND := 0.06

## 번개는 **청백색**, 금은 **어두운 흙빛**, 파편도 흙이다. 할퀴기(자홍)·피해
## 숫자(연노랑)·치명타(주황)·피격(붉은색)과 한 화면에서 갈려야 한다
## 가산 혼합에 밝은 바닥이라 **옅은 청색은 흰색으로 날아간다** (2026-09-18 캡처).
## 제 색을 알아보게 하려면 데이터에 적힌 색이 진해야 한다
const COLOR_BOLT := Color("#7ec2ff")
const COLOR_CORE := Color("#ffffff")
const COLOR_CRACK := Color("#2b1f16")
const COLOR_DEBRIS := Color("#8a6a45")

## [{node, delay}, ...] — 늦게 켤 방출기들
var _delayed: Array = []
## [{node, at}, ...] — 늦게 켜고 곧 끌 번쩍임(조명)
var _lights: Array = []
var _t := 0.0
var _span := 0.0


## 낙뢰를 떨어뜨린다.
##
## `at` 은 시전자 발밑(월드 좌표), `facing` 은 시전자가 보는 쪽(rad, `player.rot`).
static func bolt(parent: Node3D, at: Vector3, facing: float) -> LightningFx:
	var fx := LightningFx.new()
	# 떨어지는 자리는 **화면이 아니라 캐릭터가 보는 쪽** 앞이다
	fx.position = at + Vector3(sin(facing) * AHEAD, 0.0, cos(facing) * AHEAD)
	# 몸이 보는 쪽으로 돌려 둔다 — 그러면 **로컬 +Z 가 앞**이라 줄기의 기울기를
	# 좌표 계산 없이 `-Z`(뒤)에서 원점(앞)으로 적으면 된다. 할퀴기는 카메라
	# 평면에 맞췄지만(X 자가 화면에서 X 여야 해서), 번개는 하늘에서 땅으로
	# 오는 것이라 **월드 기준**이어야 카메라를 돌려도 위에서 내려온다
	fx.rotation = Vector3(0.0, facing, 0.0)
	parent.add_child(fx)
	fx._build()
	return fx


func _build() -> void:
	# 메시는 세 번이 나눠 쓴다 — 타격마다 새로 깎으면 같은 모양을 세 벌 만든다.
	# **줄기는 묶음마다 꺾인 모양이 달라야** 깜빡이는 것으로 보인다 — 같은 가닥을
	# 다시 켜면 같은 번개가 세 번 켜지는 것이다
	var bolt_meshes: Array[ArrayMesh] = []
	for f in BOLT_FLICKERS:
		bolt_meshes.append(_bolt_mesh(BOLT_LENGTH, BOLT_WIDTH, BOLT_KINKS, BOLT_KINK, float(f)))
	var fork_mesh := _bolt_mesh(FORK_LENGTH, FORK_WIDTH, 4, BOLT_KINK * 0.35, 0.5)
	# 금도 꺾인다 — 매끄러운 바늘은 갈라진 틈이 아니라 못이다
	var crack_mesh := _bolt_mesh(CRACK_LENGTH, CRACK_WIDTH, 5, 0.22, 1.0)

	for i in STRIKES:
		var swell := 1.0 + float(i) * STRIKE_SWELL
		var shake: Vector2 = JITTER[i % JITTER.size()]
		var fell := float(i) * STRIKE_GAP

		# 한 번의 낙뢰가 한 노드다 — 흔들어 둔 자리를 방출기 일곱과 조명이 함께 쓴다
		var strike := Node3D.new()
		strike.position = Vector3(shake.x, 0.0, shake.y)
		add_child(strike)

		# 줄기 묶음이 50ms 씩 갈려 들어온다 — 그게 깜빡임이다
		for f in BOLT_FLICKERS:
			_emit(strike, _bolt_jet(bolt_meshes[f], swell), fell + float(f) * BOLT_FLICKER_GAP)
		_emit(strike, _fork_jet(fork_mesh, swell), fell + BOLT_FLICKER_GAP)
		# 땅에 닿은 뒤에 터지는 것들
		_emit(strike, _flash(swell), fell + IMPACT_DELAY)
		_emit(strike, _cracks(crack_mesh, swell), fell + IMPACT_DELAY)
		_emit(strike, _debris(swell), fell + IMPACT_DELAY)
		# 치는 순간 주위가 번쩍인다
		_add_light(strike, fell)


func _emit(parent: Node3D, node: CPUParticles3D, delay: float) -> void:
	parent.add_child(node)
	if delay > 0.0:
		node.emitting = false
		_delayed.append({"node": node, "delay": delay})
	_span = maxf(_span, delay + float(node.lifetime) + 0.1)


func _add_light(parent: Node3D, delay: float) -> void:
	var light := OmniLight3D.new()
	# 땅과 캐릭터를 같이 비추는 높이
	light.position = Vector3(0.0, 1.2, 0.0)
	light.omni_range = LIGHT_RANGE
	light.light_color = COLOR_BOLT
	light.light_energy = LIGHT_ENERGY
	light.visible = false
	parent.add_child(light)
	_lights.append({"node": light, "at": delay})
	_span = maxf(_span, delay + LIGHT_LIFE + 0.1)


func _process(delta: float) -> void:
	_t += delta
	for i in range(_delayed.size() - 1, -1, -1):
		var waiting: Dictionary = _delayed[i]
		if _t >= float(waiting.delay):
			var node: CPUParticles3D = waiting.node
			node.emitting = true
			_delayed.remove_at(i)

	# 번쩍임은 **세게 켜고 빠르게 죈다.** 일정하게 켜 두면 조명이 하나 놓인 것이다
	for i in range(_lights.size() - 1, -1, -1):
		var flash: Dictionary = _lights[i]
		var light: OmniLight3D = flash.node
		var age := _t - float(flash.at)
		if age < 0.0:
			continue
		if age >= LIGHT_LIFE:
			light.visible = false
			_lights.remove_at(i)
			continue
		light.visible = true
		light.light_energy = LIGHT_ENERGY * (1.0 - age / LIGHT_LIFE)

	if _t >= _span:
		queue_free()


## 내리꽂히는 줄기. **뒤 위쪽에서 시작해 앞 아래(원점)로 간다** —
## 방출기를 뒤로 물려 놓고 방향을 원점 쪽으로 준다
func _bolt_jet(mesh: Mesh, swell: float) -> CPUParticles3D:
	var jet := CPUParticles3D.new()
	jet.amount = BOLT_STRANDS
	jet.lifetime = BOLT_LIFE
	jet.one_shot = true
	# 가닥이 같은 순간에 내려와야 한 번 친 것이다. 흘려 보내면 비가 된다
	jet.explosiveness = 1.0
	jet.mesh = mesh
	jet.position = Vector3(0.0, SKY, -BEHIND)
	jet.direction = Vector3(0.0, -SKY, BEHIND).normalized()
	jet.spread = BOLT_SPREAD
	jet.initial_velocity_min = BOLT_SPEED * 0.6
	jet.initial_velocity_max = BOLT_SPEED
	# 감속하지 않는다 — 번개는 스러지는 것이 아니라 꽂히고 꺼진다
	jet.gravity = Vector3.ZERO
	# 알갱이를 진행 방향으로 세운다. 바늘이 +Y 로만 뻗어 있으므로
	# 내려가는 쪽이 곧 줄기의 길이 방향이 된다
	jet.particle_flag_align_y = true
	jet.scale_amount_min = 0.8 * swell
	jet.scale_amount_max = 1.2 * swell
	jet.scale_amount_curve = SkillFx._grow_curve()
	jet.color = COLOR_BOLT
	jet.color_ramp = SkillFx._fade_ramp(COLOR_CORE, COLOR_BOLT)
	jet.material_override = SkillFx._glow()
	return jet


## 줄기에서 갈라지는 잔가지. 같은 자리에서 같은 쪽으로 가지만 **넓게 흩어지고
## 짧게 산다** — 굵은 줄기 하나만 있으면 막대가 떨어진 것처럼 보인다
func _fork_jet(mesh: Mesh, swell: float) -> CPUParticles3D:
	var fork := CPUParticles3D.new()
	fork.amount = FORK_STRANDS
	fork.lifetime = FORK_LIFE
	fork.one_shot = true
	fork.explosiveness = 1.0
	fork.mesh = mesh
	fork.position = Vector3(0.0, SKY * 0.55, -BEHIND * 0.55)
	fork.direction = Vector3(0.0, -SKY, BEHIND).normalized()
	fork.spread = FORK_SPREAD
	fork.initial_velocity_min = FORK_SPEED * 0.6
	fork.initial_velocity_max = FORK_SPEED
	fork.damping_min = FORK_SPEED * 0.8
	fork.damping_max = FORK_SPEED * 1.6
	fork.gravity = Vector3.ZERO
	fork.particle_flag_align_y = true
	fork.scale_amount_min = 0.7 * swell
	fork.scale_amount_max = 1.1 * swell
	fork.scale_amount_curve = SkillFx._grow_curve()
	fork.color = COLOR_BOLT
	fork.color_ramp = SkillFx._fade_ramp(COLOR_CORE, COLOR_BOLT)
	fork.material_override = SkillFx._glow()
	return fork


## 닿는 순간 땅에서 부푸는 섬광. 작은 구 여럿이라 하나를 크게 띄우는 것보다
## 터진 것으로 읽힌다 (`skill_fx.gd` 의 코어와 같은 이유)
func _flash(swell: float) -> CPUParticles3D:
	var flash := CPUParticles3D.new()
	flash.amount = FLASH_COUNT
	flash.lifetime = FLASH_LIFE
	flash.one_shot = true
	flash.explosiveness = 1.0
	# 여섯 조각이면 화면에서 **육각형**이 드러난다 (2026-09-18 캡처)
	var ball := SphereMesh.new()
	ball.radius = FLASH_SIZE * 0.5
	ball.height = FLASH_SIZE
	ball.radial_segments = 10
	ball.rings = 5
	flash.mesh = ball
	flash.position = Vector3(0.0, GROUND + 0.3, 0.0)
	flash.direction = Vector3.ZERO
	flash.spread = 180.0
	flash.initial_velocity_min = 0.4
	flash.initial_velocity_max = 1.8
	flash.damping_min = 4.0
	flash.damping_max = 8.0
	flash.gravity = Vector3.ZERO
	flash.scale_amount_min = 0.6 * swell
	flash.scale_amount_max = 1.4 * swell
	flash.scale_amount_curve = SkillFx._burst_curve()
	flash.color = COLOR_CORE
	flash.color_ramp = SkillFx._fade_ramp(COLOR_CORE, COLOR_BOLT)
	flash.material_override = SkillFx._glow()
	return flash


## **갈라지는 땅.** 금이 떨어진 자리에서 사방으로 뻗다가 그 자리에 남는다.
##
## 지면을 따라 갈라져야 하므로 방향을 수평으로 두고 **`flatness` 를 1 로 올린다** —
## 방출 방향에서 위아래 성분이 사라져 XZ 평면 전방위가 된다. `spread` 180 만
## 주면 위로도 뻗어 금이 아니라 별표가 된다
func _cracks(mesh: Mesh, swell: float) -> CPUParticles3D:
	var cracks := CPUParticles3D.new()
	cracks.amount = CRACK_COUNT
	cracks.lifetime = CRACK_LIFE
	cracks.one_shot = true
	cracks.explosiveness = 1.0
	cracks.mesh = mesh
	cracks.position = Vector3(0.0, GROUND, 0.0)
	cracks.direction = Vector3(1.0, 0.0, 0.0)
	cracks.spread = 180.0
	cracks.flatness = 1.0
	cracks.initial_velocity_min = CRACK_SPEED * 0.45
	cracks.initial_velocity_max = CRACK_SPEED
	# 뻗다가 곧 멈춘다 — 끝까지 미끄러지면 금이 아니라 흘러가는 빛이 된다
	cracks.damping_min = CRACK_SPEED * 2.4
	cracks.damping_max = CRACK_SPEED * 3.6
	cracks.gravity = Vector3.ZERO
	cracks.particle_flag_align_y = true
	# **고르게 뻗으면 별표가 된다.** 길이와 시각을 흩어 금처럼 어긋나게 둔다
	cracks.randomness = 0.6
	cracks.scale_amount_min = 0.5 * swell
	cracks.scale_amount_max = 1.3 * swell
	cracks.scale_amount_curve = SkillFx._grow_curve()
	cracks.color = COLOR_CRACK
	# **흰 머리를 주지 않는다** — 청백색 가산 혼합으로 뿌렸다가 흰 꽃이 됐다
	cracks.color_ramp = _hold_ramp(COLOR_CRACK)
	cracks.material_override = _dirt()
	return cracks


## **튀는 파편.** 위로 솟아 중력으로 떨어진다 — 안 떨어지면 불똥이지 파편이
## 아니다. 진행 방향으로 세우지 않고 굴린다(`angular_velocity`): 흙덩이는
## 날아가는 방향으로 정렬하지 않는다
func _debris(swell: float) -> CPUParticles3D:
	var debris := CPUParticles3D.new()
	debris.amount = DEBRIS_COUNT
	debris.lifetime = DEBRIS_LIFE
	debris.one_shot = true
	debris.explosiveness = 1.0
	var chunk := BoxMesh.new()
	chunk.size = Vector3(DEBRIS_SIZE, DEBRIS_SIZE, DEBRIS_SIZE)
	debris.mesh = chunk
	debris.position = Vector3(0.0, GROUND, 0.0)
	debris.direction = Vector3(0.0, 1.0, 0.0)
	debris.spread = DEBRIS_SPREAD
	debris.initial_velocity_min = DEBRIS_SPEED_MIN
	debris.initial_velocity_max = DEBRIS_SPEED_MAX
	debris.gravity = Vector3(0.0, DEBRIS_GRAVITY, 0.0)
	debris.angle_min = -180.0
	debris.angle_max = 180.0
	debris.angular_velocity_min = -420.0
	debris.angular_velocity_max = 420.0
	debris.scale_amount_min = 0.6 * swell
	debris.scale_amount_max = 1.3 * swell
	debris.color = COLOR_DEBRIS
	debris.color_ramp = _hold_ramp(COLOR_DEBRIS)
	debris.material_override = _dirt()
	return debris


## 원점에서 +Y 로 뻗으며 **좌우로 꺾이는** 번개 가닥. `phase` 가 다르면 꺾인
## 자리가 달라서, 같은 수치로도 다른 번개가 나온다.
##
## **매끄러운 바늘은 번개가 아니라 창이다** (2026-09-18 에 캡처해서 알았다).
## 뿌리가 굵고 끝이 가늘며, 칸마다 좌우로 튄다
static func _bolt_mesh(length: float, width: float, kinks: int, kink: float, phase: float) -> ArrayMesh:
	var steps := kinks * 2
	var points: Array[Vector2] = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		# 한 칸마다 좌우로 번갈아 튄다. 시작과 끝은 제자리여야 줄기가 이어진다
		var side := 1.0 if (i + int(phase)) % 2 == 0 else -1.0
		var amp := kink * (0.4 + 0.6 * sin((t + phase * 0.37) * PI))
		if i == 0 or i == steps:
			amp = 0.0
		points.append(Vector2(side * amp, t * length))

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a := points[i]
		var b := points[i + 1]
		# **폭은 선분에 수직으로 준다.** x 축으로만 주면 눕다시피 한 칸에서
		# 폭이 사라져 꺾인 자리가 **빈 사각형**이 된다 (2026-09-18 캡처 —
		# 줄기가 구겨진 철망처럼 보였다)
		var along := (b - a).normalized()
		var across := Vector2(-along.y, along.x)
		var ha := across * _taper(float(i) / float(steps)) * width * 0.5
		var hb := across * _taper(float(i + 1) / float(steps)) * width * 0.5
		# 앞뒤 어느 쪽에서 봐도 보여야 한다 (재질에서 컬링을 끈다)
		tool.add_vertex(Vector3(a.x - ha.x, a.y - ha.y, 0.0))
		tool.add_vertex(Vector3(a.x + ha.x, a.y + ha.y, 0.0))
		tool.add_vertex(Vector3(b.x - hb.x, b.y - hb.y, 0.0))
		tool.add_vertex(Vector3(b.x - hb.x, b.y - hb.y, 0.0))
		tool.add_vertex(Vector3(a.x + ha.x, a.y + ha.y, 0.0))
		tool.add_vertex(Vector3(b.x + hb.x, b.y + hb.y, 0.0))
	return tool.commit()


## 뿌리는 굵고 끝은 가늘다 — 번개는 내려갈수록 얇아진다.
##
## **차이를 크게 두면 안 된다.** 뿌리(하늘 쪽)가 카메라에 더 가까워서, 두 배로
## 굵게 하면 화면 위쪽만 네모난 고리가 되어 보인다 (2026-09-18 캡처)
static func _taper(t: float) -> float:
	return 0.6 + 0.4 * (1.0 - t)


## 제 색을 **끝까지 유지하다 마지막에만** 사라진다. 흰 머리를 섞으면
## 가장 큰 순간이 가장 하얀 순간과 겹쳐 무엇이든 흰 덩어리가 된다
static func _hold_ramp(color: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 1.0))
	ramp.set_offset(1, 0.7)
	ramp.set_color(1, Color(color.r, color.g, color.b, 1.0))
	ramp.add_point(1.0, Color(color.r, color.g, color.b, 0.0))
	return ramp


## 조명을 안 받는 **불투명** 재질. 금과 파편은 빛이 아니라 흙이다 —
## 가산 혼합으로 뿌렸더니 밝은 알갱이 무리가 됐다 (2026-09-18 캡처).
## 깊이 검사는 켜 둔다: 지면 위 6cm 라 가려지지 않고, 꺼 두면 몸 앞으로 튀어나온다
static func _dirt() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	return mat
