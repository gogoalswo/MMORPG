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

signal pick_requested(id: String)
## 합성 줄의 **합성**(`all` false) · **모두 합성**(true) — `grade` 는 넣는 쪽 등급
signal fuse_requested(grade: int, all: bool)

const STONE_IN := 30
const COLUMNS := 5
const CARD_SIZE := Vector2(150, 232)
const ART_SIZE := Vector2(126, 168)
const DETAIL_WIDTH := 380.0
const DETAIL_ART := Vector2(240, 320)
const TITLE_ROOM := 72

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
var _fuse_view: VBoxContainer
var _fuse_toggle: Button
var _fuse_rows: Dictionary = {}
var _fuse_note: Label
var _fuse_cards: HBoxContainer


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
	# 합성 — 같은 등급 여분 3장으로 다음 등급 도전 (2026-10-06). 누르면 목록 자리에 합성 줄이 선다.
	# 전설 탭 바로 옆에 청록 돌판 단추로 선다 (2026-10-07 "합성 버튼을 전설탭 옆으로")
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(12, 0)
	head.add_child(gap2)
	_fuse_toggle = Button.new()
	_fuse_toggle.name = "fuse_toggle"
	_fuse_toggle.text = "합성"
	_fuse_toggle.custom_minimum_size = Vector2(120, 48)
	_fuse_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fuse_toggle.focus_mode = Control.FOCUS_NONE
	GatePanel.paint_stone_button(_fuse_toggle, frame_box, 22)
	_fuse_toggle.pressed.connect(func() -> void: show_fuse(not _fuse_view.visible))
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
	_fuse_toggle.text = "목록" if on else "합성"
	if on:
		_fill_fuse()


func fuse_shown() -> bool:
	return _fuse_view.visible


## 합성 줄의 단추 둘 — 테스트가 누른다 `[합성, 모두 합성]`
func fuse_buttons(grade: int) -> Array:
	var row: Dictionary = _fuse_rows.get(grade, {})
	return [row.get("one"), row.get("all")]


func fuse_note() -> String:
	return _fuse_note.text


## 판정이 낸 합성 결과(`trainerFuse`) — 아래 줄에 성공·실패 수, 얻은 트레이너 카드
func show_fuse_result(payload: Dictionary) -> void:
	var results: Array = payload.get("results", [])
	var got: Array = []
	for r in results:
		if str(r.get("got", "")) != "":
			got.append(str(r.got))
	var from := str(Trainers.grade(int(payload.get("grade", 0))).get("name", ""))
	if results.size() == 1:
		_fuse_note.text = "%s 합성 — %s" % [from, "성공!" if not got.is_empty() else "실패 (재료 %d장이 사라졌습니다)" % Trainers.fuse_cost()]
	else:
		_fuse_note.text = "%s 합성 %d번 — 성공 %d · 실패 %d" % [from, results.size(), got.size(), results.size() - got.size()]
	for card in _fuse_cards.get_children():
		card.queue_free()
	for id in got.slice(0, 6):
		var card := TrainerPanel.make_card(Trainers.trainer(id), _art(id), 1, false, false)
		(card.find_child("tag", true, false) as Label).text = "획득"
		_fuse_cards.add_child(card)
	_shots.request(got.slice(0, 6))
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
	for i in _tabs.size():
		_paint_tab(_tabs[i], i == index)
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
	_fuse_view = VBoxContainer.new()
	_fuse_view.name = "fuse"
	_fuse_view.visible = false
	_fuse_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fuse_view.add_theme_constant_override("separation", 10)
	column.add_child(_fuse_view)
	var hint := _label("같은 등급 여분 %d장으로 다음 등급에 도전합니다. 트레이너마다 1장은 남깁니다 — 실패하면 재료만 사라집니다." % Trainers.fuse_cost(), 18, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 52)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fuse_view.add_child(hint)
	for g in Trainers.grades():
		var grade := int(g.grade)
		if Trainers.fuse_chance(grade) <= 0.0:
			continue
		var row := HBoxContainer.new()
		row.name = "fuse_%d" % grade
		row.add_theme_constant_override("separation", 18)
		var title := _label("%s → %s" % [str(g.name), str(Trainers.grade(grade + 1).get("name", ""))], 22, IVORY)
		title.custom_minimum_size = Vector2(170, 0)
		title.add_theme_color_override("font_color", TrainerPanel.grade_color(grade + 1).lightened(0.3))
		row.add_child(title)
		var spare := _label("", 20, IVORY)
		spare.custom_minimum_size = Vector2(150, 0)
		row.add_child(spare)
		var odds := _label("성공 %s%%" % str(Trainers.fuse_chance(grade)).trim_suffix(".0"), 20, GOLD)
		odds.custom_minimum_size = Vector2(120, 0)
		row.add_child(odds)
		var one := Button.new()
		one.name = "one"
		one.text = "합성"
		one.custom_minimum_size = Vector2(130, 50)
		one.focus_mode = Control.FOCUS_NONE
		GatePanel.paint_stone_button(one, frame_box, 20)
		one.pressed.connect(func() -> void: fuse_requested.emit(grade, false))
		row.add_child(one)
		var all := Button.new()
		all.name = "all"
		all.text = "모두 합성"
		all.custom_minimum_size = Vector2(150, 50)
		all.focus_mode = Control.FOCUS_NONE
		GatePanel.paint_stone_button(all, frame_box, 20)
		all.pressed.connect(func() -> void: fuse_requested.emit(grade, true))
		row.add_child(all)
		_fuse_view.add_child(row)
		_fuse_rows[grade] = {"spare": spare, "one": one, "all": all}
	_fuse_note = _label("", 20, IVORY)
	_fuse_note.name = "fuse_note"
	_fuse_view.add_child(_fuse_note)
	_fuse_cards = HBoxContainer.new()
	_fuse_cards.name = "fuse_cards"
	_fuse_cards.add_theme_constant_override("separation", 12)
	_fuse_view.add_child(_fuse_cards)


## 합성 줄의 여분 수와 단추 켜짐 — 여분이 `fuse_cost` 장 이상이어야 켜진다
func _fill_fuse() -> void:
	var owned: Dictionary = _me.get("trainers", {})
	for grade in _fuse_rows:
		var row: Dictionary = _fuse_rows[grade]
		var have := Trainers.spare(owned, int(grade))
		(row.spare as Label).text = "여분 %d장" % have
		var ok := have >= Trainers.fuse_cost()
		(row.one as Button).disabled = not ok
		(row.all as Button).disabled = not ok


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


## 한 장 찍혔다 — 보이는 카드(목록 · 합성 결과)의 빈 그림을 채운다
func _on_baked(id: String, texture: Texture2D) -> void:
	for box in [_grid, _fuse_cards]:
		var card: Node = box.get_node_or_null("card_%s" % id)
		if card != null:
			(card.find_child("art", true, false) as TextureRect).texture = texture


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
