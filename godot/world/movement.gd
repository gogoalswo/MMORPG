class_name Movement
extends RefCounted

## packages/shared/src/movement.ts 이식본.
##
## **TS 와 한 글자도 다르면 안 된다.** 나중에 서버(고도 헤드리스)를 붙이면
## 클라이언트 예측과 서버 판정이 같은 답을 내야 하고, 다르면 매 틱 보정이 튀면서
## 캐릭터가 떤다. 원본 주석과 이유는 movement.ts 에 있다.
##
## 검증: godot/tests/movement_test.gd 가 TS 로 낸 값과 대조한다.

## 입력 하나가 담을 수 있는 최대 시간. 안 막으면 dt 를 부풀려 순간이동할 수 있다
const MAX_INPUT_DT := 0.1

## 캐릭터가 차지하는 반지름 — 충돌 판정에만 쓴다 (모델 크기와는 별개다)
const PLAYER_RADIUS := 0.4

## **몬스터끼리만** 추가로 벌려 두는 거리. 캐릭터가 낀 판정에는 안 들어간다.
## 몬스터는 한 사람을 쫓아 우르르 모여서, 몸끼리 딱 붙기만 해도 뭉쳐 보인다.
const MONSTER_GAP := 0.2

## 몬스터가 차지하는 반지름. 모델 크기(scale)에 비례한다.
##
## **0.38 을 곱하는 이유는 붙어서 때릴 수 있어야 하기 때문이다.** 이보다 크게 잡으면
## 충돌이 공격을 막아 서로 못 때린다 — 몸집이 큰 보스부터 그렇게 된다.
static func monster_radius(scale: float) -> float:
	return 0.38 * scale

## 존 경계까지의 거리 (지면 가장자리에서 조금 안쪽)
static func zone_half_size(zone_size: float) -> float:
	return zone_size / 2.0 - 4.0


## 겹친 만큼 밖으로 민다. **미는 쪽은 언제나 움직이는 쪽이다.**
## solids 는 [{x, z, r}, ...]
static func push_out_of_solids(
	state: Dictionary,
	solids: Array,
	half_size: float,
	radius: float = PLAYER_RADIUS,
	tie_angle: float = 0.0,
) -> void:
	for solid in solids:
		var dx: float = state.x - solid.x
		var dz: float = state.z - solid.z
		var minimum: float = solid.r + radius
		var squared: float = dx * dx + dz * dz
		if squared >= minimum * minimum:
			continue

		var distance := sqrt(squared)
		if distance < 1e-4:
			# 한가운데 정확히 겹쳤다 — 밀 방향이 없다. tie_angle 쪽으로 밀어낸다
			state.x = clampf(solid.x + cos(tie_angle) * minimum, -half_size, half_size)
			state.z = clampf(solid.z + sin(tie_angle) * minimum, -half_size, half_size)
			continue
		state.x = clampf(solid.x + (dx / distance) * minimum, -half_size, half_size)
		state.z = clampf(solid.z + (dz / distance) * minimum, -half_size, half_size)


## 입력 하나를 적용한다. 믿을 수 없는 값이 들어와도 여기서 전부 걸러진다.
## state 는 {x, z} 를 가진 Dictionary 이고 제자리에서 고쳐진다.
static func apply_move(
	state: Dictionary,
	dx_in: float,
	dz_in: float,
	dt_in: float,
	half_size: float,
	run_speed: float,
	solids: Array = [],
) -> void:
	var dx := dx_in
	var dz := dz_in

	if not is_finite(dx) or not is_finite(dz):
		return

	# 방향은 단위벡터를 넘을 수 없다 (길이를 부풀린 속도 핵 차단)
	var length := sqrt(dx * dx + dz * dz)
	if length > 1.0:
		dx /= length
		dz /= length
	elif length < 1e-4:
		return

	var dt := clampf(dt_in, 0.0, MAX_INPUT_DT) if is_finite(dt_in) else 0.0

	state.x = clampf(state.x + dx * run_speed * dt, -half_size, half_size)
	state.z = clampf(state.z + dz * run_speed * dt, -half_size, half_size)

	# 움직인 다음에 민다. 먼저 밀면 이미 빠져나온 자리에서 또 밀려 제자리걸음이 된다
	if not solids.is_empty():
		push_out_of_solids(state, solids, half_size)


## 무리 안에서 **다른 몸과 겹치지 않는 자리**를 고른다. 몬스터 스폰이 쓴다.
##
## 그냥 원 안에 무작위로 뿌리면 몇 마리는 반드시 겹치고, 몬스터는 겹친 채로 가만히
## 서 있으므로 그게 그대로 화면에 남는다. 빈 자리를 tries 번 찍어 보고 전부 겹치면
## **가장 여유 있는 후보**를 골라 한 번 민다 — "될 때까지" 돌리지 않는다. 그건
## 서버가 멈추는 길이다.
static func scatter_spawn(
	center_x: float,
	center_z: float,
	center_radius: float,
	my_radius: float,
	taken: Array,
	half_size: float,
	rng: RandomNumberGenerator,
	tries: int = 12,
) -> Dictionary:
	var best := {"x": center_x, "z": center_z}
	var best_clearance := -INF

	for i in tries:
		var angle := rng.randf() * TAU
		# 제곱근을 씌워야 원 안에 고르게 퍼진다 (안 씌우면 가운데로 몰린다)
		var dist := sqrt(rng.randf()) * center_radius
		var spot := {
			"x": clampf(center_x + cos(angle) * dist, -half_size, half_size),
			"z": clampf(center_z + sin(angle) * dist, -half_size, half_size),
		}

		var clearance := INF
		for other in taken:
			var gap: float = (
				Vector2(spot.x - other.x, spot.z - other.z).length() - (other.r + my_radius)
			)
			if gap < clearance:
				clearance = gap
		if clearance >= 0.0:
			return spot
		if clearance > best_clearance:
			best_clearance = clearance
			best = spot

	push_out_of_solids(best, taken, half_size, my_radius)
	return best
