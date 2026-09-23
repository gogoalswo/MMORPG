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


## 맨몸 능력치는 설계의 복리 곡선이다 — `base(L) × 직업 배수`.
## 격투가 배수가 전부 1.0 이라 Lv1 이 곧 설계의 바탕값(100/10/10)이다
func _stats() -> void:
	var k1 := Combat.stats_for("fighter", 1)
	_eq("격투가1 체력", k1.maxHp, 100)
	_eq("격투가1 공격", k1.attack, 10)
	_eq("격투가1 방어", k1.defense, 10)
	_eq("격투가1 사거리", k1.attackRange, 2.2)
	# 공격 간격은 설계의 직업 배수에서 온다 (격투가 0.9초)
	_eq("격투가1 간격", k1.attackCooldown, 900.0)

	# 레벨 1개는 언제나 +2% — 구간마다 다르면 "장비 비중" 의 기준이 사라진다
	var k10 := Combat.stats_for("fighter", 10)
	_eq("격투가10 체력", k10.maxHp, roundi(100.0 * pow(1.02, 9)))
	_eq("격투가10 공격", k10.attack, roundi(10.0 * pow(1.02, 9)))

	# 직업은 같은 바탕에 배수만 다르다 — 마법사는 공격 1.35 / HP 0.8 / 방어 0.75
	var m50 := Combat.stats_for("mage", 50)
	var b50 := Stats.base(50)
	_eq("마법사50 체력", m50.maxHp, roundi(b50["hp"] * 0.8))
	_eq("마법사50 공격", m50.attack, roundi(b50["atk"] * 1.35))
	_eq("마법사50 방어", m50.defense, roundi(b50["df"] * 0.75))
	# 치명타는 맨몸에 없다 — 치확은 목걸이, 공속은 반지 전담
	_eq("맨몸 치확", int(m50.crit * 100.0), 0)


func _damage() -> void:
	_eq("피해 12vs3", Combat.compute_damage(12, 3), 11)
	_eq("피해 100vs45", Combat.compute_damage(100, 45), 50)
	# 방어가 아무리 높아도 최소 1 은 들어간다 — 안 그러면 전투가 멈춘다
	_eq("피해 5vs500", Combat.compute_damage(5, 500), 1)


## 경험치는 설계의 성장 곡선 표(`balance.json` 의 expTable)를 읽는다 —
## 만렙까지 2,880시간(24시간 × 120일)에서 역산한 값이다
func _exp() -> void:
	var need1 := Combat.exp_to_next(1)
	if need1 <= 0:
		_fail_text("Lv1 필요 경험치가 0 이다 — expTable 을 못 읽었다")
	# 레벨이 오를수록 무거워진다
	for level in [10, 100, 199]:
		if Combat.exp_to_next(level) <= Combat.exp_to_next(level - 1):
			_fail_text("Lv%d 에서 요구량이 역전된다" % level)

	# 한 번에 여러 레벨이 오르고, 남는 만큼은 이월된다
	var grown := Combat.apply_exp(1, 0, need1 * 3)
	if grown.level < 2:
		_fail_text("세 배를 받았는데 레벨이 안 올랐다")
	var small := Combat.apply_exp(1, 0, need1 - 1)
	_eq("한 칸 모자라면 안 오름", small.level, 1)

	# 레벨 차이 보정을 걷었다 — 몬스터 HP 에 정비례하므로 그대로 들어온다
	_eq("보상 3레벨몹/1레벨", Combat.exp_reward(3, 1, 25), 25)
	_eq("보상 1레벨몹/10레벨", Combat.exp_reward(1, 10, 25), 25)
	_eq("보상 보스", Combat.exp_reward(9, 1, 67), 67)


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
	# **상한이 없다** (2026-09-23 지시). 0.9 면 0.8 굴림도 터져야 한다
	_eq("치명타 상한 없음", Combat.roll_crit(0.9, 0.8), true)
	_eq("치명타 100% 초과", Combat.roll_crit(1.5, 0.99), true)
	_eq("치명타 음수", Combat.roll_crit(-1.0, 0.0), false)


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

	mobs.append(World.make_monster(
		"dummy", GameData.monster_kind("mob003"), 1.5, 0.0, 10000.0, 0.0
	))
	var full := int(mobs[0].hp)

	# 몬스터 쪽을 보고 친다 (dt 0 이라 제자리에서 방향만 바뀐다)
	w.input_move("me", 1, 1.0, 0.0, 0.0)
	w.attack("me")
	var hit := _first(w.drain_events(), "hit")
	if hit.is_empty():
		_fail_text("사거리 안 정면인데 안 맞았다")
		return

	# 피해는 설계 공식이다 — 공격력 × K / (K + 방어력), K 는 공격자 레벨에서 역산.
	# 수치를 박아 두면 밸런스를 만질 때마다 여기서 걸리므로 같은 식으로 잰다
	var plain := roundi(Stats.damage(float(me.stats.attack), int(me.level), float(mobs[0].defense)))
	var want: int = roundi(plain * float(me.stats.critDamage)) if hit.crit else plain
	_eq("피해량", hit.amount, want)
	_eq("체력이 그만큼 줄었다", mobs[0].hp, full - want)
	print("  들늑대 %d -> %d (%s)" % [full, mobs[0].hp, "치명타" if hit.crit else "보통"])

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
	# 레벨 차이 보정을 걷었다 — 경험치는 몬스터 HP 에 정비례하므로 그대로 들어온다
	_eq("경험치 보상", _first(events, "reward").get("exp", 0), int(mobs3[0].exp_reward))
	# 화면이 쓰러진 자리에서 `+n EXP` 를 띄우려면 자리가 있어야 한다
	_eq("보상에 쓰러진 자리", _first(events, "reward").get("x", null), mobs3[0].x)
	_eq("아직 레벨업은 아니다", w3.snapshot().players["k"].level, 1)

	w3.step(0.016)
	_eq("되살아난다", mobs3[0].hp, int(mobs3[0].max_hp))


func _first(events: Array, type_name: String) -> Dictionary:
	for e in events:
		if e.get("type", "") == type_name:
			return e
	return {}


func _fail_text(text: String) -> void:
	print("  실패 " + text)
	_failed += 1
