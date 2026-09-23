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
	_case_combo()
	_case_range()
	_case_dead()
	_case_upgrade()
	_case_wide()
	_case_claw_up()
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


func _mob(mobs: Array, id: String) -> Dictionary:
	for m in mobs:
		if str(m.get("id", "")) == id:
			return m
	return {}


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
	w.set_skill_bar("me", ["rising_kick", "sky_breaker"])
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
	# 천붕각 maxTargets 10, 전방위(arc 2PI) — 앞에 셋을 놓으면 셋 다 맞아야 한다
	var s := _setup(3)
	var w: World = s[0]
	w.learn_skill("me", "sky_breaker")
	w.set_skill_bar("me", ["sky_breaker"])
	w.drain_events()

	w.cast("me", "sky_breaker")
	var hits := 0
	for e in w.drain_events():
		if e.get("type", "") == "hit":
			hits += 1
	if hits != 3:
		_fail("천붕각이 3마리를 쳐야 하는데 %d마리" % hits)
	else:
		print("  천붕각: %d마리 동시" % hits)


## **연타** — 할퀴기는 앞 120° 안의 놈들을 `hits` 번 때린다 (2026-09-23).
## 첫 대는 누르는 순간, 나머지는 `hitGap` 간격으로 `step` 이 넣는다.
## 시간을 기다리지 않고 `_run_combos` 에 앞선 시각을 줘서 본다
func _case_combo() -> void:
	var s := _setup(3)
	var w: World = s[0]
	var mobs: Array = s[2]
	# 옆(90°)에 하나 더 — 120° 부채꼴(반각 60°) 밖이라 안 맞아야 한다
	var side := World.make_monster("side", GameData.monster_kind("mob003"), 0.0, 1.5, 10000.0, 0.0)
	mobs.append(side)
	var kick := Skills.get_skill("fighter", "rising_kick")
	var times := int(kick.get("hits", 1))
	var gap := int(kick.get("hitGap", 0))
	w.learn_skill("me", "rising_kick")
	w.set_skill_bar("me", ["rising_kick"])
	w.drain_events()

	w.cast("me", "rising_kick")
	# 시작 시각은 **예약에서 읽는다** — 시전 전에 시계를 따로 읽으면 느린 CI 에서
	# `cast` 안의 시각과 1ms 어긋나 둘째 대가 아직 안 들어온 것으로 보였다 (2026-09-23)
	var start := int(w._combos[0].at) - gap if not w._combos.is_empty() else Time.get_ticks_msec()
	var first := _hits(w.drain_events())
	if first.size() != 3:
		_fail("첫 대에 %d마리가 맞았다 (앞의 셋이어야 한다)" % first.size())
		return
	if "side" in first:
		_fail("120° 밖(옆 90°)의 놈이 맞았다")

	# 둘째 대 — 아직 셋째 대 시각이 아니므로 셋만 더 들어온다
	w._run_combos(start + gap)
	var second := _hits(w.drain_events())
	if second.size() != 3:
		_fail("둘째 대가 %d번 들어왔다 (3번이어야 한다)" % second.size())

	# 도중에 죽으면 남은 대는 건너뛴다 — 부활한 놈을 때리면 안 된다
	mobs[0].hp = 0
	w._run_combos(start + gap * times + 1000)
	var rest := _hits(w.drain_events())
	var want := 2 * (times - 2)
	if rest.size() != want:
		_fail("남은 대가 %d번이다 (%d번이어야 한다 — 죽은 놈은 빠진다)" % [rest.size(), want])
	elif not w._combos.is_empty():
		_fail("다 넣었는데 예약이 %d개 남았다" % w._combos.size())
	else:
		print("  할퀴기: %d타 × 3마리, %dms 간격, 120° 밖·죽은 놈 제외" % [times, gap])


## 맞은 놈 id 들
func _hits(events: Array) -> Array:
	var ids: Array = []
	for e in events:
		if e.get("type", "") == "hit":
			ids.append(str(e.target))
	return ids


## 범위 표시(`skillRange`)가 **판정이 실제로 쓴 모양**을 싣고 오는지.
##
## 이 이벤트의 값어치는 전부 "판정과 같다"는 데 있다. 화면이 `skills.json` 을
## 다시 읽어 그리면 판정이 바뀔 때 조용히 갈라지므로, 여기서 세 가지 모양을
## 다 본다 → docs/features/skills.md "범위 표시"
func _case_range() -> void:
	var s := _setup(3)
	var w: World = s[0]
	var me: Dictionary = s[1]

	# 1) 근접 부채꼴 — 중심은 내 몸, 각은 스킬의 각 그대로
	w.learn_skill("me", "rising_kick")
	w.set_skill_bar("me", ["rising_kick"])
	w.drain_events()
	w.cast("me", "rising_kick")
	var shape := _first(w.drain_events(), "skillRange")
	var kick := Skills.get_skill("fighter", "rising_kick")
	if shape.is_empty():
		_fail("범위가 안 실려 왔다")
		return
	if not (is_equal_approx(shape.x, float(me.x)) and is_equal_approx(shape.z, float(me.z))):
		_fail("근접기 중심이 내 몸이 아니다 (%.1f, %.1f)" % [shape.x, shape.z])
	if not is_equal_approx(float(shape.reach), float(kick.range)):
		_fail("반경이 %.1f 여야 하는데 %.1f" % [float(kick.range), shape.reach])
	if not is_equal_approx(float(shape.arc), float(kick.arc)):
		_fail("각이 %.2f 여야 하는데 %.2f" % [float(kick.arc), shape.arc])
	else:
		print("  근접 부채꼴: 반경 %.1fm · %d°" % [shape.reach, roundi(rad_to_deg(shape.arc))])

	# 2) 전방위 근접 — 각이 한 바퀴면 부채꼴이 아니라 원이다
	w.learn_skill("me", "sky_breaker")
	w.set_skill_bar("me", ["sky_breaker"])
	w.drain_events()
	w.cast("me", "sky_breaker")
	var events := w.drain_events()
	var round_shape := _first(events, "skillRange")
	var hits := 0
	for e in events:
		if e.get("type", "") == "hit":
			hits += 1
	if not is_equal_approx(float(round_shape.arc), TAU):
		_fail("전방위기 각이 한 바퀴가 아니다 (%.2f)" % round_shape.arc)
	elif int(round_shape.hits) != hits:
		_fail("맞은 수가 %d 인데 %d 로 실려 왔다" % [hits, round_shape.hits])
	else:
		print("  전방위 원: 반경 %.1fm · %d/%d 마리" % [
			round_shape.reach, round_shape.hits, round_shape.max_targets
		])

	# **그려질 모양과 맞은 놈이 같은가** — 이 도구의 값어치가 전부 여기 있다.
	# 각을 반대로 재거나 좌우가 뒤집히면 "표시는 맞는데 안 맞는" 게 되고,
	# 그건 디버그 도구로서 없느니만 못하다. 좁은 부채꼴(낙뢰 108°)로 보되
	# **반경 안이지만 옆에 선 놈**을 하나 두어 양쪽을 다 건다
	# 정면(+x)에서 90도 꺾인 자리 — 반경 4m 안이지만 108도 부채꼴 밖이다
	var aside := World.make_monster(
		"aside", GameData.monster_kind("mob003"), 0.0, 2.0, 10000.0, 0.0
	)
	s[2].append(aside)
	w.learn_skill("me", "thunder_fall")
	w.set_skill_bar("me", ["thunder_fall"])
	w.drain_events()
	w.cast("me", "thunder_fall")
	var fan_events := w.drain_events()
	var fan := _first(fan_events, "skillRange")
	var struck: Array = []
	for e in fan_events:
		if e.get("type", "") == "hit":
			struck.append(str(e.target))
	if float(fan.arc) >= TAU:
		_fail("낙뢰는 좁은 부채꼴이어야 한다 (%.2f)" % fan.arc)
	for mob in s[2]:
		var dx: float = float(mob.x) - float(fan.x)
		var dz: float = float(mob.z) - float(fan.z)
		var gap := sqrt(dx * dx + dz * dz)
		var inside := gap <= float(fan.reach) + 1e-3
		if inside and gap > 1e-3:
			var dot := (dx / gap) * sin(float(fan.facing)) + (dz / gap) * cos(float(fan.facing))
			inside = acos(clampf(dot, -1.0, 1.0)) <= float(fan.arc) / 2.0 + 1e-3
		var was_hit := str(mob.id) in struck
		# 안에 있어도 `maxTargets` 에 걸려 안 맞을 수 있다 — 그 반대는 없어야 한다
		if was_hit and not inside:
			_fail("%s 는 그려질 모양 밖인데 맞았다 (%.2f m)" % [mob.id, gap])
	if not ("aside" in struck):
		print("  모양 밖(옆 2m)은 안 맞고, 맞은 놈은 전부 모양 안이다")
	else:
		_fail("부채꼴 옆에 선 놈이 맞았다 — 각을 재는 방향이 어긋났다")

	# 3) 원거리 — **착탄점이 중심**이고 반경은 사거리가 아니라 터지는 반경이다.
	#    사거리(12m)를 그대로 그리면 화면 전체가 범위가 된다
	me["job"] = "archer"
	w.learn_skill("me", "explosive_arrow")
	w.set_skill_bar("me", ["explosive_arrow"])
	w.drain_events()
	w.cast("me", "explosive_arrow")
	var far := _first(w.drain_events(), "skillRange")
	var arrow := Skills.get_skill("archer", "explosive_arrow")
	if far.is_empty():
		_fail("원거리 범위가 안 실려 왔다")
		return
	# 앞선 시전에 쓰러진 놈이 있을 수 있다 — **살아 있는 것 중 가장 가까운 놈**이
	# 겨눠진다 (`World.cast` 가 `_pick_targets` 로 하나만 고른다)
	var mob: Dictionary = {}
	var best := INF
	for m in s[2]:
		if int(m.hp) <= 0:
			continue
		var gap := Vector2(float(m.x), float(m.z)).length()
		if gap < best:
			best = gap
			mob = m
	if not (is_equal_approx(far.x, float(mob.x)) and is_equal_approx(far.z, float(mob.z))):
		_fail("착탄점이 겨눈 놈(%s) 자리가 아니다 (%.1f, %.1f)" % [mob.id, far.x, far.z])
	if not is_equal_approx(float(far.reach), Skills.blast_radius(arrow)):
		_fail("터지는 반경이 %.1f 여야 하는데 %.1f" % [Skills.blast_radius(arrow), far.reach])
	elif not is_equal_approx(float(far.arc), TAU):
		_fail("날아가 터진 것에 부채꼴은 없다 (%.2f)" % far.arc)
	else:
		print("  원거리 착탄: 사거리 %.0fm → 터지는 반경 %.1fm" % [float(arrow.range), far.reach])


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


## 스킬 강화 — 스킬창에서 고른 강화에 **경험치북을 넣어**(`feed_upgrade`) 필요
## 경험치(1000)에 닿으면 붙는다. 책이 없거나 이미 붙었으면 안 넣는다.
## 테스트 단추는 경험치북 없이 붙인다.
## 낙뢰에 "기절" 이 붙으면 맞은 놈이 3초 동안 **서서 못 때린다** (2026-09-23)
func _case_upgrade() -> void:
	var s := _setup()
	var w: World = s[0]
	var me: Dictionary = s[1]
	var mob: Dictionary = s[2][0]
	var books: Array = Skills.exp_books()
	if books.size() != 3:
		_fail("경험치북이 세 종류여야 하는데 %d" % books.size())
		return
	var small := str(books[0].id)
	w.feed_upgrade("me", "thunder_fall", 0, small)
	if not me.get("skill_upgrade_exp", {}).is_empty():
		_fail("경험치북 없이 경험치가 들어갔다 (%s)" % str(me.skill_upgrade_exp))
	w.debug_books("me")
	for i in 3:
		w.feed_upgrade("me", "thunder_fall", 0, small)
	w.feed_upgrade("me", "thunder_fall", 0, str(books[1].id))
	var got := int(me.skill_upgrade_exp.get("thunder_fall", {}).get("stun", 0))
	if got != 800 or not me.skill_upgrades.is_empty():
		_fail("하급 셋 + 중급 하나면 800 이고 아직 안 붙어야 한다 (%d · %s)" % [got, me.skill_upgrades])
	w.feed_upgrade("me", "thunder_fall", 0, str(books[2].id))
	if me.skill_upgrades.get("thunder_fall", []) != ["stun"] or me.skill_upgrade_exp.has("thunder_fall"):
		_fail("1000 을 넘겼는데 안 붙었거나 경험치가 남았다 (%s · %s)" % [me.skill_upgrades, me.skill_upgrade_exp])
	var small_left := 0
	for stack in me.bag:
		if str(stack.id) == small:
			small_left = int(stack.count)
	w.feed_upgrade("me", "thunder_fall", 0, small)
	w.feed_upgrade("me", "thunder_fall", 5, small)
	for stack in me.bag:
		if str(stack.id) == small and int(stack.count) != small_left:
			_fail("이미 붙은 강화(또는 없는 번호)에 경험치북이 쓰였다")
	# 테스트 단추 — 책 없이 모든 스킬의 1번이 붙고, 초기화하면 다 떨어진다
	w.debug_reset_upgrades("me")
	w.feed_upgrade("me", "thunder_fall", 0, small)
	w.debug_upgrade_all("me", 0)
	if me.skill_upgrades.get("thunder_fall", []) != ["stun"] or me.skill_upgrade_exp.has("thunder_fall"):
		_fail("'전체 1번 강화' 가 기절을 안 붙였거나 쌓인 경험치가 남았다 (%s)" % str(me.skill_upgrades))

	# 기절 — 한 방에 안 죽게 체력을 올려 둔다
	mob.max_hp = 999999
	mob.hp = 999999
	w.learn_skill("me", "thunder_fall")
	w.set_skill_bar("me", ["thunder_fall"])
	w.drain_events()
	var now := Time.get_ticks_msec()
	w.cast("me", "thunder_fall")
	var cast_event := _first(w.drain_events(), "skill")
	if cast_event.get("upgrades", []) != ["stun"]:
		_fail("시전 이벤트에 강화가 안 실렸다 (%s)" % str(cast_event))
	var left := int(mob.get("stunned_until", 0)) - now
	if left < 2900 or left > 3200:
		_fail("기절이 3초가 아니다 (%dms)" % left)
	var hp := int(me.hp)
	var spot := Vector2(mob.x, mob.z)
	me.x = 6.0  # 멀어져도 쫓아오지 않아야 한다
	for i in 20:
		w.step(0.05)
	if str(mob.state) != "stun" or int(me.hp) != hp or Vector2(mob.x, mob.z).distance_to(spot) > 1e-3:
		_fail("기절한 놈이 움직이거나 때렸다 (%s · 체력 %d→%d)" % [mob.state, hp, me.hp])
	mob.stunned_until = 0
	w.step(0.05)
	if str(mob.state) == "stun":
		_fail("기절이 풀렸는데 그대로 서 있다")
	else:
		print("  낙뢰 기절: %dms 동안 제자리 · 풀리면 다시 %s" % [left, mob.state])

	# 떼면 기절도 없다
	me.x = 0.0
	w.debug_reset_upgrades("me")
	w.drain_events()
	w.cast("me", "thunder_fall")
	if not _first(w.drain_events(), "skill").get("upgrades", []).is_empty() \
			or int(mob.stunned_until) != 0:
		_fail("강화를 뗐는데 기절이 걸렸다")


## 낙뢰 "범위" — 사거리 4 → 6m. 5m 앞의 놈은 강화 전에는 안 맞고 강화 뒤에는 맞는다.
## 판정이 알리는 모양(`skillRange`)도 6m 여야 표시와 판정이 안 갈린다 (2026-09-23)
func _case_wide() -> void:
	var s := _setup(0)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var far := World.make_monster("far", GameData.monster_kind("mob003"), 5.0, 0.0, 10000.0, 0.0)
	far.max_hp = 999999
	far.hp = 999999
	s[2].append(far)
	w.learn_skill("me", "thunder_fall")
	w.set_skill_bar("me", ["thunder_fall"])
	for wide in [false, true]:
		if wide:
			w.debug_upgrade_all("me", 1)
		me.skill_ready_at = {}
		me.rot = PI / 2.0
		w.drain_events()
		w.cast("me", "thunder_fall")
		var events := w.drain_events()
		var shape := _first(events, "skillRange")
		var hit := not _first(events, "hit").is_empty()
		var want := 6.0 if wide else 4.0
		if absf(float(shape.get("reach", 0.0)) - want) > 1e-3 or hit != wide:
			_fail("범위 %s: 반경 %.1f · 5m 앞이 %s (반경 %.1f · %s 여야 한다)" % [
				wide, float(shape.get("reach", 0.0)), hit, want, wide])
	print("  낙뢰 범위: 4m → 6m, 5m 앞의 놈이 강화 뒤에만 맞는다")


## 할퀴기 강화 — "부채꼴" 은 판정 각 120 → 160°, "연타" 는 3 → 5타 (2026-09-23).
## 둘은 따로 논다. 각은 판정이 알리는 모양(`skillRange`)으로, 대 수는 예약으로 본다
func _case_claw_up() -> void:
	var s := _setup(1)
	var w: World = s[0]
	var me: Dictionary = s[1]
	var mob: Dictionary = s[2][0]
	mob.max_hp = 999999
	mob.hp = 999999
	w.learn_skill("me", "rising_kick")
	w.set_skill_bar("me", ["rising_kick"])
	for c in [[[], 120.0, 3], [["wide"], 160.0, 3], [["combo"], 120.0, 5], [["wide", "combo"], 160.0, 5]]:
		me.skill_upgrades = {"rising_kick": c[0].duplicate()}
		me.skill_ready_at = {}
		w._combos.clear()
		w.drain_events()
		w.cast("me", "rising_kick")
		var shape := _first(w.drain_events(), "skillRange")
		var arc := rad_to_deg(float(shape.get("arc", 0.0)))
		var hits := 1 + w._combos.size()
		if absf(arc - float(c[1])) > 0.5 or hits != int(c[2]):
			_fail("할퀴기 %s: %.0f° · %d타 (%.0f° · %d타 여야 한다)" % [str(c[0]), arc, hits, c[1], c[2]])
	w._combos.clear()
	me.skill_upgrades = {}
	print("  할퀴기 강화: 기본 120°·3타, 부채꼴 160°, 연타 5타, 둘 다 160°·5타")
