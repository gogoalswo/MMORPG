class_name DeathPanel
extends PanelContainer

## 사망 창 — 사냥터·마을에서 쓰러지면 뜨고, **확인**을 누르면 마을에서 되살아난다
## (2026-09-30 요청: "캐릭터가 죽으면 사망 UI 나오도록 만들고, 확인 버튼 누르면 마을가게").
## 던전에서 쓰러지면 이 창 대신 던전 결과창("실패")이 뜬다 — 나가는 길은 같다(`revive`).
## 창을 띄우고 거두는 건 `game.gd` 의 `_refresh_status` 가 **상태(`dead`)로** 한다 → combat.md "사망"
##
##   돌판 틀(ui_dungeon_card) ─┬─ 큰 글자 "사망"
##                            ├─ "쓰러졌습니다"
##                            ├─ 가르는 선
##                            ├─ "확인을 누르면 마을에서 되살아납니다"
##                            └─ 단추 "확인"
##
## 닫기 X 는 없다 — 나가는 길이 확인 하나라서다. 결은 던전 결과창과 같다 (ui-art-style.md "창은 던전 결")

signal confirmed

const WIDTH := 460.0
const STONE_IN := 30
const PAD := 4

var _frame_box := Callable()
var _button: Button


## `frame_box` 는 `game.gd` 것을 받는다 (던전 결과창과 같다)
static func make(frame_box: Callable) -> DeathPanel:
	var panel := DeathPanel.new()
	panel._frame_box = frame_box
	panel._build()
	return panel


func _build() -> void:
	name = "DeathPanel"
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

	var title := _label("사망", 56, DungeonResult.WARN)
	title.name = "verdict"
	column.add_child(title)
	column.add_child(_label("쓰러졌습니다", 24, DungeonResult.IVORY))
	var rule := ColorRect.new()
	rule.color = DungeonResult.FAINT
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)
	column.add_child(_label("확인을 누르면 마을에서 되살아납니다", 20, DungeonResult.DIM))

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


func confirm_button() -> Button:
	return _button


func _button_box(pressed: bool) -> StyleBox:
	var box: StyleBox = _frame_box.call("ui_button", DungeonResult.BUTTON_MARGIN, 12)
	var sink: int = DungeonResult.SINK if pressed else 0
	box.content_margin_top = 12 + sink
	box.content_margin_bottom = 12 - sink
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = GatePanel.PRESS_TINT if pressed else Color.WHITE
	return box


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
