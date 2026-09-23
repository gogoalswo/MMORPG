extends SceneTree

## World 와 Transport 가 붙어 실제로 캐릭터가 움직이는지 본다.
## 화면 없이 글로만 확인한다 (docs/features/verification.md 의 방식).
##
##   godot --headless --path godot --script tests/world_test.gd

var _failed := 0


func _init() -> void:
	var t := LocalTransport.new()
	t.open(GameData.start_zone())

	var start := _me(t)
	_expect("시작 자리는 마을 스폰", Vector2(start.x, start.z), Vector2(0, 0))
	_expect_text("존 이름", str(t.snapshot().get("zone")), "village")

	# 1초어치 오른쪽 이동 (60틱). 4.6m/s 이므로 4.6m
	for i in 60:
		t.send(&"input", {"seq": i + 1, "dx": 1.0, "dz": 0.0, "dt": 1.0 / 60.0})
	var after := _me(t)
	_expect("1초 달리면 4.6m", Vector2(after.x, after.z), Vector2(4.6, 0.0))

	# 같은 순번을 다시 보내면 무시한다 (지연 도착한 중복)
	t.send(&"input", {"seq": 60, "dx": 1.0, "dz": 0.0, "dt": 1.0 / 60.0})
	_expect("중복 순번은 무시", Vector2(_me(t).x, 0), Vector2(after.x, 0))

	# 계속 달리면 존 경계에서 멈춘다
	for i in 2000:
		t.send(&"input", {"seq": 1000 + i, "dx": 1.0, "dz": 0.0, "dt": 0.1})
	_expect("경계에서 멈춘다", Vector2(_me(t).x, 0), Vector2(27.0, 0))

	# 방향을 보냈으면 그쪽을 본다
	t.send(&"input", {"seq": 9000, "dx": 0.0, "dz": -1.0, "dt": 0.05})
	_expect("바라보는 각", Vector2(_me(t).rot, 0), Vector2(PI, 0))

	if _failed == 0:
		print("World: 전부 통과")
		quit(0)
	else:
		print("World: %d개 실패" % _failed)
		quit(1)


func _me(t: Transport) -> Dictionary:
	return t.snapshot().get("players", {}).get(t.my_id(), {})


func _expect(label: String, got: Vector2, want: Vector2) -> void:
	if absf(got.x - want.x) > 1e-5 or absf(got.y - want.y) > 1e-5:
		print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
		_failed += 1


func _expect_text(label: String, got: String, want: String) -> void:
	if got != want:
		print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
		_failed += 1
