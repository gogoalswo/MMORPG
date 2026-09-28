class_name DungeonPanel
extends GatePanel

## 던전 창 — 가방 옆 "던전" 단추로 연다. **두 겹이다**:
##
##   종류 셋(세로로 긴 카드 셋) ─(열린 카드를 누르면)─ 단계 목록 ─(단계를 누르면)─ travel
##
## 종류는 **줄이 아니라 카드**다 (2026-09-23 요청: 세로 네모 셋을 나란히 그린 그림 +
## "던전 타입별로 나오게 하고 이미지를 넣어"). 2026-09-28 에 받은 그림(다른 게임의
## 던전 창)대로 다시 지었다 — 위에 청동 장식, 닳은 돌판 틀, 꽉 찬 풍경, 이름·구분선·
## 권장 레벨, 맨 아래 "입장 가능".
## 단계 목록은 차원문 창(`GatePanel`)의 줄·누름·끌기를 그대로 물려받는다.
## 닫힌 종류(`open: false`)는 흐리게 막혀 눌리지 않는다.
## 표는 `zones.json` 의 `dungeons` (shared 의 dungeons.ts) → docs/features/dungeons.md

const TYPE_KEY := "type:"
const BACK_KEY := "back"
## 닫힌 종류에 붙는 말
const LOCKED := "준비 중"
## 차원문 창(520)보다 넓다 — "20단계 · Lv.199 종말의 사자" 가 한 줄에 들어가야 한다
const DUNGEON_WIDTH := 680.0
## 카드 셋을 펼칠 때의 창 폭 — 받은 그림처럼 화면을 거의 다 쓴다. 카드는 가운데에 모인다
const CARDS_WIDTH := 1200.0
const CARD_GAP := 22
## 카드 한 장의 폭. 높이는 창이 정한다(약 510) — 받은 그림처럼 세로로 길다
const CARD_W := 280.0
## 카드 그림 이름 = `dungeon_<종류 id>` (icons 폴더, 9:16 풍경 288x512). 그림 칸을
## **꽉 채운다**(cover) — 풍경이라 좌우가 조금 잘려도 된다. 그림이 없으면(`sync:godot` 전)
## `CARD_FALLBACK` 을 가운데에 앉힌다
const CARD_ART := "dungeon_"
const CARD_FALLBACK := {"raid": "ui_icon_dungeon"}
const CARD_FALLBACK_ANY := "ui_gate_here"
## 카드 틀(`ui_dungeon_card`, 231x384) 의 9조각 여백. 안쪽 판이 가장자리에서 26~36px 들어가 있다
const CARD_MARGIN := 34
## 그림 칸이 틀 가장자리에서 들어간 거리 — 틀의 닳은 테가 그림을 두른다
const ART_INSET := 22
## 그림 칸이 틀 높이의 어디까지 오나. 그 아래로 이름·레벨·입장 가능이 앉는다
const ART_SHARE := 0.66
## 카드 위 장식(`ui_dungeon_crest`, 384x98)이 틀 위로 솟는 높이와 장식 높이
const CREST_RISE := 26
const CREST_H := 66
## 그림이 아래로 녹아드는 색 — 틀 안쪽 판 색(#1b1c17)이다
const CARD_DARK := Color("#1b1c17")
const CARD_NAME_SIZE := 30
const CARD_SUB_SIZE := 20
const CARD_SUB_COLOR := Color("#c9b98a")
## 맨 아래 "입장 가능" 과 구분선의 금빛
const CARD_GOLD := Color("#dfc97a")
const CHIP_SIZE := 17
## 막힌 카드는 통째로 이만큼 어둡게
const LOCKED_TINT := Color(0.5, 0.5, 0.5)
const OPEN_TEXT := "입장 가능"

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
	panel._cards.alignment = BoxContainer.ALIGNMENT_CENTER
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


## 종류 카드 한 장 — 받은 그림(2026-09-28)의 카드를 조각으로 조립한다.
##
##      ~~<장식>~~       ui_dungeon_crest — 틀 위로 CREST_RISE 만큼 솟는다
##   ┌──────────┐
##   │[20단계]  │     칩 (닫힌 종류는 "준비 중")
##   │   풍경   │     dungeon_<id> — 그림 칸을 꽉 채우고 아래로 판 색에 녹는다
##   │ 토벌 던전 │
##   │ ───◆─── │
##   │Lv.9 ~ 199│
##   │✦입장 가능✦│    닫힌 종류는 "준비 중"
##   └──────────┘     ui_dungeon_card (9조각)
##
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

	# 왼쪽 위 칩 — 단계 수 (닫힌 종류는 "준비 중")
	var chip := PanelContainer.new()
	chip.name = "Chip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.position = Vector2(10, 22)
	chip.add_theme_stylebox_override("panel", _chip_box())
	chip.add_child(_card_label("%d단계" % stages.size() if on else LOCKED, CHIP_SIZE, TEXT_COLOR))
	window.add_child(chip)

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


## 칩 판 — 어두운 반투명 판에 얇은 금선 (아트풍 문서의 칸과 같은 결)
func _chip_box() -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.08, 0.07, 0.8)
	box.border_color = Color(CARD_GOLD, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 1
	box.content_margin_bottom = 2
	return box


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


## 종류를 누르면 단계 목록으로, "뒤로" 면 종류 셋으로, 단계면 그 존으로 간다
func _on_pick(key: String) -> void:
	if key.begins_with(TYPE_KEY) or key == BACK_KEY:
		_type = key.substr(TYPE_KEY.length()) if key != BACK_KEY else ""
		_fill(_here)
		_scroll.scroll_vertical = 0
		return
	super._on_pick(key)
