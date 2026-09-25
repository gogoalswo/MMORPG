class_name EnhancePopup
extends Control

## 강화 팝업 — 상세 창 "강화" 로 연다. **화면 가운데에 뜨고 뒤를 어둡게 덮는다** — 덮은 막이
## 뒤 창을 못 누르게 막아서, 떠 있는 동안 대상이 바뀔 일이 없다.
##
## 오기까지 (2026-09-23 ~ 24):
## 1. "상세 정보창 누르면 강화 버튼 나오게 해" → 상세 창 단추가 바로 굴렸다
## 2. "강화 ui창을 따로 만들어. 강화 버튼 누르면 팝업이 나오게" → game.gd 안의 팝업
## 3. "아이템 강화 팝업을 따로 만들어 … 여러 개 한 번에 … 목표치 자동 강화" → 이 파일
## 4. "한 단계씩 연출 넣어" → 자동은 타이머가 한 단계씩 보내고 "중지" 로 멈춘다
## 5. 리니지M "다중 강화" 그림 + "다중강화 ui를 이런식으로" → 지금 모양
##
##   ┌ 장비 강화 ────────────── X ┐ ┌ 같은 아이템 │ 같은 등급 │ 전체 ┐
##   │ [단일 강화] [다중 강화]      │ │ ▢ ▢ ▢ ▢                         │
##   │ 안내 · 담은 칸 7×2            │ │ ▢ ▢ ▢ ▢   ← 누르면 왼쪽에 담긴다 │
##   │ 강화 정보 표                  │ │ …                               │
##   │ ≫+1≫+2≫ … ≫+9  ← 목표        │ │ 담은 것 3/14   [모두 담기][비우기]│
##   │ 결과 한 줄        [다중 강화] │ └─────────────────────────────────┘
##   └──────────────────────────────┘   (오른쪽 창은 다중 강화 탭에서만)
##
## 단일 강화 — 연 장비 하나. "강화" 는 한 단계, "자동 강화" 는 목표까지 한 단계씩.
## 다중 강화 — 오른쪽 목록에서 담은 칸들을 **목표까지 한 바퀴씩**(칸마다 한 번) 되풀이한다.
## 끼고 있는 것은 목록에 안 나온다 (판정도 가방 번호만 받는다).
## 요청: enhanceItem {where, key} · enhanceMany {indices, cap}. **한 요청 = 한 번**이라
## "중지" 가 그 자리에서 정말 멈춘다. 판정이 돌려준 새 가방 번호(`picked`)로 담은 칸을 이어 간다.
##
## 틀·조각(`_window_panel`·`_make_cell`·`_fill_detail_rows` …)은 game.gd 것을 빌린다 —
## 상세 창과 같은 결이어야 해서다. 스냅샷도 game 의 `_transport` 에서 읽는다.
## → docs/features/items.md "강화"

const TABS := ["one", "multi"]
const TAB_TEXT := {"one": "단일 강화", "multi": "다중 강화"}
const FILTERS := ["item", "grade", "all"]
const FILTER_TEXT := {"item": "같은 아이템", "grade": "같은 등급", "all": "전체"}
## 왼쪽 창 안쪽 폭 — 화살표 아홉 개와 담은 칸 일곱이 한 줄에 들어간다
const WIDTH := 440
## 담는 칸 — 받은 그림처럼 7 × 2
const MULTI_MAX := 14
const MULTI_COLS := 7
const MULTI_CELL := 56
## 오른쪽 목록
const LIST_COLS := 4
const LIST_CELL := 70
const LIST_HEIGHT := 380
const GO_WIDTH := 170
const GUIDE := "강화할 아이템과 강화 단계를 선택해 주세요."

## 한 개를 두드리고 나면 — 대상이 남았나(kept), 가방 번호가 몇 칸 밀렸나(shift).
## 다중 뒤에는 가방 번호가 통째로 흔들려서 kept=false 로 알린다 (고른 칸을 비워야 한다)
signal acted(kept: bool, shift: int)
signal closed
## 자동 강화 한 판이 끝났다 — game 이 채팅창에 한 줄 적는다 (단계마다 적으면 채팅이 덮인다)
signal finished(head: String, text: String, good: bool)

var panel: PanelContainer
var list_panel: PanelContainer
var tabs: Dictionary = {}
var filters: Dictionary = {}
var one_box: Control
var multi_box: Control
var title_line: Label
var kind: Label
var icon: PanelContainer
var info: GridContainer
var chevrons: Array = []
var result: Label
## 단일: 한 단계 "강화"
var go: Button
## 단일: "자동 강화" · 다중: "N개 강화" · 도는 동안 "중지"
var run_button: Button
var picked_grid: GridContainer
var list_grid: GridContainer
var list_drag: DragScroll
var list_head: Label
## 목록 아래 "모두 담기" · "비우기" — 다중에서만 보인다
var list_foot_buttons: Array = []

var mode := "one"
var filter := "item"
var goal := 1
## 단일 대상 — {where: "bag"|"equip", index: 가방 번호 | 슬롯 번호}
var target: Dictionary = {}
## 목록 기준 — **고른 장비**의 id·등급 (단일은 대상, 다중은 처음 담은 것). 비었으면 거르지 않는다.
## 한 개가 부서져도 남는다
var ref: Dictionary = {}
## 다중 강화에 담은 칸 — 가방 번호. 판정의 `picked` 로 이어 간다
var picked: Array = []
## 오른쪽 목록 칸 k 가 가리키는 가방 번호
var _list_view: Array = []
var _list_cells: Array = []

var _game  # game.gd — class_name 이 없어서 이름 없이 든다
## 누른 순간 대상 칸의 개수 — 결과 글자 "하나가 부서졌습니다" 에 쓴다
var _pressed_count := 1
## 자동 강화가 도는 중인가 — 단추가 "중지" 가 되고, 탭·목표·목록은 잠긴다
var running := false
## 한 단계 사이(초) — 2026-09-24 "1초마다". 슬라이드·반짝임·깨짐이 한 박자 안에 끝난다.
## 테스트가 줄인다
var step_time := 1.0
## 칸 연출(`EnhanceFx`)을 얹는 층 — 팝업 맨 위, 누르기를 안 막는다
var fx_layer: Control
## 한 단계를 보내기 직전의 아이콘 — 깨지는 조각이 이 그림을 자른다. 칸 k → [그림, 화면 자리]
var _slot_tex: Dictionary = {}
var _one_tex: Array = []
var _timer: Timer
## 도는 한 판의 셈 — {steps, from, last, pieces, destroyed}
var _run: Dictionary = {}
## 다중 한 바퀴를 보내고 판정의 새 번호(`picked`)를 기다리는 중 — 그사이 담은 칸 번호는 낡았다
var _waiting := false


## 목표 띠의 화살표 하나 — 받은 그림처럼 **왼쪽이 파이고 오른쪽이 뾰족한** 조각.
## 목표까지는 금빛, 너머는 어둡게. 그림 없이 다각형으로 그린다 (조각을 코드로 조립)
class Chevron extends Control:
	signal chosen(level: int)
	const LIT := Color("#d9a63a")
	const LIT_EDGE := Color("#f1dc9c")
	const DARK := Color("#221f1a")
	const DARK_EDGE := Color("#4a4234")
	const DONE := Color("#5c4a2a")
	var level := 1
	var lit := false
	## 이미 지난 단계(단일 강화의 지금 단계 이하) — 흐리고 눌리지 않는다
	var done := false

	func _init(n: int) -> void:
		level = n
		name = "chevron%d" % n
		custom_minimum_size = Vector2(46, 34)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		var mouse := event as InputEventMouseButton
		if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and not done:
			chosen.emit(level)
			accept_event()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var notch := h * 0.32
		var points := PackedVector2Array([
			Vector2(0, 0), Vector2(w - notch, 0), Vector2(w, h * 0.5),
			Vector2(w - notch, h), Vector2(0, h), Vector2(notch, h * 0.5),
		])
		var fill := DONE if done else (LIT if lit else DARK)
		draw_colored_polygon(points, fill)
		var edge := points.duplicate()
		edge.append(points[0])
		draw_polyline(edge, LIT_EDGE if lit else DARK_EDGE, 1.5, true)
		var font := get_theme_default_font()
		var text := "+%d" % level
		var font_size := 16
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var ink := Color("#2b1a08") if lit and not done else Color("#948c7a")
		draw_string(
			font, Vector2((w - width) * 0.5 + notch * 0.25, h * 0.5 + font_size * 0.36),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink
		)


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
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 12)
	center.add_child(pair)
	panel = _game._window_panel()
	panel.visible = true
	pair.add_child(panel)
	list_panel = _game._window_panel()
	pair.add_child(list_panel)

	_build_left()
	_build_list()
	_game._close_button(panel, close, 0)

	fx_layer = Control.new()
	fx_layer.name = "FxLayer"
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)

	_timer = Timer.new()
	_timer.name = "StepTimer"
	_timer.timeout.connect(_on_tick)
	add_child(_timer)


## 왼쪽 창 — 머리 줄 · 탭 · (단일) 대상 머리 / (다중) 안내와 담은 칸 · 정보 표 · 목표 띠 ·
## 결과 한 줄 · 단추
func _build_left() -> void:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(WIDTH, 0)
	side.add_theme_constant_override("separation", 8)
	panel.add_child(side)

	_game._window_title(side, "장비 강화", 22)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	side.add_child(row)
	for key in TABS:
		var tab: Button = _game._inv_button(TAB_TEXT[key], pick_mode.bind(key))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tab)
		tabs[key] = tab

	# 단일 — 대상 이름·단계와 큰 칸
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	side.add_child(head)
	one_box = head
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

	# 다중 — 안내 한 줄과 담은 칸 7 × 2. 담은 칸을 누르면 뺀다
	var multi := VBoxContainer.new()
	multi.add_theme_constant_override("separation", 8)
	side.add_child(multi)
	multi_box = multi
	var guide: Label = _game._inv_label(GUIDE, 18, _game.INV_TEXT)
	guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	multi.add_child(guide)
	picked_grid = GridContainer.new()
	picked_grid.columns = MULTI_COLS
	picked_grid.add_theme_constant_override("h_separation", 6)
	picked_grid.add_theme_constant_override("v_separation", 6)
	picked_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	multi.add_child(picked_grid)
	for k in MULTI_MAX:
		var slot: PanelContainer = _game._make_cell(unpick_slot.bind(k), MULTI_CELL)
		picked_grid.add_child(slot)
		EnhanceFx.cross(slot).visible = false  # 도는 동안 깨진 칸 자리

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

	# 목표 띠 — +1 … +9. 누르면 거기까지가 목표 (받은 그림의 화살표 줄)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_child(bar)
	for level in range(1, Items.max_enhance() + 1):
		var chevron := Chevron.new(level)
		chevron.chosen.connect(set_goal)
		bar.add_child(chevron)
		chevrons.append(chevron)

	# 방금 두드린 결과 — 성공은 금빛, 파괴는 붉게. 새로 열면 비운다
	result = _game._inv_label("", 20, _game.INV_GOLD_HI)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size = Vector2(0, 34)
	side.add_child(result)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 8)
	side.add_child(foot)
	go = _game._inv_button("강화", press)
	go.custom_minimum_size.x = 110
	foot.add_child(go)
	run_button = _game._inv_button("자동 강화", press_run)
	run_button.custom_minimum_size.x = GO_WIDTH
	foot.add_child(run_button)


## 오른쪽 목록 — 걸러 보는 탭 셋 · 장비 칸(끌어서 내린다) · 담은 수와 모두 담기·비우기
func _build_list() -> void:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	list_panel.add_child(side)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	side.add_child(row)
	for key in FILTERS:
		var tab: Button = _game._inv_button(FILTER_TEXT[key], pick_filter.bind(key))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tab)
		filters[key] = tab

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_COLS * LIST_CELL + (LIST_COLS - 1) * 6 + 14, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	list_grid = GridContainer.new()
	list_grid.columns = LIST_COLS
	list_grid.add_theme_constant_override("h_separation", 6)
	list_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(list_grid)
	# **끌어서 내린다** — 칸 단추가 끌기를 먹었다 (`DragScroll`, 가방과 같다)
	list_drag = DragScroll.attach(scroll, list_grid, 6)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	side.add_child(foot)
	list_head = _game._inv_label("", 18, _game.INV_TEXT)
	list_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(list_head)
	var all: Button = _game._inv_button("모두 담기", pick_all)
	all.custom_minimum_size.x = 100
	foot.add_child(all)
	var clear: Button = _game._inv_button("비우기", clear_picked)
	foot.add_child(clear)
	list_foot_buttons = [all, clear]


## 연다 — `where_index` 는 {where, index}. 탭은 "단일 강화", 목표는 한 단계 위
func open(where_index: Dictionary) -> void:
	target = where_index.duplicate()
	var stack := _stack()
	ref = _ref_of(stack)
	mode = "one"
	filter = "item"
	picked = []
	_waiting = false
	goal = mini(int(stack.get("enhance", 0)) + 1, Items.max_enhance())
	result.text = ""
	visible = true
	redraw()


func close() -> void:
	hide_now()
	closed.emit()


## 닫는다 — 도는 자동 강화도 그 자리에서 멈춘다 (가방 단추로 한꺼번에 닫을 때도)
func hide_now() -> void:
	_halt()
	visible = false
	target = {}
	list_drag.forget()
	for fx in fx_layer.get_children():
		fx.queue_free()


## 깨진 칸 자리(-1)를 걷는다 — 터지는 연출 동안(한 박자)만 자리를 지키고, 다음 박자·끝·다음 조작에서
## 남은 장비를 앞으로 당겨 붙인다
func _compact() -> void:
	picked = picked.filter(func(at: int) -> bool: return at >= 0)


func pick_mode(key: String) -> void:
	_compact()
	mode = key
	result.text = ""
	# 다중으로 처음 넘어오면 연 장비(가방에 든 것)를 먼저 담아 둔다
	if mode == "multi" and picked.is_empty() and str(target.get("where", "")) == "bag" \
			and _pickable(int(target.get("index", -1))):
		picked.append(int(target.index))
	redraw()


func pick_filter(key: String) -> void:
	filter = key
	redraw()


func set_goal(level: int) -> void:
	if running:
		return
	_compact()
	goal = clampi(level, _goal_floor(), Items.max_enhance())
	# 목표 이상인 것은 더 두드릴 것이 없다 — 담은 칸에서 뺀다
	picked = picked.filter(func(at: int) -> bool: return _pickable(at))
	redraw()


## 목록 칸 k 를 누르면 — 단일은 그것을 대상으로 고르고, 다중은 담고(담긴 것이면 뺀다).
## **처음 담은 것이 목록 기준**이 된다 — "같은 아이템" · "같은 등급" 이 그것으로 거른다
func toggle_list(k: int) -> void:
	if running or k >= _list_view.size():
		return
	var at: int = _list_view[k]
	if mode == "one":
		_choose(at)
		return
	_compact()
	if picked.has(at):
		picked.erase(at)
		if picked.is_empty():
			ref = _ref_of(_stack())
	elif picked.size() < MULTI_MAX:
		if picked.is_empty():
			ref = _ref_of(_bag()[at])
		picked.append(at)
		picked.sort()
	redraw()


## 단일 — 목록에서 고른 가방 칸을 대상으로 삼는다. 목표는 한 단계 위.
## 게임의 고른 칸(상세 창)은 비운다 — 대상이 바뀌었는데 두드린 결과를 옛 칸에 따라가게 하면 어긋난다
func _choose(at: int) -> void:
	target = {"where": "bag", "index": at}
	var stack := _stack()
	ref = _ref_of(stack)
	goal = mini(int(stack.get("enhance", 0)) + 1, Items.max_enhance())
	result.text = ""
	acted.emit(false, 0)
	redraw()


## 목록 기준 — 장비의 id·등급. 장비가 아니면 비운다(거르지 않는다)
func _ref_of(stack: Dictionary) -> Dictionary:
	if Items.get_item(str(stack.get("id", ""))).is_empty():
		return {}
	return {"id": str(stack.id), "grade": int(stack.get("grade", 1))}


## 담은 칸 k 를 누르면 뺀다
func unpick_slot(k: int) -> void:
	if running or k >= picked.size():
		return
	picked.remove_at(k)
	_compact()
	if picked.is_empty():
		ref = _ref_of(_stack())
	redraw()


## 모두 담기 — 지금 목록을 앞에서부터 칸이 찰 때까지
func pick_all() -> void:
	if running:
		return
	_compact()
	for at in _list_view:
		if picked.size() >= MULTI_MAX:
			break
		if not picked.has(at):
			if picked.is_empty():
				ref = _ref_of(_bag()[at])
			picked.append(at)
	picked.sort()
	redraw()


func clear_picked() -> void:
	if running:
		return
	picked = []
	ref = _ref_of(_stack())
	redraw()


## 목표의 바닥 — 단일은 지금 단계 + 1, 다중은 +1 (칸마다 단계가 달라서)
func _goal_floor() -> int:
	if mode == "one":
		return mini(int(_stack().get("enhance", 0)) + 1, Items.max_enhance())
	return 1


func _stack() -> Dictionary:
	return _game._stack_at(target) if not target.is_empty() else {}


func _bag() -> Array:
	var me: Dictionary = _game._transport.snapshot().get("players", {}).get(_game._transport.my_id(), {})
	return me.get("bag", [])


## 가방 번호 at 이 다중 강화에 들 수 있나 — 장비이고 목표 아래
func _pickable(at: int) -> bool:
	var bag := _bag()
	return at >= 0 and at < bag.size() and Items.batch_match(bag[at], "all", "", 0, goal)


## 담은 칸의 개수 (겹친 칸은 개수대로). `below` 면 목표 아래인 것만
func _picked_pieces(below: bool = false) -> int:
	var bag := _bag()
	var pieces := 0
	for at in picked:
		if at < 0 or at >= bag.size():
			continue
		if below and int(bag[at].get("enhance", 0)) >= goal:
			continue
		pieces += int(bag[at].get("count", 1))
	return pieces


## 팝업을 채운다. 탭 불빛 · 목표 띠 · 단일/다중 · 단추 · 도는 동안의 잠금
func redraw() -> void:
	_light(tabs, mode)
	_light(filters, filter)
	# 도는 동안은 목표를 다시 재지 않는다 — 단일은 바닥이 "지금 + 1" 이라 오를 때마다
	# 목표가 따라 올라가 끝나지 않았다 (+2 목표가 +6 에서 부서졌다)
	if not running:
		goal = clampi(goal, _goal_floor(), Items.max_enhance())
	var now := int(_stack().get("enhance", 0)) if mode == "one" else 0
	for chevron in chevrons:
		chevron.lit = chevron.level <= goal
		chevron.done = mode == "one" and chevron.level <= now
		chevron.queue_redraw()
	one_box.visible = mode == "one"
	multi_box.visible = mode == "multi"
	# 목록은 두 탭이 같이 쓴다 — 단일은 대상을 고르고, 다중은 담는다
	list_panel.visible = true
	for button in list_foot_buttons:
		button.visible = mode == "multi"
	go.visible = mode == "one"
	kind.add_theme_color_override("font_color", _game.INV_GOLD_HI)
	if mode == "one":
		_redraw_one()
	else:
		_redraw_multi()
	# 도는 동안은 "중지" 하나만 산다
	for key in tabs:
		tabs[key].disabled = running
	go.disabled = go.disabled or running
	if running:
		run_button.text = "중지"
		run_button.disabled = false


func _light(buttons: Dictionary, on_key: String) -> void:
	for key in buttons:
		var on: bool = key == on_key
		var button: Button = buttons[key]
		button.add_theme_color_override("font_color", _game.INV_GOLD_HI if on else _game.INV_DIM)
		button.add_theme_color_override("font_hover_color", _game.INV_GOLD_HI if on else _game.INV_TEXT)


## 단일 — 이름(등급 색) · `+N → +N+1` · 성공률 · 목표 도달 · 실패 시 파괴 ·
## 기본 능력치가 지금 → 성공하면 얼마. **대상이 부서졌으면** 이름만 남기고 단추를 끈다
func _redraw_one() -> void:
	var stack := _stack()
	var item := Items.get_item(str(stack.get("id", "")))
	run_button.text = "자동 강화  →  +%d" % goal
	if item.is_empty():
		kind.text = "부서졌습니다" if not target.is_empty() else "대상이 없습니다"
		kind.add_theme_color_override("font_color", _game.INV_WARN)
		_game._fill_cell(icon, {}, "", "")
		_game._fill_detail_rows([], info)
		go.disabled = true
		run_button.disabled = true
		_redraw_list(_bag())
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
	run_button.disabled = not can
	if not can:
		kind.text = "최대 강화"
		_game._fill_detail_rows([["강화", "+%d (끝)" % enhance]], info)
		_redraw_list(_bag())
		return

	# 확률은 설계 4장 그대로(90% → 10%). **유지가 없다** — 실패하면 무조건 파괴
	kind.text = ("자동 강화 중  →  +%d" % goal) if running else "+%d  →  +%d" % [enhance, enhance + 1]
	var rows: Array = [["성공률", _percent(float(Items.enhance_odds(enhance).success))]]
	if goal > enhance + 1:
		rows.append(["+%d 도달" % goal, _percent(Items.enhance_reach_odds(enhance, goal))])
	rows.append(["실패 시", "아이템 파괴", _game.INV_WARN])
	var now := Items.base_bonus(item, enhance)
	var next := Items.base_bonus(item, enhance + 1)
	for key in _game.DETAIL_BONUS:
		if float(now.get(key, 0.0)) > 0.0:
			rows.append([
				_game.DETAIL_BONUS[key],
				"%s → %s" % [_game._bonus_text(key, float(now[key])), _game._bonus_text(key, float(next.get(key, 0.0)))],
			])
	if int(stack.get("count", 1)) > 1:
		rows.append(["겹친 칸", "한 개만 강화"])
	_game._fill_detail_rows(rows, info)
	_redraw_list(_bag())


## 다중 — 담은 칸 7×2 · 오른쪽 목록 · 대상 수·예상 도달·파괴 표
func _redraw_multi() -> void:
	var bag := _bag()
	if not _waiting:
		var alive: Array = []
		for at in picked:
			if at < 0 or (at < bag.size() and not Items.get_item(str(bag[at].get("id", ""))).is_empty()):
				alive.append(at)
		picked = alive
		for k in MULTI_MAX:
			var cell: PanelContainer = picked_grid.get_child(k)
			var at: int = picked[k] if k < picked.size() else -2
			var stack: Dictionary = bag[at] if at >= 0 else {}
			_game._fill_cell(cell, stack, "", _game._item_icon(stack) if not stack.is_empty() else "")
			cell.get_node("broken").visible = at == -1
		_redraw_list(bag)

	var pieces := _picked_pieces(true)
	var hope := 0.0
	for at in picked:
		if at >= 0 and at < bag.size() and int(bag[at].get("enhance", 0)) < goal:
			hope += int(bag[at].get("count", 1)) * Items.enhance_reach_odds(int(bag[at].enhance), goal)
	if not running:
		run_button.text = "%d개 강화  →  +%d" % [pieces, goal]
		run_button.disabled = pieces == 0
	_game._fill_detail_rows([
		["대상", "%d개" % pieces],
		["+%d 예상 도달" % goal, "약 %d개" % roundi(hope)],
		["실패 시", "아이템 파괴", _game.INV_WARN],
	], info)


## 오른쪽 목록을 채운다. 칸은 모자라면 더 짓고 남으면 감춘다 (가방 200칸을 매번 새로 짓지 않는다).
## 기준(`ref`)이 비었으면 — 아직 아무것도 안 골랐으면 — 어느 탭이든 전부 보인다.
## 단일은 목표와 상관없이 더 오를 수 있는 것을 다 보인다 (목표는 고른 뒤에 정한다)
func _redraw_list(bag: Array) -> void:
	_list_view = []
	var how := filter if not ref.is_empty() else "all"
	var cap := goal if mode == "multi" else Items.max_enhance()
	for at in bag.size():
		if Items.batch_match(bag[at], how, str(ref.get("id", "")), int(ref.get("grade", 1)), cap):
			_list_view.append(at)
	while _list_cells.size() < _list_view.size():
		var cell: PanelContainer = _game._make_cell(toggle_list.bind(_list_cells.size()), LIST_CELL)
		list_grid.add_child(cell)
		_list_cells.append(cell)
	for k in _list_cells.size():
		var cell: PanelContainer = _list_cells[k]
		cell.visible = k < _list_view.size()
		if not cell.visible:
			continue
		var stack: Dictionary = bag[_list_view[k]]
		_game._fill_cell(cell, stack, "", _game._item_icon(stack))
		if mode == "one":
			cell.get_node("pick").visible = str(target.get("where", "")) == "bag" \
					and int(target.get("index", -1)) == _list_view[k]
		else:
			cell.get_node("pick").visible = picked.has(_list_view[k])
	if mode == "one":
		list_head.text = "강화할 장비를 고르세요"
	else:
		list_head.text = "담은 것 %d/%d" % [picked.size(), MULTI_MAX]


func _percent(odds: float) -> String:
	if odds >= 0.1:
		return "%d%%" % roundi(odds * 100.0)
	return "%.1f%%" % (odds * 100.0)


## 단일 "강화" — 한 단계
func press() -> void:
	if running or mode != "one":
		return
	result.text = ""
	_step()
	redraw()


## "자동 강화" / "N개 강화" — 목표까지 **한 단계씩 되풀이**를 시작한다 (다시 누르면 중지).
## 판정은 매 단계 서버가 한다 — 요청 하나가 한 번이라, 멈추면 그 자리에서 정말 멈춘다
func press_run() -> void:
	if running:
		_finish(true)
		return
	result.text = ""
	_compact()
	if mode == "one":
		if _stack().is_empty() or int(_stack().get("enhance", 0)) >= goal:
			return
		_run = {"steps": 0, "from": int(_stack().get("enhance", 0)), "pieces": 0, "destroyed": 0}
	else:
		var pieces := _picked_pieces(true)
		if pieces == 0:
			return
		_run = {"steps": 0, "from": 0, "pieces": pieces, "destroyed": 0}
	running = true
	_step()
	_timer.start(step_time)
	redraw()


## 한 단계 — 단일은 enhanceItem, 다중은 enhanceMany 한 바퀴(담은 칸마다 한 번).
## **대상은 결과를 따라간다** — 부서지면 비우고, 겹친 칸에서 뗀 것이 오르면 바로 뒤 칸(뗀 것)으로
## 옮긴다. 다중 뒤에는 가방 번호가 흔들려서 단일 대상(가방)도 비우고, 담은 칸은 판정이 돌려준
## 번호(`show_result`)로 이어 간다
func _step() -> void:
	if mode == "multi":
		_slot_tex = {}
		for k in picked.size():
			if picked[k] >= 0:
				var art: TextureRect = picked_grid.get_child(k).get_node("icon")
				_slot_tex[k] = [art.texture, _icon_box(art)]
		# **낮은 강화부터 한 단계씩** (2026-09-24 "강화 수치가 다른게 있으면 낮은 강화부터 천천히
		# 한 단계씩 진행해") — 이번 바퀴는 가장 낮은 단계인 칸만 두드린다(cap = 최저 + 1).
		# 나머지도 번호는 따라가야 해서 같이 보낸다. +3·+5·+5 → +4 → +5 → 셋이 같이 +6 …
		var lowest := _lowest()
		_game._transport.send(&"enhanceMany", {
			"indices": picked.filter(func(at: int) -> bool: return at >= 0),
			"cap": mini(goal, lowest + 1) if lowest >= 0 else goal,
		})
		_waiting = true
		if str(target.get("where", "")) != "equip":
			target = {}
		acted.emit(false, 0)
		return

	var stack := _stack()
	if Items.get_item(str(stack.get("id", ""))).is_empty():
		return
	var level := int(stack.get("enhance", 0))
	_pressed_count = int(stack.get("count", 1))
	var art: TextureRect = icon.get_node("icon")
	_one_tex = [art.texture, _icon_box(art)]
	if str(target.where) == "equip":
		var slot := str(Items.slots()[int(target.index)])
		_game._transport.send(&"enhanceItem", {"where": "equip", "key": slot})
		acted.emit(not _stack().is_empty(), 0)
	else:
		var before := _bag().size()
		_game._transport.send(&"enhanceItem", {"where": "bag", "key": int(target.index)})
		var after := _bag().size()
		if after < before:
			target = {}
			acted.emit(false, 0)
		elif after > before:
			target.index = int(target.index) + 1
			acted.emit(true, 1)
		else:
			acted.emit(int(_stack().get("enhance", 0)) > level, 0)


## 타이머 한 박자 — 더 갈 수 있으면 한 단계, 아니면 끝(목표에 닿았거나 부서졌거나 대상이 없다)
func _on_tick() -> void:
	if not running:
		return
	if not visible:
		_halt()
		return
	if _waiting:
		return  # 판정의 답을 아직 못 받았다 — 다음 박자에
	# 깨진 칸은 터지는 연출(0.96초)이 이 박자 전에 끝났다 — 남은 장비를 앞으로 당긴다
	# (2026-09-24 "깨져서 터지면 남은 아이템 정렬을 맨 앞으로 땡겨")
	_compact()
	var more := false
	if mode == "one":
		var stack := _stack()
		more = not stack.is_empty() and int(stack.get("enhance", 0)) < goal
	else:
		more = _picked_pieces(true) > 0
	if more:
		_step()
		redraw()
	else:
		_finish(false)


func _halt() -> void:
	running = false
	if _timer != null:
		_timer.stop()


## 자동 강화 한 판을 맺는다 — 결과 줄에 요약, 채팅에 한 줄(`finished`)
func _finish(stopped: bool) -> void:
	_halt()
	_compact()  # 끝난 모습에 깨진 빈칸이 안 남게
	var head := ("다중 강화" if mode == "multi" else "자동 강화") + (" 중지" if stopped else "")
	var text := ""
	var good := true
	var steps := int(_run.get("steps", 0))
	if mode == "one":
		var stack := _stack()
		if stack.is_empty():
			text = "+%d 에서 부서졌습니다  (%d번)" % [int(_run.get("last", _run.from)), steps]
			good = false
		elif int(stack.get("enhance", 0)) >= goal:
			text = "완료!  +%d → +%d  (%d번)" % [int(_run.from), int(stack.enhance), steps]
		else:
			text = "+%d → +%d 에서 멈췄습니다  (%d번)" % [int(_run.from), int(stack.enhance), steps]
	else:
		var left := _picked_pieces(true)
		var lost := int(_run.destroyed)
		var reach := int(_run.pieces) - lost - left
		text = "%d개 중 +%d 도달 %d개 · 파괴 %d개" % [int(_run.pieces), goal, reach, lost]
		if left > 0:
			text += " · 남은 것 %d개" % left
		good = reach > 0
	result.text = text
	result.add_theme_color_override("font_color", _game.INV_GOLD_HI if good else _game.INV_WARN)
	finished.emit(head, text, good)
	redraw()


## 담은 칸 중 목표 아래에서 가장 낮은 강화 단계 (없으면 -1) — 다중은 이 단계부터 한 단계씩 올린다
func _lowest() -> int:
	var bag := _bag()
	var lowest := -1
	for at in picked:
		if at < 0 or at >= bag.size():
			continue
		var level := int(bag[at].get("enhance", 0))
		if level < goal and (lowest < 0 or level < lowest):
			lowest = level
	return lowest


## TextureRect 가 그림을 실제로 그린 자리 — 가운데에 비율을 지켜 앉힌다 (KEEP_ASPECT_CENTERED)
func _icon_box(art: TextureRect) -> Rect2:
	var box := art.get_global_rect()
	if art.texture == null:
		return box
	var tex := art.texture.get_size()
	var scale := minf(box.size.x / tex.x, box.size.y / tex.y)
	var drawn := tex * scale
	return Rect2(box.position + (box.size - drawn) * 0.5, drawn)


## 칸 하나의 연출 — 성공은 숫자가 밀려 올라가고 반짝, 파괴는 붉은 X 뒤에 조각으로 깨진다.
## `shot` 은 보내기 직전의 [그림, 자리] (칸은 이미 새 상태로 채워졌다)
func _cell_fx(cell: PanelContainer, from: int, to: int, broke: bool, shot: Array) -> void:
	if broke:
		EnhanceFx.shatter(fx_layer, cell, shot[0] if shot.size() > 0 else null,
			shot[1] if shot.size() > 1 else cell.get_global_rect())
		return
	if to > from:
		EnhanceFx.slide(fx_layer, cell.get_node("badge"), "+%d" % from if from > 0 else "", "+%d" % to)
		EnhanceFx.sparkle(fx_layer, cell)


## 판정의 결과 이벤트(enhanceResult · enhanceBatch)를 결과 한 줄과 칸 연출로. 자동 중이면 단계를 센다
func show_result(type: StringName, payload: Dictionary) -> void:
	if not visible:
		return
	var good: bool
	if running:
		_run.steps = int(_run.steps) + 1
	if type == &"enhanceBatch":
		# 담은 칸은 **자리를 지킨 채** 판정이 돌려준 새 번호로 잇는다. 부서진 칸은 -1(흐린 X)
		var cap := int(payload.get("cap", goal))
		var by_at := {}
		for entry in payload.get("results", []):
			by_at[int(entry.at)] = entry
		var shows: Array = []  # [칸, 원래 단계, 새 단계, 깨졌나]
		var extra: Array = []
		for k in picked.size():
			var at: int = picked[k]
			if at < 0:
				continue
			var entry: Dictionary = by_at.get(at, {})
			var to: Array = entry.get("to", [])
			picked[k] = int(to[0]) if not to.is_empty() else -1
			extra.append_array(to.slice(1))
			var from := int(entry.get("from", 0))
			if from < cap and not entry.is_empty():
				shows.append([k, from, from + 1 if int(entry.success) > 0 else from, to.is_empty()])
		for at in extra:
			if picked.size() < MULTI_MAX:
				picked.append(int(at))
		_waiting = false
		result.text = "%d개 중 %d개 성공 · %d개 파괴" % [
			int(payload.pieces), int(payload.success), int(payload.destroyed)
		]
		if running:
			_run.destroyed = int(_run.destroyed) + int(payload.destroyed)
			result.text = "+%d → +%d  ·  %d바퀴\n" % [cap - 1, cap, int(_run.steps)] + result.text
		good = int(payload.destroyed) == 0 or int(payload.success) > 0
		result.add_theme_color_override("font_color", _game.INV_GOLD_HI if good else _game.INV_WARN)
		redraw()
		for show in shows:
			_cell_fx(picked_grid.get_child(show[0]), show[1], show[2], show[3], _slot_tex.get(show[0], []))
		return

	var level := int(payload.get("level", 0))
	var from := int(payload.get("from", level))
	if running:
		_run.last = from
	var broke := false
	match str(payload.get("result", "")):
		"success":
			result.text = ("+%d → +%d 성공" % [from, level]) if running else "강화 성공!  +%d" % level
			good = true
		"destroy":
			var what := "하나가 부서졌습니다" if _pressed_count > 1 else "부서졌습니다"
			result.text = ("+%d 에서 %s" % [from, what]) if running else "강화 실패 — %s" % what
			good = false
			broke = true
		_:
			result.text = "유지  +%d" % level
			good = true
	result.add_theme_color_override("font_color", _game.INV_GOLD_HI if good else _game.INV_WARN)
	redraw()
	_cell_fx(icon, from, level, broke, _one_tex)
