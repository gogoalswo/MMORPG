class_name TrainerPanel
extends PanelContainer

## PT 트레이너 창 — 메뉴 판의 **트레이너** 로 연다 (2026-10-06 요청). 모은 트레이너를 등급 탭으로 보고,
## 하나를 골라 **동행**(같이 싸운다) · **돌려보내기**. 갖고만 있어도 붙는 **보유 효과** 합계를 아래에 적는다.
## 뽑기는 상점(뽑기 → 트레이너)에서 한다 → docs/features/trainers.md
##
##   돌판 틀(ui_dungeon_card, 전체 화면) ─────────────────────────────────── X
##   │ 전체 │ 일반 │ 고급 │ 희귀 │ 영웅 │ 전설 │                      트레이너 │ ← 등급 탭
##   ├────────────────────────────────────────────┬────────────────────────┤
##   │ ┌────┐┌────┐┌────┐┌────┐┌────┐             │   [큰 원화]            │
##   │ │원화││    ││    ││    ││    │  ← 카드      │   이름 (등급 색)        │
##   │ │이름││    ││    ││    ││    │    (스크롤)  │   계승 · 보유 효과      │
##   │ └────┘└────┘└────┘└────┘└────┘             │   [ 동행 ]             │
##   ├────────────────────────────────────────────┴────────────────────────┤
##   │ 모은 트레이너 12 / 53   보유 효과  공격력 +5% · 방어력 +3% …            │
##
## 합성 보기 (머리의 **합성** → 목록 자리, 2026-10-08 요청 "등급별로 탭이 나눠져있고, 선택해서 카드 등록하면 합성"):
##   ┌──────┬──────────────────────┬──────────────────────────────────┐
##   │ 일반•│ ┌──┐┌──┐┌──┐┌──┐     │ 왼쪽 카드를 눌러 등록하세요 …       │
##   │ 고급 │ │  ││  ││  ││  │ ←카드│ 일반 → 고급  성공 20%  등록 0/30   │
##   │ 희귀 │ │여분││  │…        │   [+][+][+]  ← 한 줄(묶음) = 도전 1번  │
##   │ 영웅 │ └──┘└──┘└──┘└──┘     │   … 10줄 (30칸 = 10번, 스크롤)      │
##   │      │  (스크롤)           │ 결과 한 줄                          │
##   │      │                     │ [카드 자동 등록]   [합성]   ← 맨 아래 │
##   [합성] → 결과가 오면 **합성 결과 판**(`TrainerFuseResult`)이 화면을 덮는다 — 도전마다 카드 한 장, X 로 걷는다

signal pick_requested(id: String)
## **합성** — 칸에 등록한 트레이너 id 들 (같은 등급, 3장마다 한 번 도전)
signal fuse_requested(ids: Array)

const STONE_IN := 30
const COLUMNS := 5
const CARD_SIZE := Vector2(150, 232)
const ART_SIZE := Vector2(126, 168)
const DETAIL_WIDTH := 380.0
const DETAIL_ART := Vector2(240, 320)
const TITLE_ROOM := 72
## 합성 보기 — 왼쪽 등급 탭 폭 · 가운데 카드 열 수와 그림 크기 · 오른쪽 등록 칸 크기 (1280 × 720 에 한 화면)
const FUSE_TAB_WIDTH := 130.0
const FUSE_COLUMNS := 4
const FUSE_ART := Vector2(88, 117)
const SLOT_SIZE := Vector2(88, 117)

const TITLE := GatePanel.PAGE_TITLE_COLOR
const GOLD := GatePanel.CARD_GOLD
const IVORY := Color("#eeead7")
const DIM := Color("#948c7a")

## 탭 — 0 은 전체, 1 ~ 5 는 등급
var _tab := 0
var _selected := ""
var _me: Dictionary = {}
var _seen := ""
var _portrait := Callable()

var _tabs: Array = []
var _grid: GridContainer
## 고른 트레이너의 3D 모델 (2026-10-06 — 그림 대신). 모델이 없으면 무대가 원화로 대신한다
var _detail_art: TrainerStage
## 카드 그림을 3D 모델로 찍는 보이지 않는 무대 (`TrainerPortraits`)
var _shots: TrainerPortraits
var _detail_name: Label
var _detail_grade: Label
var _detail_lines: Label
var _pick: Button
var _summary: Label
## 합성 보기 — 목록(`_body`)과 자리를 바꿔 선다 (`_fuse_toggle`)
var _body: HBoxContainer
var _fuse_view: HBoxContainer
var _fuse_toggle: Button
## 합성 보기의 등급 탭(왼쪽 세로) · 고른 등급 · 그 등급 카드 · 등록 칸과 거기 넣은 id
var _fuse_grade := 1
var _fuse_tabs: Dictionary = {}
var _fuse_grid: GridContainer
var _fuse_empty: Label
var _slots: Array = []
var _slot_ids: Array = []
var _fuse_target: Label
var _fuse_odds: Label
var _fuse_count: Label
var _auto: Button
var _fuse_go: Button
var _fuse_note: Label
## 합성 결과 판 (`TrainerFuseResult`) — 결과가 오면 창 위에 덮고 X 로 걷는다
var _fuse_result: TrainerFuseResult


## `portrait` 는 트레이너 id → 원화 Texture2D (없으면 null) — `game.gd` 의 `_trainer_art`
static func make(frame_box: Callable, portrait: Callable) -> TrainerPanel:
	var panel := TrainerPanel.new()
	panel._portrait = portrait
	panel._build(frame_box)
	return panel


func _build(frame_box: Callable) -> void:
	name = "TrainerPanel"
	visible = false
	add_theme_stylebox_override("panel", frame_box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, STONE_IN))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var head := HBoxContainer.new()
	head.name = "head"
	head.add_theme_constant_override("separation", 4)
	column.add_child(head)
	var names := ["전체"]
	for g in Trainers.grades():
		names.append(str(g.name))
	for index in names.size():
		var tab := Button.new()
		tab.name = "tab_%d" % index
		tab.text = names[index]
		tab.custom_minimum_size = Vector2(104, 54)
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 22)
		tab.pressed.connect(_pick_tab.bind(index))
		head.add_child(tab)
		_tabs.append(tab)
	# 합성 — 같은 등급 여분 3장으로 다음 등급 도전 (2026-10-06). 누르면 목록 자리에 합성 보기가 선다.
	# 전설 탭 바로 옆에 **등급 탭과 같은 탭**으로 선다 (2026-10-08 "합성 버튼을 일반,고급 이런 탭처럼 탭으로") —
	# 전엔 청록 돌판 단추였다. 등급 탭을 누르면 목록으로 돌아간다
	_fuse_toggle = Button.new()
	_fuse_toggle.name = "fuse_toggle"
	_fuse_toggle.text = "합성"
	_fuse_toggle.custom_minimum_size = Vector2(104, 54)
	_fuse_toggle.focus_mode = Control.FOCUS_NONE
	_fuse_toggle.add_theme_font_size_override("font_size", 22)
	_fuse_toggle.pressed.connect(show_fuse.bind(true))
	head.add_child(_fuse_toggle)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var title := _label("트레이너", 30, TITLE)
	title.name = "title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var room := Control.new()
	room.custom_minimum_size = Vector2(TITLE_ROOM, 0)
	head.add_child(room)
	column.add_child(_rule(Vector2(0, 1)))

	var body := HBoxContainer.new()
	body.name = "body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	column.add_child(body)
	_body = body
	_build_fuse(column, frame_box)

	var shelf := MarginContainer.new()
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		shelf.add_theme_constant_override("margin_" + side, 14)
	body.add_child(shelf)
	var scroll := ScrollContainer.new()
	scroll.name = "scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "grid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	# 끌어서 내린다 — 합성 칸 · 가방과 같은 길 (`DragScroll`, 2026-10-08). 카드의 `hit` 가 끌기를 먹어 휠로만 내려갔다
	DragScroll.attach(scroll, _grid, 12)
	body.add_child(_rule(Vector2(1, 0)))

	# 오른쪽 — 고른 트레이너
	var detail := VBoxContainer.new()
	detail.name = "detail"
	detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	detail.alignment = BoxContainer.ALIGNMENT_CENTER
	detail.add_theme_constant_override("separation", 10)
	body.add_child(detail)
	_shots = TrainerPortraits.new()
	_shots.baked.connect(_on_baked)
	add_child(_shots)
	_detail_art = TrainerStage.make(DETAIL_ART)
	_detail_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	detail.add_child(_detail_art)
	_detail_name = _label("", 26, IVORY)
	_detail_name.name = "name"
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_child(_detail_name)
	_detail_grade = _label("", 18, DIM)
	_detail_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_child(_detail_grade)
	_detail_lines = _label("", 19, IVORY)
	_detail_lines.name = "lines"
	_detail_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_child(_detail_lines)
	_pick = Button.new()
	_pick.name = "pick"
	_pick.custom_minimum_size = Vector2(220, 58)
	_pick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pick.focus_mode = Control.FOCUS_NONE
	GatePanel.paint_stone_button(_pick, frame_box, 24)
	_pick.pressed.connect(_on_pick)
	detail.add_child(_pick)

	column.move_child(_fuse_view, body.get_index() + 1)
	column.add_child(_rule(Vector2(0, 1)))
	_summary = _label("", 18, IVORY)
	_summary.name = "summary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(0, 56)
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_summary)

	_pick_tab(0)


func open() -> void:
	visible = true
	_seen = ""
	if not _me.is_empty():
		refresh(_me)


func close_panel() -> void:
	visible = false
	hide_fuse_result()


## 스냅샷(`trainers` · `trainer_active`)으로 다시 그린다. `_refresh_status` 가 매 프레임 부르므로
## 보이는 동안 **바뀐 것이 있을 때만** 다시 짓는다
func refresh(me: Dictionary) -> void:
	_me = me
	if _selected == "" and me.has("trainers"):
		var active := str(me.get("trainer_active", ""))
		_selected = active if active != "" else str(Trainers.all()[0].id)
	var seen := str(me.get("trainers", {})) + "|" + str(me.get("trainer_active", ""))
	if not visible or seen == _seen:
		return
	_seen = seen
	_fill()
	if _fuse_view.visible:
		_fill_fuse()


func select(id: String) -> void:
	_selected = id
	_fill()


## 합성 보기를 켜고 끈다 — 목록과 한 자리
func show_fuse(on: bool) -> void:
	_fuse_view.visible = on
	_body.visible = not on
	# 머리 탭 한 줄에서 하나만 켜진다 — 합성 탭이거나, 목록의 등급 탭이거나
	_paint_tab(_fuse_toggle, on)
	for i in _tabs.size():
		_paint_tab(_tabs[i], not on and i == _tab)
	if on:
		_fill_fuse()


func fuse_shown() -> bool:
	return _fuse_view.visible


## 합성 보기의 등급 탭 — 테스트가 누른다 (전설은 없다)
func fuse_tab(grade: int) -> Button:
	return _fuse_tabs.get(grade)


## 합성 보기의 카드(고른 등급에서 가진 것) · 등록 칸 · 칸에 넣은 id · 단추 둘 `[카드 자동 등록, 합성]`
func fuse_cards() -> Array:
	return _fuse_grid.get_children()


func fuse_slots() -> Array:
	return _slots


func slot_ids() -> Array:
	return _slot_ids


func fuse_buttons() -> Array:
	return [_auto, _fuse_go]


func fuse_note() -> String:
	return _fuse_note.text


func hide_fuse_result() -> void:
	if _fuse_result != null and is_instance_valid(_fuse_result):
		_fuse_result.queue_free()
	_fuse_result = null


## 합성 결과 판 — 없으면 null. 테스트가 본다
func fuse_result() -> TrainerFuseResult:
	return _fuse_result if _fuse_result != null and is_instance_valid(_fuse_result) and not _fuse_result.is_queued_for_deletion() else null


## 판정이 낸 합성 결과(`trainerFuse`) — **합성 결과 판**을 덮고(도전마다 카드 한 장), 단추 아래 줄에도 성공·실패 수
func show_fuse_result(payload: Dictionary) -> void:
	var results: Array = payload.get("results", [])
	var got: Array = []
	for r in results:
		if str(r.get("got", "")) != "":
			got.append(str(r.got))
	if results.size() == 1:
		_fuse_note.text = "성공! %s" % str(Trainers.trainer(got[0]).name) if not got.is_empty() else "실패 — 재료 %d장이 사라졌습니다" % Trainers.fuse_cost()
	else:
		_fuse_note.text = "합성 %d번 — 성공 %d · 실패 %d" % [results.size(), got.size(), results.size() - got.size()]
	hide_fuse_result()
	_fuse_result = TrainerFuseResult.make(results)
	_fuse_result.closed.connect(hide_fuse_result)
	add_child(_fuse_result)
	_shots.request(got)
	_seen = ""
	refresh(_me)
	_fill_fuse()


func cards() -> Array:
	return _grid.get_children()


func tab_buttons() -> Array:
	return _tabs


func detail_name() -> String:
	return _detail_name.text


## 오른쪽 3D 무대 — 테스트가 본다
func stage() -> TrainerStage:
	return _detail_art


func pick_button() -> Button:
	return _pick


func summary_text() -> String:
	return _summary.text


func _pick_tab(index: int) -> void:
	_tab = index
	# 합성 보기에서 등급 탭을 누르면 목록으로 돌아간다 (탭 색도 거기서 칠한다)
	show_fuse(false)
	_fill()


func _fill() -> void:
	for card in _grid.get_children():
		_grid.remove_child(card)
		card.queue_free()
	# 이 탭의 카드를 3D 모델로 찍어 달라고 줄 세운다 — 찍히는 대로 그림이 바뀐다 (`_on_baked`)
	var shown: Array = []
	for info in Trainers.all():
		if _tab == 0 or int(info.grade) == _tab:
			shown.append(str(info.id))
	if _shots.is_inside_tree():
		_shots.request(shown)
	var owned: Dictionary = _me.get("trainers", {})
	var active := str(_me.get("trainer_active", ""))
	for info in Trainers.all():
		if _tab != 0 and int(info.grade) != _tab:
			continue
		var id := str(info.id)
		var card := TrainerPanel.make_card(info, _art(id), int(owned.get(id, 0)), id == active, id == _selected)
		var hit := Button.new()
		hit.name = "hit"
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.pressed.connect(select.bind(id))
		card.add_child(hit)
		_grid.add_child(card)
	_fill_detail(owned, active)
	_fill_summary(owned)


func _fill_detail(owned: Dictionary, active: String) -> void:
	var info := Trainers.trainer(_selected)
	if info.is_empty():
		return
	var grade := Trainers.grade(int(info.grade))
	var have := int(owned.get(_selected, 0))
	_detail_art.show_trainer(_selected, _concept(_selected), have > 0)
	_detail_name.text = str(info.name)
	_detail_name.add_theme_color_override("font_color", TrainerPanel.grade_color(int(info.grade)))
	_detail_grade.text = "%s 등급" % str(grade.get("name", ""))
	var lines := [
		"동행 시 능력치 %d%% 계승" % int(info.inherit),
		"보유 효과  %s" % TrainerPanel.owned_text(info),
		"보유 %d" % have if have > 0 else "미보유",
	]
	_detail_lines.text = "\n".join(lines)
	if have <= 0:
		_pick.text = "미보유"
		_pick.disabled = true
	elif _selected == active:
		_pick.text = "돌려보내기"
		_pick.disabled = false
	else:
		_pick.text = "동행"
		_pick.disabled = false


func _fill_summary(owned: Dictionary) -> void:
	var count := 0
	for id in owned:
		if int(owned[id]) > 0 and not Trainers.trainer(str(id)).is_empty():
			count += 1
	var bonus := Trainers.owned_bonus(owned)
	var parts: Array = []
	for stat in ["attack", "defense", "maxHp", "crit", "critDamage"]:
		var value := float(bonus[stat])
		if value <= 0.0:
			continue
		var pct := value * 100.0 if stat in ["crit", "critDamage"] else value
		parts.append("%s +%d%%" % [Trainers.stat_name(stat), roundi(pct)])
	_summary.text = "  모은 트레이너 %d / %d     보유 효과  %s" % [
		count, Trainers.all().size(), " · ".join(parts) if not parts.is_empty() else "없음",
	]


func _build_fuse(column: VBoxContainer, frame_box: Callable) -> void:
	_fuse_view = HBoxContainer.new()
	_fuse_view.name = "fuse"
	_fuse_view.visible = false
	_fuse_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fuse_view.add_theme_constant_override("separation", 0)
	column.add_child(_fuse_view)

	# 왼쪽 — 등급 탭 (세로). 넣을 수 있는 등급(여분 3장 이상)엔 빨간 점
	var tabs := VBoxContainer.new()
	tabs.name = "fuse_tabs"
	tabs.custom_minimum_size = Vector2(FUSE_TAB_WIDTH, 0)
	tabs.add_theme_constant_override("separation", 8)
	var tab_pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		tab_pad.add_theme_constant_override("margin_" + side, 12)
	tab_pad.add_child(tabs)
	_fuse_view.add_child(tab_pad)
	for g in Trainers.grades():
		var grade := int(g.grade)
		if Trainers.fuse_chance(grade) <= 0.0:
			continue
		var tab := Button.new()
		tab.name = "fuse_tab_%d" % grade
		tab.text = str(g.name)
		tab.custom_minimum_size = Vector2(0, 64)
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 24)
		tab.pressed.connect(_pick_fuse_grade.bind(grade))
		_red_dot(tab)
		tabs.add_child(tab)
		_fuse_tabs[grade] = tab
	_fuse_view.add_child(_rule(Vector2(1, 0)))

	# 가운데 — 그 등급에서 가진 카드. 누르면 한 장씩 칸에 들어간다 (표시는 칸에 더 넣을 수 있는 장 수)
	var shelf := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		shelf.add_theme_constant_override("margin_" + side, 14)
	_fuse_view.add_child(shelf)
	var scroll := ScrollContainer.new()
	scroll.name = "fuse_scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(FUSE_COLUMNS * (FUSE_ART.x + 16) + (FUSE_COLUMNS - 1) * 10 + 12, 0)
	shelf.add_child(scroll)
	var shelf_box := VBoxContainer.new()
	scroll.add_child(shelf_box)
	_fuse_grid = GridContainer.new()
	_fuse_grid.name = "fuse_grid"
	_fuse_grid.columns = FUSE_COLUMNS
	_fuse_grid.add_theme_constant_override("h_separation", 10)
	_fuse_grid.add_theme_constant_override("v_separation", 10)
	shelf_box.add_child(_fuse_grid)
	_fuse_empty = _label("이 등급 트레이너가 없습니다", 18, DIM)
	shelf_box.add_child(_fuse_empty)
	# 끌어서 내린다 — 가방 · 강화 목록과 같은 길 (`DragScroll`, 2026-10-08 "클릭해서 내리는 건 안돼")
	DragScroll.attach(scroll, _fuse_grid, 10)
	_fuse_view.add_child(_rule(Vector2(1, 0)))

	# 오른쪽 — 등록 칸(3장 한 줄 = 도전 한 번)과 확률 · 자동 등록 · 합성 · 결과
	var right := MarginContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		right.add_theme_constant_override("margin_" + side, 14)
	_fuse_view.add_child(right)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	right.add_child(stack)
	# 한 줄에 든다 — 줄바꿈을 켜면 폭이 정해지기 전 최소 높이를 글자마다 줄을 바꿔 재서 창이 720 을 넘는다
	var hint := _label("왼쪽 카드를 눌러 등록하세요. %d장 한 묶음이 한 번 도전입니다." % Trainers.fuse_cost(), 17, DIM)
	stack.add_child(hint)
	# `일반 → 고급 · 성공 확률 20% · 등록 6 / 30 · 도전 2번` 한 줄
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 22)
	stack.add_child(info)
	_fuse_target = _label("", 22, IVORY)
	_fuse_target.name = "fuse_target"
	info.add_child(_fuse_target)
	_fuse_odds = _label("", 19, GOLD)
	_fuse_odds.name = "fuse_odds"
	_fuse_odds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(_fuse_odds)
	_fuse_count = _label("", 18, IVORY)
	_fuse_count.name = "fuse_count"
	_fuse_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(_fuse_count)
	# 등록 칸 30개(`TRAINER_FUSE_SLOTS`, 2026-10-08 "한 번에 최대 30개 · 총 10번") — 3장 묶음이 도전 한 번,
	# 한 줄이 한 묶음이다. 칸 번호는 위 줄부터라 합성은 앞 묶음부터 보낸다.
	# 칸은 원래 크기(88 × 117) 그대로 아래로 쭉 내리고 스크롤한다 (2026-10-08 "칸 크기를 이전으로 돌리고 아래로 쭉 내려서 스크롤")
	var slot_scroll := ScrollContainer.new()
	slot_scroll.name = "slot_scroll"
	slot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slot_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(slot_scroll)
	# 칸은 격자에 바로 넣는다 — 끌기(`DragScroll`)가 격자의 자식을 칸으로 보고 누른 칸을 찾는다
	var slots := GridContainer.new()
	slots.name = "slots"
	slots.columns = Trainers.fuse_cost()
	slots.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	slots.add_theme_constant_override("h_separation", 8)
	slots.add_theme_constant_override("v_separation", 14)
	slot_scroll.add_child(slots)
	for i in Trainers.fuse_slots():
		var slot := Button.new()
		slot.name = "slot_%d" % i
		slot.custom_minimum_size = SLOT_SIZE
		slot.focus_mode = Control.FOCUS_NONE
		slot.add_theme_font_size_override("font_size", 40)
		slot.add_theme_color_override("font_color", Color(GOLD, 0.7))
		slot.add_theme_color_override("font_hover_color", GOLD)
		var art := TextureRect.new()
		art.name = "art"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in [SIDE_LEFT, SIDE_TOP]:
			art.set_offset(side, 4)
		for side in [SIDE_RIGHT, SIDE_BOTTOM]:
			art.set_offset(side, -4)
		slot.add_child(art)
		slot.pressed.connect(_unslot.bind(i))
		slots.add_child(slot)
		_slots.append(slot)
	# 칸을 끌어서 내린다 — 그 자리에서 떼면 그 칸을 누른 것(뺀다), 끌면 스크롤 (2026-10-08 "클릭해서 내리는 건 안돼")
	DragScroll.attach(slot_scroll, slots, 14)
	_fuse_note = _label("", 18, IVORY)
	_fuse_note.name = "fuse_note"
	_fuse_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_fuse_note)
	# 단추 둘은 맨 아래 한 줄 (2026-10-08 "카드 자동 등록, 합성 버튼을 맨 아래쪽으로")
	var buttons := HBoxContainer.new()
	buttons.name = "fuse_buttons"
	buttons.add_theme_constant_override("separation", 14)
	stack.add_child(buttons)
	_auto = Button.new()
	_auto.name = "auto"
	_auto.text = "카드 자동 등록"
	_auto.custom_minimum_size = Vector2(0, 54)
	_auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto.focus_mode = Control.FOCUS_NONE
	GatePanel.paint_stone_button(_auto, frame_box, 20)
	_auto.pressed.connect(_auto_slot)
	buttons.add_child(_auto)
	_fuse_go = Button.new()
	_fuse_go.name = "fuse_go"
	_fuse_go.text = "합성"
	_fuse_go.custom_minimum_size = Vector2(0, 54)
	_fuse_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuse_go.focus_mode = Control.FOCUS_NONE
	GatePanel.paint_stone_button(_fuse_go, frame_box, 22)
	_fuse_go.pressed.connect(_on_fuse)
	buttons.add_child(_fuse_go)


func _pick_fuse_grade(grade: int) -> void:
	if grade == _fuse_grade:
		return
	_fuse_grade = grade
	_slot_ids.clear()
	_fill_fuse()


## 합성 보기를 다시 그린다 — 탭 빨간 점 · 그 등급 카드(남은 여분) · 칸 · 확률 · 단추 켜짐
func _fill_fuse() -> void:
	var owned: Dictionary = _me.get("trainers", {})
	# 장부가 바뀌었으면(합성 · 뽑기) 칸에 남은 것 중 이제 여분이 모자란 것을 덜어 낸다
	var kept: Array = []
	for id in _slot_ids:
		if Trainers.spare_of(owned, str(id), kept) > 0:
			kept.append(id)
	_slot_ids = kept
	for grade in _fuse_tabs:
		var tab: Button = _fuse_tabs[grade]
		_paint_tab(tab, int(grade) == _fuse_grade)
		tab.add_theme_color_override("font_color", TrainerPanel.grade_color(int(grade)).lightened(0.3) if int(grade) == _fuse_grade else DIM)
		(tab.get_node("red_dot") as Control).visible = Trainers.spare(owned, int(grade)) >= Trainers.fuse_cost()

	for card in _fuse_grid.get_children():
		_fuse_grid.remove_child(card)
		card.queue_free()
	var shown: Array = []
	for info in Trainers.of_grade(_fuse_grade):
		var id := str(info.id)
		var have := int(owned.get(id, 0))
		if have <= 0:
			continue
		shown.append(id)
		var left := Trainers.spare_of(owned, id, _slot_ids)
		var card := _mini_card(info, have, FUSE_ART)
		(card.find_child("tag", true, false) as Label).text = "여분 %d" % left
		if left <= 0:
			(card.find_child("art", true, false) as TextureRect).modulate = Color(0.3, 0.3, 0.3)
		var hit := Button.new()
		hit.name = "hit"
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.pressed.connect(_slot_in.bind(id))
		card.add_child(hit)
		_fuse_grid.add_child(card)
	_fuse_empty.visible = shown.is_empty()
	if _shots.is_inside_tree():
		_shots.request(shown)

	var color := TrainerPanel.grade_color(_fuse_grade)
	for i in _slots.size():
		var slot: Button = _slots[i]
		var box := StyleBoxFlat.new()
		box.bg_color = GatePanel.CELL_BG
		box.set_border_width_all(2)
		var art := slot.get_node("art") as TextureRect
		if i < _slot_ids.size():
			box.border_color = color
			art.texture = _art(str(_slot_ids[i]))
			slot.text = ""
		else:
			box.border_color = GatePanel.HEAD_LINE
			art.texture = null
			slot.text = "+"
		for state in ["normal", "hover", "pressed", "disabled"]:
			slot.add_theme_stylebox_override(state, box)
		slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var cost := Trainers.fuse_cost()
	var tries := _slot_ids.size() / cost
	_fuse_target.text = "%s → %s" % [str(Trainers.grade(_fuse_grade).get("name", "")), str(Trainers.grade(_fuse_grade + 1).get("name", ""))]
	_fuse_target.add_theme_color_override("font_color", TrainerPanel.grade_color(_fuse_grade + 1).lightened(0.3))
	_fuse_odds.text = "성공 확률 %s%%" % str(Trainers.fuse_chance(_fuse_grade)).trim_suffix(".0")
	_fuse_count.text = "등록 %d / %d · 도전 %d번" % [_slot_ids.size(), _slots.size(), tries]
	_auto.disabled = _slot_ids.size() >= _slots.size() or Trainers.auto_pick(owned, _fuse_grade, _slot_ids, 1).is_empty()
	_fuse_go.disabled = tries <= 0


## 카드를 눌렀다 — 여분이 남았고 빈 칸이 있으면 한 장 등록
func _slot_in(id: String) -> void:
	if _slot_ids.size() >= _slots.size() or Trainers.spare_of(_me.get("trainers", {}), id, _slot_ids) <= 0:
		return
	_slot_ids.append(id)
	_fill_fuse()


## 칸을 눌렀다 — 그 카드를 뺀다
func _unslot(index: int) -> void:
	if index >= _slot_ids.size():
		return
	_slot_ids.remove_at(index)
	_fill_fuse()


## **카드 자동 등록** — 빈 칸을 남은 여분이 많은 트레이너부터 채운다 (`Trainers.auto_pick`)
func _auto_slot() -> void:
	_slot_ids.append_array(Trainers.auto_pick(_me.get("trainers", {}), _fuse_grade, _slot_ids, _slots.size() - _slot_ids.size()))
	_fill_fuse()


## **합성** — 칸의 앞에서부터 3장 줄만 보낸다. 줄을 못 채운 나머지는 칸에 남는다
func _on_fuse() -> void:
	var take := _slot_ids.size() / Trainers.fuse_cost() * Trainers.fuse_cost()
	if take <= 0:
		return
	var ids := _slot_ids.slice(0, take)
	_slot_ids = _slot_ids.slice(take)
	fuse_requested.emit(ids)
	_fill_fuse()


## 작은 카드 — 합성 보기 카드 · 얻은 카드. `make_card` 를 그림 크기에 맞춰 줄인다
func _mini_card(info: Dictionary, have: int, art: Vector2) -> PanelContainer:
	var card := TrainerPanel.make_card(info, _art(str(info.get("id", ""))), have, false, false)
	card.custom_minimum_size = Vector2(art.x + 16, 0)
	(card.find_child("art", true, false) as TextureRect).custom_minimum_size = art
	# 폭이 좁아 15px 이면 이름이 단어 가운데서 꺾인다
	(card.find_child("name", true, false) as Label).add_theme_font_size_override("font_size", 13)
	return card


## 오른쪽 위 빨간 점 — 도감 창과 같은 모양 (`CodexPanel._red_dot`)
func _red_dot(owner: Control) -> Control:
	var dot := Panel.new()
	dot.name = "red_dot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#e3342b")
	style.border_color = Color("#3a0b08")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	dot.add_theme_stylebox_override("panel", style)
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -18
	dot.offset_right = -6
	dot.offset_top = 6
	dot.offset_bottom = 18
	dot.visible = false
	owner.add_child(dot)
	return dot


func _on_pick() -> void:
	if _pick.disabled:
		return
	var active := str(_me.get("trainer_active", ""))
	pick_requested.emit("" if _selected == active else _selected)


## 카드 그림 — **3D 모델을 찍은 것**(`TrainerPortraits`, 2026-10-06). 아직 못 찍었으면 **비워 둔다** — 원화를 먼저
## 세웠더니 창을 열 때 2D 그림이 섰다가 3D 로 바뀌었다 (2026-10-07 "3D 로딩이 안 됐으면 비어 있게 만들고, 3D 모델을 채워")
func _art(id: String) -> Texture2D:
	return TrainerPortraits.cached(id)


## 원화 — 오른쪽 무대가 모델이 없을 때 대신 깐다
func _concept(id: String) -> Texture2D:
	return _portrait.call(id) if _portrait.is_valid() else null


## 한 장 찍혔다 — 보이는 카드(목록 · 합성 카드)와 등록 칸 · 합성 결과 판의 빈 그림을 채운다
func _on_baked(id: String, texture: Texture2D) -> void:
	if fuse_result() != null:
		_fuse_result.set_art(id, texture)
	for box in [_grid, _fuse_grid]:
		var card: Node = box.get_node_or_null("card_%s" % id)
		if card != null:
			(card.find_child("art", true, false) as TextureRect).texture = texture
	for i in mini(_slot_ids.size(), _slots.size()):
		if str(_slot_ids[i]) == id:
			((_slots[i] as Button).get_node("art") as TextureRect).texture = texture


## 카드 한 장 — 트레이너 창 · 뽑기 결과가 같이 쓴다. 원화 · 등급 색 테 · 이름 · 표시(동행 / ×개수 / 미보유)
static func make_card(info: Dictionary, art: Texture2D, have: int, active: bool, picked: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "card_%s" % str(info.get("id", ""))
	card.custom_minimum_size = CARD_SIZE
	var color := TrainerPanel.grade_color(int(info.get("grade", 1)))
	var box := StyleBoxFlat.new()
	box.bg_color = GatePanel.CELL_BG
	box.border_color = GOLD if picked else color
	box.set_border_width_all(3 if picked else 2)
	box.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", box)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stack)
	var pic := TextureRect.new()
	pic.name = "art"
	pic.custom_minimum_size = ART_SIZE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture = art
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if have <= 0:
		pic.modulate = Color(0.3, 0.3, 0.3)
	stack.add_child(pic)
	var label := Label.new()
	label.name = "name"
	label.text = str(info.get("name", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color.lightened(0.35) if have > 0 else DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)
	var tag := Label.new()
	tag.name = "tag"
	tag.text = "동행" if active else ("×%d" % have if have > 1 else ("" if have == 1 else "미보유"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", GOLD if active else DIM)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(tag)
	return card


## 등급 색 — 장비 등급과 같은 표 (`items.json` 의 gradeColors). 예전에는 `combat.json` 의 없는 칸을 읽어
## 등급과 상관없이 전부 상아색이었다 (2026-10-06 뽑기 연출에서 이름을 등급 색으로 칠하다 찾았다)
static func grade_color(grade: int) -> Color:
	if grade < 1 or grade > Trainers.grades().size():
		return IVORY
	return Items.grade_color(grade)


## "공격력 +8%" — 치명타 둘은 %p 지만 화면에는 % 로 적는다
static func owned_text(info: Dictionary) -> String:
	return "%s +%d%%" % [Trainers.stat_name(str(info.get("stat", ""))), int(info.get("owned", 0))]


func _paint_tab(tab: Button, on: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.78, 0.5, 0.08) if on else Color(0, 0, 0, 0)
	box.border_color = GOLD if on else Color(0, 0, 0, 0)
	box.border_width_bottom = 3
	box.set_content_margin_all(6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		tab.add_theme_stylebox_override(state, box)
	tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tab.add_theme_color_override("font_color", GOLD if on else DIM)
	tab.add_theme_color_override("font_hover_color", GOLD if on else IVORY)
	tab.add_theme_color_override("font_pressed_color", GOLD)


func _rule(size: Vector2) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = GatePanel.HEAD_LINE
	rule.custom_minimum_size = size
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
