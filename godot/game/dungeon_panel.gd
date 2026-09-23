class_name DungeonPanel
extends GatePanel

## 던전 창 — 가방 옆 "던전" 단추로 연다. **두 겹이다**:
##
##   종류 셋(세로로 긴 카드 셋) ─(열린 카드를 누르면)─ 단계 목록 ─(단계를 누르면)─ travel
##
## 종류는 **줄이 아니라 카드**다 (2026-09-23 요청: 세로 네모 셋을 나란히 그린 그림 +
## "던전 타입별로 나오게 하고 이미지를 넣어"). 카드마다 위에 그림, 아래에 이름·단계 수.
## 단계 목록은 차원문 창(`GatePanel`)의 줄·누름·끌기를 그대로 물려받는다.
## 닫힌 종류(`open: false`)는 흐리게 막혀 눌리지 않는다.
## 표는 `zones.json` 의 `dungeons` (shared 의 dungeons.ts) → docs/features/dungeons.md

const TYPE_KEY := "type:"
const BACK_KEY := "back"
## 닫힌 종류에 붙는 말
const LOCKED := "준비 중"
## 차원문 창(520)보다 넓다 — "20단계 · Lv.199 종말의 사자" 가 한 줄에 들어가야 한다
const DUNGEON_WIDTH := 680.0
## 카드 셋을 펼칠 때의 창 폭. 카드 한 장이 약 270 × 500 — 받은 그림처럼 세로로 길다
const CARDS_WIDTH := 920.0
const CARD_GAP := 20
## 카드 그림 이름 = `dungeon_<종류 id>` (icons 폴더). 없으면 `CARD_FALLBACK` 을 가운데에 작게
const CARD_ART := "dungeon_"
const CARD_FALLBACK := {"raid": "ui_icon_dungeon"}
const CARD_FALLBACK_ANY := "ui_gate_here"
const CARD_NAME_SIZE := 30
const CARD_SUB_SIZE := 22
const CARD_SUB_COLOR := Color("#c9b98a")
## 막힌 카드는 통째로 이만큼 어둡게
const LOCKED_TINT := Color(0.5, 0.5, 0.5)

## 지금 펼친 종류 id. 비었으면 종류 셋을 보여 준다
var _type := ""
var _here := ""
## 종류 카드가 놓이는 줄 — 단계 목록(`_scroll`)과 번갈아 보인다
var _cards: HBoxContainer


static func make(frame_box := Callable(), icon := Callable()) -> DungeonPanel:
	var panel := DungeonPanel.new()
	panel._frame_box = frame_box
	panel._icon = icon
	panel._build()
	panel.name = "DungeonPanel"
	panel._title.text = "던전"
	# 카드 줄은 목록 자리에 겹쳐 둔다 (같은 세로 칸을 번갈아 쓴다)
	panel._cards = HBoxContainer.new()
	panel._cards.name = "Cards"
	panel._cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel._cards.add_theme_constant_override("separation", CARD_GAP)
	var column := panel._scroll.get_parent()
	column.add_child(panel._cards)
	column.move_child(panel._cards, panel._scroll.get_index())
	panel._set_width(DUNGEON_WIDTH)
	return panel


func _set_width(width: float) -> void:
	offset_left = -width * 0.5
	offset_right = width * 0.5
	# 줄어들 때 앞서 넓힌 크기가 남지 않게
	size.x = width


## 카드 수·카드 (테스트용)
func card_count() -> int:
	return _cards.get_child_count()


func card(i: int) -> Button:
	return _cards.get_child(i) as Button


## 열 때는 늘 종류 셋부터 — 지난번에 펼친 단계 목록이 남아 있으면 어디인지 헷갈린다
func open(current_zone: String) -> void:
	_type = ""
	_here = current_zone
	super.open(current_zone)


func _fill(_current_zone: String) -> void:
	_clear_rows()
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var cards := _type == ""
	_cards.visible = cards
	_scroll.visible = not cards
	_set_width(CARDS_WIDTH if cards else DUNGEON_WIDTH)
	if cards:
		_title.text = "던전"
		for type in GameData.dungeons():
			_add_card(type)
		return
	var picked := _find(_type)
	_title.text = str(picked.get("name", "던전"))
	_add_row("뒤로", BACK_KEY, false, _here_icon)
	for s in picked.get("stages", []):
		var zone_id := str(s.get("zone", ""))
		var boss := GameData.monster_kind(str(s.get("boss", "")))
		var text := "%d단계  ·  Lv.%d %s" % [int(s.get("stage", 0)), int(s.get("level", 0)), boss.get("name", "")]
		# 지금 들어와 있는 단계는 막는다 — 같은 존으로의 travel 은 World 가 버린다
		var here := zone_id == _here
		_add_row(text, zone_id, here, _here_icon if here else _go_icon)


## 종류 카드 한 장 — 틀은 줄과 같은 단추 조각, 누르면 금테가 달아오르고 내용이 내려앉는다.
##
##   ┌──────────┐
##   │   그림   │  dungeon_<id> (없으면 가운데에 작은 문장)
##   │          │
##   │ 토벌 던전 │
##   │  20단계   │  닫힌 종류는 "준비 중"
##   └──────────┘
func _add_card(type: Dictionary) -> Button:
	var id := str(type.get("id", ""))
	var on := bool(type.get("open", false))
	var card := Button.new()
	card.name = "Card_" + id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	card.clip_contents = true
	card.disabled = not on
	card.focus_mode = Control.FOCUS_NONE
	card.set_meta("zone", TYPE_KEY + id)
	for state in ["normal", "hover", "disabled", "focus"]:
		card.add_theme_stylebox_override(state, _row_box(false))
	card.add_theme_stylebox_override("pressed", _row_box(true))
	card.add_theme_stylebox_override("hover_pressed", _row_box(true))

	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, ROW_PAD_X)
	card.add_child(inner)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 8)
	inner.add_child(body)

	var art := TextureRect.new()
	art.name = "Art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture = _piece(CARD_ART + id)
	if art.texture != null:
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		# 그림이 아직 없으면 문장을 가운데에 작게 둔다 — 빈 칸보다 낫다
		art.texture = _piece(str(CARD_FALLBACK.get(id, CARD_FALLBACK_ANY)))
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.clip_contents = true
	body.add_child(art)

	body.add_child(_card_label(str(type.get("name", "")), CARD_NAME_SIZE, TEXT_COLOR))
	var sub := "%d단계" % (type.get("stages", []) as Array).size() if on else LOCKED
	body.add_child(_card_label(sub, CARD_SUB_SIZE, CARD_SUB_COLOR))

	if not on:
		inner.modulate = LOCKED_TINT
	# 누르면 내용이 내려앉는다 — 줄과 같은 누름 표시
	card.button_down.connect(func(): inner.offset_top = ROW_SINK; inner.offset_bottom = ROW_SINK)
	card.button_up.connect(func(): inner.offset_top = 0; inner.offset_bottom = 0)
	card.pressed.connect(_on_pick.bind(TYPE_KEY + id))
	_cards.add_child(card)
	return card


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


## 종류를 누르면 단계 목록으로, "뒤로" 면 종류 셋으로, 단계면 그 존으로 간다
func _on_pick(key: String) -> void:
	if key.begins_with(TYPE_KEY) or key == BACK_KEY:
		_type = key.substr(TYPE_KEY.length()) if key != BACK_KEY else ""
		_fill(_here)
		_scroll.scroll_vertical = 0
		return
	super._on_pick(key)
