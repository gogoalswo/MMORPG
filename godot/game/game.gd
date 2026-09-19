extends Node3D

## 화면. 상태는 Transport 에서만 받아 그린다 — World 를 직접 만지지 않는다.
##
## 씬 파일 대신 코드로 짓는 이유: 에디터를 못 쓰는 환경에서 .tscn 을 손으로
## 쓰면 틀리기 쉽고, 이 화면은 존 데이터(바닥 크기·하늘색·안개)에서 나오는
## 것이라 어차피 코드가 정한다. 모델·UI 가 들어오는 단계에서 씬으로 옮긴다.
##
## 지금은 **예측/보정이 없다.** 로컬이라 지연이 0 이므로 스냅샷을 그대로 그려도
## 매끄럽다. 서버를 붙이는 단계에서 넣는다 → docs/features/networking-state.md

const STOP_DISTANCE := 0.15

## 가방·장비 창. 가방 격자는 5열 — 웹 클라의 COLUMNS 와 같다
## (docs/features/inventory-equipment.md). 장비는 8칸이라 4열 두 줄로 떨어진다
const BAG_COLUMNS := 5
## 가방에서 한 번에 보이는 줄. 나머지는 끌어 올린다
const BAG_ROWS := 3
## 칸 한 변. 1280x720 안에 장착 두 줄 + 캐릭터 + 가방 5열이 들어가는 크기다
const CELL := 88
## 스킬 칸. 퀵슬롯은 엄지로 누르니 조금 더 크다. 아이콘은 테두리 안쪽으로 SKILL_INSET 만큼 물린다
const QUICK_CELL := 104
const SKILL_CELL := 100
const SKILL_COLUMNS := 4
const SKILL_GAP := 10
const SKILL_INSET := 11
const ICON_DIR := "res://assets/icons/"
## 가방 탭. 0 은 전체, 나머지는 `_tab_keeps` 가 슬롯으로 가른다
const BAG_TABS := ["전체", "무기", "방어구", "장신구", "재료"]
## 스탯 상자에 놓는 여섯 개. 순서가 `_redraw_bag` 의 목록과 같아야 한다
const STAT_NAMES := ["공격력", "방어력", "체력", "치명타", "치명타 피해", "공격 속도"]

var _transport: Transport
var _player: Node3D
## 기둥은 가운데가 원점이라 반만큼 띄워야 하고, 모델은 발이 원점이다
var _player_y := 0.9
## 이번 프레임에 걸었나 (달리기·대기 동작을 고르는 데 쓴다).
## 내가 민 것(`_move`)과 **판정이 옮긴 것(자동 사냥)을 둘 다** 센다 — `_draw_state` 참고
var _moving := false
## 몇 m/s 이상 움직였으면 달리는 것으로 보나. 달리기는 4.6m/s 라 넉넉하고,
## 서버 좌표가 한 번 튀는 정도로는 안 걸린다
const RUN_SPEED_EPS := 0.5
## 카메라 스무딩에 쓴다 — _draw_state 가 델타를 따로 안 받는다
var _last_delta := 0.0
## 공격 동작을 언제까지 트나 (서버가 준 경직 시간)
var _swing_until := 0
var _camera: CameraRig
var _label: Label
var _marker: MeshInstance3D

var _target: Vector3 = Vector3.INF
var _seq := 0
var _half_size := 0.0
## 존마다 다시 짓는 것들(바닥·하늘·몬스터·차원문)은 여기 아래에 둔다.
## 캐릭터·카메라·UI 는 존이 바뀌어도 그대로라 밖에 있다
var _zone_node: Node3D
var _shown_zone := ""
## 눌러 둔 몬스터. 사거리에 들 때까지 걸어가서 계속 친다
var _target_mob := ""
## 골라 둔 몬스터. 발밑에 고리가 돈다 — **땅을 눌러도 안 풀린다**
var _selected_mob := ""
## 골라 둔 놈 발밑의 고리 (game/select_ring.gd). 안 골랐으면 null
var _ring: SelectRing
## 몬스터 id -> 그려 둔 몸. 죽으면 감추고 살아나면 다시 보인다
var _mob_nodes: Dictionary = {}
## 내 머리 위 체력 막대 (game/hp_bar_3d.gd). 늘 보인다
var _player_bar: HpBar3D
## 몬스터 id -> 머리 위 체력 막대. **골라 뒀거나 내가 때린 놈만** 세운다 —
## 사냥터 한 무리가 전부 막대를 달면 화면이 붉은 줄로 덮인다
var _mob_bars: Dictionary = {}
## 몬스터 id -> 때린 막대를 언제까지 보여 주나(ms). 그 뒤에는 치운다
var _mob_bar_until: Dictionary = {}
## 때린 뒤 막대가 남아 있는 시간. 다음 한 대를 칠 때까지는 넉넉히 남아야 하고
## (제일 느린 무기가 1.2초), 지나간 놈 것이 화면에 쌓이면 안 된다
const MOB_BAR_MS := 5000
## 마지막으로 일어난 일 한 줄 (맞았다·레벨 올랐다)
var _last_event := ""
var _ui_root: Control
var _hp_bar: ProgressBar
## 맞았을 때 화면 가장자리가 붉어지는 비네트 (game/hurt_flash.gd)
var _hurt: HurtFlash
var _gate_panel: GatePanel
## 보스 범위 공격 예고. [{node, fill, start, end, radius}, ...]
var _aoe_marks: Array = []
var _npc_panel: PanelContainer
var _npc_title: Label
var _npc_rows: VBoxContainer
var _npc_role := ""
var _npc_tab := ""
var _npc_items: Array = []
## 액션바 4칸. 눌리면 그 스킬을 쓴다
var _bar_buttons: Array = []
## 칸마다 지난 프레임에 쿨타임이 돌고 있었나 — 끝나는 순간을 잡아 번쩍인다
var _bar_cooling: Array = []
## 테스트 스위치 단추 — 이름 → Button
var _switch_buttons: Dictionary = {}
## 자동 사냥 토글. 글자와 색은 **서버가 준 me.auto** 로만 정한다 —
## 눌린 것으로 지레 바꾸면 판정이 거절했을 때 화면만 켜진 채로 남는다
var _auto_button: Button
var _skill_panel: PanelContainer
## 스킬창. 틀은 한 번 짓고 `_redraw_skills` 가 채운다
var _skill_big: PanelContainer
var _skill_name: Label
var _skill_info: Label
var _skill_state: Label
var _skill_desc: Label
var _skill_equip: Button
var _skill_unequip: Button
var _skill_grid: GridContainer
## 목록 칸과 그 칸의 스킬 id (같은 순서). 직업이 바뀌면 다시 짓는다
var _skill_cells: Array = []
var _skill_ids: Array = []
## 창 안의 장착 칸 (퀵슬롯과 같은 순서)
var _slot_cells: Array = []
## 고른 스킬 id. 왼쪽 설명이 이것을 보여 준다
var _skill_pick := ""
## 4칸이 다 찬 채로 장착을 눌렀다 — 다음에 누르는 장착 칸과 바꾼다
var _skill_swap := false
## 가방·장비 창. 틀은 한 번만 짓고 `_redraw_bag` 이 내용만 채운다
var _bag_panel: PanelContainer
var _bag_head: Label
var _bag_gold: Label
var _bag_sum: Label
var _bag_grid: GridContainer
var _bag_detail: Label
var _bag_action: Button
## 고른 칸 — {"where": "equip"|"bag", "index": int}. 비면 아무것도 안 골랐다
var _bag_pick: Dictionary = {}
## 아이콘을 한 번만 찾아 기억해 둔다 (없는 것도 기억한다)
var _icon_cache: Dictionary = {}
## 장착 칸. 캐릭터를 사이에 두고 두 줄로 갈라 세우므로 격자가 아니라 목록으로 든다
var _gear_cells: Array = []
var _bag_level: Label
var _stat_labels: Array = []
var _tab_buttons: Array = []
## 지금 고른 탭 (BAG_TABS 의 번호)
var _bag_tab := 0
## 보이는 칸이 가방 몇 번째인지. 탭으로 거르면 둘이 어긋난다
var _bag_view: Array = []


func _ready() -> void:
	_transport = LocalTransport.new()
	add_child(_transport)
	_transport.open(GameData.start_zone())
	_transport.event.connect(_on_event)
	_build_persistent()
	# 캐시한 이전 빌드를 보고 있으면 화면이 직접 알려 준다
	Build.check_latest(self, func(latest: String) -> void:
		_last_event = "새 빌드가 있습니다 (%s) — 새로고침하세요" % latest
	)


## 판정이 낸 일. 글자 한 줄과 피격 이펙트로 보여준다
func _on_event(name: StringName, payload: Dictionary) -> void:
	match name:
		&"hit":
			_show_hit(payload)
			var who := "맞음" if payload.get("target_kind", "") == "player" else "피해"
			_last_event = "%s %d%s%s" % [
				who,
				payload.get("amount", 0),
				" 치명타!" if payload.get("crit", false) else "",
				"  처치!" if payload.get("killed", false) else "",
			]
		&"levelUp":
			_last_event = "레벨 %d 이 되었습니다" % payload.get("level", 0)
		&"swing":
			# 휘두르는 동안 발이 묶인다는 통보. 그 시간만큼 공격 동작을 튼다
			_swing_until = Time.get_ticks_msec() + int(payload.get("root_ms", 400))
		&"died":
			_last_event = "쓰러졌습니다 — 아무 데나 눌러 마을에서 되살아나기"
			_target = Vector3.INF
			_target_mob = ""
			_marker.visible = false
			_gate_panel.visible = false
		&"revived":
			_last_event = "마을에서 되살아났습니다"
		&"aoe":
			_show_aoe(payload)
		&"npc":
			_show_npc(payload)
		&"skill":
			# 스킬도 같은 공격 동작을 쓴다
			_swing_until = Time.get_ticks_msec() + int(payload.get("root_ms", 400))
			_show_skill(payload)
		&"skills":
			_last_event = "스킬을 배웠습니다"
			if _skill_panel.visible:
				_redraw_skills()
		&"loot":
			var got := str(payload.get("item", {}).get("id", ""))
			if got == "":
				_last_event = "골드 %d" % payload.get("gold", 0)
			else:
				_last_event = "골드 %d, %s" % [
					payload.get("gold", 0), Items.get_item(got).get("name", got)
				]
		&"inventory":
			if _bag_panel.visible:
				_redraw_bag()
			if _npc_panel.visible:
				_redraw_npc()
		&"skillBar":
			if _skill_panel.visible:
				_redraw_skills()
		&"notice":
			_last_event = str(payload.get("text", ""))
		&"gate":
			# 차원문에 섰다. 어디로 갈지는 사람이 고른다
			_open_gate()
		&"zone":
			_last_event = "%s 에 도착했습니다" % GameData.zone(str(payload.get("zone", ""))).get("name", "")


## 존이 바뀌어도 살아 있는 것들
func _build_persistent() -> void:
	# 모델이 있으면 모델, 없으면 기둥. npm run sync:godot 을 안 돌렸을 수도 있다
	var rig := Rig.create("varco_fighter", Rig.HUMAN_HEIGHT)
	if rig != null:
		_player = rig
		_player_y = 0.0
	else:
		var capsule := MeshInstance3D.new()
		var body := CapsuleMesh.new()
		body.radius = Movement.PLAYER_RADIUS
		body.height = 1.8
		capsule.mesh = body
		var body_mat := StandardMaterial3D.new()
		body_mat.albedo_color = Color("#e8d7b0")
		capsule.material_override = body_mat
		_player = capsule
		_player_y = 0.9
	add_child(_player)
	# 머리 높이를 재려면 먼저 세워야 한다 — 기둥은 원점이 몸 가운데라
	# 바닥(y=0)에 둔 채로 재면 막대가 배꼽 높이에 뜬다.
	# 매 프레임 _draw_state 가 다시 넣는 값과 같다
	_player.position.y = _player_y
	# 내 체력은 HUD 막대에도 있지만, 눈이 가 있는 곳은 발밑이다.
	# 존이 바뀌어도 나는 그대로라 여기(_zone_node 밖)에 단다
	_player_bar = HpBar3D.create(self, _player, HpBar3D.COLOR_PLAYER)

	# 어디를 눌렀는지 보여주는 표시 (웹 클라의 클릭 이동 표시와 같은 역할)
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.35
	ring.outer_radius = 0.5
	_marker.mesh = ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("#4aa8ff")
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("#4aa8ff")
	_marker.material_override = ring_mat
	_marker.visible = false
	add_child(_marker)

	_camera = CameraRig.new()
	add_child(_camera)

	var ui := CanvasLayer.new()
	add_child(ui)

	# 한글 폰트를 테마로 깐다. 고도 기본 폰트에는 한글 글리프가 없어서
	# 안 깔면 "마을" 이 네모로 나온다 (npm run sync:godot 이 복사해 둔다)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 화면 아무 데나 눌러 걸어야 하므로 UI 바탕은 터치를 먹지 않는다.
	# 단추는 제 몫을 따로 먹는다
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = _make_theme()
	ui.add_child(_ui_root)

	# 제일 먼저 넣어 HUD 글자 밑에 깔린다 — 비네트가 체력·상태를 가리면 안 된다
	_hurt = HurtFlash.new()
	_ui_root.add_child(_hurt)

	_label = Label.new()
	_label.position = Vector2(24, 24)
	_ui_root.add_child(_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(24, 150)
	_hp_bar.size = Vector2(360, 34)
	_hp_bar.show_percentage = false
	_ui_root.add_child(_hp_bar)

	_build_gate_panel()
	_build_npc_panel()
	_build_skill_bar()
	_build_skill_panel()
	_build_test_switches()
	_build_bag_panel()


## 가방과 장착 창. 웹 클라의 ui/inventory.ts 자리다.
##
## 배치는 2026-09-18 에 받은 그림대로다:
##
## ```
## ┌ LV. 1 · 경험치 ─────────────┬ [전체][무기][방어구][장신구][재료] ┐
## │ [무기]  (캐릭터)  [신발]     │ [ ][ ][ ][ ][ ]                    │
## │ [갑옷]            [목걸이]   │ [ ][ ][ ][ ][ ]                    │
## │ [투구]            [반지]     │ [ ][ ][ ][ ][ ]  ← 끌어 올림        │
## │ ┌ 공격력 방어력 체력 ──────┐ │ 고른 것 이름·옵션                  │
## │ │ 치명타 치피  공속       │ │            [끼기/벗기] [닫기]      │
## └─────────────────────────────┴────────────────────────────────────┘
## ```
##
## **왼쪽이 장착, 오른쪽이 가방이다.** 장착 6칸은 캐릭터를 사이에 두고 세 칸씩
## 세로로 세운다. 스탯은 캐릭터 아래 상자에 여섯 개를 두 줄로 놓는다.
##
## **창은 `CenterContainer` 에 얹어 늘 화면 한가운데에 둔다.** `set_anchors_preset`
## 만 부르면 오프셋이 0 이라 왼쪽 위 구석에 박힌다 (2026-09-18 에 그랬다). 지을 때
## 한 번만 맞추는 것도 안 된다 — 든 것에 따라 창 크기가 변해 그만큼 밀린다.
##
## **틀은 한 번만 짓고 내용만 다시 채운다.** 매번 지웠다 만들면 눌러 둔 칸이
## 풀리고 스크롤이 맨 위로 튄다.
##
## 판·칸·탭·단추 그림은 전부 바르코로 만든 것이다 (assets/icons/ui_*).
## **없으면 코드로 그린 판과 테두리로 나온다** — npm run sync:godot 을 안 돌린
## 사람도 창은 돌아가야 한다 (모델이 없으면 기둥으로 그리는 것과 같은 규칙)
func _build_bag_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(center)

	_bag_panel = PanelContainer.new()
	_bag_panel.visible = false
	_bag_panel.add_theme_stylebox_override("panel", _frame_box("ui_panel", 48, 16))
	center.add_child(_bag_panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	_bag_panel.add_child(pad)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	pad.add_child(columns)

	_build_gear_side(columns)
	_build_bag_side(columns)


## 왼쪽 — 이름표 · 장착 6칸 · 캐릭터 · 스탯 상자
func _build_gear_side(parent: Node) -> void:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	parent.add_child(side)

	# 이름표
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _frame_box("ui_subpanel", 24, 8))
	side.add_child(plate)
	var plate_pad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		plate_pad.add_theme_constant_override("margin_" + s, 10)
	plate.add_child(plate_pad)
	_bag_level = Label.new()
	_bag_level.add_theme_font_size_override("font_size", 26)
	plate_pad.add_child(_bag_level)

	# 장착 — 캐릭터를 사이에 두고 세 칸씩. 칸 순서는 데이터가 정한다 (items.json 의 slots)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_child(body)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 10)
	body.add_child(left_col)

	# 가운데 캐릭터. 그림이 없으면 빈 자리로 남는다 (창이 무너지지 않게 크기만 잡아 둔다)
	var figure := TextureRect.new()
	figure.custom_minimum_size = Vector2(196, CELL * 3 + 20)
	figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	figure.texture = _icon("ui_figure")
	body.add_child(figure)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 10)
	body.add_child(right_col)

	_gear_cells.clear()
	var count := Items.slots().size()
	for index in count:
		var cell := _make_cell(_pick_bag.bind("equip", index))
		(left_col if index < ceili(count / 2.0) else right_col).add_child(cell)
		_gear_cells.append(cell)

	# 스탯 상자 — 여섯 개를 두 줄로
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _frame_box("ui_subpanel", 24, 8))
	side.add_child(box)
	var box_pad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		box_pad.add_theme_constant_override("margin_" + s, 12)
	box.add_child(box_pad)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	box_pad.add_child(grid)
	_stat_labels.clear()
	for name in STAT_NAMES:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 21)
		label.custom_minimum_size = Vector2(150, 0)
		grid.add_child(label)
		_stat_labels.append(label)


## 오른쪽 — 탭 · 가방 격자 · 상세 · 단추
func _build_bag_side(parent: Node) -> void:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	parent.add_child(side)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	side.add_child(tabs)
	_tab_buttons.clear()
	for index in BAG_TABS.size():
		var tab := Button.new()
		tab.text = BAG_TABS[index]
		tab.custom_minimum_size = Vector2(0, 56)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_pick_tab.bind(index))
		tabs.add_child(tab)
		_tab_buttons.append(tab)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(CELL * BAG_COLUMNS, CELL * BAG_ROWS)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = BAG_COLUMNS
	scroll.add_child(_bag_grid)

	# 머리 줄이 아니라 격자 아래에 둔다 — 그림처럼 "몇 칸 썼나" 가 단추 옆에 붙는다
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	side.add_child(foot)
	_add_icon(foot, "bag", 34)
	_bag_head = Label.new()
	_bag_head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_bag_head)
	_add_icon(foot, "gold", 34)
	_bag_gold = Label.new()
	_bag_gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bag_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_bag_gold)

	_bag_detail = Label.new()
	_bag_detail.custom_minimum_size = Vector2(CELL * BAG_COLUMNS, 64)
	_bag_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bag_detail.add_theme_font_size_override("font_size", 21)
	side.add_child(_bag_detail)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	side.add_child(buttons)
	_bag_action = _make_button("-", _on_bag_action)
	buttons.add_child(_bag_action)
	var close := _make_button("닫기", func() -> void: _bag_panel.visible = false)
	buttons.add_child(close)


func _make_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 60)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _frame_box("ui_button", 28, 6))
	button.pressed.connect(on_press)
	return button


## 테두리·판. 바르코로 만든 그림을 9조각으로 늘여 쓴다.
## **그림이 없으면 코드로 그린 판**을 준다 — 아무것도 없이 뜨는 일은 없어야 한다
## `margin` 은 9조각으로 자를 자리(텍스처 픽셀), `content` 는 안쪽 내용이 물러앉는
## 여백이다. **둘을 따로 준다** — 안 주면 고도가 9조각 여백을 안쪽 여백으로도 써서,
## 칸마다 26px 씩 물러앉아 창이 1320x758 로 부풀었다 (2026-09-18)
func _frame_box(name: String, margin: int, content: int) -> StyleBox:
	var texture := _icon(name)
	if texture != null:
		var box := StyleBoxTexture.new()
		box.texture = texture
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			box.set_texture_margin(side, margin)
		box.set_content_margin_all(content)
		return box
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.05, 0.06, 0.08, 0.94)
	flat.border_color = Color(0.72, 0.82, 0.95)
	flat.set_border_width_all(3)
	flat.set_corner_radius_all(8)
	flat.set_content_margin_all(content)
	return flat


## 아이콘 한 장. **없으면 null** — 부르는 쪽이 글자나 코드로 그린 판으로 대신한다.
##
## **있는지는 `.import` 가 있는지로 본다.** ★ 두 번 틀린 자리다 (2026-09-18):
##
## | 방법 | PC(에셋 있음) | PC(sync 안 함) | 웹 익스포트 |
## |---|---|---|---|
## | `ResourceLoader.exists` | 있다 | 없다 | **없다고 한다** — 폰에서 전부 글자로 나왔다 |
## | 안 거르고 `load` | 있다 | **오류 쏟아짐** | 있다 |
## | `.png` 또는 `.png.import` | 있다 | 없다 | 있다 |
##
## 익스포트에서 PNG 는 `.ctex` 로 구워져 들어가고 원본 `.png` 는 빠지는데
## **`.png.import` 는 팩에 그대로 들어간다.** `load` 는 리맵을 따라가므로,
## 임포트 파일이 있으면 불러도 된다. 바닥(`.ktx2`)은 임포트를 안 거쳐 원본이
## 그대로 있어서 예전 방식이 거기서는 통했다.
##
## 한 번 해 본 결과는 이름마다 기억한다 — 칸마다 다시 찾지 않도록
func _icon(name: String) -> Texture2D:
	if name == "":
		return null
	if _icon_cache.has(name):
		return _icon_cache[name]
	var path := ICON_DIR + name + ".png"
	var texture: Texture2D = null
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".import"):
		texture = load(path) as Texture2D
	_icon_cache[name] = texture
	return texture


## 줄에 아이콘을 끼운다. 그림이 없으면 아무것도 넣지 않는다 (글자만 남는다)
func _add_icon(parent: Node, name: String, size: int) -> void:
	var texture := _icon(name)
	if texture == null:
		return
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(rect)


## 창의 한 칸 — 판 위에 그림 · 글자 · 배지 · 누르는 자리를 겹쳐 둔다.
## PanelContainer 는 자식을 모두 칸 전체에 깔기 때문에 정렬만으로 자리를 나눈다
func _make_cell(on_press: Callable) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(CELL, CELL)
	cell.add_theme_stylebox_override("panel", _frame_box("ui_slot", 26, 6))

	var icon := TextureRect.new()
	icon.name = "icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)

	# 그림이 없는 것(재료)은 이름을 줄여 적는다
	var text := Label.new()
	text.name = "text"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 18)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(text)

	var badge := Label.new()
	badge.name = "badge"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.add_theme_font_size_override("font_size", 18)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(badge)

	var hit := Button.new()
	hit.name = "hit"
	hit.flat = true
	hit.pressed.connect(on_press)
	cell.add_child(hit)
	return cell


## 칸 하나를 채운다. `icon_name` 이 없거나 그림이 없으면 글자로 나온다
func _fill_cell(cell: PanelContainer, stack: Dictionary, empty_text: String, icon_name: String) -> void:
	var icon: TextureRect = cell.get_node("icon")
	var text: Label = cell.get_node("text")
	var badge: Label = cell.get_node("badge")
	var texture := _icon(icon_name)
	icon.texture = texture

	if stack.is_empty():
		# 빈 칸 — 그림을 죽여 둔다. 그림이 없으면 칸 이름을 적는다
		icon.modulate = Color(1, 1, 1, 0.22)
		text.text = "" if texture != null else empty_text
		badge.text = ""
		return

	icon.modulate = Color(1, 1, 1, 1)
	var item := Items.get_item(str(stack.get("id", "")))
	text.text = "" if texture != null else str(item.get("name", stack.get("id", "?")))
	badge.text = _stack_badge(stack)


## 칸 오른쪽 아래 배지 — 강화 +N · 개수 · 등급. 이름은 상세 칸이 맡는다
func _stack_badge(stack: Dictionary) -> String:
	var parts: Array = []
	var enhance := int(stack.get("enhance", 0))
	if enhance > 0:
		parts.append("+%d" % enhance)
	var count := int(stack.get("count", 1))
	if count > 1:
		parts.append("x%d" % count)
	parts.append("%d" % int(stack.get("grade", 1)))
	return " ".join(parts)


## 격자의 칸 수를 맞춘다. **칸 수가 바뀔 때만 손댄다** — 매번 다시 지으면
## 눌러 둔 칸이 풀린다. 칸은 뒤에만 붙으므로 bind 해 둔 index 는 그대로 맞다
func _fit_cells(grid: GridContainer, want: int, where: String) -> void:
	while grid.get_child_count() > want:
		var last := grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(last)
		last.queue_free()
	while grid.get_child_count() < want:
		grid.add_child(_make_cell(_pick_bag.bind(where, grid.get_child_count())))


## 탭 — 무엇을 보여줄지 거른다. **거르면 칸 번호와 가방 번호가 어긋나므로**
## 보이는 칸이 가방 몇 번째인지를 `_bag_view` 에 적어 둔다
func _pick_tab(index: int) -> void:
	_bag_tab = index
	_bag_pick = {}
	_redraw_bag()


func _tab_keeps(stack: Dictionary) -> bool:
	if _bag_tab == 0:
		return true
	var item := Items.get_item(str(stack.get("id", "")))
	if bool(item.get("material", false)):
		return _bag_tab == 4
	var slot := str(item.get("slot", ""))
	match _bag_tab:
		1: return slot == "weapon"
		2: return slot in ["armor", "helmet", "boots"]
		3: return slot in ["necklace", "ring"]
	return false


func _pick_bag(where: String, index: int) -> void:
	_bag_pick = {"where": where, "index": index}
	_show_bag_detail()


func _toggle_bag() -> void:
	_bag_panel.visible = not _bag_panel.visible
	if _bag_panel.visible:
		_redraw_bag()


func _redraw_bag() -> void:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty():
		return
	var job := str(me.get("job", ""))
	var bag: Array = me.get("bag", [])
	var equipped: Dictionary = me.get("equipped", {})

	_bag_level.text = "LV. %d" % int(me.get("level", 1))
	_bag_head.text = "%d/%d" % [bag.size(), Items.bag_size()]
	_bag_gold.text = "%d" % int(me.get("gold", 0))

	# 탭 — 고른 것만 밝게
	for index in _tab_buttons.size():
		var tab: Button = _tab_buttons[index]
		var box := "ui_tab_on" if index == _bag_tab else "ui_tab_off"
		for state in ["normal", "hover", "pressed"]:
			tab.add_theme_stylebox_override(state, _frame_box(box, 24, 6))

	# 장착 — 아이콘 이름은 슬롯 이름과 같다 (assets/icons/weapon.png …)
	var slots: Array = Items.slots()
	for index in _gear_cells.size():
		var slot := str(slots[index])
		_fill_cell(_gear_cells[index], equipped.get(slot, {}), Items.slot_label(slot, job), slot)

	# 스탯 여섯 — 상태바에 안 나오는 것까지 한자리에 모은다
	var stats: Dictionary = me.get("stats", {})
	var shown := [
		"공격력 %d" % int(stats.get("attack", 0)),
		"방어력 %d" % int(stats.get("defense", 0)),
		"체력 %d" % int(stats.get("maxHp", 0)),
		"치명타 %.0f%%" % (float(stats.get("crit", 0.0)) * 100.0),
		"치명타 피해 %.0f%%" % (float(stats.get("critDamage", 0.0)) * 100.0),
		"공격 속도 +%.0f%%" % (float(stats.get("attackSpeed", 0.0)) * 100.0),
	]
	for index in _stat_labels.size():
		_stat_labels[index].text = str(shown[index])

	# 가방 — 탭으로 거른 것만. 보이는 칸이 가방 몇 번째인지 적어 둔다
	_bag_view.clear()
	for index in bag.size():
		if _tab_keeps(bag[index]):
			_bag_view.append(index)
	_fit_cells(_bag_grid, maxi(BAG_COLUMNS * BAG_ROWS, _bag_view.size()), "bag")
	for index in _bag_grid.get_child_count():
		var stack: Dictionary = bag[_bag_view[index]] if index < _bag_view.size() else {}
		var icon_name := ""
		if not stack.is_empty():
			# 재료는 슬롯이 없어 그림도 없다 — 이름으로 나온다
			icon_name = str(Items.get_item(str(stack.get("id", ""))).get("slot", ""))
		_fill_cell(_bag_grid.get_child(index), stack, "", icon_name)

	_show_bag_detail()


## 상세 칸 — 고른 것의 이름·강화·등급·옵션을 푼다. 고른 칸은 밝게 둔다
func _show_bag_detail() -> void:
	for index in _gear_cells.size():
		_gear_cells[index].modulate = _cell_tint("equip", index)
	for index in _bag_grid.get_child_count():
		_bag_grid.get_child(index).modulate = _cell_tint("bag", index)

	var stack := _picked_stack()
	if stack.is_empty():
		_bag_detail.text = "칸을 고르면 여기에 나옵니다"
		_bag_action.text = "-"
		_bag_action.disabled = true
		return
	_bag_detail.text = _stack_label(stack)
	_bag_action.text = "벗기" if str(_bag_pick.get("where", "")) == "equip" else "끼기"
	_bag_action.disabled = false


func _cell_tint(where: String, index: int) -> Color:
	if str(_bag_pick.get("where", "")) == where and int(_bag_pick.get("index", -1)) == index:
		return Color(1.35, 1.35, 1.1)
	return Color(1, 1, 1)


## 고른 칸이 가방 몇 번째인가. **탭으로 걸러 놔서 칸 번호와 다르다**
func _picked_bag_index() -> int:
	var index := int(_bag_pick.get("index", -1))
	if index < 0 or index >= _bag_view.size():
		return -1
	return int(_bag_view[index])


func _picked_stack() -> Dictionary:
	if _bag_pick.is_empty():
		return {}
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty():
		return {}
	if str(_bag_pick.get("where", "")) == "equip":
		var slots: Array = Items.slots()
		var index := int(_bag_pick.get("index", -1))
		if index < 0 or index >= slots.size():
			return {}
		return me.get("equipped", {}).get(str(slots[index]), {})
	var at := _picked_bag_index()
	var bag: Array = me.get("bag", [])
	if at < 0 or at >= bag.size():
		return {}
	return bag[at]


func _on_bag_action() -> void:
	var stack := _picked_stack()
	if stack.is_empty():
		return
	if str(_bag_pick.get("where", "")) == "equip":
		_transport.send(&"unequip", {"slot": str(Items.slots()[int(_bag_pick.index)])})
	else:
		# 탭으로 걸러 놔서 칸 번호가 아니라 가방 번호를 보낸다
		_transport.send(&"equip", {"index": _picked_bag_index()})
	_bag_pick = {}
	_redraw_bag()


## "낡은 장검 +3 (5등급) 공격 +7, 치명타 +2%"
func _stack_label(stack: Dictionary) -> String:
	var item := Items.get_item(str(stack.get("id", "")))
	var text := str(item.get("name", stack.get("id", "?")))
	var enhance := int(stack.get("enhance", 0))
	if enhance > 0:
		text += " +%d" % enhance
	text += " (%d등급)" % int(stack.get("grade", 1))
	var options: Array = []
	for option in stack.get("options", []):
		options.append(Items.describe_option(option))
	if not options.is_empty():
		text += "\n" + ", ".join(options)
	return text


## HUD 하단. **가운데에 퀵슬롯 4칸**, 오른쪽 아래에 자동사냥·스킬·가방 단추.
##
## 퀵슬롯은 스킬 아이콘을 칸 테두리(ui_skill_slot)에 넣고, 쿨타임이 남았으면
## 시계 방향으로 걷히는 어둠과 남은 초를 얹는다. 빈 칸은 "+" — 누르면 스킬창이 열린다.
##
## **앵커로 자리를 잡는다** (UI 는 조각을 앵커로 조립한다). 자식을 다 넣은 뒤에
## 최소 크기로 오프셋을 맞추고, 양쪽으로 자라게 해서 해상도가 바뀌어도 가운데에 남는다
func _build_skill_bar() -> void:
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 12)
	_ui_root.add_child(dock)
	_bar_buttons.clear()
	for slot in int(GameData.combat().get("skillBarSize", 4)):
		var cell := _make_skill_cell(QUICK_CELL, "ui_skill_slot", _on_bar_pressed.bind(slot))
		cell.find_child("key", true, false).text = str(slot + 1)
		dock.add_child(cell)
		_bar_buttons.append(cell)
		_bar_cooling.append(false)
	dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20)
	dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var menu := HBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	_ui_root.add_child(menu)

	_auto_button = Button.new()
	_auto_button.custom_minimum_size = Vector2(120, 70)
	_auto_button.text = "자동사냥"
	_auto_button.pressed.connect(_toggle_auto)
	menu.add_child(_auto_button)

	var open := Button.new()
	open.text = "스킬"
	open.custom_minimum_size = Vector2(100, 70)
	open.pressed.connect(_toggle_skills)
	menu.add_child(open)

	var bag := Button.new()
	bag.text = "가방"
	bag.custom_minimum_size = Vector2(100, 70)
	bag.pressed.connect(_toggle_bag)
	menu.add_child(bag)
	menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu.grow_vertical = Control.GROW_DIRECTION_BEGIN


## 스킬 칸 하나 — 퀵슬롯·창 안 장착 칸·목록 칸·설명 쪽 큰 아이콘이 전부 이것이다.
##
## ```
## PanelContainer (frame, 안쪽 여백 0)
##  ├ MarginContainer (SKILL_INSET) ─ icon / text / cool / secs
##  ├ badge  (오른쪽 아래 — Lv.N 또는 N번)
##  ├ pick   (고른 칸 테두리 ui_slot_pick, 칸 전체를 덮는다)
##  └ hit    (flat Button — 누름만 받는다)
## ```
##
## 테두리 안쪽 여백을 0 으로 두고 아이콘만 `MarginContainer` 로 물린다 — 고른 칸
## 테두리가 칸 테두리 위에 정확히 겹쳐야 해서다
func _make_skill_cell(size: int, frame: String, on_press: Callable) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(size, size)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.add_theme_stylebox_override("panel", _frame_box(frame, 26, 0))

	var inset := MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, SKILL_INSET)
	cell.add_child(inset)

	var icon := TextureRect.new()
	icon.name = "icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(icon)

	# 아이콘이 없는 스킬(마법사·궁수)은 이름을 적는다
	var text := Label.new()
	text.name = "text"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 18 if size < 140 else 26)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(text)

	# 쿨타임 — 남은 만큼 어둡다. 12시에서 **시계 방향으로 밝은 쪽이 넓어진다**
	# (어둠을 반시계로 채워야 경계가 시계 방향으로 돈다)
	var cool := TextureProgressBar.new()
	cool.name = "cool"
	cool.fill_mode = TextureProgressBar.FILL_COUNTER_CLOCKWISE
	cool.texture_progress = _white(size - SKILL_INSET * 2)
	cool.tint_progress = Color(0, 0, 0, 0.68)
	cool.max_value = 1.0
	cool.step = 0.0
	cool.visible = false
	cool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(cool)

	# 어둠과 밝은 쪽의 경계에서 도는 빛 바늘
	var edge := CoolEdge.new()
	edge.name = "edge"
	edge.visible = false
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(edge)

	var secs := Label.new()
	secs.name = "secs"
	secs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	secs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	secs.add_theme_font_size_override("font_size", 28)
	secs.add_theme_constant_override("outline_size", 6)
	secs.add_theme_color_override("font_outline_color", Color.BLACK)
	secs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(secs)

	# 다 쓰고 돌아왔을 때 번쩍 — 쿨타임이 끝난 것을 눈으로 알린다 (_flash_ready)
	var flash := ColorRect.new()
	flash.name = "flash"
	flash.color = Color(1.0, 0.95, 0.8, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(flash)

	# 가운데 아래 — 목록 칸의 "Lv.N 습득"
	var badge := Label.new()
	badge.name = "badge"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_constant_override("outline_size", 5)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 왼쪽 위 — 퀵슬롯 단축키 번호
	var key := Label.new()
	key.name = "key"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	key.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	key.add_theme_font_size_override("font_size", 20)
	key.add_theme_constant_override("outline_size", 6)
	key.add_theme_color_override("font_outline_color", Color.BLACK)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_pad := MarginContainer.new()
	badge_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_pad.add_theme_constant_override("margin_left", SKILL_INSET + 2)
	badge_pad.add_theme_constant_override("margin_right", 4)
	badge_pad.add_theme_constant_override("margin_top", SKILL_INSET)
	badge_pad.add_theme_constant_override("margin_bottom", SKILL_INSET - 3)
	var badge_layer := Control.new()
	badge_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_pad.add_child(badge_layer)
	badge.set_anchors_preset(Control.PRESET_FULL_RECT)
	key.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_layer.add_child(badge)
	badge_layer.add_child(key)
	cell.add_child(badge_pad)

	var pick := Panel.new()
	pick.name = "pick"
	pick.visible = false
	pick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pick.add_theme_stylebox_override("panel", _pick_box())
	cell.add_child(pick)

	var hit := Button.new()
	hit.name = "hit"
	hit.flat = true
	if on_press.is_valid():
		hit.pressed.connect(on_press)
	else:
		hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(hit)
	return cell


## 고른 칸 테두리. 그림이 없으면 코드로 그린 금색 테 (안쪽은 비운다 — 아이콘이 보여야 한다)
func _pick_box() -> StyleBox:
	var texture := _icon("ui_slot_pick")
	if texture != null:
		var box := StyleBoxTexture.new()
		box.texture = texture
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			box.set_texture_margin(side, 26)
		return box
	var flat := StyleBoxFlat.new()
	flat.draw_center = false
	flat.border_color = Color(1.0, 0.72, 0.25)
	flat.set_border_width_all(4)
	flat.set_corner_radius_all(6)
	return flat


## 쿨타임 경계의 빛 바늘. 가운데에서 칸 끝까지 긋고, 끝에 작은 불씨를 단다.
## `ratio` 는 남은 몫(1 → 0) — 어둠이 12시에서 반시계로 그만큼 덮고 있으므로
## 바늘은 12시에서 반시계로 ratio 바퀴 돈 자리다. 줄어들수록 시계 방향으로 12시에 다가간다
class CoolEdge extends Control:
	var ratio := 0.0

	func _draw() -> void:
		var half := size / 2.0
		var angle := -PI / 2.0 - ratio * TAU
		var dir := Vector2(cos(angle), sin(angle))
		# 네모 칸 끝까지 닿는 길이
		var reach := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var tip := half + dir * reach
		draw_line(half, tip, Color(0.55, 0.85, 1.0, 0.28), 7.0, true)
		draw_line(half, tip, Color(0.9, 0.97, 1.0, 0.95), 2.0, true)
		draw_circle(tip, 4.0, Color(1.0, 1.0, 1.0, 0.9))


## 쿨타임 어둠에 쓰는 흰 판. 둥근 채우기는 늘이면 안 그려지므로 칸 크기 그대로 만든다
func _white(size: int) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


## 칸에 스킬 하나를 채운다. `id` 가 비면 `empty_text` 를 적는다
func _fill_skill_cell(cell: PanelContainer, id: String, empty_text: String) -> void:
	var icon: TextureRect = cell.find_child("icon", true, false)
	var text: Label = cell.find_child("text", true, false)
	var texture := _icon("skill_" + id) if id != "" else null
	icon.texture = texture
	if id == "":
		text.text = empty_text
	elif texture == null:
		text.text = str(Skills.all().get(id, {}).get("name", id))
	else:
		text.text = ""


## 스킬창. 2026-09-19 에 받은 그림(가방 상세 화면)의 배치를 **좌우로 뒤집은** 것이다:
##
## ```
## ┌──────────────────────┬ 스킬 ─────────────────── [닫기] ┐
## │      [큰 아이콘]      │ 장착 중  [1][2][3][4]              │
## │        낙뢰           │ 스킬 목록                          │
## │ ┌ 요구 레벨·재사용 ┐ │ [ ][ ][ ][ ]                        │
## │ └ 배움·장착 상태  ┘ │ [ ]            ← 끌어 올림           │
## │ ┌ 설명 ────────────┐ │                                     │
## │ └──────────────────┘ │                     [해제] [장착]   │
## └──────────────────────┴─────────────────────────────────────┘
## ```
##
## **왼쪽이 설명, 오른쪽이 고르기·장착/해제다** (요청). 장착은 빈 칸이 있으면
## 맨 뒤에 붙고, 4칸이 다 찼으면 **바꿀 칸을 누르게 한다** — 옛 창은 말없이 맨 앞
## 칸을 밀어냈는데, 무엇이 빠지는지 모르는 채로 빠졌다.
##
## 배우기는 따로 없다. 장착할 때 아직 안 배웠으면 배우기 요청을 먼저 보낸다
## (둘 다 World 가 다시 본다 — 레벨이 모자라면 배우기가 거절되고 장착도 걸러진다).
## 틀은 한 번 짓고 `_redraw_skills` 가 내용만 채운다
func _build_skill_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(center)

	_skill_panel = PanelContainer.new()
	_skill_panel.visible = false
	_skill_panel.add_theme_stylebox_override("panel", _frame_box("ui_panel", 48, 16))
	center.add_child(_skill_panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	_skill_panel.add_child(pad)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	pad.add_child(columns)

	# 왼쪽 — 설명
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)

	_skill_big = _make_skill_cell(150, "ui_slot", Callable())
	left.add_child(_skill_big)

	_skill_name = Label.new()
	_skill_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skill_name.add_theme_font_size_override("font_size", 30)
	left.add_child(_skill_name)

	_skill_info = Label.new()
	_skill_info.add_theme_font_size_override("font_size", 20)
	_skill_state = Label.new()
	_skill_state.add_theme_font_size_override("font_size", 20)
	_skill_state.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	var info := _sub_box(left, false)
	info.add_child(_skill_info)
	info.add_child(_skill_state)

	_skill_desc = Label.new()
	_skill_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_desc.add_theme_font_size_override("font_size", 20)
	_skill_desc.custom_minimum_size = Vector2(340, 0)
	_sub_box(left, true).add_child(_skill_desc)

	# 오른쪽 — 고르기와 장착/해제
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)

	var head := HBoxContainer.new()
	right.add_child(head)
	var title := Label.new()
	title.text = "스킬"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_make_button("닫기", _toggle_skills))

	right.add_child(_caption("장착 중"))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", SKILL_GAP)
	right.add_child(slots)
	_slot_cells.clear()
	for slot in int(GameData.combat().get("skillBarSize", 4)):
		var cell := _make_skill_cell(SKILL_CELL, "ui_skill_slot", _pick_slot.bind(slot))
		slots.add_child(cell)
		_slot_cells.append(cell)

	right.add_child(_caption("스킬 목록"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(
		SKILL_CELL * SKILL_COLUMNS + SKILL_GAP * (SKILL_COLUMNS - 1), SKILL_CELL * 2 + SKILL_GAP
	)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	_skill_grid = GridContainer.new()
	_skill_grid.columns = SKILL_COLUMNS
	_skill_grid.add_theme_constant_override("h_separation", SKILL_GAP)
	_skill_grid.add_theme_constant_override("v_separation", SKILL_GAP)
	scroll.add_child(_skill_grid)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	right.add_child(buttons)
	_skill_unequip = _make_button("해제", _on_skill_unequip)
	buttons.add_child(_skill_unequip)
	_skill_equip = _make_button("장착", _on_skill_equip)
	buttons.add_child(_skill_equip)


## 테스트 스위치 단추 — 오른쪽 위. 누르면 World 에 요청하고, 글자는 표의 지금 값을 따른다
## (`_refresh_switches`). 스위치를 없애면 이 단추들도 걷는다 → skills.md "테스트 스위치"
func _build_test_switches() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_ui_root.add_child(column)
	_switch_buttons.clear()
	for name in Skills.SWITCHES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(230, 52)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_on_switch_pressed.bind(name))
		column.add_child(button)
		_switch_buttons[name] = button
	_refresh_switches()
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _on_switch_pressed(name: String) -> void:
	var on := Skills.cooldown_off() if name == "cooldownOff" else Skills.unlock_all()
	_transport.send(&"testSwitch", {"name": name, "on": not on})
	_refresh_switches()
	if _skill_panel.visible:
		_redraw_skills()


func _refresh_switches() -> void:
	for name in _switch_buttons:
		var on := Skills.cooldown_off() if name == "cooldownOff" else Skills.unlock_all()
		var label := "테스트: 쿨타임 0" if name == "cooldownOff" else "테스트: 레벨 잠금 해제"
		_switch_buttons[name].text = "%s  %s" % [label, "켬" if on else "끔"]


## 테두리 상자 안에 세로 줄을 하나 만들어 돌려준다.
##
## **`ui_subpanel` 을 쓰지 않는다.** ★ 그 그림은 가운데에 얇은 판이 있고 둘레가 넓은
## 빛번짐이라, 9조각으로 늘이면 판은 글자보다 작게, 빛번짐만 상자 크기로 그려진다 —
## 능력·설명 글자가 상자 밖으로 삐져나와 보였다 (2026-09-19). 테가 그림 가장자리에
## 붙어 있는 `ui_slot` 은 어떤 크기로 늘여도 테가 상자 끝에 온다
func _sub_box(parent: Node, fill: bool) -> VBoxContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _frame_box("ui_slot", 26, 10))
	if fill:
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var box_pad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		box_pad.add_theme_constant_override("margin_" + s, 12)
	box.add_child(box_pad)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	box_pad.add_child(rows)
	return rows


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92))
	return label


func _toggle_skills() -> void:
	_skill_panel.visible = not _skill_panel.visible
	_skill_swap = false
	if _skill_panel.visible:
		_redraw_skills()


func _me() -> Dictionary:
	return _transport.snapshot().get("players", {}).get(_transport.my_id(), {})


## 스킬창 내용을 지금 상태로 채운다. 목록은 직업이 바뀌었을 때만 다시 짓는다
func _redraw_skills() -> void:
	var me := _me()
	var job := str(me.get("job", "fighter"))
	var ids: Array = []
	for id in Skills.for_job(job):
		ids.append(str(id))
	if ids != _skill_ids:
		_skill_ids = ids
		for child in _skill_grid.get_children():
			child.queue_free()
		_skill_cells.clear()
		for index in ids.size():
			var cell := _make_skill_cell(SKILL_CELL, "ui_slot", _pick_skill.bind(index))
			_skill_grid.add_child(cell)
			_skill_cells.append(cell)
	if not (_skill_pick in _skill_ids):
		_skill_pick = str(_skill_ids[0]) if not _skill_ids.is_empty() else ""

	var bar: Array = me.get("skill_bar", [])
	var learned: Array = me.get("skills", [])
	var level := int(me.get("level", 1))

	for index in _skill_cells.size():
		var id := str(_skill_ids[index])
		var cell: PanelContainer = _skill_cells[index]
		var skill: Dictionary = Skills.all().get(id, {})
		_fill_skill_cell(cell, id, "")
		# 안 배운 것만 "Lv.N 습득". 배웠으면 지운다. 장착 번호는 적지 않는다 — 번호는 퀵슬롯에 있다
		var badge: Label = cell.find_child("badge", true, false)
		badge.text = "" if id in learned else "Lv.%d 습득" % int(skill.get("reqLevel", 1))
		# 아직 배울 수 없는 것은 흐리게
		var open: bool = id in learned or Skills.can_learn(skill, job, level)
		cell.modulate = Color.WHITE if open else Color(0.5, 0.5, 0.5)
		cell.get_node("pick").visible = id == _skill_pick

	for slot in _slot_cells.size():
		var cell: PanelContainer = _slot_cells[slot]
		var id := str(bar[slot]) if slot < bar.size() else ""
		_fill_skill_cell(cell, id, "+")
		cell.get_node("pick").visible = _skill_swap or (id != "" and id == _skill_pick)

	var skill: Dictionary = Skills.all().get(_skill_pick, {})
	_fill_skill_cell(_skill_big, _skill_pick, "")
	_skill_name.text = str(skill.get("name", ""))
	var targets := int(skill.get("maxTargets", 1))
	_skill_info.text = "요구 레벨 %d\n재사용 %s초\n사거리 %s, %s" % [
		int(skill.get("reqLevel", 1)),
		str(snappedf(float(skill.get("cooldown", 0)) / 1000.0, 0.1)),
		str(skill.get("range", 0)),
		"주위 %d명" % targets if float(skill.get("arc", 0)) >= TAU - 0.01 else "대상 %d명" % targets,
	]
	_skill_desc.text = str(skill.get("description", ""))

	var equipped := _skill_pick in bar
	if _skill_swap:
		_skill_state.text = "바꿀 칸을 누르세요"
	elif equipped:
		_skill_state.text = "장착 중 (%d번 칸)" % (bar.find(_skill_pick) + 1)
	elif _skill_pick in learned:
		_skill_state.text = "배움"
	elif Skills.can_learn(skill, job, level):
		_skill_state.text = "장착하면 배웁니다"
	else:
		_skill_state.text = "%d레벨에 배웁니다" % int(skill.get("reqLevel", 1))

	_skill_equip.text = "취소" if _skill_swap else "장착"
	_skill_equip.disabled = _skill_pick == "" or (equipped and not _skill_swap)
	_skill_unequip.disabled = not equipped or _skill_swap


func _pick_skill(index: int) -> void:
	_skill_pick = str(_skill_ids[index])
	_skill_swap = false
	_redraw_skills()


## 창 안의 장착 칸을 눌렀다. 바꿀 칸을 고르는 중이면 거기에 끼우고,
## 아니면 그 칸의 스킬을 고른다
func _pick_slot(slot: int) -> void:
	var bar: Array = _me().get("skill_bar", []).duplicate()
	if _skill_swap:
		_skill_swap = false
		if slot < bar.size():
			bar[slot] = _skill_pick
		else:
			bar.append(_skill_pick)
		_send_bar(bar)
	elif slot < bar.size():
		_skill_pick = str(bar[slot])
	_redraw_skills()


## 장착. 빈 칸이 있으면 맨 뒤에 붙고, 다 찼으면 바꿀 칸을 고르게 한다
func _on_skill_equip() -> void:
	if _skill_swap:
		_skill_swap = false
		_redraw_skills()
		return
	var bar: Array = _me().get("skill_bar", []).duplicate()
	if _skill_pick == "" or _skill_pick in bar:
		return
	if bar.size() < int(GameData.combat().get("skillBarSize", 4)):
		bar.append(_skill_pick)
		_send_bar(bar)
	else:
		_skill_swap = true
	_redraw_skills()


func _on_skill_unequip() -> void:
	var bar: Array = _me().get("skill_bar", []).duplicate()
	bar.erase(_skill_pick)
	_send_bar(bar)
	_redraw_skills()


## 액션바를 보낸다. **안 배운 것이 들어 있으면 배우기부터 요청한다** —
## World 는 배운 것만 올려 주므로 순서가 바뀌면 그 칸이 걸러진다
func _send_bar(bar: Array) -> void:
	var learned: Array = _me().get("skills", [])
	for id in bar:
		if not (id in learned):
			_transport.send(&"learnSkill", {"skill": str(id)})
	_transport.send(&"setSkillBar", {"bar": bar})


## 자동 사냥을 켜고 끈다. **켜고 끄는 것도 요청일 뿐이다** — 실제 상태는
## World 가 정하고, 버튼 글자는 다음 프레임에 스냅샷을 보고 따라온다.
##
## 켜는 순간 화면이 몰던 것(눌러 둔 자리·쫓던 놈)을 놓는다. 켜자마자 옛 목적지로
## 걸어가면 어디를 중심으로 도는지 알 수 없다. **켠 뒤에 다시 조작하는 것은
## 막지 않는다** — 그때는 사람이 이기고, 손을 떼면 그 자리에서 이어서 사냥한다
func _toggle_auto() -> void:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	var on := not bool(me.get("auto", false))
	if on:
		_target_mob = ""
		_target = Vector3.INF
	_transport.send(&"autoHunt", {"on": on})


func _on_bar_pressed(slot: int) -> void:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	var bar: Array = me.get("skill_bar", [])
	if slot >= bar.size():
		if not _skill_panel.visible:
			_toggle_skills()
		return
	_transport.send(&"skill", {"skill": str(bar[slot])})


## NPC 와 말하는 창. 웹 클라의 ui/npcDialog.ts 자리다
func _build_npc_panel() -> void:
	_npc_panel = PanelContainer.new()
	_npc_panel.set_anchors_preset(Control.PRESET_CENTER)
	_npc_panel.visible = false
	_ui_root.add_child(_npc_panel)

	var rows := VBoxContainer.new()
	_npc_panel.add_child(rows)

	_npc_title = Label.new()
	rows.add_child(_npc_title)

	_npc_rows = VBoxContainer.new()
	rows.add_child(_npc_rows)


func _show_npc(payload: Dictionary) -> void:
	var role := str(payload.get("role", ""))
	var title := str(payload.get("title", ""))
	_npc_title.text = "%s%s" % [
		payload.get("name", ""),
		"  (%s)" % title if title != "" else "",
	]
	_npc_role = role
	_npc_items = payload.get("items", [])
	_npc_tab = "buy" if role == "shop" else "forge"
	_redraw_npc()
	_npc_panel.visible = true


## 목록은 **열 때마다 다시 그린다** — 사고팔고 두드리는 동안 계속 바뀐다.
## 웹 클라의 npcDialog(상점) · craftWindow(대장간 탭 3개) 자리다
func _redraw_npc() -> void:
	for child in _npc_rows.get_children():
		child.queue_free()

	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty():
		return

	var gold := Label.new()
	gold.text = "골드 %d   가방 %d/%d" % [me.get("gold", 0), me.bag.size(), Items.bag_size()]
	_npc_rows.add_child(gold)

	var tabs := HBoxContainer.new()
	_npc_rows.add_child(tabs)
	var names := {"buy": "사기", "sell": "팔기"} if _npc_role == "shop" else {
		"forge": "새로 만들기", "enhance": "강화", "craft": "등급 올리기"
	}
	for key in names:
		var tab := Button.new()
		tab.text = names[key]
		tab.disabled = (_npc_tab == key)
		tab.pressed.connect(func() -> void:
			_npc_tab = str(key)
			_redraw_npc()
		)
		tabs.add_child(tab)

	match _npc_tab:
		"buy":
			_list_buy(me)
		"sell":
			_list_bag(me, "팔기", func(index: int) -> void:
				_transport.send(&"npcSell", {"index": index})
			)
		"forge":
			_list_forge(me)
		"enhance":
			_list_bag(me, "강화", func(index: int) -> void:
				_transport.send(&"npcEnhance", {"index": index})
			)
		"craft":
			_list_bag(me, "등급", func(index: int) -> void:
				_transport.send(&"npcCraft", {"index": index})
			)

	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(func() -> void: _npc_panel.visible = false)
	_npc_rows.add_child(close)


func _list_buy(me: Dictionary) -> void:
	for id in _npc_items:
		var item := Items.get_item(str(id))
		var button := Button.new()
		button.text = "%s   %d G" % [item.get("name", id), item.get("price", 0)]
		button.disabled = int(me.get("gold", 0)) < int(item.get("price", 0))
		button.pressed.connect(func() -> void:
			_transport.send(&"npcBuy", {"item": str(id)})
			_redraw_npc()
		)
		_npc_rows.add_child(button)


## 만들 수 있는 것이 레벨을 따라 길어진다. **가진 재료로 만들 수 있는 것만** 올린다 —
## 안 거르면 200레벨에 160줄이 깔려 정작 무엇을 만들 수 있는지가 안 보인다
func _list_forge(me: Dictionary) -> void:
	var shown := 0
	for id in _npc_items:
		if shown >= 12:
			break
		var item := Items.get_item(str(id))
		var recipe := Items.forge_recipe(item)
		if recipe.is_empty():
			continue
		var have := 0
		for stack in me.bag:
			if str(stack.get("id", "")) == str(recipe.materialId):
				have += 1
		if have < int(recipe.materialCount):
			continue
		shown += 1
		var button := Button.new()
		button.text = "%s   %s %d개 + %d G" % [
			item.get("name", id), recipe.materialName, recipe.materialCount, recipe.gold
		]
		button.pressed.connect(func() -> void:
			_transport.send(&"npcForge", {"item": str(id)})
			_redraw_npc()
		)
		_npc_rows.add_child(button)
	if shown == 0:
		var empty := Label.new()
		empty.text = "만들 수 있는 것이 없습니다 (보스가 재료를 떨굽니다)"
		_npc_rows.add_child(empty)


func _list_bag(me: Dictionary, verb: String, action: Callable) -> void:
	if me.bag.is_empty():
		var empty := Label.new()
		empty.text = "가방이 비었습니다"
		_npc_rows.add_child(empty)
		return
	for index in mini(me.bag.size(), 12):
		var stack: Dictionary = me.bag[index]
		var button := Button.new()
		button.text = "%s  [%s]" % [_stack_label(stack), verb]
		button.pressed.connect(func() -> void:
			action.call(index)
			_redraw_npc()
		)
		_npc_rows.add_child(button)



func _make_theme() -> Theme:
	var theme := Theme.new()
	var path := "res://assets/fonts/NotoSansKR-subset.ttf"
	if ResourceLoader.exists(path):
		theme.default_font = load(path)
	theme.default_font_size = 28
	return theme


## 차원문 창. 조각을 조립하는 건 GatePanel 이 하고, 여기서는 달고 고른 곳을 보내기만 한다
func _build_gate_panel() -> void:
	_gate_panel = GatePanel.create()
	_gate_panel.picked.connect(_on_gate_pick)
	_ui_root.add_child(_gate_panel)


func _open_gate() -> void:
	_gate_panel.open(_shown_zone)


## 문을 눌렀다. **거리와 상관없이 바로 창을 연다** (2026-09-18 요청: "포탈까지
## 안 걸어가도 클릭하면 UI 열리게"). 예전에는 문 밖에서 누르면 문 가운데로
## 걸어갔고, 들어서야 `gate` 이벤트가 창을 열었다 — 멀리서 한 번 누르고 기다려야
## 했다. 걸어가는 길은 그대로 남아 있다: 문 안으로 들어서면 `gate` 이벤트가 연다.
## **이동하는 건 여전히 travel 요청이고 World 가 다시 본다**
func _on_gate_tapped() -> void:
	_target = Vector3.INF
	_target_mob = ""
	_marker.visible = false
	_open_gate()


func _on_gate_pick(zone_id: String) -> void:
	_gate_panel.visible = false
	_target = Vector3.INF
	_target_mob = ""
	_marker.visible = false
	_transport.send(&"travel", {"zone": zone_id})


## 존 분위기 — 하늘색과 환경광. **안개는 켜지 않는다** (2026-09-18 요청:
## "안개를 넣으라고 한 적이 없는데 왜 넣은거야? 그냥 안개를 없애버려").
##
## 안개는 옛 웹 클라이언트에 있던 것이 고도 이관 때 따라온 것이고, 옮기면서
## 선형(70~190m)이 near 없는 지수 안개로 바뀌어 카메라 앞 27m 바닥에도 15%
## 섞이고 있었다. 안개는 곱이 아니라 **더하기**라 돌 틈 같은 어두운 데를 그대로
## 들어올린다 — 바닥 무늬가 씻기고 화면이 안개색으로 떴다. 존 데이터의
## `fogColor`·`fogNear`·`fogFar` 도 같은 날 걷어냈다.
static func environment_for(env: Dictionary) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(env.get("skyColor", "#b9c9d8"))
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(env.get("skyColor", "#b9c9d8"))
	e.ambient_light_energy = float(env.get("hemiIntensity", 1.1))
	e.fog_enabled = false
	return e


## 존 하나를 짓는다. 차원문으로 옮기면 통째로 버리고 다시 짓는다
func _build_zone(zone_id: String) -> void:
	if _zone_node != null:
		_zone_node.queue_free()
	_aoe_marks.clear()
	_zone_node = Node3D.new()
	add_child(_zone_node)
	_shown_zone = zone_id

	var zone := GameData.zone(zone_id)
	var env: Dictionary = zone.get("env", {})
	var size := float(zone.get("size", 92))
	_half_size = Movement.zone_half_size(size)
	_target = Vector3.INF
	_marker.visible = false
	# 몬스터 id 는 존마다 다시 매겨진다. 고리는 _zone_node 와 같이 사라지므로
	# 여기서 고른 것도 같이 놓는다
	_selected_mob = ""
	_ring = null
	_target_mob = ""
	# 막대는 _zone_node 밑이라 같이 사라진다. 몬스터 id 는 존마다 다시 매겨지므로
	# 때린 기록도 같이 버린다 — 안 버리면 새 존의 같은 id 에 막대가 붙는다
	_mob_bars.clear()
	_mob_bar_until.clear()

	var world_env := WorldEnvironment.new()
	world_env.environment = environment_for(env)
	_zone_node.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = float(env.get("sunIntensity", 2.7))
	sun.rotation_degrees = Vector3(-50, -35, 0)
	_zone_node.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	ground.mesh = plane
	ground.material_override = Ground.material_for(env, size)
	_zone_node.add_child(ground)


	# 차원문. 여기 들어가면 존이 바뀐다 (World._check_gate)
	var gate: Dictionary = zone.get("gate", {})
	if not gate.is_empty():
		_zone_node.add_child(Portal.create(gate))

	# NPC. 모델이 없는 look 뿐이라 기둥에 이름표를 얹는다
	for npc in _transport.snapshot().get("npcs", []):
		var post := MeshInstance3D.new()
		var shape := CapsuleMesh.new()
		shape.radius = 0.35
		shape.height = 1.7
		post.mesh = shape
		var npc_mat := StandardMaterial3D.new()
		npc_mat.albedo_color = Color("#d8c48a") if npc.has("role") else Color("#b9b3a6")
		post.material_override = npc_mat
		post.position = Vector3(npc.x, shape.height * 0.5, npc.z)
		_zone_node.add_child(post)

		var plate := Label3D.new()
		plate.text = "%s\n%s" % [npc.get("name", ""), npc.get("title", "")]
		plate.font = _ui_root.theme.default_font
		plate.font_size = 64
		plate.pixel_size = 0.004
		plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		plate.no_depth_test = true
		plate.position = Vector3(npc.x, 2.3, npc.z)
		_zone_node.add_child(plate)

	# 몬스터. 자리는 World 가 정했고 여기서는 그리기만 한다.
	# 모델이 있는 look 만 모델이고 나머지는 기둥이다 (웹 클라도 같은 규칙)
	_mob_nodes.clear()
	for monster in _transport.snapshot().get("monsters", []):
		var kind := GameData.monster_kind(monster.kind)
		var look := str(kind.get("look", ""))
		var height := GameData.beast_height(look, float(monster.scale))
		var node: Node3D = Rig.create(look, height)
		var foot := 0.0
		if node == null:
			var body := MeshInstance3D.new()
			var shape := CapsuleMesh.new()
			shape.radius = monster.r
			shape.height = maxf(monster.r * 2.0 + 0.1, height)
			body.mesh = shape
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(monster.color)
			if monster.boss:
				mat.emission_enabled = true
				mat.emission = Color(monster.color) * 0.6
			body.material_override = mat
			node = body
			foot = shape.height * 0.5
		node.position = Vector3(monster.x, foot, monster.z)
		_zone_node.add_child(node)
		_mob_nodes[monster.id] = node


func _unhandled_input(event: InputEvent) -> void:
	# 퀵슬롯 단축키 1~4. 칸 왼쪽 위에 적힌 번호와 같다
	if event is InputEventKey and event.pressed and not event.echo:
		var slot: int = event.keycode - KEY_1
		if slot >= 0 and slot < _bar_buttons.size():
			_on_bar_pressed(slot)
			get_viewport().set_input_as_handled()
			return
	# 터치는 기본 설정이 마우스로 바꿔 주므로 이 한 줄이 폰도 덮는다
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 죽어 있으면 어딜 눌러도 부활 요청이다
		if _am_dead():
			_transport.send(&"revive", {})
			return
		var hit := _ground_point(event.position)
		if hit == Vector3.INF:
			return
		# 차원문을 눌렀다. 아치는 높이가 있어 바닥 점이 아니라 화면에서 쏜 선으로 본다
		if _gate_tapped(event.position):
			_on_gate_tapped()
			return
		# NPC 를 눌렀으면 말을 건다. **닿는지는 World 가 다시 본다**
		var npc := _npc_at(hit)
		if npc != "":
			_transport.send(&"npc", {"name": npc})
			return
		# 몬스터를 눌렀으면 그놈을 잡으러 간다. 아니면 그 자리로 걸어간다
		var mob := _mob_at(hit)
		if mob != "":
			_select_mob(mob)
			_target_mob = mob
			_target = Vector3.INF
			_marker.visible = false
		else:
			# 땅을 누르면 걸어가기만 한다. **골라 둔 놈은 그대로 둔다** —
			# 원거리 직업이 자리를 옮겨 가며 같은 놈을 보는 게 자연스럽다
			# (docs/features/auto-hunt-and-targeting.md 의 "클릭 타겟팅")
			_target_mob = ""
			_target = hit
			_marker.position = hit + Vector3(0, 0.05, 0)
			_marker.visible = true


## 화면의 그 점이 차원문 아치에 닿나
func _gate_tapped(screen: Vector2) -> bool:
	if _camera == null:
		return false
	return Portal.hit(
		_camera.project_ray_origin(screen), _camera.project_ray_normal(screen),
		_transport.snapshot().get("gate", {})
	)


## 바닥의 그 자리에 NPC 가 있나
func _npc_at(point: Vector3) -> String:
	for npc in _transport.snapshot().get("npcs", []):
		if Vector2(point.x - float(npc.x), point.z - float(npc.z)).length() < 1.2:
			return str(npc.get("name", ""))
	return ""


## 바닥의 그 자리에 산 몬스터가 있나. 손가락은 굵으니 반지름에 여유를 준다
func _mob_at(point: Vector3) -> String:
	var best := ""
	var best_gap := INF
	for monster in _transport.snapshot().get("monsters", []):
		if int(monster.hp) <= 0:
			continue
		var gap: float = Vector2(point.x - monster.x, point.z - monster.z).length() - monster.r
		if gap < 0.8 and gap < best_gap:
			best_gap = gap
			best = monster.id
	return best


## 이놈을 골라 둔다. 발밑에 고리를 세우고, 자리는 _tick_ring 이 매 프레임 따라간다.
##
## **판정에는 안 보낸다** — 누구를 맞출지는 World 가 정면 부채꼴에서 다시 고른다
## (docs/features/godot-migration.md 의 "대상은 서버가 고른다")
func _select_mob(id: String) -> void:
	if id == _selected_mob and _ring != null and is_instance_valid(_ring):
		return
	_clear_selection()
	_selected_mob = id
	if _zone_node != null:
		_ring = SelectRing.create(_zone_node)


## 골라 둔 것을 놓는다 (죽었다·내가 죽었다·존을 옮겼다)
func _clear_selection() -> void:
	_selected_mob = ""
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null


## 골라 둔 놈 발밑으로 고리를 옮긴다. 놓을 자리는 여기 한 군데다 —
## 몬스터가 죽는 길이 여럿이라 각자 지우게 두면 반드시 한 곳이 빠진다
func _tick_ring(snap: Dictionary) -> void:
	if _selected_mob == "":
		return
	var me: Dictionary = snap.get("players", {}).get(_transport.my_id(), {})
	var mob := _find_mob(snap, _selected_mob)
	if bool(me.get("dead", false)) or mob.is_empty() or int(mob.hp) <= 0:
		_clear_selection()
		return
	if _ring == null or not is_instance_valid(_ring):
		return
	_ring.follow(Vector3(mob.x, 0.0, mob.z), float(mob.r), _last_delta)


## 몬스터 머리 위 체력 막대. **골라 둔 놈과 방금 때린 놈만** 보여 준다
## (2026-09-18 지시: "몬스터는 나한테 피격을 받은 경우거나 타겟팅 된 경우에만").
##
## 세우고 치우는 자리는 여기 한 군데다 — 고리와 같은 이유로, 죽는 길이 여럿이라
## 각자 지우게 두면 반드시 한 곳이 빠지고 **막대가 시체에 남는다.**
## 몬스터마다 매 프레임 한 번 불린다 (`_draw_state` 의 몬스터 고리 안).
func _tick_mob_bar(monster: Dictionary, node: Node3D) -> void:
	var id := str(monster.id)
	var hit_until := int(_mob_bar_until.get(id, 0))
	var show := int(monster.hp) > 0 and (id == _selected_mob or hit_until > Time.get_ticks_msec())

	var bar: HpBar3D = _mob_bars.get(id)
	if not show:
		if bar != null and is_instance_valid(bar):
			bar.queue_free()
		_mob_bars.erase(id)
		# 죽었거나 시간이 지났으면 때린 기록도 버린다. 살아나면 처음부터다
		_mob_bar_until.erase(id)
		return

	if bar == null or not is_instance_valid(bar):
		bar = HpBar3D.create(_zone_node, node, HpBar3D.COLOR_MOB)
		_mob_bars[id] = bar
	bar.follow(
		Vector3(monster.x, 0.0, monster.z),
		float(monster.hp) / maxf(1.0, float(monster.max_hp))
	)


## 화면의 한 점이 바닥의 어디인지
func _ground_point(screen: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.INF
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	return hit if hit != null else Vector3.INF


func _process(delta: float) -> void:
	_moving = false
	_last_delta = delta
	_send_input(delta)
	_draw_state()
	_tick_aoe()


## 눌러 둔 자리로 향하는 방향을 만들어 보낸다. **요청일 뿐이고 판정은 World 가 한다.**
func _am_dead() -> bool:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	return bool(me.get("dead", false))


func _send_input(delta: float) -> void:
	if _zone_node == null or _am_dead():
		return
	if _target_mob != "":
		_chase_and_hit(delta)
		return
	if _target == Vector3.INF:
		return
	var me := _my_position()
	var to := Vector2(_target.x - me.x, _target.z - me.z)
	if to.length() <= STOP_DISTANCE:
		_target = Vector3.INF
		_marker.visible = false
		return
	_move(to.normalized(), delta)


## 눌러 둔 몬스터에게 걸어가서 사거리에 들면 계속 친다.
## 때릴 수 있는지는 **World 가 다시 본다** — 여기서 보내는 건 요청일 뿐이다
func _chase_and_hit(delta: float) -> void:
	var snap := _transport.snapshot()
	var me: Dictionary = snap.get("players", {}).get(_transport.my_id(), {})
	var mob := _find_mob(snap, _target_mob)
	if me.is_empty() or mob.is_empty() or int(mob.hp) <= 0:
		_target_mob = ""
		return

	var to := Vector2(mob.x - me.x, mob.z - me.z)
	var dir := to.normalized()
	var reach: float = float(me.stats.attackRange)
	if to.length() > reach:
		_move(dir, delta)
		return
	# 사거리 안이다. 제자리에서 그쪽을 보고(dt 0) 친다
	_move(dir, 0.0)
	_transport.send(&"attack", {})


func _move(dir: Vector2, delta: float) -> void:
	_seq += 1
	_moving = delta > 0.0
	_transport.send(&"input", {"seq": _seq, "dx": dir.x, "dz": dir.y, "dt": delta})


## 죽음 > 공격 > 달리기 > 대기 순으로 고른다.
##
## 격투가 공격 클립은 3.23초짜리라 통째로 틀면 한 번 차는 데 3초가 걸린다.
## 앞 0.8초는 자세를 잡는 준비라, 공격 간격(700ms)마다 처음으로 되감으면 발이
## 한 번도 안 나간다. 웹 클라이언트는 0.8~1.60초 구간만 1.6배로 트는데
## (`modelRig` 의 ATTACK_CLIPS), 여기서는 **시작과 배속만 같고 끝을 안 자른다.**
## 2.30초에 뒤돌려차기가 한 번 더 있어서, 한 대에 발이 두 번 나가 보이면 그 자리다.
func _play_player_clip(me: Dictionary) -> void:
	if not _player is Rig:
		return
	var rig: Rig = _player
	if bool(me.get("dead", false)):
		rig.play("Death")
		return
	if Time.get_ticks_msec() < _swing_until:
		rig.play("Attack", 1.6, 0.8)
		return
	rig.play("Run" if _moving else "Idle")


func _find_mob(snap: Dictionary, id: String) -> Dictionary:
	for monster in snap.get("monsters", []):
		if monster.id == id:
			return monster
	return {}


func _my_position() -> Vector3:
	var players: Dictionary = _transport.snapshot().get("players", {})
	var me: Dictionary = players.get(_transport.my_id(), {})
	if me.is_empty():
		return Vector3.ZERO
	return Vector3(me.x, 0, me.z)


func _draw_state() -> void:
	var snap := _transport.snapshot()
	# 차원문으로 옮겼으면 존을 통째로 다시 짓는다
	var zone_now := str(snap.get("zone", ""))
	var zone_changed := zone_now != "" and zone_now != _shown_zone
	if zone_changed:
		_build_zone(zone_now)

	var players: Dictionary = snap.get("players", {})
	var me: Dictionary = players.get(_transport.my_id(), {})
	if me.is_empty():
		return

	# **판정이 옮긴 것도 걷는 것이다.** 자동 사냥은 내가 입력을 안 보내므로
	# `_moving`(=_move 가 켠다)만 보면 대기 자세로 미끄러진다. 실제로 움직인
	# 거리에서 되돌린다 — 웹 클라이언트가 서버 주도 이동에서 쓰던 방법과 같다
	# (docs/features/auto-hunt-and-targeting.md 의 "클라이언트가 하는 일" 3번)
	var walked_to := Vector3(me.x, _player_y, me.z)
	if not _moving and not zone_changed and _last_delta > 0.0:
		var step := Vector2(
			walked_to.x - _player.position.x, walked_to.z - _player.position.z
		).length()
		_moving = step / _last_delta > RUN_SPEED_EPS

	_player.position = walked_to
	_player.rotation.y = me.rot
	_play_player_clip(me)

	# 뒤 위에서 내려다본다. 지금은 고정 각도다
	# 존을 옮긴 프레임에는 보간 없이 곧바로 자리잡는다
	_camera.follow(_player.position, _last_delta, zone_changed)

	# 쫓아오는 놈들이 실제로 움직인다. 자리는 World 가 정하고 여기서는 따라 그린다
	for monster in snap.get("monsters", []):
		var node: Node3D = _mob_nodes.get(monster.id)
		if node == null:
			continue
		node.visible = int(monster.hp) > 0
		_tick_mob_bar(monster, node)
		if not node.visible:
			continue
		node.position.x = monster.x
		node.position.z = monster.z
		node.rotation.y = monster.get("rot", 0.0)
		if node is Rig:
			var state := str(monster.get("state", "idle"))
			if state == "chase":
				node.play("Run")
			elif state == "patrol":
				# 순찰은 걷는 것이다. 걷기 클립이 없으니 달리기를 반 배속으로 돌린다
				node.play("Run", 0.5)
			elif state == "attack":
				node.play("Attack")
			else:
				node.play("Idle")

	_tick_ring(snap)

	var alive := 0
	for monster in snap.get("monsters", []):
		if int(monster.hp) > 0:
			alive += 1
	_player.visible = not bool(me.get("dead", false))
	# 죽으면 몸과 같이 감춘다 — 시체 위에 빈 막대가 떠 있으면 안 죽은 것처럼 보인다
	_player_bar.visible = _player.visible
	if _player_bar.visible:
		_player_bar.follow(
			Vector3(me.x, 0.0, me.z), float(me.hp) / maxf(1.0, float(me.stats.maxHp))
		)

	_hp_bar.max_value = me.stats.maxHp
	_hp_bar.value = me.hp
	_refresh_bar(me)
	_refresh_auto(me)

	_label.text = "%s   %d레벨   체력 %d/%d   경험치 %d/%d\n골드 %d   몬스터 %d/%d   %d fps   빌드 %s\n%s" % [
		GameData.zone(zone_now).get("name", zone_now),
		me.level,
		me.hp,
		me.stats.maxHp,
		me.exp,
		Combat.exp_to_next(int(me.level)),
		me.get("gold", 0),
		alive,
		snap.get("monsters", []).size(),
		Engine.get_frames_per_second(),
		Build.stamp(),
		_last_event,
	]


## 맞았다. 맞은 자리에서 터뜨리고, 맞은 몸을 붉게 물들이고, 내가 맞았으면
## 화면 가장자리까지 붉힌다. **판정은 여기서 하지 않는다** — payload 를 그대로 읽는다.
func _show_hit(payload: Dictionary) -> void:
	if _zone_node == null:
		return
	var on_me := str(payload.get("target_kind", "")) == "player"
	# 내가 때린 놈은 잠깐 막대를 보여 준다. 혼자 노는 판이라 몬스터를 때리는 건
	# 나뿐이므로 때린 사람을 따로 가리지 않는다 (서버가 붙으면 source 를 본다)
	if not on_me:
		_mob_bar_until[str(payload.get("target", ""))] = Time.get_ticks_msec() + MOB_BAR_MS
	var body: Node3D = null
	if on_me:
		body = _player
	else:
		body = _mob_nodes.get(str(payload.get("target", "")), null)

	# 자리는 World 가 준 것을 쓰고, 높이만 그려 둔 몸에서 잰다
	var at := Vector3(payload.get("x", 0.0), 0.0, payload.get("z", 0.0))
	at.y = HitFx.chest_y(body, 1.0)

	var font: Font = _ui_root.theme.default_font if _ui_root.theme != null else null
	var fx := HitFx.spawn(_zone_node, at, payload, font)
	if body != null and not bool(payload.get("heal", false)):
		fx.flash_body(body)

	# 회복은 맞은 것이 아니다
	if on_me and not bool(payload.get("heal", false)):
		var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
		var max_hp := float(me.get("stats", {}).get("maxHp", 100))
		# 최대 체력의 4분의 1을 한 번에 맞으면 제일 진하다
		_hurt.hit(float(payload.get("amount", 0)) / maxf(1.0, max_hp * 0.25))


## 스킬 이펙트.
##
## **스킬마다 그림이 다르므로 id 로 고른다.** 지금 그리는 것은 할퀴기
## (`rising_kick` — 이름은 '올려차기' 에서 바뀌었지만 id 는 저장된 캐릭터 때문에
## 그대로다)와 **낙뢰**(`thunder_fall`) 둘이다. 나머지 셋은 아직 웹 클라이언트에만
## 있다 → [skills.md](../../docs/features/skills.md).
##
## **남이 쓴 것은 아직 안 그린다** — 다른 플레이어를 세우는 자리가 고도에 없다.
func _show_skill(payload: Dictionary) -> void:
	if _zone_node == null:
		return
	if str(payload.get("id", "")) != _transport.my_id():
		return
	var skill := str(payload.get("skill", ""))
	if not (skill in ["rising_kick", "thunder_fall"]):
		return
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty():
		return
	var here := Vector3(me.x, 0.0, me.z)
	if skill == "thunder_fall":
		LightningFx.bolt(_zone_node, here, float(me.rot))
	else:
		SkillFx.claw(_zone_node, here, float(me.rot))


## 보스 범위 공격 예고 원.
##
## 바깥 테두리는 **터질 자리와 크기**를 그대로 보여 주고(판정과 같은 반지름),
## 안쪽 원이 차오르며 남은 시간을 알린다. 다 차면 터진다 — 그 전에 테두리
## 밖으로 나가면 안 맞는다 (`World._burst_aoe` 가 원으로 다시 자른다).
func _show_aoe(payload: Dictionary) -> void:
	if _zone_node == null:
		return
	var radius := float(payload.get("radius", 7.0))
	var here := Vector3(payload.get("x", 0.0), 0.06, payload.get("z", 0.0))

	var mark := Node3D.new()
	mark.position = here
	_zone_node.add_child(mark)

	var edge := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.25
	ring.outer_radius = radius
	edge.mesh = ring
	edge.material_override = _aoe_material(0.85)
	mark.add_child(edge)

	var fill := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.04
	fill.mesh = disc
	fill.material_override = _aoe_material(0.3)
	mark.add_child(fill)

	var now := Time.get_ticks_msec()
	_aoe_marks.append({
		"node": mark,
		"fill": fill,
		"start": now,
		"end": now + int(payload.get("delay_ms", 1600)),
		"radius": radius,
	})


func _aoe_material(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.25, 0.2, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## 퀵슬롯을 상태에 맞춘다. 쿨타임이 남았으면 어둠을 덮고 남은 초를 적는다
func _refresh_bar(me: Dictionary) -> void:
	var bar: Array = me.get("skill_bar", [])
	var ready_at: Dictionary = me.get("skill_ready_at", {})
	var now := Time.get_ticks_msec()
	for slot in _bar_buttons.size():
		var cell: PanelContainer = _bar_buttons[slot]
		var id := str(bar[slot]) if slot < bar.size() else ""
		_fill_skill_cell(cell, id, "+")
		var cool: TextureProgressBar = cell.find_child("cool", true, false)
		var secs: Label = cell.find_child("secs", true, false)
		var left := int(ready_at.get(id, 0)) - now if id != "" else 0
		var cooling := left > 0
		cool.visible = cooling
		var edge: CoolEdge = cell.find_child("edge", true, false)
		edge.visible = cooling
		if cooling:
			var total := maxf(float(Skills.all().get(id, {}).get("cooldown", 0)), float(left))
			cool.value = left / total
			edge.ratio = cool.value
			edge.queue_redraw()
			# 1초 아래로는 소수 한 자리 — 막 돌아오는 순간이 보인다
			secs.text = "%.1f" % (left / 1000.0) if left < 1000 else str(ceili(left / 1000.0))
		else:
			secs.text = ""
		if _bar_cooling[slot] and not cooling:
			_flash_ready(cell)
		_bar_cooling[slot] = cooling


## 쿨타임이 끝났다 — 칸이 번쩍이며 살짝 튀었다 가라앉는다
func _flash_ready(cell: PanelContainer) -> void:
	var flash: ColorRect = cell.find_child("flash", true, false)
	cell.pivot_offset = cell.size / 2.0
	var tween := cell.create_tween().set_parallel()
	flash.color.a = 0.75
	tween.tween_property(flash, "color:a", 0.0, 0.35).set_ease(Tween.EASE_OUT)
	cell.scale = Vector2.ONE * 1.12
	tween.tween_property(cell, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 자동 사냥 버튼 글자와 사냥 자리 표시. **상태는 스냅샷(me.auto)만 보고 그린다** —
## 누른 것으로 지레 바꾸면 판정이 거절했을 때 화면만 켜진 채로 남는다.
##
## 사람이 몰고 있지 않을 때만 파란 고리가 **앵커**(사냥하며 서성이는 중심)를
## 가리킨다. 어디를 중심으로 도는지 안 보이면 왜 저기서 멈추는지 알 수 없다.
## 조작 중에는 같은 고리가 "눌러 둔 자리"라 건드리지 않는다 — 한 고리가 두 가지를
## 가리키면 걸어가는 도중에 표시가 발밑으로 튄다 (앵커가 따라오기 때문이다)
func _refresh_auto(me: Dictionary) -> void:
	var on := bool(me.get("auto", false))
	_auto_button.text = "자동사냥\n켜짐" if on else "자동사냥"
	_auto_button.modulate = Color("#7ce08a") if on else Color.WHITE
	if _target != Vector3.INF or _target_mob != "":
		return
	if on:
		_marker.position = Vector3(float(me.get("auto_x", 0.0)), 0.05, float(me.get("auto_z", 0.0)))
		_marker.visible = true
	else:
		_marker.visible = false


func _tick_aoe() -> void:
	var now := Time.get_ticks_msec()
	var alive: Array = []
	for mark in _aoe_marks:
		if not is_instance_valid(mark.node):
			continue
		var span: float = maxf(1.0, float(mark.end - mark.start))
		var ratio := clampf((now - mark.start) / span, 0.0, 1.0)
		mark.fill.scale = Vector3(mark.radius * ratio, 1.0, mark.radius * ratio)
		if ratio >= 1.0:
			mark.node.queue_free()
			continue
		alive.append(mark)
	_aoe_marks = alive
