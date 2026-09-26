class_name JobPanel
extends PanelContainer

## 전직 창 — 전직관에게 말을 걸면 뜬다 (docs/features/job-advance.md).
## **그림 한 장이 아니라 조각을 조립한다** (CLAUDE.md). 조각은 스킬창·차원문 창과 같은
## 얇은 금테 결이다 (docs/features/ui-art-style.md):
##
##   창 바탕(ui_panel) ─ 여백 ─┬─ 제목 "전직" · NPC 이름            [X]
##                            ├─ 가르는 금선
##                            ├─ 단계 줄  ●──●──◉──○──○   (기본 · 1차 … 4차)
##                            ├─ 카드(ui_slot) ─ [해금 스킬 칸] 다음 전직 · 조건 두 줄
##                            └─ 단추(ui_button) "N차 전직 시험 입장"
##
## 처음 판(2026-09-26)은 고도 기본 패널에 글자·단추만 쌓았다가 **"UI 가 너무 엉성해"**
## 지적을 받고 이렇게 다시 지었다. 판정은 여전히 World 다 — 창은 `World._job_state` 가
## 준 것을 그리고, 단추는 `advance` 신호만 낸다.

signal advance

const WIDTH := 640.0
## 창 바탕·단추·칸 조각의 9조각 여백 — 스킬창·차원문 창과 같은 값
const PANEL_MARGIN := 26
const BUTTON_MARGIN := 28
const SLOT_MARGIN := 26
const PAD := 30
## 단계 점 한 변과 잇는 선 굵기
const DOT := 30
const LINE := 3
## 해금 스킬 칸 한 변
const SKILL_CELL := 108
const SKILL_INSET := 8
## 누르면 금테가 달아오르고 글자가 내려앉는다 (차원문 창과 같다)
const PRESS_TINT := Color(1.45, 1.3, 1.0)
const SINK := 3

## 색 — ui-art-style.md 의 표에서 가져왔다
const TITLE := Color("#e8c14a")
const GOLD := Color("#dfc97a")
const GOLD_DEEP := Color("#86714d")
const IVORY := Color("#eeead7")
const DIM := Color("#948c7a")
const FAINT := Color("#4a4234")
const DARK := Color("#191a19")
const OK := Color("#a9c77a")
const WARN := Color("#d9644f")

var _frame_box := Callable()
var _icon := Callable()

var _title: Label
var _npc: Label
var _track: HBoxContainer
var _skill_icon: TextureRect
var _skill_empty: Label
var _next_title: Label
var _level_row: Label
var _boss_row: Label
var _unlock_row: Label
var _button: Button


## `frame_box(이름, 9조각 여백, 안쪽 여백)` 과 `icon(이름)` 은 `game.gd` 것을 받는다 —
## 같은 로더를 두 벌 두지 않는다 (GatePanel 과 같다)
static func make(frame_box: Callable, icon: Callable) -> JobPanel:
	var panel := JobPanel.new()
	panel._frame_box = frame_box
	panel._icon = icon
	panel._build()
	return panel


func _build() -> void:
	name = "JobPanel"
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", _frame_box.call("ui_panel", PANEL_MARGIN, 0))
	# 화면 가운데. 앵커로만 잡는다 — 높이는 내용이 정한다
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, PAD)
	add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	pad.add_child(column)

	# 제목 — 닫기 X(오른쪽 위)는 game.gd 의 `_close_button` 이 단다
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	column.add_child(head)
	_title = _label("전직", 32, TITLE)
	head.add_child(_title)
	_npc = _label("", 18, DIM)
	head.add_child(_npc)
	column.add_child(_rule())

	# 단계 줄 — 점 다섯과 잇는 선
	_track = HBoxContainer.new()
	_track.name = "track"
	_track.add_theme_constant_override("separation", 0)
	column.add_child(_track)

	# 다음 전직 카드
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _frame_box.call("ui_slot", SLOT_MARGIN, 18))
	column.add_child(card)
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 22)
	card.add_child(card_row)

	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(SKILL_CELL, SKILL_CELL)
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_theme_stylebox_override("panel", _frame_box.call("ui_slot", SLOT_MARGIN, SKILL_INSET))
	card_row.add_child(cell)
	_skill_icon = TextureRect.new()
	_skill_icon.name = "skill_icon"
	_skill_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skill_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cell.add_child(_skill_icon)
	# 아이콘이 없을 때(4차 · sync 안 함) 칸 가운데 글자
	_skill_empty = _label("", 20, DIM)
	_skill_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skill_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skill_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell.add_child(_skill_empty)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card_row.add_child(info)
	_next_title = _label("", 28, IVORY)
	info.add_child(_next_title)
	_level_row = _label("", 20, IVORY)
	_level_row.name = "level_row"
	info.add_child(_level_row)
	_boss_row = _label("", 20, IVORY)
	_boss_row.name = "boss_row"
	info.add_child(_boss_row)
	_unlock_row = _label("", 20, GOLD)
	_unlock_row.name = "unlock_row"
	info.add_child(_unlock_row)

	# 단추 — 창 폭을 다 쓴다
	_button = Button.new()
	_button.name = "advance"
	_button.custom_minimum_size = Vector2(0, 70)
	_button.add_theme_font_size_override("font_size", 26)
	_button.add_theme_color_override("font_color", IVORY)
	_button.add_theme_color_override("font_hover_color", IVORY)
	_button.add_theme_color_override("font_pressed_color", IVORY)
	_button.add_theme_color_override("font_focus_color", IVORY)
	_button.add_theme_color_override("font_disabled_color", DIM)
	_button.add_theme_stylebox_override("normal", _button_box(false, false))
	_button.add_theme_stylebox_override("hover", _button_box(false, false))
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.add_theme_stylebox_override("pressed", _button_box(true, false))
	_button.add_theme_stylebox_override("disabled", _button_box(false, true))
	_button.pressed.connect(func() -> void: advance.emit())
	column.add_child(_button)


## 창을 채운다. `job` 은 `World._job_state` 가 준 것 그대로다
func fill(npc_name: String, job: Dictionary, level: int, skill_name: Callable) -> void:
	_npc.text = npc_name
	var tier := int(job.get("tier", 0))
	var steps: Array = Skills.job_advances()
	_draw_track(tier, steps)

	var next: Dictionary = job.get("next", {})
	if next.is_empty():
		_skill_icon.texture = null
		_skill_empty.text = "완료"
		_next_title.text = "모든 전직을 마쳤습니다"
		_level_row.text = "%d차 전직" % tier
		_level_row.add_theme_color_override("font_color", DIM)
		_boss_row.text = ""
		_unlock_row.text = ""
		_button.text = "전직 완료"
		_button.disabled = true
		return

	var ready := bool(job.get("ready", false))
	var need := int(next.get("level", 0))
	_next_title.text = "%d차 전직" % int(next.get("tier", tier + 1))
	_level_row.text = "레벨 %d   (지금 %d)" % [need, level]
	_level_row.add_theme_color_override("font_color", OK if level >= need else WARN)
	_boss_row.text = "시험 보스  %s  Lv.%d" % [str(job.get("boss_name", "")), int(next.get("bossLevel", 0))]

	var skills: Array = job.get("skills", [])
	var names: Array = []
	for id in skills:
		names.append(str(skill_name.call(str(id))))
	_unlock_row.text = "해금  %s" % (", ".join(names) if not names.is_empty() else "아직 없음")
	var texture: Texture2D = _icon.call("skill_" + str(skills[0])) if not skills.is_empty() else null
	_skill_icon.texture = texture
	if texture != null:
		_skill_empty.text = ""
	elif not names.is_empty():
		_skill_empty.text = str(names[0])
	else:
		_skill_empty.text = "?"

	_button.disabled = not ready
	_button.text = "%d차 전직 시험 입장" % int(next.get("tier", tier + 1)) if ready \
		else "Lv.%d 에 열립니다" % need


## 기본 · 1차 … 4차. 마친 단계는 금빛으로 채우고, 지금 단계는 한 겹 더 두르고,
## 아직인 단계는 흐린 테만 남긴다. 잇는 선도 마친 데까지 금빛이다
func _draw_track(tier: int, steps: Array) -> void:
	for child in _track.get_children():
		_track.remove_child(child)
		child.queue_free()
	var count := steps.size() + 1
	for i in count:
		if i > 0:
			var line := ColorRect.new()
			line.color = GOLD if i <= tier else FAINT
			line.custom_minimum_size = Vector2(0, LINE)
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			# 점 가운데 높이에 맞춘다
			var holder := MarginContainer.new()
			holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			holder.add_theme_constant_override("margin_top", (DOT - LINE) / 2)
			holder.add_child(line)
			_track.add_child(holder)
		var step := VBoxContainer.new()
		step.name = "step%d" % i
		step.add_theme_constant_override("separation", 6)
		_track.add_child(step)
		var dot := Panel.new()
		dot.name = "dot"
		dot.custom_minimum_size = Vector2(DOT, DOT)
		dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", _dot_box(i, tier))
		step.add_child(dot)
		var name_text := "기본" if i == 0 else "%d차" % i
		var label := _label(name_text, 18, GOLD if i <= tier else DIM)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		step.add_child(label)
		var level := _label("Lv.1" if i == 0 else "Lv.%d" % int(steps[i - 1].get("level", 0)), 14, DIM)
		level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		step.add_child(level)


## 단계 점 — 코드로 그린 둥근 판. 마침(금 채움) · 지금(금 채움 + 밝은 테) · 아직(어두운 판 + 흐린 테)
func _dot_box(i: int, tier: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(DOT / 2)
	box.anti_aliasing = true
	if i < tier:
		box.bg_color = GOLD_DEEP
		box.border_color = GOLD
		box.set_border_width_all(2)
	elif i == tier:
		box.bg_color = GOLD
		box.border_color = IVORY
		box.set_border_width_all(3)
		box.shadow_color = Color(GOLD, 0.45)
		box.shadow_size = 6
	else:
		box.bg_color = DARK
		box.border_color = FAINT
		box.set_border_width_all(2)
	return box


func _button_box(pressed: bool, dim: bool) -> StyleBox:
	var box: StyleBox = _frame_box.call("ui_button", BUTTON_MARGIN, 12)
	var sink: int = SINK if pressed else 0
	box.content_margin_top = 12 + sink
	box.content_margin_bottom = 12 - sink
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = \
			PRESS_TINT if pressed else (Color(0.55, 0.55, 0.55) if dim else Color.WHITE)
	return box


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = FAINT
	rule.custom_minimum_size = Vector2(0, 1)
	return rule


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
