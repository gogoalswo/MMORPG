extends SceneTree

## 물약 판정 — 저절로 마시기 · 쿨타임 10초 · 직접 마시기 · 기준(HP %) 자르기 · 저장.
## 화면(물약 칸·설정 창)은 `ui_test.gd` 의 `_case_potion` 이 본다.
##
##   godot --headless --path godot --script tests/potion_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_auto()
	_case_manual()
	_case_pct()
	_case_save()
	Save.clear()

	if _failed == 0:
		print("물약: 전부 통과")
		quit(0)
	else:
		print("물약: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _world() -> World:
	var w := World.new()
	w.open("meadow")
	w.join("me")
	# 몬스터가 끼어들어 HP 를 깎지 않게 치운다
	w.snapshot().monsters.clear()
	w.drain_events()
	return w


func _potions(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == "potion")


## HP 가 기준(처음 50%) 이하로 떨어지면 한 틱 안에 마신다. 쿨타임 동안은 또 안 마신다
func _case_auto() -> void:
	var w := _world()
	var me: Dictionary = w.snapshot().players["me"]
	var max_hp := int(me.stats.maxHp)
	var rules := GameData.combat()
	if int(me.potion_pct) != int(rules.get("potionAutoDefault", -1)):
		_fail("처음 기준이 %d%% 다" % int(me.potion_pct))

	# 기준 위에서는 안 마신다
	me.hp = max_hp * 6 / 10
	w.step(0.016)
	if not _potions(w.drain_events()).is_empty():
		_fail("HP 60% 인데 마셨다")

	me.hp = max_hp * 4 / 10
	var before := int(me.hp)
	var now := Time.get_ticks_msec()
	w.step(0.016)
	var drank := _potions(w.drain_events())
	var heal := roundi(max_hp * float(rules.get("potionHealRatio", 0)))
	if drank.size() != 1 or not bool(drank[0].get("auto", false)):
		_fail("HP 40% 인데 저절로 안 마셨다 (%s)" % str(drank))
	if int(me.hp) != mini(max_hp, before + heal):
		_fail("회복이 %d → %d 다 (최대 %d 의 %d 를 채워야 한다)" % [before, int(me.hp), max_hp, heal])
	var cool := int(me.potion_ready_at) - now
	if absi(cool - int(rules.get("potionCooldownMs", 0))) > 50 or int(rules.get("potionCooldownMs", 0)) != 10000:
		_fail("쿨타임이 %dms 다 (10초여야 한다)" % cool)

	# 쿨타임 중에는 또 떨어져도 안 마신다
	me.hp = max_hp / 10
	w.step(0.016)
	if not _potions(w.drain_events()).is_empty():
		_fail("쿨타임 중인데 또 마셨다")

	# 쿨타임이 끝나면 다시 마신다 (시각을 앞당겨 본다)
	me.potion_ready_at = 0
	w.step(0.016)
	if _potions(w.drain_events()).size() != 1:
		_fail("쿨타임이 끝났는데 안 마셨다")

	# 죽은 채로는 안 마신다
	me.potion_ready_at = 0
	me.hp = 0
	me.dead = true
	w.step(0.016)
	if not _potions(w.drain_events()).is_empty():
		_fail("죽었는데 마셨다")
	print("  저절로: HP 40%% 에서 %d → %d, 쿨타임 %.1f초" % [before, mini(max_hp, before + heal), cool / 1000.0])


## 칸을 누르면(`potion` 요청) 기준과 상관없이 마신다. 가득 차 있으면 쿨타임을 안 쓴다
func _case_manual() -> void:
	var w := _world()
	var me: Dictionary = w.snapshot().players["me"]
	var max_hp := int(me.stats.maxHp)
	w.set_potion_pct("me", 0)

	# 가득 찬 채 누르면 안 마시고 쿨타임도 안 쓴다
	me.hp = max_hp
	w.drink_potion("me")
	if int(me.potion_ready_at) != 0 or not _potions(w.drain_events()).is_empty():
		_fail("HP 가 가득한데 마셨다")

	# 자동이 꺼져 있으면 틱은 안 마신다
	me.hp = max_hp / 5
	w.step(0.016)
	if not _potions(w.drain_events()).is_empty():
		_fail("자동을 껐는데 저절로 마셨다")

	var before := int(me.hp)
	w.drink_potion("me")
	var drank := _potions(w.drain_events())
	if drank.size() != 1 or bool(drank[0].get("auto", true)) or int(me.hp) <= before:
		_fail("눌렀는데 안 마셨다 (%s, HP %d → %d)" % [str(drank), before, int(me.hp)])

	# 쿨타임 중 누르면 안내만 한다
	var after := int(me.hp)
	w.drink_potion("me")
	var events := w.drain_events()
	if int(me.hp) != after or not _potions(events).is_empty():
		_fail("쿨타임 중에 눌렀는데 마셨다")
	var told := events.any(func(e: Dictionary) -> bool: return str(e.get("text", "")).begins_with("물약 쿨타임"))
	if not told:
		_fail("쿨타임 중에 눌렀는데 안내가 없다")
	print("  직접: HP %d → %d, 쿨타임 중 누르면 안내" % [before, after])


## 기준은 10% 폭으로 0 ~ 90 에 잘린다
func _case_pct() -> void:
	var w := _world()
	var me: Dictionary = w.snapshot().players["me"]
	for pair in [[95, 90], [-5, 0], [34, 30], [70, 70]]:
		w.set_potion_pct("me", int(pair[0]))
		if int(me.potion_pct) != int(pair[1]):
			_fail("기준 %d 을 주니 %d 이 됐다 (%d 이어야 한다)" % [pair[0], int(me.potion_pct), pair[1]])


## 기준은 저장에 남는다. 옛 저장(칸 없음)은 처음 값으로 읽힌다
func _case_save() -> void:
	var w := _world()
	w.set_potion_pct("me", 70)
	w.save("me")
	var back := _world()
	back.restore("me")
	if int(back.snapshot().players["me"].potion_pct) != 70:
		_fail("저장한 기준 70 이 %d 로 돌아왔다" % int(back.snapshot().players["me"].potion_pct))
	Save.clear()
