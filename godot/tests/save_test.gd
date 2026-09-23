extends SceneTree

## user:// 저장이 실제로 남고 다시 읽히는지 본다.
##
## **끝나면 지운다.** 안 지우면 다음 테스트가 저장에서 이어서 시작해 버려
## 엉뚱한 존에서 검사하게 된다.
##
##   godot --headless --path godot --script tests/save_test.gd

var _failed := 0


func _init() -> void:
	Save.clear()
	_case_round_trip()
	_case_missing()
	_case_restore_zone()
	_case_dead()
	Save.clear()

	if _failed == 0:
		print("저장: 전부 통과")
		quit(0)
	else:
		print("저장: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _case_round_trip() -> void:
	var w := World.new()
	w.open("meadow")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.x = 12.5
	me.z = -3.25
	me.level = 7
	me.exp = 123
	me.hp = 88
	me.gold = 4500
	me.skill_upgrades = {"thunder_fall": ["stun", "stun", "gone"], "gone_skill": ["stun"]}
	# 붙기 전 경험치 — 이미 붙은 것·없는 강화의 것은 버린다
	me.skill_upgrade_exp = {"thunder_fall": {"stun": 300, "gone": 50}, "gone_skill": {"stun": 1}}
	w.save("me")
	# 강화는 **지금 표에 있는 것만** 되살아난다 — 겹친 것·없는 것은 버린다
	var back := World.new()
	back.open("meadow")
	back.join("me")
	back.restore("me")
	var restored: Dictionary = back.snapshot().players["me"].skill_upgrades
	if restored != {"thunder_fall": ["stun"]}:
		_fail("스킬 강화가 %s 로 돌아왔다" % str(restored))
	var restored_exp: Dictionary = back.snapshot().players["me"].skill_upgrade_exp
	if not restored_exp.is_empty():
		_fail("이미 붙은·없는 강화의 경험치가 %s 로 살아났다" % str(restored_exp))
	me.skill_upgrades = {}
	me.skill_upgrade_exp = {"thunder_fall": {"stun": 300}}
	w.save("me")
	back.restore("me")
	if back.snapshot().players["me"].skill_upgrade_exp != {"thunder_fall": {"stun": 300}}:
		_fail("쌓인 경험치 300 이 안 돌아왔다 (%s)" % str(back.snapshot().players["me"].skill_upgrade_exp))

	var saved := Save.read()
	if saved.is_empty():
		_fail("저장이 안 남았다")
		return
	# JSON 은 정수를 실수로 돌려준다. 읽는 쪽(restore)이 int() 로 받으므로 여기서도 그렇게 본다
	if str(saved.get("zone")) != "meadow":
		_fail("존이 meadow 여야 하는데 %s" % saved.get("zone"))
	for pair in [["level", 7], ["exp", 123], ["hp", 88], ["gold", 4500]]:
		if int(saved.get(pair[0], -1)) != int(pair[1]):
			_fail("%s 가 %s 여야 하는데 %s" % [pair[0], pair[1], saved.get(pair[0])])
	if absf(float(saved.x) - 12.5) > 1e-9 or absf(float(saved.z) + 3.25) > 1e-9:
		_fail("자리가 다르다 (%.2f, %.2f)" % [saved.x, saved.z])
	else:
		print("  저장: %s (%.1f, %.1f) %d레벨 골드 %d" % [saved.zone, saved.x, saved.z, saved.level, saved.gold])


func _case_missing() -> void:
	Save.clear()
	if not Save.read().is_empty():
		_fail("지웠는데 뭔가 읽혔다")
	var w := World.new()
	w.open("village")
	w.join("me")
	if w.restore("me"):
		_fail("저장이 없는데 되살렸다고 한다")


func _case_restore_zone() -> void:
	# 초원에서 저장하고, 마을에서 시작한 새 World 가 초원으로 돌아가야 한다
	var first := World.new()
	first.open("meadow")
	first.join("me")
	var me: Dictionary = first.snapshot().players["me"]
	me.x = -5.0
	me.z = 8.0
	me.level = 4
	me.exp = 30
	me.gold = 900
	me.hp = 50
	first.save("me")

	var second := World.new()
	second.open("village")
	second.join("me")
	if not second.restore("me"):
		_fail("저장이 있는데 못 되살렸다")
		return
	var back: Dictionary = second.snapshot().players["me"]
	if second.zone_id != "meadow":
		_fail("존이 meadow 여야 하는데 %s" % second.zone_id)
	if back.level != 4 or back.exp != 30 or back.gold != 900 or back.hp != 50:
		_fail("값이 안 맞다 (%d레벨 %d경험치 %d골드 %d체력)" % [back.level, back.exp, back.gold, back.hp])
	if absf(back.x + 5.0) > 1e-9 or absf(back.z - 8.0) > 1e-9:
		_fail("자리가 안 맞다 (%.2f, %.2f)" % [back.x, back.z])
	# 레벨에 맞는 스탯으로 다시 만들어져야 한다
	if back.stats.maxHp != Combat.stats_for("fighter", 4).maxHp:
		_fail("스탯이 레벨 4 것이 아니다")
	else:
		print("  되살림: %s (%.1f, %.1f) %d레벨 체력 %d/%d" % [
			second.zone_id, back.x, back.z, back.level, back.hp, back.stats.maxHp
		])
	# 몬스터는 저장하지 않는다 — 다시 들어오면 새로 난다
	if second.snapshot().monsters.size() != 201:
		_fail("되살린 존에 몬스터가 안 났다")


func _case_dead() -> void:
	# 죽은 채로 저장됐으면 자리는 스폰으로 — 시체 자리에서 시작할 이유가 없다
	var w := World.new()
	w.open("meadow")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]
	me.x = 20.0
	me.z = 20.0
	me["dead"] = true
	w.save("me")

	var again := World.new()
	again.open("meadow")
	again.join("me")
	again.restore("me")
	var back: Dictionary = again.snapshot().players["me"]
	if not bool(back.dead):
		_fail("죽은 상태가 안 남았다")
	if absf(back.x - 20.0) < 1e-9:
		_fail("시체 자리에서 시작했다")
