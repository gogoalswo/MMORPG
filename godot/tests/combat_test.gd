extends SceneTree

## 전투 공식이 TS 원본과 같은 답을 내는지 본다.
## 기준값은 packages/shared/src/combat.ts 를 node 로 직접 돌려 뽑았다 (2026-09-17).
##
##   godot --headless --path godot --script tests/combat_test.gd

var _failed := 0


func _init() -> void:
	_stats()
	_damage()
	_exp()
	_cooldown()
	_crit()
	_fight()

	if _failed == 0:
		print("전투: 전부 통과")
		quit(0)
	else:
		print("전투: %d개 실패" % _failed)
		quit(1)


func _eq(label: String, got, want) -> void:
	if typeof(got) == TYPE_FLOAT or typeof(want) == TYPE_FLOAT:
		if absf(float(got) - float(want)) < 1e-9:
			return
	elif got == want:
		return
	print("  실패 %s: %s 이어야 하는데 %s" % [label, want, got])
	_failed += 1


func _stats() -> void:
	var k1 := Combat.stats_for("knight", 1)
	_eq("기사1 체력", k1.maxHp, 140)
	_eq("기사1 공격", k1.attack, 12)
	_eq("기사1 방어", k1.defense, 8)
	_eq("기사1 사거리", k1.attackRange, 2.4)
	_eq("기사1 간격", k1.attackCooldown, 900.0)

	var k10 := Combat.stats_for("knight", 10)
	_eq("기사10 체력", k10.maxHp, 266)
	_eq("기사10 공격", k10.attack, 32)
	_eq("기사10 방어", k10.defense, 21)

	var m50 := Combat.stats_for("mage", 50)
	_eq("마법사50 체력", m50.maxHp, 374)
	_eq("마법사50 공격", m50.attack, 196)
	_eq("마법사50 방어", m50.defense, 28)


func _damage() -> void:
	_eq("피해 12vs3", Combat.compute_damage(12, 3), 11)
	_eq("피해 100vs45", Combat.compute_damage(100, 45), 50)
	# 방어가 아무리 높아도 최소 1 은 들어간다 — 안 그러면 전투가 멈춘다
	_eq("피해 5vs500", Combat.compute_damage(5, 500), 1)


func _exp() -> void:
	_eq("다음레벨 1", Combat.exp_to_next(1), 55)
	_eq("다음레벨 10", Combat.exp_to_next(10), 872)
	_eq("다음레벨 199", Combat.exp_to_next(199), 31549)

	var grown := Combat.apply_exp(1, 0, 1000)
	_eq("1000경험치 레벨", grown.level, 5)
	_eq("1000경험치 나머지", grown.exp, 323)

	var small := Combat.apply_exp(1, 0, 54)
	_eq("54경험치는 안오름", small.level, 1)

	_eq("보상 3레벨몹/1레벨", Combat.exp_reward(3, 1, 25), 31)
	# 8레벨 이상 낮으면 0 — 약한 몬스터만 잡는 걸 막는다
	_eq("보상 1레벨몹/10레벨", Combat.exp_reward(1, 10, 25), 0)
	_eq("보상 보스", Combat.exp_reward(9, 1, 67), 131)


func _cooldown() -> void:
	_eq("간격 900/속도0", Combat.effective_cooldown(900, 0), 900)
	_eq("간격 900/속도1", Combat.effective_cooldown(900, 1), 450)
	_eq("간격 700/속도1", Combat.effective_cooldown(700, 1), 350)
	# 경직은 400ms 를 넘지 않고, 간격이 더 짧으면 간격까지만
	_eq("경직 900", Combat.attack_root_ms(900), 400)
	_eq("경직 350", Combat.attack_root_ms(350), 350)


func _crit() -> void:
	_eq("치명타 .05/.04", Combat.roll_crit(0.05, 0.04), true)
	_eq("치명타 .05/.06", Combat.roll_crit(0.05, 0.06), false)
	# 상한 0.75 — 0.9 를 줘도 0.8 굴림은 안 터진다
	_eq("치명타 상한", Combat.roll_crit(0.9, 0.8), false)


## World 에서 실제로 때려 죽여 본다.
##
## 사냥터 몬스터를 쓰지 않는다 — 무리가 빽빽해서 "노린 놈"보다 가까운 놈이 먼저
## 맞는다(실제로 그랬다). 그건 판정이 맞는 것이지 버그가 아니므로, 여기서는
## 몬스터가 없는 마을에 시험용 한 마리만 놓고 본다.
func _fight() -> void:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	var mobs: Array = w.snapshot().monsters
	_eq("마을엔 몬스터가 없다", mobs.size(), 0)

	mobs.append({
		"id": "dummy", "kind": "mob003", "x": 1.5, "z": 0.0,
		"r": 0.38, "scale": 1.0, "color": "#888888", "boss": false,
		"level": 3, "max_hp": 100, "hp": 100, "defense": 3.0,
		"exp_reward": 25.0, "respawn_ms": 10000.0, "respawn_at": 0,
	})

	# 몬스터 쪽을 보고 친다 (dt 0 이라 제자리에서 방향만 바뀐다)
	w.input_move("me", 1, 1.0, 0.0, 0.0)
	w.attack("me")
	var hit := _first(w.drain_events(), "hit")
	if hit.is_empty():
		_fail_text("사거리 안 정면인데 안 맞았다")
		return

	# 기사 Lv1 공격 12, 들늑대 방어 3 -> 11. 치명타면 1.5배
	var want: int = 17 if hit.crit else 11
	_eq("피해량", hit.amount, want)
	_eq("체력이 그만큼 줄었다", mobs[0].hp, 100 - want)
	print("  들늑대 100 -> %d (%s)" % [mobs[0].hp, "치명타" if hit.crit else "보통"])

	# 쿨타임 안에 또 치면 아무 일도 없다
	w.attack("me")
	_eq("쿨타임 중에는 안 나간다", w.drain_events().size(), 0)

	# 등 뒤는 맞지 않는다
	mobs[0].hp = 100
	var w2 := World.new()
	w2.open("village")
	w2.join("you")
	var mobs2: Array = w2.snapshot().monsters
	mobs2.append(mobs[0].duplicate())
	w2.input_move("you", 1, -1.0, 0.0, 0.0)
	w2.attack("you")
	_eq("등 뒤는 안 맞는다", _first(w2.drain_events(), "hit").is_empty(), true)

	# 휘두르는 동안 발이 묶인다
	var held: float = me.x
	w.input_move("me", 50, 0.0, 1.0, 0.1)
	_eq("경직 중에는 못 움직인다", me.x, held)

	# 죽이면 경험치가 들어오고, 제 시간에 되살아난다
	var w3 := World.new()
	w3.open("village")
	w3.join("k")
	var mobs3: Array = w3.snapshot().monsters
	mobs3.append(mobs[0].duplicate())
	mobs3[0].hp = 1
	mobs3[0].respawn_ms = 0.0
	w3.input_move("k", 1, 1.0, 0.0, 0.0)
	w3.attack("k")
	var events := w3.drain_events()
	_eq("죽었다고 알린다", _first(events, "hit").get("killed", false), true)
	# 3레벨 몹을 1레벨이 잡으면 25 * (1 + 2*0.12) = 31
	_eq("경험치 보상", _first(events, "reward").get("exp", 0), 31)
	_eq("아직 레벨업은 아니다", w3.snapshot().players["k"].level, 1)

	w3.step(0.016)
	_eq("되살아난다", mobs3[0].hp, 100)


func _first(events: Array, type_name: String) -> Dictionary:
	for e in events:
		if e.get("type", "") == type_name:
			return e
	return {}


func _fail_text(text: String) -> void:
	print("  실패 " + text)
	_failed += 1
