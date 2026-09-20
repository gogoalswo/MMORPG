extends SceneTree

## 스킬 **시스템** — 배우기·액션바·시전·판정.
##
## **스킬 내용(34종)은 다시 만들기로 했다.** 그래서 여기서는 개별 스킬의 수치가
## 맞는지가 아니라, 표에 적힌 대로 판정이 도는지를 본다. 표가 바뀌면 이 테스트가
## 읽는 값도 같이 바뀐다.
##
##   godot --headless --path godot --script tests/skill_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_learn()
	_case_bar()
	_case_cast()
	_case_multi()
	_case_dead()
	Save.clear()

	if _failed == 0:
		print("스킬: 전부 통과")
		quit(0)
	else:
		print("스킬: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _first(events: Array, type_name: String) -> Dictionary:
	for e in events:
		if e.get("type", "") == type_name:
			return e
	return {}


## 마을(몬스터 0)에 시험용을 놓는다. 사냥터를 쓰면 다른 놈이 먼저 맞는다
func _setup(mob_count: int = 1) -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	var mobs: Array = w.snapshot().monsters
	for i in mob_count:
		var mob := World.make_monster(
			"dummy%d" % i, GameData.monster_kind("mob003"), 1.5 + i * 0.6, 0.0, 10000.0, 0.0
		)
		mobs.append(mob)
	# 몬스터 쪽을 본다
	w.input_move("me", 1, 1.0, 0.0, 0.0)
	return [w, me, mobs]


func _case_learn() -> void:
	var s := _setup()
	var w: World = s[0]
	var me: Dictionary = s[1]

	# 남의 직업 스킬은 못 배운다 — 스위치와 무관하다
	w.learn_skill("me", "fireball")
	if "fireball" in me.skills:
		_fail("마법사 스킬을 배웠다")

	# 없는 스킬도 마찬가지
	w.learn_skill("me", "없는스킬")
	if me.skills.size() != 0:
		_fail("없는 스킬이 들어갔다")

	w.drain_events()
	w.learn_skill("me", "rising_kick")
	if not ("rising_kick" in me.skills):
		_fail("내 직업 스킬을 못 배웠다")
	elif _first(w.drain_events(), "skills").is_empty():
		_fail("배웠다고 알려 주지 않았다")
	else:
		print("  배우기: %s (포인트 %d, 잠금해제 스위치 %s)" % [
			str(me.skills), me.skill_points, Skills.unlock_all()
		])


func _case_bar() -> void:
	var s := _setup()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var size := int(GameData.combat().get("skillBarSize", 4))

	# 안 배운 것은 안 올라간다
	w.set_skill_bar("me", ["rising_kick", "tiger_roar"])
	if me.skill_bar.size() != 0:
		_fail("안 배운 스킬이 액션바에 올라갔다")

	for id in Skills.for_job("fighter"):
		w.learn_skill("me", str(id))
	w.set_skill_bar("me", Skills.for_job("fighter"))
	if me.skill_bar.size() != size:
		_fail("액션바가 %d칸이어야 하는데 %d" % [size, me.skill_bar.size()])
	else:
		print("  액션바 %d칸: %s" % [size, str(me.skill_bar)])


func _case_cast() -> void:
	var s := _setup()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var mob: Dictionary = s[2][0]
	w.learn_skill("me", "rising_kick")
	w.set_skill_bar("me", ["rising_kick"])
	w.drain_events()

	w.cast("me", "rising_kick")
	var events := w.drain_events()
	var used := _first(events, "skill")
	var hit := _first(events, "hit")
	if used.is_empty():
		_fail("스킬을 못 썼다")
		return
	if int(used.root_ms) <= 0:
		_fail("경직이 0 이다 — 스킬도 같은 공격 동작을 쓴다")
	if hit.is_empty():
		_fail("사거리 안인데 안 맞았다")
		return

	# 스킬 피해도 설계 공식을 탄다 — 공격력 × 계수 × K / (K + 방어력).
	# 맨몸에는 치명타가 없으므로(설계: 치확·치피는 목걸이 전담) 치명타면 배수만 곱한다
	var power := float(Skills.get_skill("fighter", "rising_kick").get("power", 1.0))
	var plain := roundi(Stats.damage(float(me.stats.attack) * power, int(me.level), float(mob.defense)))
	var want: int = roundi(plain * float(me.stats.critDamage)) if hit.crit else plain
	if int(hit.amount) != want:
		_fail("피해가 %d 여야 하는데 %d" % [want, hit.amount])
	elif str(hit.get("skill", "")) != "rising_kick":
		_fail("어느 스킬이었는지 안 실려 왔다")
	else:
		print("  할퀴기: %d 피해 (경직 %dms)" % [hit.amount, used.root_ms])

	# 남의 직업 스킬은 써지지 않는다
	w.cast("me", "fireball")
	if not _first(w.drain_events(), "skill").is_empty():
		_fail("마법사 스킬이 나갔다")


func _case_multi() -> void:
	# 호포각 maxTargets 5, 전방위(arc 2PI) — 앞에 셋을 놓으면 셋 다 맞아야 한다
	var s := _setup(3)
	var w: World = s[0]
	w.learn_skill("me", "tiger_roar")
	w.set_skill_bar("me", ["tiger_roar"])
	w.drain_events()

	w.cast("me", "tiger_roar")
	var hits := 0
	for e in w.drain_events():
		if e.get("type", "") == "hit":
			hits += 1
	if hits != 3:
		_fail("호포각이 3마리를 쳐야 하는데 %d마리" % hits)
	else:
		print("  호포각: %d마리 동시" % hits)


## 자가 회복 스킬을 확인하던 `_case_heal` 은 **2026-09-17 에 뺐다** — 회복기를
## 가진 직업이 기사뿐이었고 기사를 지웠다. `selfHeal` 판정은 `World` 에 그대로
## 있으니, 회복 스킬을 다시 만들면 여기에 한 편 되살린다.
func _case_dead() -> void:
	var s := _setup()
	var w: World = s[0]
	var me: Dictionary = s[1]
	w.learn_skill("me", "rising_kick")
	w.set_skill_bar("me", ["rising_kick"])
	me["dead"] = true
	w.drain_events()
	w.cast("me", "rising_kick")
	if not w.drain_events().is_empty():
		_fail("죽었는데 스킬이 나갔다")
