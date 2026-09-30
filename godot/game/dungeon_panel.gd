class_name DungeonPanel
extends GatePanel

## 던전 창 — 가방 옆 "던전" 단추로 연다. **전체 화면이고, 두 겹이다**:
##
##   종류 셋(세로로 긴 카드 셋) ─(열린 카드를 누르면)─ 단계 창(던전 창 **위에** 뜬다)
##                                                  └ 단계를 고르고 "입장" ─ travel
##
## 카드는 받은 그림(2026-09-28, 다른 게임의 던전 창)대로 조립한다 — 위에 청동 장식,
## 닳은 돌판 틀, 꽉 찬 풍경, 이름·구분선·권장 레벨, 맨 아래 "입장 가능".
## 단계 창도 받은 그림(같은 날 둘째 장)대로다 — 왼쪽 단계 목록 · 가운데 보상 ·
## 오른쪽 보스, 오른쪽 아래 "입장". **단계를 누르면 고르기만 하고 떠나지 않는다.**
## 단계 목록은 차원문 창(`GatePanel`)의 줄·누름·끌기를 그대로 물려받는다.
## 표는 `zones.json` 의 `dungeons` (shared 의 dungeons.ts) → docs/features/dungeons.md

const TYPE_KEY := "type:"
## 닫힌 종류에 붙는 말
const LOCKED := "준비 중"
const CARD_GAP := 22
## 카드 한 장의 폭. 높이는 화면이 정한다(약 560) — 받은 그림처럼 세로로 길다
const CARD_W := 300.0
## 카드 그림 이름 = `dungeon_<종류 id>` (icons 폴더, 9:16 풍경 288x512). 그림 칸을
## **꽉 채운다**(cover) — 풍경이라 좌우가 조금 잘려도 된다. 그림이 없으면(`sync:godot` 전)
## `CARD_FALLBACK` 을 가운데에 앉힌다
const CARD_ART := "dungeon_"
const CARD_FALLBACK := {"raid": "ui_icon_dungeon"}
const CARD_FALLBACK_ANY := "ui_gate_here"
## 카드 틀 여백(`CARD_MARGIN`)·제목·칸 색은 **차원문 창(`GatePanel`)으로 올렸다** (2026-09-28) —
## 모든 창이 던전 결을 같이 쓰게 되어서다
## 전체 화면 틀 안쪽 여백 — 틀의 테(34)보다 조금 안쪽
const PAGE_PAD := 44
## 그림 칸이 틀 가장자리에서 들어간 거리 — 틀의 닳은 테가 그림을 두른다
const ART_INSET := 22
## 그림 칸이 틀 높이의 어디까지 오나. 그 아래로 이름·레벨·입장 가능이 앉는다
const ART_SHARE := 0.66
## 카드 위 장식(`ui_dungeon_crest`, 384x98)이 틀 위로 솟는 높이와 장식 높이
const CREST_RISE := 26
const CREST_H := 70
const CARD_NAME_SIZE := 30
const CARD_SUB_SIZE := 20
## 막힌 카드는 통째로 이만큼 어둡게
const LOCKED_TINT := Color(0.5, 0.5, 0.5)
const OPEN_TEXT := "입장 가능"

## 단계 창 — 화면에서 차지하는 크기, 칸 폭
const STAGE_SIZE := Vector2(1060, 600)
const STAGE_LIST_W := 200.0
const STAGE_BOSS_W := 250.0
const STAGE_FONT := 26
## 단계 창 뒤 풍경의 밝기 — 받은 그림처럼 흐릿하게 비친다
const STAGE_ART_TINT := Color(1, 1, 1, 0.22)
## 단계 창 뒤로 던전 창을 덮는 어둠
const STAGE_DIM := Color(0, 0, 0, 0.6)
const REWARD_ICON := 52
const REWARD_FONT := 22
const ENTER_TEXT := "입장"
const ENTER_SIZE := Vector2(200, 60)

## 지금 펼친 종류 id. 비었으면 단계 창이 닫혀 있다
var _type := ""
var _here := ""
## 단계 창에서 고른 존 id
var _stage := ""
## 종류 카드가 놓이는 줄
var _cards: HBoxContainer
## 물건 아이콘 이름 (`game.gd` 의 `_item_icon`). 없으면 슬롯 그림
var _item_icon := Callable()

## 단계 창 — 던전 창 위에 덮인다
var _stages: Control
var _stage_title: Label
var _stage_art: TextureRect
var _stage_close: Button
var _rewards: GridContainer
var _boss: VBoxContainer
var _enter: Button


static func make(frame_box := Callable(), icon := Callable(), item_icon := Callable()) -> DungeonPanel:
	var panel := DungeonPanel.new()
	panel._frame_box = frame_box
	panel._icon = icon
	panel._item_icon = item_icon
	panel._build()
	panel.name = "DungeonPanel"
	# **전체 화면이다** (2026-09-28 요청). 틀은 카드와 같은 닳은 돌판이다
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", panel._box("ui_dungeon_card", CARD_MARGIN, PAGE_PAD))
	panel._restyle_title(panel._title, "던전", "ui_icon_dungeon")

	var column := panel._scroll.get_parent()
	panel._cards = HBoxContainer.new()
	panel._cards.name = "Cards"
	panel._cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel._cards.alignment = BoxContainer.ALIGNMENT_CENTER
	panel._cards.add_theme_constant_override("separation", CARD_GAP)
	column.add_child(panel._cards)
	# 물려받은 목록은 단계 창 왼쪽 칸으로 옮긴다
	column.remove_child(panel._scroll)
	panel._build_stages()
	return panel


## 카드 수·카드 (테스트용)
func card_count() -> int:
	return _cards.get_child_count()


func card(i: int) -> Button:
	return _cards.get_child(i) as Button


## 단계 창이 떠 있나 · 고른 단계 · 보상 칸 수 (테스트용)
func stages_open() -> bool:
	return _stages.visible


func picked_stage() -> String:
	return _stage


func reward_count() -> int:
	return _rewards.get_child_count()


func enter_button() -> Button:
	return _enter


func close_button() -> Button:
	return _stage_close


## 열 때는 늘 종류 셋부터 — 지난번에 펼친 단계 창이 남아 있으면 어디인지 헷갈린다
func open(current_zone: String) -> void:
	_type = ""
	_here = current_zone
	super.open(current_zone)


func _fill(_current_zone: String) -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	for type in GameData.dungeons():
		_add_card(type)
	_show_stages(_type)


## 종류 카드 한 장 — 받은 그림(2026-09-28)의 카드를 조각으로 조립한다.
##
##      ~~<장식>~~       ui_dungeon_crest — 틀 위로 CREST_RISE 만큼 솟는다
##   ┌──────────┐
##   │   풍경   │     dungeon_<id> — 그림 칸을 꽉 채우고 아래로 판 색에 녹는다
##   │ 토벌 던전 │
##   │ ───◆─── │
##   │Lv.9 ~ 199│
##   │✦입장 가능✦│    닫힌 종류는 "준비 중"
##   └──────────┘     ui_dungeon_card (9조각)
##
## 단계 수를 적던 칩은 뺐다 (2026-09-28 요청: "단계 적어놓은 부분 제거해").
## 누르면 통째로 밝아지고 `ROW_SINK` 만큼 내려앉는다 (줄과 같은 누름 표시)
func _add_card(type: Dictionary) -> Button:
	var id := str(type.get("id", ""))
	var on := bool(type.get("open", false))
	var stages: Array = type.get("stages", [])
	var card := Button.new()
	card.name = "Card_" + id
	card.custom_minimum_size.x = CARD_W
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.disabled = not on
	card.focus_mode = Control.FOCUS_NONE
	card.set_meta("zone", TYPE_KEY + id)
	# 틀은 단추가 아니라 안쪽 판이 그린다 — 장식이 틀 위로 솟아야 해서다
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		card.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	var inner := Control.new()
	inner.name = "Inner"
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inner)

	var frame := Panel.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_top = CREST_RISE
	frame.add_theme_stylebox_override("panel", _box("ui_dungeon_card", CARD_MARGIN, 0))
	inner.add_child(frame)

	# 그림 칸 — 자식을 잘라 풍경이 틀 밖으로 안 넘친다
	var window := Control.new()
	window.name = "Window"
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.anchor_right = 1.0
	window.anchor_bottom = ART_SHARE
	window.offset_left = ART_INSET
	window.offset_right = -ART_INSET
	window.offset_top = ART_INSET
	frame.add_child(window)

	var art := TextureRect.new()
	art.name = "Art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture = _piece(CARD_ART + id)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if art.texture == null:
		art.texture = _piece(str(CARD_FALLBACK.get(id, CARD_FALLBACK_ANY)))
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	window.add_child(art)
	# 그림 아래쪽이 판 색으로 녹는다 — 이름이 그림 위에 얹혀도 읽힌다
	var fade := TextureRect.new()
	fade.name = "Fade"
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.anchor_top = 0.55
	fade.anchor_right = 1.0
	fade.anchor_bottom = 1.0
	fade.texture = _fade_texture()
	window.add_child(fade)

	# 아래 글자 묶음 — 이름은 그림이 녹는 자리에 걸친다
	var text := VBoxContainer.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.anchor_top = ART_SHARE - 0.08
	text.anchor_right = 1.0
	text.anchor_bottom = 1.0
	text.offset_left = ART_INSET
	text.offset_right = -ART_INSET
	text.offset_bottom = -CARD_MARGIN - 6
	text.add_theme_constant_override("separation", 10)
	frame.add_child(text)
	var title := _card_label(str(type.get("name", "")), CARD_NAME_SIZE, TEXT_COLOR)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	text.add_child(title)
	text.add_child(_divider())
	var levels := ""
	if not stages.is_empty():
		levels = "권장 Lv.%d ~ %d" % [int(stages[0].get("level", 0)), int(stages[-1].get("level", 0))]
	text.add_child(_card_label(levels, CARD_SUB_SIZE, CARD_SUB_COLOR))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(gap)
	text.add_child(_status(OPEN_TEXT if on else LOCKED, CARD_GOLD if on else HERE_COLOR))

	# 위 장식 — 틀 윗변에 걸쳐 솟는다
	var crest := TextureRect.new()
	crest.name = "Crest"
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest.texture = _piece("ui_dungeon_crest")
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.anchor_right = 1.0
	crest.offset_left = -6
	crest.offset_right = 6
	crest.offset_bottom = CREST_H
	crest.visible = crest.texture != null
	inner.add_child(crest)

	var base := LOCKED_TINT if not on else Color.WHITE
	inner.modulate = base
	# 누르면 통째로 달아오르고 내려앉는다 — 줄과 같은 누름 표시
	card.button_down.connect(func():
		inner.modulate = PRESS_TINT
		inner.offset_top = ROW_SINK
		inner.offset_bottom = ROW_SINK)
	card.button_up.connect(func():
		inner.modulate = base
		inner.offset_top = 0
		inner.offset_bottom = 0)
	card.pressed.connect(_on_pick.bind(TYPE_KEY + id))
	_cards.add_child(card)
	return card


## 단계 창을 짓는다 (한 번). 받은 그림(2026-09-28 둘째 장)의 배치다:
##
##   ┌ [문장] 토벌 던전 ──────────────────────── X ┐
##   │ 1단계 │ [아이콘] 보상 이름   [아이콘] …  │ Lv.9    │
##   │ 2단계 │ …                               │ 보스 이름 │
##   │ …     │        (뒤에 풍경이 흐릿하게)     │          │
##   │       │                                 │  [ 입장 ] │
##   └──────────────────────────────────────────────┘
##
## 던전 창 **위에 덮인다** — 카드를 눌러도 던전 창은 닫히지 않는다 (2026-09-28 요청)
func _build_stages() -> void:
	_stages = Control.new()
	_stages.name = "Stages"
	_stages.visible = false
	_stages.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stages)

	var dim := ColorRect.new()
	dim.color = STAGE_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 던전 창 틀 안쪽 여백까지 덮는다
	dim.offset_left = -PAGE_PAD + CARD_MARGIN * 0.5
	dim.offset_top = -PAGE_PAD + CARD_MARGIN * 0.5
	dim.offset_right = PAGE_PAD - CARD_MARGIN * 0.5
	dim.offset_bottom = PAGE_PAD - CARD_MARGIN * 0.5
	_stages.add_child(dim)

	var window := PanelContainer.new()
	window.name = "StageWindow"
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.offset_left = -STAGE_SIZE.x * 0.5
	window.offset_right = STAGE_SIZE.x * 0.5
	window.offset_top = -STAGE_SIZE.y * 0.5
	window.offset_bottom = STAGE_SIZE.y * 0.5
	window.add_theme_stylebox_override("panel", _box("ui_dungeon_card", CARD_MARGIN, 30))
	_stages.add_child(window)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	window.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	_stage_title = Label.new()
	_stage_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_stage_title)
	_restyle_title(_stage_title, "", "ui_icon_dungeon")
	_stage_close = _close_button()
	_stage_close.name = "StageClose"
	_stage_close.pressed.connect(_show_stages.bind(""))
	head.add_child(_stage_close)

	var line := ColorRect.new()
	line.color = HEAD_LINE
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	# 몸통 — 뒤에 그 던전 풍경이 흐릿하게 깔린다
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	column.add_child(body)
	_stage_art = TextureRect.new()
	_stage_art.name = "StageArt"
	_stage_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_stage_art.modulate = STAGE_ART_TINT
	body.add_child(_stage_art)

	var cols := HBoxContainer.new()
	cols.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cols.add_theme_constant_override("separation", 14)
	body.add_child(cols)

	# 왼쪽 — 단계 목록 (차원문 창의 끌어서 내리는 목록 그대로)
	_scroll.custom_minimum_size.x = STAGE_LIST_W
	_scroll.size_flags_horizontal = 0
	cols.add_child(_scroll)

	# 가운데 — 그 단계 보스가 주는 것
	var middle := ScrollContainer.new()
	middle.name = "Rewards"
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(middle)
	_rewards = GridContainer.new()
	_rewards.columns = 2
	_rewards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rewards.add_theme_constant_override("h_separation", 8)
	_rewards.add_theme_constant_override("v_separation", 8)
	middle.add_child(_rewards)

	# 오른쪽 — 보스, 아래에 입장
	var right := PanelContainer.new()
	right.custom_minimum_size.x = STAGE_BOSS_W
	right.add_theme_stylebox_override("panel", _cell_box())
	cols.add_child(right)
	var right_col := VBoxContainer.new()
	right.add_child(right_col)
	_boss = VBoxContainer.new()
	_boss.name = "Boss"
	_boss.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_boss.add_theme_constant_override("separation", 6)
	right_col.add_child(_boss)
	_enter = Button.new()
	_enter.name = "Enter"
	_enter.text = ENTER_TEXT
	_enter.custom_minimum_size = ENTER_SIZE
	_enter.size_flags_horizontal = Control.SIZE_SHRINK_END
	_enter.focus_mode = Control.FOCUS_NONE
	paint_button_text(_enter, 28)
	# 입장은 단추 조각(`ui_button`) 그대로다 — 줄만 평평하다(`_row_box`)
	for state in ["normal", "hover", "disabled", "focus"]:
		_enter.add_theme_stylebox_override(state, _button_box(false))
	_enter.add_theme_stylebox_override("pressed", _button_box(true))
	_enter.add_theme_stylebox_override("hover_pressed", _button_box(true))
	_enter.pressed.connect(_on_enter)
	right_col.add_child(_enter)


## 다른 창과 같은 X 조각 (그림이 없으면 글자 X)
func _close_button() -> Button:
	var close := Button.new()
	close.custom_minimum_size = Vector2(CLOSE_BTN, CLOSE_BTN)
	close.expand_icon = true
	close.focus_mode = Control.FOCUS_NONE
	close.icon = _piece("ui_close")
	if close.icon == null:
		close.text = "X"
	for state in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return close


## 단계 창을 연다(`type_id`) · 닫는다(빈 문자열). 던전 창은 그대로 둔다
func _show_stages(type_id: String) -> void:
	_forget_hold()
	_type = type_id
	_stages.visible = type_id != ""
	_clear_rows()
	if type_id == "":
		return
	var picked := _find(type_id)
	_stage_title.text = str(picked.get("name", "던전"))
	_stage_art.texture = _piece(CARD_ART + type_id)
	var first := ""
	for s in picked.get("stages", []):
		var zone_id := str(s.get("zone", ""))
		# 지금 들어와 있는 단계는 막는다 — 같은 존으로의 travel 은 World 가 버린다
		var here := zone_id == _here
		var row := _add_row("%d단계" % int(s.get("stage", 0)), zone_id, here, null)
		row.add_theme_font_size_override("font_size", STAGE_FONT)
		row.custom_minimum_size.y = 52
		if first == "" and not here:
			first = zone_id
	_scroll.scroll_vertical = 0
	_select(first)


## 단계를 고른다 — 줄을 금빛으로, 보상·보스를 그 단계 것으로 바꾼다. **떠나지 않는다**
func _select(zone_id: String) -> void:
	_stage = zone_id
	for child in _rows.get_children():
		var row := child as Button
		if row.disabled:
			continue
		var on := str(row.get_meta("zone", "")) == zone_id
		row.add_theme_stylebox_override("normal", _row_box(on))
		row.add_theme_color_override("font_color", CARD_GOLD if on else TEXT_COLOR)
	for child in _rewards.get_children():
		_rewards.remove_child(child)
		child.queue_free()
	for child in _boss.get_children():
		_boss.remove_child(child)
		child.queue_free()
	_enter.disabled = zone_id == ""
	var stage := _stage_def(zone_id)
	if stage.is_empty():
		return
	var level := int(stage.get("level", 0))
	# 토벌은 보스, 시련의 탑은 나오는 일반 몬스터와 규칙("30초 · 7마리")
	var boss := GameData.monster_kind(str(stage.get("boss", stage.get("monster", ""))))
	_boss.add_child(_card_label("Lv.%d" % level, CARD_SUB_SIZE, CARD_SUB_COLOR))
	var name_label := _card_label(str(boss.get("name", "")), CARD_NAME_SIZE - 4, TEXT_COLOR)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_boss.add_child(name_label)
	if int(stage.get("kills", 0)) > 0:
		var rule := _card_label("%d초 안에 %d마리" % [int(stage.get("seconds", 30)), int(stage.kills)], CARD_SUB_SIZE, CARD_GOLD)
		rule.name = "trial_rule"
		_boss.add_child(rule)
	for reward in _stage_rewards(stage):
		_rewards.add_child(_reward_cell(reward))


## 그 단계 보스가 주는 것 — **판정이 주는 것 그대로다.** 던전은 클리어의
## **스킬 경험치**(`skillExp`, `ledger.gd` 의 `_check_dungeon_clear`)와 헬스 **프로틴 세 종**을 준다 —
## 장비·크리스탈·골드는 뺐다 (2026-09-29 요청). 시련의 탑은 통과 보상 크리스탈 한 칸이 더 있다
func _stage_rewards(stage: Dictionary) -> Array:
	var out: Array = []
	var skill_exp := int(stage.get("skillExp", 0))
	# **보이는 스킬이 없으면 숨긴다** (2026-09-29 요청: "던전의 스킬 경험치 숨김 처리해").
	# 판정은 그대로 쌓는다 — 스킬 표의 `hidden` 을 풀면 곧바로 다시 뜬다
	if skill_exp > 0 and Skills.actives_shown(World.DEFAULT_JOB):
		out.append({"name": "스킬 경험치 %d" % skill_exp, "icon": "ui_icon_skill", "color": CARD_GOLD})
	# 시련의 탑 통과 보상 — 크리스탈 단계 × 1개 (`Ledger.trial_clear`). 이것도 한 칸만
	var trial_crystals := int(stage.get("crystals", 0))
	if trial_crystals > 0:
		out.append({"name": "크리스탈 %d개" % trial_crystals, "icon": Items.crystal_id(), "color": CARD_GOLD})
	# 헬스 프로틴 — 세 종 **각각** 단계 × 5개 (토벌 · 시련 둘 다, docs/features/fitness.md)
	var protein := int(stage.get("protein", 0))
	if protein > 0:
		for kind in Fitness.kinds():
			out.append({
				"name": "%s %d개" % [str(kind.proteinName), protein],
				"icon": "ui_protein_" + str(kind.protein), "color": CARD_GOLD,
			})
	return out


## 보상 한 칸 — 어두운 칸에 등급 색 테를 두른 아이콘 + 이름
func _reward_cell(reward: Dictionary) -> Control:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_theme_stylebox_override("panel", _cell_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	cell.add_child(row)
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(REWARD_ICON, REWARD_ICON)
	var slot_box := StyleBoxFlat.new()
	slot_box.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	slot_box.border_color = reward.get("color", CELL_LINE) if reward.has("grade") else CELL_LINE
	slot_box.set_border_width_all(1)
	slot.add_theme_stylebox_override("panel", slot_box)
	var icon := TextureRect.new()
	icon.texture = _piece(str(reward.get("icon", "")))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.add_child(icon)
	row.add_child(slot)
	var label := _card_label(str(reward.get("name", "")), REWARD_FONT, reward.get("color", TEXT_COLOR))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return cell


func _cell_box() -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = CELL_BG
	box.border_color = CELL_LINE
	box.set_border_width_all(1)
	box.set_content_margin_all(8)
	return box


func _stage_def(zone_id: String) -> Dictionary:
	for s in _find(_type).get("stages", []):
		if str(s.get("zone", "")) == zone_id:
			return s
	return {}


func _on_enter() -> void:
	if _stage == "" or _stage == _here:
		return
	super._on_pick(_stage)


## 그림이 아래로 판 색에 녹는 띠 (위 투명 → 아래 판 색)
func _fade_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(CARD_DARK, 0.0))
	gradient.set_color(1, CARD_DARK)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	return tex


## 이름 아래 구분선 — 가는 금선 가운데에 마름모 하나 (받은 그림처럼)
func _divider() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for i in 3:
		if i == 1:
			row.add_child(_diamond(8, CARD_GOLD))
			continue
		var line := ColorRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = Color(CARD_GOLD, 0.35)
		line.custom_minimum_size = Vector2(0, 1)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(line)
	return row


## 맨 아래 "입장 가능" — 양옆에 작은 마름모 (✦ 는 폰트에 없어서 그린다)
func _status(text: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.name = "Status"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.add_child(_diamond(6, color))
	row.add_child(_card_label(text, CARD_SUB_SIZE, color))
	row.add_child(_diamond(6, color))
	return row


## 45° 돌린 작은 네모. 컨테이너는 돌림을 모르므로 빈 칸 안에 따로 앉힌다
func _diamond(side: float, color: Color) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(side * 1.5, side * 1.5)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot := ColorRect.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.color = color
	dot.size = Vector2(side, side)
	dot.position = Vector2(side * 0.25, side * 0.25)
	dot.pivot_offset = Vector2(side * 0.5, side * 0.5)
	dot.rotation = PI * 0.25
	holder.add_child(dot)
	return holder


func _card_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _find(type_id: String) -> Dictionary:
	for type in GameData.dungeons():
		if str(type.get("id", "")) == type_id:
			return type
	return {}


## 카드를 누르면 **던전 창 위에** 단계 창을, 단계 줄을 누르면 **고르기만** 한다.
## 떠나는 것은 "입장" 뿐이다 (2026-09-28 요청)
func _on_pick(key: String) -> void:
	if key.begins_with(TYPE_KEY):
		_show_stages(key.substr(TYPE_KEY.length()))
		return
	_select(key)
