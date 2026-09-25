extends SceneTree

## 한글이 실제로 그려지는지, 차원문 화면과 체력바가 도는지 본다.
##
## 스크린샷을 찍지 않는다 — 폰트에 글리프가 있는지는 글로 확인할 수 있다.
##
##   godot --headless --path godot --script tests/ui_test.gd

const FONT := "res://assets/fonts/NotoSansKR-subset.ttf"
## 가방을 끈 뒤에 누를 칸 — 넷째 줄 셋째 칸. 끈 만큼(두 줄 남짓) 올라와도 보인다
const BAG_TAP_CELL := 17

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
		print("  존 %d곳·몬스터 60종 이름 전부 그려진다" % GameData.zones().get("zones", {}).size())


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
	me.x = 4.0
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
		elif not (panel.get_theme_stylebox("panel") is StyleBoxTexture):
			_fail("창 바탕이 조각(ui_panel)이 아니다 — npm run sync:godot 을 돌렸나")
		elif not (panel.row(1).get_theme_stylebox("normal") is StyleBoxTexture):
			_fail("줄 틀이 조각(ui_button)이 아니다 — 다른 창과 결이 달라진다")
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

	# 끌지 않고 그 자리에서 떼면 그 줄을 고른 것이다.
	# **줄 오른쪽 끝**을 누른다 — 아이콘이 아니라 줄 전체가 누르는 자리여야 한다
	# (2026-09-20 요청: "해당 라인을 전체 클릭 영역으로 잡어")
	list.scroll_vertical = 0
	await process_frame
	var box := panel2.row(1).get_global_rect()
	var far := Vector2(list.size.x - 8.0, box.get_center().y - list.global_position.y)
	panel2._on_list_input(_mouse(far, true))
	# 누르고 있는 동안은 **눌린 틀**이다
	if panel2._held != panel2.row(1):
		_fail("줄을 눌렀는데 눌린 표시가 안 난다")
	panel2._on_list_input(_mouse(far, false))
	if panel2._held != null:
		_fail("뗐는데 눌린 표시가 남아 있다")
	if panel2.visible:
		_fail("줄 오른쪽 끝을 눌렀다 뗐는데 안 골라졌다")
	else:
		print("  줄 오른쪽 끝(%.0fpx)으로 고르기, 누름 표시 붙었다 떨어진다" % far.x)

	# 문 아치를 누르면 창이 열린다 — **멀리 서 있어도 바로** 열린다
	# (2026-09-18 요청: "포탈까지 안 걸어가도 클릭하면 UI 열리게")
	game._gate_panel.close_panel()
	me.x = 25.0
	me.z = 25.0
	for i in 3:
		await process_frame
	# 누르는 곳은 **소용돌이 원판뿐**이다 (2026-09-18: "지금 너무 넓어").
	# 소용돌이는 문 반지름 2.6 기준 높이 2.44, 반지름 1.14 짜리 판이다
	var swirl := Vector3(4.0, 2.6 * 2.0 * PortalSwirl.CENTER, 0.0)
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
	if game._gate_tapped(game._camera.unproject_position(Vector3(4.0, 4.8, 0.0))):
		_fail("아치 꼭대기가 아직 문으로 잡힌다 — 판이 너무 넓다")
	if game._gate_tapped(game._camera.unproject_position(Vector3(4.0, 0.1, 0.0))):
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
	game._auto_cell.find_child("hit", true, false).pressed.emit()
	await process_frame
	if not bool(me.get("auto", false)):
		_fail("자동사냥 칸을 눌렀는데 안 켜졌다")
	elif not game._auto_spin.visible:
		_fail("켜졌는데 화살표 고리가 안 보인다")
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
	# 누를 자리는 **빈 땅**이라야 한다. 맵을 2/3 로 줄인 뒤로(2026-09-23) 도착 지점
	# 둘레까지 무리가 와 있어서, 화면 한 점을 박아 두면 몬스터를 누르게 된다
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(200, 200)
	for i in 16:
		var angle := TAU * float(i) / 16.0
		var spot := Vector3(me.x + cos(angle) * 3.0, 0.0, me.z + sin(angle) * 3.0)
		var screen: Vector2 = game._camera.unproject_position(spot)
		var ground: Vector3 = game._ground_point(screen)
		if ground != Vector3.INF and game._mob_at(ground) == "" \
				and game._npc_at(ground) == "" and not game._gate_tapped(screen):
			press.position = screen
			break
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

	# 켜져 있는 동안 고리가 돈다 — 각이 그대로면 멈춘 그림이다
	var spun: float = game._auto_spin.rotation
	for i in 5:
		await process_frame
	if is_equal_approx(game._auto_spin.rotation, spun):
		_fail("자동사냥을 켰는데 화살표가 안 돈다 (각 %.2f 그대로)" % spun)
	else:
		print("  자동사냥 고리가 돈다 (%.2f → %.2f)" % [spun, game._auto_spin.rotation])

	game._auto_cell.find_child("hit", true, false).pressed.emit()
	await process_frame
	if bool(me.get("auto", false)):
		_fail("다시 눌렀는데 안 꺼졌다")
	if game._auto_spin.visible:
		_fail("껐는데 화살표 고리가 남아 있다")

	await _case_status(game)
	await _case_bag(game)
	await _case_char(game)
	await _case_bag_drag(game)
	await _case_compare(game)
	await _case_skills(game)
	await _case_design_panel(game)
	# 존을 옮기므로 맨 끝에 둔다
	await _case_dungeon(game)

	if _failed == 0:
		print("UI: 전부 통과")
		quit(0)
	else:
		print("UI: %d개 실패" % _failed)
		quit(1)


## 퀵슬롯 위 묶음과 오른쪽 위 메뉴 — 자리, 숫자, 누르면 창이 열리나.
## 2026-09-20 요청으로 레벨·경험치·체력이 왼쪽 위에서 **퀵슬롯 위**로 내려왔다.
## 화면 밖으로 나가거나 서로 겹치는 것은 수치로 잡힌다 — 찍어서 볼 것은 결뿐이다
func _case_status(game: Node3D) -> void:
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	var screen := Vector2(1280, 720)

	# 레벨·체력·경험치가 스냅샷을 그대로 보여 준다. 레벨은 `Lv.N`(2026-09-20 요청),
	# 경험치는 막대가 아니라 퍼센트다
	if game._level_label.text != "Lv.%d" % int(me.level):
		_fail("레벨 글자가 '%s' (스냅샷은 %d)" % [game._level_label.text, me.level])
	if game._hp_text.text != "%d / %d" % [int(me.hp), int(me.stats.maxHp)]:
		_fail("체력 글자가 '%s' (스냅샷은 %d/%d)" % [game._hp_text.text, me.hp, me.stats.maxHp])
	if not game._exp_text.text.begins_with("경험치 ") or not game._exp_text.text.ends_with("%"):
		_fail("경험치가 퍼센트가 아니다: '%s'" % game._exp_text.text)

	# 경험치 게이지는 **화면 맨 아래를 가로지른다** (2026-09-20 요청)
	var need := maxi(1, Combat.exp_to_next(int(me.level)))
	var gauge: Rect2 = game._exp_bar.get_global_rect()
	if gauge.size.x < screen.x - 1.0 or absf(gauge.end.y - screen.y) > 1.0:
		_fail("경험치 게이지가 화면 맨 아래 가로 전체가 아니다: %s" % gauge)
	if game._exp_bar.max_value != float(need):
		_fail("경험치 게이지 최대치가 %d 이어야 하는데 %d" % [need, game._exp_bar.max_value])

	# 막대가 줄어든다 — 반쯤 깎아 보고 채움 폭이 아니라 값으로 본다
	me.hp = int(me.stats.maxHp) / 2
	await process_frame
	if game._hp_bar.value != float(me.hp):
		_fail("체력을 깎았는데 막대가 %d" % game._hp_bar.value)

	# 퀵슬롯 바로 위에, 퀵슬롯과 같은 길이로 깔린다.
	# **테두리(부모) 기준이다** — 채움은 안쪽 여백만큼 좁다
	var hp_frame: Control = game._hp_bar.get_parent()
	var hp_rect: Rect2 = hp_frame.get_global_rect()
	var quick: Rect2 = game._bar_buttons[0].get_global_rect()
	var badge: Rect2 = game._level_label.get_global_rect()
	if hp_rect.end.y > quick.position.y + 1.0 or quick.position.y - hp_rect.end.y > 24.0:
		_fail("체력 막대가 퀵슬롯 바로 위가 아니다: 막대 %s · 퀵슬롯 %s" % [hp_rect, quick])
	if absf(hp_rect.get_center().x - screen.x / 2.0) > 2.0:
		_fail("체력 막대가 화면 가운데가 아니다: %s" % hp_rect)
	if absf(hp_rect.size.x - float(game._auto_cell.get_global_rect().end.x - quick.position.x)) > 6.0:
		_fail("체력 막대가 퀵슬롯 줄과 길이가 다르다 (%.0f)" % hp_rect.size.x)
	if badge.end.y > hp_rect.position.y or badge.position.y < 0.0:
		_fail("레벨 배지가 막대 위에 안 올라갔다: %s" % badge)
	# 퍼센트 글자는 **맨 아래 띠 가운데**에 얹힌다 (2026-09-20 요청)
	var exp_rect: Rect2 = game._exp_text.get_global_rect()
	if not gauge.grow(1.0).encloses(exp_rect):
		_fail("경험치 글자가 띠 안에 없다: 글자 %s · 띠 %s" % [exp_rect, gauge])
	elif absf(exp_rect.get_center().x - gauge.get_center().x) > 2.0:
		_fail("경험치 글자가 띠 가운데가 아니다: %s" % exp_rect)

	# 오른쪽 위 메뉴 — 화면 안, 묶음과 안 겹침.
	# 스킬·가방·던전·설계(디버그) 넷이다 — 설계 재현 창은 문서 9장 5번의 디버그 수단이다
	# 정보 · 스킬 · 강화 · 크리스탈 · 가방 · 던전 · 설계 (강화·크리스탈은 2026-09-24 에 가방 왼쪽에,
	# 정보는 2026-09-25 에 맨 앞에 더했다)
	if game._menu_cells.size() != 7:
		_fail("오른쪽 위 단추가 7개여야 하는데 %d개" % game._menu_cells.size())
		return
	var skill_rect: Rect2 = game._menu_cells[1].get_global_rect()
	var bag_rect: Rect2 = game._menu_cells[4].get_global_rect()
	if bag_rect.end.x > screen.x or skill_rect.position.y < 0.0 or bag_rect.position.y > 120.0:
		_fail("메뉴 단추가 오른쪽 위에 안 붙었다: %s / %s" % [skill_rect, bag_rect])
	if skill_rect.intersects(hp_rect) or skill_rect.intersects(badge):
		_fail("메뉴 단추가 퀵슬롯 위 묶음과 겹친다")

	# 눌러서 창이 열린다
	game._menu_cells[1].find_child("hit", true, false).pressed.emit()
	await process_frame
	if not game._skill_panel.visible:
		_fail("오른쪽 위 스킬 단추를 눌렀는데 스킬창이 안 열렸다")
	game._toggle_skills()
	game._menu_cells[4].find_child("hit", true, false).pressed.emit()
	await process_frame
	if not game._bag_panel.visible:
		_fail("오른쪽 위 가방 단추를 눌렀는데 가방이 안 열렸다")
	game._toggle_bag()
	await process_frame
	# 크리스탈 — 가방 **바로 왼쪽**. 누르면 인벤토리·장비 창과 크리스탈 창이 같이 뜨고,
	# 장비 칸을 누르면 대상이 된다. 다시 누르면 셋 다 닫힌다
	var cry_rect: Rect2 = game._menu_cells[3].get_global_rect()
	if absf(bag_rect.position.x - cry_rect.end.x) > 12.0 or absf(cry_rect.position.y - bag_rect.position.y) > 1.0:
		_fail("크리스탈 단추가 가방 옆이 아니다: 크리스탈 %s · 가방 %s" % [cry_rect, bag_rect])
	if game._menu_cells[3].find_children("*", "TextureRect", true, false).is_empty():
		_fail("크리스탈 단추에 그림이 없다 — npm run sync:godot 을 돌렸나 (crystal)")
	game._menu_cells[3].find_child("hit", true, false).pressed.emit()
	await process_frame
	if not (game._crystal_panel.visible and game._bag_panel.visible and game._gear_panel.visible) or game._detail_panel.visible:
		_fail("크리스탈 단추 — 크리스탈 %s · 가방 %s · 장비 %s · 상세 %s" % [game._crystal_panel.visible, game._bag_panel.visible, game._gear_panel.visible, game._detail_panel.visible])
	else:
		print("  가방 옆 크리스탈: %s" % game._crystal_hint.text)
	game._menu_cells[3].find_child("hit", true, false).pressed.emit()
	await process_frame
	if game._crystal_panel.visible or game._bag_panel.visible or game._gear_panel.visible:
		_fail("크리스탈 단추를 다시 눌렀는데 창이 안 닫혔다")
	# 강화 — 크리스탈 **바로 왼쪽**. 누르면 강화 팝업이 대상 없이 **다중 강화 · 전체** 목록으로 뜬다
	var enh_rect: Rect2 = game._menu_cells[2].get_global_rect()
	if absf(cry_rect.position.x - enh_rect.end.x) > 12.0 or absf(enh_rect.position.y - cry_rect.position.y) > 1.0:
		_fail("강화 단추가 크리스탈 옆이 아니다: 강화 %s · 크리스탈 %s" % [enh_rect, cry_rect])
	game._menu_cells[2].find_child("hit", true, false).pressed.emit()
	await process_frame
	var pop: EnhancePopup = game._enhance
	if not pop.visible or pop.mode != "multi" or pop.filter != "all" or not pop.list_panel.visible:
		_fail("가방 옆 강화 단추 — 보임 %s · 탭 %s · 목록 %s · 목록 창 %s" % [pop.visible, pop.mode, pop.filter, pop.list_panel.visible])
	else:
		print("  가방 옆 강화: 다중 강화 · 전체 목록 %d칸" % pop._list_view.size())
	game._menu_cells[2].find_child("hit", true, false).pressed.emit()
	await process_frame
	if pop.visible:
		_fail("강화 단추를 다시 눌렀는데 팝업이 안 닫혔다")
	print("  퀵슬롯 위: %s · %s · 체력 %s (막대 %.0fpx · 게이지 %.0fpx)" % [game._level_label.text, game._exp_text.text, game._hp_text.text, hp_rect.size.x, gauge.size.x])


## 던전 — 가방 옆 단추 → 종류 셋 → 단계 목록 → 들어가면 보스 한 마리 (docs/features/dungeons.md)
func _case_dungeon(game: Node3D) -> void:
	var panel: DungeonPanel = game._dungeon_panel
	var bag_rect: Rect2 = game._menu_cells[4].get_global_rect()
	var cell_rect: Rect2 = game._menu_cells[5].get_global_rect()
	# 가방 **바로 옆**이다 (2026-09-23 요청)
	if absf(cell_rect.position.x - bag_rect.end.x) > 12.0 or absf(cell_rect.position.y - bag_rect.position.y) > 1.0:
		_fail("던전 단추가 가방 옆이 아니다: 가방 %s · 던전 %s" % [bag_rect, cell_rect])
	# 글자가 아니라 그림(ui_icon_dungeon)이 나와야 한다
	if game._menu_cells[5].find_children("*", "TextureRect", true, false).is_empty():
		_fail("던전 단추에 그림이 없다 — npm run sync:godot 을 돌렸나 (ui_icon_dungeon)")
	game._menu_cells[5].find_child("hit", true, false).pressed.emit()
	await process_frame
	if not panel.visible:
		_fail("던전 단추를 눌렀는데 창이 안 떴다")
		return
	# 종류 셋 = 세로로 긴 카드 셋을 나란히 (2026-09-23 요청 그림) — 첫째(토벌)만 열려 있다
	var font: Font = load(FONT)
	var seen := ""
	await process_frame
	if panel.card_count() != 3 or panel._scroll.visible:
		_fail("던전 종류가 카드 3장이어야 하는데 %d장 (목록 보임 %s)" % [panel.card_count(), panel._scroll.visible])
		return
	if panel.card(0).disabled or not panel.card(1).disabled or not panel.card(2).disabled:
		_fail("토벌만 열리고 나머지 둘은 막혀야 한다")
	for i in 3:
		var box: Rect2 = panel.card(i).get_global_rect()
		if box.size.y < box.size.x * 1.4:
			_fail("카드 %d 가 세로로 길지 않다: %s" % [i, box.size])
		if i > 0 and absf(box.position.y - panel.card(0).get_global_rect().position.y) > 1.0:
			_fail("카드가 한 줄로 나란하지 않다")
		var art: TextureRect = panel.card(i).find_child("Art", true, false)
		if art == null or art.texture == null or not art.texture.resource_path.contains("dungeon_"):
			_fail("카드 %d 에 제 그림(dungeon_*)이 없다 — npm run sync:godot 을 돌렸나" % i)
		for label in panel.card(i).find_children("*", "Label", true, false):
			seen += label.text
	print("  던전 카드: %s 창 %s" % [panel.card(0).size, panel.size])
	if panel.get_global_rect().end.x > panel.get_viewport_rect().size.x:
		_fail("카드 창이 화면 밖으로 넘친다: %s" % panel.get_global_rect())
	# 막힌 카드는 눌러도 아무 일이 없다
	await _tap_card(panel, 1)
	if panel.card_count() != 3 or panel._scroll.visible:
		_fail("준비 중인 종류를 눌렀는데 화면이 바뀌었다")
	# 토벌을 누르면 단계 목록 — "뒤로" + 20단계
	await _tap_card(panel, 0)
	if panel.row_count() != 21:
		_fail("토벌 던전 단계 목록이 21줄(뒤로 + 20)이어야 하는데 %d줄" % panel.row_count())
		return
	seen += panel._title.text + panel.row(0).text + panel.row(20).text
	print("  던전 창: 종류 3 → '%s' %d줄, 첫 단계 '%s'" % [panel._title.text, panel.row_count(), panel.row(1).text])
	# 한 줄에 들어가야 한다 — 넘치면 줄이 창을 밀어 넓힌다
	if panel.size.x > DungeonPanel.DUNGEON_WIDTH + 1.0:
		_fail("단계 줄이 창 폭을 넘겨 창이 %.0fpx 로 넓어졌다" % panel.size.x)
	await _tap_row(panel, 0)
	if not panel._cards.visible or panel.card_count() != 3:
		_fail("뒤로를 눌렀는데 종류 카드로 안 돌아갔다")
	var missing := ""
	for ch in seen:
		if ch != " " and not font.has_char(ch.unicode_at(0)):
			missing += ch
	if missing != "":
		_fail("던전 창 글자가 폰트에 없다: %s" % missing)
	# 1단계로 들어간다 — 보스 한 마리뿐이다
	await _tap_card(panel, 0)
	await _tap_row(panel, 1)
	if panel.visible:
		_fail("단계를 골랐는데 창이 안 닫혔다")
	for i in 3:
		await process_frame
	var snap: Dictionary = game._transport.snapshot()
	var monsters: Array = snap.get("monsters", [])
	if str(snap.get("zone", "")) != "raid_01":
		_fail("1단계를 골랐는데 존이 %s" % snap.get("zone", ""))
	elif monsters.size() != 1 or not bool(GameData.monster_kind(str(monsters[0].get("kind", ""))).get("boss", false)):
		_fail("던전 안에 보스 한 마리만 있어야 하는데 %d마리" % monsters.size())
	else:
		print("  던전 1단계: 보스 %s 한 마리" % GameData.monster_kind(str(monsters[0].kind)).get("name", ""))


## 던전 종류 카드 i 를 누른다 — 막힌 카드는 고도 단추처럼 아무 일도 없다
func _tap_card(panel: DungeonPanel, i: int) -> void:
	var card := panel.card(i)
	if not card.disabled:
		card.pressed.emit()
	await process_frame
	await process_frame


## 목록의 i 번째 줄 가운데를 눌렀다 뗀다 (끌지 않는다)
func _tap_row(panel: GatePanel, i: int) -> void:
	var list: ScrollContainer = panel._scroll
	var box := panel.row(i).get_global_rect()
	var at := Vector2(list.size.x * 0.5, box.get_center().y - list.global_position.y)
	panel._on_list_input(_mouse(at, true))
	panel._on_list_input(_mouse(at, false))
	await process_frame


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

	# 장착 6칸(3열) · 가방 5열 세 줄
	var slots: Array = Items.slots()
	if slots.size() != 6:
		_fail("슬롯이 6종이어야 하는데 %d종: %s" % [slots.size(), str(slots)])
	var gear: Array = game._gear_cells
	if gear.size() != slots.size():
		_fail("장착이 %d칸이어야 하는데 %d칸" % [slots.size(), gear.size()])
	if game._bag_grid.get_child_count() < 15:
		_fail("가방 격자가 15칸 이상이어야 하는데 %d칸" % game._bag_grid.get_child_count())
	if game._bag_grid.columns != 5:
		_fail("가방 격자가 5열이어야 하는데 %d열" % game._bag_grid.columns)

	# **왼쪽이 장착, 오른쪽이 가방이다** (2026-09-18 요청)
	var gear_x: float = gear[0].get_global_rect().position.x
	var grid_x: float = game._bag_grid.get_global_rect().position.x
	if gear_x >= grid_x:
		_fail("장착(%.0f)이 가방(%.0f) 왼쪽에 있어야 한다" % [gear_x, grid_x])
	else:
		print("  좌우: 장착 x=%.0f · 가방 x=%.0f" % [gear_x, grid_x])

	# 테두리가 붙었나 — 그림이 없으면 코드로 그린 것이라도 있어야 한다
	if game._bag_panel.get_theme_stylebox("panel") == null:
		_fail("창에 테두리가 없다")
	if gear[0].get_theme_stylebox("panel") == null:
		_fail("칸에 테두리가 없다")

	# 그림이 붙었나. 아이콘이 없으면(sync 를 안 돌렸으면) 칸 이름이 글자로 나와야 한다
	var drawn := 0
	var named := 0
	for index in gear.size():
		var cell: PanelContainer = gear[index]
		if cell.get_node("icon").texture != null:
			drawn += 1
		elif cell.get_node("text").text != "":
			named += 1
	if drawn + named != slots.size():
		_fail("장착 칸 %d개가 그림도 글자도 없다" % [slots.size() - drawn - named])
	else:
		print("  가방 창: 장착 %d칸(그림 %d · 글자 %d), 가방 %d칸" % [
			slots.size(), drawn, named, game._bag_grid.get_child_count()
		])

	# 칸 수·레벨·스탯 상자
	if not game._bag_head.text.contains("/%d" % Items.bag_size()):
		_fail("가방 칸 수가 '%s'" % game._bag_head.text)
	if not game._bag_level.text.begins_with("LV."):
		_fail("이름표가 'LV.' 로 시작해야 하는데 '%s'" % game._bag_level.text)
	var stat_names: Array = game.STAT_NAMES
	var stat_labels: Array = game._stat_labels
	if stat_labels.size() != stat_names.size():
		_fail("스탯이 %d개여야 하는데 %d개" % [stat_names.size(), stat_labels.size()])
	else:
		var wrote := ""
		for index in stat_labels.size():
			var want := str(stat_names[index])
			if not str(stat_labels[index].text).begins_with(want):
				_fail("%d번째 스탯이 '%s' 여야 하는데 '%s'" % [index, want, stat_labels[index].text])
			wrote += stat_labels[index].text + "  "
		print("  스탯 상자: %s" % wrote.strip_edges())

	# 탭 — 네 개, 고른 것만 바뀐다 (재료 탭은 제작과 함께 없앴다)
	var tabs: Array = game._tab_buttons
	if tabs.size() != 4:
		_fail("탭이 4개여야 하는데 %d개" % tabs.size())
	elif game._bag_tab != 0:
		_fail("처음에는 '전체' 가 골라져 있어야 한다 (%d)" % game._bag_tab)

	# 아무것도 안 골랐으면 상세 창은 닫혀 있고, 단추는 꺼져 있어야 한다
	if not game._bag_action.disabled:
		_fail("아무것도 안 골랐는데 끼기 단추가 켜져 있다")
	if game._detail_panel.visible:
		_fail("아무것도 안 골랐는데 상세 창이 떠 있다")
	if not game._gear_panel.visible:
		_fail("가방을 열었는데 장비 창이 같이 안 떴다")

	# 처음 들어오면 크리스탈 30개가 한 번 들어와 있다 (2026-09-23 요청 "가방에 30개 넣어")
	var gift: Array = me.bag.filter(func(s: Dictionary) -> bool: return str(s.id) == Items.crystal_id())
	if gift.size() != 1 or int(gift[0].count) != 30:
		_fail("처음 가방에 크리스탈 30개가 없다: %s" % str(gift))
	me.bag.clear()

	# 가방에 하나 넣고 — 골라서 낀다
	me.bag.append({"id": "g1_w", "grade": 1, "enhance": 2, "options": []})
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
	if game._bag_action.text != "장착":
		_fail("가방 칸을 골랐는데 단추가 '%s'" % game._bag_action.text)
	if not game._detail_panel.visible:
		_fail("칸을 눌렀는데 상세 창이 안 떴다")
	if game._detail_grade.text != Items.grade_name(1):
		_fail("상세 창 등급이 '%s'" % game._detail_grade.text)
	var info := ""
	for label in game._detail_info.get_children():
		info += label.text + " "
	if not info.contains("등급"):
		_fail("상세 창 아이템 정보가 '%s'" % info.left(60))
	# 강화 줄은 뺐다 (2026-09-23 요청) — 강화는 이름 뒤 +N 과 칸 배지로만 보인다
	if info.contains("강화"):
		_fail("상세 창에 강화 줄이 남아 있다: '%s'" % info.left(60))
	# 저장된 옛 아이템의 방어력 옵션이 영어 키(defense)로 찍혔다 (2026-09-23)
	var old := Items.describe_option({"kind": "defense", "value": 12})
	if old != "방어력 +12":
		_fail("옛 방어력 옵션이 '%s' 로 찍힌다" % old)
	if not first.get_node("pick").visible:
		_fail("고른 칸에 금테가 안 덮였다")

	# **세 창의 자리** (2026-09-23 요청) — 장비는 왼쪽 끝, 인벤토리는 오른쪽 끝,
	# 상세는 인벤토리 바로 왼쪽. 셋 다 화면 안이고 서로 안 겹친다
	await process_frame
	var gear_box: Rect2 = game._gear_panel.get_global_rect()
	var detail_box: Rect2 = game._detail_panel.get_global_rect()
	var bag_box: Rect2 = game._bag_panel.get_global_rect()
	var screen_box := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for pair in [["장비", gear_box], ["상세", detail_box], ["인벤토리", bag_box]]:
		if not screen_box.encloses(pair[1]):
			_fail("%s 창이 화면 밖으로 나갔다: %s" % [pair[0], pair[1]])
	if gear_box.position.x > 40.0:
		_fail("장비 창이 왼쪽 끝이 아니다: x=%.0f" % gear_box.position.x)
	if bag_box.end.x < 1240.0:
		_fail("인벤토리가 오른쪽 끝이 아니다: 끝 x=%.0f" % bag_box.end.x)
	if detail_box.end.x > bag_box.position.x or bag_box.position.x - detail_box.end.x > 20.0:
		_fail("상세 창이 인벤토리 바로 왼쪽이 아니다: %s / %s" % [detail_box, bag_box])
	if gear_box.intersects(detail_box):
		_fail("장비 창과 상세 창이 겹친다: %s / %s" % [gear_box, detail_box])
	print("  창 셋: 장비 %s · 상세 %s · 인벤토리 %s" % [gear_box, detail_box, bag_box])

	# 빈칸을 누르면 상세 창이 닫힌다
	game._bag_grid.get_child(game._bag_grid.get_child_count() - 1).get_node("hit").pressed.emit()
	await process_frame
	if game._detail_panel.visible:
		_fail("빈칸을 눌렀는데 상세 창이 그대로다")
	first.get_node("hit").pressed.emit()
	await process_frame
	# 고른 칸에 "장착" 이 얹히고, **한 번 더 누르면 낀다** (2026-09-23 요청)
	var act: Label = first.get_node("act")
	if not act.visible or act.text != "장착":
		_fail("고른 칸에 '장착' 이 안 얹혔다 (%s '%s')" % [act.visible, act.text])
	if game._bag_grid.get_child(1).get_node("act").visible:
		_fail("안 고른 칸에도 글자가 얹혔다")
	first.get_node("hit").pressed.emit()
	for i in 3:
		await process_frame
	if me.equipped.get("weapon", {}).is_empty():
		_fail("고른 칸을 한 번 더 눌렀는데 무기가 안 끼워졌다")
	elif act.visible:
		_fail("끼운 뒤에도 칸에 '%s' 가 남았다" % act.text)
	else:
		var worn: Dictionary = Items.get_item(str(me.equipped.weapon.id))
		print("  골라서 끼기: 무기 칸에 '%s'" % worn.get("name", "?"))

	# 끼운 칸을 골라 벗긴다
	var slot_index := slots.find("weapon")
	game._gear_cells[slot_index].get_node("hit").pressed.emit()
	await process_frame
	if game._bag_action.text != "해제":
		_fail("장비 칸을 골랐는데 단추가 '%s'" % game._bag_action.text)
	game._on_bag_action()
	for i in 3:
		await process_frame
	if not me.equipped.get("weapon", {}).is_empty():
		_fail("벗기를 눌렀는데 무기가 그대로다")
	else:
		print("  골라서 벗기: 무기 칸이 비었다")

	# 탭으로 거르면 **칸 번호와 가방 번호가 어긋난다** — 거기서 끼면 엉뚱한 게 끼워진다
	me.bag.clear()
	me.bag.append({"id": "g1_a", "grade": 1, "enhance": 0, "options": []})
	me.bag.append({"id": "g1_w", "grade": 1, "enhance": 0, "options": []})
	game._pick_tab(1)  # 무기
	await process_frame
	if game._bag_view != [1]:
		_fail("무기 탭인데 보이는 것이 %s (가방 1번만 나와야 한다)" % str(game._bag_view))
	game._bag_grid.get_child(0).get_node("hit").pressed.emit()
	await process_frame
	game._on_bag_action()
	for i in 3:
		await process_frame
	if me.equipped.get("weapon", {}).is_empty():
		_fail("무기 탭에서 골라 꼈는데 무기 칸이 비어 있다")
	else:
		print("  탭으로 거른 칸을 골라도 제대로 끼워진다")
	game._pick_tab(0)
	await process_frame

	# 착용 레벨이 모자란 장비 (2026-09-23) — 테스트 창이 끼워 준 Lv.181 반지를 벗으면
	# 다시 못 낀다. "장착" 이 켜져 있으면 눌러도 아무 일이 없어 보이므로 "레벨 부족" 을 띄운다
	me.bag.clear()
	me.bag.append({"id": "g7_r", "grade": 7, "enhance": 0, "options": []})
	var worn_ring: Dictionary = me.equipped.get("ring", {})
	game._redraw_bag()
	await process_frame
	var high: PanelContainer = game._bag_grid.get_child(0)
	high.get_node("hit").pressed.emit()
	await process_frame
	var high_act: Label = high.get_node("act")
	if int(me.level) >= int(Items.get_item("g7_r").level):
		_fail("레벨이 이미 %d 이라 레벨 부족을 볼 수 없다" % int(me.level))
	elif game._bag_action.text != "레벨 부족" or not game._bag_action.disabled:
		_fail("레벨이 모자란 반지인데 단추가 '%s' (꺼짐 %s)" % [game._bag_action.text, game._bag_action.disabled])
	elif not high_act.visible or not high_act.text.contains("부족"):
		_fail("레벨이 모자란 반지 칸에 '레벨 부족' 이 안 얹혔다 ('%s')" % high_act.text)
	high.get_node("hit").pressed.emit()
	for i in 3:
		await process_frame
	if me.bag.size() != 1 or me.equipped.get("ring", {}) != worn_ring:
		_fail("레벨이 모자란 반지를 두 번 눌렀는데 뭔가 바뀌었다")
	else:
		print("  레벨 부족: 칸 '%s' · 단추 '%s'" % [high_act.text.replace("\n", " "), game._bag_action.text])
	game._close_detail()

	# 정렬 — 높은 등급이 앞으로 온다. 순서만 바뀌고 물건 수는 그대로다
	me.bag.clear()
	me.bag.append({"id": "g1_r", "grade": 1, "enhance": 0, "options": []})
	me.bag.append({"id": "g3_w", "grade": 3, "enhance": 0, "options": []})
	me.bag.append({"id": "g1_w", "grade": 1, "enhance": 0, "options": []})
	game._on_bag_sort()
	for i in 3:
		await process_frame
	var order: Array = me.bag.map(func(s: Dictionary) -> String: return str(s.id))
	if order != ["g3_w", "g1_w", "g1_r"]:
		_fail("정렬했는데 순서가 %s (g3_w, g1_w, g1_r 이어야 한다)" % str(order))
	else:
		print("  정렬: %s" % str(order))

	# 크리스탈 (2026-09-23 요청) — 크리스탈 칸을 고르면 단추가 "사용", 누르면 상세 창 자리에
	# 크리스탈 창이 뜬다. 떠 있는 동안 장비 칸을 누르면 대상이 되고, "굴리기" 로 2차를 굴린다
	me.bag.clear()
	me.bag.append({"id": Items.crystal_id(), "count": 2})
	me.bag.append({"id": "g2_n", "grade": 2, "enhance": 0, "options": []})
	game._redraw_bag()
	await process_frame
	game._bag_grid.get_child(0).get_node("hit").pressed.emit()
	await process_frame
	if game._bag_action.text != "사용" or game._bag_action.disabled:
		_fail("크리스탈을 골랐는데 단추가 '%s'" % game._bag_action.text)
	if game._detail_name.text != "크리스탈":
		_fail("크리스탈 상세 이름이 '%s'" % game._detail_name.text)
	if game._enhance_button.visible:
		_fail("재료(크리스탈)를 골랐는데 강화 단추가 떠 있다")
	var use_act: Label = game._bag_grid.get_child(0).get_node("act")
	if not use_act.visible or use_act.text != "사용":
		_fail("크리스탈 칸에 '사용' 이 안 얹혔다 (%s '%s')" % [use_act.visible, use_act.text])
	# 아이콘(바르코, 2026-09-23)을 받았으면 칸에 글자 대신 그림이 뜬다
	var crystal_cell: PanelContainer = game._bag_grid.get_child(0)
	if game._icon("crystal") != null and crystal_cell.get_node("text").text != "":
		_fail("크리스탈 그림이 있는데 칸에 글자가 찍혔다")

	game._bag_grid.get_child(0).get_node("hit").pressed.emit()  # 한 번 더 누르면 사용
	await process_frame
	await process_frame
	if not game._crystal_panel.visible or game._detail_panel.visible:
		_fail("크리스탈 칸을 한 번 더 눌렀는데 크리스탈 창이 안 떴다 (상세 %s)" % game._detail_panel.visible)
	if use_act.visible:
		_fail("크리스탈 창이 떴는데 칸에 '사용' 이 남았다")
	if not game._crystal_roll.disabled:
		_fail("대상을 안 골랐는데 굴리기가 켜져 있다")
	var crystal_box: Rect2 = game._crystal_panel.get_global_rect()
	var inv_box: Rect2 = game._bag_panel.get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(crystal_box):
		_fail("크리스탈 창이 화면 밖으로 나갔다: %s" % crystal_box)
	if crystal_box.end.x > inv_box.position.x or inv_box.position.x - crystal_box.end.x > 20.0:
		_fail("크리스탈 창이 인벤토리 바로 왼쪽이 아니다: %s / %s" % [crystal_box, inv_box])

	# 장비 칸을 누르면 대상이 된다 — 상세 창은 안 뜬다
	game._bag_grid.get_child(1).get_node("hit").pressed.emit()
	await process_frame
	if game._crystal_roll.disabled or game._detail_panel.visible:
		_fail("장비 칸을 눌렀는데 대상이 안 잡혔다")
	if not game._bag_grid.get_child(1).get_node("pick").visible:
		_fail("크리스탈 대상 칸에 금테가 없다")
	game._on_crystal_roll()
	await process_frame
	var necklace: Dictionary = me.bag[1]
	var rows := ""
	for label in game._crystal_info.get_children():
		rows += label.text + " "
	if necklace.get("options2", []).size() != 1:
		_fail("굴렸는데 2차가 안 붙었다")
	elif not rows.contains("2차 옵션") or not rows.contains("3차 옵션 비어 있음"):
		_fail("크리스탈 창에 차수가 안 적혔다: '%s'" % rows)
	if game._crystal_have.text != "보유 크리스탈 x1":
		_fail("하나 썼는데 '%s'" % game._crystal_have.text)

	# 마지막 하나를 쓰면 크리스탈 칸이 빠져 목걸이가 가방 0번으로 당겨진다 — 대상도 따라가야 한다
	game._on_crystal_roll()
	await process_frame
	if me.bag.size() != 1 or int(game._crystal_target.get("index", -1)) != 0:
		_fail("마지막 크리스탈을 쓴 뒤 대상이 %s (가방 %d칸)" % [game._crystal_target, me.bag.size()])
	elif not game._crystal_roll.disabled:
		_fail("크리스탈이 0개인데 굴리기가 켜져 있다")
	elif not game._crystal_name.text.begins_with(str(Items.get_item("g2_n").name)):
		_fail("대상 이름이 '%s'" % game._crystal_name.text)
	game._close_crystal()
	await process_frame
	if game._crystal_panel.visible:
		_fail("크리스탈 창 X 를 눌렀는데 그대로다")
	print("  크리스탈: 사용 → 창 → 칸 고르기 → 굴리기 두 번 — %s" % Items.describe_option(me.bag[0].options2[0]))

	# 테스트 단추 — 건틀릿(무기)이 등급마다 하나씩 들어오고, 그림이 있으면 등급별 그림을 쓴다
	me.bag.clear()
	game._transport.send(&"debugGauntlets", {})
	for i in 3:
		await process_frame
	var grades: Array = me.bag.map(func(s: Dictionary) -> int: return int(s.grade))
	if grades != [1, 2, 3, 4, 5, 6, 7]:
		_fail("건틀릿 테스트 단추가 넣은 등급이 %s" % str(grades))
	else:
		var icon: String = game._item_icon(me.bag[4])
		if game._icon("weapon_g5") != null and icon != "weapon_g5":
			_fail("전설 건틀릿 아이콘이 '%s' (weapon_g5 여야 한다)" % icon)
		print("  건틀릿 7등급: 전설 아이콘 %s" % icon)
		# 태초는 +9 — 상세 창 큰 칸 오른쪽 아래에 나와야 한다
		game._pick_bag("bag", 6)
		await process_frame
		var big: String = game._detail_icon.get_node("badge").text
		if big != "+9":
			_fail("태초 건틀릿 상세 칸 배지가 '%s' (+9 여야 한다)" % big)
		# 강화 (2026-09-23 요청) — 상세 창에 "강화" 단추. +9 는 끝이라 꺼진다
		if not game._enhance_button.visible or not game._enhance_button.disabled:
			_fail("+9 인데 강화 단추가 %s/%s" % [game._enhance_button.visible, game._enhance_button.disabled])
		# 일반(+0)을 골라 "강화" 를 누르면 **팝업**이 화면 가운데 뜬다 (2026-09-23 요청
		# "강화 ui창을 따로 만들어. 강화 버튼 누르면 팝업이 나오게") — 성공률 90%·파괴가 적혀 있다
		game._pick_bag("bag", 0)
		await process_frame
		if not game._enhance_button.visible or game._enhance_button.disabled:
			_fail("+0 장비인데 강화 단추가 %s/%s" % [game._enhance_button.visible, game._enhance_button.disabled])
		game._enhance_button.pressed.emit()
		await process_frame
		await process_frame
		if not game._enhance.visible:
			_fail("강화 단추를 눌렀는데 팝업이 안 떴다")
		var pop_box: Rect2 = game._enhance.panel.get_global_rect()
		var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
		if not screen.encloses(pop_box) or absf(pop_box.get_center().x - 640.0) > 2.0:
			_fail("강화 팝업이 화면 가운데가 아니다: %s" % pop_box)
		var odds_rows: Array = game._enhance.info.get_children().map(func(l: Label) -> String: return l.text)
		var odds_at := odds_rows.find("성공률")
		if odds_at < 0 or odds_rows[odds_at + 1] != "90%" or not odds_rows.has("아이템 파괴"):
			_fail("팝업 표에 성공률 90%%·파괴가 없다: %s" % str(odds_rows))
		if game._enhance.kind.text != "+0  →  +1":
			_fail("팝업 단계 줄이 '%s'" % game._enhance.kind.text)
		print("  강화 팝업: %s · %s" % [pop_box, str(odds_rows)])
		game._enhance.go.pressed.emit()
		for i in 3:
			await process_frame
		if game._enhance.result.text == "":
			_fail("팝업에서 강화했는데 결과 줄이 비었다")
		var last_line: Array = game._chat.lines().back() if not game._chat.lines().is_empty() else ["", ""]
		if not str(last_line[0]).begins_with("강화"):
			_fail("강화했는데 채팅창 마지막 줄이 %s" % str(last_line))
		if me.bag.size() == 7:
			if int(me.bag[0].enhance) != 1 or game._bag_pick.is_empty():
				_fail("강화 성공인데 +%d · 고른 것 %s" % [int(me.bag[0].enhance), game._bag_pick])
			print("  강화: 성공 → +1, 채팅 %s" % str(last_line))
		elif me.bag.size() == 6:
			if not game._bag_pick.is_empty() or game._detail_panel.visible:
				_fail("부서졌는데 고른 것이 남았다 (%s)" % game._bag_pick)
			if not game._enhance.go.disabled:
				_fail("부서졌는데 팝업의 강화 단추가 켜져 있다")
			print("  강화: 파괴 → 상세 창 닫힘, 팝업 '%s'" % game._enhance.result.text)
		else:
			_fail("강화 뒤 가방이 %d칸" % me.bag.size())
		await _case_enhance_batch(game, me)
		# 팝업 X — 팝업만 닫힌다
		game._enhance.panel.find_child("close", true, false).find_child("hit", true, false).pressed.emit()
		await process_frame
		if game._enhance.visible:
			_fail("강화 팝업 X 를 눌렀는데 그대로다")

	# 장비 창은 따로 닫고 다시 연다 (자기 X · 인벤토리의 "장비" 단추)
	var gear_mark: Control = game._gear_panel.find_child("close", true, false)
	if gear_mark == null:
		_fail("장비 창에 닫기 X 가 없다")
	else:
		gear_mark.find_child("hit", true, false).pressed.emit()
		await process_frame
		if game._gear_panel.visible or not game._bag_panel.visible:
			_fail("장비 창 X 는 장비 창만 닫아야 한다")
		game._toggle_gear()
		await process_frame
		if not game._gear_panel.visible:
			_fail("'장비' 단추로 장비 창이 다시 안 열렸다")

	game._toggle_bag()
	await process_frame
	if game._bag_panel.visible:
		_fail("다시 눌렀는데 가방이 안 닫혔다")

	# 닫기는 **오른쪽 위 X** 하나다 (2026-09-20 요청 — 모든 창이 같다)
	for panel_name in ["_bag_panel", "_skill_panel"]:
		var panel: PanelContainer = game.get(panel_name)
		if panel_name == "_bag_panel":
			game._toggle_bag()
		else:
			game._toggle_skills()
		await process_frame
		var mark: Control = panel.find_child("close", true, false)
		if mark == null:
			_fail("%s 에 닫기 X 가 없다" % panel_name)
			continue
		var at: Rect2 = mark.get_global_rect()
		var box: Rect2 = panel.get_global_rect()
		if at.get_center().x < box.get_center().x or at.get_center().y > box.get_center().y:
			_fail("%s 의 닫기 X 가 오른쪽 위가 아니다: %s (창 %s)" % [panel_name, at, box])
		elif not box.encloses(at):
			_fail("%s 의 닫기 X 가 창 밖으로 나갔다: %s" % [panel_name, at])
		mark.find_child("hit", true, false).pressed.emit()
		await process_frame
		if panel.visible:
			_fail("%s 의 X 를 눌렀는데 안 닫혔다" % panel_name)
	print("  닫기는 창 오른쪽 위 X 하나다")


## 캐릭터 정보 창 — 오른쪽 위 "정보" 단추로 여는 **따로 뜨는 창**(2026-09-25 요청). 공격력은
## **기본 → 증가 % → 최종** 세 줄이고 값은 판정이 내려준 그대로다. 가방 창들과는 번갈아 뜬다
func _case_char(game: Node3D) -> void:
	var world: World = game._transport._world
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	var kept: Dictionary = me.equipped
	var was_open: bool = game._bag_panel.visible
	var weapon_slot := str(Items.get_item("g3_w").slot)
	me.equipped = {weapon_slot: {"id": "g3_w", "grade": 3, "enhance": 0, "options": []}}
	world._refresh_stats(me)
	if not was_open:
		game._toggle_bag()
	await process_frame

	# 맨 앞 단추 — 스킬 바로 왼쪽. 가방이 떠 있으면 닫고 뜬다
	var info_cell: Control = game._menu_cells[0]
	var skill_rect: Rect2 = game._menu_cells[1].get_global_rect()
	if absf(skill_rect.position.x - info_cell.get_global_rect().end.x) > 12.0:
		_fail("정보 단추가 스킬 왼쪽 옆이 아니다: %s / %s" % [info_cell.get_global_rect(), skill_rect])
	info_cell.find_child("hit", true, false).pressed.emit()
	await process_frame
	await process_frame
	if not game._char_panel.visible or game._bag_panel.visible or game._gear_panel.visible:
		_fail("정보 단추 — 정보 %s · 가방 %s · 장비 %s" % [game._char_panel.visible, game._bag_panel.visible, game._gear_panel.visible])
	game._refresh_status(me)  # 매 프레임 채우는 길 — 테스트는 프레임을 안 돌려 직접 부른다

	var base := int(Combat.stats_for(str(me.job), int(me.level)).attack)
	var pct := float(Items.equipment_stats(me.equipped).attack)
	var rows: Array = []
	for label in game._char_grids[0].get_children():
		rows.append(label.text)
	var want := [
		"기본 공격력", str(base), "공격력 증가", game._bonus_text("attack", pct),
		"최종 공격력", str(int(me.stats.attack)),
	]
	if pct <= 0.0:
		_fail("무기를 꼈는데 공격력 증가가 %s" % pct)
	if rows != want:
		_fail("공격력 줄이 %s — %s 여야 한다" % [rows, want])
	if int(me.stats.attack) != roundi(base * (1.0 + pct / 100.0)):
		_fail("최종 공격력 %d ≠ %d × (1 + %s%%)" % [int(me.stats.attack), base, pct])
	if game._char_grids.size() != game.CHAR_SPLIT.size() + 1:
		_fail("묶음이 %d개" % game._char_grids.size())

	# 자리 — 화면 가운데, 화면 안
	var box: Rect2 = game._char_panel.get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(box):
		_fail("정보 창이 화면 밖으로 나갔다: %s" % box)
	if absf(box.get_center().x - 640.0) > 2.0 or absf(box.get_center().y - 360.0) > 2.0:
		_fail("정보 창이 화면 가운데가 아니다: %s" % box)

	# 장비를 바꾸면 창을 연 채로 따라간다 (가방을 닫아 둬도)
	me.equipped = {}
	world._refresh_stats(me)
	game._refresh_status(me)
	if str(game._char_grids[0].get_child(3).text) != "+0%":
		_fail("장비를 벗었는데 증가가 '%s'" % game._char_grids[0].get_child(3).text)

	# 가방을 열면 정보 창이 비킨다
	game._toggle_bag()
	await process_frame
	if game._char_panel.visible or not game._bag_panel.visible:
		_fail("가방을 열었는데 정보 %s · 가방 %s" % [game._char_panel.visible, game._bag_panel.visible])
	game._toggle_bag()
	game._toggle_char()
	await process_frame
	game._toggle_char()  # X 와 같은 길
	await process_frame
	if game._char_panel.visible:
		_fail("정보 창 X 를 눌렀는데 그대로다")
	print("  캐릭터 정보: 기본 %d · 증가 %s · 최종 %d" % [base, want[3], int(me.stats.attack)])

	me.equipped = kept
	world._refresh_stats(me)
	if was_open:
		game._toggle_bag()
	await process_frame


## 칸 목록은 **끌어서 내린다** (`DragScroll`) — 칸 단추가 끌기를 먹어 휠로만 내려갔다
## (2026-09-24 지적: "인벤토리 ui 스크롤이 안돼" → 스킬 목록·강화 목록도 같이).
## 끌기만 하면 칸을 누르지 않고, 그 자리에서 떼면 그 칸을 누른 것이다
func _case_bag_drag(game: Node3D) -> void:
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	var kept: Array = me.bag.duplicate(true)
	# 한 화면(5×8)을 넘치게 채운다
	me.bag.clear()
	for i in 60:
		me.bag.append({"id": "g1_w", "grade": 1, "enhance": 0, "options": []})
	# 입력을 창에 넣으므로 위에 뜬 창이 없어야 한다 — 앞 절에서 연 차원문 창은
	# 제 레이어라 맨 위에서 강화 목록을 덮는다
	game._gate_panel.close_panel()
	if not game._bag_panel.visible:
		game._toggle_bag()
	await process_frame
	await process_frame

	# 가방 — 끈 뒤 누른 칸이 골라져야 한다 (스크롤된 채로 누른 칸)
	await _drag_list("가방", game._bag_drag, game._bag_scroll, game._bag_grid)
	if game._detail_panel.visible:
		_fail("가방을 끌기만 했는데 칸이 골라졌다 (상세 창이 떴다)")
	await _tap_cell(game._bag_drag, game._bag_scroll, game._bag_grid, BAG_TAP_CELL)
	if not game._detail_panel.visible:
		_fail("가방 칸을 눌렀는데 상세 창이 안 떴다")
	elif int(game._bag_pick.get("index", -1)) != BAG_TAP_CELL:
		_fail("%d 번 칸을 눌렀는데 %s 가 골라졌다" % [BAG_TAP_CELL, game._bag_pick])

	# 강화 목록(다중 강화) — 끈 뒤 누른 칸이 담겨야 한다
	var pop: EnhancePopup = game._enhance
	pop.open({"where": "bag", "index": 0})
	pop.tabs["multi"].pressed.emit()
	await process_frame
	await process_frame
	pop.clear_picked()
	await _drag_list("강화 목록", pop.list_drag, pop.list_drag._scroll, pop.list_grid)
	if not pop.picked.is_empty():
		_fail("강화 목록을 끌기만 했는데 담겼다 (%s)" % str(pop.picked))
	await _tap_cell(pop.list_drag, pop.list_drag._scroll, pop.list_grid, BAG_TAP_CELL)
	if not pop.picked.has(pop._list_view[BAG_TAP_CELL]):
		_fail("강화 목록 %d 번 칸을 눌렀는데 %s 가 담겼다" % [BAG_TAP_CELL, str(pop.picked)])
	pop.hide_now()

	me.bag.clear()
	me.bag.append_array(kept)
	game._toggle_bag()
	await process_frame

	# 스킬 목록 — 직업 스킬이 두 줄을 안 넘으면 끌 거리가 없다. 누르기만 본다
	game._toggle_skills()
	await process_frame
	await process_frame
	await _drag_list("스킬 목록", game._skill_drag, game._skill_drag._scroll, game._skill_grid)
	if game._skill_ids.size() > 1:
		await _tap_cell(game._skill_drag, game._skill_drag._scroll, game._skill_grid, 1)
		if game._skill_pick != game._skill_ids[1]:
			_fail("스킬 목록 1 번 칸을 눌렀는데 '%s' 가 골라졌다" % game._skill_pick)
	game._toggle_skills()
	await process_frame


## 착용 중 비교 창 (2026-09-25 요청: "장착중인 장비가 있으면 장착중인 아이템도 상세 정보창
## 띄워서 비교할 수 있게" + "상세 정보창 크기를 좀 줄여"). 가방 칸을 고르면 같은 부위에
## 낀 것이 **상세 창 바로 왼쪽에 같은 높이로** 뜬다. 줄이 가장 많은 장비(능력치 셋 ·
## 옵션 셋 = 8줄)로 채워도 두 창이 화면 안이어야 한다
func _case_compare(game: Node3D) -> void:
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	var kept_bag: Array = me.bag.duplicate(true)
	var kept_ring = me.equipped.get("ring", null)
	me.equipped["ring"] = {"id": "g1_r", "grade": 1, "enhance": 3,
		"options": [{"kind": "crit", "value": 2}], "options2": [{"kind": "penetration", "value": 1}]}
	me.bag.clear()
	me.bag.append({"id": "g1_r", "grade": 1, "enhance": 0,
		"options": [{"kind": "critDamage", "value": 4}], "options2": [{"kind": "maxHp", "value": 3}]})
	me.bag.append({"id": "g1_b", "grade": 1, "enhance": 0, "options": []})
	game._gate_panel.close_panel()
	if not game._bag_panel.visible:
		game._toggle_bag()
	await process_frame
	await process_frame

	# 반지를 고르면 — 낀 반지가 비교 창에 뜬다 (칸은 창에 입력을 넣어 누른다)
	await _tap_cell(game._bag_drag, game._bag_scroll, game._bag_grid, 0)
	await process_frame
	var compare: PanelContainer = game._compare_panel
	if not game._detail_panel.visible or not compare.visible:
		_fail("낀 반지가 있는데 비교 창이 안 떴다 (상세 %s · 비교 %s)" % [game._detail_panel.visible, compare.visible])
	else:
		var view: Dictionary = game._compare_view
		if view.state.text != "착용 중" or not view.name.text.ends_with("+3"):
			_fail("비교 창이 낀 반지가 아니다: '%s' · '%s'" % [view.name.text, view.state.text])
		if game._detail_state.text != "보유 중":
			_fail("상세 창이 고른 반지가 아니다: '%s'" % game._detail_state.text)
		var detail_box: Rect2 = game._detail_panel.get_global_rect()
		var box: Rect2 = compare.get_global_rect()
		var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
		if absf(box.end.x + 8.0 - detail_box.position.x) > 1.0 or absf(box.position.y - detail_box.position.y) > 1.0:
			_fail("비교 창이 상세 창 바로 왼쪽이 아니다: %s / %s" % [box, detail_box])
		if not screen.encloses(box) or not screen.encloses(detail_box):
			_fail("8줄짜리 두 창이 화면 밖으로 나갔다: %s / %s" % [box, detail_box])
		# 줄 수가 같다 — 같은 틀이라 줄끼리 맞대어 읽힌다
		if view.info.get_child_count() != game._detail_info.get_child_count():
			_fail("두 창 줄 수가 다르다: 비교 %d · 상세 %d" % [view.info.get_child_count(), game._detail_info.get_child_count()])
		print("  비교 창: %s · 상세 %s (%d줄)" % [box, detail_box, game._detail_info.get_child_count() / 2])

		# 비교 창 X 는 비교 창만 닫는다
		compare.find_child("close", true, false).find_child("hit", true, false).pressed.emit()
		await process_frame
		if compare.visible or not game._detail_panel.visible:
			_fail("비교 창 X 를 눌렀는데 비교 %s · 상세 %s" % [compare.visible, game._detail_panel.visible])

	# 낀 것이 없는 부위(신발)를 고르면 비교 창이 없다
	me.equipped.erase("boots")
	await _tap_cell(game._bag_drag, game._bag_scroll, game._bag_grid, 1)
	if compare.visible:
		_fail("낀 신발이 없는데 비교 창이 떴다")
	# 다시 반지 → 뜨고, 빈칸을 누르면 상세 창과 같이 닫힌다
	await _tap_cell(game._bag_drag, game._bag_scroll, game._bag_grid, 0)
	await _tap_cell(game._bag_drag, game._bag_scroll, game._bag_grid, 5)
	if compare.visible or game._detail_panel.visible:
		_fail("빈칸을 눌렀는데 비교 %s · 상세 %s" % [compare.visible, game._detail_panel.visible])
	# 장비 창의 낀 칸을 고르면 비교하지 않는다 (그것 자체가 낀 것이다)
	game._gear_cells[Items.slots().find("ring")].get_node("hit").pressed.emit()
	await process_frame
	if compare.visible:
		_fail("낀 반지를 골랐는데 비교 창이 떴다")

	me.bag.clear()
	me.bag.append_array(kept_bag)
	if kept_ring == null:
		me.equipped.erase("ring")
	else:
		me.equipped["ring"] = kept_ring
	game._toggle_bag()
	await process_frame


## 목록 가운데를 잡아 위로 끈다. 내용이 목록보다 크면 내려가야 하고, 작으면 그대로다.
## **입력은 창에 넣는다**(`_push_*`) — 엔진이 칸 → 격자 → 목록으로 올려 보내는 길까지
## 본다. `on_input` 을 직접 불렀더니 칸(STOP)이 입력을 멈추는 걸 못 잡고 통과했다
## (2026-09-24: 화면에서는 선택도 스크롤도 안 됐다)
func _drag_list(name: String, _drag: DragScroll, list: ScrollContainer, grid: Container) -> void:
	list.scroll_vertical = 0
	await process_frame
	# **칸 위**를 잡는다 — 목록 한가운데는 칸 사이 틈일 수 있고, 틈은 칸이 막는지 못 본다
	var grid_cols := (grid as GridContainer).columns
	var grab: Vector2 = grid.get_child(mini(grid.get_child_count() - 1, grid_cols * 2)).get_global_rect().get_center()
	_push_move(grab, 0)
	_push_mouse(grab, true)
	for i in 6:
		grab.y -= 20
		_push_move(grab, MOUSE_BUTTON_MASK_LEFT)
		await process_frame
	var dragged := list.scroll_vertical
	_push_mouse(grab, false)
	await process_frame
	var overflow := grid.size.y > list.size.y + 1.0
	if overflow and dragged <= 0:
		_fail("%s 을 끌었는데 안 내려갔다 (스크롤 %d)" % [name, dragged])
	else:
		print("  %s 끌기: %dpx 내려감%s" % [name, dragged, "" if overflow else " (한 화면에 다 들어간다)"])


## 끌지 않고 i 번째 칸 가운데를 눌렀다 뗀다 — 스크롤된 채로 보이는 칸이어야 한다
func _tap_cell(_drag: DragScroll, list: ScrollContainer, grid: Container, i: int) -> void:
	var at: Vector2 = grid.get_child(i).get_global_rect().get_center()
	_push_move(at, 0)
	_push_mouse(at, true)
	_push_mouse(at, false)
	await process_frame


## 창에 마우스 누름/뗌을 넣는다. 자리는 **화면(캔버스) 기준** — `true` 로 늘이기 배율을 건너뛴다
func _push_mouse(at: Vector2, pressed: bool) -> void:
	var event := _mouse(at, pressed)
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)


func _push_move(at: Vector2, mask: int) -> void:
	var event := _move(at)
	event.global_position = at
	event.button_mask = mask
	root.push_input(event, true)

## 퀵슬롯과 스킬창 — 자리, 크기, 그림, 장착·해제·바꾸기.
## 창은 **왼쪽이 설명, 오른쪽이 고르기** 다 (2026-09-19 요청)
## **설계 재현 창** — 문서 9장 5번의 디버그 수단. 눌러서 열고, 값을 바꾸면
## 캐릭터가 실제로 그 조건으로 서는지 본다 (화면만 바뀌고 판정이 안 따라오면 쓸모없다)
func _case_design_panel(game: Node3D) -> void:
	game._toggle_debug()
	await game.get_tree().process_frame
	if not game._debug_panel.visible:
		_fail("설계 창이 안 열린다")
		return
	if game._debug_text.text.strip_edges() == "":
		_fail("설계 창이 비어 있다")

	var me: Dictionary = game._transport.snapshot().get("players", {}).get("me", {})
	if int(me.get("level", 0)) != game._debug_level:
		_fail("창을 열었는데 레벨이 안 맞춰졌다 (%d ≠ %d)" % [int(me.get("level", 0)), game._debug_level])
	if me.get("equipped", {}).size() != 6:
		_fail("여섯 칸이 안 찼다 (%d)" % me.get("equipped", {}).size())

	# 등급을 내리면 실제로 약해져야 한다
	var before := int(me.get("stats", {}).get("attack", 0))
	game._debug_grade = maxi(1, game._debug_grade - 2)
	game._apply_debug()
	await game.get_tree().process_frame
	var after: int = int(
		game._transport.snapshot().players["me"].get("stats", {}).get("attack", 0)
	)
	if after >= before:
		_fail("등급을 내렸는데 공격력이 안 줄었다 (%d -> %d)" % [before, after])
	else:
		print("  설계 창: 등급 내리니 공격 %d -> %d" % [before, after])

	game._toggle_debug()
	await game.get_tree().process_frame
	if game._debug_panel.visible:
		_fail("설계 창이 안 닫힌다")


## 스킬창 셋째 칸 — 강화 1번·2번 카드와 경험치북 단추 (2026-09-23). 가장 오른쪽 칸이고
## 창이 화면 안이며, 책이 없으면 단추가 꺼지고, 카드를 골라 책을 누르면 그 강화에
## 경험치가 쌓이고, 필요 경험치에 닿으면 "강화 완료" 가 된다
func _check_upgrades(game: Node3D, me: Dictionary, panel: Control, screen: Vector2) -> void:
	var world: World = game._transport._world
	world.debug_reset_upgrades("me")
	var index: int = Skills.for_job(str(me.job)).find("thunder_fall")
	game._pick_skill(index)
	await process_frame
	var cards: Array = game._upgrade_cards
	if cards.size() != 2:
		_fail("강화 칸이 둘이어야 하는데 %d" % cards.size())
		return
	var box: Rect2 = panel.get_global_rect()
	if not Rect2(Vector2.ZERO, screen).encloses(box):
		_fail("강화 칸을 더한 스킬창 %s 이 화면 밖이다" % box)
	if cards[0].card.get_global_rect().position.x <= game._skill_grid.get_global_rect().end.x:
		_fail("강화 칸이 목록 오른쪽에 있지 않다")
	var books: Array = Skills.exp_books()
	var small: Button = game._book_buttons[str(books[0].id)]
	var big: Button = game._book_buttons[str(books[2].id)]
	if str(cards[0].name.text) != "기절" or not cards[0].pick.visible or not small.disabled:
		_fail("낙뢰 1번 강화가 '기절'·골라짐·책 단추 꺼짐이어야 하는데 '%s'·%s·%s" % [
			cards[0].name.text, cards[0].pick.visible, small.disabled])
	if cards[1].hit.disabled or str(cards[1].name.text) != "범위":
		_fail("낙뢰 2번 강화가 '범위' 로 골라질 수 있어야 하는데 '%s'" % cards[1].name.text)
	for button in game._book_buttons.values():
		if button.get_global_rect().end.x > box.end.x or button.get_global_rect().end.y > box.end.y:
			_fail("경험치북 단추 %s 가 창 밖이다" % button.get_global_rect())

	# 책을 받고 하급 둘 → 200, 상급 하나 → 완료
	game._test_button("", 10, 10, &"debugBooks", {}).pressed.emit()
	if small.disabled or not small.text.ends_with("10권"):
		_fail("경험치북을 받았는데 단추가 꺼져 있다 ('%s')" % small.text)
	small.pressed.emit()
	small.pressed.emit()
	if str(cards[0].amount.text) != "경험치 200 / 1000" or int(cards[0].bar.value) != 200:
		_fail("하급 둘을 넣었는데 '%s'" % cards[0].amount.text)
	big.pressed.emit()
	await process_frame
	if me.skill_upgrades.get("thunder_fall", []) != ["stun"] or str(cards[0].amount.text) != "강화 완료" \
			or not big.disabled:
		_fail("1000 을 넘겼는데 강화가 안 붙었다 (%s · '%s')" % [str(me.skill_upgrades), cards[0].amount.text])
	else:
		print("  강화 칸: %s · 하급 둘 200 → 상급 하나로 '%s'" % [box, cards[0].amount.text])
	world.debug_reset_upgrades("me")


func _case_skills(game: Node3D) -> void:
	var me: Dictionary = game._transport.snapshot().players[game._transport.my_id()]
	var screen := Vector2(1280, 720)

	# 퀵슬롯 4칸이 화면 아래 가운데에, 오른쪽 단추들과 겹치지 않게
	var quick: Array = game._bar_buttons
	if quick.size() != 4:
		_fail("퀵슬롯이 4칸이어야 하는데 %d칸" % quick.size())
		return
	var first: Rect2 = quick[0].get_global_rect()
	var last: Rect2 = quick[3].get_global_rect()
	# 자동사냥 칸까지 **다섯 칸 한 줄**이 아래 가운데다 (2026-09-19 요청)
	var auto_rect: Rect2 = game._auto_cell.get_global_rect()
	var middle := (first.position.x + auto_rect.end.x) / 2.0
	if absf(middle - screen.x / 2.0) > 2.0 or last.end.y > screen.y or last.end.y < screen.y - 60:
		_fail("퀵슬롯이 아래 가운데가 아니다: %s ~ %s" % [first, last])
	if last.intersects(auto_rect):
		_fail("퀵슬롯이 자동사냥 칸과 겹친다")
	if auto_rect.position.x < last.end.x:
		_fail("자동사냥 칸이 퀵슬롯 옆이 아니다: %s" % auto_rect)

	# 처음에는 액션바가 비어 있을 수 있다 — 앞의 넷을 올려 두고 시작한다
	game._send_bar(Skills.for_job(str(me.job)).slice(0, 4))
	if me.skill_bar.size() != 4:
		_fail("앞의 넷을 올렸는데 액션바가 %d칸" % me.skill_bar.size())
		return
	game._refresh_bar(me)
	var icons := 0
	for cell in quick:
		if cell.find_child("icon", true, false).texture != null:
			icons += 1
	print("  퀵슬롯: 가운데 x=%.0f, 아이콘 %d/4" % [middle, icons])

	# 쿨타임 — 쓰고 나면 어둠이 덮이고 초가 뜬다
	var used := str(me.skill_bar[0])
	me.skill_ready_at[used] = Time.get_ticks_msec() + 3000
	game._refresh_bar(me)
	if not quick[0].find_child("cool", true, false).visible or quick[0].find_child("secs", true, false).text != "3":
		_fail("쿨타임 3초가 퀵슬롯에 안 나온다")
	if not quick[0].find_child("edge", true, false).visible:
		_fail("쿨타임이 도는데 경계 바늘이 없다")
	me.skill_ready_at[used] = 0
	game._refresh_bar(me)
	# 끝나는 순간 번쩍인다
	if quick[0].find_child("flash", true, false).color.a <= 0.0:
		_fail("쿨타임이 끝났는데 칸이 안 번쩍인다")
	# 단축키 번호가 왼쪽 위에 1~4
	for slot in quick.size():
		if quick[slot].find_child("key", true, false).text != str(slot + 1):
			_fail("%d번 퀵슬롯에 단축키 번호가 없다" % (slot + 1))

	# 스킬 단추를 누르면 창이 열린다
	game._toggle_skills()
	await process_frame
	var panel: Control = game._skill_panel
	if not panel.visible:
		_fail("스킬 단추를 눌렀는데 창이 안 떴다")
		return
	var box: Rect2 = panel.get_global_rect()
	if not Rect2(Vector2.ZERO, screen).encloses(box):
		_fail("스킬창 %s 이 화면 밖으로 나간다" % box)

	# 왼쪽 설명, 오른쪽 목록
	var ids: Array = Skills.for_job(str(me.job))
	if game._skill_cells.size() != ids.size():
		_fail("목록이 %d칸이어야 하는데 %d칸" % [ids.size(), game._skill_cells.size()])
		return
	var big_x: float = game._skill_big.get_global_rect().position.x
	var list_x: float = game._skill_grid.get_global_rect().position.x
	if big_x >= list_x:
		_fail("설명(%.0f)이 목록(%.0f) 왼쪽에 있어야 한다" % [big_x, list_x])
	var drawn := 0
	for cell in game._skill_cells:
		if cell.find_child("icon", true, false).texture != null or cell.find_child("text", true, false).text != "":
			drawn += 1
	if drawn != ids.size():
		_fail("목록 칸 %d개가 그림도 글자도 없다" % (ids.size() - drawn))

	# 고르면 왼쪽 설명이 따라온다
	var last_id := str(ids[ids.size() - 1])
	game._pick_skill(ids.size() - 1)
	if game._skill_name.text != str(Skills.all()[last_id].name) or game._skill_desc.text == "":
		_fail("고른 스킬(%s)이 설명에 안 나온다: '%s'" % [last_id, game._skill_name.text])
	# 설명 끝에 피해 배율. 연타는 "* N연타" 를 붙인다
	if not game._skill_desc.text.ends_with(Skills.damage_text(Skills.all()[last_id])):
		_fail("설명에 데미지 줄이 없다: '%s'" % game._skill_desc.text)
	for want in [["fireball", "데미지 : 260%"], ["rising_kick", "데미지 : 56% * 3연타"]]:
		if Skills.all().has(want[0]) and Skills.damage_text(Skills.all()[want[0]]) != want[1]:
			_fail("%s 데미지 줄이 '%s' 여야 하는데 '%s'" % [want[0], want[1], Skills.damage_text(Skills.all()[want[0]])])
	if not game._skill_cells[ids.size() - 1].get_node("pick").visible:
		_fail("고른 칸에 테두리가 안 뜬다")
	# 배운 것은 레벨 글자를 지우고, 안 배운 것은 "Lv.N 습득"
	for index in ids.size():
		var badge: String = game._skill_cells[index].find_child("badge", true, false).text
		var want := "" if str(ids[index]) in me.skills else "Lv.%d 습득" % int(Skills.all()[str(ids[index])].reqLevel)
		if badge != want:
			_fail("%s 칸 글자가 '%s' 여야 하는데 '%s'" % [ids[index], want, badge])

	# 해제 → 빈 칸에 장착 → 가득 찼으면 바꿀 칸을 골라 끼운다
	var bar: Array = me.skill_bar
	var before := bar.size()
	game._skill_pick = str(bar[0])
	game._on_skill_unequip()
	if me.skill_bar.size() != before - 1:
		_fail("해제했는데 액션바가 %d칸 그대로다" % me.skill_bar.size())
	game._on_skill_equip()
	if me.skill_bar.size() != before:
		_fail("빈 칸이 있는데 장착이 안 됐다")
	if me.skill_bar.size() == 4 and not (last_id in me.skill_bar):
		game._pick_skill(ids.size() - 1)
		game._on_skill_equip()
		if not game._skill_swap or game._skill_state.text != "바꿀 칸을 누르세요":
			_fail("4칸이 다 찼는데 바꿀 칸을 묻지 않는다")
		game._pick_slot(2)
		if str(me.skill_bar[2]) != last_id:
			_fail("3번 칸을 골랐는데 %s 가 들어갔다" % str(me.skill_bar[2]))
		else:
			print("  스킬창: 목록 %d칸, 해제·장착·바꾸기(3번 칸 → %s) 확인" % [ids.size(), last_id])

	await _check_upgrades(game, me, panel, screen)

	game._toggle_skills()
	await process_frame
	if panel.visible:
		_fail("닫기를 눌렀는데 스킬창이 안 닫혔다")

	# 빈 퀵슬롯을 눌러도 스킬창이 열리지 않는다 (2026-09-23 요청으로 뺐다)
	var kept: Array = me.skill_bar.duplicate()
	me.skill_bar.resize(mini(kept.size(), 3))
	game._on_bar_pressed(me.skill_bar.size())
	await process_frame
	me.skill_bar.assign(kept)
	if panel.visible:
		_fail("빈 퀵슬롯을 눌렀는데 스킬창이 열렸다")

	# 테스트 스위치 단추 — 누르면 뒤집히고, 다시 누르면 돌아온다
	if game._switch_buttons.has("unlockAll"):
		_fail("레벨 잠금 해제 단추는 걷었는데 아직 있다")
	for name in game._switch_buttons:
		var read := func() -> bool: return Skills.cooldown_off() if name == "cooldownOff" else Skills.unlock_all()
		var was: bool = read.call()
		game._switch_buttons[name].pressed.emit()
		if read.call() == was or not game._switch_buttons[name].text.ends_with("켬" if not was else "끔"):
			_fail("%s 단추를 눌렀는데 안 바뀐다: %s" % [name, game._switch_buttons[name].text])
		game._switch_buttons[name].pressed.emit()
		if read.call() != was:
			_fail("%s 단추를 두 번 눌렀는데 원래대로 안 돌아온다" % name)
	var corner: Rect2 = game._switch_buttons["cooldownOff"].get_global_rect()
	# 왼쪽 아래 구석은 채팅창 자리라(2026-09-23) 단추 묶음은 그 바로 위에 선다
	var chat: Rect2 = game._chat.get_global_rect()
	if corner.position.x > 40 or corner.end.y > chat.position.y or corner.end.y < chat.position.y - 40:
		_fail("스위치 단추가 채팅창 바로 위(왼쪽 아래)가 아니다: %s, 채팅창 %s" % [corner, chat])
	if corner.intersects(game._bar_buttons[0].get_global_rect()):
		_fail("스위치 단추가 퀵슬롯과 겹친다")
	print("  테스트 스위치 단추 %d개: 켜고 끄기 확인 (%s)" % [game._switch_buttons.size(), corner])

	# 무적 단추 — 왼쪽 아래 줄에 있고, 켜면 맞아도 HP 가 그대로다
	var world = game._transport._world
	var hero: Dictionary = world.snapshot().players[game._transport.my_id()]
	var shield: Rect2 = game._invincible_button.get_global_rect()
	if shield.position.x > 40 or shield.end.y > corner.position.y:
		_fail("무적 단추가 쿨타임 단추 위(왼쪽 아래)가 아니다: %s" % shield)
	game._invincible_button.pressed.emit()
	if not bool(hero.get("invincible", false)):
		_fail("무적 단추를 눌렀는데 안 켜졌다")
	var hp_before := int(hero.hp)
	world._hit_player(hero, {"id": "test", "attack": 999.0})
	if int(hero.hp) != hp_before:
		_fail("무적인데 HP 가 줄었다: %d → %d" % [hp_before, int(hero.hp)])
	game._invincible_button.pressed.emit()
	if bool(hero.get("invincible", false)):
		_fail("무적 단추를 다시 눌렀는데 안 꺼졌다")
	print("  무적 단추: 켜면 피해 0, 다시 누르면 꺼짐 (%s)" % shield)

	# 스킬 범위 단추 — **꺼 두면 판정이 보내도 안 그린다**, 켜면 그리고 숫자를 적는다.
	# 끄면 떠 있던 것까지 치운다 (남아 있으면 꺼졌는지가 안 읽힌다)
	var band: Rect2 = game._range_button.get_global_rect()
	if band.position.x > 40 or band.end.y > shield.position.y:
		_fail("스킬 범위 단추가 무적 단추 위(왼쪽 아래)가 아니다: %s" % band)
	var shape := {"x": 1.0, "z": 2.0, "reach": 4.0, "arc": TAU, "facing": 0.0, "hits": 3, "skill": "thunder_fall"}
	game._on_event(&"skillRange", shape)
	if not game._range_marks.is_empty():
		_fail("꺼 뒀는데 범위를 그렸다")
	game._range_button.pressed.emit()
	game._on_event(&"skillRange", shape)
	if game._range_marks.size() != 1:
		_fail("켰는데 범위를 안 그렸다 (%d개)" % game._range_marks.size())
	elif not game._range_label.text.contains("3 마리"):
		_fail("맞은 수가 안 적혔다: '%s'" % game._range_label.text)
	game._range_button.pressed.emit()
	await process_frame
	if not game._range_marks.is_empty() or game._range_label.text != "":
		_fail("껐는데 떠 있던 범위가 안 치워졌다")
	print("  스킬 범위 단추: 꺼 두면 안 그리고, 켜면 그리며 '%s' (%s)" % [
		"3 마리", band
	])

	# 새 문구 글자가 폰트에 있나 (부분집합이라 빠질 수 있다)
	var font: Font = load(FONT)
	var missing := ""
	for ch in "장착 해제 취소 스킬 목록 바꿀 칸을 누르세요 요구 레벨 재사용 사거리 주위 대상 배움 습득 테스트 쿨타임 잠금 해제 켬 끔 무적 범위 마리":
		if ch != " " and not font.has_char(ch.unicode_at(0)):
			missing += ch
	if missing != "":
		_fail("스킬창 글자가 폰트에 없다: %s" % missing)


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


## 강화 팝업의 다중 강화 (2026-09-24 요청: 리니지M "다중 강화" 그림 + "다중강화 ui를 이런식으로") —
## 탭 둘, 오른쪽 목록에서 눌러 담고, 화살표 띠로 목표를 고르면 한 바퀴씩 돈다("중지").
## 채팅은 끝날 때 한 줄, 담은 칸은 판정이 돌려준 번호로 이어 간다
func _case_enhance_batch(game: Node, me: Dictionary) -> void:
	var pop: EnhancePopup = game._enhance
	var ref_id := str(pop.ref.id)
	for i in 3:
		me.bag.append({"id": ref_id, "grade": 1, "enhance": 0, "options": []})
	me.bag.append({"id": "g1_a", "grade": 1, "enhance": 0, "options": []})  # 같은 등급·다른 아이템
	pop.tabs["multi"].pressed.emit()
	await process_frame
	if not pop.list_panel.visible or not pop.multi_box.visible or pop.one_box.visible:
		_fail("다중 강화 탭인데 목록 %s · 담는 칸 %s" % [pop.list_panel.visible, pop.multi_box.visible])
	var pair := pop.panel.get_global_rect().merge(pop.list_panel.get_global_rect())
	if not Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(pair):
		_fail("다중 강화 두 창이 화면을 벗어난다: %s" % pair)
	print("  다중 강화 창: 왼쪽 %s · 오른쪽 %s" % [pop.panel.size, pop.list_panel.size])
	# 목표 +3 (화살표 셋째)
	pop.chevrons[2].chosen.emit(3)
	await process_frame
	if pop.goal != 3 or not pop.chevrons[2].lit or pop.chevrons[3].lit:
		_fail("화살표 +3 을 눌렀는데 목표 %d" % pop.goal)
	# 같은 아이템 탭 — 목록에 같은 id 만. 모두 담기로 담는다
	var same := 0
	for stack in me.bag:
		if Items.batch_match(stack, "item", ref_id, 1, 3):
			same += 1
	pop.pick_filter("item")
	await process_frame
	if pop._list_view.size() != same:
		_fail("같은 아이템 목록이 %d칸 (%d 이어야 한다)" % [pop._list_view.size(), same])
	pop.clear_picked()
	var first: PanelContainer = pop._list_cells[0]
	first.get_node("hit").pressed.emit()
	await process_frame
	if pop.picked.size() != 1 or not first.get_node("pick").visible:
		_fail("목록 칸을 눌렀는데 담기지 않았다 (%s)" % str(pop.picked))
	pop.picked_grid.get_child(0).get_node("hit").pressed.emit()
	await process_frame
	if not pop.picked.is_empty():
		_fail("담은 칸을 눌렀는데 빠지지 않았다 (%s)" % str(pop.picked))
	# 같은 등급 탭 — 다른 아이템도 나온다
	pop.pick_filter("grade")
	await process_frame
	if pop._list_view.size() <= same:
		_fail("같은 등급 목록이 같은 아이템보다 많지 않다 (%d)" % pop._list_view.size())
	pop.pick_filter("item")
	pop.pick_all()
	await process_frame
	var pieces: int = pop._picked_pieces(true)
	if pop.run_button.text != "%d개 강화  →  +3" % pieces or pieces != same:
		_fail("모두 담기 뒤 단추가 '%s' (같은 아이템 %d)" % [pop.run_button.text, same])
	var rows: Array = pop.info.get_children().map(func(l: Label) -> String: return l.text)
	if not rows.has("+3 예상 도달"):
		_fail("다중 표에 예상 도달이 없다: %s" % str(rows))
	var chat_before: int = game._chat.lines().size()
	pop.step_time = 0.05
	pop.run_button.pressed.emit()
	await process_frame
	if not pop.running or pop.run_button.text != "중지" or not pop.tabs["one"].disabled:
		_fail("다중 강화를 눌렀는데 도는 중이 아니다 (%s · '%s')" % [pop.running, pop.run_button.text])
	var waited := 0
	while pop.running and waited < 600:
		await process_frame
		waited += 1
	if pop.running:
		_fail("다중 강화가 %d프레임이 지나도 안 끝난다" % waited)
	if not pop.result.text.contains("도달"):
		_fail("다중 강화 결과 줄이 '%s'" % pop.result.text)
	var line: Array = game._chat.lines().back()
	if str(line[0]) != "다중 강화" or game._chat.lines().size() != chat_before + 1:
		_fail("다중 강화 뒤 채팅이 %d줄 늘고 마지막이 %s (한 줄이어야 한다)" % [
			game._chat.lines().size() - chat_before, str(line)
		])
	# 깨진 칸은 터지는 한 박자 동안만 자리를 지키고, 끝나면 남은 장비가 앞으로 당겨진다
	# (2026-09-24 "깨져서 터지면 남은 아이템 정렬을 맨 앞으로 땡겨")
	if pop.picked.has(-1):
		_fail("다 돈 뒤에 깨진 빈칸이 남았다: %s" % str(pop.picked))
	for k in pop.picked.size():
		var at: int = pop.picked[k]
		var mark: Control = pop.picked_grid.get_child(k).get_node("broken")
		if at < 0:
			if not mark.visible:
				_fail("깨진 칸 %d 에 X 가 없다" % k)
			continue
		if mark.visible:
			_fail("살아 있는 칸 %d 에 X 가 떠 있다" % k)
		if int(me.bag[at].enhance) != 3 or str(me.bag[at].id) != ref_id:
			_fail("다 돈 뒤 담은 칸 %d 이 %s +%d" % [at, me.bag[at].id, int(me.bag[at].enhance)])
	if not game._bag_pick.is_empty():
		_fail("다중 강화 뒤에 고른 칸이 남았다 (%s)" % game._bag_pick)
	print("  다중 강화 +3: '%s' · 채팅 %s" % [pop.result.text, str(line)])
	# 중지 — 목표를 +9 로 올려 돌리고 바로 누르면 그 자리에서 멈춘다
	pop.chevrons[8].chosen.emit(9)
	pop.pick_all()
	if pop._picked_pieces(true) > 0:
		pop.step_time = 5.0
		pop.run_button.pressed.emit()
		await process_frame
		pop.run_button.pressed.emit()
		await process_frame
		if pop.running or str(game._chat.lines().back()[0]) != "다중 강화 중지":
			_fail("중지를 눌렀는데 %s · 채팅 %s" % [pop.running, str(game._chat.lines().back())])
	# 단일 탭으로 돌아오면 대상(가방)은 다중으로 흔들려서 비었다
	pop.tabs["one"].pressed.emit()
	await process_frame
	if not pop.go.disabled or pop.list_panel.visible:
		_fail("다중 뒤 단일 탭인데 강화 단추 %s · 목록 %s" % [pop.go.disabled, pop.list_panel.visible])
	# 단일 자동 — +0 하나를 +2 까지. 닿으면 "완료", 부서지면 "부서졌습니다"
	me.bag.append({"id": ref_id, "grade": 1, "enhance": 0, "options": []})
	pop.open({"where": "bag", "index": me.bag.size() - 1})
	if not pop.chevrons[0].lit or pop.chevrons[1].lit:
		_fail("+0 을 열었는데 목표 띠가 +1 까지가 아니다")
	pop.chevrons[1].chosen.emit(2)
	pop.step_time = 0.05
	pop.run_button.pressed.emit()
	var ticks := 0
	while pop.running and ticks < 600:
		await process_frame
		ticks += 1
	if pop.running or not (pop.result.text.contains("완료") or pop.result.text.contains("부서졌")):
		_fail("단일 자동 +2 결과가 '%s' (도는 중 %s)" % [pop.result.text, pop.running])
	var left: Dictionary = game._stack_at(pop.target) if not pop.target.is_empty() else {}
	if not left.is_empty() and int(left.get("enhance", 0)) != 2:
		_fail("목표 +2 인데 +%d 에서 멈췄다" % int(left.get("enhance", 0)))
	print("  단일 자동 +2: '%s'" % pop.result.text)
	# 낮은 강화부터 한 단계씩 (2026-09-24 "강화 수치가 다른게 있으면 낮은 강화부터 천천히 한 단계씩") —
	# +0 셋과 +2 둘을 +3 목표로 돌리면 첫 바퀴는 +0 만 두드리고 +2 는 그대로다
	var low: Array = []
	var high: Array = []
	for level in [0, 2, 0, 2, 0]:
		me.bag.append({"id": ref_id, "grade": 1, "enhance": level, "options": []})
		(low if level == 0 else high).append(me.bag.size() - 1)
	pop.open({"where": "bag", "index": low[0]})
	pop.pick_mode("multi")
	pop.set_goal(3)
	pop.picked = low + high
	pop.picked.sort()
	pop.step_time = 5.0
	var chat_mark: int = game._chat.lines().size()
	pop.run_button.pressed.emit()
	for i in 3:
		await process_frame
	var twos := 0
	for at in high:  # +0 칸은 한 칸씩이라 갈라지지 않는다 — +2 칸 번호는 그대로다
		if int(me.bag[at].enhance) == 2:
			twos += 1
	var ones: Array = me.bag.slice(me.bag.size() - 8).filter(func(s: Dictionary) -> bool: return int(s.enhance) == 1)
	if twos != 2 or not pop.result.text.begins_with("+0 → +1"):
		_fail("섞인 단계 첫 바퀴에 +2 가 %d개 남음 (2 여야) · 결과 '%s'" % [twos, pop.result.text])
	print("  낮은 것부터: 첫 바퀴 +0 → +1 에서 %d칸 성공, +2 둘은 그대로 · '%s'" % [
		ones.size(), pop.result.text.replace("\n", " / ")])
	pop.run_button.pressed.emit()  # 중지
	if game._chat.lines().size() != chat_mark + 1:
		_fail("중지했는데 채팅이 한 줄이 아니다")
