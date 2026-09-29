class_name DungeonResult
extends PanelContainer

## 던전 결과창 — **모든 던전**(토벌 · 시련의 탑)에서 성공이든 실패든 뜨고, **확인**을 누르면 마을로 나간다
## (2026-09-29 요청: 시련의 탑 "결과창 UI 만들어서 성공, 실패 및 보상 아이템 표시하고 확인 누르면 나가게"
## → "모든 던전을 결과창 UI 나오게 만들어"). 판정은 World(`_run`)가 했고, 이 창은 `dungeonResult`
## 이벤트를 그리기만 한다 → docs/features/dungeons.md "결과창"
##
##   돌판 틀(ui_dungeon_card) ─┬─ 제목 "토벌 던전 N단계" / "시련의 탑 N단계"
##                            ├─ 큰 글자 "성공" / "실패" · (시련만) 처치 k / 7
##                            ├─ 가르는 선
##                            ├─ 보상 칸 [스킬] 스킬 경험치 N · [크리스탈] 크리스탈 xN   (실패면 "보상 없음")
##                            └─ 단추 "확인"
##
## 닫기 X 는 없다 — 나가는 길이 확인 하나라서다. 결은 전직 창과 같다 (ui-art-style.md "창은 던전 결")

signal confirmed

const WIDTH := 520.0
const STONE_IN := 30
const PAD := 4
const BUTTON_MARGIN := 28
const SINK := 3
const REWARD_ICON := 64

const TITLE := GatePanel.PAGE_TITLE_COLOR
const IVORY := Color("#eeead7")
const DIM := Color("#948c7a")
const FAINT := Color("#4a4234")
const OK := Color("#a9c77a")
const WARN := Color("#d9644f")

var _frame_box := Callable()
var _icon := Callable()

var _title: Label
var _verdict: Label
var _count: Label
var _rewards: VBoxContainer
var _button: Button


## `frame_box` · `icon` 은 `game.gd` 것을 받는다 (전직 창과 같다)
static func make(frame_box: Callable, icon: Callable) -> DungeonResult:
	var panel := DungeonResult.new()
	panel._frame_box = frame_box
	panel._icon = icon
	panel._build()
	return panel


func _build() -> void:
	name = "DungeonResult"
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", _frame_box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, STONE_IN))
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, PAD)
	add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	pad.add_child(column)

	_title = _label("", 26, TITLE)
	_title.name = "title"
	column.add_child(_title)
	_verdict = _label("", 56, OK)
	_verdict.name = "verdict"
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_verdict)
	_count = _label("", 22, IVORY)
	_count.name = "count"
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_count)
	var rule := ColorRect.new()
	rule.color = FAINT
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)
	column.add_child(_label("보상", 18, DIM))
	_rewards = VBoxContainer.new()
	_rewards.name = "rewards"
	_rewards.add_theme_constant_override("separation", 8)
	column.add_child(_rewards)

	_button = Button.new()
	_button.name = "confirm"
	_button.text = "확인"
	_button.custom_minimum_size = Vector2(0, 70)
	_button.focus_mode = Control.FOCUS_NONE
	GatePanel.paint_button_text(_button, 26)
	_button.add_theme_stylebox_override("normal", _button_box(false))
	_button.add_theme_stylebox_override("hover", _button_box(false))
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.add_theme_stylebox_override("pressed", _button_box(true))
	_button.pressed.connect(func() -> void:
		visible = false
		confirmed.emit()
	)
	column.add_child(_button)


## `World._finish_run` 그대로 — `{dungeon, name, stage, result, kills, need, skill_exp, crystals}`
func show_result(event: Dictionary) -> void:
	var clear := str(event.get("result", "")) == "clear"
	_title.text = "%s %d단계" % [str(event.get("name", "던전")), int(event.get("stage", 0))]
	_verdict.text = "성공" if clear else "실패"
	_verdict.add_theme_color_override("font_color", OK if clear else WARN)
	# 처치 수는 시련의 탑만 — 토벌은 보스 한 마리라 셀 것이 없다
	_count.visible = int(event.get("need", 0)) > 0
	_count.text = "처치 %d / %d" % [int(event.get("kills", 0)), int(event.get("need", 0))]
	for child in _rewards.get_children():
		_rewards.remove_child(child)
		child.queue_free()
	var skill_exp := int(event.get("skill_exp", 0))
	if skill_exp > 0:
		_rewards.add_child(_reward_cell("ui_icon_skill", "스킬 경험치 %d" % skill_exp))
	var crystals := int(event.get("crystals", 0))
	if crystals > 0:
		_rewards.add_child(_reward_cell(Items.crystal_id(), "%s x%d" % [Items.stack_name({"id": Items.crystal_id()}), crystals]))
	if _rewards.get_child_count() == 0:
		var none := _label("보상 없음", 20, DIM)
		none.name = "no_reward"
		_rewards.add_child(none)
	visible = true


func confirm_button() -> Button:
	return _button


func reward_count() -> int:
	return _rewards.get_child_count() if _rewards.get_node_or_null("no_reward") == null else 0


## 보상 한 칸 — 던전 단계 창의 보상 칸과 같은 평판 + 아이콘 + 이름
func _reward_cell(icon_name: String, text: String) -> Control:
	var cell := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = GatePanel.CELL_BG
	box.border_color = GatePanel.CELL_LINE
	box.set_border_width_all(1)
	box.set_content_margin_all(8)
	cell.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	cell.add_child(row)
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(REWARD_ICON, REWARD_ICON)
	var slot_box := StyleBoxFlat.new()
	slot_box.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	slot_box.border_color = GatePanel.CELL_LINE
	slot_box.set_border_width_all(1)
	slot.add_theme_stylebox_override("panel", slot_box)
	var icon := TextureRect.new()
	icon.texture = _icon.call(icon_name) if _icon.is_valid() else null
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.add_child(icon)
	row.add_child(slot)
	var label := _label(text, 24, GatePanel.CARD_GOLD)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return cell


func _button_box(pressed: bool) -> StyleBox:
	var box: StyleBox = _frame_box.call("ui_button", BUTTON_MARGIN, 12)
	var sink: int = SINK if pressed else 0
	box.content_margin_top = 12 + sink
	box.content_margin_bottom = 12 - sink
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = GatePanel.PRESS_TINT if pressed else Color.WHITE
	return box


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
