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
		# 마을 + 사냥터 20곳 = 21줄. 맨 위(마을)가 지금 서 있는 곳이라 막혀 있다
		var panel: GatePanel = game._gate_panel
		print("  차원문 화면: %d줄, 첫 줄 '%s'" % [panel.row_count(), panel.row(0).text])
		if panel.row_count() != 21:
			_fail("줄이 21개여야 하는데 %d개" % panel.row_count())
		elif not panel.row(0).disabled or panel.row(1).disabled:
			_fail("서 있는 곳(마을)만 막혀야 한다")
		elif panel.row(0).icon == panel.row(1).icon:
			_fail("서 있는 곳과 갈 곳의 칸 아이콘이 같다")
		elif panel.texture == null:
			_fail("창 바탕 조각(panel.png)이 없다 — npm run sync:godot 을 돌렸나")
		# 앵커로만 자리를 잡는다 — 화면 가운데에 있어야 한다
		var mid := panel.get_global_rect().get_center().x
		if absf(mid - game.get_viewport().get_visible_rect().size.x * 0.5) > 2.0:
			_fail("창이 가운데가 아니다 (%.0f)" % mid)

	# 목록은 **끌어서도** 내려간다 (휠 말고) — 2026-09-18 요청
	var panel2: GatePanel = game._gate_panel
	var list: ScrollContainer = panel2._scroll
	# 목록 기준 좌표다. 가운데를 눌러 위로 끈다
	var grab := list.size * 0.5
	panel2._on_list_input(_mouse(grab, true))
	for i in 6:
		grab.y -= 20
		panel2._on_list_input(_move(grab))
		await process_frame
	var dragged := list.scroll_vertical
	panel2._on_list_input(_mouse(grab, false))
	if dragged <= 0:
		_fail("목록을 끌었는데 안 내려갔다 (스크롤 %d)" % dragged)
	elif not panel2.visible:
		_fail("끌기만 했는데 창이 닫혔다 — 끌다가 고른 것으로 친다")
	else:
		print("  목록 끌기: %dpx 내려감" % dragged)

	# 끌지 않고 그 자리에서 떼면 그 줄을 고른 것이다
	list.scroll_vertical = 0
	await process_frame
	var row1 := panel2.row(1).get_global_rect().get_center() - list.global_position
	panel2._on_list_input(_mouse(row1, true))
	panel2._on_list_input(_mouse(row1, false))
	if panel2.visible:
		_fail("줄을 눌렀다 뗐는데 안 골라졌다")

	# 문 아치를 누르면 창이 열린다 — **멀리 서 있어도 바로** 열린다
	# (2026-09-18 요청: "포탈까지 안 걸어가도 클릭하면 UI 열리게")
	game._gate_panel.close_panel()
	me.x = 30.0
	me.z = 30.0
	for i in 3:
		await process_frame
	# 누르는 곳은 **소용돌이 원판뿐**이다 (2026-09-18: "지금 너무 넓어").
	# 소용돌이는 문 반지름 2.6 기준 높이 2.44, 반지름 1.14 짜리 판이다
	var swirl := Vector3(9.0, 2.6 * 2.0 * PortalSwirl.CENTER, 0.0)
	var on_swirl: Vector2 = game._camera.unproject_position(swirl)
	if not game._gate_tapped(on_swirl):
		_fail("소용돌이를 눌렀는데 문으로 안 잡힌다 (%s)" % on_swirl)
	else:
		game._on_gate_tapped()
		if not game._gate_panel.visible:
			_fail("문에서 멀리 서서 눌렀는데 창이 안 떴다")
		elif game._marker.visible:
			_fail("문을 눌렀는데 창 대신 걸어가는 표시가 떴다")
	# 아치 돌기둥 꼭대기와 받침은 이제 문이 아니다
	if game._gate_tapped(game._camera.unproject_position(Vector3(9.0, 4.8, 0.0))):
		_fail("아치 꼭대기가 아직 문으로 잡힌다 — 판이 너무 넓다")
	if game._gate_tapped(game._camera.unproject_position(Vector3(9.0, 0.1, 0.0))):
		_fail("문 발치(받침)가 아직 문으로 잡힌다")
	if game._gate_tapped(game._camera.unproject_position(Vector3(-9.0, 0.0, 0.0))):
		_fail("문에서 먼 땅이 문으로 잡힌다")
	if ResourceLoader.exists(Portal.MODEL):
		print("  차원문 모델: 있음, 소용돌이를 누르면 창")
	else:
		_fail("차원문 모델이 없다 — npm run sync:godot 을 돌렸나")

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

	# 판정이 발을 옮기는 동안에도 **달리기 동작**이 나와야 한다. 입력(_move)만
	# 세면 자동 사냥은 대기 자세로 미끄러진다 (2026-09-18 에 지적받았다)
	var mobs: Array = game._transport.snapshot().monsters
	mobs.append(World.make_monster(
		"uitest", GameData.monster_kind("mob003"), me.x + 6.0, me.z, 10000.0, 0.0
	))
	var ran := false
	for i in 30:
		await process_frame
		if game._moving:
			ran = true
			break
	if not ran:
		_fail("자동 사냥으로 움직이는데 달리기 동작이 안 나온다 (_moving 이 false)")
	else:
		print("  자동 사냥으로 걷는 동안 달리기 동작이 나온다")

	# 켜 둔 채로 땅을 누르면 **조작이 이긴다** — 화면이 탭을 삼키면 안 된다
	# (판정 쪽은 tests/auto_hunt_test.gd 의 _case_manual_wins 가 본다)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(200, 200)
	game._unhandled_input(press)
	if game._target == Vector3.INF:
		_fail("자동사냥 중에 땅을 눌렀는데 화면이 무시했다")
	var was := Vector2(me.x, me.z)
	for i in 30:
		await process_frame
	if Vector2(me.x, me.z).distance_to(was) < 0.3:
		_fail("자동사냥 중에 눌렀는데 그쪽으로 안 걸었다")
	else:
		print("  켜 둔 채로 누른 자리로 걸어간다 (%.2f m)" % Vector2(me.x, me.z).distance_to(was))

	game._auto_button.pressed.emit()
	await process_frame
	if bool(me.get("auto", false)):
		_fail("다시 눌렀는데 안 꺼졌다")
	if game._auto_button.text.contains("켜짐"):
		_fail("껐는데 단추 글자가 '%s'" % game._auto_button.text)

	await _case_bag(game)

	if _failed == 0:
		print("UI: 전부 통과")
		quit(0)
	else:
		print("UI: %d개 실패" % _failed)
		quit(1)


## 가방·장비 창 — 열리나, 칸이 제대로 깔리나, 골라서 낄 수 있나.
## 스크린샷을 찍지 않는다: 칸 수와 칸 안의 글자·그림은 노드로 읽을 수 있다
func _case_bag(game: Node3D) -> void:
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]

	if game._bag_panel.visible:
		_fail("아직 안 눌렀는데 가방이 떠 있다")
	game._toggle_bag()
	await process_frame
	if not game._bag_panel.visible:
		_fail("가방 단추를 눌렀는데 창이 안 떴다")
		return

	# 장비 8칸 · 가방 최소 25칸
	var slots: Array = Items.slots()
	if game._bag_gear.get_child_count() != slots.size():
		_fail("장비가 %d칸이어야 하는데 %d칸" % [slots.size(), game._bag_gear.get_child_count()])
	if game._bag_grid.get_child_count() < 25:
		_fail("가방 격자가 25칸 이상이어야 하는데 %d칸" % game._bag_grid.get_child_count())
	if game._bag_grid.columns != 5:
		_fail("가방 격자가 5열이어야 하는데 %d열" % game._bag_grid.columns)

	# 그림이 붙었나. 아이콘이 없으면(sync 를 안 돌렸으면) 칸 이름이 글자로 나와야 한다
	var drawn := 0
	var named := 0
	for index in game._bag_gear.get_child_count():
		var cell: PanelContainer = game._bag_gear.get_child(index)
		if cell.get_node("icon").texture != null:
			drawn += 1
		elif cell.get_node("text").text != "":
			named += 1
	if drawn + named != slots.size():
		_fail("장비 칸 %d개가 그림도 글자도 없다" % [slots.size() - drawn - named])
	else:
		print("  가방 창: 장비 %d칸(그림 %d · 글자 %d), 가방 %d칸" % [
			slots.size(), drawn, named, game._bag_grid.get_child_count()
		])

	# 머리 줄과 요약 줄
	if not game._bag_head.text.contains("/%d" % Items.bag_size()):
		_fail("머리 줄이 '%s'" % game._bag_head.text)
	if not game._bag_sum.text.contains("치명타"):
		_fail("요약 줄에 치명타가 없다: '%s'" % game._bag_sum.text)

	# 아무것도 안 골랐으면 상세 칸은 안내만, 단추는 꺼져 있어야 한다
	if not game._bag_action.disabled:
		_fail("아무것도 안 골랐는데 끼기 단추가 켜져 있다")

	# 가방에 하나 넣고 — 골라서 낀다
	me.bag.append({"id": "w_fighter_00", "grade": 3, "enhance": 2, "options": []})
	game._redraw_bag()
	await process_frame
	var first: PanelContainer = game._bag_grid.get_child(0)
	if first.get_node("badge").text == "":
		_fail("가방 첫 칸에 배지가 안 붙었다")
	elif not first.get_node("badge").text.contains("+2"):
		_fail("강화 배지가 '+2' 여야 하는데 '%s'" % first.get_node("badge").text)

	first.get_node("hit").pressed.emit()
	await process_frame
	if game._bag_action.disabled:
		_fail("칸을 골랐는데 끼기 단추가 안 켜졌다")
	if game._bag_action.text != "끼기":
		_fail("가방 칸을 골랐는데 단추가 '%s'" % game._bag_action.text)
	if not game._bag_detail.text.contains("등급"):
		_fail("상세 칸이 '%s'" % game._bag_detail.text.left(30))

	game._on_bag_action()
	for i in 3:
		await process_frame
	if me.equipped.get("weapon", {}).is_empty():
		_fail("끼기를 눌렀는데 무기가 안 끼워졌다")
	else:
		var worn: Dictionary = Items.get_item(str(me.equipped.weapon.id))
		print("  골라서 끼기: 무기 칸에 '%s'" % worn.get("name", "?"))

	# 창이 화면 안에 들어오나. **눈으로 볼 수 없는 것은 재서 본다** —
	# 칸을 키우다 720 을 넘기면 폰에서 아래가 잘린다
	var panel: Vector2 = game._bag_panel.size
	if panel.x > 1280.0 or panel.y > 720.0:
		_fail("가방 창이 화면(1280x720)보다 크다: %.0fx%.0f" % [panel.x, panel.y])
	else:
		print("  창 크기 %.0fx%.0f — 화면 안에 들어온다" % [panel.x, panel.y])

	# 끼운 칸을 골라 벗긴다
	var slot_index := slots.find("weapon")
	game._bag_gear.get_child(slot_index).get_node("hit").pressed.emit()
	await process_frame
	if game._bag_action.text != "벗기":
		_fail("장비 칸을 골랐는데 단추가 '%s'" % game._bag_action.text)
	game._on_bag_action()
	for i in 3:
		await process_frame
	if not me.equipped.get("weapon", {}).is_empty():
		_fail("벗기를 눌렀는데 무기가 그대로다")
	else:
		print("  골라서 벗기: 무기 칸이 비었다")

	game._toggle_bag()
	await process_frame
	if game._bag_panel.visible:
		_fail("다시 눌렀는데 가방이 안 닫혔다")

## 목록을 눌렀다/뗐다. 자리는 **목록 기준**이다 (Control 의 gui_input 이 그렇다)
func _mouse(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	return event


## 누른 채로 움직였다
func _move(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event
