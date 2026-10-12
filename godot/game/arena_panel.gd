class_name ArenaPanel
extends PanelContainer

## 결투장 창 — **전체 화면** (2026-10-12 요청 "HUD에 결투장 버튼을 만들고, 해당 버튼을 누르면 전체 페이지로
## 결투장 UI가 나오는거야. 랭킹도 있고, 스크롤로 내가 도전할 도전자 목록이 나오면 좋겠어") → docs/features/arena.md
##
##   돌판 틀(ui_dungeon_card, 전체 화면) ──────────────────────────────────────── X
##   │ 결투장                                                                  │
##   │ 상대 캐릭터의 복사본과 자동으로 겨룹니다.                                │
##   ├ 내 기록 ─────────────┬ 도전자 목록 50명 ──────────────────────────────┤
##   │ 이름  Lv.30           │ ┌ 1  푸른늑대   Lv.35  전투력 …  점수 1,490 [도전] ┐ │
##   │ 26위 / 51명 · 1,000점 │ │ 2  검은독수리 …                                 │ │  ← 끌어 굴린다
##   │ 전투력 12,345         │ └─────────────────────────────────────────────────┘ │
##   │ 랭킹 (끌어 굴린다)    │                                                     │
##   │ 1 푸른늑대  1,490     │                                                     │
##
## 표는 `arenaBoard` 답 하나(`Arena.board`) — 서버가 있으면 서버, 없으면 로컬이 짓는다. 도전을 누르면 그 줄
## (**상대 복사본**)을 `challenge_requested` 로 넘긴다 — `game.gd` 가 창을 닫고 결투장으로 보낸다 (`World.start_duel`).
## 못 가는 때(쓰러져 있음)는 `game.gd` 가 안내 줄(`show_notice`)에 적는다

signal challenge_requested(foe: Dictionary)

const STONE_IN := 30
const SIDE_WIDTH := 440.0
## 도전자 한 줄 높이 · 도전 단추
const ROW_HEIGHT := 64.0
const CHALLENGE_SIZE := Vector2(120, 48)
## 제목이 오른쪽 위 X 에 안 걸리게 비워 두는 몫
const TITLE_ROOM := 72

const TITLE := GatePanel.PAGE_TITLE_COLOR
const GOLD := Color("#ceb474")
## 1~3위 밝은 금빛, 내 줄 청록 — 레벨 · 샌드백 랭킹과 같다
const TOP := Color("#f1dc9c")
const ME := ChatLog.EXP
const TEXT := Color("#ddd6c4")
const DIM := Color("#948c7a")

var _frame_box := Callable()

var _me_name: Label
var _me_rank: Label
var _me_power: Label
var _ranking: VBoxContainer
var _challengers: VBoxContainer
var _count: Label
var _notice: Label
## 랭킹 1 · 2 · 3위가 장착 정보대로 서는 시상대 (`ArenaPodium`, 2026-10-12)
var _podium: ArenaPodium


## `frame_box` · `icon` 은 `game.gd` 것을 받는다 (상점 창과 같다)
static func make(frame_box: Callable, icon: Callable) -> ArenaPanel:
	var panel := ArenaPanel.new()
	panel._frame_box = frame_box
	panel._build(frame_box, icon)
	return panel


func _build(frame_box: Callable, icon: Callable) -> void:
	name = "ArenaPanel"
	visible = false
	add_theme_stylebox_override("panel", frame_box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, STONE_IN))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	# 제목 — 왼쪽 문장(메뉴 아이콘, 없으면 숨김) + 상아빛 글자 + 밑줄 (`game.gd` `_stone_title` 과 같은 결)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	column.add_child(head)
	var emblem := TextureRect.new()
	emblem.name = "Emblem"
	emblem.texture = icon.call("ui_icon_arena")
	emblem.custom_minimum_size = Vector2(GatePanel.EMBLEM, GatePanel.EMBLEM)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.visible = emblem.texture != null
	head.add_child(emblem)
	var title := _label("결투장", 30, TITLE)
	title.name = "title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var room := Control.new()
	room.custom_minimum_size = Vector2(TITLE_ROOM, 0)
	head.add_child(room)
	column.add_child(_rule(Vector2(0, 2)))
	var rule_text := _label("상대 캐릭터의 복사본과 자동으로 겨룹니다.", 18, DIM)
	rule_text.name = "rule"
	column.add_child(rule_text)

	var body := HBoxContainer.new()
	body.name = "body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)

	# --- 왼쪽 — 내 기록 · 랭킹 ---
	var side := VBoxContainer.new()
	side.name = "side"
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	var mine := PanelContainer.new()
	mine.name = "mine"
	mine.add_theme_stylebox_override("panel", _cell_box(14))
	side.add_child(mine)
	var mine_stack := VBoxContainer.new()
	mine_stack.add_theme_constant_override("separation", 4)
	mine.add_child(mine_stack)
	_me_name = _label("", 22, TEXT)
	_me_name.name = "me_name"
	mine_stack.add_child(_me_name)
	_me_rank = _label("불러오는 중…", 20, ME)
	_me_rank.name = "me_rank"
	mine_stack.add_child(_me_rank)
	_me_power = _label("", 18, DIM)
	_me_power.name = "me_power"
	mine_stack.add_child(_me_power)

	# 시상대 — 내 기록과 랭킹 사이 (2026-10-12 요청 "랭킹 1,2,3위 장착정보 반영해서 시상대 만들어서 모델링 띄워")
	_podium = ArenaPodium.make()
	side.add_child(_podium)
	side.add_child(_label("랭킹", 22, GOLD))
	var ranking_scroll := _scroll("RankingScroll")
	side.add_child(ranking_scroll)
	_ranking = VBoxContainer.new()
	_ranking.name = "ranking"
	_ranking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ranking.add_theme_constant_override("separation", 6)
	ranking_scroll.add_child(_ranking)
	DragScroll.attach(ranking_scroll, _ranking, 6)

	body.add_child(_rule(Vector2(1, 0)))

	# --- 오른쪽 — 도전자 목록 (끌어 굴린다) ---
	var board := VBoxContainer.new()
	board.name = "board"
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.add_theme_constant_override("separation", 8)
	body.add_child(board)
	var board_head := HBoxContainer.new()
	board.add_child(board_head)
	var board_title := _label("도전자 목록", 22, GOLD)
	board_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_head.add_child(board_title)
	_count = _label("", 18, DIM)
	_count.name = "count"
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	board_head.add_child(_count)
	var challenger_scroll := _scroll("ChallengerScroll")
	board.add_child(challenger_scroll)
	_challengers = VBoxContainer.new()
	_challengers.name = "challengers"
	_challengers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_challengers.add_theme_constant_override("separation", 8)
	challenger_scroll.add_child(_challengers)
	DragScroll.attach(challenger_scroll, _challengers, 8)
	# 도전을 누르면 바뀌는 안내 줄 — 결투가 붙기 전까지
	_notice = _label("", 18, TEXT)
	_notice.name = "notice"
	board.add_child(_notice)


func open() -> void:
	_notice.text = ""
	_me_rank.text = "불러오는 중…"
	visible = true


func close_panel() -> void:
	visible = false


## 답 `{ranking, challengers, me: {rank, score, power, level, name}, total}` (`Arena.board`) 으로 다시 짓는다
func fill(board: Dictionary) -> void:
	var me: Dictionary = board.get("me", {})
	_me_name.text = "%s  Lv.%d" % [str(me.get("name", "")), int(me.get("level", 1))]
	_me_rank.text = "%d위 / %d명 · 점수 %s" % [
		int(me.get("rank", 0)), int(board.get("total", 0)), _commas(int(me.get("score", 0)))]
	_me_power.text = "전투력 %s" % _commas(int(me.get("power", 0)))

	for child in _ranking.get_children():
		_ranking.remove_child(child)
		child.queue_free()
	var top: Array = board.get("ranking", []).slice(0, 3)
	_podium.show_top(top, get_theme_default_font())
	for row in board.get("ranking", []):
		_ranking.add_child(_rank_row(row))

	for child in _challengers.get_children():
		_challengers.remove_child(child)
		child.queue_free()
	var list: Array = board.get("challengers", [])
	for row in list:
		_challengers.add_child(_challenger_row(row))
	_count.text = "%d명" % list.size()


func ranking_rows() -> Array:
	return _ranking.get_children()


func challenger_rows() -> Array:
	return _challengers.get_children()


func notice_text() -> String:
	return _notice.text


func show_notice(text: String) -> void:
	_notice.text = text


## 랭킹 한 줄 — 순위 · 이름 · 점수. 1~3위 밝은 금빛, 내 줄 청록
func _rank_row(row: Dictionary) -> Control:
	var rank := int(row.get("rank", 0))
	var tint := TEXT
	if bool(row.get("me", false)):
		tint = ME
	elif rank <= 3:
		tint = TOP
	var line := HBoxContainer.new()
	line.name = "me" if bool(row.get("me", false)) else "row"
	line.add_theme_constant_override("separation", 12)
	var place := _label("%d" % rank, 20, tint)
	place.custom_minimum_size = Vector2(48, 0)
	line.add_child(place)
	var who := _label(str(row.get("name", "")), 20, tint)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.clip_text = true
	line.add_child(who)
	var score := _label(_commas(int(row.get("score", 0))), 20, tint)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(score)
	return line


## 도전자 한 줄 — 어두운 칸에 순위 · 이름 · 레벨 · 전투력 · 점수 · [도전].
## 줄을 덮는 투명한 `hit` 이 칸 바로 아래 자식이라 줄 어디를 눌러도 도전이다 (`DragScroll` 은 칸의 `hit` 만 찾는다 —
## 끌면 굴리고, 그 자리에서 떼면 누름). 보이는 [도전] 단추(`challenge`)는 그림이다 — 목록 안의 것은 입력을 비킨다
func _challenger_row(row: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "challenger"
	card.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	card.add_theme_stylebox_override("panel", _cell_box(10))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	card.add_child(line)
	var rank := int(row.get("rank", 0))
	var place := _label("%d" % rank, 22, TOP if rank <= 3 else TEXT)
	place.custom_minimum_size = Vector2(52, 0)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(place)
	var who := _label(str(row.get("name", "")), 22, TEXT)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	who.clip_text = true
	line.add_child(who)
	for text in [
		"Lv.%d" % int(row.get("level", 1)),
		"전투력 %s" % _commas(int(row.get("power", 0))),
		"점수 %s" % _commas(int(row.get("score", 0))),
	]:
		var stat := _label(text, 18, DIM)
		stat.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(stat)
	var challenge := Button.new()
	challenge.name = "challenge"
	challenge.text = "도전"
	challenge.custom_minimum_size = CHALLENGE_SIZE
	challenge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	challenge.focus_mode = Control.FOCUS_NONE
	GatePanel.paint_stone_button(challenge, _frame_box, 20)
	line.add_child(challenge)
	var hit := Button.new()
	hit.name = "hit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var copy := row.duplicate(true)
	hit.pressed.connect(func() -> void: challenge_requested.emit(copy))
	card.add_child(hit)
	return card


func _scroll(node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return scroll


## 어두운 평판 + 가는 흙금빛 선 — 창 안 칸의 결 (ui-art-style.md "창은 던전 결")
func _cell_box(margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = GatePanel.CELL_BG
	box.border_color = GatePanel.CELL_LINE
	box.set_border_width_all(1)
	box.set_content_margin_all(margin)
	return box


## 55000 → "55,000"
static func _commas(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


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
