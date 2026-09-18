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
## 다음 번개가 들어오는 간격. 균열 수명(0.45s)보다 훨씬 짧아서 겹친다
const STRIKE_GAP := 0.12
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

## 줄기 한 가닥의 길이·폭. **미터가 아니라 px 로 정한다** — 길이 2.6m = 99px,
## 폭 0.22m = 8px 으로 할퀴기 발톱(57px/6px)보다 굵고 길다
const BOLT_LENGTH := 2.6
const BOLT_WIDTH := 0.22
## 몇 가닥이 함께 내려오나. 한 가닥이면 그어 놓은 선이 된다
const BOLT_STRANDS := 7
## 내려오는 속도(m/s)와 사는 시간. 8.6m 를 0.14초에 지나간다 —
## 눈으로는 꽂히는 순간만 남고, 그게 번개다
const BOLT_SPEED := 62.0
const BOLT_LIFE := 0.2
## 가닥이 흩어지는 각(도). 좁게 둬야 한 줄기로 읽힌다
const BOLT_SPREAD := 4.0

## 줄기에서 갈라지는 잔가지. 굵은 줄기 하나만 있으면 막대가 떨어진 것 같다
const FORK_STRANDS := 5
const FORK_LENGTH := 1.2
const FORK_WIDTH := 0.12
const FORK_SPEED := 38.0
const FORK_LIFE := 0.16
const FORK_SPREAD := 17.0

## 줄기가 땅에 닿기까지 걸리는 시간. **균열과 파편은 이만큼 늦게 터진다** —
## 닿기 전에 땅이 갈라지면 번개가 원인으로 안 읽힌다
const IMPACT_DELAY := 0.13

## 닿는 순간의 섬광
const FLASH_COUNT := 9
const FLASH_SIZE := 0.9
const FLASH_LIFE := 0.22

## 갈라지는 땅 — 금이 사방으로 뻗는다. 길이 1.6m = 61px
const CRACK_COUNT := 12
const CRACK_LENGTH := 1.6
const CRACK_WIDTH := 0.17
## 뻗는 속도와 사는 시간. `damping` 으로 곧 멈춘다 — 금은 날아가는 것이
## 아니라 그 자리에 남는다. 1m 쯤 뻗어 반지름 2.6m(지름 5.2m)를 덮는다
const CRACK_SPEED := 5.5
const CRACK_LIFE := 0.45

## 튀는 파편. 위로 솟아 중력으로 떨어진다 — 안 떨어지면 불똥이지 파편이 아니다
const DEBRIS_COUNT := 16
const DEBRIS_SIZE := 0.17
const DEBRIS_SPEED_MIN := 5.0
const DEBRIS_SPEED_MAX := 11.0
const DEBRIS_SPREAD := 46.0
const DEBRIS_LIFE := 0.5
const DEBRIS_GRAVITY := -16.0

## 균열과 파편이 나는 높이. 0 으로 두면 지면과 같은 면이라 깜빡인다
const GROUND := 0.06

## 번개는 **청백색**, 균열은 옅은 파랑, 파편은 흙빛이다. 할퀴기(자홍)·피해
## 숫자(연노랑)·치명타(주황)·피격(붉은색)과 한 화면에서 갈려야 한다
const COLOR_BOLT := Color("#bfe4ff")
const COLOR_CORE := Color("#ffffff")
const COLOR_CRACK := Color("#8fb8ff")
const COLOR_DEBRIS := Color("#d9a05a")

## [{node, delay}, ...] — 늦게 켤 방출기들
var _delayed: Array = []
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
	# 메시는 세 번이 나눠 쓴다 — 타격마다 새로 깎으면 같은 모양을 세 벌 만든다
	var bolt_mesh := SkillFx._needle_mesh(BOLT_LENGTH, BOLT_WIDTH)
	var fork_mesh := SkillFx._needle_mesh(FORK_LENGTH, FORK_WIDTH)
	var crack_mesh := SkillFx._needle_mesh(CRACK_LENGTH, CRACK_WIDTH)

	for i in STRIKES:
		var swell := 1.0 + float(i) * STRIKE_SWELL
		var shake: Vector2 = JITTER[i % JITTER.size()]
		var fell := float(i) * STRIKE_GAP

		# 한 번의 낙뢰가 한 노드다 — 흔들어 둔 자리를 방출기 다섯이 함께 쓴다
		var strike := Node3D.new()
		strike.position = Vector3(shake.x, 0.0, shake.y)
		add_child(strike)

		_emit(strike, _bolt_jet(bolt_mesh, swell), fell)
		_emit(strike, _fork_jet(fork_mesh, swell), fell)
		# 땅에 닿은 뒤에 터지는 것들
		_emit(strike, _flash(swell), fell + IMPACT_DELAY)
		_emit(strike, _cracks(crack_mesh, swell), fell + IMPACT_DELAY)
		_emit(strike, _debris(swell), fell + IMPACT_DELAY)


func _emit(parent: Node3D, node: CPUParticles3D, delay: float) -> void:
	parent.add_child(node)
	if delay > 0.0:
		node.emitting = false
		_delayed.append({"node": node, "delay": delay})
	_span = maxf(_span, delay + float(node.lifetime) + 0.1)


func _process(delta: float) -> void:
	_t += delta
	for i in range(_delayed.size() - 1, -1, -1):
		var waiting: Dictionary = _delayed[i]
		if _t >= float(waiting.delay):
			var node: CPUParticles3D = waiting.node
			node.emitting = true
			_delayed.remove_at(i)
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
	jet.initial_velocity_min = BOLT_SPEED * 0.9
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
	fork.position = Vector3(0.0, SKY * 0.62, -BEHIND * 0.62)
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
	var ball := SphereMesh.new()
	ball.radius = FLASH_SIZE * 0.5
	ball.height = FLASH_SIZE
	ball.radial_segments = 6
	ball.rings = 3
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
	cracks.scale_amount_min = 0.7 * swell
	cracks.scale_amount_max = 1.2 * swell
	cracks.scale_amount_curve = SkillFx._grow_curve()
	cracks.color = COLOR_CRACK
	cracks.color_ramp = SkillFx._fade_ramp(COLOR_CORE, COLOR_CRACK)
	cracks.material_override = SkillFx._glow()
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
	debris.color_ramp = SkillFx._fade_ramp(COLOR_DEBRIS, COLOR_DEBRIS)
	debris.material_override = SkillFx._glow()
	return debris
