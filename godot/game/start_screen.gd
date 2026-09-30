extends Control

## 게임을 켜면 처음 뜨는 화면 — **테스트 모드 / 일반 모드** 를 고른다 (2026-09-25 요청).
## 테스트 모드는 오른쪽 아래 구석 단추로만 들어간다 (2026-09-29, `_corner_test_button`).
## 고르면 `PlayMode.current` 에 적고 로딩 막(`loading_screen.gd`)을 덮은 채 `main.tscn` 으로
## 넘어간다. 무적·쿨타임을 켜는 건
## 게임 쪽(`game.gd` 의 `_apply_play_mode`)이 한다 — 여기는 고르기만 한다.
##
## 색은 ui-art-style.md 의 판·금테·상아 글자를 그대로 쓴다. 조각 그림 없이 코드로 그린다
## (시작 화면은 에셋을 안 받은 사람에게도 떠야 한다)

const GAME_SCENE := "res://main.tscn"
## 편집기에서 디버그로 띄운 창을 보낼 거리 — 모든 모니터의 오른쪽·아래 끝에서 이만큼 더 민다
const OFFSCREEN_GAP := 4000
const BG := Color("#0e100f")
const PANEL := Color("#191a19")
const GOLD := Color("#b9a46c")
const GOLD_HI := Color("#e3d092")
const TEXT := Color("#ddd6c4")
const DIM := Color("#948c7a")

var test_button: Button
var normal_button: Button
## 이름 입력칸 — **모드 단추가 곧 로그인**이다. 비워 두고 누르면 무작위로 지어 들어간다
## (2026-09-28 요청: "아무것도 입력 안 하고 로그인 누르면 랜덤하게 이름 아무거나 지어서")
var name_input: LineEdit
var _name_note: Label
## 저장 초기화 — **두 번 눌러야 지운다** (2026-09-26 요청: "초기화 버튼을 만들어서 초기화 시켜").
## 모드가 저장 하나를 같이 써서, 테스트 모드에서 치트로 올린 100레벨이 일반 모드에 그대로 떴다
var reset_button: Button
var _reset_note: Label
var _reset_armed := false


func _ready() -> void:
	_hide_debug_window()
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

	column.add_child(_name_row())
	normal_button = _mode_button("일반 모드", "캐릭터만 만들어 시작", PlayMode.NORMAL)
	column.add_child(normal_button)
	reset_button = _mode_button("저장 초기화", "", "")
	reset_button.custom_minimum_size.y = 80
	reset_button.pressed.disconnect(choose)
	reset_button.pressed.connect(_on_reset)
	_reset_note = reset_button.get_child(0).get_child(1)
	column.add_child(reset_button)
	_show_reset(false)
	add_child(_corner_test_button())


## **테스트 모드는 오른쪽 아래 구석의 작은 단추로만 들어간다** (2026-09-29 요청: "오른쪽 아래
## 버튼 눌러야 테스트 모드 들어가도록 변경하고, 현재 보이는 테스트 모드 버튼은 제거해").
## 가운데 열에는 일반 모드만 남는다. 해상도가 바뀌어도 구석에 붙도록 앵커로 자리를 잡는다
func _corner_test_button() -> Button:
	test_button = Button.new()
	test_button.text = "테스트"
	test_button.custom_minimum_size = Vector2(96, 44)
	test_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	test_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	test_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	test_button.add_theme_font_size_override("font_size", 18)
	test_button.add_theme_color_override("font_color", DIM)
	test_button.add_theme_color_override("font_hover_color", TEXT)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = PANEL if state != "pressed" else PANEL.lightened(0.08)
		box.border_color = GOLD_HI if state == "hover" else GOLD.darkened(0.4)
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		test_button.add_theme_stylebox_override(state, box)
	test_button.pressed.connect(choose.bind(PlayMode.TEST))
	return test_button


## 이름 줄 — 입력칸과 그 아래 알림 한 줄. 지난번 이름(저장)이 미리 채워진다
func _name_row() -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	name_input = HangulLineEdit.new()  # 윈도우에서 한글 앞 글자가 지워지는 고도 버그를 메운다
	name_input.custom_minimum_size = Vector2(420, 64)
	name_input.max_length = Names.MAX_LEN
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input.placeholder_text = "이름 (비우면 아무렇게나 짓습니다)"
	name_input.text = str(Save.read().get("name", ""))
	name_input.add_theme_font_size_override("font_size", 28)
	name_input.add_theme_color_override("font_color", TEXT)
	name_input.add_theme_color_override("font_placeholder_color", DIM)
	for state in ["normal", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = PANEL
		box.border_color = GOLD_HI if state == "focus" else GOLD
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		box.set_content_margin_all(8)
		name_input.add_theme_stylebox_override(state, box)
	row.add_child(name_input)
	_name_note = Label.new()
	_name_note.text = "한글·영문·숫자 %d~%d자" % [Names.MIN_LEN, Names.MAX_LEN]
	_name_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_note.add_theme_font_size_override("font_size", 18)
	_name_note.add_theme_color_override("font_color", DIM)
	row.add_child(_name_note)
	return row


## 들어갈 이름 — 비었으면 무작위로 짓는다. 규칙에 안 맞으면 빈 글자(들어가지 않는다)
func resolve_name() -> String:
	var name := Names.clean(name_input.text)
	if name.is_empty():
		name = Names.random()
		name_input.text = name
		return name
	var why := Names.why_invalid(name)
	if not why.is_empty():
		_name_note.text = why
		_name_note.add_theme_color_override("font_color", Color("#d9644f"))
		return ""
	return name


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


## 처음 누르면 되묻고, 한 번 더 누르면 지운다 — 다음에 고르는 모드는 1레벨부터 새로 시작한다
func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_note.text = "한 번 더 누르면 지웁니다"
		_reset_note.add_theme_color_override("font_color", GOLD_HI)
		return
	Save.clear()
	name_input.text = ""  # 이름도 캐릭터와 같이 지운다
	_reset_armed = false
	_show_reset(true)


func _show_reset(cleared: bool) -> void:
	var has_save := FileAccess.file_exists(Save.PATH)
	reset_button.disabled = not has_save
	_reset_note.add_theme_color_override("font_color", DIM)
	if cleared:
		_reset_note.text = "지웠습니다 — 1레벨부터 시작합니다"
	elif has_save:
		_reset_note.text = "캐릭터를 지우고 1레벨부터"
	else:
		_reset_note.text = "저장이 없습니다"


## 고른 모드를 적고, 로딩 막(`LoadingScreen`)을 덮은 채 게임으로 넘어간다.
## 막은 루트에 달아서 장면이 바뀌어도 남고, 게임이 자리 잡으면 페이드 아웃으로 걷힌다
func choose(mode: String) -> void:
	var name := resolve_name()
	if name.is_empty():
		return  # 이름이 규칙에 안 맞는다 — 알림을 보고 고친다
	PlayMode.player_name = name
	PlayMode.current = mode
	test_button.disabled = true
	normal_button.disabled = true
	reset_button.disabled = true
	var curtain := LoadingScreen.new("테스트 모드" if mode == PlayMode.TEST else "일반 모드")
	get_tree().root.add_child(curtain)
	curtain.load_scene(GAME_SCENE)


## **편집기에서 디버그 실행(F5)한 게임 창을 모니터 밖으로 보낸다** (2026-09-28 요청: "고도 엔진
## 디버깅 할 때 오른쪽 아래 화면이 나오는데, 화면에서 아예 안 보이게 멀리 보내").
## 편집기가 실행할 때 `--position` 을 넘겨서 프로젝트 설정(`initial_position`)은 덮인다 — 그래서
## 뜬 뒤에 코드로 옮긴다. 디버거가 붙은 PC 실행에서만 한다: `play.bat`·`npm run shot:godot`
## (디버거 없음)·헤드리스 테스트·폰 원클릭 배포·편집기 Game 탭 임베드는 그대로 둔다
func _hide_debug_window() -> void:
	if not EngineDebugger.is_active() or not OS.has_feature("pc"):
		return
	if Engine.is_embedded_in_editor() or DisplayServer.get_name() == "headless":
		return
	var far := Vector2i.ZERO
	for i in DisplayServer.get_screen_count():
		var end := DisplayServer.screen_get_position(i) + DisplayServer.screen_get_size(i)
		far = Vector2i(maxi(far.x, end.x), maxi(far.y, end.y))
	get_window().position = far + Vector2i(OFFSCREEN_GAP, OFFSCREEN_GAP)
