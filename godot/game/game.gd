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
## 가방에서 한 번에 보이는 줄. 나머지는 끌어 올린다.
## **받은 그림대로 8줄(40칸)** 이다 (2026-09-23)
const BAG_ROWS := 8
## 칸 한 변 — **테두리까지 친 바깥 크기**다. 8줄이 720 높이 안에 들어가는 크기다.
## 88 → 74 (2026-09-20, 창이 화면을 꽉 채웠다) → 58 (2026-09-23, 8줄)
const CELL := 58
## 칸 테두리 안쪽 여백 (아이콘이 테에서 물러앉는 폭)
const BAG_CELL_PAD := 4
## 장비 창 칸과 상세 창의 큰 칸
const GEAR_CELL := 64
const DETAIL_ICON := 92
## 상세 창 폭
const DETAIL_W := 300
## 창이 화면 양 끝에서 떨어지는 폭과, 상세 창·인벤토리 사이
const WINDOW_EDGE := 16
const WINDOW_GAP := 8
## 인벤토리 오른쪽 세로 탭 한 개, 단추 한 개
const INV_TAB := Vector2(64, 58)
const INV_BUTTON := Vector2(76, 40)
## 인벤토리 결 조각(`inv_*`)의 9조각 여백 — 그림에서 테가 차지하는 두께다.
## 창 바탕은 안쪽 여백(`INV_PANEL_PAD`)을 따로 준다
## (구운 크기에서 잰 값: 창 바탕 테 9 · 모서리 장식 10, 칸·탭 3, 단추 4 — 2026-09-23)
const INV_PANEL_MARGIN := 12
const INV_PANEL_PAD := 18
const INV_SLOT_MARGIN := 4
const INV_PICK_MARGIN := 8
const INV_TAB_MARGIN := 4
const INV_BUTTON_MARGIN := 6
## 인벤토리 결의 글자색 — 받은 그림에서 뽑았다 (2026-09-23)
const INV_GOLD := Color("#ceb474")
const INV_GOLD_HI := Color("#f1dc9c")
const INV_TEXT := Color("#ddd6c4")
const INV_DIM := Color("#948c7a")
const INV_RULE := Color("#4a4234")
const INV_PICK := Color("#e8b449")
## 못 하는 것 — 착용 레벨이 모자란 장비의 "착용 Lv" 줄과 "레벨 부족" 글자
const INV_WARN := Color("#d9644f")
## 가방 격자 칸 사이
const BAG_GRID_GAP := 4
## 세로 스크롤바가 먹는 폭
const SCROLLBAR_W := 14
## 스킬 칸. 퀵슬롯은 엄지로 누르니 조금 더 크다. 아이콘은 테두리 안쪽으로 SKILL_INSET 만큼 물린다.
## **HUD 는 2026-09-20 에 한 번 줄였다** — 화면을 너무 먹었다. 창 칸(SKILL_CELL)은 그대로다
const QUICK_CELL := 52
const SKILL_CELL := 100
const SKILL_COLUMNS := 4
const SKILL_GAP := 10
## 스킬창 셋째 칸(강화) 폭
const UPGRADE_W := 280
const SKILL_INSET := 5
## 퀵슬롯 위 한 묶음 (2026-09-20 요청). 레벨 배지 한 변과 체력 막대 높이다.
## **막대 길이는 안 정한다** — 세로 상자가 가장 넓은 자식(퀵슬롯 줄)에 맞춰 준다.
## 막대는 **테두리 두께의 두 배보다 높아야 한다** — 34 에 여백 18 을 주었더니
## 위아래 조각이 겹쳐 홈이 안 보였다 (2026-09-20, 찍어서 봤다)
const LEVEL_BADGE := 50
## 막대 높이. **글자가 들어갈 만큼은 남겨야 한다** — 반으로 줄이면서 안쪽 여백
## (`BAR_PAD`)도 같이 줄였다 (2026-09-20)
const HP_BAR_H := 22
## 막대 테두리 그림에서 테가 차지하는 두께 (9조각 여백). 얇은 선이라 작게 준다
const BAR_FRAME_MARGIN := 5
## (채움은 직사각이라 여백이 필요 없다 — 홈이 `clip_children` 으로 잘라 준다)
## 막대 테두리 안쪽 여백 — 채움이 테를 덮으면 홈이 아니라 판으로 보인다
## 막대 테두리 안쪽 여백. **0 이다** — 조금이라도 주면 채움과 테 사이에 홈 바닥이
## 띠로 비쳐 "빈 공간" 으로 보인다 (2026-09-20 지적)
const BAR_PAD := 0
## 오른쪽 위 메뉴 단추 (스킬·가방). 엄지로 누르니 퀵슬롯과 비슷한 크기다.
## **테두리가 없다** — 받은 그림이 그렇다 (2026-09-20). 그래서 아이콘을 거의 꽉 채운다
const MENU_BTN := 62
const MENU_INSET := 3
## 창 닫기 X. **모든 창이 오른쪽 위에 이것 하나를 둔다** (2026-09-20 요청)
const CLOSE_BTN := 44
## 창 테두리(PANEL_MARGIN 26)보다 안쪽으로 들여야 모서리 장식에 안 걸친다
const CLOSE_PAD := 24
## 퀵슬롯 칸 테두리가 차지하는 두께. 받은 그림의 칸은 **머리카락처럼 얇은 선**이라
## 26 으로 그리면 테가 칸을 먹는다 (2026-09-20 지적). 창 칸은 26 그대로다
const QUICK_MARGIN := 6
## 창 바탕 테두리 두께. 48 로 두면 얇은 금테 그림에서는 안쪽 여백이 그만큼 커져
## **가방 한 줄이 창 밖으로 밀린다** (2026-09-20, 찍어서 봤다)
const PANEL_MARGIN := 26
## 자동사냥 고리가 한 바퀴 도는 속도(라디안/초)
const SPIN_SPEED := 1.6
## 자동사냥 칸의 아이콘만 더 물린다. 퀵슬롯과 같은 11 로 두면 고리가 아이콘 위를
## 덮어 검이 안 보였다 (2026-09-19). 고리가 얇아진 뒤로는 덜 물려도 된다 (2026-09-20)
## 자동사냥 칸은 **퀵슬롯보다 크다** — 고리가 작아서 안 보인다는 지적을 받았다
## (2026-09-20). 테가 없으니 커도 스킬 칸으로 안 보인다
const AUTO_CELL := 64
const AUTO_INSET := 13
## 퀵슬롯 줄과 자동사냥 칸 사이를 얼마나 띄우나
const AUTO_GAP := 8
## 고리를 칸 바닥에서 얼마나 띄우나 (글자 자리)
const SPIN_LIFT := 13
## 화면 맨 아래 경험치 게이지 높이. 가운데에 퍼센트를 적으므로 글자가 들어갈 만큼은 된다
const EXP_GAUGE_H := 20
## 채팅창을 화면 왼쪽·아래(경험치 띠)에서 띄우는 거리(px)
const CHAT_MARGIN := 12
const ICON_DIR := "res://assets/icons/"
## 가방 탭. 0 은 전체, 나머지는 `_tab_keeps` 가 슬롯으로 가른다
const BAG_TABS := ["전체", "무기", "방어구", "장신구"]
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
## 존 이름·골드·fps·빌드가 적히는 줄. 상태판 아래에 깔린다
var _label: Label
var _marker: MeshInstance3D

var _target: Vector3 = Vector3.INF
var _seq := 0
var _half_size := 0.0
## 존마다 다시 짓는 것들(바닥·하늘·몬스터·차원문)은 여기 아래에 둔다.
## 캐릭터·카메라·UI 는 존이 바뀌어도 그대로라 밖에 있다
var _zone_node: Node3D
## 이펙트 풀 — **존 밖에 붙는다.** 존은 차원문을 지날 때 통째로 버려지는데,
## 거기 두면 풀도 같이 지워져 다음 시전에 다시 만든다 (`fx_pool.gd`)
var _fx: FxPool
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
## 왼쪽 아래 채팅창 — 경험치·장비 획득을 적는다 (`ChatLog`)
var _chat: ChatLog
var _ui_root: Control
## 퀵슬롯 위 한 묶음 — 레벨 배지 안 숫자, 체력 막대와 그 위 숫자, 경험치 퍼센트
var _level_label: Label
## 화면 맨 아래를 가로지르는 경험치 게이지 (2026-09-20 요청)
var _exp_bar: TextureProgressBar
var _hp_bar: TextureProgressBar
var _hp_text: Label
var _exp_text: Label
## 맞았을 때 화면 가장자리가 붉어지는 비네트 (game/hurt_flash.gd)
var _hurt: HurtFlash
var _gate_panel: GatePanel
## 던전 창 — 가방 옆 단추로 연다 (docs/features/dungeons.md)
var _dungeon_panel: DungeonPanel
## 보스 범위 공격 예고. [{node, fill, start, end, radius}, ...]
var _aoe_marks: Array = []
## 스킬 범위 표시(테스트 단추). 살아 있는 SkillRange 들
var _range_marks: Array = []
## 스킬 범위를 그릴까 — **화면에만 있는 값이다.** 판정은 늘 모양을 보내고,
## 그릴지 말지만 여기서 정한다 (`_toggle_range`)
var _show_range := false
## 스킬 범위 표시 단추와, 그 위에 마지막 시전의 반경·각·맞은 수를 적는 줄
var _range_button: Button
var _range_label: Label
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
## 테스트 무적 단추. 글자는 **스냅샷(me.invincible)** 만 보고 그린다 (자동사냥과 같다)
var _invincible_button: Button
## 자동 사냥 칸. 퀵슬롯 옆에 같은 모양으로 붙는다. 켜짐 표시는 **서버가 준
## me.auto** 로만 정한다 — 눌린 것으로 지레 바꾸면 판정이 거절했을 때 화면만
## 켜진 채로 남는다
var _auto_cell: PanelContainer
## 켜져 있는 동안 칸 위에서 도는 화살표 고리
var _auto_spin: TextureRect
## 오른쪽 위 메뉴 단추 둘 (스킬·가방)
var _menu_cells: Array = []
var _skill_panel: PanelContainer
## 스킬창. 틀은 한 번 짓고 `_redraw_skills` 가 채운다
var _skill_big: PanelContainer
var _skill_name: Label
var _skill_info: Label
var _skill_state: Label
var _skill_desc: Label
## 스킬창 셋째 칸 — 강화 1번·2번 카드 (`_make_upgrade_card` 가 채우는 사전)
var _upgrade_cards: Array = []
## 경험치북을 넣을 강화 번호 (0 부터). 카드를 눌러 고른다
var _upgrade_slot := 0
## 경험치북 id → 단추
var _book_buttons: Dictionary = {}
## "기절 에 경험치 넣기"
var _upgrade_hint: Label
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

## **설계 재현 창** — 레벨·등급·강화를 강제로 맞추고, 그 조건에서 설계가 말하는
## 값(그룹 정리 시간·HP 손실·몬스터 수치)을 같이 보여 준다. 설계 문서 9장 5번
var _debug_panel: PanelContainer
var _debug_text: Label
var _debug_level := 100
var _debug_grade := 4
var _debug_enhance := 3
var _bag_head: Label
var _bag_gold: Label
var _bag_sum: Label
var _bag_grid: GridContainer
var _bag_action: Button
var _enhance_button: Button  # 상세 창 "강화" — 장비를 고르면 뜨고, 누르면 강화 팝업을 연다
## 강화 팝업 — 화면 가운데, 뒤를 어둡게 덮는다
var _enhance_layer: Control
var _enhance_panel: PanelContainer
var _enhance_name: Label
var _enhance_kind: Label
var _enhance_icon: PanelContainer
var _enhance_info: GridContainer
var _enhance_result: Label
var _enhance_go: Button
## 두드릴 것 — {where: "bag"|"equip", index: 가방 번호|슬롯 번호}. 칸 번호가 아니다
var _enhance_target: Dictionary = {}
## 크리스탈 창 — 크리스탈을 고르고 "사용" 을 누르면 상세 창 자리에 뜬다.
## 떠 있는 동안 장비 칸을 누르면 그 장비가 대상이 된다 (`_crystal_target`)
var _crystal_panel: PanelContainer
var _crystal_icon: PanelContainer
var _crystal_name: Label
var _crystal_kind: Label
var _crystal_info: GridContainer
var _crystal_hint: Label
var _crystal_have: Label
var _crystal_roll: Button
## 대상 — `{"where": "bag"|"equip", "index": 가방 번호|슬롯 번호}`. **가방은 칸 번호가
## 아니라 가방 번호다** (탭으로 거르면 둘이 어긋난다)
var _crystal_target: Dictionary = {}
## 장비 창(왼쪽 끝)과 상세 창(인벤토리 왼쪽). 인벤토리는 `_bag_panel` 이다
var _gear_panel: PanelContainer
var _detail_panel: PanelContainer
var _detail_grade: Label
var _detail_name: Label
var _detail_kind: Label
var _detail_state: Label
var _detail_icon: PanelContainer
## 상세 창 "아이템 정보" 표 — 이름 · 값 두 칸씩
var _detail_info: GridContainer
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
	# 스킬·타격 이펙트를 미리 만들어 쉬게 둔다 — 시전 때 만들지 않고 되감아 쓴다
	_fx = FxPool.new()
	_fx.name = "FxPool"
	add_child(_fx)
	_fx.fill(_ui_root.theme.default_font if _ui_root.theme != null else null)
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
		&"reward":
			_chat.add_exp(int(payload.get("exp", 0)))
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
			_dungeon_panel.visible = false
		&"revived":
			_last_event = "마을에서 되살아났습니다"
		&"aoe":
			_show_aoe(payload)
		&"skillRange":
			# 판정은 늘 보낸다. 켜 뒀을 때만 그린다
			if _show_range:
				_show_skill_range(payload)
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
				_chat.add_item(str(Items.get_item(got).get("name", got)), int(payload.item.get("grade", 1)))
			if int(payload.get("crystal", 0)) > 0:
				_chat.add_line("재료 획득", Items.stack_name({"id": Items.crystal_id()}), INV_TEXT)
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
		&"enhanceResult":
			# 강화 결과는 채팅창에 남긴다 — 부서진 것은 상세 창이 닫혀서 달리 알 길이 없다
			var enhanced := "%s +%d" % [str(payload.get("name", "")), int(payload.get("level", 0))]
			match str(payload.get("result", "")):
				"success": _chat.add_line("강화 성공", enhanced, INV_GOLD_HI)
				"destroy": _chat.add_line("강화 실패", enhanced + " 파괴", INV_WARN)
				_: _chat.add_line("강화 유지", enhanced, INV_TEXT)
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

	# 존 이름·골드·몬스터 수·fps·빌드. **체력·레벨·경험치는 여기서 지웠다** —
	# 퀵슬롯 위 묶음이 보여 준다. 빌드 표시는 남긴다 (지금 보는 것이 어느 빌드인지)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 16)
	_ui_root.add_child(_label)

	# 채팅창은 왼쪽 아래 구석, 경험치 띠 바로 위. 테스트 단추 묶음은 그 위로 올린다
	# (`_build_test_switches`) → hud.md "채팅창"
	_chat = ChatLog.new()
	_ui_root.add_child(_chat)
	_chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	_chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat.offset_left = CHAT_MARGIN
	_chat.offset_bottom = -(EXP_GAUGE_H + CHAT_MARGIN)
	_chat.offset_top = _chat.offset_bottom - ChatLog.SIZE.y
	_chat.offset_right = CHAT_MARGIN + ChatLog.SIZE.x

	_build_gate_panel()
	_build_npc_panel()
	_build_skill_bar()
	_build_skill_panel()
	_build_test_switches()
	_build_bag_panel()
	_build_debug_panel()
	_build_enhance_popup()

	# **모든 창의 닫기는 오른쪽 위 X 하나로 통일한다** (2026-09-20 요청).
	# 창이 다 지어진 뒤에 얹어야 자식 맨 뒤라 창 위에 그려진다
	_close_button(_bag_panel, _toggle_bag, 0)
	_close_button(_gear_panel, _toggle_gear, 0)
	_close_button(_detail_panel, _close_detail, 0)
	_close_button(_crystal_panel, _close_crystal, 0)
	_close_button(_enhance_panel, _close_enhance, 0)
	_close_button(_skill_panel, _toggle_skills)
	_close_button(_npc_panel, func() -> void: _npc_panel.visible = false)


## 레벨 배지와 경험치 — **퀵슬롯 위 묶음의 맨 윗 두 줄**이다 (2026-09-20 요청,
## 받은 그림대로). 배지 안에 레벨 숫자를 크게 넣고, 바로 아래에 경험치를
## 퍼센트로 적는다. 막대로 두지 않은 것도 요청이다 — 받은 그림이 그렇다
func _build_level_badge(parent: Node) -> void:
	# **배지는 9조각으로 늘이지 않는다** ★ 9조각은 가운데를 늘여 채우므로 둥근 테가
	# 사라지고 좌우 날개만 남았다 (2026-09-20, 찍어서 봤다). 그림 한 장을 비율 그대로
	# 깔고 그 위에 숫자를 얹는다 — 창 테두리(늘여 쓰는 것)와 다른 쓰임이다
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(LEVEL_BADGE, LEVEL_BADGE)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(badge)

	var ring := _icon("ui_level_badge")
	if ring != null:
		var rect := TextureRect.new()
		rect.texture = ring
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.add_child(rect)

	_level_label = Label.new()
	_level_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 13)
	_level_label.add_theme_constant_override("outline_size", 7)
	_level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_level_label)

	# 퍼센트 글자는 **화면 맨 아래 띠 가운데**로 옮겼다 (2026-09-20 요청) —
	# 여기(배지 아래)에는 아무것도 두지 않는다


## 화면 맨 아래를 가로지르는 경험치 게이지 ★ 받은 그림(2026-09-20)대로 **가는 띠**를
## 화면 바닥에 깐다. 홈(테두리)을 두르지 않는다 — 화면 끝까지 닿아야 해서다.
##
## 퍼센트 글자는 배지 아래에 그대로 둔다 (`_exp_text`) — 띠만으로는 몇 퍼센트인지
## 읽을 수 없고, 받은 그림에도 글자와 띠가 둘 다 있다
func _build_exp_gauge() -> void:
	_exp_bar = TextureProgressBar.new()
	_exp_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_exp_bar.nine_patch_stretch = true
	var gauge_fill := _icon("ui_bar_fill")
	_exp_bar.texture_progress = gauge_fill if gauge_fill != null else _white(16)
	_exp_bar.tint_progress = Color("#e8c14a")
	# 아직 안 채운 쪽 — 체력 막대 홈 바닥과 같은 톤이라야 한 벌로 보인다
	_exp_bar.texture_under = _exp_bar.texture_progress
	_exp_bar.tint_under = Color("#26241f")
	_exp_bar.step = 0.0
	_exp_bar.custom_minimum_size = Vector2(0, EXP_GAUGE_H)
	_exp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_exp_bar)
	# 앵커만 잡고 **여백을 손으로 준다** — `PRESET_MODE_MINSIZE` 로 두면 띠가 화면
	# 아래로 제 높이만큼 삐져나간다 (2026-09-20, 테스트가 잡았다)
	_exp_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_exp_bar.offset_left = 0.0
	_exp_bar.offset_right = 0.0
	_exp_bar.offset_top = -EXP_GAUGE_H
	_exp_bar.offset_bottom = 0.0

	# 퍼센트는 **띠 가운데**에 적는다 (2026-09-20 요청)
	_exp_text = Label.new()
	_exp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exp_text.add_theme_font_size_override("font_size", 12)
	_exp_text.add_theme_constant_override("outline_size", 5)
	_exp_text.add_theme_color_override("font_outline_color", Color.BLACK)
	_exp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_exp_bar.add_child(_exp_text)


## 막대 하나 — 홈(9조각) 안에 채움을 깔고, **그 위에 금테를 다시 얹고**, 숫자를 얹는다.
## `{"frame": PanelContainer, "bar": TextureProgressBar, "text": Label}`
func _make_bar(height: int, tint: Color, font: int) -> Dictionary:
	var frame := PanelContainer.new()
	# 가로 길이는 안 정한다 — 세로 상자가 퀵슬롯 줄 너비에 맞춰 늘여 준다
	frame.custom_minimum_size = Vector2(0, height)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _frame_box("ui_bar_frame", BAR_FRAME_MARGIN, BAR_PAD))
	# **홈이 마스크다** ★★ 부모가 그린 알파 안에서만 자식이 보인다. 채움은 직사각
	# 한 장이면 되고, 끝이 비스듬히 잘린 모양은 홈이 잘라 준다 (2026-09-20 지적)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	var bar := TextureProgressBar.new()
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	# 채움은 **직사각 한 장**이다 — 통째로 늘여도 될 모양이라 여백을 안 준다
	bar.nine_patch_stretch = true
	var fill := _icon("ui_bar_fill")
	bar.texture_progress = fill if fill != null else _white(16)
	bar.tint_progress = tint
	# 빈 쪽 바닥은 **홈 그림 안에 있다** — 조각을 뚫지 않고 어두운 안쪽째로 받는다
	bar.step = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(bar)

	# **금테는 채움 위에 한 번 더 얹는다** ★★ 홈이 부모라 채움이 그 위에 그려져
	# 찬 쪽의 금테를 덮었다 — 테가 빈 쪽에만 남아 막대가 반으로 갈린 것처럼 보였다
	# (2026-09-20 지적: "HP 가 차 있어도 황금 테두리는 동일하게 있어야 한다").
	# 같은 홈 그림을 `draw_center = false` 로 다시 깔면 **가운데(채움)는 그대로 두고
	# 테만** 올라온다. 조각을 새로 만들지 않아도 되고, 비스듬히 잘린 끝은 모서리
	# 조각에 들어 있어 그대로 따라온다
	var edge := _frame_box("ui_bar_frame", BAR_FRAME_MARGIN, 0)
	if edge is StyleBoxTexture:
		(edge as StyleBoxTexture).draw_center = false
	elif edge is StyleBoxFlat:
		(edge as StyleBoxFlat).draw_center = false
	var border := Panel.new()
	border.add_theme_stylebox_override("panel", edge)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(border)

	var text := Label.new()
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", font)
	text.add_theme_constant_override("outline_size", 5)
	text.add_theme_color_override("font_outline_color", Color.BLACK)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(text)

	return {"frame": frame, "bar": bar, "text": text}


## 오른쪽 위 메뉴 단추 하나 — **테두리 없이 심볼만** 얹고 누르는 자리를 덮는다
## (2026-09-20 지적: 받은 그림의 메뉴는 테가 없는 선화 아이콘이다).
## 심볼이 없으면 글자가 대신 나온다
func _icon_button(
	icon_name: String, text: String, on_press: Callable, size: int = MENU_BTN
) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(size, size)
	cell.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var inset := MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, MENU_INSET)
	cell.add_child(inset)

	var texture := _icon(icon_name)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(rect)
	else:
		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(label)

	var hit := Button.new()
	hit.name = "hit"
	hit.flat = true
	hit.tooltip_text = text
	hit.pressed.connect(on_press)
	cell.add_child(hit)
	return cell


## 고리 그림이 없을 때 대신 도는 화살표 둘. 칸 둘레를 따라 반원씩 긋고
## 끝에 삼각 머리를 단다 — 돌리는 것은 부모(`_auto_spin`)가 한다
class SpinRing extends Control:
	const ARC := PI * 0.82

	func _draw() -> void:
		var mid := size / 2.0
		var radius := minf(size.x, size.y) / 2.0 - 3.0
		# **눈에 띄어야 한다** — 2.0 으로 그었더니 안 보인다는 지적을 받았다 (2026-09-20)
		var color := Color(0.96, 0.89, 0.66, 0.97)
		for half in 2:
			var from := half * PI + 0.1
			draw_arc(mid, radius, from, from + ARC, 28, color, 5.0, true)
			var tip := from + ARC
			var head := mid + Vector2(cos(tip), sin(tip)) * radius
			var side := Vector2(-sin(tip), cos(tip))
			var back := -Vector2(cos(tip), sin(tip))
			draw_colored_polygon(
				PackedVector2Array(
					[
						head + side * 11.0,
						head + back * 9.0 + side * 1.0,
						head + back * 1.0 - side * 9.0,
					]
				),
				color
			)


## 가방과 장착 창. 웹 클라의 ui/inventory.ts 자리다.
##
## 배치는 2026-09-18 에 받은 그림대로다:
##
## ```
## ┌ LV. 1 · 경험치 ─────────────┬ [전체][무기][방어구][장신구] ┐
## │ [무기]  (캐릭터)  [신발]     │ [ ][ ][ ][ ][ ]                    │
## │ [갑옷]            [목걸이]   │ [ ][ ][ ][ ][ ]                    │
## │ [투구]            [반지]     │ [ ][ ][ ][ ][ ]  ← 끌어 올림        │
## │ ┌ 공격력 방어력 체력 ──────┐ │ 고른 것 이름·옵션                  │
## │ │ 치명타 치피  공속       │ │            [장착/해제]             │
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
## **설계 재현 창** — 설계 문서 9장 5번이 요구한 디버그 수단이다.
##
## 레벨·등급·강화를 강제로 맞춰 시뮬레이터와 같은 조건을 세우고, 그 조건에서
## 설계가 말하는 값을 나란히 찍는다. 수치로만 맞다고 믿었다가 화면이 다른 적이
## 여러 번이라, **게임 안에서 대조할 수단**이 있어야 한다.
func _build_debug_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(center)

	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	_debug_panel.add_theme_stylebox_override("panel", _frame_box("ui_panel", PANEL_MARGIN, 16))
	center.add_child(_debug_panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	_debug_panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)

	var title := Label.new()
	title.text = "설계 재현"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)

	column.add_child(_debug_row("레벨", func(step: int) -> void:
		_debug_level = clampi(_debug_level + step, 1, Stats.max_level())
		_apply_debug()
	, [-10, -1, 1, 10]))
	column.add_child(_debug_row("등급", func(step: int) -> void:
		_debug_grade = clampi(_debug_grade + step, 1, Stats.grade_count())
		_apply_debug()
	, [-1, 1]))
	column.add_child(_debug_row("강화", func(step: int) -> void:
		_debug_enhance = clampi(_debug_enhance + step, 0, Items.max_enhance())
		_apply_debug()
	, [-1, 1]))

	_debug_text = Label.new()
	_debug_text.add_theme_font_size_override("font_size", 18)
	_debug_text.custom_minimum_size = Vector2(560, 0)
	column.add_child(_debug_text)

	_close_button(_debug_panel, _toggle_debug)


## 값 한 줄 — 이름 + 증감 단추들
func _debug_row(label: String, on_step: Callable, steps: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(90, 0)
	name_label.add_theme_font_size_override("font_size", 20)
	row.add_child(name_label)
	for step in steps:
		var button := _make_button("%+d" % int(step), on_step.bind(int(step)))
		button.custom_minimum_size = Vector2(84, 52)
		row.add_child(button)
	return row


func _toggle_debug() -> void:
	_debug_panel.visible = not _debug_panel.visible
	if _debug_panel.visible:
		_apply_debug()


## 지금 값으로 캐릭터를 세우고, 설계가 말하는 값을 함께 찍는다
func _apply_debug() -> void:
	_transport.send(&"debugGear", {
		"level": _debug_level, "grade": _debug_grade, "enhance": _debug_enhance
	})
	var level := _debug_level
	var mon := Stats.monster(level)
	var ref := Stats.ref_player(level)
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	var stats: Dictionary = me.get("stats", {})

	# 설계가 말하는 것 — 한 그룹을 몇 초에 정리하고 HP 를 얼마나 잃는가
	var per_hit: float = Stats.damage(float(stats.get("attack", 1)), level, float(mon["df"]))
	var hits := int(ceil(float(mon["hp"]) / maxf(1.0, per_hit)))
	var casts := int(ceil(float(Stats.spawn_count(level)) * hits / float(Stats.aoe_targets(level))))
	var clear := casts * float(stats.get("attackCooldown", 1000)) / 1000.0
	var taken: float = (
		Stats.damage(float(mon["atk"]), level, float(stats.get("defense", 1)))
		* float(Stats.melee_attackers(level)) * clear / float(mon["interval"])
	)
	var loss := taken / maxf(1.0, float(stats.get("maxHp", 1)))

	_debug_text.text = "\n".join([
		"Lv%d · 등급%d · 강화 +%d   (사냥터 %d, 기준 등급 %.2f, 기준 강화 %d단)" % [
			level, _debug_grade, _debug_enhance,
			Stats.field_of(level), Stats.ref_grade(level), Stats.enh_ref_step(level)
		],
		"",
		"내  HP %d  공격 %d  방어 %d" % [
			int(stats.get("maxHp", 0)), int(stats.get("attack", 0)), int(stats.get("defense", 0))
		],
		"기준 HP %d  공격 %d  방어 %d" % [roundi(ref["hp"]), roundi(ref["atk"]), roundi(ref["df"])],
		"몬스터 HP %d  공격 %d  방어 %d" % [roundi(mon["hp"]), roundi(mon["atk"]), roundi(mon["df"])],
		"",
		"1마리 %d타 (설계 6타)" % hits,
		"한 그룹(%d마리) 정리 %.1f초 / HP 손실 %.0f%%  — 설계 목표 15초 / 50%%" % [
			Stats.spawn_count(level), clear, loss * 100.0
		],
	])


## 가방 창은 **창 세 개**다 (2026-09-23 요청 — 받은 그림대로).
##
## ```
## ┌ 장비 ──────┐                 ┌ 전설 ────┐┌ 인벤토리 ──── X ┐
## │ [ ] 몸 [ ] │                 │ 이름     ││ [][][][][] [전체]│
## │ [ ]    [ ] │   (게임 화면)    │ 무기 [칸]││ [][][][][] [무기]│
## │ [ ]    [ ] │                 │ 아이템 정보││ ...           ...│
## │ 스탯 상자   │                 │ 등급 ...  ││ 소지품 3/200 [정렬]│
## └────────────┘                 └──────────┘└──────────────────┘
## ```
## - **장비 창은 왼쪽 끝**, 인벤토리는 오른쪽 끝, 상세 창은 인벤토리 바로 왼쪽이다.
##   셋을 한 가로 상자에 두고 가운데에 늘어나는 빈칸을 넣어 양 끝으로 민다 —
##   앵커만으로 자리를 잡으니 해상도가 바뀌어도 양 끝에 붙는다.
## - **상세 창은 칸을 눌러야 뜬다.** 빈칸을 누르거나 X 를 누르면 닫힌다.
## - 세 창의 높이는 가로 상자가 맞춘다(가장 큰 인벤토리 높이).
func _build_bag_panel() -> void:
	var layer := MarginContainer.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_theme_constant_override("margin_left", WINDOW_EDGE)
	layer.add_theme_constant_override("margin_right", WINDOW_EDGE)
	_ui_root.add_child(layer)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", WINDOW_GAP)
	layer.add_child(row)

	_gear_panel = _window_panel()
	row.add_child(_gear_panel)
	_build_gear_window(_gear_panel)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_detail_panel = _window_panel()
	row.add_child(_detail_panel)
	_build_detail_window(_detail_panel)

	# 크리스탈 창은 상세 창과 **같은 자리**에 번갈아 뜬다
	_crystal_panel = _window_panel()
	row.add_child(_crystal_panel)
	_build_crystal_window(_crystal_panel)

	_bag_panel = _window_panel()
	row.add_child(_bag_panel)
	_build_bag_window(_bag_panel)


## 창 하나 — 바르코로 뽑은 창 바탕(`inv_panel`)을 9조각으로 깐다
func _window_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.add_theme_stylebox_override(
		"panel", _inv_box("inv_panel", INV_PANEL_MARGIN, INV_PANEL_PAD, "#161b1a", "#4a3f30")
	)
	return panel


## 창 머리 줄 — 제목 글자와, 오른쪽 위 X 가 앉을 빈자리
func _window_title(parent: Node, text: String, size: int) -> Label:
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, CLOSE_BTN)
	head.add_theme_constant_override("separation", 10)
	parent.add_child(head)
	var title := _inv_label(text, size, INV_GOLD)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var room := Control.new()
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(room)
	return title


func _inv_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## 장비 창 — 이름표 · 장착 6칸 · 캐릭터 · 스탯 상자
func _build_gear_window(panel: PanelContainer) -> void:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	panel.add_child(side)

	var title := _window_title(side, "장비", 26)
	_bag_level = _inv_label("", 20, INV_TEXT)
	_bag_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.get_parent().add_child(_bag_level)
	title.get_parent().move_child(_bag_level, 1)

	# 장착 — 캐릭터를 사이에 두고 세 칸씩. 칸 순서는 데이터가 정한다 (items.json 의 slots)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(body)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", BAG_GRID_GAP * 2)
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(left_col)

	# 가운데 캐릭터. 그림이 없으면 빈 자리로 남는다 (창이 무너지지 않게 크기만 잡아 둔다)
	var figure := TextureRect.new()
	figure.custom_minimum_size = Vector2(150, GEAR_CELL * 3 + 20)
	figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	figure.texture = _icon("ui_figure")
	body.add_child(figure)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", BAG_GRID_GAP * 2)
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(right_col)

	_gear_cells.clear()
	var count := Items.slots().size()
	for index in count:
		var cell := _make_cell(_pick_bag.bind("equip", index), GEAR_CELL)
		(left_col if index < ceili(count / 2.0) else right_col).add_child(cell)
		_gear_cells.append(cell)

	# 스탯 상자 — 여섯 개를 두 줄씩 세 단으로. 바탕은 칸과 같은 움푹한 판이다
	var box := PanelContainer.new()
	box.add_theme_stylebox_override(
		"panel", _inv_box("inv_slot", INV_SLOT_MARGIN, 12, "#111313", "#292d27")
	)
	side.add_child(box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	_stat_labels.clear()
	for name in STAT_NAMES:
		var label := _inv_label("", 17, INV_TEXT)
		label.custom_minimum_size = Vector2(150, 0)
		grid.add_child(label)
		_stat_labels.append(label)


## 상세 창 — 받은 그림의 왼쪽 창. 등급 · 이름 · 종류 · 큰 칸 · 아이템 정보 · 단추
func _build_detail_window(panel: PanelContainer) -> void:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(DETAIL_W, 0)
	side.add_theme_constant_override("separation", 8)
	panel.add_child(side)

	_detail_grade = _window_title(side, "", 19)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	side.add_child(head)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 4)
	head.add_child(lines)
	_detail_name = _inv_label("", 24, INV_GOLD)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(_detail_name)
	_detail_kind = _inv_label("", 17, INV_DIM)
	lines.add_child(_detail_kind)
	_detail_state = _inv_label("", 17, INV_GOLD)
	lines.add_child(_detail_state)
	_detail_icon = _make_cell(func() -> void: pass, DETAIL_ICON)
	_detail_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# 강화는 큰 칸 오른쪽 아래 `+9` 로만 보인다 — 정보 표의 강화 줄은 뺐다 (2026-09-23 요청)
	_detail_icon.get_node("badge").add_theme_font_size_override("font_size", 22)
	head.add_child(_detail_icon)

	# "아이템 정보" — 제목 아래에 가는 줄 한 가닥
	var section := _inv_label("아이템 정보", 20, INV_GOLD)
	side.add_child(section)
	var rule := ColorRect.new()
	rule.color = INV_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	side.add_child(rule)

	# 이름 · 값 두 줄짜리 표. 값은 오른쪽에 붙인다 (받은 그림대로)
	_detail_info = GridContainer.new()
	_detail_info.columns = 2
	_detail_info.add_theme_constant_override("h_separation", 12)
	_detail_info.add_theme_constant_override("v_separation", 6)
	side.add_child(_detail_info)

	var room := Control.new()
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(room)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	side.add_child(buttons)
	_enhance_button = _inv_button("강화", _open_enhance)
	_enhance_button.visible = false
	buttons.add_child(_enhance_button)
	_bag_action = _inv_button("-", _on_bag_action)
	buttons.add_child(_bag_action)


## 크리스탈 창 — 상세 창과 같은 틀이다: 머리 줄 · 대상 이름과 큰 칸 · 옵션 표 · 아래 단추.
## 대상은 **장비·인벤토리 창의 칸을 눌러** 고른다 (창 안에 격자를 또 두지 않는다)
func _build_crystal_window(panel: PanelContainer) -> void:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(DETAIL_W, 0)
	side.add_theme_constant_override("separation", 8)
	panel.add_child(side)

	_window_title(side, "크리스탈 강화", 22)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	side.add_child(head)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 4)
	head.add_child(lines)
	_crystal_name = _inv_label("", 22, INV_GOLD)
	_crystal_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(_crystal_name)
	_crystal_kind = _inv_label("", 17, INV_DIM)
	lines.add_child(_crystal_kind)
	_crystal_icon = _make_cell(func() -> void: pass, DETAIL_ICON)
	_crystal_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_crystal_icon.get_node("badge").add_theme_font_size_override("font_size", 22)
	head.add_child(_crystal_icon)

	side.add_child(_inv_label("옵션", 20, INV_GOLD))
	var rule := ColorRect.new()
	rule.color = INV_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	side.add_child(rule)

	_crystal_info = GridContainer.new()
	_crystal_info.columns = 2
	_crystal_info.add_theme_constant_override("h_separation", 12)
	_crystal_info.add_theme_constant_override("v_separation", 6)
	side.add_child(_crystal_info)

	# 무엇을 하는 창인지 한 줄 — 대상이 없을 때는 "장비 칸을 누르세요"
	_crystal_hint = _inv_label("", 16, INV_DIM)
	_crystal_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_crystal_hint)

	var room := Control.new()
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(room)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	side.add_child(foot)
	_crystal_have = _inv_label("", 18, INV_TEXT)
	_crystal_have.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crystal_have.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_crystal_have)
	_crystal_roll = _inv_button("굴리기", _on_crystal_roll)
	foot.add_child(_crystal_roll)


## 강화 팝업 (2026-09-23 요청: "강화 ui창을 따로 만들어. 강화 버튼 누르면 팝업이 나오게").
## 상세 창의 "강화" 로 연다. **화면 가운데에 뜨고 뒤를 어둡게 덮는다** — 덮은 막이 뒤 창을
## 못 누르게 막아서, 떠 있는 동안 대상이 바뀔 일이 없다. 틀·조각은 상세 창과 같다.
## 머리 줄 · 대상 이름과 큰 칸 · 강화 정보 표 · 결과 한 줄 · "강화" 단추
func _build_enhance_popup() -> void:
	_enhance_layer = Control.new()
	_enhance_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enhance_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enhance_layer.visible = false
	_ui_root.add_child(_enhance_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enhance_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enhance_layer.add_child(center)
	_enhance_panel = _window_panel()
	_enhance_panel.visible = true
	center.add_child(_enhance_panel)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(DETAIL_W, 0)
	side.add_theme_constant_override("separation", 8)
	_enhance_panel.add_child(side)

	_window_title(side, "장비 강화", 22)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	side.add_child(head)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 4)
	head.add_child(lines)
	_enhance_name = _inv_label("", 22, INV_GOLD)
	_enhance_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(_enhance_name)
	_enhance_kind = _inv_label("", 20, INV_GOLD_HI)
	lines.add_child(_enhance_kind)
	_enhance_icon = _make_cell(func() -> void: pass, DETAIL_ICON)
	_enhance_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_enhance_icon.get_node("badge").add_theme_font_size_override("font_size", 22)
	head.add_child(_enhance_icon)

	side.add_child(_inv_label("강화 정보", 20, INV_GOLD))
	var rule := ColorRect.new()
	rule.color = INV_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	side.add_child(rule)

	_enhance_info = GridContainer.new()
	_enhance_info.columns = 2
	_enhance_info.add_theme_constant_override("h_separation", 12)
	_enhance_info.add_theme_constant_override("v_separation", 6)
	side.add_child(_enhance_info)

	# 방금 두드린 결과 — 성공은 금빛, 파괴는 붉게. 새로 열면 비운다
	_enhance_result = _inv_label("", 22, INV_GOLD_HI)
	_enhance_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enhance_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enhance_result.custom_minimum_size = Vector2(0, 34)
	side.add_child(_enhance_result)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	side.add_child(foot)
	_enhance_go = _inv_button("강화", _on_enhance)
	foot.add_child(_enhance_go)


## 인벤토리 창 — 머리 줄 · 격자와 오른쪽 세로 탭 · 소지품 수와 정렬 · 동전
func _build_bag_window(panel: PanelContainer) -> void:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	panel.add_child(side)

	_window_title(side, "인벤토리", 26)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	side.add_child(body)

	# 칸은 `CELL` 이 바깥 크기다. 예전 칸은 안쪽 여백만큼 더 커져서 `CELL * 줄수` 로
	# 잡으면 마지막 줄이 잘렸다(2026-09-20). 지금은 칸 안에 최소 크기를 가진 것이
	# 없어 `CELL` 그대로다 — 여백까지 더하면 격자 아래가 한 줄 가까이 빈다 (2026-09-23)
	var cell_box := CELL
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(
		cell_box * BAG_COLUMNS + BAG_GRID_GAP * (BAG_COLUMNS - 1) + SCROLLBAR_W,
		cell_box * BAG_ROWS + BAG_GRID_GAP * (BAG_ROWS - 1)
	)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = BAG_COLUMNS
	_bag_grid.add_theme_constant_override("h_separation", BAG_GRID_GAP)
	_bag_grid.add_theme_constant_override("v_separation", BAG_GRID_GAP)
	scroll.add_child(_bag_grid)

	# 탭은 격자 오른쪽에 세로로 (받은 그림대로)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	body.add_child(tabs)
	_tab_buttons.clear()
	for index in BAG_TABS.size():
		var tab := Button.new()
		tab.text = BAG_TABS[index]
		tab.custom_minimum_size = INV_TAB
		tab.add_theme_font_size_override("font_size", 17)
		tab.pressed.connect(_pick_tab.bind(index))
		tabs.add_child(tab)
		_tab_buttons.append(tab)

	# 소지품 수 · 정렬 · 장비 창 여닫기
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	side.add_child(foot)
	_add_icon(foot, "bag", 28)
	_bag_head = _inv_label("", 18, INV_TEXT)
	_bag_head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bag_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_bag_head)
	foot.add_child(_inv_button("장비", _toggle_gear))
	foot.add_child(_inv_button("정렬", _on_bag_sort))

	var coins := HBoxContainer.new()
	coins.add_theme_constant_override("separation", 8)
	side.add_child(coins)
	_add_icon(coins, "gold", 28)
	_bag_gold = _inv_label("", 18, INV_GOLD)
	_bag_gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coins.add_child(_bag_gold)


## 인벤토리 결의 단추 (정렬·장비·장착). 그림이 없으면 코드로 그린 판
func _inv_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = INV_BUTTON
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INV_TEXT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(
			state, _inv_box("inv_button", INV_BUTTON_MARGIN, 6, "#1a1a17", "#5a4c34")
		)
	button.pressed.connect(on_press)
	return button


## `_frame_box` 와 같은데, 그림이 없을 때 **받은 그림의 색으로** 판을 그린다
## (어두운 판 + 녹슨 청동 테). 조각을 안 받은 사람도 같은 결로 보인다
func _inv_box(name: String, margin: int, content: int, bg: String, border: String) -> StyleBox:
	if _icon(name) != null:
		return _frame_box(name, margin, content)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(bg)
	flat.border_color = Color(border)
	flat.set_border_width_all(2)
	flat.set_corner_radius_all(3)
	flat.set_content_margin_all(content)
	return flat


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
func _make_cell(on_press: Callable, size: int = CELL) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(size, size)
	cell.add_theme_stylebox_override(
		"panel", _inv_box("inv_slot", INV_SLOT_MARGIN, BAG_CELL_PAD, "#111313", "#292d27")
	)

	var icon := TextureRect.new()
	icon.name = "icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)

	# 그림이 없는 것은 이름을 줄여 적는다
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
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(badge)

	# 등급 테 — 칸 안쪽에 등급 색 가는 선. 빈칸이면 감춘다
	var grade := Panel.new()
	grade.name = "grade"
	grade.visible = false
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(grade)

	# 고른 가방 칸에 "장착"/"사용" 을 얹는다 — 한 번 더 누르면 그대로 한다 (`_pick_bag`)
	var act := Label.new()
	act.name = "act"
	act.visible = false
	act.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	act.add_theme_font_size_override("font_size", 18)
	act.add_theme_color_override("font_color", INV_GOLD_HI)
	act.add_theme_color_override("font_outline_color", Color.BLACK)
	act.add_theme_constant_override("outline_size", 5)
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(0, 0, 0, 0.55)
	act.add_theme_stylebox_override("normal", shade)
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(act)

	# 고른 칸 — 받은 그림처럼 밝은 금테를 덮는다
	var pick := Panel.new()
	pick.name = "pick"
	pick.visible = false
	pick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pick.add_theme_stylebox_override("panel", _inv_pick_box())
	cell.add_child(pick)

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

	var grade: Panel = cell.get_node("grade")
	if stack.is_empty():
		# 빈 칸 — 그림을 죽여 둔다. 그림이 없으면 칸 이름을 적는다
		icon.modulate = Color(1, 1, 1, 0.22)
		text.text = "" if texture != null else empty_text
		badge.text = ""
		grade.visible = false
		return

	icon.modulate = Color(1, 1, 1, 1)
	text.text = "" if texture != null else Items.stack_name(stack)
	badge.text = _stack_badge(stack)
	# 재료(크리스탈)는 등급이 없다 — 등급 테를 두르지 않는다
	grade.visible = not Items.is_material(str(stack.get("id", "")))
	grade.add_theme_stylebox_override("panel", _grade_box(int(stack.get("grade", 1))))


## 물건 아이콘 이름. **등급별 그림(`<슬롯>_g<등급>`)이 있으면 그것**, 없으면 슬롯 그림.
## 2026-09-23 에 무기만 등급별 건틀릿 일곱 장(`weapon_g1`~`weapon_g7`)을 받았다 —
## 다른 슬롯도 같은 이름으로 넣으면 따로 고칠 것 없이 붙는다
func _item_icon(stack: Dictionary) -> String:
	# 재료는 제 id 가 그림 이름이다 (`crystal.png`). 그림이 없으면 칸에 이름을 적는다
	if Items.is_material(str(stack.get("id", ""))):
		return str(stack.id)
	var slot := str(Items.get_item(str(stack.get("id", ""))).get("slot", ""))
	var graded := "%s_g%d" % [slot, int(stack.get("grade", 1))]
	return graded if _icon(graded) != null else slot


## 칸 오른쪽 아래 배지 — 강화 +N · 개수. **등급은 칸 테 색이 말한다**
## (2026-09-23 — 받은 그림은 숫자 대신 색으로 등급을 보인다). 이름은 상세 창이 맡는다
func _stack_badge(stack: Dictionary) -> String:
	var parts: Array = []
	var enhance := int(stack.get("enhance", 0))
	if enhance > 0:
		parts.append("+%d" % enhance)
	var count := int(stack.get("count", 1))
	if count > 1:
		parts.append("x%d" % count)
	return " ".join(parts)


## 등급 색. 표의 색은 흙빛이라 어두운 창 위에서는 밝혀 쓴다 — **채팅창과 같은 식**
## (색상은 그대로, 밝기만 올림). 흰색을 섞던 때(2026-09-23 까지)는 등급끼리 옅어져
## 비슷해 보였다 → hud.md "채팅창"
func _grade_tint(grade: int) -> Color:
	return ChatLog.grade_text_color(grade)


func _grade_box(grade: int) -> StyleBox:
	var flat := StyleBoxFlat.new()
	flat.draw_center = false
	flat.border_color = _grade_tint(grade)
	flat.set_border_width_all(2)
	flat.set_corner_radius_all(2)
	return flat


## 고른 칸 금테. 그림(`inv_slot_pick`)이 없으면 코드로 그린 금선
func _inv_pick_box() -> StyleBox:
	var texture := _icon("inv_slot_pick")
	if texture != null:
		var box := StyleBoxTexture.new()
		box.texture = texture
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			box.set_texture_margin(side, INV_PICK_MARGIN)
		# 칸 테 위까지 덮는다 — 칸 안쪽 여백만큼 밖으로 늘인다
		box.set_expand_margin_all(BAG_CELL_PAD)
		return box
	var flat := StyleBoxFlat.new()
	flat.draw_center = false
	flat.border_color = INV_PICK
	flat.set_border_width_all(3)
	flat.set_corner_radius_all(3)
	flat.set_expand_margin_all(BAG_CELL_PAD)
	flat.shadow_color = Color(INV_PICK, 0.35)
	flat.shadow_size = 4
	return flat


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
	var slot := str(item.get("slot", ""))
	match _bag_tab:
		1: return slot == "weapon"
		2: return slot in ["armor", "helmet", "boots"]
		3: return slot in ["necklace", "ring"]
	return false


## 칸을 누르면 상세 창이 뜬다. **빈칸을 누르면 닫는다**.
## **고른 가방 칸을 한 번 더 누르면** 칸에 얹힌 "장착"/"사용" 을 한다 (상세 창 단추와 같다).
## 크리스탈 창이 떠 있으면 **장비 칸은 크리스탈 대상이 된다** — 재료·빈칸은 무시한다
func _pick_bag(where: String, index: int) -> void:
	if _crystal_panel.visible:
		var at := index
		if where == "bag":
			at = int(_bag_view[index]) if index >= 0 and index < _bag_view.size() else -1
		var target := {"where": where, "index": at}
		if not Items.get_item(str(_stack_at(target).get("id", ""))).is_empty():
			_crystal_target = target
			_redraw_bag()
		return
	if where == "bag" and _is_picked(where, index) and not _bag_action.disabled:
		_on_bag_action()
		return
	_bag_pick = {"where": where, "index": index}
	if _picked_stack().is_empty():
		_bag_pick = {}
	_show_bag_detail()


## 가방 단추 — 인벤토리와 장비 창을 같이 열고 닫는다. 상세 창은 칸을 눌러야 뜬다
func _toggle_bag() -> void:
	var open := not _bag_panel.visible
	_enhance_layer.visible = false
	_enhance_target = {}
	_bag_panel.visible = open
	_gear_panel.visible = open
	_bag_pick = {}
	_detail_panel.visible = false
	_crystal_panel.visible = false
	_crystal_target = {}
	if open:
		_redraw_bag()


## 장비 창만 여닫는다 (자기 X, 인벤토리의 "장비" 단추)
func _toggle_gear() -> void:
	_gear_panel.visible = not _gear_panel.visible
	if _gear_panel.visible:
		_redraw_bag()


func _close_detail() -> void:
	_bag_pick = {}
	_show_bag_detail()


## 크리스탈 창 X — 상세 창으로 돌아가지 않고 둘 다 닫는다 (칸을 다시 누르면 상세가 뜬다)
func _close_crystal() -> void:
	_crystal_panel.visible = false
	_crystal_target = {}
	_bag_pick = {}
	_show_bag_detail()


func _on_bag_sort() -> void:
	_bag_pick = {}
	_crystal_target = {}  # 정렬하면 가방 번호가 바뀐다
	_transport.send(&"sortBag", {})
	_redraw_bag()


func _redraw_bag() -> void:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty():
		return
	var job := str(me.get("job", ""))
	var bag: Array = me.get("bag", [])
	var equipped: Dictionary = me.get("equipped", {})

	_bag_level.text = "LV. %d" % int(me.get("level", 1))
	_bag_head.text = "소지품 %d/%d" % [bag.size(), Items.bag_size()]
	_bag_gold.text = "%d" % int(me.get("gold", 0))

	# 탭 — 고른 것만 밝게
	for index in _tab_buttons.size():
		var tab: Button = _tab_buttons[index]
		var on := index == _bag_tab
		var box := _inv_box(
			"inv_tab_on" if on else "inv_tab_off", INV_TAB_MARGIN, 4,
			"#4a4232" if on else "#0e1010", "#c9a95c" if on else "#2c2a24"
		)
		for state in ["normal", "hover", "pressed"]:
			tab.add_theme_stylebox_override(state, box)
		# 받은 그림처럼 고른 탭은 밝은 금빛, 나머지는 죽인 회색 글자
		tab.add_theme_color_override("font_color", INV_GOLD_HI if on else INV_DIM)
		tab.add_theme_color_override("font_hover_color", INV_GOLD_HI if on else INV_TEXT)

	# 장착 — 아이콘 이름은 슬롯 이름과 같다 (assets/icons/weapon.png …)
	var slots: Array = Items.slots()
	for index in _gear_cells.size():
		var slot := str(slots[index])
		var worn: Dictionary = equipped.get(slot, {})
		_fill_cell(
			_gear_cells[index], worn, Items.slot_label(slot, job),
			slot if worn.is_empty() else _item_icon(worn)
		)

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
			icon_name = _item_icon(stack)
		_fill_cell(_bag_grid.get_child(index), stack, "", icon_name)

	_show_bag_detail()


## 상세 창 — 고른 것의 등급·이름·종류·능력치·옵션을 푼다 (받은 그림의 왼쪽 창).
## 고른 칸에는 금테를 덮는다. 아무것도 안 골랐으면 창을 닫는다
func _show_bag_detail() -> void:
	for index in _gear_cells.size():
		_gear_cells[index].get_node("pick").visible = _is_picked("equip", index)
	for index in _bag_grid.get_child_count():
		_bag_grid.get_child(index).get_node("pick").visible = _is_picked("bag", index)
	# 크리스탈 창이 떠 있으면 상세 창은 쉰다 — 같은 자리를 번갈아 쓴다
	if _crystal_panel.visible:
		_detail_panel.visible = false
		_show_cell_action()
		_redraw_crystal()
		return

	var stack := _picked_stack()
	_enhance_button.visible = not Items.get_item(str(stack.get("id", ""))).is_empty()
	if stack.is_empty():
		_detail_panel.visible = false
		_bag_action.text = "-"
		_bag_action.disabled = true
		_show_cell_action()
		return
	_detail_panel.visible = _bag_panel.visible
	if Items.is_material(str(stack.get("id", ""))):
		_show_material_detail(stack)
		return

	var item := Items.get_item(str(stack.get("id", "")))
	var grade := int(stack.get("grade", 1))
	var enhance := int(stack.get("enhance", 0))
	var worn := str(_bag_pick.get("where", "")) == "equip"
	var tint := _grade_tint(grade)
	var slot := str(item.get("slot", ""))

	_detail_grade.text = Items.grade_name(grade)
	_detail_grade.add_theme_color_override("font_color", tint)
	_detail_name.text = str(item.get("name", stack.get("id", "?")))
	if enhance > 0:
		_detail_name.text += " +%d" % enhance
	_detail_name.add_theme_color_override("font_color", tint)
	_detail_kind.text = "%s · 착용 Lv.%d" % [Items.slot_label(slot), int(item.get("level", 1))]
	# **낄 수 있는지 판정과 같은 식으로 미리 본다** — 테스트 창·옛 저장은 레벨이 모자란
	# 장비를 끼워 주는데, 한 번 벗으면 판정이 다시 끼기를 거부한다. 그때 "장착" 이 켜져
	# 있으면 눌러도 아무 일이 없어 보인다 (2026-09-23)
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	var level := int(me.get("level", 1))
	var fits := worn or Items.can_equip(item, str(me.get("job", "")), level)
	_detail_kind.add_theme_color_override("font_color", INV_DIM if fits else INV_WARN)
	_detail_state.text = "착용 중" if worn else "보유 중"
	_fill_cell(_detail_icon, stack, "", _item_icon(stack))

	# 아이템 정보 — 이름 · 값 두 줄짜리 표를 다시 채운다
	var rows: Array = [
		["등급", Items.grade_name(grade)],
		["보유 수량", "%d" % int(stack.get("count", 1))],
	]
	var bonus := Items.base_bonus(item, enhance)
	for key in DETAIL_BONUS:
		var value := float(bonus.get(key, 0.0))
		if value > 0.0:
			rows.append([DETAIL_BONUS[key], _bonus_text(key, value)])
	# 옵션은 **차수별로** 적는다 — 1차(드랍) · 2차(크리스탈) · 3차(비어 있음)
	for tier in Items.option_tiers():
		var head := "%d차 옵션" % int(tier.tier)
		var lines: Array = stack.get(str(tier.key), [])
		for option in lines:
			rows.append([head, Items.describe_option(option)])
		if lines.is_empty():
			match str(tier.get("source", "")):
				"crystal": rows.append([head, "크리스탈로 붙임"])
				"drop": pass
				_: rows.append([head, "비어 있음"])
	# 성공률·실패 시 파괴는 **강화 팝업**에 적는다 (2026-09-23 요청 "강화 ui창을 따로 만들어")
	var can := Items.can_enhance(enhance)
	_enhance_button.text = "강화" if can else "최대"
	_enhance_button.disabled = not can
	_fill_detail_rows(rows)

	if fits:
		_bag_action.text = "해제" if worn else "장착"
	else:
		_bag_action.text = "레벨 부족" if level < int(item.get("level", 1)) else "착용 불가"
	_bag_action.disabled = not fits
	_show_cell_action()


## 고른 가방 칸에만 상세 창 단추와 같은 글자("장착"/"사용")를 얹는다.
## 못 끼면 "레벨 부족" 을 붉게 얹는다 — 다시 눌러도 안 끼운다 (`_pick_bag` 이 단추를 본다).
## 장비 창 칸·크리스탈 대상 고르기 중에는 얹지 않는다
func _show_cell_action() -> void:
	var on := not _crystal_panel.visible and _bag_action.text != "-" \
		and str(_bag_pick.get("where", "")) == "bag"
	for index in _bag_grid.get_child_count():
		var act: Label = _bag_grid.get_child(index).get_node("act")
		act.visible = on and _is_picked("bag", index)
		# 칸이 58px 라 네 글자는 두 줄로 접는다
		act.text = _bag_action.text.replace(" ", "\n")
		act.add_theme_color_override("font_color", INV_WARN if _bag_action.disabled else INV_GOLD_HI)
		act.add_theme_font_size_override("font_size", 15 if act.text.contains("\n") else 18)


## 이름 · 값 두 줄짜리 표를 다시 채운다. 줄에 세 번째 칸(색)이 있으면 값을 그 색으로
func _fill_detail_rows(rows: Array, grid: GridContainer = null) -> void:
	if grid == null:
		grid = _detail_info
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for row in rows:
		var key_label := _inv_label(str(row[0]), 17, INV_DIM)
		key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(key_label)
		var tint: Color = row[2] if row.size() > 2 else INV_TEXT
		var value_label := _inv_label(str(row[1]), 17, tint)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value_label)


## 재료(크리스탈)를 고르면 — 등급·능력치가 없고, 낄 수도 없다.
## 쓰는 곳은 **장비 쪽 상세 창의 크리스탈 단추**다
func _show_material_detail(stack: Dictionary) -> void:
	_detail_grade.text = "재료"
	_detail_grade.add_theme_color_override("font_color", INV_DIM)
	_detail_name.text = Items.stack_name(stack)
	_detail_name.add_theme_color_override("font_color", INV_TEXT)
	_detail_kind.text = "재료"
	_detail_kind.add_theme_color_override("font_color", INV_DIM)
	_detail_state.text = "보유 중"
	_fill_cell(_detail_icon, stack, "", _item_icon(stack))
	var material := Items.get_material(str(stack.get("id", "")))
	if int(material.get("skillExp", 0)) > 0:
		_show_book_detail(stack, material)
		return
	_fill_detail_rows([
		["보유 수량", "%d" % int(stack.get("count", 1))],
		["쓰임", "2차 옵션 굴리기"],
	])
	# "사용" 을 누르면 크리스탈 창이 뜬다 (2026-09-23 요청)
	_bag_action.text = "사용"
	_bag_action.disabled = int(stack.get("count", 1)) <= 0
	_show_cell_action()


## 스킬 경험치북 — **가방에서는 안 쓴다.** 스킬창의 강화 칸에서 강화를 골라 넣는다
## (2026-09-23 요청: "인벤토리에서 사용하지 말고 그쪽에서"). 여기서는 보여 주기만 한다
func _show_book_detail(stack: Dictionary, material: Dictionary) -> void:
	_detail_kind.text = "스킬 경험치북"
	_fill_detail_rows([
		["보유 수량", "%d" % int(stack.get("count", 1))],
		["경험치", "+%d" % int(material.get("skillExp", 0))],
	])
	_detail_state.text = "스킬창에서 사용"
	_bag_action.text = "-"
	_bag_action.disabled = true
	_show_cell_action()


## 가방에 든 크리스탈 수
func _crystal_count() -> int:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	for stack in me.get("bag", []):
		if str(stack.get("id", "")) == Items.crystal_id():
			return int(stack.get("count", 1))
	return 0


## 대상(`{"where", "index"}`)이 가리키는 물건. 가방은 **가방 번호**, 장비는 슬롯 번호다
func _stack_at(target: Dictionary) -> Dictionary:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	var index := int(target.get("index", -1))
	if me.is_empty() or index < 0:
		return {}
	if str(target.get("where", "")) == "equip":
		var slots: Array = Items.slots()
		return me.get("equipped", {}).get(str(slots[index]), {}) if index < slots.size() else {}
	var bag: Array = me.get("bag", [])
	return bag[index] if index < bag.size() else {}


## 크리스탈 창을 채운다 — 대상의 이름·큰 칸·1·2·3차 옵션, 보유 수, 굴리기 단추.
## **2차 줄은 금빛**이다 — 크리스탈이 바꾸는 줄이 어느 것인지 한눈에 보여야 한다
func _redraw_crystal() -> void:
	var crystals := _crystal_count()
	_crystal_have.text = "보유 크리스탈 x%d" % crystals
	var stack := _stack_at(_crystal_target)
	var item := Items.get_item(str(stack.get("id", "")))
	if item.is_empty():
		_crystal_target = {}
		_crystal_name.text = "대상 없음"
		_crystal_name.add_theme_color_override("font_color", INV_DIM)
		_crystal_kind.text = ""
		_fill_cell(_crystal_icon, {}, "", "")
		_fill_detail_rows([], _crystal_info)
		_crystal_hint.text = "장비나 인벤토리에서 장비 칸을 누르세요.\n2차 옵션 1줄을 새로 굴립니다."
		_crystal_roll.disabled = true
		return

	var grade := int(stack.get("grade", 1))
	var enhance := int(stack.get("enhance", 0))
	_crystal_name.text = str(item.name) + (" +%d" % enhance if enhance > 0 else "")
	_crystal_name.add_theme_color_override("font_color", _grade_tint(grade))
	var worn := str(_crystal_target.get("where", "")) == "equip"
	_crystal_kind.text = "%s · %s" % [Items.grade_name(grade), "착용 중" if worn else "보유 중"]
	_fill_cell(_crystal_icon, stack, "", _item_icon(stack))

	var rows: Array = []
	for tier in Items.option_tiers():
		var head := "%d차 옵션" % int(tier.tier)
		var tint := INV_GOLD_HI if str(tier.get("source", "")) == "crystal" else INV_TEXT
		var lines: Array = stack.get(str(tier.key), [])
		for option in lines:
			rows.append([head, Items.describe_option(option), tint])
		if lines.is_empty() and str(tier.get("source", "")) != "drop":
			rows.append([head, "비어 있음", INV_DIM])
	_fill_detail_rows(rows, _crystal_info)
	var second: Array = stack.get("options2", [])
	var has_second := not second.is_empty()
	_crystal_hint.text = "굴리면 2차 옵션이 새로 바뀝니다." if has_second \
		else "굴리면 2차 옵션 1줄이 붙습니다."
	_crystal_roll.disabled = crystals <= 0


## 크리스탈 쓰기. **대상은 그대로 둔다** — 결과를 보고 또 굴릴지 정해야 한다.
## 마지막 크리스탈을 쓰면 그 칸이 빠져 **뒤쪽 가방 번호가 하나씩 당겨지므로** 대상 번호도 맞춘다
func _on_crystal_roll() -> void:
	var stack := _stack_at(_crystal_target)
	if Items.get_item(str(stack.get("id", ""))).is_empty():
		return
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	var bag: Array = me.get("bag", [])
	var crystal_at := -1
	for index in bag.size():
		if str(bag[index].get("id", "")) == Items.crystal_id():
			crystal_at = index
			break
	if crystal_at < 0:
		return
	var last := int(bag[crystal_at].get("count", 1)) <= 1

	var index := int(_crystal_target.index)
	if str(_crystal_target.where) == "equip":
		_transport.send(&"useCrystal", {"where": "equip", "key": str(Items.slots()[index])})
	else:
		_transport.send(&"useCrystal", {"where": "bag", "key": index})
		if last and crystal_at < index:
			_crystal_target.index = index - 1
	_redraw_bag()


## 상세 창 능력치 줄에 적는 기본 능력치 (옵션은 따로 적는다)
const DETAIL_BONUS := {
	"attack": "공격력", "defense": "방어력", "maxHp": "체력",
	"crit": "치명타", "attackSpeed": "공격 속도",
}


func _bonus_text(key: String, value: float) -> String:
	if key in ["crit", "attackSpeed"]:
		return "+%.0f%%" % (value * 100.0)
	return "+%d" % roundi(value)


func _is_picked(where: String, index: int) -> bool:
	# 크리스탈 창이 떠 있으면 금테는 **크리스탈 대상**에 두른다 (가방은 칸 → 가방 번호로 바꿔 댄다)
	if _crystal_panel.visible:
		if str(_crystal_target.get("where", "")) != where:
			return false
		var at := index
		if where == "bag":
			at = int(_bag_view[index]) if index < _bag_view.size() else -1
		return int(_crystal_target.get("index", -1)) == at
	return str(_bag_pick.get("where", "")) == where and int(_bag_pick.get("index", -1)) == index


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
	# 경험치북은 가방에서 안 쓴다 — 스킬창에서 쓴다
	if Items.book_exp(str(stack.get("id", ""))) > 0:
		return
	# 크리스탈 "사용" — 상세 창 자리에 크리스탈 창을 띄운다. 대상은 칸을 눌러 고른다
	if Items.is_material(str(stack.get("id", ""))):
		_bag_pick = {}
		_crystal_target = {}
		_crystal_panel.visible = true
		_redraw_bag()
		return
	if str(_bag_pick.get("where", "")) == "equip":
		_transport.send(&"unequip", {"slot": str(Items.slots()[int(_bag_pick.index)])})
	else:
		# 탭으로 걸러 놔서 칸 번호가 아니라 가방 번호를 보낸다
		_transport.send(&"equip", {"index": _picked_bag_index()})
	_bag_pick = {}
	_redraw_bag()


## 상세 창 "강화" — 고른 장비로 강화 팝업을 연다. 대상은 **가방 번호**로 잡는다
## (칸 번호는 탭으로 거르면 어긋난다 — 크리스탈 대상과 같다)
func _open_enhance() -> void:
	if Items.get_item(str(_picked_stack().get("id", ""))).is_empty():
		return
	var worn := str(_bag_pick.get("where", "")) == "equip"
	_enhance_target = {
		"where": "equip" if worn else "bag",
		"index": int(_bag_pick.index) if worn else _picked_bag_index(),
	}
	_enhance_result.text = ""
	_enhance_layer.visible = true
	_redraw_enhance()


## 팝업 X — 상세 창은 그대로 둔다 (대상이 부서졌으면 이미 닫혀 있다)
func _close_enhance() -> void:
	_enhance_layer.visible = false
	_enhance_target = {}
	_redraw_bag()


## 팝업을 채운다 — 이름(등급 색) · `+N → +N+1` · 큰 칸 · 성공률 · 실패 시 파괴 ·
## 기본 능력치가 지금 → 성공하면 얼마. **대상이 부서졌으면** 이름만 남기고 단추를 끈다
func _redraw_enhance() -> void:
	var stack := _stack_at(_enhance_target)
	var item := Items.get_item(str(stack.get("id", "")))
	if item.is_empty():
		_enhance_kind.text = "부서졌습니다"
		_enhance_kind.add_theme_color_override("font_color", INV_WARN)
		_fill_cell(_enhance_icon, {}, "", "")
		_fill_detail_rows([], _enhance_info)
		_enhance_go.disabled = true
		return

	var grade := int(stack.get("grade", 1))
	var enhance := int(stack.get("enhance", 0))
	_enhance_name.text = str(item.get("name", "?"))
	if enhance > 0:
		_enhance_name.text += " +%d" % enhance
	_enhance_name.add_theme_color_override("font_color", _grade_tint(grade))
	_fill_cell(_enhance_icon, stack, "", _item_icon(stack))

	var can := Items.can_enhance(enhance)
	_enhance_go.disabled = not can
	_enhance_kind.add_theme_color_override("font_color", INV_GOLD_HI)
	if not can:
		_enhance_kind.text = "최대 강화"
		_fill_detail_rows([["강화", "+%d (끝)" % enhance]], _enhance_info)
		return

	# 확률은 설계 4장 그대로(90% → 10%). **유지가 없다** — 실패하면 무조건 파괴
	_enhance_kind.text = "+%d  →  +%d" % [enhance, enhance + 1]
	var odds := Items.enhance_odds(enhance)
	var rows: Array = [
		["성공률", "%d%%" % roundi(float(odds.success) * 100.0)],
		["실패 시", "아이템 파괴", INV_WARN],
	]
	var now := Items.base_bonus(item, enhance)
	var next := Items.base_bonus(item, enhance + 1)
	for key in DETAIL_BONUS:
		if float(now.get(key, 0.0)) > 0.0:
			rows.append([
				DETAIL_BONUS[key],
				"%s → %s" % [_bonus_text(key, float(now[key])), _bonus_text(key, float(next.get(key, 0.0)))],
			])
	if int(stack.get("count", 1)) > 1:
		rows.append(["겹친 칸", "한 개만 강화"])
	_fill_detail_rows(rows, _enhance_info)


## 팝업 "강화" — 한 번 두드린다. 결과는 팝업 한 줄과 채팅창에 남는다.
## **대상과 고른 칸은 결과를 따라간다** — 부서져 가방이 줄면 둘 다 비우고(안 비우면 다음
## 물건을 가리킨다), 겹친 칸에서 뗀 것이 성공하면 바로 뒤 칸(뗀 것)으로 옮긴다
func _on_enhance() -> void:
	var stack := _stack_at(_enhance_target)
	var item := Items.get_item(str(stack.get("id", "")))
	if item.is_empty():
		return
	var level := int(stack.get("enhance", 0))
	var count := int(stack.get("count", 1))
	var success := false
	if str(_enhance_target.where) == "equip":
		var slot := str(Items.slots()[int(_enhance_target.index)])
		_transport.send(&"enhanceItem", {"where": "equip", "key": slot})
		success = not _stack_at(_enhance_target).is_empty()
		if not success:
			_bag_pick = {}
	else:
		var before := _bag_count()
		_transport.send(&"enhanceItem", {"where": "bag", "key": int(_enhance_target.index)})
		var after := _bag_count()
		if after < before:
			_enhance_target = {}
			_bag_pick = {}
		elif after > before:
			success = true
			_enhance_target.index = int(_enhance_target.index) + 1
			if not _bag_pick.is_empty():
				_bag_pick.index = int(_bag_pick.index) + 1
		else:
			success = int(_stack_at(_enhance_target).get("enhance", 0)) > level
	if success:
		_enhance_result.text = "강화 성공!  +%d" % (level + 1)
		_enhance_result.add_theme_color_override("font_color", INV_GOLD_HI)
	else:
		_enhance_result.text = "강화 실패 — %s" % ("하나가 부서졌습니다" if count > 1 else "부서졌습니다")
		_enhance_result.add_theme_color_override("font_color", INV_WARN)
	_redraw_bag()
	_redraw_enhance()


func _bag_count() -> int:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	return (me.get("bag", []) as Array).size()


## "낡은 장검 +3 (5등급) 공격 +7, 치명타 +2%"
func _stack_label(stack: Dictionary) -> String:
	var text := Items.stack_name(stack)
	if Items.is_material(str(stack.get("id", ""))):
		return "%s x%d" % [text, int(stack.get("count", 1))]
	var enhance := int(stack.get("enhance", 0))
	if enhance > 0:
		text += " +%d" % enhance
	text += " (%d등급)" % int(stack.get("grade", 1))
	var options: Array = []
	for option in stack.get("options", []) + stack.get("options2", []):
		options.append(Items.describe_option(option))
	if not options.is_empty():
		text += "\n" + ", ".join(options)
	return text


## HUD 하단. **가운데에 퀵슬롯 4칸**, 오른쪽 아래에 자동사냥·스킬·가방 단추.
##
## 퀵슬롯은 스킬 아이콘을 칸 테두리(ui_skill_slot)에 넣고, 쿨타임이 남았으면
## 시계 방향으로 걷히는 어둠과 남은 초를 얹는다. 빈 칸은 "+" — 눌러도 아무 일 없다.
##
## **앵커로 자리를 잡는다** (UI 는 조각을 앵커로 조립한다). 자식을 다 넣은 뒤에
## 최소 크기로 오프셋을 맞추고, 양쪽으로 자라게 해서 해상도가 바뀌어도 가운데에 남는다
func _build_skill_bar() -> void:
	# 아래 가운데 한 묶음 — 위에서부터 레벨 배지 · 경험치 % · 체력 막대 · 퀵슬롯
	# (2026-09-20 요청). 왼쪽 위에 따로 있던 상태판을 여기로 내렸다.
	# 세로 상자에 담아야 막대가 퀵슬롯 줄과 같은 길이로 늘어난다
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(column)

	_build_exp_gauge()
	_build_level_badge(column)

	var hp := _make_bar(HP_BAR_H, Color("#c33122"), 12)
	_hp_bar = hp["bar"]
	_hp_text = hp["text"]
	column.add_child(hp["frame"])

	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 5)
	column.add_child(dock)
	_bar_buttons.clear()
	for slot in int(GameData.combat().get("skillBarSize", 4)):
		var cell := _make_skill_cell(QUICK_CELL, "ui_quick_slot", _on_bar_pressed.bind(slot), QUICK_MARGIN)
		cell.find_child("key", true, false).text = str(slot + 1)
		dock.add_child(cell)
		_bar_buttons.append(cell)
		_bar_cooling.append(false)

	# 자동사냥도 같은 칸이다 — 엄지가 퀵슬롯과 같은 높이에서 닿는다 (2026-09-19 요청).
	# 켜지면 칸 위에서 화살표 고리가 돈다
	# 퀵슬롯에서 한 뼘 띄운다 — 붙여 두면 다섯 번째 스킬 칸으로 보인다
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(AUTO_GAP, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(gap)

	_auto_cell = _make_skill_cell(AUTO_CELL, "ui_quick_slot", _toggle_auto, QUICK_MARGIN)
	# **테두리를 없앤다** (2026-09-20 요청) — 같은 테를 두르면 퀵슬롯과 구분이 안 된다
	_auto_cell.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var auto_icon: TextureRect = _auto_cell.find_child("icon", true, false)
	auto_icon.texture = _icon("ui_icon_auto")
	if auto_icon.texture == null:
		_auto_cell.find_child("text", true, false).text = "자동사냥"
	var auto_inset: MarginContainer = auto_icon.get_parent()
	for side in ["left", "right", "top", "bottom"]:
		auto_inset.add_theme_constant_override("margin_" + side, AUTO_INSET)
	# "자동"·"켜짐" 을 칸 테두리 위로 올린다 — 금테 칸은 테가 두꺼워 글자가 걸렸다
	var auto_badge: MarginContainer = _auto_cell.find_child("badge", true, false).get_parent().get_parent()
	# 칸이 작아진 뒤로는 바닥에 바짝 붙인다 — 가운데로 올라오면 검 손잡이와 겹친다
	auto_badge.add_theme_constant_override("margin_bottom", 4)
	dock.add_child(_auto_cell)

	_auto_spin = TextureRect.new()
	_auto_spin.texture = _icon("ui_auto_spin")
	_auto_spin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_auto_spin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_auto_spin.visible = false
	_auto_spin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 고리 그림이 없으면 코드로 그린 화살표 둘이 돈다 — 에셋을 안 받은 사람도 보여야 한다
	if _auto_spin.texture == null:
		var drawn := SpinRing.new()
		drawn.name = "drawn"
		drawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drawn.set_anchors_preset(Control.PRESET_FULL_RECT)
		_auto_spin.add_child(drawn)
	# 고리를 바닥에서 띄운다 — 칸을 꽉 채우면 아래쪽 화살표가 "자동사냥" 글자와 겹친다
	var spin_pad := MarginContainer.new()
	spin_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spin_pad.add_theme_constant_override("margin_bottom", SPIN_LIFT)
	spin_pad.add_child(_auto_spin)
	_auto_cell.add_child(spin_pad)
	# 아이콘 바로 위, 글자 아래로 넣는다 — 맨 뒤에 두면 고리가 글자를 덮는다
	_auto_cell.move_child(spin_pad, 1)

	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var menu := HBoxContainer.new()
	menu.add_theme_constant_override("separation", 6)
	_ui_root.add_child(menu)

	# 오른쪽 위 — 스킬·가방. 아이콘만 남기고 글자를 뺐다 (2026-09-19 요청).
	# 무엇인지는 그림으로 알린다 — 그림이 없으면 글자가 대신 나온다
	_menu_cells = [
		_icon_button("ui_icon_skill", "스킬", _toggle_skills),
		_icon_button("ui_icon_bag", "가방", _toggle_bag),
		# 던전 — 가방 바로 옆 (2026-09-23 요청). 아직 그림이 없어 글자로 나온다
		_icon_button("ui_icon_dungeon", "던전", _toggle_dungeon),
		_icon_button("", "설계", _toggle_debug),
	]
	for cell in _menu_cells:
		menu.add_child(cell)
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN


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
func _make_skill_cell(size: int, frame: String, on_press: Callable, margin: int = 26) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(size, size)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.add_theme_stylebox_override("panel", _frame_box(frame, margin, 0))

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
	# **칸 크기를 넘기면 안 된다** — 28 로 뒀더니 이 글자의 최소 높이가 칸보다 커서
	# 퀵슬롯이 세로로 늘어났다 (2026-09-20, 찍어서 봤다)
	secs.add_theme_font_size_override("font_size", 16)
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
	badge.add_theme_font_size_override("font_size", 9)
	badge.add_theme_constant_override("outline_size", 5)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 왼쪽 위 — 퀵슬롯 단축키 번호
	var key := Label.new()
	key.name = "key"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	key.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	key.add_theme_font_size_override("font_size", 12)
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


## 창 오른쪽 위 X. **모든 창이 이것 하나를 쓴다** (2026-09-20 요청 — "모든 ui 의
## 닫기 버튼은 오른쪽 위로 통일할거야, x버튼으로 만들어").
##
## `PanelContainer` 는 자식을 창 전체에 깔기 때문에, 여백을 준 `MarginContainer`
## 안에 `Control` 을 한 겹 두고 그 오른쪽 위 구석에 앵커로 붙인다 (레벨 배지와 같은 방법)
##
## `inset` 은 창 안쪽 여백에서 **더** 들이는 폭이다. 인벤토리 결 창(`inv_panel`)은
## 안쪽 여백이 이미 테 안쪽이라 0 을 준다 — 24 를 더 들였더니 상세 창의 큰 칸에 걸쳤다
func _close_button(panel: PanelContainer, on_press: Callable, inset: int = CLOSE_PAD) -> void:
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_right", inset)
	pad.add_theme_constant_override("margin_top", inset)
	panel.add_child(pad)

	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(layer)

	var button := _icon_button("ui_close", "X", on_press, CLOSE_BTN)
	button.name = "close"
	button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	layer.add_child(button)
	if inset == 0:
		# **트리에 넣기 전에는 최소 크기를 8 로 읽어** 위 줄이 X 를 36px 오른쪽에 붙인다
		# (2026-09-23 에 쟀다). 옛 창들은 그 자리에 맞춰 눈으로 `CLOSE_PAD` 를 고른 것이라
		# 그대로 두고, 인벤토리 결 창만 넣은 뒤에 크기로 자리를 다시 잡는다
		button.offset_left = -CLOSE_BTN
		button.offset_right = 0
		button.offset_top = 0
		button.offset_bottom = CLOSE_BTN


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
	_skill_panel.add_theme_stylebox_override("panel", _frame_box("ui_panel", PANEL_MARGIN, 16))
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

	_build_upgrade_column(columns)


## 스킬창 셋째 칸 — **고른 스킬의 강화 두 칸과 경험치북 단추** (2026-09-23).
##
## 요청 둘이 겹쳐 있다: "스킬창에서 스킬 강화하는 ui 만들어. 인벤토리에서 사용하지
## 말고" → "스킬 강화 경험치북들 만들고 … 어떤 타입을 강화할지 선택해서 경험치를 넣을
## 수 있으면". 그래서 **카드를 눌러 강화를 고르고**(금테), 아래 **경험치북 단추**
## (하급·중급·상급, 가진 수)를 누르면 고른 강화에 한 권씩 들어간다. 카드마다 경험치
## 막대와 `320 / 1000` 이 있고, 다 차면 "강화 완료" 로 바뀐다.
##
## 설명 칸 아래에 줄로 넣지 않고 칸을 하나 더 세웠다 — 창이 이미 580px 라 더하면
## 720 을 넘는다. 옆으로는 1234px 로 1280 안에 든다. 조각은 설명 칸과 같은
## `ui_slot` 테두리·고른 칸 테두리(`_pick_box`)·`ui_button` 이고 새 조각은 없다
func _build_upgrade_column(columns: HBoxContainer) -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(UPGRADE_W, 0)
	column.add_theme_constant_override("separation", 10)
	columns.add_child(column)
	var title := Label.new()
	title.text = "강화"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)

	_upgrade_cards.clear()
	for slot in int(GameData.load_table("skills").get("upgradeMax", 2)):
		column.add_child(_make_upgrade_card(slot))

	# 경험치북 — 고른 강화에 한 권씩 넣는다
	_upgrade_hint = _inv_label("", 17, INV_DIM)
	column.add_child(_upgrade_hint)
	var books := HBoxContainer.new()
	books.add_theme_constant_override("separation", 8)
	column.add_child(books)
	_book_buttons.clear()
	for book in Skills.exp_books():
		var button := _make_button("", _on_book_pressed.bind(str(book.id)))
		button.custom_minimum_size = Vector2((UPGRADE_W - 16) / 3.0, 70)
		# 18 이면 "상급 +2000" 이 둥근 테에 닿는다 (찍어서 봤다)
		button.add_theme_font_size_override("font_size", 16)
		books.add_child(button)
		_book_buttons[str(book.id)] = button


## 강화 카드 하나 — 번호 · 이름 · 효과 · 경험치 막대 · `320 / 1000`.
## 스킬 칸처럼 **겉에 투명 단추(`hit`)를 덮어** 카드 어디를 눌러도 고른다
func _make_upgrade_card(slot: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _frame_box("ui_slot", 26, 10))
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 4)
	pad.add_child(rows)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(head)
	var title_label := _inv_label("", 24, INV_TEXT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	head.add_child(_inv_label("%d번" % (slot + 1), 17, INV_DIM))
	var effect := _inv_label("", 18, INV_TEXT)
	rows.add_child(effect)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color("#191a19")
	back.border_color = INV_GOLD.darkened(0.3)
	back.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#e8c14a")
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	rows.add_child(bar)
	var amount := _inv_label("", 17, INV_DIM)
	rows.add_child(amount)

	var pick := Panel.new()
	pick.name = "pick"
	pick.visible = false
	pick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pick.add_theme_stylebox_override("panel", _pick_box())
	card.add_child(pick)
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.pressed.connect(_on_upgrade_pressed.bind(slot))
	card.add_child(hit)

	_upgrade_cards.append({
		"card": card, "name": title_label, "effect": effect, "bar": bar,
		"amount": amount, "pick": pick, "hit": hit,
	})
	return card


## 강화 카드와 경험치북 단추를 고른 스킬로 채운다. 표 순서가 곧 1번·2번이다
func _redraw_upgrades(me: Dictionary) -> void:
	var list := Skills.upgrades_of(_skill_pick)
	var have: Array = me.get("skill_upgrades", {}).get(_skill_pick, [])
	var progress: Dictionary = me.get("skill_upgrade_exp", {}).get(_skill_pick, {})
	if _upgrade_slot >= list.size():
		_upgrade_slot = 0
	for slot in _upgrade_cards.size():
		var card: Dictionary = _upgrade_cards[slot]
		var bar: ProgressBar = card.bar
		card.pick.visible = slot == _upgrade_slot and slot < list.size()
		card.hit.disabled = slot >= list.size()
		if slot >= list.size():
			card.name.text = "없음"
			card.name.add_theme_color_override("font_color", INV_DIM)
			card.effect.text = "아직 없는 강화"
			bar.visible = false
			card.amount.text = ""
			continue
		var upgrade: Dictionary = list[slot]
		var done: bool = str(upgrade.id) in have
		var need := int(upgrade.get("exp", 1))
		var got := need if done else int(progress.get(str(upgrade.id), 0))
		card.name.text = str(upgrade.name)
		card.name.add_theme_color_override("font_color", INV_GOLD_HI if done else INV_TEXT)
		card.effect.text = str(upgrade.get("desc", ""))
		bar.visible = true
		bar.max_value = need
		bar.value = got
		card.amount.text = "강화 완료" if done else "경험치 %d / %d" % [got, need]

	# 경험치북 단추 — 고른 강화가 없거나 이미 붙었으면 다 꺼진다
	var target: Dictionary = list[_upgrade_slot] if _upgrade_slot < list.size() else {}
	var open := not target.is_empty() and not (str(target.id) in have)
	if target.is_empty():
		_upgrade_hint.text = "넣을 강화가 없다"
	elif not open:
		_upgrade_hint.text = "%s — 강화 완료" % target.name
	else:
		_upgrade_hint.text = "%s에 경험치 넣기" % target.name
	for book in Skills.exp_books():
		var count := 0
		for stack in me.get("bag", []):
			if str(stack.get("id", "")) == str(book.id):
				count += int(stack.get("count", 1))
		var button: Button = _book_buttons[str(book.id)]
		button.text = "%s +%d\n%d권" % [book.short, int(book.exp), count]
		button.disabled = not open or count <= 0


## 카드를 누르면 그 강화를 고른다 — 경험치북이 그쪽으로 들어간다
func _on_upgrade_pressed(slot: int) -> void:
	_upgrade_slot = slot
	_redraw_skills()


func _on_book_pressed(book: String) -> void:
	_transport.send(&"feedUpgrade", {"skill": _skill_pick, "slot": _upgrade_slot, "book": book})
	_redraw_skills()


## 테스트 줄의 요청 단추 하나. 누르면 요청을 보내고 열린 창을 다시 그린다
func _test_button(text: String, width: int, font: int, message: StringName, payload: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(width, 52)
	button.add_theme_font_size_override("font_size", font)
	button.text = text
	button.pressed.connect(func() -> void:
		_transport.send(message, payload)
		if _bag_panel.visible:
			_redraw_bag()
		if _skill_panel.visible:
			_redraw_skills()
	)
	return button


## 테스트 스위치 단추 — 왼쪽 아래 (2026-09-19 에 오른쪽 위에서 옮겼다, 요청). 누르면 World 에 요청하고, 글자는 표의 지금 값을 따른다
## (`_refresh_switches`). 스위치를 없애면 이 단추들도 걷는다 → skills.md "테스트 스위치"
##
## **쿨타임 0 하나만 단다.** 레벨 잠금 해제 단추는 2026-09-19 에 걷었다 (요청).
## 스위치 자체와 World 쪽 처리는 그대로다 — 켜고 끄려면 `skills.json` 을 고친다
const SWITCH_BUTTONS := ["cooldownOff"]
func _build_test_switches() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_ui_root.add_child(column)
	_switch_buttons.clear()
	for name in SWITCH_BUTTONS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(230, 52)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_on_switch_pressed.bind(name))
		column.add_child(button)
		_switch_buttons[name] = button
	# 등급별 건틀릿(무기) 일곱 개를 가방에 넣는다 (2026-09-23 요청 — 아이콘 확인용)
	var gauntlets := Button.new()
	gauntlets.custom_minimum_size = Vector2(230, 52)
	gauntlets.add_theme_font_size_override("font_size", 18)
	gauntlets.text = "테스트: 건틀릿 7등급"
	gauntlets.pressed.connect(func() -> void:
		_transport.send(&"debugGauntlets", {})
		if _bag_panel.visible:
			_redraw_bag()
	)
	column.add_child(gauntlets)
	column.move_child(gauntlets, 0)  # 쿨타임 단추가 맨 아래 구석에 남아야 한다 (ui_test 가 본다)
	# 크리스탈 30개를 가방에 넣는다 (2026-09-23 요청 — "가방에 30개 넣어". 드랍이 0.01% 라
	# 주워서는 시험해 볼 수 없다)
	var crystals := Button.new()
	crystals.custom_minimum_size = Vector2(230, 52)
	crystals.add_theme_font_size_override("font_size", 18)
	crystals.text = "테스트: 크리스탈 30"
	crystals.pressed.connect(func() -> void:
		_transport.send(&"debugCrystals", {"count": 30})
		if _bag_panel.visible:
			_redraw_bag()
	)
	column.add_child(crystals)
	column.move_child(crystals, 0)
	# 스킬 강화 — **모든 스킬 1번 강화 · 2번 강화 · 초기화** (2026-09-23 요청). 경험치북
	# 없이 바로 붙는다 (사용자 선택). 줄이 위로 자라므로 앞의 둘은 **한 줄에 반씩** 놓는다
	var reset := _test_button("테스트: 강화 초기화", 230, 18, &"debugResetUpgrades", {})
	column.add_child(reset)
	column.move_child(reset, 0)
	# 경험치북 — 종류마다 10권 (던전 드랍 전까지 얻을 길이 이것뿐이다, 사용자 선택)
	var books := _test_button("테스트: 경험치북 +10", 230, 18, &"debugBooks", {})
	column.add_child(books)
	column.move_child(books, 0)
	var upgrade_row := HBoxContainer.new()
	upgrade_row.add_theme_constant_override("separation", 6)
	for slot in 2:
		upgrade_row.add_child(_test_button(
			"전체 %d번 강화" % (slot + 1), 112, 16, &"debugUpgradeAll", {"slot": slot}
		))
	column.add_child(upgrade_row)
	column.move_child(upgrade_row, 0)
	# 무적은 플레이어 값이라 표 스위치와 따로 논다 — 요청은 `invincible`
	_invincible_button = Button.new()
	_invincible_button.custom_minimum_size = Vector2(230, 52)
	_invincible_button.add_theme_font_size_override("font_size", 18)
	_invincible_button.text = "테스트: 무적  끔"
	_invincible_button.pressed.connect(_toggle_invincible)
	column.add_child(_invincible_button)
	column.move_child(_invincible_button, 0)
	# 스킬 범위도 표 스위치가 아니다 — **화면에만 있는 값**이라 판정에 보낼 것이 없다
	_range_button = Button.new()
	_range_button.custom_minimum_size = Vector2(230, 52)
	_range_button.add_theme_font_size_override("font_size", 18)
	_range_button.pressed.connect(_toggle_range)
	column.add_child(_range_button)
	column.move_child(_range_button, 0)
	# 숫자는 **단추 위 전용 줄**에 적는다. HUD 한 줄(`_last_event`)에 적었더니
	# 바로 다음 틱의 몬스터 피격 알림이 덮어써서 읽을 틈이 없었다 (2026-09-21)
	_range_label = Label.new()
	_range_label.add_theme_font_size_override("font_size", 17)
	_range_label.add_theme_color_override("font_color", Color("#46e0d8"))
	column.add_child(_range_label)
	column.move_child(_range_label, 0)
	_refresh_range_button()
	_refresh_switches()
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# 왼쪽 아래 구석은 채팅창 자리다 (2026-09-23) — 묶음을 채팅창 위로 올린다
	var lift := ChatLog.SIZE.y + EXP_GAUGE_H + CHAT_MARGIN + 8 - 20
	column.offset_top -= lift
	column.offset_bottom -= lift


func _on_switch_pressed(name: String) -> void:
	var on := Skills.cooldown_off() if name == "cooldownOff" else Skills.unlock_all()
	_transport.send(&"testSwitch", {"name": name, "on": not on})
	_refresh_switches()
	if _skill_panel.visible:
		_redraw_skills()


func _toggle_invincible() -> void:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	_transport.send(&"invincible", {"on": not bool(me.get("invincible", false))})


## 스킬 범위 표시를 켜고 끈다. 끄면 이미 떠 있는 것도 바로 치운다 —
## 끄고 나서 1초쯤 남아 있으면 꺼졌는지 아닌지가 헷갈린다
func _toggle_range() -> void:
	_show_range = not _show_range
	if not _show_range:
		for mark in _range_marks:
			if is_instance_valid(mark):
				mark.queue_free()
		_range_marks.clear()
		_range_label.text = ""
	_refresh_range_button()


func _refresh_range_button() -> void:
	_range_button.text = "테스트: 스킬 범위  %s" % ("켬" if _show_range else "끔")
	_range_button.modulate = Color("#7ce08a") if _show_range else Color.WHITE


func _refresh_invincible(me: Dictionary) -> void:
	var on := bool(me.get("invincible", false))
	_invincible_button.text = "테스트: 무적  %s" % ("켬" if on else "끔")
	_invincible_button.modulate = Color("#7ce08a") if on else Color.WHITE


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
		# 맨 앞으로 — 강화 칸을 더해 1234px 가 되면서 왼쪽 테스트 단추 줄 밑으로
		# 들어갔다. 단추 글자가 창 위에 찍혔다 (2026-09-23 캡처)
		_skill_panel.get_parent().move_to_front()
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
	var damage := Skills.damage_text(skill)
	if damage != "":
		_skill_desc.text += "\n\n" + damage

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
	_redraw_upgrades(me)


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
	# 빈 칸은 아무 일도 안 한다 — 스킬창을 열던 것은 뺐다 (2026-09-23 요청)
	if slot >= bar.size():
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
	_npc_tab = "buy" if role == "shop" else "enhance"
	_redraw_npc()
	_npc_panel.visible = true


## 목록은 **열 때마다 다시 그린다** — 사고팔고 두드리는 동안 계속 바뀐다.
## 웹 클라의 npcDialog(상점) · craftWindow 자리다. 대장간은 제작을 걷은 뒤 강화만 남았다
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
	var names := {"buy": "사기", "sell": "팔기"} if _npc_role == "shop" else {"enhance": "강화"}
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
		"enhance":
			_list_bag(me, "강화", func(index: int) -> void:
				_transport.send(&"npcEnhance", {"index": index})
			)


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



func _list_bag(me: Dictionary, verb: String, action: Callable) -> void:
	if me.bag.is_empty():
		var empty := Label.new()
		empty.text = "가방이 비었습니다"
		_npc_rows.add_child(empty)
		return
	for index in mini(me.bag.size(), 12):
		var stack: Dictionary = me.bag[index]
		# 재료는 팔지도 강화하지도 않는다
		if Items.is_material(str(stack.get("id", ""))):
			continue
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


## 차원문 창. 조각을 조립하는 건 GatePanel 이 하고, 여기서는 달고 고른 곳을 보내기만 한다.
##
## **HUD 보다 위에 있는 제 층(CanvasLayer)에 단다** (2026-09-20 지적: "포탈이 HUD에
## 이미지가 가려지는데"). `_ui_root` 안에 두면 나중에 붙는 액션바·가방창이 위에
## 그려져 목록을 덮고, 그쪽이 누름까지 먹어 줄이 안 눌렸다. 층 번호를 올리면
## 붙이는 순서와 상관없이 늘 맨 위다
func _build_gate_panel() -> void:
	var top := CanvasLayer.new()
	top.name = "GateLayer"
	top.layer = 10
	add_child(top)

	# 조각(판·단추·닫기 X)은 가방창·스킬창과 같은 것을 쓴다 — 여는 손을 넘겨준다
	_gate_panel = GatePanel.create(_frame_box, _icon)
	# 한글 폰트는 _ui_root 의 테마에 있다 — 다른 층이라 직접 물려준다
	_gate_panel.theme = _ui_root.theme
	_gate_panel.picked.connect(_on_gate_pick)
	top.add_child(_gate_panel)

	# 던전 창도 같은 층이다 — 틀·줄·끌기를 차원문 창에서 물려받는다
	_dungeon_panel = DungeonPanel.make(_frame_box, _icon)
	_dungeon_panel.theme = _ui_root.theme
	_dungeon_panel.picked.connect(_on_gate_pick)
	top.add_child(_dungeon_panel)


func _open_gate() -> void:
	_dungeon_panel.visible = false
	_gate_panel.open(_shown_zone)


## 던전 단추. 열려 있으면 닫는다. 차원문 창과 한 자리라 둘이 겹치지 않게 한쪽을 닫는다
func _toggle_dungeon() -> void:
	if _dungeon_panel.visible:
		_dungeon_panel.close_panel()
		return
	_gate_panel.visible = false
	_dungeon_panel.open(_shown_zone)


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


## 차원문 창과 던전 창이 같이 쓴다 — 둘 다 결국 `travel` 요청이고 World 가 다시 본다
func _on_gate_pick(zone_id: String) -> void:
	_gate_panel.visible = false
	_dungeon_panel.visible = false
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
	# 떠 있던 이펙트는 풀로 거둔다 — 예전에는 존과 같이 지워졌다
	_fx.recall()
	_aoe_marks.clear()
	_range_marks.clear()
	_zone_node = Node3D.new()
	add_child(_zone_node)
	_shown_zone = zone_id
	# 이펙트 셰이더를 미리 굽는다 — 스킬을 처음 쓸 때 멈칫하지 않게 (한 게임에 한 번)
	if _camera != null:
		FxWarm.run(self, _camera, _ui_root.theme.default_font if _ui_root != null and _ui_root.theme != null else null)

	var zone := GameData.zone(zone_id)
	var env: Dictionary = zone.get("env", {})
	var size := float(zone.get("size", 66))
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
	_tick_range(delta)
	if _auto_spin != null and _auto_spin.visible:
		# PanelContainer 가 자식 크기를 칸에 맞춰 다시 잡는다 — 축은 그때마다 가운데로
		_auto_spin.pivot_offset = _auto_spin.size / 2.0
		_auto_spin.rotation += delta * SPIN_SPEED


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
	HitFx.apply_react(_player, _last_delta)
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
			HitFx.settle(node)
			continue
		node.position.x = monster.x
		node.position.z = monster.z
		HitFx.apply_react(node, _last_delta)
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

	_refresh_status(me)
	_refresh_bar(me)
	_refresh_auto(me)
	_refresh_invincible(me)

	_label.text = "%s   골드 %d   몬스터 %d/%d   %d fps   빌드 %s\n%s" % [
		GameData.zone(zone_now).get("name", zone_now),
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
	var fx := HitFx.spawn(_fx, at, payload, font)
	if body != null and not bool(payload.get("heal", false)):
		fx.flash_body(body)

	# 회복은 맞은 것이 아니다
	if on_me and not bool(payload.get("heal", false)):
		var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
		var max_hp := float(me.get("stats", {}).get("maxHp", 100))
		# 최대 체력의 4분의 1을 한 번에 맞으면 제일 진하다
		_hurt.hit(float(payload.get("amount", 0)) / maxf(1.0, max_hp * 0.25))

	_feel_hit(payload, on_me, body)


## 타격감 — 히트스톱·흔들림·몸 튕김·찌그러짐. 세기는 `HitFx.TIERS` 네 단계다
## (평타 < 치명타 < 처치 < 보스) → docs/features/hit-effects.md 의 "타격감"
func _feel_hit(payload: Dictionary, on_me: bool, body: Node3D) -> void:
	var tier := HitFx.tier_of(payload, false)
	if tier < 0:
		return
	# 보스가 끼었나 — 내가 맞았으면 때린 놈, 아니면 맞은 놈을 본다
	var mob_id := str(payload.get("source", "")) if on_me else str(payload.get("target", ""))
	var mob := _find_mob(_transport.snapshot(), mob_id)
	var boss := bool(mob.get("boss", false))
	tier = HitFx.tier_of(payload, boss)
	var feel: Dictionary = HitFx.TIERS[tier]

	# 때린 쪽도 같이 멈춰야 "걸렸다" 가 된다
	var attacker: Node3D = _mob_nodes.get(mob_id, null) if on_me else _player
	HitFx.hitstop(body, feel.stop)
	HitFx.hitstop(attacker, feel.stop)
	if body != null:
		# **내 캐릭터는 밀지 않는다** — 카메라가 쫓아가 화면째 흔들리고, 걷는지 보는
		# 거리 계산(`_moving`)이 밀린 거리를 달린 걸로 읽는다. 퍼지기만 한다
		var kick: float = 0.0 if on_me else float(feel.kick) * (HitFx.BOSS_KICK if boss else 1.0)
		var from := attacker.position if attacker != null else body.position
		HitFx.react(body, from, kick, feel.squash)
	if float(feel.shake) > 0.0:
		_camera.shake(feel.shake, feel.shake_time)


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
	if not (skill in ["rising_kick", "thunder_fall", "sky_breaker", "frost_pillar"]):
		return
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty():
		return
	var here := Vector3(me.x, 0.0, me.z)
	if skill == "thunder_fall":
		# 강화는 판정이 이벤트에 실어 보낸다 — "기절" 이면 붉은 번개, "범위" 면 좌우로
		# 두 번 더. 둘은 따로 논다 (범위만 붙었으면 색은 그대로)
		var upgrades: Array = payload.get("upgrades", [])
		LightningFx.bolt(_fx, here, float(me.rot), "stun" in upgrades, "wide" in upgrades)
	elif skill == "sky_breaker":
		QuakeFx.slam(_fx, here, float(me.rot))
		_camera.shake(QuakeFx.SHAKE, QuakeFx.SHAKE_TIME)
	elif skill == "frost_pillar":
		IceFx.burst(_fx, here, float(me.rot))
		_camera.shake(IceFx.SHAKE, IceFx.SHAKE_TIME)
	else:
		SkillFx.claw(_fx, here, float(me.rot))


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
## 왼쪽 위 상태판을 스냅샷에 맞춘다. 레벨·체력·경험치는 **여기 한 곳에서만** 그린다
func _refresh_status(me: Dictionary) -> void:
	_level_label.text = "Lv.%d" % int(me.level)
	var max_hp := maxf(1.0, float(me.stats.maxHp))
	_hp_bar.max_value = max_hp
	_hp_bar.value = float(me.hp)
	_hp_text.text = "%d / %d" % [int(me.hp), int(max_hp)]
	# 다음 레벨까지 필요한 양. 만렙이면 0 이 와서 0 으로 나누게 된다
	var need := maxi(1, Combat.exp_to_next(int(me.level)))
	_exp_text.text = "경험치 %.2f%%" % (minf(float(me.exp) / need, 1.0) * 100.0)
	_exp_bar.max_value = need
	_exp_bar.value = mini(int(me.exp), need)


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
	# 켜져 있는 동안만 고리가 보이고 돈다 (_process). 끄면 각도를 되돌려
	# 다음에 켤 때 늘 같은 자리에서 시작한다
	_auto_spin.visible = on
	if not on:
		_auto_spin.rotation = 0.0
	# 켜진 것은 **고리가 알린다** — 칸까지 초록으로 물들이면 고리와 아이콘이
	# 한 덩어리로 보여 무엇이 도는지 알 수 없었다 (2026-09-19, 찍어서 봤다)
	_auto_cell.find_child("badge", true, false).text = "자동사냥"
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


## 스킬 범위 표시를 늙힌다. 수명이 다한 것은 스스로 알려 준다
func _tick_range(delta: float) -> void:
	var alive: Array = []
	for mark in _range_marks:
		if not is_instance_valid(mark):
			continue
		if mark.tick(delta):
			mark.queue_free()
			continue
		alive.append(mark)
	_range_marks = alive


## 판정이 보낸 모양 그대로 땅에 그리고, 몇 마리가 걸렸는지는 글로 적는다 —
## 반경만 보면 "왜 저기 있는 놈이 안 맞지" 가 `maxTargets` 때문인지 모른다
func _show_skill_range(payload: Dictionary) -> void:
	if _zone_node == null:
		return
	_range_marks.append(SkillRange.show_cast(_zone_node, payload))
	_range_label.text = "%s  %.1fm · %d° · %d/%d 마리" % [
		Skills.all().get(str(payload.get("skill", "")), {}).get("name", "스킬"),
		float(payload.get("reach", 0.0)),
		roundi(rad_to_deg(float(payload.get("arc", 0.0)))),
		int(payload.get("hits", 0)),
		int(payload.get("max_targets", 0)),
	]
