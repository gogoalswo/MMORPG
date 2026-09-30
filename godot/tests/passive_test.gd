extends SceneTree

## 패시브 질풍각 (docs/features/passives.md) — **판정은 장부가 다시 본다.**
## 레벨마다 한 단계가 열리고 [습득] 한 번에 한 단계, 공속은 여기서만 온다.
## 2레벨마다 한 단계, Lv.200 · 100단계면 격투가 평타가 100ms = 초당 10번이다 (2026-09-30 요청, 처음엔 8번)
##
##   godot --headless --path godot --script tests/passive_test.gd

var _failed := 0


func _init() -> void:
	_case_learn()
	_case_speed()
	_case_gear()
	_case_save()
	_case_kill_check()
	_case_level_passives()
	_case_move_speed()
	Save.clear()
	if _failed == 0:
		print("패시브: 전부 통과")
		quit(0)
	else:
		print("패시브: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _me() -> Array:
	var w := World.new()
	w.open("village")
	w.join("me")
	return [w, w.snapshot().players["me"]]


func _rank(me: Dictionary) -> int:
	return int(me.get("passives", {}).get("gale_kicks", 0))


## 레벨이 안 되면 안 오르고, 되면 한 번에 한 단계, 끝 단계를 넘지 않는다
func _case_learn() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.level = 1
	w.learn_passive("me", "gale_kicks")
	if _rank(me) != 0:
		_fail("Lv.1 인데 1단계를 배웠다")
	me.level = 5
	w.learn_passive("me", "gale_kicks")
	w.learn_passive("me", "gale_kicks")
	w.learn_passive("me", "gale_kicks")
	if _rank(me) != 2:
		_fail("Lv.5 는 두 단계까지(2레벨마다 한 단계)인데 %d단계" % _rank(me))
	if Skills.passive_learnable("fighter", 5, me.passives):
		_fail("열린 단계를 다 배웠는데 레드닷 조건이 켜져 있다")
	if not Skills.passive_learnable("fighter", 6, me.passives):
		_fail("Lv.6 이면 3단계가 열려 레드닷 조건이 켜져야 한다")
	w.learn_passive("me", "없는패시브")
	me.level = 999
	for i in 120:
		w.learn_passive("me", "gale_kicks")
	var top := int(Skills.passive("gale_kicks").maxRank)
	if _rank(me) != top:
		_fail("끝 단계가 %d 인데 %d단계" % [top, _rank(me)])
	else:
		print("  배우기: Lv.1 막힘 · Lv.5 두 단계까지 · 끝 %d단계에서 멈춤" % top)


## 끝 단계(100)면 격투가 평타 간격 100ms (초당 10번) — `stats_of` 가 더한다
func _case_speed() -> void:
	var top := int(Skills.passive("gale_kicks").maxRank)
	var stats := World.stats_of("fighter", 200, {}, {"gale_kicks": top})
	var interval := Combat.effective_cooldown(stats.attackCooldown, stats.attackSpeed)
	if interval != 100:
		_fail("Lv.200 · %d단계 평타 간격이 100ms 가 아니다: %dms" % [top, interval])
	var bare := World.stats_of("fighter", 200, {})
	if float(bare.attackSpeed) != 0.0:
		_fail("패시브 없이 공속이 %s" % bare.attackSpeed)
	print("  공속: 0단계 %dms → %d단계 %dms (초당 %.1f번)" % [
		Combat.effective_cooldown(bare.attackCooldown, bare.attackSpeed), top, interval, 1000.0 / interval
	])


## 장비의 옛 공속 옵션은 무시한다 (2026-09-29 요청: "장비 옵션에 공속은 제거할꺼야")
func _case_gear() -> void:
	var ring := {"id": str(Items.all().keys()[0]), "options": [{"kind": "attackSpeed", "value": 20}]}
	if float(Items.stack_stats(ring).attackSpeed) != 0.0:
		_fail("옛 공속 옵션이 공속을 올렸다")
	if not Items.shown_options(ring.options).is_empty():
		_fail("옛 공속 옵션이 화면에 적힌다")
	if "attackSpeed" in GameData.load_table("items").get("optionKinds", []):
		_fail("공속이 아직 뽑히는 옵션 목록에 있다")


## 저장했다 불러와도 단계가 남는다
func _case_save() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.level = 50
	for i in 3:
		w.learn_passive("me", "gale_kicks")
	w.save("me")
	var again := World.new()
	again.open("village")
	again.restore("me")
	var back: Dictionary = again.snapshot().players["me"]
	if _rank(back) != 3 or float(back.stats.attackSpeed) <= 0.0:
		_fail("불러온 뒤 질풍각 %d단계 · 공속 %s" % [_rank(back), back.stats.attackSpeed])


## 서버의 처치 검증도 패시브를 본다 — 빼먹으면 빨라진 평타가 "너무 빨리 잡았다" 로 거부된다
func _case_kill_check() -> void:
	if not LedgerServer.OPS.has("learn_passive"):
		_fail("서버가 learn_passive 요청을 모른다")
	# 가장 높은 레벨 몬스터 — 약한 놈은 Lv.200 에게 0ms 라 차이가 안 보인다
	var kind := {}
	for id in GameData.load_table("monsters").kinds:
		var each: Dictionary = GameData.load_table("monsters").kinds[id]
		if kind.is_empty() or int(each.get("level", 0)) > int(kind.get("level", 0)):
			kind = each
	var ledger := Ledger.fresh("fighter")
	ledger.level = 200
	var slow := KillCheck.min_ms(ledger, kind)
	ledger.passives = {"gale_kicks": int(Skills.passive("gale_kicks").maxRank)}
	var fast := KillCheck.min_ms(ledger, kind)
	if fast >= slow:
		_fail("패시브를 배웠는데 최소 처치 시간이 그대로다: %.0f → %.0fms" % [slow, fast])


## 레벨 도달 패시브 (2026-09-30 요청) — 그 레벨에 한 번, 스탯은 `stats_of` 가 더한다
func _case_level_passives() -> void:
	var s := _me()
	var w: World = s[0]
	var me: Dictionary = s[1]
	me.level = 69
	w.learn_passive("me", "vital_strike")
	if int(me.passives.get("vital_strike", 0)) != 0:
		_fail("Lv.69 에 급소 강타(Lv.70)를 배웠다")
	me.level = 70
	w.learn_passive("me", "vital_strike")
	w.learn_passive("me", "vital_strike")
	if int(me.passives.get("vital_strike", 0)) != 1:
		_fail("Lv.70 급소 강타가 1 이 아니다: %s" % me.passives)
	# 계열 잇기 (2026-09-30 요청) — 필살각(Lv.150)은 급소 간파(Lv.50)를 배워야, 극의(Lv.200)는 급소 강타 뒤
	me.level = 200
	w.learn_passive("me", "deadly_kick")
	if int(me.passives.get("deadly_kick", 0)) != 0:
		_fail("급소 간파 없이 필살각을 배웠다")
	if Skills.passive_can_learn(Skills.passive("deadly_kick"), 200, {}):
		_fail("급소 간파 없이도 필살각을 배울 수 있다고 한다 (레드닷이 잘못 켜진다)")
	w.learn_passive("me", "keen_eye")
	w.learn_passive("me", "deadly_kick")
	w.learn_passive("me", "ultimate")
	if int(me.passives.get("deadly_kick", 0)) != 1 or int(me.passives.get("ultimate", 0)) != 1:
		_fail("앞 단계를 배웠는데 필살각·극의가 안 배워진다: %s" % me.passives)

	var all := {}
	for p in Skills.passives_for("fighter"):
		all[str(p.id)] = int(p.maxRank)
	var bare := World.stats_of("fighter", 200, {})
	var full := World.stats_of("fighter", 200, {}, all)
	# 철각 계열 10 · 40 · 80 · 120 = +10 · 20 · 40 · 80% → 합 +150% (2026-09-30)
	var want_attack := roundi(float(bare.attack) * 2.5)
	if int(full.attack) != want_attack:
		_fail("철각 계열 공격력 %d → %d (×2.5 = %d 여야)" % [bare.attack, full.attack, want_attack])
	# 치확 50 (+10%) · 150 (+20%, 2026-09-30 에 치피에서 바꿨다) · 치피 70 (+20%) · 200 (+50%)
	var checks := {"crit": 0.3, "critDamage": 0.7, "penetration": 0.1, "moveSpeed": 0.2}
	for key in checks:
		var gained := float(full.get(key, 0.0)) - float(bare.get(key, 0.0))
		if absf(gained - float(checks[key])) > 1e-6:
			_fail("%s 가 %.2f 올라야 하는데 %.2f" % [key, checks[key], gained])
	print("  레벨 패시브: 공격력 %d → %d · 치확 +%.0f%% · 치피 %.0f%% → %.0f%% · 관통 +%.0f%% · 이속 +%.0f%%" % [
		bare.attack, full.attack, full.crit * 100.0, bare.critDamage * 100.0, full.critDamage * 100.0,
		full.penetration * 100.0, full.moveSpeed * 100.0,
	])
	# 서버의 처치 검증도 같은 스탯을 본다 — 세졌으면 최소 처치 시간이 줄어야 한다
	var ledger := Ledger.fresh("fighter")
	ledger.level = 200
	var kind: Dictionary = GameData.load_table("monsters").kinds.values()[0]
	var slow := KillCheck.min_ms(ledger, kind)
	ledger.passives = all.duplicate()
	ledger.passives.erase("gale_kicks")
	if KillCheck.min_ms(ledger, kind) > slow:
		_fail("레벨 패시브를 배웠는데 최소 처치 시간이 늘었다")


## 경공(이속 +20%) — 같은 입력으로 1.2배 멀리 간다
func _case_move_speed() -> void:
	var gone := []
	for ranks in [{}, {"light_step": 1}]:
		var s := _me()
		var w: World = s[0]
		var me: Dictionary = s[1]
		me.level = 30
		me.passives = ranks
		w._refresh_stats(me)
		var x0 := float(me.x)
		var z0 := float(me.z)
		w.input_move("me", 1, 1.0, 0.0, 0.1)
		gone.append(Vector2(float(me.x) - x0, float(me.z) - z0).length())
	if absf(gone[1] / maxf(gone[0], 1e-6) - 1.2) > 0.01:
		_fail("경공이 이동 거리를 1.2배로 늘리지 않았다: %.3f → %.3f" % gone)
