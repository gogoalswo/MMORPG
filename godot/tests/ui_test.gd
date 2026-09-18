extends SceneTree

## 한글이 실제로 그려지는지, 차원문 화면과 체력바가 도는지 본다.
##
## 스크린샷을 찍지 않는다 — 폰트에 글리프가 있는지는 글로 확인할 수 있다.
##
##   godot --headless --path godot --script tests/ui_test.gd

const FONT := "res://assets/fonts/NotoSansKR-subset.ttf"

var _failed := 0


func _init() -> void:
	# 남아 있는 저장이 있으면 엉뚱한 존에서 시작한다 (LocalTransport 가 이어서 연다)
	Save.clear()
	_case_font()
	_run_scene.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _case_font() -> void:
	if not ResourceLoader.exists(FONT):
		_fail("폰트가 없다 — npm run sync:godot 을 돌렸나")
		return
	var font: Font = load(FONT)

	# 게임에 나오는 글자가 전부 들어 있어야 한다. 없으면 네모로 나온다
	var sample := "마을 초원 레벨 체력 경험치 몬스터 어디로 갈까요 되살아나기 들늑대 처치 치명타"
	var missing := ""
	for ch in sample:
		if ch == " ":
			continue
		if not font.has_char(ch.unicode_at(0)):
			missing += ch
	if missing != "":
		_fail("폰트에 없는 글자: %s" % missing)
	else:
		print("  폰트: %s 글자 확인 (%d자)" % ["한글", sample.length()])

	# 존 21곳과 몬스터 60종 이름도 전부 나와야 한다
	var names := ""
	for id in GameData.zones().get("zones", {}):
		names += str(GameData.zone(str(id)).get("name", ""))
	for id in GameData.load_table("monsters").get("kinds", {}):
		names += str(GameData.monster_kind(str(id)).get("name", ""))
	var bad := ""
	for ch in names:
		if ch != " " and not font.has_char(ch.unicode_at(0)):
			bad += ch
	if bad != "":
		_fail("존·몬스터 이름에 없는 글자: %s" % bad)
	else:
		print("  존 21곳·몬스터 60종 이름 전부 그려진다")


func _run_scene() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	# 화면 글자가 한국어인가
	if not game._label.text.begins_with("마을"):
		_fail("존 이름이 한국어가 아니다: %s" % game._label.text.left(20))

	# 빌드 표시가 화면에 있어야 한다. 이게 없으면 캐시한 이전 빌드를 보고 있는지
	# 알 방법이 없다 (2026-09-17)
	if not game._label.text.contains("빌드 "):
		_fail("빌드 표시가 화면에 없다")

	# 체력바가 스탯을 따라간다
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	if game._hp_bar.max_value != float(me.stats.maxHp):
		_fail("체력바 최대치가 %d 이어야 하는데 %d" % [me.stats.maxHp, game._hp_bar.max_value])
	me.hp = 70
	await process_frame
	if game._hp_bar.value != 70:
		_fail("체력바가 안 따라온다 (%d)" % game._hp_bar.value)

	# 차원문에 서면 고르는 화면이 뜬다
	if game._gate_panel.visible:
		_fail("아직 문에 안 섰는데 화면이 떠 있다")
	me.x = 9.0
	me.z = 0.0
	for i in 3:
		await process_frame
	if not game._gate_panel.visible:
		_fail("차원문에 섰는데 고르는 화면이 안 떴다")
	else:
		# 마을 + 사냥터 20곳 = 21개 단추
		var grid: GridContainer = game._gate_panel.get_child(0).get_child(1)
		print("  차원문 화면: 단추 %d개, 첫 줄 '%s'" % [
			grid.get_child_count(), grid.get_child(0).text
		])
		if grid.get_child_count() != 21:
			_fail("단추가 21개여야 하는데 %d개" % grid.get_child_count())

	# 골라서 옮긴다
	game._on_gate_pick("meadow")
	for i in 5:
		await process_frame
	if game._shown_zone != "meadow":
		_fail("골랐는데 화면이 %s 그대로다" % game._shown_zone)
	elif game._gate_panel.visible:
		_fail("옮겼는데 고르는 화면이 안 닫혔다")
	else:
		print("  골라서 이동: %s" % game._label.text.split("\n")[0].strip_edges())

	# 자동 사냥 단추 — 누르면 켜지고 글자가 바뀐다. 실제로 사냥하는지는
	# tests/auto_hunt_test.gd 가 본다 (여기는 단추와 화면만)
	me = game._transport.snapshot().players[game._transport.my_id()]
	game._auto_button.pressed.emit()
	await process_frame
	if not bool(me.get("auto", false)):
		_fail("자동사냥 단추를 눌렀는데 안 켜졌다")
	elif not game._auto_button.text.contains("켜짐"):
		_fail("켜졌는데 단추 글자가 '%s'" % game._auto_button.text)
	elif not game._marker.visible:
		_fail("켜졌는데 사냥 자리 표시가 없다")
	else:
		print("  자동사냥 켜짐 — 앵커 (%.1f, %.1f)" % [me.auto_x, me.auto_z])

	game._auto_button.pressed.emit()
	await process_frame
	if bool(me.get("auto", false)):
		_fail("다시 눌렀는데 안 꺼졌다")
	if game._auto_button.text.contains("켜짐"):
		_fail("껐는데 단추 글자가 '%s'" % game._auto_button.text)

	if _failed == 0:
		print("UI: 전부 통과")
		quit(0)
	else:
		print("UI: %d개 실패" % _failed)
		quit(1)
