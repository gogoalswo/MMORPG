extends Control

## 게임을 켜면 처음 뜨는 화면 — **테스트 모드 / 일반 모드** 를 고른다 (2026-09-25 요청).
## 고르면 `PlayMode.current` 에 적고 로딩 막(`loading_screen.gd`)을 덮은 채 `main.tscn` 으로
## 넘어간다. 무적·쿨타임을 켜는 건
## 게임 쪽(`game.gd` 의 `_apply_play_mode`)이 한다 — 여기는 고르기만 한다.
##
## 색은 ui-art-style.md 의 판·금테·상아 글자를 그대로 쓴다. 조각 그림 없이 코드로 그린다
## (시작 화면은 에셋을 안 받은 사람에게도 떠야 한다)

const GAME_SCENE := "res://main.tscn"
const BG := Color("#0e100f")
const PANEL := Color("#191a19")
const GOLD := Color("#b9a46c")
const GOLD_HI := Color("#e3d092")
const TEXT := Color("#ddd6c4")
const DIM := Color("#948c7a")

var test_button: Button
var normal_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var path := "res://assets/fonts/NotoSansKR-subset.ttf"
	theme = Theme.new()
	if ResourceLoader.exists(path):
		theme.default_font = load(path)
	theme.default_font_size = 28

	var back := ColorRect.new()
	back.color = BG
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)

	var title := Label.new()
	title.text = "모드를 고르세요"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", GOLD_HI)
	column.add_child(title)

	test_button = _mode_button("테스트 모드", "무적 · 스킬 쿨타임 0", PlayMode.TEST)
	column.add_child(test_button)
	normal_button = _mode_button("일반 모드", "캐릭터만 만들어 시작", PlayMode.NORMAL)
	column.add_child(normal_button)


## 두 줄짜리 단추 — 위는 모드 이름, 아래는 무엇이 켜지는지. 글자는 Label 로 얹는다
func _mode_button(name: String, note: String, mode: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(420, 120)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = PANEL if state != "pressed" else PANEL.lightened(0.08)
		box.border_color = GOLD_HI if state == "hover" else GOLD
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		button.add_theme_stylebox_override(state, box)
	var lines := VBoxContainer.new()
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(lines)
	for pair in [[name, 34, TEXT], [note, 20, DIM]]:
		var label := Label.new()
		label.text = pair[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", pair[1])
		label.add_theme_color_override("font_color", pair[2])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(label)
	button.pressed.connect(choose.bind(mode))
	return button


## 고른 모드를 적고, 로딩 막(`LoadingScreen`)을 덮은 채 게임으로 넘어간다.
## 막은 루트에 달아서 장면이 바뀌어도 남고, 게임이 자리 잡으면 페이드 아웃으로 걷힌다
func choose(mode: String) -> void:
	PlayMode.current = mode
	test_button.disabled = true
	normal_button.disabled = true
	var curtain := LoadingScreen.new("테스트 모드" if mode == PlayMode.TEST else "일반 모드")
	get_tree().root.add_child(curtain)
	curtain.load_scene(GAME_SCENE)
