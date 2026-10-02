class_name GatePanel
extends PanelContainer

## 차원문 창 — 어디로 갈지 고르는 목록. **그림 한 장이 아니라 조각을 조립한다** (CLAUDE.md):
##
##   창 바탕(ui_panel, 9조각) ─ 여백 ─┬─ 제목 · 닫기(ui_close)
##                                    └─ 스크롤 ─ 줄마다 [칸 아이콘][존 이름]
##
## **조각은 가방창·스킬창과 같은 것을 쓴다** (2026-09-20 요청: "스타일도 다른 UI와
## 아트풍 비슷하게"). 그림을 여는 것은 `game.gd` 의 `_frame_box`·`_icon` 이므로
## `create` 가 그 둘을 받아 온다 — 같은 로더를 두 벌 두지 않으려는 것이다
## ([hud.md](../../docs/features/hud.md) 의 "조각으로 조립한다")
##
## 칸 아이콘은 둘이다 — 지금 서 있는 곳은 소용돌이(gate_here), 갈 수 있는 곳은 별(gate_go).
## 자리는 **앵커로만** 잡는다: 가로는 가운데 고정 폭, 세로는 화면 높이의 비율이라
## 해상도가 바뀌어도 줄 수만 달라지고 모양은 그대로다 (docs/features/portal-ui.md)

signal picked(zone_id: String)

## 창 폭(기준 해상도 1280×720 의 px). 높이는 화면 위아래 ANCHOR_Y 만큼 비운 나머지
const WIDTH := 520.0
const ANCHOR_Y := 0.06
## 바탕 그림의 9분할 여백 — 256px 그림의 테두리가 약 7px 이다 (scripts/build-ui.mjs)
const PATCH := 12
## 테두리 안쪽 여백
const PAD := 26
## 칸 아이콘 한 변과 줄 사이
## 칸 아이콘 한 변. **틀 안에 들어가는 크기여야 한다** — 60 으로 두었더니 줄
## 높이(64)에서 위아래 여백을 빼고 남는 48 을 넘어 **금테 밖으로 삐져나왔다**
## (2026-09-21 지적)
const ICON := 40
const ROW_GAP := 6
const FONT_SIZE := 30
const TEXT_COLOR := Color("#f2f2f2")
## 지금 서 있는 곳은 누를 수 없고 흐리게 (참고 그림의 맨 윗줄)
const HERE_COLOR := Color("#8c8c8c")

## **조각은 다른 창과 같은 것을 쓴다** (2026-09-20 요청: "스타일도 다른 UI와
## 아트풍 비슷하게"). 기본 단추(회색 네모)를 그대로 쓰면 이 창만 사무용 UI 로
## 보인다. 이름과 9조각 여백은 `game.gd` 의 가방창·스킬창이 쓰는 값 그대로다
## ([hud.md](../../docs/features/hud.md) 의 "조각 여덟 장")
const PANEL_MARGIN := 26
const BUTTON_MARGIN := 28
## 줄 안쪽 여백
## 줄 안쪽 여백. 가로는 **금테 굵기보다 넉넉히** 준다 — 좁으면 아이콘이 테 위에 올라탄다
const ROW_PAD := 10
const ROW_PAD_X := 20
## **누르면 내용이 이만큼 내려앉는다.** 색만 바뀌면 눌렸는지 눈에 안 들어온다
const ROW_SINK := 3
## 누른 동안 틀을 이만큼 밝힌다 (금테가 달아오른다)
const PRESS_TINT := Color(1.45, 1.3, 1.0)
## 닫기 X 한 변 — 다른 창과 같다 (game.gd 의 CLOSE_BTN)
const CLOSE_BTN := 44
## 제목 금색·가르는 금 — 경험치 막대와 같은 금색이다
const TITLE_COLOR := Color("#e8c14a")
const HEAD_LINE := Color("#4a412b")

## ── 던전 결 (2026-09-28) ── 던전 창에서 굳힌 결을 **모든 창이 같이 쓴다** ("나머지 창들도 던전 UI
## 아트풍으로"). 던전 창이 이 창을 물려받으므로 여기에 둔다 → docs/features/ui-art-style.md "던전 결"
## 카드 틀(`ui_dungeon_card`, 231x384) 의 9조각 여백. 안쪽 판이 가장자리에서 26~36px 들어가 있다
const CARD_MARGIN := 34
## 틀 안쪽 판 색(#1b1c17) — 창 뒤에 까는 불투명한 판, 풍경이 녹아드는 색
const CARD_DARK := Color("#1b1c17")
## 칸 제목 · 부제의 옅은 금빛
const CARD_SUB_COLOR := Color("#c9b98a")
## 고른 줄 · 구분선의 금빛
const CARD_GOLD := Color("#dfc97a")
## 단추 글자 — 청록 돌판 단추(`ui_button`, 2026-09-29) 위의 **주황빛 금 + 검은 테**.
## 받은 단추 그림("인챈트")의 글자에서 뽑은 값이다. 옅은 `CARD_GOLD` 는 청록 위에서 묻혔다
const BUTTON_TEXT := Color("#f8c878")
const BUTTON_OUTLINE := Color("#141816")
const BUTTON_OUTLINE_SIZE := 4


## 단추 글자를 받은 그림 결로 칠한다 (`BUTTON_TEXT` + 검은 테). 막힌 단추는 회색.
## 누름·뗌·클릭 움직임(`ButtonFx`)도 여기서 붙인다 — 청록 단추는 대부분 이 길을 지난다
static func paint_button_text(button: Button, size: int) -> Button:
	ButtonFx.attach(button)
	for key in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, BUTTON_TEXT)
	button.add_theme_color_override("font_disabled_color", HERE_COLOR)
	button.add_theme_color_override("font_outline_color", BUTTON_OUTLINE)
	button.add_theme_constant_override("outline_size", BUTTON_OUTLINE_SIZE)
	button.add_theme_font_size_override("font_size", size)
	return button


## 제목 글자 — 노란 제목(`TITLE_COLOR`) 대신 상아빛 (받은 던전 그림의 제목 결)
const PAGE_TITLE_COLOR := Color("#ece4cc")
const PAGE_TITLE_SIZE := 32
## 제목 왼쪽 문장 한 변
const EMBLEM := 44
## 칸 판 — 어둡고 테가 가늘다
const CELL_BG := Color(0.1, 0.1, 0.09, 0.78)
const CELL_LINE := Color("#3d3729")
## 끌기로 치는 최소 거리(px). 이만큼 움직이면 고르기가 아니라 스크롤이다
const DEADZONE := 14
## 스크롤 막대 굵기 — 손가락으로 집을 수 있어야 한다 (기본은 폰에서 너무 가늘다)
const BAR_WIDTH := 18
## 줄 끝 느낌표 배지 한 변 · 누르는 자리를 배지 밖으로 넓히는 폭
const INFO := 36
const INFO_REACH := 8
## 추천 레벨 글자 크기와 느낌표와의 틈
const LEVEL_FONT := 22
const LEVEL_GAP := 14

var _rows: VBoxContainer
## 제목 — 던전 창(`DungeonPanel`)이 고른 종류 이름으로 바꿔 단다
var _title: Label
var _scroll: ScrollContainer
var _here_icon: Texture2D
var _go_icon: Texture2D
## 끌기 — 누른 자리(창 기준 세로), 누를 때의 스크롤, 데드존을 넘겼나
var _hold := false
var _hold_y := 0.0
var _hold_scroll := 0
var _dragging := false
## 지금 눌려 있는 줄 (뗄 때까지 밝은 틀로 둔다)
var _held: Button = null
## 누르고 있는 느낌표 배지 — 뗄 때 같은 배지 위면 드랍 창을 연다
var _info_held: Control = null
## 사냥터 드랍 창 — 느낌표를 처음 누를 때 만든다 (던전 창은 물려받아도 안 쓴다)
var drops: DropPanel = null
## 조각을 여는 `game.gd` 의 손 — `_frame_box(이름, 9조각 여백, 안쪽 여백)` · `_icon(이름)`
var _frame_box := Callable()
var _icon := Callable()


## `frame_box(이름, 9조각 여백, 안쪽 여백)` 과 `icon(이름)` 은 `game.gd` 것을 받는다.
## 안 주면(테스트에서 창만 띄울 때) 코드로 그린 틀로 물러선다
static func create(frame_box := Callable(), icon := Callable()) -> GatePanel:
	var panel := GatePanel.new()
	panel._frame_box = frame_box
	panel._icon = icon
	panel._build()
	return panel


func _build() -> void:
	name = "GatePanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = ANCHOR_Y
	anchor_bottom = 1.0 - ANCHOR_Y
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = 0.0
	offset_bottom = 0.0

	# 던전 창과 같은 닳은 돌판이다 (2026-09-28). 안쪽 판이 테에서 26~36px 들어가 있어 조금 더 물린다
	add_theme_stylebox_override("panel", _box("ui_dungeon_card", CARD_MARGIN, PAD + 4))
	# 줄 아이콘 — 다른 UI 와 같은 결의 조각이다 (상아빛 문장, 판 없음).
	# 파란 타일(`assets/ui/gate_*.png`)을 쓰다가 **금빛 창과 결이 달라** 다시 뽑았다
	# (2026-09-21) → docs/features/ui-art-style.md
	_here_icon = _piece("ui_gate_here")
	_go_icon = _piece("ui_gate_go")

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_restyle_title(_title, "차원문", "ui_gate_go")
	# 닫기는 다른 창과 같은 X 조각이다 (그림이 없으면 글자 X)
	var close := Button.new()
	close.name = "Close"
	close.custom_minimum_size = Vector2(CLOSE_BTN, CLOSE_BTN)
	close.expand_icon = true
	close.icon = _piece("ui_close")
	if close.icon == null:
		close.text = "X"
	close.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	close.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	close.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	close.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close.pressed.connect(close_panel)
	head.add_child(close)

	# 제목과 목록을 가르는 금
	var line := ColorRect.new()
	line.color = HEAD_LINE
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# **끌어서 내린다** (2026-09-18 요청: "UI 스크롤이 마우스 휠로만 되는데,
	# 클릭해서 내릴 수 있게"). 엔진에도 끌기가 있지만 **터치 화면일 때만** 켜지고,
	# 그러면 폰에서는 손가락 이벤트와 흉내 낸 마우스 이벤트가 겹쳐 두 배로 내려간다.
	# 그래서 목록에 오는 입력을 여기서 직접 받는다 (`_on_list_input`)
	_scroll.gui_input.connect(_on_list_input)
	_scroll.get_v_scroll_bar().custom_minimum_size.x = BAR_WIDTH
	column.add_child(_scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", ROW_GAP)
	_scroll.add_child(_rows)


## 연다. 지금 서 있는 존을 알아야 그 줄을 흐리게 막는다
func open(current_zone: String) -> void:
	_close_drops()
	_fill(current_zone)
	_scroll.scroll_vertical = 0
	_forget_hold()
	visible = true


func close_panel() -> void:
	_forget_hold()
	_close_drops()
	visible = false


## 사냥터 드랍 창을 연다 (줄 끝 느낌표). 판정이 굴리는 것 그대로다 → `DropPanel`
func show_drops(zone_id: String) -> void:
	if drops == null:
		drops = DropPanel.make(_box, _piece)
		add_child(drops)
	drops.show_zone(zone_id)


func _close_drops() -> void:
	if drops != null:
		drops.close_panel()


## 누르던 것을 잊는다 — 창을 여닫는 사이에 손을 뗐을 수 있다
func _forget_hold() -> void:
	_hold = false
	_dragging = false
	_press(null)
	_hold_info(null)


## 줄 수 (테스트용)
func row_count() -> int:
	return _rows.get_child_count()


func row(i: int) -> Button:
	return _rows.get_child(i) as Button


## 마을 + 사냥터 20곳. 순서는 데이터가 정한다 (zones.json 의 fieldOrder).
## **목록 맨 위가 마을이다** — 돌아가는 길을 매번 훑지 않게 (world-zones.md)
func _fill(current_zone: String) -> void:
	_clear_rows()
	var ids: Array = [GameData.start_zone()]
	ids.append_array(GameData.field_order())
	for id in ids:
		var here := str(id) == current_zone
		var row := _add_row(str(GameData.zone(str(id)).get("name", id)), str(id), here, _here_icon if here else _go_icon)
		# 사냥터 줄 끝에 느낌표 — 누르면 그 사냥터의 드랍 (마을은 떨어지는 것이 없다)
		if str(id) != GameData.start_zone():
			_add_level(row, str(id))
			_add_info(row)


## 느낌표 왼쪽의 추천 레벨 (2026-10-02 요청: "사냥터에 추천 레벨 적어두고").
## 그 사냥터 몬스터의 레벨이다 — 밸런스가 "같은 레벨 몬스터 한 마리 4초" 기준이라(`balance.ts` `KILL_SECONDS`).
## 몬스터 레벨이 여럿이면 가장 낮은 것. 줄은 입력을 안 받으니 이것도 받지 않는다
func _add_level(row: Button, zone_id: String) -> void:
	var levels = Items.zone_drops(zone_id).get("levels")
	if levels == null:
		return
	var label := Label.new()
	label.name = "Level"
	label.text = "추천 Lv.%d" % (levels as Vector2i).x
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", LEVEL_FONT)
	label.add_theme_color_override("font_color", HERE_COLOR if row.disabled else CARD_SUB_COLOR)
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0
	label.anchor_bottom = 1.0
	label.offset_right = -ROW_PAD_X - INFO - LEVEL_GAP
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_child(label)


## 줄 오른쪽 끝의 느낌표 배지 (2026-09-30 요청: "각 사냥터별로 느낌표 눌러서, 드랍되는 아이템
## 표시"). 그림이 아니라 둥근 판 + `Label` 이다 — 글자는 그림에 굽지 않는다. 줄처럼 입력을
## 받지 않고, 누름은 목록이 `_info_at` 으로 가른다. 서 있는 곳(막힌 줄)에도 단다
func _add_info(row: Button) -> void:
	var badge := PanelContainer.new()
	badge.name = "Info"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := StyleBoxFlat.new()
	disc.bg_color = Color(0.08, 0.08, 0.07, 0.9)
	disc.border_color = CARD_GOLD
	disc.set_border_width_all(2)
	disc.set_corner_radius_all(INFO)
	badge.add_theme_stylebox_override("panel", disc)
	var mark := Label.new()
	mark.text = "!"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", INFO - 14)
	mark.add_theme_color_override("font_color", BUTTON_TEXT)
	mark.add_theme_color_override("font_outline_color", BUTTON_OUTLINE)
	mark.add_theme_constant_override("outline_size", 3)
	badge.add_child(mark)
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 0.5
	badge.anchor_bottom = 0.5
	badge.offset_left = -ROW_PAD_X - INFO
	badge.offset_right = -ROW_PAD_X
	badge.offset_top = -INFO * 0.5
	badge.offset_bottom = INFO * 0.5
	row.add_child(badge)


## 그 자리의 느낌표 배지 (없으면 null). 손가락이 작은 배지를 비껴도 잡히게 `INFO_REACH` 만큼 넓혀 본다.
## 막힌 줄(서 있는 곳)도 본다 — 갈 수는 없어도 드랍은 볼 수 있다
func _info_at(at: Vector2) -> Control:
	var point := _scroll.global_position + at
	for child in _rows.get_children():
		var badge := child.get_node_or_null("Info") as Control
		if badge != null and badge.get_global_rect().grow(INFO_REACH).has_point(point):
			return badge
	return null


## 누르는 배지를 달군다 (null 이면 지운다)
func _hold_info(badge: Control) -> void:
	if _info_held != null and is_instance_valid(_info_held):
		_info_held.modulate = Color.WHITE
	_info_held = badge
	if badge != null:
		badge.modulate = PRESS_TINT


func _clear_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


## 줄 하나. `key` 는 고르면 `_on_pick` 에 넘어가는 값이고, `blocked` 면 흐리게 막는다.
## 던전 창(`DungeonPanel`)도 이것으로 줄을 단다 — 틀·누름·끌기가 차원문과 같아야 해서다
func _add_row(text: String, key: String, blocked: bool, row_icon: Texture2D) -> Button:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = text
	button.icon = row_icon
	button.add_theme_constant_override("icon_max_width", ICON)
	button.add_theme_constant_override("h_separation", 22)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_disabled_color", HERE_COLOR)
	# **줄 하나가 칸 하나다.** 검푸른 바탕에 푸른 테 — 누르면 `_press` 가
	# 밝은 틀로 바꿔 끼운다 (`normal` 을 갈아 끼운다: 이 단추는 입력을 안 받아
	# 고도의 pressed 상태가 오지 않는다)
	if blocked:
		var dim := _row_box(false)
		button.add_theme_stylebox_override("disabled", dim)
	else:
		button.add_theme_stylebox_override("normal", _row_box(false))
	button.custom_minimum_size = Vector2(0, ICON + ROW_PAD * 2)
	button.disabled = blocked
	# **줄은 입력을 받지 않는다.** 누른 것이 고르기인지 끌기인지는 목록 쪽에서
	# 판정한다 — 줄이 먼저 받으면 끌다가 손을 뗀 자리의 줄로 떠나 버린다
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.set_meta("zone", key)
	_rows.add_child(button)
	return button


## 목록에 온 입력. **누르고 끌면 스크롤, 누르고 그 자리에서 떼면 고르기**다.
##
## 휠은 건드리지 않고 `ScrollContainer` 에 그대로 넘긴다 (`accept_event` 를 안 부른다).
## 손가락 이벤트도 넘기지 않고 **삼킨다** — 고도는 기본으로 같은 손짓을 마우스로도
## 흉내 내 보내므로(`emulate_mouse_from_touch`), 둘 다 받으면 두 배로 내려간다
func _on_list_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		accept_event()
		return
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		# 줄 끝 느낌표 — 줄 고르기보다 먼저 본다. 누른 배지에서 떼면 드랍 창
		if click.pressed and _info_at(click.position) != null:
			_hold_info(_info_at(click.position))
			accept_event()
			return
		if not click.pressed and _info_held != null:
			var badge := _info_held
			_hold_info(null)
			if badge == _info_at(click.position):
				show_drops(str(badge.get_parent().get_meta("zone", "")))
			accept_event()
			return
		if click.pressed:
			_hold = true
			_dragging = false
			_hold_y = click.position.y
			_hold_scroll = _scroll.scroll_vertical
			# 누른 줄을 **눌린 틀**로 바꾼다
			_press(_row_at(click.position))
		elif _hold:
			_hold = false
			var row_under := _row_at(click.position)
			var held := _held
			_press(null)
			# 누른 줄에서 뗐을 때만 고른다 — 다른 줄로 미끄러졌으면 취소다
			if not _dragging and held != null and held == row_under:
				_on_pick(str(held.get_meta("zone", "")))
		accept_event()
		return
	var move := event as InputEventMouseMotion
	if move != null and _hold:
		var moved := move.position.y - _hold_y
		if not _dragging and absf(moved) > DEADZONE:
			_dragging = true
			# 끌기 시작 = 고르기 취소. 눌린 자국을 지운다
			_press(null)
		if _dragging:
			# 손을 따라간다 — 위로 끌면 목록이 올라온다. 범위는 고도가 죈다
			_scroll.scroll_vertical = _hold_scroll - int(moved)
			accept_event()


## 그 자리의 줄. **줄 전체가 누르는 자리다** (2026-09-20 요청: "해당 라인을 전체
## 클릭 영역으로") — 가로는 따지지 않고(목록 안이면 다 그 줄이다) 세로만 본다.
## 줄 사이 틈(ROW_GAP)도 가까운 줄에 붙여 준다. `at` 은 목록 기준이라 화면
## 기준으로 옮겨서 견준다 (줄은 스크롤만큼 밀려 있다)
func _row_at(at: Vector2) -> Button:
	var y: float = _scroll.global_position.y + at.y
	for child in _rows.get_children():
		var button := child as Button
		if button == null or button.disabled:
			continue
		var box := button.get_global_rect()
		if y >= box.position.y - ROW_GAP * 0.5 and y <= box.end.y + ROW_GAP * 0.5:
			return button
	return null


## 눌린 틀로 바꿔 끼운다. `row` 가 null 이면 눌린 자국을 지운다.
## 누름을 **보이게** 하는 자리다 (2026-09-20 요청: 누를 때와 뗄 때가 달라야 한다)
func _press(row: Button) -> void:
	if _held == row:
		return
	if _held != null and is_instance_valid(_held):
		_held.add_theme_stylebox_override("normal", _row_box(false))
	_held = row
	if _held != null:
		_held.add_theme_stylebox_override("normal", _row_box(true))


## 목록 줄 — 던전 단계 창처럼 **평평한 줄**이다 (2026-09-28 에 차원문 창도 이리로). 둥근 금테
## 단추(`ui_button`)를 쓰면 목록이 단추 더미로 보였다 (던전 창에서 찍어서 봤다). 아래에 가는
## 선 하나, 고른(누른) 줄만 바탕이 밝아지고 왼쪽에 금 막대가 선다
func _row_box(pressed: bool) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.75, 0.45, 0.14) if pressed else Color(0, 0, 0, 0)
	box.border_color = CARD_GOLD if pressed else CELL_LINE
	box.border_width_left = 3 if pressed else 0
	box.border_width_bottom = 1
	box.content_margin_left = ROW_PAD_X
	box.content_margin_right = ROW_PAD_X
	box.content_margin_top = ROW_PAD
	box.content_margin_bottom = ROW_PAD
	return box


## 제목을 던전 결로 — 왼쪽에 문장(`emblem_name`), 상아빛 글자
func _restyle_title(label: Label, text: String, emblem_name: String) -> void:
	label.text = text
	label.add_theme_color_override("font_color", PAGE_TITLE_COLOR)
	label.add_theme_font_size_override("font_size", PAGE_TITLE_SIZE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var emblem := TextureRect.new()
	emblem.name = "Emblem"
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.texture = _piece(emblem_name)
	emblem.custom_minimum_size = Vector2(EMBLEM, EMBLEM)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.visible = emblem.texture != null
	var head := label.get_parent()
	head.add_child(emblem)
	head.move_child(emblem, label.get_index())
	(head as BoxContainer).add_theme_constant_override("separation", 12)


## 단추 한 칸의 틀 — 단추 조각(`ui_button`) 그대로다 (던전 창의 입장 단추). 누르면 **밝게
## 달아오르고 내용이 `ROW_SINK` 만큼 내려앉는다.** 조각이 없으면 코드로 그린 틀로 물러선다
func _button_box(pressed: bool) -> StyleBox:
	var box := _box("ui_button", BUTTON_MARGIN, ROW_PAD)
	box.content_margin_left = ROW_PAD_X
	box.content_margin_right = ROW_PAD_X
	var sink: int = ROW_SINK if pressed else 0
	box.content_margin_top = ROW_PAD + sink
	box.content_margin_bottom = maxf(ROW_PAD - sink, 0.0)
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = PRESS_TINT if pressed else Color.WHITE
	elif box is StyleBoxFlat:
		var flat := box as StyleBoxFlat
		flat.bg_color = flat.bg_color.lightened(0.25) if pressed else flat.bg_color
		flat.border_color = PRESS_TINT if pressed else flat.border_color
	return box


## 조각으로 만든 틀. `game.gd` 의 `_frame_box` 를 그대로 부르고,
## 안 받았으면(테스트에서 창만 띄울 때) 코드로 그린 판을 준다
func _box(name: String, margin: int, content: int) -> StyleBox:
	if _frame_box.is_valid():
		return _frame_box.call(name, margin, content)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.05, 0.06, 0.08, 0.94)
	flat.border_color = Color(0.72, 0.82, 0.95)
	flat.set_border_width_all(2)
	flat.set_corner_radius_all(8)
	flat.set_content_margin_all(content)
	return flat


## 조각 그림 한 장 (`game.gd` 의 `_icon`). 없으면 null
func _piece(name: String) -> Texture2D:
	return _icon.call(name) if _icon.is_valid() else null


func _on_pick(zone_id: String) -> void:
	visible = false
	picked.emit(zone_id)

