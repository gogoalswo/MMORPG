extends SceneTree

## 단추 움직임(`ButtonFx`, 2026-09-29) — 누르면 줄고, 밖에서 떼면 제 크기로, 클릭하면 부풀었다
## 돌아오며 번쩍이는지 본다. 그리고 **가방·던전 같은 진짜 단추에 붙어 있는지** 본다.
##
## 신호를 직접 쏜다 (`button_down` · `button_up` · `pressed`). 스크린샷을 찍지 않는다 — 크기·색을 읽는다.
##
##   godot --headless --path godot --script tests/button_fx_test.gd

var _failed := 0


func _init() -> void:
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _run() -> void:
	var button := Button.new()
	button.text = "인챈트"
	button.size = Vector2(200, 60)
	root.add_child(button)
	ButtonFx.attach(button)
	ButtonFx.attach(button)  # 두 번 붙여도 한 번만
	await process_frame

	await _case_press(button)
	await _case_release(button)
	await _case_click(button)
	await _case_real()
	_done()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## 누르면 가운데를 축으로 줄어든다
func _case_press(button: Button) -> void:
	button.button_down.emit()
	await _wait(ButtonFx.PRESS_SEC + 0.1)
	if not is_equal_approx(button.scale.x, ButtonFx.PRESS_SCALE):
		_fail("누르니 %.3f 배다 (%.2f 여야)" % [button.scale.x, ButtonFx.PRESS_SCALE])
	if button.pivot_offset != button.size / 2.0:
		_fail("축이 가운데가 아니다 (%s)" % button.pivot_offset)
	print("  누름: %.2f 배" % button.scale.x)


## 밖에서 떼면(`pressed` 없이) 번쩍이지 않고 제 크기로 돌아온다
func _case_release(button: Button) -> void:
	button.button_up.emit()
	await process_frame
	await process_frame
	if button.self_modulate != Color.WHITE:
		_fail("클릭이 아닌데 번쩍였다 (%s)" % button.self_modulate)
	await _wait(ButtonFx.RELEASE_SEC + 0.1)
	if not button.scale.is_equal_approx(Vector2.ONE):
		_fail("떼고 나서 %s 배다" % button.scale)
	print("  뗌: %.2f 배로 돌아옴" % button.scale.x)


## 클릭 — 부풀었다 돌아오고, 잠깐 밝아졌다가 원래 색으로
func _case_click(button: Button) -> void:
	button.button_down.emit()
	await _wait(ButtonFx.PRESS_SEC + 0.05)
	# 고도는 뗄 때 `pressed` 와 `button_up` 을 같은 프레임에 쏜다 — 순서를 바꿔 쏴도 클릭이어야 한다
	button.pressed.emit()
	button.button_up.emit()
	await process_frame
	await process_frame
	var bright := button.self_modulate
	if bright.r <= 1.0:
		_fail("클릭했는데 밝아지지 않았다 (%s)" % bright)
	var biggest := 0.0
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < int((ButtonFx.CLICK_UP_SEC + ButtonFx.CLICK_DOWN_SEC) * 1000) + 150:
		biggest = maxf(biggest, button.scale.x)
		await process_frame
	if biggest <= 1.02:
		_fail("클릭했는데 부풀지 않았다 (가장 클 때 %.3f 배)" % biggest)
	await _wait(ButtonFx.FLASH_SEC)
	if not button.scale.is_equal_approx(Vector2.ONE):
		_fail("클릭 뒤 %s 배로 남았다" % button.scale)
	if not button.self_modulate.is_equal_approx(Color.WHITE):
		_fail("클릭 뒤 색이 %s 로 남았다" % button.self_modulate)
	print("  클릭: 가장 클 때 %.2f 배, 번쩍 %.2f → 원래 색" % [biggest, bright.r])


## 진짜 단추들 — 청록 단추를 만드는 길(`paint_button_text` · `_make_button` · 상점 탭)에 붙어 있다
func _case_real() -> void:
	Save.clear()
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	await process_frame
	var game: Node3D = root.get_node("Game")
	if game._icon("ui_button") == null:
		print("  (단추 조각이 없어 진짜 단추 검사는 건너뜀 — npm run sync:godot)")
		return
	var found := 0
	var missing: Array = []
	for node in game.find_children("*", "Button", true, false):
		var box = node.get_theme_stylebox("normal")
		if not (box is StyleBoxTexture) or box.texture == null:
			continue
		if not box.texture.resource_path.ends_with("ui_button.png") and box.texture != game._small_button_texture():
			continue
		found += 1
		if not node.has_meta(&"button_fx"):
			missing.append(str(game.get_path_to(node)))
	if found == 0:
		_fail("청록 단추를 하나도 못 찾았다")
	elif not missing.is_empty():
		_fail("움직임이 없는 청록 단추 %d개: %s" % [missing.size(), missing.slice(0, 6)])
	print("  청록 단추 %d개 모두 움직임이 붙음" % found)
	await _case_hud(game)


## HUD 아이콘 — 메뉴 · 퀵슬롯 · 자동사냥 · 물약. 투명한 hit 이 누름을 받고 **칸이** 움직인다.
## 숨긴 설계 칸(`modulate.a = 0`)은 클릭해도 숨은 채다
func _case_hud(game: Node3D) -> void:
	var cells: Array = game._menu_cells.duplicate()
	cells.append_array(game._bar_buttons)
	cells.append(game._auto_cell)
	cells.append(game._potion_cell)
	var bare: Array = []
	for cell in cells:
		var hit: Button = cell.get_node_or_null("hit")
		if hit == null or not hit.has_meta(&"button_fx"):
			bare.append(str(cell.name))
	if not bare.is_empty():
		_fail("움직임이 없는 HUD 칸: %s" % [bare])

	var cell: Control = game._bar_buttons[0]
	var hit: Button = cell.get_node("hit")
	hit.button_down.emit()
	await _wait(ButtonFx.PRESS_SEC + 0.1)
	if not is_equal_approx(cell.scale.x, ButtonFx.PRESS_SCALE):
		_fail("퀵슬롯을 누르니 칸이 %.3f 배다" % cell.scale.x)
	hit.button_up.emit()
	hit.pressed.emit()
	await process_frame
	await process_frame
	if cell.modulate.r <= 1.0:
		_fail("퀵슬롯을 클릭했는데 칸이 밝아지지 않았다 (%s)" % cell.modulate)
	await _wait(ButtonFx.CLICK_UP_SEC + ButtonFx.CLICK_DOWN_SEC + ButtonFx.FLASH_SEC)
	if not cell.scale.is_equal_approx(Vector2.ONE) or not cell.modulate.is_equal_approx(Color.WHITE):
		_fail("퀵슬롯 클릭 뒤 %s 배 · %s 색으로 남았다" % [cell.scale, cell.modulate])

	var design: Control = game._design_cell
	var was: float = design.modulate.a
	var design_hit: Button = design.get_node("hit")
	design_hit.button_down.emit()
	design_hit.button_up.emit()
	design_hit.pressed.emit()
	await process_frame
	await process_frame
	if not is_equal_approx(design.modulate.a, was):
		_fail("숨긴 설계 칸을 클릭하니 알파가 %.2f → %.2f" % [was, design.modulate.a])
	await _wait(ButtonFx.FLASH_SEC + 0.1)
	if not is_equal_approx(design.modulate.a, was):
		_fail("숨긴 설계 칸이 클릭 뒤 알파 %.2f 로 남았다 (%.2f 여야)" % [design.modulate.a, was])
	print("  HUD 칸 %d개 — 누르면 칸이 줄고 클릭하면 번쩍, 숨긴 칸은 숨은 채" % cells.size())


func _done() -> void:
	if _failed == 0:
		print("단추 움직임: 통과")
		quit(0)
	else:
		print("단추 움직임: %d개 실패" % _failed)
		quit(1)
