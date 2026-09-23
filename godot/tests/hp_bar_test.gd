extends SceneTree

## 머리 위 체력 막대가 규칙대로 뜨는지 본다.
##
##   내 것   — 늘 보이고, 머리 위에 있고, 체력을 따라 줄고, 죽으면 감춰진다
##   몬스터  — **골라 뒀거나 내가 때린 놈만.** 그 밖에는 서지 않고,
##             시간이 지나거나 죽으면 치운다
##
## 스크린샷을 찍지 않는다 — 여기서 볼 것("섰나·어디 있나·얼마나 찼나")은 전부
## 노드 수치다. 눈으로 볼 것은 색뿐이다 (select_test.gd 와 같은 이유).
##
##   godot --headless --path godot --script tests/hp_bar_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _run() -> void:
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	await _case_player(game)

	# 마을에는 몬스터가 없다. 사냥터로 옮겨야 막대를 달 놈이 생긴다
	game._transport.send(&"travel", {"zone": "meadow"})
	for i in 3:
		await process_frame

	var mob := _nearest(game)
	if mob.is_empty():
		_fail("존에 몬스터가 없다")
		_done()
		return

	await _case_quiet(game, mob)
	await _case_selected(game, mob)
	await _case_hit(game)
	await _case_dead(game, mob)
	_done()


## 내 막대는 늘 서 있고, 머리 위에 있고, 체력을 따라 줄어든다
func _case_player(game: Node3D) -> void:
	var bar: HpBar3D = game._player_bar
	if bar == null or not is_instance_valid(bar):
		_fail("내 체력 막대가 없다")
		return
	if not bar.visible:
		_fail("내 체력 막대가 안 보인다")
	if not is_equal_approx(bar.ratio(), 1.0):
		_fail("가득 찬 체력인데 막대가 %.2f 다" % bar.ratio())

	var head := HpBar3D.head_height(game._player)
	if bar.position.y < head - 0.01:
		_fail("막대가 머리(%.2f m) 아래에 있다 (%.2f m)" % [head, bar.position.y])
	else:
		print("  내 막대 %.2f m (머리 %.2f m), 가로 %.2f m" % [
			bar.position.y, head, HpBar3D.WIDTH])
	var gap := Vector2(bar.position.x - game._player.position.x,
		bar.position.z - game._player.position.z).length()
	if gap > 0.05:
		_fail("내 막대가 몸 위가 아니다 (%.2f m 떨어져 있다)" % gap)

	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id())
	me.hp = int(me.stats.maxHp) / 2
	await process_frame
	if absf(bar.ratio() - 0.5) > 0.05:
		_fail("체력을 반으로 깎았는데 막대가 %.2f 다" % bar.ratio())
	me.hp = me.stats.maxHp

	# 죽으면 몸과 같이 감춘다
	me.dead = true
	await process_frame
	if bar.visible:
		_fail("죽었는데 내 막대가 남았다")
	me.dead = false
	await process_frame


## 안 고르고 안 때린 놈에게는 막대가 없다 — 무리 전부가 달면 화면이 덮인다
func _case_quiet(game: Node3D, mob: Dictionary) -> void:
	if not game._mob_bars.is_empty():
		_fail("아무것도 안 했는데 몬스터 막대가 %d 개 섰다" % game._mob_bars.size())


## 고르면 선다. 놓으면 사라진다
func _case_selected(game: Node3D, mob: Dictionary) -> void:
	_click(game, Vector3(mob.x, 0.0, mob.z))
	await process_frame
	if game._selected_mob != str(mob.id):
		_fail("몬스터를 눌렀는데 안 골라졌다")
		return

	var bar: HpBar3D = game._mob_bars.get(str(mob.id))
	if bar == null or not is_instance_valid(bar):
		_fail("골랐는데 막대가 안 섰다")
		return
	if not is_equal_approx(bar.ratio(), 1.0):
		_fail("안 때린 몬스터인데 막대가 %.2f 다" % bar.ratio())
	var node: Node3D = game._mob_nodes.get(str(mob.id))
	var head := HpBar3D.head_height(node)
	if bar.position.y < head - 0.01:
		_fail("몬스터 막대가 머리(%.2f m) 아래다 (%.2f m)" % [head, bar.position.y])
	else:
		print("  몬스터 막대 %.2f m (머리 %.2f m)" % [bar.position.y, head])
	# **그려진 몸과 댄다.** 몬스터는 순찰로 걷는다 — 받아 둔 `mob` 좌표나 판정의 지금
	# 좌표와 대면, 막대·몸이 그려진 뒤 판정이 한 틱 더 걸은 만큼(0.05 m) 어긋나
	# CI 에서 운 나쁘게 깨졌다 (2026-09-23). 눈에 보이는 건 몸과 막대의 관계다
	var gap := Vector2(bar.position.x - node.position.x, bar.position.z - node.position.z).length()
	if gap > 0.05:
		_fail("몬스터 막대가 몸 위가 아니다 (%.2f m 떨어져 있다)" % gap)

	# 반쯤 깎으면 막대도 반이다
	mob.hp = int(mob.max_hp) / 2
	await process_frame
	if absf(bar.ratio() - 0.5) > 0.05:
		_fail("체력을 반으로 깎았는데 몬스터 막대가 %.2f 다" % bar.ratio())
	mob.hp = mob.max_hp

	game._clear_selection()
	await process_frame
	if game._mob_bars.has(str(mob.id)):
		_fail("고름을 풀었는데 막대가 남았다")


## 때리면 안 골라도 선다. 그리고 시간이 지나면 치운다
func _case_hit(game: Node3D) -> void:
	var mob := _nearest(game)
	if mob.is_empty():
		_fail("때릴 몬스터가 없다")
		return
	var id := str(mob.id)
	if game._selected_mob == id:
		game._clear_selection()

	game._on_event(&"hit", {
		"target": id, "target_kind": "monster", "amount": 5,
		"crit": false, "killed": false, "x": mob.x, "z": mob.z,
	})
	await process_frame
	if not game._mob_bars.has(id):
		_fail("때렸는데 막대가 안 섰다")
		return

	# 때린 뒤 남는 시간이 지나면 사라진다
	game._mob_bar_until[id] = Time.get_ticks_msec() - 1
	await process_frame
	if game._mob_bars.has(id):
		_fail("때린 지 %d ms 가 지났는데 막대가 남았다" % game.MOB_BAR_MS)

	# 내가 맞은 것으로는 서지 않는다 (막대는 내가 때린 놈의 것이다)
	game._on_event(&"hit", {
		"target": game._transport.my_id(), "target_kind": "player", "amount": 5,
		"crit": false, "killed": false, "x": mob.x, "z": mob.z,
	})
	await process_frame
	if not game._mob_bars.is_empty():
		_fail("내가 맞았을 뿐인데 몬스터 막대가 섰다")


## 죽으면 치운다. 시체에 막대가 남으면 산 놈처럼 보인다
func _case_dead(game: Node3D, mob: Dictionary) -> void:
	var live := _nearest(game)
	if live.is_empty():
		return
	var id := str(live.id)
	_click(game, Vector3(live.x, 0.0, live.z))
	await process_frame
	if not game._mob_bars.has(id):
		_fail("고른 몬스터에 막대가 없다")
		return
	live.hp = 0
	await process_frame
	if game._mob_bars.has(id):
		_fail("죽었는데 막대가 남았다")
	if game._mob_bar_until.has(id):
		_fail("죽었는데 때린 기록이 남았다 — 살아나면 막대가 그대로 뜬다")


func _click(game: Node3D, at: Vector3) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = game._camera.unproject_position(at)
	game._unhandled_input(press)


func _nearest(game: Node3D) -> Dictionary:
	var snap: Dictionary = game._transport.snapshot()
	var me: Dictionary = snap.get("players", {}).get(game._transport.my_id(), {})
	var best: Dictionary = {}
	var best_gap := INF
	for monster in snap.get("monsters", []):
		if int(monster.hp) <= 0:
			continue
		var gap: float = Vector2(monster.x - me.x, monster.z - me.z).length()
		if gap < best_gap:
			best_gap = gap
			best = monster
	return best


func _done() -> void:
	if _failed == 0:
		print("머리 위 체력 막대: 통과")
		quit(0)
	else:
		print("머리 위 체력 막대: %d개 실패" % _failed)
		quit(1)
