class_name EnhancePopup
extends Control

## 강화 팝업 — 상세 창 "강화" 로 연다. **화면 가운데에 뜨고 뒤를 어둡게 덮는다** — 덮은 막이
## 뒤 창을 못 누르게 막아서, 떠 있는 동안 대상이 바뀔 일이 없다.
##
## 오기까지 (2026-09-23 ~ 24):
## 1. "상세 정보창 누르면 강화 버튼 나오게 해" → 상세 창 단추가 바로 굴렸다
## 2. "강화 ui창을 따로 만들어. 강화 버튼 누르면 팝업이 나오게" → game.gd 안의 팝업
## 3. "아이템 강화 팝업을 따로 만들어. 한 개만 강화할 수도 있고 동일한 아이템 혹은 등급
##    아이템을 여러 개 한 번에 강화할 수 있게 … 강화 목표치를 설정해서 자동 강화" → 이 파일
##
## 위 탭 셋이 **무엇을** 두드릴지 고른다:
##   한 개      — 연 장비 하나 (겹친 칸이면 한 개만 뗀다)   → enhanceItem {where, key, goal}
##   같은 아이템 — 가방의 같은 id·등급 장비 전부            → enhanceBatch {mode: "item", …}
##   같은 등급   — 가방의 같은 등급 장비 전부               → enhanceBatch {mode: "grade", …}
## 아래 **"자동"** 을 켜면 목표 단계(−/+)까지 부서지거나 닿을 때까지 이어서 두드린다.
## 끄면 한 개씩 한 단계만. 일괄은 **끼고 있는 것을 뺀다** (판정 `World.enhance_batch`).
## 대상 규칙은 `Items.batch_match` 하나 — 팝업이 세는 수와 판정이 두드리는 수가 같다.
##
## 틀·조각(`_window_panel`·`_make_cell`·`_fill_detail_rows` …)은 game.gd 것을 빌린다 —
## 상세 창과 같은 결이어야 해서다. 스냅샷도 game 의 `_transport` 에서 읽는다.
## → docs/features/items.md "강화"

## 탭 순서와 글자
const MODES := ["one", "item", "grade"]
const MODE_TEXT := {"one": "한 개", "item": "같은 아이템", "grade": "같은 등급"}
const WIDTH := 360
## "12개 자동 강화" 가 한 줄에 들어가는 폭
const GO_WIDTH := 170

## 한 개를 두드리고 나면 — 대상이 남았나(kept), 가방 번호가 몇 칸 밀렸나(shift).
## 일괄 뒤에는 가방 번호가 통째로 흔들려서 kept=false 로 알린다 (고른 칸을 비워야 한다)
signal acted(kept: bool, shift: int)
signal closed

var panel: PanelContainer
var title_line: Label
var kind: Label
var icon: PanelContainer
var info: GridContainer
var result: Label
var go: Button
var auto_button: Button
var goal_label: Label
var goal_down: Button
var goal_up: Button
var tabs: Dictionary = {}

var mode := "one"
var auto := false
var goal := 1
## 한 개 모드의 대상 — {where: "bag"|"equip", index: 가방 번호 | 슬롯 번호}
var target: Dictionary = {}
## 일괄 기준 — 연 장비의 id·등급. 한 개가 부서져도 남는다
var ref: Dictionary = {}

var _game  # game.gd — class_name 이 없어서 이름 없이 든다
## 누른 순간 대상 칸의 개수 — 결과 글자 "하나가 부서졌습니다" 에 쓴다
var _pressed_count := 1


static func make(game: Node) -> EnhancePopup:
	var popup := EnhancePopup.new()
	popup.name = "EnhancePopup"
	popup._game = game
	popup._build()
	return popup


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = _game._window_panel()
	panel.visible = true
	center.add_child(panel)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(WIDTH, 0)
	side.add_theme_constant_override("separation", 8)
	panel.add_child(side)

	_game._window_title(side, "장비 강화", 22)

	# 무엇을 두드리나 — 탭 셋
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	side.add_child(row)
	for key in MODES:
		var tab: Button = _game._inv_button(MODE_TEXT[key], pick_mode.bind(key))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tab)
		tabs[key] = tab

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	side.add_child(head)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 4)
	head.add_child(lines)
	title_line = _game._inv_label("", 22, _game.INV_GOLD)
	title_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(title_line)
	kind = _game._inv_label("", 20, _game.INV_GOLD_HI)
	lines.add_child(kind)
	icon = _game._make_cell(func() -> void: pass, _game.DETAIL_ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.get_node("badge").add_theme_font_size_override("font_size", 22)
	head.add_child(icon)

	side.add_child(_game._inv_label("강화 정보", 20, _game.INV_GOLD))
	var rule := ColorRect.new()
	rule.color = _game.INV_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	side.add_child(rule)

	info = GridContainer.new()
	info.columns = 2
	info.add_theme_constant_override("h_separation", 12)
	info.add_theme_constant_override("v_separation", 6)
	side.add_child(info)

	# 자동 강화 — 켜면 목표 단계까지 이어서 두드린다
	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 6)
	side.add_child(auto_row)
	auto_button = _game._inv_button("자동 끔", toggle_auto)
	auto_button.custom_minimum_size.x = 110
	auto_row.add_child(auto_button)
	var room := Control.new()
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_row.add_child(room)
	auto_row.add_child(_game._inv_label("목표", 18, _game.INV_DIM))
	goal_down = _game._inv_button("−", step_goal.bind(-1))
	goal_down.custom_minimum_size.x = 44
	auto_row.add_child(goal_down)
	goal_label = _game._inv_label("", 20, _game.INV_GOLD_HI)
	goal_label.custom_minimum_size.x = 44
	goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	auto_row.add_child(goal_label)
	goal_up = _game._inv_button("+", step_goal.bind(1))
	goal_up.custom_minimum_size.x = 44
	auto_row.add_child(goal_up)

	# 방금 두드린 결과 — 성공은 금빛, 파괴는 붉게. 새로 열면 비운다
	result = _game._inv_label("", 20, _game.INV_GOLD_HI)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size = Vector2(0, 34)
	side.add_child(result)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	side.add_child(foot)
	go = _game._inv_button("강화", press)
	go.custom_minimum_size.x = GO_WIDTH
	foot.add_child(go)

	_game._close_button(panel, close, 0)


## 연다 — `where_index` 는 {where, index}. 탭은 "한 개", 자동은 끈 채로, 목표는 한 단계 위
func open(where_index: Dictionary) -> void:
	target = where_index.duplicate()
	var stack := _stack()
	ref = {"id": str(stack.get("id", "")), "grade": int(stack.get("grade", 1))}
	mode = "one"
	auto = false
	goal = mini(int(stack.get("enhance", 0)) + 1, Items.max_enhance())
	result.text = ""
	visible = true
	redraw()


func close() -> void:
	visible = false
	target = {}
	closed.emit()


func pick_mode(key: String) -> void:
	mode = key
	result.text = ""
	redraw()


func toggle_auto() -> void:
	auto = not auto
	redraw()


func step_goal(step: int) -> void:
	goal = clampi(goal + step, _goal_floor(), Items.max_enhance())
	redraw()


## 목표의 바닥 — 한 개는 지금 단계 + 1, 일괄은 +1 (대상마다 단계가 달라서)
func _goal_floor() -> int:
	if mode == "one":
		return mini(int(_stack().get("enhance", 0)) + 1, Items.max_enhance())
	return 1


func _stack() -> Dictionary:
	return _game._stack_at(target) if not target.is_empty() else {}


func _bag() -> Array:
	var me: Dictionary = _game._transport.snapshot().get("players", {}).get(_game._transport.my_id(), {})
	return me.get("bag", [])


## 일괄 대상 — 가방에서 `Items.batch_match` 에 드는 칸들. [[가방 번호, 칸], ...]
func batch_targets() -> Array:
	var cap := goal if auto else Items.max_enhance()
	var out: Array = []
	var bag := _bag()
	for index in bag.size():
		if Items.batch_match(bag[index], mode, str(ref.get("id", "")), int(ref.get("grade", 1)), cap):
			out.append([index, bag[index]])
	return out


## 팝업을 채운다. 탭 불빛 · 자동 줄 · 머리(이름·단계·큰 칸) · 표 · 단추
func redraw() -> void:
	for key in tabs:
		var on: bool = key == mode
		var tab: Button = tabs[key]
		tab.add_theme_color_override("font_color", _game.INV_GOLD_HI if on else _game.INV_DIM)
		tab.add_theme_color_override("font_hover_color", _game.INV_GOLD_HI if on else _game.INV_TEXT)
	goal = clampi(goal, _goal_floor(), Items.max_enhance())
	auto_button.text = "자동 켬" if auto else "자동 끔"
	auto_button.add_theme_color_override("font_color", _game.INV_GOLD_HI if auto else _game.INV_TEXT)
	goal_label.text = "+%d" % goal
	goal_label.add_theme_color_override("font_color", _game.INV_GOLD_HI if auto else _game.INV_DIM)
	goal_down.disabled = not auto or goal <= _goal_floor()
	goal_up.disabled = not auto or goal >= Items.max_enhance()
	kind.add_theme_color_override("font_color", _game.INV_GOLD_HI)
	if mode == "one":
		_redraw_one()
	else:
		_redraw_batch()


## 한 개 — 이름(등급 색) · `+N → +N+1`(자동이면 목표) · 성공률 · 실패 시 파괴 ·
## 기본 능력치가 지금 → 성공하면 얼마. **대상이 부서졌으면** 이름만 남기고 단추를 끈다
func _redraw_one() -> void:
	var stack := _stack()
	var item := Items.get_item(str(stack.get("id", "")))
	go.text = "자동 강화" if auto else "강화"
	if item.is_empty():
		kind.text = "부서졌습니다" if not target.is_empty() else "대상이 없습니다"
		kind.add_theme_color_override("font_color", _game.INV_WARN)
		_game._fill_cell(icon, {}, "", "")
		_game._fill_detail_rows([], info)
		go.disabled = true
		return

	var grade := int(stack.get("grade", 1))
	var enhance := int(stack.get("enhance", 0))
	title_line.text = str(item.get("name", "?"))
	if enhance > 0:
		title_line.text += " +%d" % enhance
	title_line.add_theme_color_override("font_color", _game._grade_tint(grade))
	_game._fill_cell(icon, stack, "", _game._item_icon(stack))

	var can := Items.can_enhance(enhance)
	go.disabled = not can
	if not can:
		kind.text = "최대 강화"
		_game._fill_detail_rows([["강화", "+%d (끝)" % enhance]], info)
		return

	# 확률은 설계 4장 그대로(90% → 10%). **유지가 없다** — 실패하면 무조건 파괴
	var to := goal if auto else enhance + 1
	kind.text = "+%d  →  +%d" % [enhance, to]
	var rows: Array = []
	if auto:
		rows.append(["목표 도달", _percent(Items.enhance_reach_odds(enhance, to))])
		rows.append(["다음 한 번", _percent(float(Items.enhance_odds(enhance).success))])
	else:
		rows.append(["성공률", _percent(float(Items.enhance_odds(enhance).success))])
	rows.append(["실패 시", "아이템 파괴", _game.INV_WARN])
	var now := Items.base_bonus(item, enhance)
	var next := Items.base_bonus(item, to)
	for key in _game.DETAIL_BONUS:
		if float(now.get(key, 0.0)) > 0.0:
			rows.append([
				_game.DETAIL_BONUS[key],
				"%s → %s" % [_game._bonus_text(key, float(now[key])), _game._bonus_text(key, float(next.get(key, 0.0)))],
			])
	if int(stack.get("count", 1)) > 1:
		rows.append(["겹친 칸", "한 개만 강화"])
	_game._fill_detail_rows(rows, info)


## 일괄 — 기준(같은 아이템이면 그 이름, 같은 등급이면 "N등급 장비") · 대상 수와 단계별 개수 ·
## 예상 성공 · 실패 시 파괴 · 끼고 있는 것은 빠진다
func _redraw_batch() -> void:
	var grade := int(ref.get("grade", 1))
	var item := Items.get_item(str(ref.get("id", "")))
	var face := {"id": str(ref.get("id", "")), "grade": grade}
	title_line.text = str(item.get("name", "?")) if mode == "item" else "%d등급 장비" % grade
	title_line.add_theme_color_override("font_color", _game._grade_tint(grade))
	_game._fill_cell(icon, face, "", _game._item_icon(face))

	var pieces := 0
	var hope := 0.0
	var levels := {}
	for pair in batch_targets():
		var stack: Dictionary = pair[1]
		var count := int(stack.get("count", 1))
		var at := int(stack.get("enhance", 0))
		pieces += count
		levels[at] = int(levels.get(at, 0)) + count
		hope += count * Items.enhance_reach_odds(at, goal if auto else at + 1)
	kind.text = ("전부  →  +%d" % goal) if auto else "한 단계씩"
	go.text = ("%d개 자동 강화" if auto else "%d개 강화") % pieces
	go.disabled = pieces == 0
	if pieces == 0:
		kind.text = "강화할 장비가 없습니다"
		kind.add_theme_color_override("font_color", _game.INV_DIM)
		_game._fill_detail_rows([["끼고 있는 것", "빠진다"]], info)
		return

	var spread: Array = []
	var keys := levels.keys()
	keys.sort()
	for at in keys:
		spread.append("+%d ×%d" % [int(at), int(levels[at])])
	_game._fill_detail_rows([
		["대상", "%d개" % pieces],
		["단계", " · ".join(spread)],
		["예상 성공", "약 %d개" % roundi(hope)],
		["실패 시", "아이템 파괴", _game.INV_WARN],
		["끼고 있는 것", "빠진다"],
	], info)


func _percent(odds: float) -> String:
	if odds >= 0.1:
		return "%d%%" % roundi(odds * 100.0)
	return "%.1f%%" % (odds * 100.0)


## "강화" — 한 개는 enhanceItem, 일괄은 enhanceBatch. 결과 글자는 판정이 낸 이벤트로 채운다
## (`show_result`). **대상은 결과를 따라간다** — 부서지면 비우고, 겹친 칸에서 뗀 것이 오르면
## 바로 뒤 칸(뗀 것)으로 옮긴다. 일괄 뒤에는 가방 번호가 흔들려서 한 개 대상도 비운다
func press() -> void:
	result.text = ""
	if mode != "one":
		var targets := batch_targets()
		if targets.is_empty():
			return
		_game._transport.send(&"enhanceBatch", {
			"mode": mode, "id": str(ref.id), "grade": int(ref.grade), "goal": goal if auto else -1,
		})
		if str(target.get("where", "")) != "equip":
			target = {}
		acted.emit(false, 0)
		redraw()
		return

	var stack := _stack()
	if Items.get_item(str(stack.get("id", ""))).is_empty():
		return
	var level := int(stack.get("enhance", 0))
	_pressed_count = int(stack.get("count", 1))
	var goal_sent := goal if auto else -1
	if str(target.where) == "equip":
		var slot := str(Items.slots()[int(target.index)])
		_game._transport.send(&"enhanceItem", {"where": "equip", "key": slot, "goal": goal_sent})
		acted.emit(not _stack().is_empty(), 0)
	else:
		var before := _bag().size()
		_game._transport.send(&"enhanceItem", {"where": "bag", "key": int(target.index), "goal": goal_sent})
		var after := _bag().size()
		if after < before:
			target = {}
			acted.emit(false, 0)
		elif after > before:
			target.index = int(target.index) + 1
			acted.emit(true, 1)
		else:
			acted.emit(int(_stack().get("enhance", 0)) > level, 0)
	redraw()


## 판정의 결과 이벤트(enhanceResult · enhanceBatch)를 결과 한 줄로
func show_result(type: StringName, payload: Dictionary) -> void:
	if not visible:
		return
	var good: bool
	if type == &"enhanceBatch":
		var reached: Dictionary = payload.get("reached", {})
		var keys := reached.keys()
		keys.sort()
		var kept: Array = []
		for at in keys:
			kept.append("+%d ×%d" % [int(at), int(reached[at])])
		result.text = "%d개 중 %d개 성공 · %d개 파괴" % [
			int(payload.pieces), int(payload.success), int(payload.destroyed)
		]
		if not kept.is_empty():
			result.text += "\n남은 것 " + " · ".join(kept)
		good = int(payload.success) > 0
	else:
		var level := int(payload.get("level", 0))
		var tries := int(payload.get("tries", 1))
		match str(payload.get("result", "")):
			"success":
				result.text = ("자동 강화 성공!  +%d  (%d번)" % [level, tries]) if payload.get("auto", false) \
					else "강화 성공!  +%d" % level
				good = true
			"destroy":
				var what := "하나가 부서졌습니다" if _pressed_count > 1 else "부서졌습니다"
				result.text = ("+%d 에서 %s  (%d번)" % [level, what, tries]) if payload.get("auto", false) \
					else "강화 실패 — %s" % what
				good = false
			_:
				result.text = "유지  +%d" % level
				good = true
	result.add_theme_color_override("font_color", _game.INV_GOLD_HI if good else _game.INV_WARN)
	redraw()
