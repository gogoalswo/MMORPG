extends SceneTree

## Movement 이식본이 TS 원본과 같은 답을 내는지 본다.
##
## 기준값은 packages/shared/src/movement.ts 를 node 로 직접 돌려서 뽑았다
## (2026-09-16). 두 쪽이 갈라지면 나중에 서버를 붙였을 때 매 틱 보정이 튄다.
##
##   godot --headless --path godot --script tests/movement_test.gd
##
## 실패하면 종료코드 1 로 끝나므로 CI 에서도 쓸 수 있다.

const HALF := 42.0        # zoneHalfSize(92) — 마을
const RUN_SPEED := 4.6
const EPS := 1e-6

var _failed := 0


func _init() -> void:
	_check_constants()
	_case_diagonal()
	_case_dt_cap()
	_case_normalize()
	_case_edge()
	_case_push()
	_case_dead_center()

	if _failed == 0:
		print("이동 판정: 전부 통과")
		quit(0)
	else:
		print("이동 판정: %d개 실패" % _failed)
		quit(1)


func _expect(label: String, got: float, want: float) -> void:
	if absf(got - want) > EPS:
		print("  실패 %s: %.6f 이어야 하는데 %.6f" % [label, want, got])
		_failed += 1


func _check_constants() -> void:
	# 내보낸 JSON 이 기준값과 같은 세계인지 먼저 본다
	var zone := GameData.zone("village")
	_expect("마을 크기", float(zone.get("size", 0)), 92.0)
	_expect("경계", Movement.zone_half_size(float(zone.size)), HALF)
	_expect("달리기 속도", float(GameData.constants().get("runSpeed", 0)), RUN_SPEED)


func _case_diagonal() -> void:
	var s := {"x": 0.0, "z": 0.0}
	for i in 10:
		Movement.apply_move(s, 0.6, 0.8, 1.0 / 60.0, HALF, RUN_SPEED)
	_expect("A 대각선10회 x", s.x, 0.46)
	_expect("A 대각선10회 z", s.z, 0.613333)


func _case_dt_cap() -> void:
	# dt 0.5 를 넣어도 MAX_INPUT_DT(0.1) 로 잘린다
	var s := {"x": 0.0, "z": 0.0}
	Movement.apply_move(s, 1.0, 0.0, 0.5, HALF, RUN_SPEED)
	_expect("B dt상한", s.x, 0.46)


func _case_normalize() -> void:
	# 길이 10 짜리 방향을 보내도 단위벡터로 깎인다
	var s := {"x": 0.0, "z": 0.0}
	Movement.apply_move(s, 10.0, 0.0, 0.1, HALF, RUN_SPEED)
	_expect("C 벡터정규화", s.x, 0.46)


func _case_edge() -> void:
	var s := {"x": HALF - 0.01, "z": 0.0}
	Movement.apply_move(s, 1.0, 0.0, 0.1, HALF, RUN_SPEED)
	_expect("D 경계", s.x, HALF)


func _case_push() -> void:
	var s := {"x": 0.0, "z": 0.0}
	Movement.push_out_of_solids(s, [{"x": 0.3, "z": 0.0, "r": 1.0}], HALF)
	_expect("E 밀기", s.x, -1.1)
	_expect("E 밀기 z", s.z, 0.0)


func _case_dead_center() -> void:
	# 정확히 겹치면 tie_angle(0) 쪽, 즉 +x 로 밀린다
	var s := {"x": 5.0, "z": 5.0}
	Movement.push_out_of_solids(s, [{"x": 5.0, "z": 5.0, "r": 1.0}], HALF)
	_expect("F 한가운데 x", s.x, 6.4)
	_expect("F 한가운데 z", s.z, 5.0)
