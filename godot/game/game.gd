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
## 땅을 눌러 걷는데 **이만큼(ms) 동안 이만큼(m)도 못 가면 이동 명령을 버린다**
## (2026-09-27 "둘러싸인 채 못 가는 데를 누르면 가만히 서 있다"). 휘두르는 경직
## (400ms)에는 걸리지 않게 그보다 길게 잡았다 → "켜 둔 채로 조작하면 사람이 이긴다"
const STUCK_MS := 600
const STUCK_GAIN := 0.1

## 마을 NPC 의 키(m). 모델은 높이 1 로 정규화돼 오니 여기서 키를 준다.
## 다 1.8 이면 복제인간이 선다 — 대장장이는 크게, 소녀·노인은 작게. 없으면 Rig.HUMAN_HEIGHT
const NPC_HEIGHTS := {
	"smith": 1.95,
	"merchant": 1.75,
	"villager_sack": 1.66,
	"villager_hood": 1.55,
	"villager_old": 1.68,
}

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
## 랭킹 창 표 높이 — 넘치면 창 안에서 굴린다 (위 50명)
const RANK_LIST_H := 360
## 아이템 상세 창(고른 것 · 착용 중 비교)의 폭 · 큰 칸 · 글자. **작게 둔다** —
## 두 창을 인벤토리 높이(670) 안에 위아래로 쌓는다 (2026-09-25 요청: "상세 정보창
## 크기를 좀 줄여" + 착용 중 장비 비교). 옆으로는 자리가 없다: 1280 폭에 장비·상세·
## 인벤토리가 이미 거의 다 찬다
const ITEM_W := 240
const ITEM_ICON := 64
const ITEM_FONT := 14
## 창이 화면 양 끝에서 떨어지는 폭과, 상세 창·인벤토리 사이
const WINDOW_EDGE := 16
const WINDOW_GAP := 8
## 인벤토리 오른쪽 세로 탭 한 개, 단추 한 개
const INV_TAB := Vector2(64, 58)
const INV_BUTTON := Vector2(76, 40)
## 샌드백 창 주간 보상 줄의 옐로우 크리스탈 그림 한 변 — 글자(18) 한 줄 높이에 맞춘다
const SANDBAG_GEM := 26
## 창을 던전 결로 (2026-09-28) — 틀 안쪽 여백 · 제목 문장 크기.
## 인벤토리 결 조각(`inv_panel`·`inv_slot`·`inv_tab_*`·`inv_button`)은 이때부터 안 쓴다 — 고른 칸 금테만 남았다
const STONE_PAD := 30
const STONE_EMBLEM := 40
## 고른 칸 금테(`inv_slot_pick`)의 9조각 여백 (구운 크기에서 잰 값, 2026-09-23)
const INV_PICK_MARGIN := 8
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
## 강화 칸 글자는 칸 폭이 고정이고 **글자가 줄어든다** — 이름·설명·경험치·안내 줄 모두
## 한 줄에 안 들어가면 제 크기에서 한 단계씩 줄인다(`UPGRADE_FONT_MIN` 까지, 그래도 넘치면 잘린다).
## 글자에 맞춰 칸이 늘면 창 전체가 들썩였다 — "+10만" 뒤 안내 줄이 280 을 넘었다 (2026-09-29 지적)
const UPGRADE_DESC_SIZE := 18
const UPGRADE_FONT_MIN := 10
const SKILL_INSET := 5
## 스킬창 설명 칸이 늘 잡아 두는 줄 수 — 설명 두 줄 + 빈 줄 + 데미지 줄.
## 설명이 한 줄이든 두 줄이든 칸 높이를 **두 줄 기준**으로 고정한다 (2026-09-28 요청).
## 칸이 줄 수를 따라 자라면 세 칸을 가운데에 모으는 `CenterContainer` 가 창 전체를 위아래로 밀었다
const SKILL_DESC_LINES := 4
## 패시브 나무 (2026-09-30 요청: 받은 그림 — 레벨 줄마다 칸). 2026-10-01 부터 계열 하나가 칸 하나라 화살표는 없다.
## 칸 · 칸 사이(가로·세로) · 왼쪽 "Lv.N" 폭
const TREE_CELL := 84
const TREE_GAP := 22
const TREE_LABEL_W := 80
## [레벨업] 꾹 누르기 — 처음 기다림 · 첫 간격 · 가장 짧은 간격 · 한 번마다 간격에 곱하는 수 (2026-10-01)
const LEARN_HOLD_DELAY := 0.35
const LEARN_HOLD_GAP := 0.12
const LEARN_HOLD_MIN := 0.03
const LEARN_HOLD_SPEEDUP := 0.85
## 안 배운 칸의 음영 (그림·틀에 곱한다)
const TREE_SHADE := Color(0.4, 0.4, 0.4)
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
## 평소 줄에 늘 서는 메뉴 — 이름(글자)으로 고른다. 나머지는 ≡ 를 눌러야 펼쳐진다 (2026-10-01 요청 그림:
## 다른 게임의 메뉴 — 평소엔 아이콘 넷 + ≡, 누르면 판이 펼쳐지고 ≡ 자리가 X)
const MENU_QUICK := ["정보", "스킬", "가방", "던전"]
## 펼친 판의 열 수 · 판 안 여백 · 줄 간격
const MENU_SHEET_COLUMNS := 4
const MENU_SHEET_PAD := 12
const MENU_SHEET_ROW_GAP := 10
## HUD 위쪽 가운데 "마을가기" 단추 크기
const HOME_BUTTON_SIZE := Vector2(140, 48)
const MENU_INSET := 3
## 메뉴 단추 아래 이름 글자 — 그림만으로는 무엇인지 헷갈린다 (2026-09-28 요청, 받은 그림은
## 아이콘 아래에 "상점·인벤토리·스펠·퀘스트" 가 붙어 있다). **아이콘 네모 밑에 세로로 쌓는다** —
## 처음엔 칸 안에서 아이콘 발치와 4px 겹쳤는데, 글자 줄 높이가 칸보다 커서 아이콘을 덮었다
## ("아이콘이랑 글씨가 겹쳐 있는데, 스크린샷처럼 아래에 넣어", 같은 날)
const MENU_CAPTION_GAP := 1
const MENU_CAPTION_FONT := 14
## 가방 단추 오른쪽 위 빨간 점 — 새 장비를 얻었는데 아직 가방을 안 열어 봤다 (2026-09-28 요청
## "신규 아이템 획득하면 가방에 레드닷 표시해줘"). 아이콘 네모 모서리에 반쯤 걸친다
const RED_DOT := 14
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
## 캐릭터 정보 창에서 **기본 → 증가 % → 최종** 으로 푸는 스탯. 이름은 `DETAIL_BONUS` 를 쓴다
const CHAR_SPLIT := ["attack", "defense", "maxHp"]

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
## 블렌더로 지은 동작 (`scripts/blender/fighter_moves.py`). 평타는 **옆차기로 든 발로 뺨 치듯 좌우로**
## 친다 (2026-09-30 요청: "느릴 때, 빠를 때 구분하지 말고, 아까 스크린샷 보여준 자세에서 뺨 때리듯이
## 좌우로 팍팍팍팍" — 그 전엔 높은 옆차기를 느릴 때·빠를 때 나눠 틀었고, 그 전엔 앞차기, 잽·스트레이트).
## 네 벌 모두 길이 0.9초 = 기본 간격이라 **공속만큼 배속**(`swing.speed`)으로 틀면 다음 대가 오는 때에
## 끝난다. 고르는 것은 `_kick_clip`. 스킬은 스킬마다 하나다
const KICK_FULL := "KickSlapFull"
const KICK_IN := "KickSlapIn"
const KICK_A := "KickSlapA"
const KICK_B := "KickSlapB"
const SWING_CLIPS := [KICK_FULL, KICK_IN, KICK_A, KICK_B]
## 초당 이만큼 미만이면 **한 대마다 치고 제자리로 내려와 선다**(`KICK_FULL`) — 2026-09-30 요청:
## "공속이 초당 3타 이하 일 떄는 발차기 하고 제자리로 왔다가 다시 발차기 하고 … 4타부터 지금처럼".
## 질풍각 6단계(초당 3.8타)까지가 내려오고, 7단계(4.2타)부터 발을 든 채 좌우로 친다
const KICK_CHAIN_HITS := 4.0
## 지난 평타 시각 — 한 간격의 1.5배 안에 다음 대가 오면 발을 든 채 이어 친다
var _last_kick_at := -100000
## 이어 칠 때 다음이 A(바깥으로) 인가. 첫 대(`KICK_IN`)는 안쪽에서 끝나니 다음은 A 다
var _kick_to_a := true
const SKILL_CLIPS := {
	"rising_kick": "Claw", "thunder_fall": "Thunder",
	"sky_breaker": "SkyBreaker", "frost_pillar": "FrostStomp",
	# 파천장 — 주먹을 내질러 0.2초 멈췄다가 기가 나간다
	"ki_burst": "KiBurst",
	# 폭렬권 — 0.10초에 주먹을 뻗고 버티다가 0.77초에 두 팔을 펼쳐 기를 터뜨린다
	"nova_fist": "NovaFist",
	# 무적파쇄권 — 기마 자세로 1초 떨며 기를 모으고 1.08초에 오른주먹을 내지른다
	"crush_fist": "CrushFist",
}
## 판정은 늦게 떨어지는데 **이펙트는 누르자마자 시작하는** 스킬. 폭렬권은 주먹이
## 닿는 순간부터 기운이 끓다가 판정 시각(`delayMs`)에 터진다 — 그 시각은 이펙트가
## 스스로 맞춘다 (`NovaFx.EXPLODE`)
## 무적파쇄권도 같다 — 기를 모으는 1초 동안 이펙트가 돌다가 `CrushFx.PUNCH` 에 터진다
const EARLY_FX := ["nova_fist", "crush_fist"]
## 앞 자세에서 동작으로 섞어 넘어가는 시간. 부딪히는 순간이 클립 0.1초 자리라
## 길게 섞으면 이펙트보다 주먹이 늦는다
const MOVE_BLEND := 0.06
## 동작이 끝나거나 끊겨 대기·달리기로 돌아갈 때 섞는 시간
const MOVE_OUT_BLEND := 0.15
## 동작이 클립 길이의 몇 배까지 걸려도 기다리나. 끝은 클립 자리로 보고(`_play_player_clip`),
## 이건 멎지 않는 클립에 붙잡히지 않게 하는 상한이다 — 히트스톱이 겹쳐도 이만큼은 안 된다
const MOVE_CEILING := 2.0
## 맞았을 때 — 뒤로 젖히며 팔로 얼굴을 막는다 (0.45초).
## **공격 동작(평타·스킬) 중에는 안 튼다** — 공격이 늘 먼저다. 거꾸로 맞는 동작 중에
## 공격하면 공격 동작이 곧바로 이긴다 (`_start_move` 가 무엇이 돌든 갈아끼운다)
## (2026-09-24 요청. 그 전엔 평타는 주먹이 닿은 뒤면 끊었다).
## 달리는 중에도 안 튼다 — 다리가 멈춰 미끄러진다
const HIT_CLIP := "Hit"
## 지금 트는 동작과 언제 끝나나. `_move_fresh` 면 다음 그리기에서 처음부터 튼다
var _move_clip := ""
var _move_until := 0
var _move_fresh := false
## 동작 배속 — 날라차기만 1 이 아니다 (발이 닿는 키가 도착에 오게 판정이 정해 준다)
var _move_speed := 1.0
## 날라차기 클립 — 판정(`World._lunge`)이 `lunge` 로 알린다
const LUNGE_CLIP := "FlyingKick"
var _swings := 0
var _camera: CameraRig
## 존 이름·골드·fps·빌드가 적히는 줄. 상태판 아래에 깔린다
var _label: Label
var _marker: MeshInstance3D

var _target: Vector3 = Vector3.INF
## 막혔는지 재는 기준점과 그 시각. 여기서 `STUCK_GAIN` 을 벗어나면 다시 잡는다
var _stuck_at: Vector3 = Vector3.INF
var _stuck_since := 0
## 땅을 누른 채로 있나. 누르고 있는 동안은 매 프레임 그 화면 점 아래로 `_target` 을
## 다시 잡는다 — 손가락(마우스)을 따라 걷는다 (2026-09-26 요청)
var _holding := false
## 누르고 있는 화면 점. 끌면 `_input` 이 옮긴다
var _hold_at := Vector2.ZERO
var _seq := 0
var _half_size := 0.0
## 이 존의 지형. 없으면(`null`) 평평한 바닥이다 — 높이는 `_ground_y` 로만 읽는다
var _terrain: Terrain = null
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
## 몬스터 id -> 휘두르는 동작을 언제까지 트나(ms). **서버가 때린 순간(`hit`)에
## 켠다** — 상태(`attack`)로 틀면 사거리 안에 서 있는 내내 3.73초짜리 클립이
## 준비 자세부터 감겨, 맞고 있는 동안 한 번도 안 휘두르는 것으로 보인다 (2026-09-24)
var _mob_swing_until: Dictionary = {}
## 오우거 `Attack` 에서 첫 할퀴기가 시작되는 자리(초). 손이 닿는 건 1.00초라, 판정이 휘두르기를
## 알리고 0.2초 뒤(`monsterHitDelayMs`)에 피해를 넣는다. 저레벨 여섯(mob_moves.py)도 1.00 에 친다. 길이는 서버 경직
## (`monsterSwingMs` 0.65초)과 같다 → docs/features/characters-and-animation.md
const MOB_SWING_FROM := 0.8
## 마지막으로 일어난 일 한 줄 (맞았다·레벨 올랐다)
var _last_event := ""
## 왼쪽 아래 채팅창 — 장비 획득·강화·말을 적는다 (`ChatLog`)
var _chat: ChatLog
## 오른쪽 아래, 잠깐 떴다 사라지는 경험치 알림 (`ExpToast`, 2026-09-28)
var _exp_toast: ExpToast
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
## 평타가 맞을 때 나는 소리 (2026-09-30 요청). 없으면(에셋을 안 받은 PC) 조용히 넘어간다
const HIT_SOUND := "res://assets/sfx/hit.wav"
var _hit_sound: AudioStreamPlayer
var _touch_guard: TouchGuard
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
## 상점·대장간 창 — 조각으로 조립한 창이다 (`NpcPanel`). 지금 마을에는 서는 NPC 가 없다
var _npc_panel: NpcPanel
## HUD 스킬 아이콘의 레드닷 — 배울 수 있는 패시브 단계가 있으면 켠다 (`_refresh_status`)
var _skill_dot: Control
## 액션바 4칸. 눌리면 그 스킬을 쓴다
var _bar_buttons: Array = []
## 칸마다 지난 프레임에 쿨타임이 돌고 있었나 — 끝나는 순간을 잡아 번쩍인다
var _bar_cooling: Array = []
## 물약 칸 — 퀵슬롯 바로 옆. 누르면 마신다. 쿨타임·자동 기준은 스냅샷(me.potion_*)만 보고 그린다
var _potion_cell: PanelContainer
## 지난 프레임에 물약 쿨타임이 돌고 있었나 — 끝나는 순간 번쩍인다
var _potion_cooling := false
## 물약 설정 창 — 저절로 마실 HP % 를 고른다 (`_potion_step`)
var _potion_panel: PanelContainer
var _potion_pct_label: Label
var _potion_slider: HSlider
## 소리 설정 창 (메뉴 "설정") — 전체 볼륨. 값은 기기 설정(`SoundSettings`)이다
var _sound_panel: PanelContainer
var _sound_label: Label
var _sound_slider: HSlider
## 테스트 스위치 단추 — 이름 → Button
var _switch_buttons: Dictionary = {}
## 테스트 무적 단추. 글자는 **스냅샷(me.invincible)** 만 보고 그린다 (자동사냥과 같다)
var _invincible_button: Button
## 치트(테스트 단추) 목록 묶음과 그것을 여닫는 단추 (2026-09-25 — 왼쪽이 치트로 도배돼 안 보였다)
var _cheat_column: VBoxContainer
var _cheat_toggle: Button
## 테스트 모드 스킬 목록과 그것을 여닫는 단추 (2026-09-28) — 치트 여닫기 단추 오른쪽
var _skill_list: GridContainer
var _skill_list_toggle: Button
## 자동 사냥 칸. 퀵슬롯 옆에 같은 모양으로 붙는다. 켜짐 표시는 **서버가 준
## me.auto** 로만 정한다 — 눌린 것으로 지레 바꾸면 판정이 거절했을 때 화면만
## 켜진 채로 남는다
var _auto_cell: PanelContainer
## 켜져 있는 동안 칸 위에서 도는 화살표 고리
var _auto_spin: TextureRect
## 오른쪽 위 메뉴 단추 전부 — 순서는 정보 · 스킬 · 강화 · 크리스탈 · 가방 · 던전 · 헬스 · 도감 · (랭킹) · 설정.
## 평소 줄에 서는 것(`MENU_QUICK`)과 ≡ 를 눌러 펼치는 판에 서는 것으로 나뉜다 (2026-10-01)
var _menu_cells: Array = []
## 평소 줄 · 펼친 판 · 판의 칸 격자 · ≡ / X 단추
var _menu_bar: HBoxContainer
var _menu_sheet: PanelContainer
var _menu_grid: GridContainer
var _menu_open_cell: Control
var _menu_close_cell: Control
## 가방 단추의 빨간 점 (`_add_red_dot`). 장비를 얻으면 켜고, 가방을 열면 끈다
var _bag_dot: Control
## 설계 창 단추 — 오른쪽 맨 아래, 알파 0 (안 보이지만 눌린다)
var _design_cell: Control
## HUD 위쪽 가운데 "마을가기" — 마을 밖에서만 선다 (`_refresh_home_button`)
var _home_button: Button
## 시련의 탑 시계(마을가기 밑의 "남은 시간 · 처치 k / 7" 줄)와 **모든 던전의 결과창** (docs/features/dungeons.md "결과창")
var _trial_hud: Label
var _dungeon_result: DungeonResult
## 사냥터·마을에서 쓰러지면 뜨는 사망 창 — 확인 → 마을에서 되살아나기 (death_panel.gd)
var _death_panel: DeathPanel
## 쓰러진 자리 `{zone, x, z}` — 묘비(tomb.gd)를 세운다. **메모리에만 두고 저장하지 않는다**
## (2026-09-30 요청: "묘비는 게임 껐다 켜면 사라지게")
var _tombs: Array[Dictionary] = []
## 헬스 창 — 던전 창과 같은 층(10) · 전체 화면 (fitness_panel.gd)
var _fitness_panel: FitnessPanel
## 장비 도감 창 — 헬스 창과 같은 층(10) · 전체 화면 (codex_panel.gd)
var _codex_panel: CodexPanel
## 강화 창을 도감 [강화] 로 열었나 — 닫으면 도감으로 돌아간다 (`_back_to_codex`)
var _enhance_from_codex := false
var _skill_panel: PanelContainer
## 스킬창. 틀은 한 번 짓고 `_redraw_skills` 가 채운다
var _skill_big: PanelContainer
var _skill_name: Label
var _skill_info: Label
var _skill_state: Label
var _skill_desc: Label
## 스킬창 셋째 칸 — 강화 1번·2번 카드 (`_make_upgrade_card` 가 채우는 사전)
var _upgrade_cards: Array = []
## 스킬 경험치를 넣을 강화 번호 (0 부터). 카드를 눌러 고른다
var _upgrade_slot := 0
## 모아 둔 스킬 경험치를 고른 강화에 넣는 단추 (`feedUpgrade`)
var _feed_button: Button
## "스킬 경험치 12000 — 기절에 넣기"
var _upgrade_hint: Label
var _skill_equip: Button
var _skill_unequip: Button
## 패시브 한 단계를 배우는 단추 (`learnPassive`) — 패시브를 골랐을 때만 선다. 위에 레드닷
var _passive_learn: Button
var _passive_dot: Control
## 보이는 액티브 스킬이 없으면 숨기는 것들 — "장착 중" 줄 · 장착/해제 · 강화 칸 (2026-09-29)
var _active_only: Array = []
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

## **설계 재현 창** — 레벨을 맞추고, 그 레벨에서 설계가 말하는 값(그룹 정리 시간·
## HP 손실·몬스터 수치)을 같이 보여 준다. 장비는 안 건드린다. 설계 문서 9장 5번
var _debug_panel: PanelContainer
var _debug_text: Label
var _debug_level := 100
var _bag_head: Label
var _bag_gold: Label
var _bag_auto: Button
var _bag_sum: Label
var _bag_grid: GridContainer
var _bag_scroll: ScrollContainer
## 가방·스킬 목록을 끌어서 내린다 (`DragScroll`)
var _bag_drag: DragScroll
var _skill_drag: DragScroll
## 패시브 나무 — 칸 목록 `{ id, step, row, column, cell, dot }` (나무 자식 순서와 같다) · 고른 칸의 단계
var _tree_scroll: ScrollContainer
var _tree: Container
var _tree_drag: DragScroll
var _tree_nodes: Array = []
var _tree_job := ""
var _learn_held := false
var _learn_wait := 0.0
var _learn_gap := 0.0
var _bag_action: Button
var _enhance_button: Button  # 상세 창 "강화" — 장비를 고르면 뜨고, 누르면 강화 팝업을 연다
var _lock_button: Button  # 상세 창 "잠금" / "잠금 해제" — 장비를 고르면 뜬다 (`_toggle_lock`)
## 강화 팝업 — 화면 가운데, 뒤를 어둡게 덮는다. 한 개 · 같은 아이템 · 같은 등급, 자동 강화
## → `enhance_popup.gd`
var _enhance: EnhancePopup
## 크리스탈 창 — 크리스탈을 고르고 "사용" 을 누르면 상세 창 자리에 뜬다.
## 떠 있는 동안 장비 칸을 누르면 그 장비가 대상이 된다 (`_crystal_target`)
var _crystal_panel: PanelContainer
# 캐릭터 정보 창 — 오른쪽 위 "정보" 단추로 여는 **따로 뜨는 창**. 묶음마다 이름·값 표 하나
# (`CHAR_SPLIT` + 전투 한 묶음). `_char_last` 는 지난번에 적은 줄 — 같으면 다시 안 짓는다
var _char_panel: PanelContainer
## 랭킹 창 — 서버에 붙었을 때만 메뉴에 단추가 선다 (docs/features/server.md "랭킹")
var _rank_panel: PanelContainer
var _rank_grid: GridContainer
var _rank_note: Label
## 샌드백 랭킹전 (docs/features/sandbag.md) — 입장 창(규칙 · 주간 보상 표 · 이번 주 순위 · 내 기록 · 입장)과
## 화면 가운데 큰 카운트(3 · 2 · 1 · 시작!)
var _sandbag_panel: PanelContainer
var _sandbag_grid: GridContainer
var _sandbag_note: Label
var _sandbag_count: Label
var _char_head: Label
## 캐릭터 정보 창 제목 — "캐릭터 정보" 대신 닉네임을 적는다 (2026-09-30 요청)
var _char_name: Label
var _char_grids: Array = []
var _char_last := ""
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
## 어느 재료로 굴리나 — 2 = 크리스탈(2차), 3 = 옐로우 크리스탈(3차, 2026-10-02). 창 위 단추 둘로 바꾼다
var _crystal_tier := 2
var _crystal_tabs: Array[Button] = []
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
## 착용 중 비교 창 — 가방 칸을 고르면, 같은 부위에 낀 것이 있을 때 상세 창 아래에 뜬다.
## 노드는 `_build_item_view` 가 돌려준 묶음(grade·name·kind·state·icon·info)이다
var _compare_panel: PanelContainer
var _compare_view: Dictionary = {}
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
	_apply_play_mode()
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
			# 회복(물약·회복기)은 맞은 게 아니다 — 움찔 동작을 틀지 않는다
			var healed := bool(payload.get("heal", false))
			if str(payload.get("target_kind", "")) == "player" \
					and str(payload.get("target", "")) == _transport.my_id() and not healed \
					and int(payload.get("amount", 0)) > 0 and not bool(payload.get("killed", false)):
				_start_hit()
			var who := "회복" if healed else "맞음" if payload.get("target_kind", "") == "player" else "피해"
			_last_event = "%s %d%s%s" % [
				who,
				payload.get("amount", 0),
				" 치명타!" if payload.get("crit", false) else "",
				"  처치!" if payload.get("killed", false) else "",
			]
		&"reward":
			_exp_toast.add_exp(int(payload.get("exp", 0)))
		&"levelUp":
			_last_event = "레벨 %d 이 되었습니다" % payload.get("level", 0)
		&"swing":
			# 휘두르는 동안 발이 묶인다는 통보. 그 시간만큼 공격 동작을 튼다
			_swing_until = Time.get_ticks_msec() + int(payload.get("root_ms", 400))
			if str(payload.get("id", "")) == _transport.my_id():
				_swings += 1
				# **공속만큼 빨리 찬다** (2026-09-29 요청: "공속이 빨라지면 그만큼 애니메이션을 빠르게
				# 재생해") — 판정이 실어 보낸 배속(= 기본 간격 / 지금 간격). Lv.200 이면 9배
				var speed := float(payload.get("speed", 1.0))
				_start_move(_kick_clip(int(payload.get("ms", 900))), speed)
		&"lunge":
			# 날라차기 — 나는 동안과 내려앉는 동안 달리기로 끊기지 않게 막는다
			_swing_until = Time.get_ticks_msec() + int(payload.get("ms", 700))
			if str(payload.get("id", "")) == _transport.my_id():
				_start_move(LUNGE_CLIP, float(payload.get("speed", 1.0)))
		&"died":
			_last_event = "쓰러졌습니다 — 확인을 누르면 마을에서 되살아납니다"
			_plant_tomb()
			_target = Vector3.INF
			_holding = false
			_target_mob = ""
			_marker.visible = false
			_gate_panel.visible = false
			_dungeon_panel.visible = false
		&"aoe":
			_show_aoe(payload)
		&"mobSwing":
			# 몬스터가 휘두르기 시작했다 — 피해(`hit`)는 손이 닿는 0.2초 뒤에 따로 온다
			_swing_mob(str(payload.get("id", "")))
		&"skillRange":
			# 판정은 늘 보낸다. 켜 뒀을 때만 그린다
			if _show_range:
				_show_skill_range(payload)
		&"npc":
			_show_npc(payload)
		&"skill":
			# 스킬마다 제 동작이 있다. 없는 스킬(마법사·궁수)은 평타 동작으로 친다
			_swing_until = Time.get_ticks_msec() + int(payload.get("root_ms", 400))
			if str(payload.get("id", "")) == _transport.my_id():
				_start_move(SKILL_CLIPS.get(str(payload.get("skill", "")), SWING_CLIPS[0]))
			# 늦게 떨어지는 스킬(천붕각)은 동작만 먼저 틀고, 이펙트는 판정이 떨어지는 때에 세운다
			var delay := int(payload.get("delay_ms", 0))
			if delay > 0 and not (str(payload.get("skill", "")) in EARLY_FX):
				get_tree().create_timer(delay / 1000.0).timeout.connect(_show_skill.bind(payload))
			else:
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
				# 가방을 보고 있으면 이미 본 것이다 — 닫혀 있을 때만 점을 켠다
				if not _bag_panel.visible:
					_bag_dot.visible = true
			if int(payload.get("crystal", 0)) > 0:
				_chat.add_line("재료 획득", Items.stack_name({"id": Items.crystal_id()}), INV_TEXT)
		&"inventory":
			if _bag_panel.visible:
				_redraw_bag()
			if _npc_panel.visible:
				_npc_panel.redraw()
		&"skillBar":
			if _skill_panel.visible:
				_redraw_skills()
		&"chat":
			_chat.add_chat(str(payload.get("from", "")), str(payload.get("text", "")), bool(payload.get("system", false)))
		&"rank":
			_fill_rank(payload)
		&"sandbagRank":
			_fill_sandbag(payload)
		&"sandbagRecord":
			# 서버에 붙어 있으면 결과창이 먼저 뜨고 최고 기록이 늦게 온다 — 그때 고친다
			if _dungeon_result.visible:
				_dungeon_result.show_sandbag_best(int(payload.get("best", 0)), bool(payload.get("new_best", false)))
		&"sandbagReward":
			_chat.add_line("샌드백 랭킹전", "지난주 %d위 · %s x%d" % [
				int(payload.get("rank", 0)), Items.stack_name({"id": Items.yellow_crystal_id()}),
				int(payload.get("crystals", 0))], INV_GOLD_HI)
		&"notice":
			_last_event = str(payload.get("text", ""))
		&"enhanceResult":
			# 강화 결과는 채팅창에 남긴다 — 부서진 것은 상세 창이 닫혀서 달리 알 길이 없다
			# 자동 강화가 도는 중이면 단계마다 적지 않는다 — 끝날 때 팝업이 한 줄(`finished`)
			var enhanced := "%s +%d" % [str(payload.get("name", "")), int(payload.get("level", 0))]
			if not _enhance.running:
				match str(payload.get("result", "")):
					"success": _chat.add_line("강화 성공", enhanced, INV_GOLD_HI)
					"destroy": _chat.add_line("강화 실패", enhanced + " 파괴", INV_WARN)
					_: _chat.add_line("강화 유지", enhanced, INV_TEXT)
			_enhance.show_result(name, payload)
		&"enhanceBatch":
			# 일괄은 한 줄로 — 수십 개를 줄마다 적으면 채팅창이 강화로 덮인다
			if not _enhance.running:
				_chat.add_line("다중 강화", "%d개 중 성공 %d · 파괴 %d" % [
					int(payload.get("pieces", 0)), int(payload.get("success", 0)), int(payload.get("destroyed", 0))
				], INV_GOLD_HI if int(payload.get("success", 0)) > 0 else INV_WARN)
			_enhance.show_result(name, payload)
		# `gate`(문에 들어섰다)는 창을 열지 않는다 — 창은 문을 눌렀을 때만 뜬다
		# (2026-09-28 요청: "포탈을 클릭 했을 때만 UI가 나오도록")
		&"zone":
			_last_event = "%s 에 도착했습니다" % GameData.zone(str(payload.get("zone", ""))).get("name", "")
			# 창이 열린 채 옮겨 가면 남는다 — 새 존에는 그 NPC 가 없다
			_npc_panel.visible = false
			_dungeon_result.visible = false
		&"fitnessResult":
			_fitness_panel.show_result(payload)
		&"codexResult":
			_codex_panel.show_result(payload)
		&"dungeonResult":
			# 성공이든 실패든 결과창. 걷던 곳·자동 사냥 겨냥을 멈춘다 — 확인을 누르면 마을로 나간다
			# (쓰러졌으면 마을에서 되살아난다 — `_on_result_confirmed`)
			_target = Vector3.INF
			_target_mob = ""
			_marker.visible = false
			_dungeon_result.show_result(payload)
			if _am_dead():
				_last_event = "쓰러졌습니다 — 확인을 누르면 마을에서 되살아납니다"
		&"revived":
			_dungeon_result.visible = false
			_last_event = "마을에서 되살아났습니다"
		&"trialReward":
			_chat.add_line("재료 획득", "%s x%d" % [Items.stack_name({"id": Items.crystal_id()}), int(payload.get("crystal", 0))], INV_TEXT)
			if _bag_panel.visible:
				_redraw_bag()
		&"passives":
			# 글은 뒤따르는 notice 가 적는다. 레드닷은 `_refresh_status` 가 매 프레임 맞춘다
			if _skill_panel.visible:
				_redraw_skills()


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
	_hit_sound = AudioStreamPlayer.new()
	# 공속이 초당 8번까지 오른다 — 한 벌이면 다음 대가 앞 소리를 끊는다
	_hit_sound.max_polyphony = 4
	if ResourceLoader.exists(HIT_SOUND):
		_hit_sound.stream = load(HIT_SOUND)
	add_child(_hit_sound)
	# 저장해 둔 소리 크기를 버스에 건다 — 창을 안 열어도 켤 때부터 그 크기다
	SoundSettings.apply(SoundSettings.volume())
	# 폰 웹에서 손가락 떼기를 놓치면 모든 누름이 죽는다 — 막히면 푼다 (touch_guard.gd)
	_touch_guard = TouchGuard.new()
	add_child(_touch_guard)

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
	# 서버에 붙었을 때만 입력칸이 선다 — 보낸 말은 서버가 방송해서 돌아와야 창에 적힌다
	_chat.set_online(_transport.online())
	_chat.submitted.connect(func(text: String) -> void: _transport.send(&"chat", {"text": text}))
	_chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	_chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat.offset_left = CHAT_MARGIN
	_chat.offset_bottom = -(EXP_GAUGE_H + CHAT_MARGIN)
	_chat.offset_top = _chat.offset_bottom - ChatLog.SIZE.y
	_chat.offset_right = CHAT_MARGIN + ChatLog.SIZE.x

	# 경험치는 채팅창이 아니라 오른쪽 아래, 경험치 띠 바로 위에 잠깐 떴다 사라진다
	# (2026-09-28 요청, 받은 스크린샷의 파란 상자 자리) → hud.md "경험치 알림"
	_exp_toast = ExpToast.new()
	_ui_root.add_child(_exp_toast)
	_exp_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_exp_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_exp_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_exp_toast.offset_right = -CHAT_MARGIN
	_exp_toast.offset_left = _exp_toast.offset_right - ExpToast.WIDTH
	_exp_toast.offset_bottom = -(EXP_GAUGE_H + CHAT_MARGIN)
	_exp_toast.offset_top = _exp_toast.offset_bottom

	_build_gate_panel()
	_build_npc_panel()
	_build_skill_bar()
	_build_skill_panel()
	_build_test_switches()
	_build_bag_panel()
	_build_char_panel()
	_build_rank_panel()
	_build_sandbag_panel()
	_build_potion_panel()
	_build_sound_panel()
	_build_debug_panel()
	_enhance = EnhancePopup.make(self)
	_ui_root.add_child(_enhance)
	_enhance.acted.connect(_on_enhance_acted)
	_enhance.closed.connect(_redraw_bag)
	_enhance.closed.connect(_back_to_codex)
	_enhance.finished.connect(
		func(head: String, text: String, good: bool) -> void:
			_chat.add_line(head, text, INV_GOLD_HI if good else INV_WARN)
	)

	# **모든 창의 닫기는 오른쪽 위 X 하나로 통일한다** (2026-09-20 요청).
	# 창이 다 지어진 뒤에 얹어야 자식 맨 뒤라 창 위에 그려진다
	_close_button(_bag_panel, _toggle_bag, 0)
	_close_button(_gear_panel, _toggle_gear, 0)
	_close_button(_detail_panel, _close_detail, 0)
	# 비교 창 X 는 비교 창만 닫는다 — 고른 것은 그대로 (다른 칸을 고르면 다시 뜬다)
	_close_button(_compare_panel, func() -> void: _compare_panel.visible = false, 0)
	_close_button(_crystal_panel, _close_crystal, 0)
	_close_button(_char_panel, _toggle_char, 0)
	_close_button(_rank_panel, _toggle_rank, 0)
	_close_button(_sandbag_panel, _toggle_sandbag, 0)
	_close_button(_potion_panel, _toggle_potion_panel, 0)
	_close_button(_sound_panel, _toggle_sound_panel, 0)
	_close_button(_npc_panel, func() -> void: _npc_panel.visible = false, 0)


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
## 심볼이 없으면 글자가 대신 나온다. `caption` 이면 아이콘 **아래에** 이름을 늘 얹는다
## (메뉴 단추 — `MENU_CAPTION`). 닫기 X 는 글자를 안 단다
func _icon_button(
	icon_name: String, text: String, on_press: Callable, size: int = MENU_BTN, caption := false
) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(size, size)
	cell.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var inset := MarginContainer.new()
	inset.name = "inset"
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, MENU_INSET)
	# 글자를 달면 아이콘 네모 · 글자를 세로로 쌓는다 — 세로 상자가 글자 줄 높이만큼 칸을 늘여서
	# 둘이 겹칠 수 없다
	var stack: VBoxContainer = null
	if caption:
		stack = VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_theme_constant_override("separation", MENU_CAPTION_GAP)
		cell.add_child(stack)
		inset.custom_minimum_size = Vector2(size, size)
		stack.add_child(inset)
	else:
		cell.add_child(inset)

	var texture := _icon(icon_name)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(rect)
	elif not caption:
		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(label)

	if caption:
		# 아이콘 네모 **아래** 줄 — 흰 글자에 검은 테 (받은 그림이 그렇다, 밤 바닥에서도 읽힌다)
		var name_label := Label.new()
		name_label.name = "caption"
		name_label.text = text
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		name_label.add_theme_font_size_override("font_size", MENU_CAPTION_FONT)
		name_label.add_theme_color_override("font_color", Color("#eeead7"))
		name_label.add_theme_constant_override("outline_size", 5)
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(name_label)

	var hit := Button.new()
	hit.name = "hit"
	hit.flat = true
	hit.tooltip_text = text
	hit.pressed.connect(on_press)
	cell.add_child(hit)
	# 누름은 투명한 hit 이 받고, 움직이는 건 아이콘·글자가 든 칸이다 (`ButtonFx`)
	ButtonFx.attach(hit, cell)
	return cell


## 메뉴 단추 아이콘 네모의 오른쪽 위 모서리에 빨간 점을 단다 — 처음엔 숨겨 둔다.
## 컨테이너 안에서는 자리를 못 잡으니 아이콘 네모(`inset`)를 꽉 채운 빈 `Control` 에 앵커로 붙인다.
## 글자 줄이 아니라 아이콘에 붙여야 그림 모서리에 뜬다. 짙은 테를 둘러 밝은 그림 위에서도 읽힌다
func _add_red_dot(cell: Control) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 아이콘 칸은 그림 판(`inset`)에, 단추는 단추 자체에 붙인다
	var inset := cell.find_child("inset", true, false)
	(inset if inset != null else cell).add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dot := Panel.new()
	dot.name = "red_dot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#e3342b")
	style.border_color = Color("#3a0b08")
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(RED_DOT * 0.5))
	dot.add_theme_stylebox_override("panel", style)
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -RED_DOT
	dot.offset_right = 0
	dot.offset_top = 0
	dot.offset_bottom = RED_DOT
	dot.visible = false
	holder.add_child(dot)
	return dot


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
## 레벨을 맞추고, 지금 입은 장비 그대로의 스탯과 설계가 말하는 값을 나란히 찍는다.
## 수치로만 맞다고 믿었다가 화면이 다른 적이 여러 번이라, **게임 안에서 대조할
## 수단**이 있어야 한다. **장비는 자동으로 입히지 않는다** (2026-09-26 요청) — 예전의
## 등급·강화 단추는 여섯 칸을 풀세트로 갈아입혀서 걷었다
func _build_debug_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(center)

	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	_debug_panel.add_theme_stylebox_override("panel", _frame_box("ui_dungeon_card", GatePanel.CARD_MARGIN, 16))
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


## **열기만 해서는 캐릭터를 건드리지 않는다** (2026-09-26 요청: "버튼 누른다고 세팅을
## 바꾸지 마"). 예전에는 여는 순간 `debugGear` 를 보내 100레벨·4등급 풀세트로 갈아입혔다.
## 열 때는 레벨 칸을 지금 레벨에 맞추고 값만 찍는다 — 레벨 단추를 눌러야 바뀐다
func _toggle_debug() -> void:
	_debug_panel.visible = not _debug_panel.visible
	if _debug_panel.visible:
		var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
		_debug_level = int(me.get("level", _debug_level))
		_refresh_debug()


## 레벨만 맞추고 다시 찍는다 — 레벨 단추만 부른다. 장비는 안 건드린다
func _apply_debug() -> void:
	_transport.send(&"debugLevel", {"level": _debug_level})
	_refresh_debug()


## 같은 레벨 몬스터가 때릴 때 들어오는 비율 — `Stats.damage_taken` 과 같은 K
func _taken_share(level: int, defense: float) -> float:
	var k := Stats.def_k_of(level)
	return k / (k + maxf(0.0, defense))


## 지금 캐릭터 스탯과 설계가 말하는 값을 함께 찍는다 (캐릭터는 안 바꾼다)
func _refresh_debug() -> void:
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
		Stats.damage_taken(float(mon["atk"]), level, float(stats.get("defense", 1)))
		* float(Stats.melee_attackers(level)) * clear / float(mon["interval"])
	)
	var loss := taken / maxf(1.0, float(stats.get("maxHp", 1)))

	_debug_text.text = "\n".join([
		"Lv%d   (사냥터 %d, 기준 등급 %.2f, 기준 강화 %d단)" % [
			level, Stats.field_of(level), Stats.ref_grade(level), Stats.enh_ref_step(level)
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
## │ 스탯 상자   │                 │ 등급 ...  ││ 소지품 3/200      │
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

	# 상세 창은 **내용 높이만** 쓴다 (2026-09-25 요청: "크기를 좀 줄여") — 위에 붙인다
	_detail_panel = _window_panel()
	_detail_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_detail_panel)
	_build_detail_window(_detail_panel)

	# 크리스탈 창은 상세 창과 **같은 자리**에 번갈아 뜬다
	_crystal_panel = _window_panel()
	row.add_child(_crystal_panel)
	_build_crystal_window(_crystal_panel)

	_bag_panel = _window_panel()
	row.add_child(_bag_panel)
	_build_bag_window(_bag_panel)
	_build_compare_layer()


## 창 하나의 틀 — **던전 창 결이다.** 던전 카드 틀(`ui_dungeon_card`)을 9조각으로 깐다.
## 2026-09-28 에 가방 창("가방 UI도 던전 UI 아트풍으로"), 이어서 나머지 창("나머지 창들도")을
## 이리로 옮겼다 — 그 전엔 인벤토리 결 창 바탕(`inv_panel`). 안쪽 판이 가장자리에서 26~36px
## 들어가 있어 내용은 `STONE_PAD` 만큼 물린다. 조각이 없으면 같은 색으로 그린 판
func _window_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.add_theme_stylebox_override(
		"panel",
		_inv_box("ui_dungeon_card", DungeonPanel.CARD_MARGIN, STONE_PAD, "#1b1c17", "#4a3f30")
	)
	return panel


## 던전 창 제목 — 왼쪽에 문장(메뉴 아이콘), 상아빛 글자, 밑에 가는 선 (`DungeonPanel._restyle_title`)
func _stone_title(parent: Node, text: String, size: int, emblem_name: String) -> Label:
	var title := _window_title(parent, text, size)
	title.add_theme_color_override("font_color", DungeonPanel.PAGE_TITLE_COLOR)
	var emblem := TextureRect.new()
	emblem.name = "Emblem"
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.texture = _icon(emblem_name)
	emblem.custom_minimum_size = Vector2(STONE_EMBLEM, STONE_EMBLEM)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.visible = emblem.texture != null
	title.get_parent().add_child(emblem)
	title.get_parent().move_child(emblem, 0)
	var line := ColorRect.new()
	line.color = GatePanel.HEAD_LINE
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	return title


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

	var title := _stone_title(side, "장비", 26, "ui_icon_character")
	_bag_level = _inv_label("", 20, INV_TEXT)
	_bag_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.get_parent().add_child(_bag_level)
	title.get_parent().move_child(_bag_level, title.get_index() + 1)

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
	box.add_theme_stylebox_override("panel", _stone_cell_box(12))
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


## 캐릭터 정보 창 — 가방 창들과 따로 뜬다 (2026-09-25 요청: "상세 정보창을 따로 띄우고
## 버튼을 만들어"). 처음엔 장비 창 "상세" 로 상세 창 자리를 번갈아 썼다.
## **채팅창 자리(왼쪽 아래)에 채팅창을 덮고 뜬다** (2026-09-28 요청: "채팅창 위에 나오도록").
## 그 전엔 화면 가운데였다. 창(627px)이 채팅창 윗자리(506px)에 안 들어가서, 왼쪽·아래 끝을
## 채팅창에 맞추고 위로 자라게 했다. 판은 인벤토리 결(`_window_panel`) 그대로다
func _build_char_panel() -> void:
	# 받침은 여닫을 때 `move_to_front` 로 채팅창보다 뒤(= 위에 그려지는) 자식이 되게 하는 몫이다
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(holder)
	_char_panel = _window_panel()
	holder.add_child(_char_panel)
	_build_char_window(_char_panel)
	_char_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	_char_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_char_panel.offset_left = _chat.offset_left
	_char_panel.offset_bottom = _chat.offset_bottom
	_char_panel.offset_top = _chat.offset_bottom
	_char_panel.offset_right = _chat.offset_left


## 캐릭터 정보 창 — 상세 창과 같은 틀(머리 줄 · 가는 줄 · 이름/값 표).
## 묶음 제목은 달지 않는다 — 줄 이름에 "공격력" 이 이미 있고, 달면 창이 782px 로 화면(720)을 넘는다.
## 공격력·방어력·체력은 **기본 → 증가 % → 최종** 세 줄로 푼다 (2026-09-25 요청:
## "기본 공격력 / 공격력 증가 % / 최종 공격력 이렇게 디테일하게")
func _build_char_window(panel: PanelContainer) -> void:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(DETAIL_W, 0)
	# 5 — "평타" 줄(2026-09-30)에 8 → 7, 증가 풀이 줄 셋(2026-10-02)에 7 → 5 (창이 화면 위로 넘쳤다)
	side.add_theme_constant_override("separation", 5)
	panel.add_child(side)

	var title := _stone_title(side, "", 22, "ui_icon_character")
	_char_name = title
	_char_head = _inv_label("", 20, INV_TEXT)
	_char_head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.get_parent().add_child(_char_head)
	title.get_parent().move_child(_char_head, title.get_index() + 1)

	_char_grids.clear()
	for index in CHAR_SPLIT.size() + 1:
		var rule := ColorRect.new()
		rule.color = INV_RULE
		rule.custom_minimum_size = Vector2(0, 1)
		side.add_child(rule)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		# 2 — "아이템 드랍률" 줄(2026-10-01)에 6 → 4, 증가 풀이 줄 셋(2026-10-02)에 4 → 2 (화면 위로 48px 넘쳤다)
		grid.add_theme_constant_override("v_separation", 2)
		side.add_child(grid)
		_char_grids.append(grid)

	var room := Control.new()
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(room)
	# 아래 끝의 "최종 = 기본 × (1 + 증가 %)" 안내 줄은 뺐다 (2026-10-02) — 증가 줄 아래 풀이
	# `(장비 × 헬스 × 도감)` 가 같은 것을 보여 주고, 그 줄 셋 때문에 창이 화면 위로 넘쳤다


## 착용 중 비교 창 — **상세 창 바로 왼쪽에 같은 높이로** 나란히 뜬다 (2026-09-25 요청:
## "장착중인 장비가 있으면 장착중인 아이템도 상세 정보창 띄워서 비교할 수 있게").
##
## 나란히 두어야 줄끼리 맞대어 읽힌다. 그런데 1280 폭에 장비·상세·인벤토리가 이미
## 거의 다 차서(378 + 276 + 428) 한 줄에 넣을 자리가 없다 — 위아래로 쌓으면 옵션 많은
## 장비(8줄)에서 670 을 넘는다. 그래서 **위에 한 줄 더 깔고 장비 창 오른쪽을 덮는다.**
## 줄은 가방 창과 같은 틀(양 끝 여백 · 세로 가운데)이라 자리는 컨테이너가 잡는다:
##   [빈칸(늘어남)][비교 창][상세 + 틈 + 인벤토리 폭만큼 빈 자리]
## 빈 자리의 크기는 두 창이 바뀔 때마다 따라간다 (`resized`)
func _build_compare_layer() -> void:
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
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_compare_panel = _window_panel()
	_compare_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_compare_panel)
	_compare_view = _build_item_view(_compare_panel)

	# 상세 창 + 틈 + 인벤토리 자리. 높이도 인벤토리와 같아야 줄이 같은 높이에 선다
	var room := Control.new()
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(room)
	var fit := func() -> void:
		room.custom_minimum_size = Vector2(
			_detail_panel.size.x + WINDOW_GAP + _bag_panel.size.x, _bag_panel.size.y
		)
	_detail_panel.resized.connect(fit)
	_bag_panel.resized.connect(fit)
	# 상세 창이 지면 비교 창도 진다 (빈칸 · X · 가방 닫기 · 크리스탈 창)
	_detail_panel.visibility_changed.connect(func() -> void:
		if not _detail_panel.is_visible_in_tree():
			_compare_panel.visible = false
	)


## 상세 창 — 받은 그림의 왼쪽 창. 등급 · 이름 · 종류 · 큰 칸 · 아이템 정보 · 단추
func _build_detail_window(panel: PanelContainer) -> void:
	var view := _build_item_view(panel)
	_detail_grade = view.grade
	_detail_name = view.name
	_detail_kind = view.kind
	_detail_state = view.state
	_detail_icon = view.icon
	_detail_info = view.info
	var side: VBoxContainer = view.side

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	# 단추 셋(76 × 3)이 상세 창 폭(`ITEM_W` 240)에 꼭 맞도록 간격은 6
	buttons.add_theme_constant_override("separation", 6)
	side.add_child(buttons)
	_lock_button = _inv_button("잠금", _toggle_lock)
	_lock_button.name = "LockButton"
	_lock_button.visible = false
	buttons.add_child(_lock_button)
	_enhance_button = _inv_button("강화", _open_enhance)
	_enhance_button.visible = false
	buttons.add_child(_enhance_button)
	_bag_action = _inv_button("-", _on_bag_action)
	buttons.add_child(_bag_action)


## 아이템 한 벌을 보여 주는 틀 — 등급(머리 줄) · 이름 · 종류 · 상태 · 큰 칸 · 아이템 정보 표.
## 상세 창과 착용 중 비교 창이 같이 쓴다 — **두 창이 같은 모양이라야 줄을 맞대어 비교된다.**
## 단추는 상세 창만 단다. 글자·칸은 `ITEM_*` 로 작게 (2026-09-25 요청)
func _build_item_view(panel: PanelContainer) -> Dictionary:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(ITEM_W, 0)
	side.add_theme_constant_override("separation", 6)
	panel.add_child(side)

	var grade := _window_title(side, "", 17)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	side.add_child(head)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 2)
	head.add_child(lines)
	var title := _inv_label("", 18, INV_GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(title)
	var kind := _inv_label("", ITEM_FONT, INV_DIM)
	lines.add_child(kind)
	var state := _inv_label("", ITEM_FONT, INV_GOLD)
	lines.add_child(state)
	var icon := _make_cell(func() -> void: pass, ITEM_ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# 강화는 큰 칸 오른쪽 아래 `+9` 로만 보인다 — 정보 표의 강화 줄은 뺐다 (2026-09-23 요청)
	icon.get_node("badge").add_theme_font_size_override("font_size", 18)
	head.add_child(icon)

	# "아이템 정보" — 제목 아래에 가는 줄 한 가닥
	side.add_child(_inv_label("아이템 정보", 16, INV_GOLD))
	var rule := ColorRect.new()
	rule.color = INV_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	side.add_child(rule)

	# 이름 · 값 두 줄짜리 표. 값은 오른쪽에 붙인다 (받은 그림대로)
	var info := GridContainer.new()
	info.columns = 2
	info.add_theme_constant_override("h_separation", 10)
	info.add_theme_constant_override("v_separation", 3)
	# 표 글자 크기 — `_fill_detail_rows` 가 읽는다 (다른 창의 표는 17 그대로)
	info.set_meta("font", ITEM_FONT)
	side.add_child(info)
	return {"side": side, "grade": grade, "name": title, "kind": kind, "state": state, "icon": icon, "info": info}


## 크리스탈 창 — 상세 창과 같은 틀이다: 머리 줄 · 대상 이름과 큰 칸 · 옵션 표 · 아래 단추.
## 대상은 **장비·인벤토리 창의 칸을 눌러** 고른다 (창 안에 격자를 또 두지 않는다)
func _build_crystal_window(panel: PanelContainer) -> void:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(DETAIL_W, 0)
	side.add_theme_constant_override("separation", 8)
	panel.add_child(side)

	_stone_title(side, "크리스탈 강화", 22, "ui_icon_crystal")

	# 재료 고르기 — 크리스탈(2차) · 옐로우 크리스탈(3차). 가방에서 "사용" 을 누르면 그 재료로 열린다
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	side.add_child(tabs)
	_crystal_tabs.clear()
	for tier in [2, 3]:
		var tab := _inv_button(
			"크리스탈" if tier == 2 else "옐로우", func() -> void: _pick_crystal_tier(tier)
		)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.set_meta("tier", tier)
		tabs.add_child(tab)
		_crystal_tabs.append(tab)

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


## 인벤토리 창 — 머리 줄 · 격자와 오른쪽 세로 탭 · 소지품 수와 정렬 · 동전
func _build_bag_window(panel: PanelContainer) -> void:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	panel.add_child(side)

	_stone_title(side, "인벤토리", 26, "ui_icon_bag")

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
	_bag_scroll = scroll
	_bag_grid = GridContainer.new()
	_bag_grid.columns = BAG_COLUMNS
	_bag_grid.add_theme_constant_override("h_separation", BAG_GRID_GAP)
	_bag_grid.add_theme_constant_override("v_separation", BAG_GRID_GAP)
	scroll.add_child(_bag_grid)
	# **끌어서 내린다** — 칸 단추가 끌기를 먹었다 (`DragScroll`)
	_bag_drag = DragScroll.attach(scroll, _bag_grid, BAG_GRID_GAP)

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

	# 소지품 수 — 장비·정렬 단추는 뺐다 (2026-09-30 요청). 정렬은 창을 열 때마다 저절로 하고,
	# 장비 창은 인벤토리와 같이 열린다
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	side.add_child(foot)
	_add_icon(foot, "bag", 28)
	_bag_head = _inv_label("", 18, INV_TEXT)
	_bag_head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bag_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_bag_head)
	# 자동 장착 (2026-10-02 요청) — 부위마다 전투력이 가장 높아지는 것을 장부가 고른다
	_bag_auto = _inv_button("자동장착", _on_auto_equip)
	_bag_auto.name = "AutoEquip"
	foot.add_child(_bag_auto)

	var coins := HBoxContainer.new()
	coins.add_theme_constant_override("separation", 8)
	side.add_child(coins)
	_add_icon(coins, "gold", 28)
	_bag_gold = _inv_label("", 18, INV_GOLD)
	_bag_gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coins.add_child(_bag_gold)


## 창 안의 작은 단추 (장착·강화·물약 ±·자동사냥 위/아래 …) — 던전 창의 입장 단추처럼
## **청록 돌판 단추 조각(`ui_button`) + 주황빛 금 글자** (2026-09-29, 그 전엔 둥근 금테).
## 조각은 83px 높이라 40px 단추에 여백 28 로 늘이면 모서리가 겹친다. 그래서 **조각을 단추
## 높이로 한 번 줄여**(`_small_button_texture`) 좌우 끝을 그대로 쓴다
func _inv_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = INV_BUTTON
	button.pressed.connect(on_press)
	var texture := _small_button_texture()
	for state in ["normal", "hover", "pressed", "disabled"]:
		if texture == null:
			button.add_theme_stylebox_override(state, _inv_box("ui_button", 28, 6, "#45605d", "#1a1e1e"))
			continue
		var box := StyleBoxTexture.new()
		box.texture = texture
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			box.set_texture_margin(side, texture.get_height() / 2.0)
		box.set_content_margin_all(6)
		button.add_theme_stylebox_override(state, box)
	return _gold_text(button, 18)


## `ui_button` 을 가방 단추 높이(`INV_BUTTON.y`)로 비율 그대로 줄인 것. 한 번만 만든다.
## 조각은 무손실 임포트(`compress/mode=0`)라 웹에서도 `get_image` 가 된다
var _small_button: Texture2D
func _small_button_texture() -> Texture2D:
	if _small_button != null:
		return _small_button
	var source := _icon("ui_button")
	if source == null:
		return null
	var image := source.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	var height := int(INV_BUTTON.y)
	image.resize(roundi(image.get_width() * height / float(image.get_height())), height, Image.INTERPOLATE_LANCZOS)
	_small_button = ImageTexture.create_from_image(image)
	return _small_button


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
	ButtonFx.attach(button)
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
	# 던전 단계 창의 보상 칸과 같은 평판 (2026-09-28 — 가방을 던전 결로)
	cell.add_theme_stylebox_override("panel", _stone_cell_box(BAG_CELL_PAD))

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
	# 칸 높이를 다 받아야 BOTTOM 이 먹는다 — 안 주면 글자 높이로 가운데에 떠서 오른쪽
	# **가운데**에 찍혔고, 고른 칸의 "장착" 과 붙어 "장착3" 으로 읽혔다 (2026-09-26)
	badge.size_flags_vertical = Control.SIZE_FILL
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
	# 칸을 **꽉 덮어야** 한다. 안 주면 글자 높이(27px)만큼 가운데 띠로 깔려 그림 위쪽을
	# 가리고 강화 배지(+3)와 겹쳤다 (2026-09-26, 찍어서 봤다)
	act.size_flags_vertical = Control.SIZE_FILL
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(act)

	# 잠근 장비 — 왼쪽 위에 "잠금" (`Items.is_locked`). 강화 배지(오른쪽 아래)와 안 겹친다
	var lock := Label.new()
	lock.name = "lock"
	lock.visible = false
	lock.text = "잠금"
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lock.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lock.size_flags_vertical = Control.SIZE_FILL
	lock.add_theme_font_size_override("font_size", 13)
	lock.add_theme_color_override("font_color", INV_GOLD_HI)
	lock.add_theme_color_override("font_outline_color", Color.BLACK)
	lock.add_theme_constant_override("outline_size", 4)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(lock)

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
	var lock: Label = cell.get_node_or_null("lock")
	if lock != null:
		lock.visible = Items.is_locked(stack)
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
	_enhance.hide_now()
	_enhance_from_codex = false
	_bag_panel.visible = open
	_gear_panel.visible = open
	_bag_pick = {}
	_detail_panel.visible = false
	_crystal_panel.visible = false
	_char_panel.visible = false
	_crystal_target = {}
	_bag_drag.forget()
	if open:
		_bag_dot.visible = false
		# 열 때마다 정렬한다 (희귀도 → 장비 종류 → 강화, 2026-09-29 요청) — 강화 창을 닫고 고른
		# 칸도 비운 뒤라 가방 번호가 바뀌어도 붙잡고 있던 것이 없다. 열려 있는 동안 들어온
		# 드롭은 끝에 붙는다 — 강화 창이 가방 번호로 대상을 붙잡고 있어서 그때 섞으면 엉뚱한 걸 두드린다
		_transport.send(&"sortBag", {})
		_redraw_bag()


## 장비 창만 여닫는다 (자기 X). 다시 열려면 인벤토리를 다시 연다 — "장비" 단추는 뺐다
func _toggle_gear() -> void:
	_gear_panel.visible = not _gear_panel.visible
	if _gear_panel.visible:
		_redraw_bag()


## 오른쪽 위 "정보" · 캐릭터 정보 창 X — 여닫는다. **가방 창들과는 번갈아 뜬다** —
## 가운데 창이 상세 창 자리(인벤토리 왼쪽)를 덮기 때문이다. 가방·크리스탈 단추도 이 창을 닫는다
## --- 랭킹 (docs/features/server.md "랭킹") ---

## 랭킹 창 — 정보 창과 같은 틀(창 바탕 · 머리 줄 · 가는 줄 · 표). 값은 서버가 준 그대로 적는다
func _build_rank_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(center)
	_rank_panel = _window_panel()
	center.add_child(_rank_panel)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(DETAIL_W, 0)
	side.add_theme_constant_override("separation", 8)
	_rank_panel.add_child(side)
	_stone_title(side, "랭킹", 22, "ui_icon_rank")
	var rule := ColorRect.new()
	rule.color = INV_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	side.add_child(rule)

	# 줄이 많으면 창 안에서 굴린다 — 위 50명이 다 온다
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, RANK_LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	DragScroll.top_on_open(scroll)
	_rank_grid = GridContainer.new()
	_rank_grid.columns = 4
	_rank_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rank_grid.add_theme_constant_override("h_separation", 16)
	_rank_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_rank_grid)

	var foot := ColorRect.new()
	foot.color = INV_RULE
	foot.custom_minimum_size = Vector2(0, 1)
	side.add_child(foot)
	_rank_note = _inv_label("", 18, INV_TEXT)
	side.add_child(_rank_note)


func _toggle_rank() -> void:
	var open := not _rank_panel.visible
	_rank_panel.visible = open
	if open:
		_rank_panel.get_parent().move_to_front()
		# 열 때마다 새로 묻는다 — 순위는 남이 사냥하는 동안에도 바뀐다
		_rank_note.text = "불러오는 중…"
		_transport.send(&"rank", {})


## 서버의 답 `{top: [{rank, name, level, exp}], me: {rank, level, exp}, total}` 으로 표를 다시 짓는다.
## 1~3위는 밝은 금빛, **내 줄**은 청록(채팅창 경험치 색)으로 칠한다. 경험치는 그 레벨의 % 로 적는다
func _fill_rank(board: Dictionary) -> void:
	for child in _rank_grid.get_children():
		child.queue_free()
	for head in ["순위", "이름", "레벨", "경험치"]:
		_rank_grid.add_child(_inv_label(head, 16, INV_DIM))
	var me: Dictionary = board.get("me", {})
	for row in board.get("top", []):
		var rank := int(row.get("rank", 0))
		var tint := INV_TEXT
		if rank == int(me.get("rank", -1)):
			tint = ChatLog.EXP
		elif rank <= 3:
			tint = INV_GOLD_HI
		_rank_grid.add_child(_inv_label("%d" % rank, 18, tint))
		_rank_grid.add_child(_inv_label(str(row.get("name", "")), 18, tint))
		_rank_grid.add_child(_inv_label("Lv.%d" % int(row.get("level", 1)), 18, tint))
		_rank_grid.add_child(_inv_label(_rank_exp(int(row.get("level", 1)), int(row.get("exp", 0))), 18, tint))
	if me.is_empty():
		_rank_note.text = "아직 순위가 없습니다"
	else:
		_rank_note.text = "내 순위  %d위 / %d명 · Lv.%d %s" % [
			int(me.rank), int(board.get("total", 0)), int(me.level), _rank_exp(int(me.level), int(me.exp))]


static func _rank_exp(level: int, exp_now: int) -> String:
	var need := Combat.exp_to_next(level)
	return "%.1f%%" % (100.0 * exp_now / need) if need > 0 else "-"


## --- 샌드백 랭킹전 (docs/features/sandbag.md) ---

## 입장 창 — **전체 화면**(2026-10-02 요청 "UI를 전체 화면으로"). 헬스·도감 창과 같은 층(`GateLayer`)·같은 결
## (돌판 틀 `ui_dungeon_card` + 뒤에 불투명한 판). 왼쪽 칸은 제목 · 설명 한 줄 · 주간 보상 표 · 내 기록 · 입장,
## 오른쪽은 이번 주 순위(**100위까지 굴린다** — `LedgerServer.SANDBAG_RANK_TOP`). 화면 가운데 큰 카운트 글자도 여기서 단다
func _build_sandbag_panel() -> void:
	var top: CanvasLayer = get_node("GateLayer")
	_sandbag_panel = PanelContainer.new()
	_sandbag_panel.name = "SandbagPanel"
	_sandbag_panel.visible = false
	_sandbag_panel.theme = _ui_root.theme
	_sandbag_panel.add_theme_stylebox_override("panel", _frame_box.call("ui_dungeon_card", GatePanel.CARD_MARGIN, 30))
	_sandbag_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 틀 가장자리가 반투명이라 화면 끝에 게임이 비친다 — 헬스·도감 창처럼 뒤에 판을 한 장 깐다
	var back := ColorRect.new()
	back.name = "SandbagBack"
	back.color = DungeonPanel.CARD_DARK
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.visible = false
	top.add_child(back)
	_sandbag_panel.visibility_changed.connect(func(): back.visible = _sandbag_panel.visible)
	top.add_child(_sandbag_panel)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	_sandbag_panel.add_child(body)

	# --- 왼쪽 — 제목 · 설명 · 보상 · 내 기록 · 입장 ---
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(480, 0)
	side.add_theme_constant_override("separation", 10)
	body.add_child(side)
	_stone_title(side, "샌드백 랭킹전", 26, "ui_icon_sandbag")
	# 설명은 한 줄만 (2026-10-02 요청 "15초 동안 샌드백에 넣은 피해를 겨룹니다. 이것만 적어")
	var rule_text := _inv_label("%d초 동안 샌드백에 넣은 피해를 겨룹니다." % (Sandbag.play_ms() / 1000), 18, INV_DIM)
	rule_text.name = "SandbagRule"
	rule_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(rule_text)
	var line := ColorRect.new()
	line.color = GatePanel.HEAD_LINE
	line.custom_minimum_size = Vector2(0, 1)
	side.add_child(line)

	# 주간 보상 — **한 줄에 한 순위**(2026-10-02 요청 "1열 2행으로 만들지 말고, 1열 1행으로").
	# 개수 앞에 옐로우 크리스탈 그림(`yellow_crystal`, 가방 칸과 같은 그림)
	side.add_child(_inv_label("주간 보상 — %s" % Items.stack_name({"id": Items.yellow_crystal_id()}), 20, INV_GOLD))
	var rewards := GridContainer.new()
	rewards.name = "SandbagRewards"
	rewards.columns = 2
	rewards.add_theme_constant_override("h_separation", 18)
	rewards.add_theme_constant_override("v_separation", 4)
	side.add_child(rewards)
	var crystal := _icon(Items.yellow_crystal_id())
	for row in Sandbag.table().get("rewards", []):
		var head := _inv_label(Sandbag.reward_label(row), 18, INV_TEXT)
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rewards.add_child(head)
		var prize := HBoxContainer.new()
		prize.add_theme_constant_override("separation", 6)
		if crystal != null:
			var gem := TextureRect.new()
			gem.name = "SandbagRewardIcon"
			gem.texture = crystal
			gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			gem.custom_minimum_size = Vector2(SANDBAG_GEM, SANDBAG_GEM)
			gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
			prize.add_child(gem)
		var count := _inv_label("x%d" % int(row.yellowCrystals), 18, INV_GOLD_HI)
		count.custom_minimum_size = Vector2(44, 0)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		prize.add_child(count)
		rewards.add_child(prize)

	var room := Control.new()
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(room)
	# 내 기록 글자와 입장을 **한 줄에** — 단추는 글자 오른쪽, 세로 가운데 (2026-10-02 요청
	# "입장 버튼이 너무 작아 … 텍스트 옆에 줄 맞춰서"). 단추는 던전 창 입장과 같은 조각·같은 크기
	var foot := HBoxContainer.new()
	foot.name = "SandbagFoot"
	foot.add_theme_constant_override("separation", 16)
	side.add_child(foot)
	_sandbag_note = _inv_label("", 18, INV_TEXT)
	_sandbag_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sandbag_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sandbag_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_sandbag_note)
	var enter := GatePanel.paint_button_text(Button.new(), 28)
	enter.name = "SandbagEnter"
	enter.text = "입장"
	enter.custom_minimum_size = DungeonPanel.ENTER_SIZE
	enter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	enter.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "disabled", "focus", "pressed", "hover_pressed"]:
		var pressed: bool = state.ends_with("pressed")
		var box: StyleBox = _frame_box("ui_button", GatePanel.BUTTON_MARGIN, 12)
		box.content_margin_top = 12 + (GatePanel.ROW_SINK if pressed else 0)
		box.content_margin_bottom = 12 - (GatePanel.ROW_SINK if pressed else 0)
		if box is StyleBoxTexture:
			(box as StyleBoxTexture).modulate_color = GatePanel.PRESS_TINT if pressed else Color.WHITE
		enter.add_theme_stylebox_override(state, box)
	enter.pressed.connect(_on_sandbag_enter)
	foot.add_child(enter)

	var split := ColorRect.new()
	split.color = GatePanel.HEAD_LINE
	split.custom_minimum_size = Vector2(1, 0)
	body.add_child(split)

	# --- 오른쪽 — 이번 주 순위 (끌어 굴린다) ---
	var board := VBoxContainer.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.add_theme_constant_override("separation", 8)
	body.add_child(board)
	board.add_child(_inv_label("이번 주 순위", 22, INV_GOLD))
	var scroll := ScrollContainer.new()
	scroll.name = "SandbagScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board.add_child(scroll)
	_sandbag_grid = GridContainer.new()
	_sandbag_grid.columns = 3
	_sandbag_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sandbag_grid.add_theme_constant_override("h_separation", 40)
	_sandbag_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_sandbag_grid)
	# 휠·손가락 둘 다 굴린다 — 엔진의 끌기는 터치 화면에서만 켜진다 (가방 격자와 같다)
	DragScroll.attach(scroll, _sandbag_grid, 8)

	# 화면 가운데 큰 카운트 — 판이 도는 동안만 (`_draw_sandbag_hud`)
	_sandbag_count = Label.new()
	_sandbag_count.name = "sandbag_count"
	_sandbag_count.add_theme_font_size_override("font_size", 140)
	_sandbag_count.add_theme_color_override("font_color", GatePanel.CARD_GOLD)
	_sandbag_count.add_theme_color_override("font_outline_color", GatePanel.BUTTON_OUTLINE)
	_sandbag_count.add_theme_constant_override("outline_size", 14)
	_sandbag_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sandbag_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sandbag_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sandbag_count.visible = false
	_ui_root.add_child(_sandbag_count)
	_sandbag_count.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_sandbag_count.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sandbag_count.grow_vertical = Control.GROW_DIRECTION_BOTH


## HUD 단추 — 창을 열 때마다 순위를 새로 묻는다 (남이 치는 동안에도 바뀐다)
func _toggle_sandbag() -> void:
	var open := not _sandbag_panel.visible
	# 같은 층의 전체 화면 창들(차원문 · 던전 · 헬스 · 도감)은 닫는다 — 겹쳐 열려 있으면 닫기 X 가 엉킨다
	if open:
		_gate_panel.visible = false
		_dungeon_panel.visible = false
		_fitness_panel.visible = false
		if _codex_panel.visible:
			_codex_panel.close_panel()
	_sandbag_panel.visible = open
	if open:
		_sandbag_note.text = "불러오는 중…"
		_transport.send(&"sandbagRank", {})


## 입장 — 차원문 창에서 고른 것과 같은 `travel` (World 가 다시 본다). 이미 샌드백 존이면 막는다
func _on_sandbag_enter() -> void:
	if _shown_zone == Sandbag.zone():
		return
	_sandbag_panel.visible = false
	_on_gate_pick(Sandbag.zone())


## 답 `{top: [{rank, name, best}], me: {rank, best}, total, ends_at, local?}` 으로 표를 다시 짓는다.
## 1~3위는 밝은 금빛, 내 줄은 청록 — 레벨 랭킹 창(`_fill_rank`)과 같다
func _fill_sandbag(board: Dictionary) -> void:
	for child in _sandbag_grid.get_children():
		child.queue_free()
	for head in ["순위", "이름", "최고 피해"]:
		_sandbag_grid.add_child(_inv_label(head, 18, INV_DIM))
	var me: Dictionary = board.get("me", {})
	for row in board.get("top", []):
		var rank := int(row.get("rank", 0))
		var tint := INV_TEXT
		if rank == int(me.get("rank", -1)):
			tint = ChatLog.EXP
		elif rank <= 3:
			tint = INV_GOLD_HI
		_sandbag_grid.add_child(_inv_label("%d" % rank, 20, tint))
		_sandbag_grid.add_child(_inv_label(str(row.get("name", "")), 20, tint))
		_sandbag_grid.add_child(_inv_label(DungeonResult.comma(int(row.get("best", 0))), 20, tint))
	var left := maxf(0.0, float(board.get("ends_at", 0.0)) - Time.get_unix_time_from_system())
	var until := "정산까지 %d일 %d시간" % [int(left / 86400.0), int(fmod(left, 86400.0) / 3600.0)]
	if int(me.get("rank", 0)) <= 0:
		_sandbag_note.text = "이번 주 기록 없음\n%s" % until
	else:
		_sandbag_note.text = "내 기록 %s · %d위 / %d명\n%s" % [
			DungeonResult.comma(int(me.best)), int(me.rank), int(board.get("total", 0)), until]


## 판이 도는 동안 — 카운트 중엔 가운데 큰 숫자(3 · 2 · 1), 재기 시작하면 "시작!" 을 잠깐, 시계 줄엔 남은 시간 · 누적 피해
func _draw_sandbag_hud(run: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var going := str(run.get("result", "")) == ""
	var starts := int(run.get("starts_at", 0))
	_trial_hud.visible = going
	_sandbag_count.visible = going and now < starts + 700
	if not going:
		return
	if now < starts:
		_sandbag_count.text = "%d" % ceili((starts - now) / 1000.0)
		_trial_hud.text = "곧 시작합니다"
		return
	_sandbag_count.text = "시작!"
	var left := maxi(0, int(run.get("ends_at", 0)) - now)
	_trial_hud.text = "남은 시간 %d초   누적 피해 %s" % [ceili(left / 1000.0), DungeonResult.comma(int(run.get("damage", 0)))]


func _toggle_char() -> void:
	var open := not _char_panel.visible
	if open and _bag_panel.visible:
		_toggle_bag()
	_char_panel.visible = open
	if open:
		_char_panel.get_parent().move_to_front()
		_char_last = ""
		_redraw_char(_me())


## 캐릭터 정보 — 값은 판정(`world.gd` `_refresh_stats`)이 내려준 그대로 적는다.
## 기본(`base_*`)은 레벨 맨몸 값, 증가(`gear_*`)는 장비 % 합계, 헬스(`fitness_*`)는 헬스 %,
## 도감(`codex_*`)은 도감 %, 최종은 넷을 곱한 판정 값이다.
## 화면이 공식을 다시 돌리지 않는다 — 돌리면 반올림이 어긋나 최종이 1 씩 틀려 보인다
## **`_refresh_status` 가 매 프레임 부른다** — 레벨업·장비가 가방을 닫은 채로도 바로 보인다.
## 줄 글자가 지난번과 같으면 표를 다시 짓지 않는다
func _redraw_char(me: Dictionary) -> void:
	if not _char_panel.visible or me.is_empty():
		return
	var stats: Dictionary = me.get("stats", {})
	var groups: Array = []
	for key in CHAR_SPLIT:
		var name := str(DETAIL_BONUS[key])
		var final := int(stats.get(key, 0))
		# 공격력 증가는 장비 % 에 패시브 철각(+30%)을 더한 합이다 — 최종이 그 합으로 곱해진다
		var gear := float(stats.get("gear_" + key, 0.0)) + float(stats.get("passive_" + key, 0.0)) * 100.0
		var fit := float(stats.get("fitness_" + key, 0.0))
		var book := float(stats.get("codex_" + key, 0.0))
		# 증가 줄은 **세 몫을 곱한 합계 %** 하나 — 헬스(fitness.md)·도감(codex.md)은 장비 % 에 더하지 않고
		# 따로 곱한다. 몫은 그 아래 풀이 줄에 `(장비 × 헬스 × 도감)` 으로 적는다 (2026-10-02 요청:
		# "헬스가 따로 텍스트로 표시 되는데 이렇게 하지마"). 도감은 0.01% 단위라 소수 둘째 자리까지
		var total := ((1.0 + gear / 100.0) * (1.0 + fit / 100.0) * (1.0 + book / 100.0) - 1.0) * 100.0
		var group: Array = [
			["기본 " + name, "%d" % int(stats.get("base_" + key, final))],
			[name + " 증가", _bonus_text(key, total), INV_GOLD_HI if total > 0.0 else INV_DIM],
		]
		# 풀이 줄에는 **0% 인 몫을 적지 않는다** (2026-10-02 요청 "0%일 경우에는 표시하지 마") — 적힐 글자로
		# 가린다(0.004% 가 "0%" 로 찍히지 않게). 셋 다 0 이면 풀이 줄을 넣지 않는다
		var parts := PackedStringArray()
		var gear_text := _bonus_text(key, gear).trim_prefix("+")
		if gear_text != "0%":
			parts.append("장비 " + gear_text)
		if int(fit) != 0:
			parts.append("헬스 %d%%" % int(fit))
		var book_text := ("%.2f" % book).rstrip("0").rstrip(".")
		if book_text != "0":
			parts.append("도감 %s%%" % book_text)
		if not parts.is_empty():
			group.append(["(%s)" % " × ".join(parts), "", INV_DIM, "note"])
		group.append(["최종 " + name, "%d" % final, INV_GOLD_HI])
		groups.append(group)
	# 나머지는 맨몸 값이 없거나(0) 고정(치명타 피해 100%)이라 합계 한 줄씩이다
	groups.append([
		["치명타", "%.0f%%" % (float(stats.get("crit", 0.0)) * 100.0)],
		["치명타 피해", "%.0f%%" % (float(stats.get("critDamage", 1.0)) * 100.0)],
		["공격 속도", "+%.0f%%" % (float(stats.get("attackSpeed", 0.0)) * 100.0)],
		# 공속을 실제 평타 횟수로 (2026-09-30 요청: "초당 7.5회 공격 이런식으로") — 판정과 같은
		# `effective_cooldown` 으로 센다. 질풍각 설명(`_show_passive`)과 같은 계산이다
		["평타", "초당 %.1f회 공격" % _attacks_per_second(stats)],
		["쿨타임 감소", "%.0f%%" % (float(stats.get("cooldown", 0.0)) * 100.0)],
		["방어력 관통", "%.0f%%" % (float(stats.get("penetration", 0.0)) * 100.0)],
		["아이템 드랍률", "+%.0f%%" % (float(stats.get("dropRate", 0.0)) * 100.0)],
		# 같은 레벨 몬스터에게 맞을 때 원래 피해의 몇 % 가 들어오나 (2026-09-27). 후반 감소율이
		# 90% 대라 "감소율 94 → 95%" 는 1%p 로 보여도 받는 피해는 17% 준다 — 그래서 이쪽을 보인다
		["받는 피해", "%.1f%%" % (_taken_share(int(me.get("level", 1)), float(stats.get("defense", 0))) * 100.0)],
	])
	var head := "LV. %d" % int(me.get("level", 1))
	var nick := str(me.get("name", ""))
	var seen := nick + head + str(groups)
	if seen == _char_last:
		return
	_char_last = seen
	_char_name.text = nick
	_char_head.text = head
	for index in groups.size():
		_fill_detail_rows(groups[index], _char_grids[index])


## 초당 평타 횟수 — 판정(`world.gd`)이 다음 평타를 `effective_cooldown` 뒤로 미는 것과 같은 값
func _attacks_per_second(stats: Dictionary) -> float:
	return 1000.0 / Combat.effective_cooldown(
		float(stats.get("attackCooldown", 900)), float(stats.get("attackSpeed", 0.0)))


func _close_detail() -> void:
	_bag_pick = {}
	_show_bag_detail()


## 오른쪽 위 "크리스탈" — 인벤토리·장비 창과 크리스탈 창을 같이 연다. 대상은 두 창의 장비
## 칸을 눌러 고른다 (가방에서 크리스탈 "사용" 을 누른 것과 같은 상태). 다시 누르면 셋 다 닫는다
func _toggle_crystal() -> void:
	var open := not _crystal_panel.visible
	_enhance.hide_now()
	_enhance_from_codex = false
	_bag_panel.visible = open
	_gear_panel.visible = open
	_bag_pick = {}
	_detail_panel.visible = false
	_crystal_panel.visible = open
	_char_panel.visible = false
	_crystal_target = {}
	if open:
		_transport.send(&"sortBag", {})  # 가방 창을 여는 것과 같다 (`_toggle_bag`)
		_redraw_bag()


## 크리스탈 창 X — 상세 창으로 돌아가지 않고 둘 다 닫는다 (칸을 다시 누르면 상세가 뜬다)
func _close_crystal() -> void:
	_crystal_panel.visible = false
	_crystal_target = {}
	_bag_pick = {}
	_show_bag_detail()


## 자동 장착 — 가방 번호가 바뀌니 정렬처럼 고른 칸을 비운다 (`Ledger.auto_equip`)
func _on_auto_equip() -> void:
	_bag_pick = {}
	_crystal_target = {}
	_transport.send(&"autoEquip", {})
	_show_bag_detail()
	_redraw_bag()


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
		# 던전 단계 창의 단계 줄과 같다 — 고른 것만 옅은 금빛 바탕 + 왼쪽 금 막대, 줄마다 아래 선
		var box := _stone_tab_box(on)
		for state in ["normal", "hover", "pressed"]:
			tab.add_theme_stylebox_override(state, box)
		tab.add_theme_color_override("font_color", DungeonPanel.CARD_GOLD if on else INV_DIM)
		tab.add_theme_color_override("font_hover_color", DungeonPanel.CARD_GOLD if on else INV_TEXT)

	# 장착 — 아이콘 이름은 슬롯 이름과 같다 (assets/icons/weapon.png …)
	var slots: Array = Items.slots()
	for index in _gear_cells.size():
		var slot := str(slots[index])
		var worn: Dictionary = equipped.get(slot, {})
		_fill_cell(
			_gear_cells[index], worn, Items.slot_label(slot, job),
			slot if worn.is_empty() else _item_icon(worn)
		)

	# 스탯 여섯 — **장착한 장비가 올려 주는 몫만** 적는다 (2026-09-28 요청). 맨몸 값·최종 값은
	# 캐릭터 정보 창(`_redraw_char`)이 풀어 적는다. 값은 판정이 내려준 `gear_*` 그대로다
	var stats: Dictionary = me.get("stats", {})
	var shown := []
	for index in STAT_NAMES.size():
		var key := str(["attack", "defense", "maxHp", "crit", "critDamage", "attackSpeed"][index])
		var gear := float(stats.get("gear_" + key, 0.0))
		# 치명타 피해만 `_bonus_text` 의 비율 목록에 없다 — 같은 모양(+N%)으로 ×100 해 적는다
		var text := _bonus_text("crit" if key == "critDamage" else key, gear)
		shown.append("%s %s" % [STAT_NAMES[index], text])
	# **0% 인 줄은 숨긴다** (같은 날 요청) — 격자가 숨은 칸을 건너뛰어 남은 줄이 앞으로 당겨진다.
	# 하나도 안 남으면(맨몸) 빈 판이 남지 않게 상자째 숨긴다
	var any := false
	for index in _stat_labels.size():
		var label: Label = _stat_labels[index]
		label.text = str(shown[index])
		label.visible = not label.text.ends_with(" +0%")
		any = any or label.visible
	if not _stat_labels.is_empty():
		_stat_labels[0].get_parent().get_parent().visible = any

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
	_lock_button.visible = _enhance_button.visible
	if stack.is_empty():
		_detail_panel.visible = false
		_bag_action.text = "-"
		_bag_action.disabled = true
		_show_cell_action()
		return
	_detail_panel.visible = _bag_panel.visible
	_compare_panel.visible = false
	if Items.is_material(str(stack.get("id", ""))):
		_show_material_detail(stack)
		return

	var item := Items.get_item(str(stack.get("id", "")))
	var enhance := int(stack.get("enhance", 0))
	var worn := str(_bag_pick.get("where", "")) == "equip"
	# **낄 수 있는지 판정과 같은 식으로 미리 본다** — 테스트 창·옛 저장은 레벨이 모자란
	# 장비를 끼워 주는데, 한 번 벗으면 판정이 다시 끼기를 거부한다. 그때 "장착" 이 켜져
	# 있으면 눌러도 아무 일이 없어 보인다 (2026-09-23)
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	var level := int(me.get("level", 1))
	var fits := worn or Items.can_equip(item, str(me.get("job", "")), level)
	_fill_item_view({
		"grade": _detail_grade, "name": _detail_name, "kind": _detail_kind,
		"state": _detail_state, "icon": _detail_icon, "info": _detail_info,
	}, stack, worn, fits)

	# 가방 칸이면 **같은 부위에 낀 것**을 아래 비교 창에 띄운다 (2026-09-25 요청:
	# "장착중인 장비가 있으면 장착중인 아이템도 상세 정보창 띄워서 비교할 수 있게")
	var equipped: Dictionary = me.get("equipped", {}).get(str(item.get("slot", "")), {})
	_compare_panel.visible = not worn and not equipped.is_empty()
	if _compare_panel.visible:
		_fill_item_view(_compare_view, equipped, true, true)

	# 성공률·실패 시 파괴는 **강화 팝업**에 적는다 (2026-09-23 요청 "강화 ui창을 따로 만들어")
	var can := Items.can_enhance(enhance)
	_enhance_button.text = "강화" if can else "최대"
	# 잠근 장비는 강화 팝업을 열지 않는다 — 판정(`Ledger.enhance`)도 거절한다
	var locked := Items.is_locked(stack)
	_enhance_button.disabled = not can or locked
	_lock_button.text = "잠금 해제" if locked else "잠금"
	_fit_button_text(_lock_button, 18)

	if fits:
		_bag_action.text = "해제" if worn else "장착"
	else:
		_bag_action.text = "레벨 부족" if level < int(item.get("level", 1)) else "착용 불가"
	_bag_action.disabled = not fits
	_show_cell_action()


## 장비 한 벌을 틀(`_build_item_view` 묶음)에 채운다 — 등급 · 이름 +강화 · 부위와 착용 레벨
## (못 끼면 붉게) · 착용 중/보유 중 · 큰 칸 · 아이템 정보(능력치 · 차수별 옵션).
## 상세 창과 비교 창이 같이 쓴다 — 줄 순서가 같아야 맞대어 읽힌다
func _fill_item_view(view: Dictionary, stack: Dictionary, worn: bool, fits: bool) -> void:
	var item := Items.get_item(str(stack.get("id", "")))
	var grade := int(stack.get("grade", 1))
	var enhance := int(stack.get("enhance", 0))
	var tint := _grade_tint(grade)
	var grade_label: Label = view.grade
	grade_label.text = Items.grade_name(grade)
	grade_label.add_theme_color_override("font_color", tint)
	var title: Label = view.name
	title.text = str(item.get("name", stack.get("id", "?")))
	if enhance > 0:
		title.text += " +%d" % enhance
	title.add_theme_color_override("font_color", tint)
	var kind: Label = view.kind
	kind.text = "%s · 착용 Lv.%d" % [Items.slot_label(str(item.get("slot", ""))), int(item.get("level", 1))]
	kind.add_theme_color_override("font_color", INV_DIM if fits else INV_WARN)
	var state: Label = view.state
	state.text = "착용 중" if worn else "보유 중"
	if Items.is_locked(stack):
		state.text += " · 잠금"
	_fill_cell(view.icon, stack, "", _item_icon(stack))

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
		var lines: Array = Items.shown_options(stack.get(str(tier.key), []))
		for option in lines:
			rows.append([head, Items.describe_option(option)])
		if lines.is_empty():
			match str(tier.get("source", "")):
				"crystal": rows.append([head, "크리스탈로 붙임"])
				"drop": pass
				_: rows.append([head, "비어 있음"])
	_fill_detail_rows(rows, view.info)


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
	var font := int(grid.get_meta("font", 17))
	for row in rows:
		# 풀이 줄(`"note"`) — 작은 글자로 왼쪽 칸에서 **오른쪽 칸까지 넘쳐** 그린다. 칸에 그대로 넣으면
		# 글자 폭만큼 왼쪽 칸이 넓어져 창이 커진다 — 폭 0 인 틀에 얹어 칸 폭을 건드리지 않는다
		if row.size() > 3 and str(row[3]) == "note":
			var note := _inv_label(str(row[0]), font - 4, row[2])
			var holder := Control.new()
			holder.custom_minimum_size = Vector2(0, note.get_minimum_size().y)
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(note)
			grid.add_child(holder)
			grid.add_child(Control.new())
			continue
		var key_label := _inv_label(str(row[0]), font, INV_DIM)
		key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(key_label)
		var tint: Color = row[2] if row.size() > 2 else INV_TEXT
		var value_label := _inv_label(str(row[1]), font, tint)
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
	_fill_detail_rows([
		["보유 수량", "%d" % int(stack.get("count", 1))],
		["쓰임", "%d차 옵션 굴리기" % maxi(2, Items.material_tier(str(stack.get("id", ""))))],
	])
	# "사용" 을 누르면 크리스탈 창이 뜬다 (2026-09-23 요청)
	_bag_action.text = "사용"
	_bag_action.disabled = int(stack.get("count", 1)) <= 0
	_show_cell_action()


## 가방에 든 크리스탈 수 — 고른 재료(`_crystal_tier`)의 것
func _crystal_count() -> int:
	var material := Items.tier_material(_crystal_tier)
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	for stack in me.get("bag", []):
		if str(stack.get("id", "")) == material:
			return int(stack.get("count", 1))
	return 0


## 크리스탈 창 위 단추 — 재료를 바꾼다. 대상은 그대로 둔다 (같은 장비에 2차·3차를 번갈아 굴릴 수 있다)
func _pick_crystal_tier(tier: int) -> void:
	_crystal_tier = tier
	_redraw_crystal()


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
	var material_name := str(Items.get_material(Items.tier_material(_crystal_tier)).get("name", "크리스탈"))
	_crystal_have.text = "보유 %s x%d" % [material_name, crystals]
	# 고른 재료 단추만 밝게 — 나머지는 어둡게 눌러 둔다
	for tab in _crystal_tabs:
		tab.modulate = Color.WHITE if int(tab.get_meta("tier")) == _crystal_tier else Color(1, 1, 1, 0.45)
	var stack := _stack_at(_crystal_target)
	var item := Items.get_item(str(stack.get("id", "")))
	if item.is_empty():
		_crystal_target = {}
		_crystal_name.text = "대상 없음"
		_crystal_name.add_theme_color_override("font_color", INV_DIM)
		_crystal_kind.text = ""
		_fill_cell(_crystal_icon, {}, "", "")
		_fill_detail_rows([], _crystal_info)
		_crystal_hint.text = "장비나 인벤토리에서 장비 칸을 누르세요.\n%d차 옵션 1줄을 새로 굴립니다." % _crystal_tier
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
		var tint := INV_GOLD_HI if int(tier.tier) == _crystal_tier else INV_TEXT
		var lines: Array = Items.shown_options(stack.get(str(tier.key), []))
		for option in lines:
			rows.append([head, Items.describe_option(option), tint])
		if lines.is_empty() and str(tier.get("source", "")) != "drop":
			rows.append([head, "비어 있음", INV_DIM])
	_fill_detail_rows(rows, _crystal_info)
	var rolled: Array = stack.get(str(Items.option_tier(_crystal_tier).get("key", "options2")), [])
	_crystal_hint.text = ("굴리면 %d차 옵션이 새로 바뀝니다." if not rolled.is_empty() \
		else "굴리면 %d차 옵션 1줄이 붙습니다.") % _crystal_tier
	_crystal_roll.disabled = crystals <= 0


## 크리스탈 쓰기. **대상은 그대로 둔다** — 결과를 보고 또 굴릴지 정해야 한다.
## 마지막 크리스탈을 쓰면 그 칸이 빠져 **뒤쪽 가방 번호가 하나씩 당겨지므로** 대상 번호도 맞춘다
func _on_crystal_roll() -> void:
	var stack := _stack_at(_crystal_target)
	if Items.get_item(str(stack.get("id", ""))).is_empty():
		return
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	var bag: Array = me.get("bag", [])
	var material := Items.tier_material(_crystal_tier)
	var crystal_at := -1
	for index in bag.size():
		if str(bag[index].get("id", "")) == material:
			crystal_at = index
			break
	if crystal_at < 0:
		return
	var last := int(bag[crystal_at].get("count", 1)) <= 1

	var index := int(_crystal_target.index)
	if str(_crystal_target.where) == "equip":
		_transport.send(&"useCrystal", {"where": "equip", "key": str(Items.slots()[index]), "tier": _crystal_tier})
	else:
		_transport.send(&"useCrystal", {"where": "bag", "key": index, "tier": _crystal_tier})
		if last and crystal_at < index:
			_crystal_target.index = index - 1
	_redraw_bag()


## 상세 창 능력치 줄에 적는 기본 능력치 (옵션은 따로 적는다)
const DETAIL_BONUS := {
	"attack": "공격력", "defense": "방어력", "maxHp": "체력",
	"crit": "치명타", "attackSpeed": "공격 속도",
}


## 장비 기본 능력치는 **전부 %** 다 — 공격력·방어력·체력도 맨몸 수치에 곱한다
## (`world.gd` `_refresh_stats`). 소수점은 **올림** (2026-09-24 지시). 치명타·공속만
## 비율(0.05)로 들고 있어 ×100 한다. 부동소수 찌꺼기(30.0000001)가 31 로 올라가지 않게 조금 뺀다
func _bonus_text(key: String, value: float) -> String:
	var percent := value * 100.0 if key in ["crit", "attackSpeed"] else value
	return "+%d%%" % ceili(percent - 0.0001)


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
	# 크리스탈 "사용" — 상세 창 자리에 크리스탈 창을 띄운다. 대상은 칸을 눌러 고른다
	if Items.is_material(str(stack.get("id", ""))):
		_crystal_tier = maxi(2, Items.material_tier(str(stack.get("id", ""))))
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


## 상세 창 "잠금" — 고른 장비의 잠금을 뒤집는다 (`Ledger.toggle_lock`). 잠근 것은 판매 · 강화 ·
## 도감 등록을 못 한다. 가방 번호는 그대로라 고른 칸도 그대로 둔다
func _toggle_lock() -> void:
	if Items.get_item(str(_picked_stack().get("id", ""))).is_empty():
		return
	var worn := str(_bag_pick.get("where", "")) == "equip"
	_transport.send(&"toggleLock", {
		"where": "equip" if worn else "bag",
		"key": str(Items.slots()[int(_bag_pick.index)]) if worn else _picked_bag_index(),
	})
	_redraw_bag()


## 상세 창 "강화" — 고른 장비로 강화 팝업을 연다. 대상은 **가방 번호**로 잡는다
## (칸 번호는 탭으로 거르면 어긋난다 — 크리스탈 대상과 같다)
func _open_enhance() -> void:
	if Items.get_item(str(_picked_stack().get("id", ""))).is_empty():
		return
	_enhance_from_codex = false
	var worn := str(_bag_pick.get("where", "")) == "equip"
	_enhance.open({
		"where": "equip" if worn else "bag",
		"index": int(_bag_pick.index) if worn else _picked_bag_index(),
	})


## 오른쪽 위 "강화" — 대상 없이 강화 팝업을 연다. **"단일 강화" · "전체" 목록**으로 열고
## 장비부터 고르게 한다 — 고르기 전에는 다른 탭이 잠겨 있다 (2026-09-28. 그 전엔 다중 · 전체로 열었다)
func _toggle_enhance() -> void:
	if _enhance.visible:
		_enhance.close()
		return
	_enhance_from_codex = false
	_enhance.open({})


## 도감 [강화] — 그 칸을 채울 장비(가방 번호 `index`)를 고르고 **목표를 그 칸의 강화 단계로** 잡은 단일 강화 창을 띄운다
## (2026-10-02 요청). 강화 창은 도감 창(층 10) 아래 층이라 도감을 잠시 감추고, X 로 닫으면 도감으로 돌아온다
func _open_enhance_from_codex(index: int, goal: int) -> void:
	_codex_panel.close_panel()
	_enhance_from_codex = true
	_bag_pick = {}
	_enhance.open({"where": "bag", "index": index})
	_enhance.set_goal(goal)


## 강화 창을 X 로 닫았다 — 도감에서 열었으면 도감을 다시 연다 (고른 칸·탭은 그대로다)
func _back_to_codex() -> void:
	if not _enhance_from_codex:
		return
	_enhance_from_codex = false
	_codex_panel.refresh(_me())
	_codex_panel.open()


## 강화 팝업이 한 개를 두드린 뒤 — **고른 칸은 결과를 따라간다.** 부서졌거나 일괄로 가방이
## 흔들렸으면 비우고(안 비우면 다음 물건을 가리킨다), 겹친 칸에서 뗀 것이 오르면 한 칸 뒤로
func _on_enhance_acted(kept: bool, shift: int) -> void:
	if not kept:
		_bag_pick = {}
	elif shift != 0 and not _bag_pick.is_empty():
		_bag_pick.index = int(_bag_pick.index) + shift
	_redraw_bag()



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
	for option in Items.shown_options(stack.get("options", []) + stack.get("options2", [])):
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
	_build_potion_cell(dock)
	for slot in int(GameData.combat().get("skillBarSize", 4)):
		var cell := _make_skill_cell(QUICK_CELL, "ui_quick_slot", _on_bar_pressed.bind(slot), QUICK_MARGIN)
		cell.find_child("key", true, false).text = str(slot + 1)
		# **보이는 액티브 스킬이 없으면 숨긴다** (2026-09-29 요청: "퀵슬롯 … 숨김 처리해") —
		# 격투가는 평타만 쓴다. 스킬 표의 `hidden` 을 풀면 칸이 곧바로 돌아온다
		cell.visible = Skills.actives_shown(World.DEFAULT_JOB)
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

	# 경험치 띠 위로 한 뼘 띄운다 — 16 으로 두었더니 칸 아래가 띠에 가렸다 (2026-09-26 요청)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, EXP_GAUGE_H + 8)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# ≡ 를 누르면 펼쳐지는 판 — 평소 줄보다 **먼저** 단다 (줄이 판 위에 얹혀 그대로 보인다)
	_build_menu_sheet()
	var menu := HBoxContainer.new()
	menu.name = "MenuBar"
	menu.add_theme_constant_override("separation", 6)
	_ui_root.add_child(menu)
	_menu_bar = menu

	# 오른쪽 위 메뉴. 2026-09-19 에 글자를 뺐다가 **2026-09-28 에 다시 아래에 달았다** —
	# 그림만으로는 무엇인지 헷갈린다는 요청 ("이런식으로 텍스트 넣도록"). 그림도 같은 날
	# 받은 그림(리니지풍 칠한 아이콘)대로 일곱 장 전부 갈았다 (docs/features/hud.md "메뉴 아이콘")
	var bag_cell := _icon_button("ui_icon_bag", "가방", _toggle_bag, MENU_BTN, true)
	var skill_cell := _icon_button("ui_icon_skill", "스킬", _toggle_skills, MENU_BTN, true)
	_menu_cells = [
		# 캐릭터 정보 — 스킬 왼쪽, 메뉴 맨 앞 (2026-09-25 요청 "상세 정보창을 따로 띄우고
		# 버튼을 만들어"). 그림은 기사 투구
		_icon_button("ui_icon_character", "정보", _toggle_char, MENU_BTN, true),
		skill_cell,
		# 강화 — 가방 왼쪽 옆 (2026-09-24 요청 "가방 ui 옆에 강화 ui 버튼 만들어").
		# 오른쪽 옆은 던전 자리다. 그림은 모루를 내리치는 망치
		_icon_button("ui_icon_enhance", "강화", _toggle_enhance, MENU_BTN, true),
		# 크리스탈 강화 — 가방 바로 왼쪽 (2026-09-24 요청 "크리스탈 사용해서 강화하는 ui도 따로
		# 버튼을 만들고 싶어. 가방 옆에"). 오른쪽 옆은 던전이라 강화를 한 칸 밀었다
		_icon_button("ui_icon_crystal", "크리스탈", _toggle_crystal, MENU_BTN, true),
		bag_cell,
		# 던전 — 가방 바로 옆 (2026-09-23 요청)
		_icon_button("ui_icon_dungeon", "던전", _toggle_dungeon, MENU_BTN, true),
		# 헬스 — 던전 옆 (2026-09-30). 던전에서 받은 프로틴을 넣는 곳이라 붙여 둔다. 그림은 쇠 덤벨
		_icon_button("ui_icon_fitness", "헬스", _toggle_fitness, MENU_BTN, true),
		# 장비 도감 — 헬스 옆 (2026-10-01). 그림은 펼친 책(`ui_icon_codex`) — 없으면 이름 글자만 선다
		_icon_button("ui_icon_codex", "도감", _toggle_codex, MENU_BTN, true),
		# 샌드백 랭킹전 — 도감 옆 (2026-10-02 요청 "HUD 별도 단추"). 그림은 받침에 선 가죽 샌드백
		_icon_button("ui_icon_sandbag", "샌드백", _toggle_sandbag, MENU_BTN, true),
	]
	# 랭킹 — 던전 옆. **서버에 붙었을 때만** 선다 (혼자 노는 판에는 견줄 사람이 없다).
	# 그림은 월계관 두른 금 트로피(`ui_icon_rank`)
	if _transport.online():
		_menu_cells.append(_icon_button("ui_icon_rank", "랭킹", _toggle_rank, MENU_BTN, true))
	# 설정 — 메뉴 맨 끝 (2026-09-30 요청 "볼륨 조절 하는 기능 추가해"). 지금은 소리 크기만 있다.
	# 그림(`ui_icon_settings`)은 아직 없어서 이름 글자만 선다
	_menu_cells.append(_icon_button("ui_icon_settings", "설정", _toggle_sound_panel, MENU_BTN, true))
	# 평소 줄엔 `MENU_QUICK` 넷만, 나머지는 펼친 판의 격자로 (2026-10-01 요청 그림)
	for cell in _menu_cells:
		var hit: Button = cell.get_node("hit")
		if hit.tooltip_text in MENU_QUICK:
			menu.add_child(cell)
		else:
			_menu_grid.add_child(cell)
			# 판 안 단추를 누르면 그 창이 열리고 판은 접힌다
			hit.pressed.connect(_close_menu)
	# 줄 맨 오른쪽 ≡ — 누르면 판이 펼쳐지고 그 자리에 X 가 선다. 글자 줄이 없어 아이콘 높이(위)에 맞춘다
	_menu_open_cell = _icon_button("ui_icon_menu", "메뉴", _toggle_menu, MENU_BTN)
	_menu_open_cell.name = "MenuOpen"
	_menu_close_cell = _icon_button("ui_icon_menu_close", "닫기", _toggle_menu, MENU_BTN)
	_menu_close_cell.name = "MenuClose"
	for each: Control in [_menu_open_cell, _menu_close_cell]:
		each.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		menu.add_child(each)
	_menu_close_cell.visible = false
	# 판 맨 위는 평소 줄이 얹히는 자리 — 줄 크기를 그대로 따라간다
	var room: Control = _menu_sheet.find_child("bar_room", true, false)
	room.custom_minimum_size = menu.get_combined_minimum_size()
	menu.resized.connect(func() -> void: room.custom_minimum_size = menu.size)
	_bag_dot = _add_red_dot(bag_cell)
	# 배울 수 있는 패시브 단계가 있으면 켠다 — `_refresh_status` 가 매 프레임 맞춘다 (2026-09-29 요청)
	_skill_dot = _add_red_dot(skill_cell)
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# 마을가기 — **위쪽 가운데** (2026-09-29 요청: "사냥터에 들어가면 포탈을 제거해. HUD 윗 부분에
	# 마을가기 버튼을 만들어서 마을 갈 수 있는 기능 만들어"). 사냥터에 차원문이 없어져서 나오는 길이
	# 이것뿐이다. 왼쪽 위는 상태 글자 줄, 오른쪽 위는 메뉴라 가운데가 비어 있다.
	# 단추 조각(`ui_button`) + 글자 — 그림이 없으면 `_frame_box` 가 코드로 그린 판을 준다
	_home_button = _make_button("마을가기", _go_village)
	_home_button.name = "home"
	_home_button.custom_minimum_size = HOME_BUTTON_SIZE
	_home_button.focus_mode = Control.FOCUS_NONE
	_home_button.add_theme_font_size_override("font_size", 20)
	_ui_root.add_child(_home_button)
	_home_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 20)
	_home_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_refresh_home_button()

	# 시련의 탑 시계 — 마을가기 바로 밑. 도는 동안만 보인다 (`_draw_trial_hud`)
	_trial_hud = Label.new()
	_trial_hud.name = "trial_hud"
	_trial_hud.add_theme_font_size_override("font_size", 26)
	_trial_hud.add_theme_color_override("font_color", GatePanel.CARD_GOLD)
	_trial_hud.add_theme_color_override("font_outline_color", GatePanel.BUTTON_OUTLINE)
	_trial_hud.add_theme_constant_override("outline_size", 6)
	_trial_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trial_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_hud.visible = false
	_ui_root.add_child(_trial_hud)
	_trial_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 20)
	_trial_hud.offset_top = 20 + HOME_BUTTON_SIZE.y + 10
	_trial_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# 설계(치트 목록) — 메뉴에서 빼서 **화면 오른쪽 맨 아래 모서리**에 숨겨 둔다 (2026-09-28 요청:
	# "설계 버튼을 오른쪽 맨 아래로 위치 변경하고, 아이콘이랑 텍스트 안 보이게 알파0으로").
	# `modulate` 알파 0 이라 그림·글자는 안 보이지만 누름(hit)은 그대로 받는다
	_design_cell = _icon_button("ui_icon_design", "설계", _toggle_debug, MENU_BTN, true)
	_design_cell.name = "design"
	_design_cell.modulate.a = 0.0
	_ui_root.add_child(_design_cell)
	_design_cell.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_design_cell.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_design_cell.grow_vertical = Control.GROW_DIRECTION_BEGIN


## 물약 칸 — **퀵슬롯 왼쪽** (2026-09-26 요청: 처음엔 오른쪽 옆이었다가 "물약을 퀵슬롯 왼쪽에 두고").
## 누르면 마시고, 오른쪽 위 "설정" 으로 저절로 마실 HP % 를 고른다. 쿨타임은 스킬 칸과 같은
## 어둠·바늘로 돈다 (`_refresh_potion`). 퀵슬롯과 `AUTO_GAP` 만큼 띄운다 — 붙이면 다섯 번째
## 스킬 칸으로 보인다 (자동사냥 칸에서 받은 지적과 같다)
func _build_potion_cell(dock: HBoxContainer) -> void:
	_potion_cell = _make_skill_cell(QUICK_CELL, "ui_quick_slot", _drink_potion, QUICK_MARGIN)
	_potion_cell.name = "potion"
	var potion_icon: TextureRect = _potion_cell.find_child("icon", true, false)
	potion_icon.texture = _icon("ui_icon_potion")
	# 그림을 안 받은 사람에게는 글자로 나온다
	if potion_icon.texture == null:
		_potion_cell.find_child("text", true, false).text = "물약"
	# 칸의 누름(hit)보다 **뒤에** 얹어야 이 단추가 먼저 눌린다
	_potion_cell.add_child(_cell_setting("potion_setting", _toggle_potion_panel))
	dock.add_child(_potion_cell)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(AUTO_GAP, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(gap)


## 칸 오른쪽 위 작은 "설정" 단추 — 물약 칸·자동사냥 칸. 칸의 누름(hit)보다 **뒤에**
## 얹어야 이 단추가 먼저 눌린다
func _cell_setting(name: String, on_press: Callable) -> Button:
	var setting := Button.new()
	setting.name = name
	setting.text = "설정"
	setting.add_theme_font_size_override("font_size", 10)
	setting.add_theme_constant_override("outline_size", 4)
	setting.add_theme_color_override("font_outline_color", Color.BLACK)
	setting.add_theme_color_override("font_color", INV_GOLD_HI)
	setting.size_flags_horizontal = Control.SIZE_SHRINK_END
	setting.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0.55)
		box.border_color = Color(INV_GOLD, 0.8)
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		box.set_content_margin_all(2)
		setting.add_theme_stylebox_override(state, box)
	setting.pressed.connect(on_press)
	ButtonFx.attach(setting)
	return setting


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
		# 퀵슬롯·자동사냥·물약 칸 — 칸째 줄었다 튄다 (`ButtonFx`)
		ButtonFx.attach(hit, cell)
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
	var texture := _icon("skill_" + Skills.icon_of(id)) if id != "" else null
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
	# **던전 창과 같은 결이다** (2026-09-28 요청: "스킬 UI도 던전 UI와 비슷한 아트풍으로").
	# 전체 화면 · 닳은 돌판 틀(`ui_dungeon_card`) · 왼쪽 위 문장 + 상아빛 제목 · 제목 밑 선.
	# 틀 가장자리가 반투명이라 던전 창처럼 뒤에 불투명한 판을 깐다 (`DungeonBack` 과 같은 까닭)
	var holder := Control.new()
	holder.name = "SkillLayer"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(holder)
	var back := ColorRect.new()
	back.name = "SkillBack"
	back.color = DungeonPanel.CARD_DARK
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.visible = false
	holder.add_child(back)

	_skill_panel = PanelContainer.new()
	_skill_panel.visible = false
	_skill_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_skill_panel.add_theme_stylebox_override(
		"panel", _frame_box("ui_dungeon_card", DungeonPanel.CARD_MARGIN, DungeonPanel.PAGE_PAD)
	)
	_skill_panel.visibility_changed.connect(func(): back.visible = _skill_panel.visible)
	holder.add_child(_skill_panel)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_skill_panel.add_child(page)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	page.add_child(head)
	var emblem := TextureRect.new()
	emblem.name = "Emblem"
	emblem.texture = _icon("ui_icon_skill")
	emblem.custom_minimum_size = Vector2(DungeonPanel.EMBLEM, DungeonPanel.EMBLEM)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.visible = emblem.texture != null
	head.add_child(emblem)
	var title := Label.new()
	title.text = "스킬"
	title.add_theme_font_size_override("font_size", DungeonPanel.PAGE_TITLE_SIZE)
	title.add_theme_color_override("font_color", DungeonPanel.PAGE_TITLE_COLOR)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _icon_button("ui_close", "X", _toggle_skills, CLOSE_BTN)
	close.name = "close"
	head.add_child(close)
	var line := ColorRect.new()
	line.color = GatePanel.HEAD_LINE
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(line)

	# 세 칸은 가운데에 모은다 — 화면이 넓어도 칸이 벌어지지 않게
	var middle := CenterContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(middle)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	middle.add_child(columns)

	# 왼쪽 — 설명
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	# 8 — 설명을 두 줄 기준으로 잡으면 왼쪽 칸이 창에서 가장 길어져, 12 로는 720 을 11px 넘었다
	# (그 전에도 두 줄 설명을 고르면 넘었다 — 731px)
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)

	_skill_big = _make_skill_cell(150, "ui_slot", Callable())
	left.add_child(_skill_big)

	_skill_name = Label.new()
	_skill_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skill_name.add_theme_font_size_override("font_size", 30)
	_skill_name.add_theme_color_override("font_color", DungeonPanel.PAGE_TITLE_COLOR)
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
	_sub_box(left, true).add_child(_skill_desc)
	# 트리에 붙은 뒤에 재야 테마 글꼴(`_make_theme`)로 잰다
	# 줄 간격은 줄 사이에만 들어간다 — N줄이면 N-1번
	var spacing := _skill_desc.get_theme_constant("line_spacing")
	var desc_h := (_skill_desc.get_theme_font("font").get_height(20) + spacing) * SKILL_DESC_LINES - spacing
	_skill_desc.custom_minimum_size = Vector2(340, ceilf(desc_h))

	# 오른쪽 — 고르기와 장착/해제
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)

	var equip_caption := _caption("장착 중")
	right.add_child(equip_caption)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", SKILL_GAP)
	right.add_child(slots)
	_active_only = [equip_caption, slots]
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
	# **끌어서 내린다** — 가방과 같다 (`DragScroll`)
	_skill_drag = DragScroll.attach(scroll, _skill_grid, SKILL_GAP)
	# 패시브는 격자가 아니라 **나무**다 (2026-09-30) — 같은 자리에 두고, 칸이 있는 쪽만 보인다
	_tree_scroll = ScrollContainer.new()
	_tree_scroll.name = "passiveTree"
	_tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_tree_scroll)
	_tree = Container.new()
	_tree_scroll.add_child(_tree)
	_tree_drag = DragScroll.attach(_tree_scroll, _tree, TREE_GAP)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	right.add_child(buttons)
	_skill_unequip = _gold_text(_make_button("해제", _on_skill_unequip))
	buttons.add_child(_skill_unequip)
	_skill_equip = _gold_text(_make_button("장착", _on_skill_equip))
	buttons.add_child(_skill_equip)
	# 패시브 [습득] — 레벨이 되면 공짜로 한 단계 (2026-09-29 요청: "습득 버튼을 만들어서 배우게 …
	# 스킬 UI 안에서도 습득 버튼 위에 레드닷"). 점은 단추 오른쪽 위 모서리에 얹는다
	_passive_learn = _gold_text(_make_button("습득", _on_passive_learn))
	_passive_learn.name = "learnPassive"
	# 누르는 순간 한 번, 누르고 있으면 계속 (`_tick_learn_hold`) — 떼는 순간에 한 번 더 배우지 않게 누를 때 받는다
	_passive_learn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_passive_learn.button_down.connect(_on_learn_down)
	_passive_learn.button_up.connect(_on_learn_up)
	buttons.add_child(_passive_learn)
	_passive_dot = _add_red_dot(_passive_learn)

	_active_only.append(_build_upgrade_column(columns))


## 스킬창 셋째 칸 — **고른 스킬의 강화 두 칸과 경험치북 단추** (2026-09-23).
##
## 요청 둘이 겹쳐 있다: "스킬창에서 스킬 강화하는 ui 만들어. 인벤토리에서 사용하지
## 말고" → "스킬 강화 경험치북들 만들고 … 어떤 타입을 강화할지 선택해서 경험치를 넣을
## 수 있으면". 그래서 **카드를 눌러 강화를 고르고**(금테), 아래 **경험치북 단추**
## (하급·중급·상급, 가진 수)를 누르면 고른 강화에 한 권씩 들어간다. 카드마다 경험치
## 막대와 `320 / 1000` 이 있고, 다 차면 "강화 완료" 로 바뀐다.
##
## 설명 칸 아래에 줄로 넣지 않고 칸을 하나 더 세웠다 — 창이 이미 580px 라 더하면
## 720 을 넘는다. 옆으로는 1234px 로 1280 안에 든다. 카드는 설명 칸과 같은 던전 결 평판
## (`_stone_cell_box`), 고른 카드는 금 막대(`_stone_pick_box`), 단추는 `ui_button` — 새 조각은 없다
func _build_upgrade_column(columns: HBoxContainer) -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(UPGRADE_W, 0)
	column.add_theme_constant_override("separation", 10)
	columns.add_child(column)
	column.add_child(_caption("강화"))

	_upgrade_cards.clear()
	for slot in int(GameData.load_table("skills").get("upgradeMax", 2)):
		column.add_child(_make_upgrade_card(slot))

	# 모아 둔 스킬 경험치(던전 클리어로 쌓인다)를 고른 강화에 모자란 만큼 넣는다.
	# 예전엔 경험치북 세 단추(하급·중급·상급)였다 — 2026-09-28 에 하나로 합쳤다
	_upgrade_hint = _inv_label("", 17, INV_DIM)
	_upgrade_hint.clip_text = true
	column.add_child(_upgrade_hint)
	_feed_button = _gold_text(_make_button("넣기", _on_feed_pressed))
	_feed_button.custom_minimum_size = Vector2(UPGRADE_W, 70)
	_feed_button.add_theme_font_size_override("font_size", 20)
	column.add_child(_feed_button)
	return column


## 강화 카드 하나 — 번호 · 이름 · 효과 · 경험치 막대 · `320 / 1000`.
## 스킬 칸처럼 **겉에 투명 단추(`hit`)를 덮어** 카드 어디를 눌러도 고른다
## 강화 칸 글자를 `room` 폭 한 줄에 맞춘다 — `size` 에서 넘치면 한 단계씩 줄인다.
## 칸은 `clip_text` 라 글자에 밀려 넓어지지 않는다 (창 크기가 고정이다)
func _fit_upgrade_text(label: Label, room: float, size: int) -> void:
	var font := label.get_theme_font("font")
	while size > UPGRADE_FONT_MIN and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 1
	label.add_theme_font_size_override("font_size", size)


func _make_upgrade_card(slot: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _stone_cell_box())
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
	title_label.clip_text = true
	head.add_child(title_label)
	var number := _inv_label("%d번" % (slot + 1), 17, INV_DIM)
	head.add_child(number)
	var effect := _inv_label("", UPGRADE_DESC_SIZE, INV_TEXT)
	effect.clip_text = true
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
	amount.clip_text = true
	rows.add_child(amount)

	var pick := Panel.new()
	pick.name = "pick"
	pick.visible = false
	pick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pick.add_theme_stylebox_override("panel", _stone_pick_box())
	card.add_child(pick)
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.pressed.connect(_on_upgrade_pressed.bind(slot))
	card.add_child(hit)

	_upgrade_cards.append({
		"card": card, "name": title_label, "number": number, "effect": effect, "bar": bar,
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
			_fit_upgrade_card(card)
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
		_fit_upgrade_card(card)

	# 넣기 단추 — 고른 강화가 없거나 이미 붙었거나 모아 둔 경험치가 없으면 꺼진다
	var target: Dictionary = list[_upgrade_slot] if _upgrade_slot < list.size() else {}
	var open := not target.is_empty() and not (str(target.id) in have)
	var pool := int(me.get("skill_exp", 0))
	if target.is_empty():
		_upgrade_hint.text = "스킬 경험치 %d — 넣을 강화가 없다" % pool
	elif not open:
		_upgrade_hint.text = "스킬 경험치 %d — %s 강화 완료" % [pool, target.name]
	else:
		_upgrade_hint.text = "스킬 경험치 %d — %s에 넣기" % [pool, target.name]
	_fit_upgrade_text(_upgrade_hint, UPGRADE_W, 17)
	_feed_button.disabled = not open or pool <= 0


## 카드 안쪽(`UPGRADE_W` − 여백 24)에 이름·설명·경험치 줄을 맞춘다. 이름은 "1번" 옆자리만 쓴다
func _fit_upgrade_card(card: Dictionary) -> void:
	var room := float(UPGRADE_W - 24)
	var number: Label = card.number
	var head_gap := float(number.get_parent().get_theme_constant("separation"))
	_fit_upgrade_text(card.name, room - number.get_minimum_size().x - head_gap, 24)
	_fit_upgrade_text(card.effect, room, UPGRADE_DESC_SIZE)
	_fit_upgrade_text(card.amount, room, 17)


## 카드를 누르면 그 강화를 고른다 — 넣기 단추가 그쪽으로 넣는다
func _on_upgrade_pressed(slot: int) -> void:
	_upgrade_slot = slot
	_redraw_skills()


func _on_feed_pressed() -> void:
	_transport.send(&"feedUpgrade", {"skill": _skill_pick, "slot": _upgrade_slot})
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
	_cheat_column = column
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
	# 가방 빈칸을 장비로 꽉 채운다 (2026-09-24 요청 — "테스트하기 위해서 아이템을 인벤토리에 채워".
	# 다중 강화를 시험하려면 같은 아이템 여럿 · 섞인 강화 단계가 필요하다)
	var fill := Button.new()
	fill.custom_minimum_size = Vector2(230, 52)
	fill.add_theme_font_size_override("font_size", 18)
	fill.text = "테스트: 가방 채우기"
	fill.pressed.connect(func() -> void:
		_transport.send(&"debugFillBag", {})
		if _bag_panel.visible:
			_redraw_bag()
	)
	column.add_child(fill)
	column.move_child(fill, 0)
	# 크리스탈 30개를 가방에 넣는다 (2026-09-23 요청 — "가방에 30개 넣어". 드랍이 0.1% 라
	# 주워서는 시험해 볼 수 없다)
	var crystals := Button.new()
	crystals.custom_minimum_size = Vector2(72, 52)
	crystals.add_theme_font_size_override("font_size", 14)
	crystals.text = "크리스탈\n30"
	crystals.pressed.connect(func() -> void:
		_transport.send(&"debugCrystals", {"count": 30})
		if _bag_panel.visible:
			_redraw_bag()
	)
	# 프로틴 세 종 +1만 — 던전을 안 돌고 헬스를 볼 때 (`World.debug_protein`, 2026-09-30).
	# 목록이 위로 넘치므로 줄을 늘리지 않고 크리스탈과 한 줄에 셋으로 놓는다.
	# 옐로우 크리스탈 30 — 3차 옵션 재료 (2026-10-02). 샌드백 랭킹전 보상으로만 들어와서 시험할 길이 없다
	var crystal_row := HBoxContainer.new()
	crystal_row.add_theme_constant_override("separation", 6)
	crystal_row.add_child(crystals)
	crystal_row.add_child(_test_button("옐로우\n30", 72, 14, &"debugCrystals", {"count": 30, "id": Items.yellow_crystal_id()}))
	crystal_row.add_child(_test_button("프로틴\n+1만", 72, 14, &"debugProtein", {}))
	column.add_child(crystal_row)
	column.move_child(crystal_row, 0)
	# 스킬 강화 — **모든 스킬 1번 강화 · 2번 강화 · 초기화** (2026-09-23 요청). 경험치북
	# 없이 바로 붙는다 (사용자 선택). 줄이 위로 자라므로 앞의 둘은 **한 줄에 반씩** 놓는다
	var reset := _test_button("테스트: 강화 초기화", 230, 18, &"debugResetUpgrades", {})
	column.add_child(reset)
	column.move_child(reset, 0)
	# 스킬 경험치 +10만 — 던전을 안 돌고 강화를 볼 때 (`World.debug_skill_exp`)
	# 스킬 모두 배우기 — 패시브도 끝 단계까지 (2026-09-26 요청, `World.debug_learn_all`).
	# 목록이 이미 화면 위로 넘치므로 **줄을 늘리지 않고** 스킬 경험치와 한 줄에 반씩 놓는다
	var book_row := HBoxContainer.new()
	book_row.add_theme_constant_override("separation", 6)
	book_row.add_child(_test_button("스킬 경험치\n+10만", 112, 16, &"debugSkillExp", {}))
	var learn_all := _test_button("스킬 모두\n배우기", 112, 16, &"debugLearnAll", {})
	learn_all.name = "learnAll"
	book_row.add_child(learn_all)
	column.add_child(book_row)
	column.move_child(book_row, 0)
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
	# 채팅창 바로 위에는 **치트 목록 여닫기 단추** 하나가 서고, 묶음은 그 위로 선다 (2026-09-25).
	# 단추 열 개가 왼쪽을 다 덮어서 접을 수 있게 했다
	_cheat_toggle = Button.new()
	_cheat_toggle.custom_minimum_size = CHEAT_TOGGLE
	_cheat_toggle.add_theme_font_size_override("font_size", 18)
	_cheat_toggle.pressed.connect(_toggle_cheats)
	_ui_root.add_child(_cheat_toggle)
	_cheat_toggle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	_cheat_toggle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cheat_toggle.offset_top -= lift
	_cheat_toggle.offset_bottom -= lift
	_build_skill_list(lift)
	lift += CHEAT_TOGGLE.y + 6
	column.offset_top -= lift
	column.offset_bottom -= lift
	_set_cheats_open(true)


## 치트 목록 여닫기 단추의 크기 — 테스트 단추(230)와 너비를 맞춘다
const CHEAT_TOGGLE := Vector2(230, 44)


func _toggle_cheats() -> void:
	_set_cheats_open(not _cheat_column.visible)


## **테스트 모드 스킬 목록** (2026-09-28 요청: "테스트 모드에서는 스킬을 목록을 왼쪽에 버튼 만들어서
## 누르면 사용할 수 있게 만들어"). 치트 여닫기 단추 **오른쪽 옆**에 "스킬 목록" 단추가 서고, 펼치면
## 내 직업 스킬이 두 줄로 **왼쪽 끝에 붙어** 선다 (2026-09-29 요청: "나오는 화면을 왼쪽으로 붙여").
## 누르면 퀵슬롯 칸과 **같은 요청**(`skill`)을 보낸다 — 판정은 World 가 다시 본다 (안 배웠으면
## 거절). 퀵슬롯 4칸에 없는 스킬도 바로 써 볼 수 있게 한 것이다.
## 목록 자리가 펼친 치트 목록 자리와 같아서 **한쪽을 펼치면 다른 쪽이 접힌다**
const SKILL_LIST_TOGGLE := Vector2(150, 44)
const SKILL_LIST_CELL := Vector2(160, 52)
func _build_skill_list(lift: float) -> void:
	var shift := CHEAT_TOGGLE.x + 6
	_skill_list_toggle = Button.new()
	_skill_list_toggle.name = "skillListToggle"
	_skill_list_toggle.custom_minimum_size = SKILL_LIST_TOGGLE
	_skill_list_toggle.add_theme_font_size_override("font_size", 18)
	_skill_list_toggle.pressed.connect(func() -> void: _set_skill_list_open(not _skill_list.visible))
	_ui_root.add_child(_skill_list_toggle)
	_skill_list_toggle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	_skill_list_toggle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skill_list_toggle.offset_left += shift
	_skill_list_toggle.offset_right += shift
	_skill_list_toggle.offset_top -= lift
	_skill_list_toggle.offset_bottom -= lift
	_skill_list = GridContainer.new()
	_skill_list.name = "skillList"
	_skill_list.columns = 2
	_skill_list.add_theme_constant_override("h_separation", 6)
	_skill_list.add_theme_constant_override("v_separation", 6)
	_ui_root.add_child(_skill_list)
	_skill_list.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	_skill_list.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skill_list.offset_top -= lift + SKILL_LIST_TOGGLE.y + 6
	_skill_list.offset_bottom -= lift + SKILL_LIST_TOGGLE.y + 6
	_set_skill_list_open(false)


## 펼칠 때마다 다시 짓는다 — 직업을 새로 골라도 그 직업 스킬이 뜬다
func _set_skill_list_open(open: bool) -> void:
	if open:
		_fill_skill_list()
		if _cheat_column.visible:
			_set_cheats_open(false)
	_skill_list.visible = open
	_skill_list_toggle.text = "스킬 목록 닫기" if open else "스킬 목록 열기"
	_skill_list_toggle.modulate = Color.WHITE if open else Color(1, 1, 1, 0.75)


func _fill_skill_list() -> void:
	for child in _skill_list.get_children():
		_skill_list.remove_child(child)
		child.queue_free()
	for id in Skills.for_job(str(_me().get("job", ""))):
		var button := Button.new()
		button.name = str(id)
		button.custom_minimum_size = SKILL_LIST_CELL
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_constant_override("icon_max_width", 36)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.icon = _icon("skill_" + str(id))
		button.text = str(Skills.all().get(id, {}).get("name", id))
		button.pressed.connect(func() -> void: _transport.send(&"skill", {"skill": str(id)}))
		_skill_list.add_child(button)


func _set_cheats_open(open: bool) -> void:
	if open and _skill_list != null and _skill_list.visible:
		_set_skill_list_open(false)
	_cheat_column.visible = open
	_cheat_toggle.text = "치트 목록 닫기" if open else "치트 목록 열기"
	_cheat_toggle.modulate = Color.WHITE if open else Color(1, 1, 1, 0.75)


## 시작 화면에서 고른 모드를 건다 → play-mode.md
## - 테스트 모드: 무적과 쿨타임 0 을 켜고, 치트 목록은 접어 둔다 (펼치면 왼쪽을 다 덮는다)
## - 일반 모드: 아무것도 안 켜고, 치트 목록과 여닫기 단추를 아예 숨긴다
## - 모드 없음(테스트·도구가 main.tscn 을 바로 띄움): 지금까지처럼 둔다
func _apply_play_mode() -> void:
	match PlayMode.current:
		PlayMode.TEST:
			_transport.send(&"invincible", {"on": true})
			if not Skills.cooldown_off():
				_transport.send(&"testSwitch", {"name": "cooldownOff", "on": true})
			# 모든 장비 등급별로 하나씩(+0)과 크리스탈 300개 — 한 번만 준다 (`World.grant_test_kit`)
			_transport.send(&"testKit", {})
			# 200레벨로 시작한다 — 한 번만 (`World.grant_test_level`)
			_transport.send(&"testLevel", {})
			# 모든 스킬을 배운다 — 한 번만 (`World.grant_test_skills`). 패시브는 비워 둔다(습득을 눌러 본다)
			_transport.send(&"testSkills", {})
			# 스킬 목록 단추는 **보이는 스킬이 있을 때만** — 격투가는 평타만 쓴다 (2026-09-29)
			_skill_list_toggle.visible = Skills.actives_shown(World.DEFAULT_JOB)
			_refresh_switches()
			_set_cheats_open(false)
		PlayMode.NORMAL:
			_set_cheats_open(false)
			_cheat_toggle.visible = false
			_set_skill_list_open(false)
			_skill_list_toggle.visible = false


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
## 능력·설명 글자가 상자 밖으로 삐져나와 보였다 (2026-09-19). 2026-09-28 부터는 조각 대신
## 던전 단계 창의 칸과 같은 코드 평판(`_stone_cell_box`)이다 — 테가 늘 상자 끝에 온다
func _sub_box(parent: Node, fill: bool) -> VBoxContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _stone_cell_box())
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
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", DungeonPanel.CARD_SUB_COLOR)
	return label


## 스킬창의 상자 — 던전 단계 창의 보상 칸과 같은 어두운 평판에 가는 흙금빛 선
## (`DungeonPanel._cell_box`). 둘레가 넓게 번지는 조각이 아니라 글자가 밖으로 나올 일도 없다
func _stone_cell_box(content: int = 8) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = DungeonPanel.CELL_BG
	box.border_color = DungeonPanel.CELL_LINE
	box.set_border_width_all(1)
	box.set_content_margin_all(content)
	return box


## 가방의 세로 탭 — 던전 단계 창의 줄(`DungeonPanel._row_box`)과 같은 모양
func _stone_tab_box(on: bool) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.75, 0.45, 0.14) if on else Color(0, 0, 0, 0)
	box.border_color = DungeonPanel.CARD_GOLD if on else DungeonPanel.CELL_LINE
	box.border_width_left = 3 if on else 0
	box.border_width_bottom = 1
	box.set_content_margin_all(4)
	return box


## 고른 강화 카드 — 던전 단계 창의 고른 줄처럼 옅은 금빛 바탕 + 왼쪽 금 막대
func _stone_pick_box() -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.75, 0.45, 0.14)
	box.border_color = DungeonPanel.CARD_GOLD
	box.set_border_width_all(1)
	box.border_width_left = 4
	return box


## 단추 글자를 던전 창의 입장 단추처럼 금빛으로 (막히면 흐린 회색)
## 글자가 단추 폭(`INV_BUTTON.x`)에 들어가도록 `largest` 부터 한 칸씩 줄인다. 글자가 넘치면 단추가
## 넘쳐 옆 단추를 덮는다 — "잠금 해제" 를 15 로 박아 뒀더니 웹에서 76px 를 넘어 "강화" 를 덮었다 (2026-10-02 캡처).
## 헤드리스는 15 가 들어간다고 쟀다 — **웹 글꼴 폭이 조금 더 넓다.** 그래서 외곽선 양쪽과 여유 4px 를 더 빼고 재며
## ("잠금 해제" 는 13 — 헤드리스 51px, 웹이 20% 넓어도 단추 안쪽 64px 에 든다),
## `clip_text` 로 단추 밖에는 아예 안 그린다 (어긋나도 옆을 덮지 않는다)
func _fit_button_text(button: Button, largest: int) -> void:
	button.clip_text = true
	var font := button.get_theme_font("font")
	var room := INV_BUTTON.x - button.get_theme_stylebox("normal").get_minimum_size().x \
			- 2.0 * button.get_theme_constant("outline_size") - 4.0
	var size := largest
	while size > 10 and font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 1
	button.add_theme_font_size_override("font_size", size)


func _gold_text(button: Button, size: int = 26) -> Button:
	return GatePanel.paint_button_text(button, size)


func _toggle_skills() -> void:
	_skill_panel.visible = not _skill_panel.visible
	_skill_swap = false
	_skill_drag.forget()
	_tree_drag.forget()
	if _skill_panel.visible:
		# 맨 앞으로 — 강화 칸을 더해 1234px 가 되면서 왼쪽 테스트 단추 줄 밑으로
		# 들어갔다. 단추 글자가 창 위에 찍혔다 (2026-09-23 캡처)
		_skill_panel.get_parent().move_to_front()
		_redraw_skills()
		# 나무는 열 때마다 **지금 습득할 칸**으로 간다 — Lv.100 이면 그 칸이 한참 아래다
		var ready := _tree_ready_index()
		if ready >= 0:
			_pick_tree(ready)
			_tree_scroll.ensure_control_visible.call_deferred(_tree_nodes[ready].cell)


func _me() -> Dictionary:
	return _transport.snapshot().get("players", {}).get(_transport.my_id(), {})


## 스킬창 내용을 지금 상태로 채운다. 목록은 직업이 바뀌었을 때만 다시 짓는다.
## **패시브가 목록 앞에 선다** (2026-09-29) — 격투가는 보이는 액티브가 없어 질풍각 하나다
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
	if job != _tree_job:
		_build_tree(job)
	var on_tree := _tree_find(_skill_pick) >= 0
	if not (_skill_pick in _skill_ids) and not on_tree:
		if not _tree_nodes.is_empty():
			_skill_pick = str(_tree_nodes[maxi(_tree_ready_index(), 0)].id)
		else:
			_skill_pick = str(_skill_ids[0]) if not _skill_ids.is_empty() else ""
	# 액티브 격자와 패시브 나무는 칸이 있는 쪽만 — 격투가는 나무만, 다른 직업은 격자만
	_skill_drag._scroll.visible = not _skill_ids.is_empty()
	_tree_scroll.visible = not _tree_nodes.is_empty()

	var bar: Array = me.get("skill_bar", [])
	var learned: Array = me.get("skills", [])
	var level := int(me.get("level", 1))
	var ranks: Dictionary = me.get("passives", {})
	var actives := Skills.actives_shown(job)
	for node in _active_only:
		node.visible = actives

	for index in _skill_cells.size():
		var id := str(_skill_ids[index])
		var cell: PanelContainer = _skill_cells[index]
		_fill_skill_cell(cell, id, "")
		cell.get_node("pick").visible = id == _skill_pick
		var badge: Label = cell.find_child("badge", true, false)
		var skill: Dictionary = Skills.all().get(id, {})
		# 안 배운 것만 "Lv.N 습득". 배웠으면 지운다. 장착 번호는 적지 않는다 — 번호는 퀵슬롯에 있다
		badge.text = "" if id in learned else "Lv.%d 습득" % int(skill.get("reqLevel", 1))
		# 아직 배울 수 없는 것은 흐리게
		var open: bool = id in learned or Skills.can_learn(skill, job, level)
		cell.modulate = Color.WHITE if open else Color(0.5, 0.5, 0.5)
	_redraw_tree(level, ranks)

	for slot in _slot_cells.size():
		var cell: PanelContainer = _slot_cells[slot]
		var id := str(bar[slot]) if slot < bar.size() else ""
		_fill_skill_cell(cell, id, "+")
		cell.get_node("pick").visible = _skill_swap or (id != "" and id == _skill_pick)

	_fill_skill_cell(_skill_big, _skill_pick, "")
	var picked_passive := Skills.passive(_skill_pick)
	_passive_learn.visible = not picked_passive.is_empty()
	_skill_equip.visible = actives and picked_passive.is_empty()
	_skill_unequip.visible = _skill_equip.visible
	if not picked_passive.is_empty() and _tree_find(_skill_pick) >= 0:
		_draw_passive(me, _tree_nodes[_tree_find(_skill_pick)])
		return

	var skill: Dictionary = Skills.all().get(_skill_pick, {})
	_skill_name.text = str(skill.get("name", ""))
	# 범위기는 범위에 든 놈을 **전부** 친다 — 명수 상한이 없어서 "범위" 라고만 적는다
	var targets := int(skill.get("maxTargets", 1))
	_skill_info.text = "요구 레벨 %d\n재사용 %s초\n사거리 %s, %s" % [
		int(skill.get("reqLevel", 1)),
		str(snappedf(float(skill.get("cooldown", 0)) / 1000.0, 0.1)),
		str(skill.get("range", 0)),
		"대상 %d명" % targets if targets <= 1 else "범위",
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


## 패시브 나무를 짓는다 — 직업이 바뀔 때만. **칸 하나가 계열 하나**다 (2026-10-01 요청: "다른 스킬들도
## 마찬가지로 레벨업 형식으로") — `requires` 로 이은 패시브(철각 1~4단 · 급소 간파 1·2단 · 급소 강타 1·2단)는
## 한 칸에서 차례로 배우고, 단계가 여럿인 질풍각도 한 칸이다. **줄은 계열이 처음 열리는 레벨**, 칸은 계열마다 옆으로.
## 저장·장부는 그대로 패시브 id 하나씩이다 — 칸이 "다음에 배울 [id, 단계]"(`_tree_next`)를 골라 요청한다.
## 노드: `id`(계열 첫 패시브) · `ids`(계열 순서) · `steps`([id, 단계] 를 배우는 순서대로) · `row` · `column` · `cell` · `dot`.
## 칸은 `Container` 에 자리를 박아 둔다 — 끌기·누르기는 가방과 같은 `DragScroll` 이 맡는다.
## 칸을 먼저 넣고 레벨 글자는 뒤에 넣는다 — 나무 자식 번호가 `_tree_nodes` 번호와 같아야 한다
func _build_tree(job: String) -> void:
	_tree_job = job
	for child in _tree.get_children():
		_tree.remove_child(child)
		child.queue_free()
	_tree_nodes.clear()
	var node_of := {}
	for p in Skills.passives_for(job):
		var need := str(p.get("requires", ""))
		if node_of.has(need):
			var upper: Dictionary = node_of[need]
			upper.ids.append(str(p.id))
			node_of[str(p.id)] = upper
		else:
			var fresh := {"id": str(p.id), "ids": [str(p.id)], "level": int(p.everyLevels), "column": _tree_nodes.size()}
			node_of[str(p.id)] = fresh
			_tree_nodes.append(fresh)
	var levels: Array = []
	for node in _tree_nodes:
		if not node.level in levels:
			levels.append(node.level)
	levels.sort()
	for index in _tree_nodes.size():
		var node: Dictionary = _tree_nodes[index]
		node.row = levels.find(node.level)
		node.steps = []
		for id in node.ids:
			for step in range(1, int(Skills.passive(id).maxRank) + 1):
				node.steps.append([id, step])
		var cell := _make_skill_cell(TREE_CELL, "ui_slot", _pick_tree.bind(index))
		cell.position = _tree_spot(node.column, node.row)
		cell.size = Vector2(TREE_CELL, TREE_CELL)
		_tree.add_child(cell)
		_fill_skill_cell(cell, node.id, "")
		node.cell = cell
		node.dot = _add_red_dot(cell)
	for row in levels.size():
		var label := _inv_label("Lv.%d" % levels[row], 20, INV_GOLD)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = Vector2(0, row * (TREE_CELL + TREE_GAP))
		label.size = Vector2(TREE_LABEL_W - 8, TREE_CELL)
		_tree.add_child(label)
	_tree.custom_minimum_size = Vector2.ZERO if _tree_nodes.is_empty() else Vector2(
		TREE_LABEL_W + _tree_nodes.size() * (TREE_CELL + TREE_GAP) - TREE_GAP,
		levels.size() * (TREE_CELL + TREE_GAP) - TREE_GAP
	)


func _tree_spot(column: int, row: int) -> Vector2:
	return Vector2(TREE_LABEL_W + column * (TREE_CELL + TREE_GAP), row * (TREE_CELL + TREE_GAP))


## 그 패시브가 든 나무 칸 번호 (없으면 -1)
func _tree_find(id: String) -> int:
	for index in _tree_nodes.size():
		if id in _tree_nodes[index].ids:
			return index
	return -1


## 지금 습득할 수 있는 첫 칸 (없으면 -1)
func _tree_ready_index() -> int:
	var me := _me()
	for index in _tree_nodes.size():
		if _tree_state(_tree_nodes[index], int(me.get("level", 1)), me.get("passives", {})) == "ready":
			return index
	return -1


## 계열 칸에서 배운 단계 수 — 앞 단계부터 배우므로(`requires`) 패시브마다 배운 단계를 더하면 된다
func _tree_done(node: Dictionary, ranks: Dictionary) -> int:
	var done := 0
	for id in node.ids:
		done += clampi(int(ranks.get(id, 0)), 0, int(Skills.passive(id).maxRank))
	return done


## 그 칸에서 다음에 배울 [패시브 id, 단계] — 끝까지 배웠으면 빈 배열
func _tree_next(node: Dictionary, ranks: Dictionary) -> Array:
	var done := _tree_done(node, ranks)
	return node.steps[done] if done < node.steps.size() else []


## 칸 하나의 상태 — "done"(끝까지 배움) · "ready"(지금 습득) · "level"(다음 단계가 아직 안 열림)
func _tree_state(node: Dictionary, level: int, ranks: Dictionary) -> String:
	var next := _tree_next(node, ranks)
	if next.is_empty():
		return "done"
	return "level" if int(next[1]) * int(Skills.passive(str(next[0])).everyLevels) > level else "ready"


## 앞 `count` 단계를 합친 효과("공격력 +30%"). 한 계열은 스탯이 같다 — 합만 다르다
func _tree_effect(node: Dictionary, count: int) -> String:
	if count <= 0:
		return "없음"
	var total := 0.0
	for i in count:
		total += float(Skills.passive(str(node.steps[i][0])).perRank)
	return Skills.passive_effect({"stat": Skills.passive(str(node.id)).stat, "perRank": total}, 1)


## 칸 이름 — 배운 마지막 단계("철각 2단" · "질풍각 12단"), 하나도 안 배웠으면 계열 이름("철각")
func _tree_title(node: Dictionary, done: int) -> String:
	if done <= 0:
		return Skills.passive_title(Skills.passive(str(node.id)), 1).rsplit(" ", true, 1)[0]
	var last: Array = node.steps[done - 1]
	return Skills.passive_title(Skills.passive(str(last[0])), int(last[1]))


## 칸마다 — 고른 테두리 · 칸 글자 **"배운/전체"** · **하나도 안 배운 칸은 음영**(2026-09-30 요청: "미습득한 스킬은
## 음영 처리해") · 지금 습득할 칸에 레드닷. 칸째(`modulate`) 어둡게 하면 칸에 얹힌 레드닷까지 어두워져서
## 틀(`self_modulate`)과 그림만 어둡게 한다
func _redraw_tree(level: int, ranks: Dictionary) -> void:
	for node in _tree_nodes:
		var done := _tree_done(node, ranks)
		node.cell.get_node("pick").visible = node.id == _skill_pick
		node.cell.find_child("badge", true, false).text = "%d/%d" % [done, node.steps.size()]
		var shade := Color.WHITE if done > 0 else TREE_SHADE
		node.cell.self_modulate = shade
		node.cell.find_child("icon", true, false).modulate = shade
		node.dot.visible = _tree_state(node, level, ranks) == "ready"


## 고른 칸(계열)을 왼쪽 칸에 적고 [습득]/[레벨업] 을 맞춘다. **레벨이 되면 공짜** — 되는지는 장부가 다시 본다.
## "패시브 · N / 전체 단계" · 현재 단계 · 다음 단계(합친 효과). 단추는 처음(0단계)만 "습득", 그 뒤로 "레벨업" —
## 질풍각(2026-09-30)에서 시작해 모든 계열이 같다(2026-10-01).
## 질풍각은 초당 타수를 지금 스탯(`me.stats`, 패시브가 이미 더해진 것)과 다음 단계 뒤로 나란히 적는다
func _draw_passive(me: Dictionary, node: Dictionary) -> void:
	var ranks: Dictionary = me.get("passives", {})
	var done := _tree_done(node, ranks)
	var top: int = node.steps.size()
	var next := _tree_next(node, ranks)
	_skill_name.text = _tree_title(node, done)
	_skill_info.text = "패시브 · %d / %d 단계\n현재 단계 : %s\n다음 단계 : %s" % [
		done, top, _tree_effect(node, done), "없음" if next.is_empty() else _tree_effect(node, done + 1),
	]
	# 설명은 다음에 배울 패시브의 것 (끝까지 배웠으면 마지막 것)
	var shown := Skills.passive(str(node.steps[mini(done, top - 1)][0]))
	_skill_desc.text = str(shown.get("description", ""))
	if str(shown.get("stat", "")) == "attackSpeed":
		var stats: Dictionary = me.get("stats", {})
		var base := float(stats.get("attackCooldown", 900))
		var speed := float(stats.get("attackSpeed", 0.0))
		_skill_desc.text += "\n\n초당 %.1f회 공격" % (1000.0 / Combat.effective_cooldown(base, speed))
		if not next.is_empty():
			var after := speed + float(shown.perRank)
			_skill_desc.text += " → 다음 단계 %.1f회" % (1000.0 / Combat.effective_cooldown(base, after))
	var state := _tree_state(node, int(me.get("level", 1)), ranks)
	match state:
		"done":
			_skill_state.text = "끝까지 배웠습니다"
		"ready":
			_skill_state.text = "습득할 수 있습니다"
		_:
			var at := int(next[1]) * int(Skills.passive(str(next[0])).everyLevels)
			_skill_state.text = "%d레벨에 다음 단계가 열립니다" % at
	_passive_learn.text = "습득" if done == 0 else "레벨업"
	_passive_learn.disabled = state != "ready"
	_passive_dot.visible = state == "ready"


## [습득]/[레벨업] — 고른 칸의 다음 단계를 요청한다. 장부는 패시브 id 로 "다음 단계 하나" 를 올린다.
## 답(`passives`)이 오면 창을 다시 그린다
func _on_passive_learn() -> void:
	var index := _tree_find(_skill_pick)
	if index < 0:
		return
	var me := _me()
	var ranks: Dictionary = me.get("passives", {})
	var node: Dictionary = _tree_nodes[index]
	if _tree_state(node, int(me.get("level", 1)), ranks) == "ready":
		_transport.send(&"learnPassive", {"id": str(_tree_next(node, ranks)[0])})


## [레벨업] 을 **누르고 있으면** 열린 데까지 빠르게 오른다 (2026-10-01 요청). 단추는 누르는 순간 한 번 배우고
## (`ACTION_MODE_BUTTON_PRESS`), `LEARN_HOLD_DELAY` 뒤로는 `_tick_learn_hold` 가 간격을 줄여 가며 한 단계씩 —
## 떼거나 창을 닫거나 배울 것이 없으면(단추가 막히면) 멈춘다
func _on_learn_down() -> void:
	_learn_held = true
	_learn_wait = LEARN_HOLD_DELAY
	_learn_gap = LEARN_HOLD_GAP


func _on_learn_up() -> void:
	_learn_held = false


func _tick_learn_hold(delta: float) -> void:
	if not _learn_held:
		return
	if not _skill_panel.visible or not _passive_learn.visible or _passive_learn.disabled:
		_learn_held = false
		return
	_learn_wait -= delta
	if _learn_wait > 0.0:
		return
	_on_passive_learn()
	_learn_gap = maxf(LEARN_HOLD_MIN, _learn_gap * LEARN_HOLD_SPEEDUP)
	_learn_wait = _learn_gap


func _pick_tree(index: int) -> void:
	_skill_pick = str(_tree_nodes[index].id)
	_learn_held = false
	_skill_swap = false
	_redraw_skills()


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
	# 상점·대장간 창과 전직 창은 **HUD 보다 위 층**에 단다 — `_ui_root` 에 두었더니 체력
	# 막대·퀵슬롯이 창 아래쪽을 덮었다 (2026-09-26, 찍어서 봤다). 차원문 창과 같은 층 번호다
	var top := CanvasLayer.new()
	top.name = "NpcLayer"
	top.layer = 10
	add_child(top)

	# 상점·대장간 — 얇은 금테 결 (npc_panel.gd). 줄을 누르면 신호가 오고 요청만 보낸다
	_npc_panel = NpcPanel.make(_frame_box, _icon, _item_icon, _grade_tint, _me)
	# 한글 폰트는 _ui_root 의 테마에 있다 — 다른 층이라 직접 물려준다
	_npc_panel.theme = _ui_root.theme
	top.add_child(_npc_panel)
	_npc_panel.buy.connect(func(id: String) -> void:
		_transport.send(&"npcBuy", {"item": id})
		_npc_panel.redraw()
	)
	_npc_panel.sell.connect(func(index: int) -> void:
		_transport.send(&"npcSell", {"index": index})
		_npc_panel.redraw()
	)
	_npc_panel.enhance.connect(func(index: int) -> void:
		_transport.send(&"npcEnhance", {"index": index})
		_npc_panel.redraw()
	)

	# 시련의 탑 결과창 — 확인을 누르면 마을로 (trial_result.gd)
	_dungeon_result = DungeonResult.make(_frame_box, _icon)
	_dungeon_result.theme = _ui_root.theme
	top.add_child(_dungeon_result)
	_dungeon_result.confirmed.connect(_on_result_confirmed)

	# 사망 창 — 확인을 누르면 마을에서 되살아난다. 띄우는 건 `_refresh_status` 가 상태로 한다
	_death_panel = DeathPanel.make(_frame_box)
	_death_panel.theme = _ui_root.theme
	top.add_child(_death_panel)
	_death_panel.confirmed.connect(func() -> void: _transport.send(&"revive", {}))


func _show_npc(payload: Dictionary) -> void:
	var role := str(payload.get("role", ""))
	var title := str(payload.get("title", ""))
	_npc_panel.open(str(payload.get("name", "")), role, title, payload.get("items", []))


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
	# 단계 창의 보상 칸이 가방과 같은 물건 그림을 쓴다
	_dungeon_panel = DungeonPanel.make(_frame_box, _icon, _item_icon)
	_dungeon_panel.theme = _ui_root.theme
	_dungeon_panel.picked.connect(_on_gate_pick)
	# 던전 창은 전체 화면인데 틀 그림(`ui_dungeon_card`)의 가장자리가 찢긴 종이처럼
	# 반투명이라 **화면 끝에 게임 배경이 가늘게 비쳤다** (2026-09-28 지적). 창 뒤에
	# 불투명한 판을 한 장 깐다 — 창과 같이 보이고 같이 사라진다
	var dungeon_back := ColorRect.new()
	dungeon_back.name = "DungeonBack"
	dungeon_back.color = DungeonPanel.CARD_DARK
	dungeon_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dungeon_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dungeon_back.visible = false
	top.add_child(dungeon_back)
	_dungeon_panel.visibility_changed.connect(func(): dungeon_back.visible = _dungeon_panel.visible)
	top.add_child(_dungeon_panel)

	# 헬스 창도 같은 층·같은 결이다 (전체 화면 · 돌판 틀 · 뒤에 불투명한 판) → docs/features/fitness.md
	_fitness_panel = FitnessPanel.make(_frame_box, _icon)
	_fitness_panel.theme = _ui_root.theme
	_fitness_panel.up_requested.connect(func(kind: String, auto: bool) -> void:
		_transport.send(&"fitnessUp", {"kind": kind, "auto": auto})
	)
	var fitness_back := ColorRect.new()
	fitness_back.name = "FitnessBack"
	fitness_back.color = DungeonPanel.CARD_DARK
	fitness_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fitness_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fitness_back.visible = false
	top.add_child(fitness_back)
	_fitness_panel.visibility_changed.connect(func(): fitness_back.visible = _fitness_panel.visible)
	top.add_child(_fitness_panel)
	_close_button(_fitness_panel, _toggle_fitness, 0)

	# 도감 창도 같은 층·같은 결이다 → docs/features/codex.md
	_codex_panel = CodexPanel.make(_frame_box, _icon)
	_codex_panel.theme = _ui_root.theme
	_codex_panel.register_requested.connect(func(item_id: String, enhance: int, index: int) -> void:
		_transport.send(&"codexRegister", {"id": item_id, "enhance": enhance, "index": index})
	)
	_codex_panel.enhance_requested.connect(_open_enhance_from_codex)
	_codex_panel.register_all_requested.connect(func() -> void:
		_transport.send(&"codexRegisterAll", {})
	)
	var codex_back := ColorRect.new()
	codex_back.name = "CodexBack"
	codex_back.color = DungeonPanel.CARD_DARK
	codex_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	codex_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	codex_back.visible = false
	top.add_child(codex_back)
	_codex_panel.visibility_changed.connect(func(): codex_back.visible = _codex_panel.visible)
	top.add_child(_codex_panel)
	_close_button(_codex_panel, _toggle_codex, 0)


## ≡ 를 눌러 펼치는 메뉴 판 (2026-10-01 요청: "오른쪽 위에 x버튼을 평소에는 … 3줄 짜리 ui 아이콘 만들고
## 누르면 … 아이콘 나열되게"). 어두운 판 + 얇은 금테(ui-art-style.md), 맨 위는 평소 줄이 얹히는 빈 자리,
## 구분선 아래에 나머지 단추가 `MENU_SHEET_COLUMNS` 열로 선다. 열 간격이 평소 줄과 같아 칸이 줄 아래에 맞는다
func _build_menu_sheet() -> void:
	_menu_sheet = PanelContainer.new()
	_menu_sheet.name = "MenuSheet"
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.055, 0.045, 0.94)
	box.border_color = Color(GatePanel.CARD_GOLD, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(MENU_SHEET_PAD)
	_menu_sheet.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", MENU_SHEET_ROW_GAP)
	_menu_sheet.add_child(column)
	var room := Control.new()
	room.name = "bar_room"
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(room)
	var rule := ColorRect.new()
	rule.color = GatePanel.HEAD_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	_menu_grid = GridContainer.new()
	_menu_grid.name = "MenuGrid"
	_menu_grid.columns = MENU_SHEET_COLUMNS
	_menu_grid.add_theme_constant_override("h_separation", 6)
	_menu_grid.add_theme_constant_override("v_separation", MENU_SHEET_ROW_GAP)
	column.add_child(_menu_grid)
	_menu_sheet.visible = false
	_ui_root.add_child(_menu_sheet)
	# 평소 줄(위·오른쪽 20)을 판 여백만큼 감싼다 — 판 안쪽 왼쪽 끝이 줄 왼쪽 끝과 맞는다
	_menu_sheet.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20 - MENU_SHEET_PAD
	)
	_menu_sheet.grow_horizontal = Control.GROW_DIRECTION_BEGIN


## ≡ / X — 판을 펼치거나 접는다
func _toggle_menu() -> void:
	_set_menu_open(not _menu_sheet.visible)


func _close_menu() -> void:
	_set_menu_open(false)


func _set_menu_open(on: bool) -> void:
	_menu_sheet.visible = on
	_menu_open_cell.visible = not on
	_menu_close_cell.visible = on


func _open_gate() -> void:
	_dungeon_panel.visible = false
	_fitness_panel.visible = false
	_codex_panel.visible = false
	_gate_panel.open(_shown_zone)


## 던전 단추. 열려 있으면 닫는다. 차원문 창과 한 자리라 둘이 겹치지 않게 한쪽을 닫는다
func _toggle_dungeon() -> void:
	if _dungeon_panel.visible:
		_dungeon_panel.close_panel()
		return
	_gate_panel.visible = false
	_fitness_panel.visible = false
	_codex_panel.visible = false
	_sandbag_panel.visible = false
	_dungeon_panel.spent = _spent_dungeons()
	_dungeon_panel.open(_shown_zone)


## 오늘 입장을 다 쓴 던전 종류 `{ 종류 id: true }` — 던전 창이 카드·입장 단추를 막는다 (dungeons.md "하루 한 번")
func _spent_dungeons() -> Dictionary:
	var me := _me()
	var day := Ledger.day_of(Time.get_unix_time_from_system())
	var out := {}
	for type in GameData.dungeons():
		var stages: Array = type.get("stages", [])
		if not stages.is_empty() and Ledger.dungeon_entries_left(me, str(stages[0].zone), day) == 0:
			out[str(type.id)] = true
	return out


## 헬스 단추. 열려 있으면 닫는다. 차원문·던전 창과 한 층이라 그 둘을 닫고 연다
func _toggle_fitness() -> void:
	if _fitness_panel.visible:
		_fitness_panel.close_panel()
		return
	_gate_panel.visible = false
	_dungeon_panel.visible = false
	_codex_panel.visible = false
	_sandbag_panel.visible = false
	_fitness_panel.refresh(_me())
	_fitness_panel.open()


## 도감 단추. 열려 있으면 닫는다. 차원문·던전·헬스 창과 한 층이라 그 셋을 닫고 연다
func _toggle_codex() -> void:
	if _codex_panel.visible:
		_codex_panel.close_panel()
		return
	_gate_panel.visible = false
	_dungeon_panel.visible = false
	_fitness_panel.visible = false
	_sandbag_panel.visible = false
	_codex_panel.refresh(_me())
	_codex_panel.open()


## 문을 눌렀다. **거리와 상관없이 바로 창을 연다** (2026-09-18 요청: "포탈까지
## 안 걸어가도 클릭하면 UI 열리게"). 예전에는 문 밖에서 누르면 문 가운데로
## 걸어갔고, 들어서야 `gate` 이벤트가 창을 열었다 — 멀리서 한 번 누르고 기다려야
## 했다. 문 안으로 걸어 들어가도 창은 뜨지 않는다 — **누를 때만 연다** (2026-09-28).
## **이동하는 건 여전히 travel 요청이고 World 가 다시 본다**
func _on_gate_tapped() -> void:
	_target = Vector3.INF
	_target_mob = ""
	_marker.visible = false
	_open_gate()


## 던전 결과창 "확인" — 쓰러져 있으면 되살아나기(마을에서), 아니면 마을가기와 같은 `travel`
func _on_result_confirmed() -> void:
	if _am_dead():
		_transport.send(&"revive", {})
	else:
		_go_village()


## 시련의 탑 시계 줄 — World 가 준 던전 판(`ends_at` · `kills` · `need`)을 그린다. 결과가 나면 숨긴다.
## 샌드백 랭킹전도 같은 줄에 남은 시간 · 누적 피해를 적고, 카운트는 가운데 큰 글자로 (`_draw_sandbag_count`)
func _draw_trial_hud() -> void:
	if _trial_hud == null:
		return
	var trial: Dictionary = _transport.snapshot().get("dungeon", {})
	if str(trial.get("dungeon", "")) == "sandbag":
		_draw_sandbag_hud(trial)
		return
	if _sandbag_count != null:
		_sandbag_count.visible = false
	_trial_hud.visible = str(trial.get("dungeon", "")) == "trial" and str(trial.get("result", "")) == ""
	if not _trial_hud.visible:
		return
	var left := maxi(0, int(trial.get("ends_at", 0)) - Time.get_ticks_msec())
	_trial_hud.text = "남은 시간 %d초   처치 %d / %d" % [
		ceili(left / 1000.0), int(trial.get("kills", 0)), int(trial.get("need", 0))]


## "마을가기" — 마을 밖에서만 보인다. 존을 지을 때마다 다시 본다
func _refresh_home_button() -> void:
	if _home_button != null:
		_home_button.visible = _shown_zone != "" and _shown_zone != GameData.start_zone()


## "마을가기" 단추 — 차원문 창에서 마을을 고른 것과 같은 `travel` 요청이다 (World 가 다시 본다)
func _go_village() -> void:
	_on_gate_pick(GameData.start_zone())


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
	_refresh_home_button()
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
	_mob_swing_until.clear()
	# 이 존에서 쓰러졌던 자리의 묘비. _zone_node 밑이라 존을 떠나면 같이 사라지고, 돌아오면 다시 선다
	for tomb in _tombs:
		if str(tomb.zone) == zone_id:
			_zone_node.add_child(Tomb.create(tomb.x, _ground_y(tomb.x, tomb.z), tomb.z))

	var world_env := WorldEnvironment.new()
	world_env.environment = environment_for(env)
	_zone_node.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = float(env.get("sunIntensity", 2.7))
	sun.rotation_degrees = Vector3(-50, -35, 0)
	_zone_node.add_child(sun)

	# 바닥. 지형이 있는 존(마을 · 덤불숲)은 높낮이와 바닥 여러 장을 섞은 메시,
	# 없으면 평평한 한 장이다 → docs/features/world-zones.md "지형"
	_terrain = Terrain.build(zone_id)
	if _terrain != null:
		_zone_node.add_child(_terrain.mesh_instance(env))
	else:
		var ground := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(size, size)
		ground.mesh = plane
		ground.material_override = Ground.material_for(env, size)
		_zone_node.add_child(ground)


	# 차원문. 여기 들어가면 존이 바뀐다 (World._check_gate)
	var gate: Dictionary = zone.get("gate", {})
	if not gate.is_empty():
		var portal := Portal.create(gate, _ui_root.theme.default_font if _ui_root.theme != null else null)
		portal.position.y = _ground_y(portal.position.x, portal.position.z)
		_zone_node.add_child(portal)

	# NPC. 모델이 있는 look 은 바르코 모델이 대기 동작으로 서 있고, 없으면 기둥이다
	var npc_index := 0
	for npc in _transport.snapshot().get("npcs", []):
		var look := str(npc.get("look", ""))
		var rig := Rig.create(look, float(NPC_HEIGHTS.get(look, Rig.HUMAN_HEIGHT)))
		if rig != null:
			rig.position = Vector3(npc.x, _ground_y(npc.x, npc.z), npc.z)
			# 마을 가운데(스폰 0,0)를 본다. 모델 앞은 +Z 라 World 의 rot 규약과 같다
			rig.rotation.y = atan2(-float(npc.x), -float(npc.z))
			_zone_node.add_child(rig)
			# 다 같이 숨 쉬면 복제인간이다 — 사람마다 클립 중간 다른 자리에서 시작한다
			rig.play("Idle", 1.0, fmod(npc_index * 1.7, maxf(rig.clip_length("Idle"), 0.1)))
		else:
			var post := MeshInstance3D.new()
			var shape := CapsuleMesh.new()
			shape.radius = 0.35
			shape.height = 1.7
			post.mesh = shape
			var npc_mat := StandardMaterial3D.new()
			npc_mat.albedo_color = Color("#d8c48a") if npc.has("role") else Color("#b9b3a6")
			post.material_override = npc_mat
			post.position = Vector3(npc.x, _ground_y(npc.x, npc.z) + shape.height * 0.5, npc.z)
			_zone_node.add_child(post)
		npc_index += 1

		var plate := Label3D.new()
		plate.text = "%s\n%s" % [npc.get("name", ""), npc.get("title", "")]
		plate.font = _ui_root.theme.default_font
		plate.font_size = 64
		plate.pixel_size = 0.004
		plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		plate.no_depth_test = true
		plate.position = Vector3(npc.x, _ground_y(npc.x, npc.z) + 2.3, npc.z)
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
		node.position = Vector3(monster.x, _ground_y(monster.x, monster.z) + foot, monster.z)
		# 매 프레임 발밑 높이에 더한다 — 기둥은 원점이 몸 가운데다
		node.set_meta("foot", foot)
		_zone_node.add_child(node)
		_mob_nodes[monster.id] = node


## 누르고 있던 손을 떼거나 끄는 것은 UI 위에서 일어나도 받아야 한다 —
## `_unhandled_input` 은 UI 가 먹은 이벤트를 못 받아서, 창 위에서 떼면 계속 걷는다
func _input(event: InputEvent) -> void:
	if not _holding:
		return
	if event is InputEventMouseMotion:
		_hold_at = event.position
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_holding = false


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
		_holding = false
		# 죽어 있으면 화면을 눌러도 아무 일 없다 — 되살아나기는 사망 창(던전이면 결과창)의 "확인" 으로만
		if _am_dead():
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
			_holding = true
			_hold_at = event.position
			_stuck_at = Vector3.INF
			_set_target(hit)


## 걸어갈 바닥 점을 잡고 표시를 그 자리에 세운다.
##
## **이동 끝 너머를 눌렀으면 끝으로 당긴다** (2026-09-26). 마을은 언덕이 끝(±29)
## 너머까지 그려져서 거기를 누를 수 있는데, World 는 끝에서 멈추니 목표에
## 영영 못 닿아 제자리 뛰기를 했다. 고리도 실제로 설 자리에 둔다
func _set_target(hit: Vector3) -> void:
	var x := clampf(hit.x, -_half_size, _half_size)
	var z := clampf(hit.z, -_half_size, _half_size)
	hit = Vector3(x, _ground_y(x, z), z)
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
	_ring.follow(Vector3(mob.x, _ground_y(mob.x, mob.z), mob.z), float(mob.r), _last_delta)


## 몬스터 머리 위 체력 막대. **골라 둔 놈과 방금 때린 놈만** 보여 준다
## (2026-09-18 지시: "몬스터는 나한테 피격을 받은 경우거나 타겟팅 된 경우에만").
##
## 세우고 치우는 자리는 여기 한 군데다 — 고리와 같은 이유로, 죽는 길이 여럿이라
## 각자 지우게 두면 반드시 한 곳이 빠지고 **막대가 시체에 남는다.**
## 몬스터마다 매 프레임 한 번 불린다 (`_draw_state` 의 몬스터 고리 안).
## 얼음빛 덧칠 — 모두가 같이 쓴다 (맞을 때 붉히기와 같은 `material_overlay` 방식)
var _ice_overlay: StandardMaterial3D


## **빙결** — 판정이 `stun_look = "ice"` 로 세운 놈은 몸이 얼음빛으로 굳는다 (빙주각 빙결).
## 덧칠(`material_overlay`)을 입히고 동작을 멈춘다(`Rig.freeze` — 히트스톱과 같은 멈춤).
## **매 프레임 다시 본다** — 맞을 때 붉히기가 덧칠을 걷어 가면 다음 프레임에 도로 입힌다.
## 풀리면 얼음 덧칠만 걷는다 (붉히기 중이면 그건 두다)
func _tick_frozen(monster: Dictionary, node: Node3D) -> void:
	var frozen: bool = str(monster.get("state", "")) == "stun" \
		and str(monster.get("stun_look", "")) == "ice"
	var was: bool = node.get_meta(&"frozen", false)
	if not frozen and not was:
		return
	if _ice_overlay == null:
		_ice_overlay = StandardMaterial3D.new()
		_ice_overlay.albedo_color = Color(0.55, 0.85, 1.0, 0.7)
		_ice_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ice_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var meshes: Array = node.get_meta(&"meshes", [])
	if meshes.is_empty():
		meshes = HitFx.meshes_of(node)
		node.set_meta(&"meshes", meshes)
	for mesh in meshes:
		if not is_instance_valid(mesh):
			continue
		if frozen and mesh.material_overlay == null:
			mesh.material_overlay = _ice_overlay
		elif not frozen and mesh.material_overlay == _ice_overlay:
			mesh.material_overlay = null
	if frozen and node is Rig:
		# 한 프레임 조금 넘게만 세운다 — 풀리는 즉시 다시 움직인다
		(node as Rig).freeze(0.1)
	node.set_meta(&"frozen", frozen)


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
		Vector3(monster.x, _ground_y(monster.x, monster.z), monster.z),
		float(monster.hp) / maxf(1.0, float(monster.max_hp))
	)


## 화면의 한 점이 바닥의 어디인지
func _ground_point(screen: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.INF
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if _terrain != null:
		return _terrain.ray_hit(from, dir)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	return hit if hit != null else Vector3.INF


## 발밑 높이. 지형이 없는 존은 0 이다. **그리기만** 쓴다 — 판정은 평면에서 돈다
func _ground_y(x: float, z: float) -> float:
	return _terrain.height_at(x, z) if _terrain != null else 0.0


func _process(delta: float) -> void:
	_moving = false
	_last_delta = delta
	_send_input(delta)
	_draw_state()
	_draw_trial_hud()
	_tick_aoe()
	_tick_range(delta)
	_tick_learn_hold(delta)
	if _auto_spin != null and _auto_spin.visible:
		# PanelContainer 가 자식 크기를 칸에 맞춰 다시 잡는다 — 축은 그때마다 가운데로
		_auto_spin.pivot_offset = _auto_spin.size / 2.0
		_auto_spin.rotation += delta * SPIN_SPEED


## 눌러 둔 자리로 향하는 방향을 만들어 보낸다. **요청일 뿐이고 판정은 World 가 한다.**
## 쓰러진 자리에 묘비를 세우고 기억해 둔다 (`_tombs` — 저장하지 않는다). 존을 다시 지을 때도 세운다
func _plant_tomb() -> void:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty() or _zone_node == null:
		return
	var x := float(me.x)
	var z := float(me.z)
	_tombs.append({"zone": _shown_zone, "x": x, "z": z})
	_zone_node.add_child(Tomb.create(x, _ground_y(x, z), z))


func _am_dead() -> bool:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	return bool(me.get("dead", false))


func _send_input(delta: float) -> void:
	if _zone_node == null or _am_dead():
		return
	# 키보드가 쥐고 있으면 그게 먼저다. 누른 목표·쫓던 놈은 내려놓는다 — 골라 둔 놈은 그대로
	var keys := _key_dir()
	if keys != Vector2.ZERO:
		_target_mob = ""
		_target = Vector3.INF
		_holding = false
		_stuck_at = Vector3.INF
		_marker.visible = false
		_move(keys, delta)
		return
	if _target_mob != "":
		_chase_and_hit(delta)
		return
	# 누르고 있으면 그 화면 점 아래를 다시 잡는다. 캐릭터가 걸으면 카메라가 따라와서
	# 손가락을 가만히 둬도 바닥 점이 앞으로 밀린다 — 누르는 동안 계속 걷는다
	if _holding:
		var hit := _ground_point(_hold_at)
		if hit != Vector3.INF:
			_set_target(hit)
	if _target == Vector3.INF:
		return
	var me := _my_position()
	var to := Vector2(_target.x - me.x, _target.z - me.z)
	if to.length() <= STOP_DISTANCE or _stuck(me):
		_target = Vector3.INF
		_holding = false
		_stuck_at = Vector3.INF
		_marker.visible = false
		return
	_move(to.normalized(), delta)


## WASD 로 걸을 방향 (x, z). **화면 기준**이다 — W 는 화면 위쪽, D 는 화면 오른쪽.
## 카메라가 대각선으로 보므로 세계 축(±x, ±z)이 아니라 카메라 방향을 바닥에 눕혀 쓴다.
## 채팅 칸에 글을 쓰는 중이면 움직이지 않는다
func _key_dir() -> Vector2:
	if _camera == null or get_viewport().gui_get_focus_owner() is LineEdit:
		return Vector2.ZERO
	var up := int(Input.is_physical_key_pressed(KEY_W)) - int(Input.is_physical_key_pressed(KEY_S))
	var right := int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
	if up == 0 and right == 0:
		return Vector2.ZERO
	var basis := _camera.global_transform.basis
	var fwd := Vector2(-basis.z.x, -basis.z.z).normalized()
	var side := Vector2(basis.x.x, basis.x.z).normalized()
	return (fwd * up + side * right).normalized()


## 걷는데 발이 안 나가나. **막힌 채 이동 입력을 계속 보내면 자동 사냥이 영영 쉰다** —
## 입력이 올 때마다 World 가 "사람이 몰고 있다"(`manual_until`)로 잡기 때문이다.
## 몬스터에 둘러싸인 채 바깥을 누르면 캐릭터가 그 자리에 서서 아무것도 안 했다.
## 옆으로 미끄러지는 것도 움직인 것이다 — 목표까지 거리가 아니라 **발이 옮겨 간 거리**로
## 잰다 (누르고 있으면 목표가 매 프레임 바뀌어서 거리로는 못 잰다)
func _stuck(me: Vector3) -> bool:
	var now := Time.get_ticks_msec()
	if _stuck_at == Vector3.INF or me.distance_to(_stuck_at) >= STUCK_GAIN:
		_stuck_at = me
		_stuck_since = now
		return false
	return now - _stuck_since >= STUCK_MS


## 눌러 둔 몬스터에게 걸어가서 사거리에 들면 계속 친다.
## 때릴 수 있는지는 **World 가 다시 본다** — 여기서 보내는 건 요청일 뿐이다.
##
## **자동 사냥을 켜 뒀으면 `strike` 로 보내 스킬부터 쓴다** (2026-09-26 요청). 쫓는 동안은
## 이동 입력 때문에 자동 사냥이 쉬어서, `attack` 만 보내면 평타만 나갔다. 붙는 도중에도
## 매 프레임 보낸다 — 원거리기는 그 스킬 사거리에 들자마자 나가야 한다
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
	var auto := bool(me.get("auto", false))
	if to.length() > reach:
		_move(dir, delta)
		# 끈 사람도 보낸다 — 멀면 판정이 날라차기로 붙인다(`World._lunge`). 가까우면 걸어서 붙는다
		_transport.send(&"strike", {"id": _target_mob})
		return
	# 사거리 안이다. 제자리에서 그쪽을 보고(dt 0) 친다
	_move(dir, 0.0)
	if auto:
		_transport.send(&"strike", {"id": _target_mob})
	else:
		_transport.send(&"attack", {})


func _move(dir: Vector2, delta: float) -> void:
	_seq += 1
	_moving = delta > 0.0
	_transport.send(&"input", {"seq": _seq, "dx": dir.x, "dz": dir.y, "dt": delta})


## 동작을 건다. 실제로 트는 건 다음 `_play_player_clip` 이다 — 이벤트는 그리기 전에 온다
## 평타 넷 중 무엇을 틀까. **초당 4타 미만**이면 한 대마다 치고 내려와 선다(`KICK_FULL`).
## 그보다 빠르면 첫 대는 발을 들어 올리며 치고(`KICK_IN`), 이어지는 대는 든 발로 바깥(`KICK_A`)·
## 안쪽(`KICK_B`)을 번갈아 친다. 이어지는지는 **지난 대가 한 간격의 1.5배 안이었나**로 본다 —
## 멈췄다 다시 치면 첫 대부터 (멈추면 든 발은 대기로 섞이며 내려온다)
func _kick_clip(interval_ms: int) -> String:
	var now := Time.get_ticks_msec()
	var chained := now - _last_kick_at <= int(interval_ms * 1.5)
	_last_kick_at = now
	if 1000.0 / maxf(1.0, interval_ms) < KICK_CHAIN_HITS:
		return KICK_FULL
	if not chained:
		_kick_to_a = true
		return KICK_IN
	var clip := KICK_A if _kick_to_a else KICK_B
	_kick_to_a = not _kick_to_a
	return clip


func _start_move(clip: String, speed := 1.0) -> void:
	if not _player is Rig:
		return
	var rig: Rig = _player
	if not rig.has_clip(clip):
		return
	_move_clip = clip
	_move_fresh = true
	_move_speed = speed
	_move_until = Time.get_ticks_msec() + int(rig.clip_length(clip) * 1000.0 * MOVE_CEILING / speed)


## 맞은 동작을 건다 — 틀어도 되는 때만 (`HIT_CLIP` 위 설명)
func _start_hit() -> void:
	if _moving:
		return
	if _move_clip != "" and _move_clip != HIT_CLIP:
		return
	_start_move(HIT_CLIP)


## 죽음 > 동작(평타·스킬·맞음) > 옛 공격 > 달리기 > 대기 순으로 고른다.
##
## **동작은 끝까지 튼다.** 경직(0.4초)이 풀려도 서 있으면 마저 튼다 — 스킬 동작은
## 1초 남짓이라 경직에 맞춰 자르면 내리친 주먹이 땅에 닿자마자 대기 자세로 튄다.
## 경직이 풀린 뒤 **움직이면 그 자리에서 끊고** 달리기로 섞어 넘어간다
## (웹 클라이언트의 `ATTACK_CUT_SPEED` 와 같은 생각이다).
##
## 아래는 새 동작이 없는 모델에서 쓰는 옛 길이다.
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
		_move_clip = ""
		rig.play("Death")
		return
	var now := Time.get_ticks_msec()
	if _move_clip != "":
		if _move_fresh:
			_move_fresh = false
			# 섞는 시간도 배속만큼 줄인다 — 7배로 찰 때 0.06초를 섞으면 발이 다 뻗기 전에 다음 대가 온다
			rig.replay(_move_clip, _move_speed, MOVE_BLEND / maxf(_move_speed, 1.0))
			return
		var cut := _moving and now >= _swing_until
		# 끝은 **클립이 실제로 다 돌았는지**로 본다. 시계(`_move_until`)로 재면 히트스톱이
		# 멈춘 만큼 덜 돈 채 잘린다 — 여러 마리에게 맞으며 스킬을 쓰면 1초 동작이 0.7초에서
		# 끊겼다 (2026-09-24). 시계는 클립이 멎지 않을 때를 막는 넉넉한 상한으로만 쓴다
		var at := rig.position_in(_move_clip)
		var playing := at >= 0.0 and at < rig.clip_length(_move_clip) - 0.01
		if playing and now < _move_until and not cut:
			return
		_move_clip = ""
		# 옛 `Attack` 길로 떨어지지 않게 — 동작이 경직을 이미 다 덮었다
		_swing_until = mini(_swing_until, now)
		if _moving:
			rig.play("Run", _run_rate(me), 0.0, false, MOVE_OUT_BLEND)
		else:
			rig.play("Idle", 1.0, 0.0, false, MOVE_OUT_BLEND)
		return
	if now < _swing_until:
		rig.play("Attack", 1.6, 0.8)
		return
	if _moving:
		rig.play("Run", _run_rate(me))
	else:
		rig.play("Idle")


## 달리기 클립 배속 — 이동 속도만큼 빨리 튼다 (경공 +20% 면 1.2배, 2026-09-30 요청:
## "이동 속도에 맞춰서 애니메이션도 빠르게 재생해"). 안 그러면 몸이 빨라진 만큼 발이 미끄러진다
func _run_rate(me: Dictionary) -> float:
	return 1.0 + maxf(float(me.get("stats", {}).get("moveSpeed", 0.0)), 0.0)


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
	var walked_to := Vector3(me.x, _player_y + _ground_y(me.x, me.z), me.z)
	if not _moving and not zone_changed and _last_delta > 0.0:
		var step := Vector2(
			walked_to.x - _player.position.x, walked_to.z - _player.position.z
		).length()
		_moving = step / _last_delta > RUN_SPEED_EPS

	_player.position = walked_to
	HitFx.apply_react(_player, _last_delta)
	_player.rotation.y = me.rot
	_play_player_clip(me)
	_wear_weapon(me)

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
		node.position.y = float(node.get_meta("foot", 0.0)) + _ground_y(monster.x, monster.z)
		HitFx.apply_react(node, _last_delta)
		_tick_frozen(monster, node)
		node.rotation.y = monster.get("rot", 0.0)
		if node is Rig:
			var state := str(monster.get("state", "idle"))
			# 휘두르기는 **창 끝까지 무조건** 튼다 — 사람이 한 발 물러난 것 때문에
			# 끊으면 휘두르다 만 채로 동작이 사라진 것으로만 보인다
			if Time.get_ticks_msec() < int(_mob_swing_until.get(monster.id, 0)):
				node.play("Attack", 1.0, MOB_SWING_FROM)
			elif state == "chase":
				node.play("Run")
			elif state == "patrol":
				# 순찰은 걷는 것이다. 걷기 클립이 없으니 달리기를 반 배속으로 돌린다
				node.play("Run", 0.5)
			else:
				# 사거리 안에서 다음 한 대를 기다리는 동안(`attack`)도 선다
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
			Vector3(me.x, _ground_y(me.x, me.z), me.z), float(me.hp) / maxf(1.0, float(me.stats.maxHp))
		)

	_refresh_status(me)
	_refresh_bar(me)
	_refresh_potion(me)
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


## 낀 무기를 주먹 소켓에 보인다 — 무기를 바꾸면 모델이 바뀌고, 벗으면 맨주먹이다.
## 등급이 곧 생김새다 (무기는 등급마다 하나). **강화 수치만큼 주먹 기운이 커진다**.
## 등급·강화가 같으면 Rig 가 다시 짓지 않는다
func _wear_weapon(me: Dictionary) -> void:
	if not _player is Rig:
		return
	var weapon: Dictionary = me.get("equipped", {}).get("weapon", {})
	if weapon.is_empty():
		(_player as Rig).set_weapon(0)
	else:
		(_player as Rig).set_weapon(int(weapon.get("grade", 1)), int(weapon.get("enhance", 0)))
	# 갑옷·투구·신발 — 그 부위 스킨을 등급으로 갈아입는다 (`Armor`)
	for slot in Armor.SLOTS:
		var item: Dictionary = me.get("equipped", {}).get(slot, {})
		(_player as Rig).set_gear(slot, 0 if item.is_empty() else int(item.get("grade", 1)))


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
	var fx := HitFx.spawn(_fx, at, payload, font, body)
	if body != null and not bool(payload.get("heal", false)):
		fx.flash_body(body)

	# 회복은 맞은 것이 아니다
	if on_me and not bool(payload.get("heal", false)):
		var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
		var max_hp := float(me.get("stats", {}).get("maxHp", 100))
		# 최대 체력의 4분의 1을 한 번에 맞으면 제일 진하다
		_hurt.hit(float(payload.get("amount", 0)) / maxf(1.0, max_hp * 0.25))

	# 평타만 소리를 낸다 — 스킬 피격(`skill` 이 있음)·내가 맞음·회복은 조용하다
	if not on_me and str(payload.get("skill", "")) == "" and _hit_sound.stream != null:
		_hit_sound.play()

	_feel_hit(payload, on_me, body)


## 몬스터가 휘두르기 시작했다(`mobSwing`). 첫 할퀴기 구간을 **처음부터 다시** 튼다 — 서버가 세워 두는
## 시간(`monsterSwingMs`)만큼만. 범위 공격이 터진 것도 여기로 온다 (보스는 그 뒤 선다).
## **피해 알림에서 틀지 않는다** (2026-09-30) — 피해는 손이 닿는 순간(클립 1.0초) 오므로 거기서
## 0.8초부터 틀면 숫자가 뜬 뒤에 할퀴기가 나온다
func _swing_mob(id: String) -> void:
	var node: Node3D = _mob_nodes.get(id, null)
	if id == "" or not node is Rig:
		return
	var swing_ms := int(GameData.combat().get("monsterSwingMs", 650))
	_mob_swing_until[id] = Time.get_ticks_msec() + swing_ms
	(node as Rig).play("Attack", 1.0, MOB_SWING_FROM, true)


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
	# **공격·스킬 동작 중에 맞으면 내 몸은 안 세운다.** 여러 마리에게 맞으면 0.07초씩
	# 연달아 걸려 동작이 뚝뚝 끊긴다 (2026-09-24). 맞은 건 붉어짐·흔들림·퍼짐으로 안다.
	# 맞음 동작(`Hit`)과 공격이 이기는 규칙(`HIT_CLIP` 위)과 같은 생각이다
	var busy := on_me and _move_clip != "" and _move_clip != HIT_CLIP
	# **내가 때렸으면 멈춤을 공속만큼 줄인다** (2026-09-29) — 초당 10번 차는데 한 대에 0.045초씩
	# 멈추면 시간의 45% 가 멈춰 있어 발차기가 뚝뚝 끊긴다. 한 대 간격에서 차지하는 몫을 지킨다
	var stop := float(feel.stop)
	if not on_me:
		stop /= 1.0 + maxf(float(_me().get("stats", {}).get("attackSpeed", 0.0)), 0.0)
	if not busy:
		HitFx.hitstop(body, stop)
	HitFx.hitstop(attacker, stop)
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
	if not (skill in ["rising_kick", "thunder_fall", "sky_breaker", "frost_pillar", "ki_burst", "nova_fist", "crush_fist"]):
		return
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty():
		return
	var here := Vector3(me.x, _ground_y(me.x, me.z), me.z)
	if skill == "thunder_fall":
		# 강화는 판정이 이벤트에 실어 보낸다 — "기절" 이면 붉은 번개, "범위" 면 좌우로
		# 두 번 더. 둘은 따로 논다 (범위만 붙었으면 색은 그대로)
		var upgrades: Array = payload.get("upgrades", [])
		LightningFx.bolt(_fx, here, float(me.rot), "stun" in upgrades, "wide" in upgrades)
	elif skill == "sky_breaker":
		# 강화 — "진폭" 이면 모래 토네이도, "균열 지대" 면 진흙 소용돌이 (따로 논다)
		var quake_up: Array = payload.get("upgrades", [])
		QuakeFx.slam(_fx, here, float(me.rot), "wide" in quake_up, "zone" in quake_up)
		_camera.shake(QuakeFx.SHAKE, QuakeFx.SHAKE_TIME)
	elif skill == "frost_pillar":
		# 강화 — "파쇄" 면 기둥이 부서지고, "빙결" 이면 짙은 청색 (따로 논다)
		var ice_up: Array = payload.get("upgrades", [])
		IceFx.burst(_fx, here, float(me.rot), "shatter" in ice_up, "freeze" in ice_up)
		_camera.shake(IceFx.SHAKE, IceFx.SHAKE_TIME)
	elif skill == "ki_burst":
		# 강화 — "기폭" 이면 소용돌이가 앞 한 점으로 모여 터지고, "연파" 면 푸른 파도가 한 번
		# 더 나간다 (따로 논다 — 기폭은 첫 파도만). 흔들림도 터질 때·두 번째 파도에 한 번씩
		var ki_up: Array = payload.get("upgrades", [])
		var ki_rot := float(me.rot)
		KiFx.burst(_fx, here, ki_rot, false, "detonate" in ki_up)
		_camera.shake(KiFx.SHAKE, KiFx.SHAKE_TIME)
		if "twin" in ki_up:
			get_tree().create_timer(KiFx.TWIN_DELAY).timeout.connect(_ki_twin.bind(here, ki_rot))
		if "detonate" in ki_up:
			get_tree().create_timer(KiFx.DETONATE_AT).timeout.connect(
				_camera.shake.bind(KiFx.BLAST_SHAKE, KiFx.BLAST_SHAKE_TIME))
	elif skill == "nova_fist":
		# 누르자마자 띄운다 — 끓다가 `EXPLODE` 에 터진다. 흔들림도 그때다.
		# 강화 — "과부하" 면 굵고 흰 폭발, "연쇄 폭발" 이면 `CHAIN` 초 뒤 작게 한 번 더 (따로 논다)
		var nova_up: Array = payload.get("upgrades", [])
		var chain := "chain" in nova_up
		NovaFx.burst(_fx, here, float(me.rot), "overload" in nova_up, chain)
		get_tree().create_timer(NovaFx.EXPLODE).timeout.connect(
			_camera.shake.bind(NovaFx.SHAKE, NovaFx.SHAKE_TIME))
		if chain:
			get_tree().create_timer(NovaFx.EXPLODE + NovaFx.CHAIN).timeout.connect(
				_camera.shake.bind(NovaFx.CHAIN_SHAKE, NovaFx.SHAKE_TIME))
	elif skill == "crush_fist":
		# 누르자마자 띄운다 — 기를 모으다가 `PUNCH` 에 터진다. 흔들림도 그때다
		CrushFx.burst(_fx, here, float(me.rot))
		get_tree().create_timer(CrushFx.PUNCH).timeout.connect(
			_camera.shake.bind(CrushFx.SHAKE, CrushFx.SHAKE_TIME))
	else:
		# 강화 — "연타" 면 두 번 더 긁고 보라다. "위력"(`wide`)은 피해만 키워서 이펙트가 그대로다
		var claw_up: Array = payload.get("upgrades", [])
		SkillFx.claw(_fx, here, float(me.rot), "combo" in claw_up)


## 파천장 "연파" 의 두 번째 파도 — 첫 파도와 같은 자리·보는 쪽에서 푸르게 (`_show_skill`).
## 그 사이 존을 옮겼으면 띄우지 않는다
func _ki_twin(at: Vector3, facing: float) -> void:
	if _fx == null or not is_instance_valid(_fx):
		return
	KiFx.burst(_fx, at, facing, true)
	_camera.shake(KiFx.TWIN_SHAKE, KiFx.SHAKE_TIME)


## 보스 범위 공격 예고 원.
##
## 바깥 테두리는 **터질 자리와 크기**를 그대로 보여 주고(판정과 같은 반지름),
## 안쪽 원이 차오르며 남은 시간을 알린다. 다 차면 터진다 — 그 전에 테두리
## 밖으로 나가면 안 맞는다 (`World._burst_aoe` 가 원으로 다시 자른다).
func _show_aoe(payload: Dictionary) -> void:
	if _zone_node == null:
		return
	var radius := float(payload.get("radius", 7.0))
	var here := Vector3(payload.get("x", 0.0), 0.0, payload.get("z", 0.0))
	here.y = _ground_y(here.x, here.z) + 0.06

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
	# 사망 창은 **상태로** 띄운다 — `died` 사건 없이 죽은 채 저장된 캐릭터로 들어와도 뜬다.
	# 던전에서 쓰러졌으면 결과창("실패")이 대신 뜬다
	_death_panel.visible = bool(me.get("dead", false)) and not _dungeon_result.visible
	_redraw_char(me)
	_fitness_panel.refresh(me)
	_codex_panel.refresh(me)
	var max_hp := maxf(1.0, float(me.stats.maxHp))
	_hp_bar.max_value = max_hp
	_hp_bar.value = float(me.hp)
	_skill_dot.visible = Skills.passive_learnable(str(me.job), int(me.level), me.get("passives", {}))
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


## 물약 칸 — 쿨타임(어둠·바늘·남은 초)과 아래 배지(저절로 마시는 HP %)를 스냅샷으로 그린다
func _refresh_potion(me: Dictionary) -> void:
	var left := int(me.get("potion_ready_at", 0)) - Time.get_ticks_msec()
	var cooling := left > 0
	var cool: TextureProgressBar = _potion_cell.find_child("cool", true, false)
	var edge: CoolEdge = _potion_cell.find_child("edge", true, false)
	var secs: Label = _potion_cell.find_child("secs", true, false)
	cool.visible = cooling
	edge.visible = cooling
	if cooling:
		var total := maxf(float(GameData.combat().get("potionCooldownMs", 10000)), float(left))
		cool.value = left / total
		edge.ratio = cool.value
		edge.queue_redraw()
		secs.text = "%.1f" % (left / 1000.0) if left < 1000 else str(ceili(left / 1000.0))
	else:
		secs.text = ""
	if _potion_cooling and not cooling:
		_flash_ready(_potion_cell)
	_potion_cooling = cooling
	var pct := int(me.get("potion_pct", 0))
	_potion_cell.find_child("badge", true, false).text = "HP %d%%" % pct if pct > 0 else "자동 끔"
	if _potion_panel.visible:
		_potion_pct_label.text = "HP %d%% 이하" % pct if pct > 0 else "자동 끔"
		# 신호 없이 옮긴다 — 신호를 내면 받은 값을 다시 보내는 되먹임이 된다
		_potion_slider.set_value_no_signal(pct)


## 소리 설정 창 — 전체 볼륨을 -/+ (10 씩)와 슬라이더로 고른다. 0 이 "소리 끔".
## 판정이 아니라 기기 설정이라 서버에 보내지 않고 `SoundSettings` 가 바로 걸고 저장한다
func _build_sound_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(center)
	_sound_panel = _window_panel()
	_sound_panel.name = "sound_panel"
	center.add_child(_sound_panel)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_constant_override("separation", 12)
	_sound_panel.add_child(side)
	_stone_title(side, "소리 설정", 20, "ui_icon_settings")
	side.add_child(_inv_label("전체 볼륨 — 0 이면 소리를 끈다", 14, INV_TEXT))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	side.add_child(row)
	# ASCII "-" — 빼기 기호(U+2212)는 한글 폰트 부분집합에 없다 (물약 창과 같다)
	var down := _inv_button("-", _sound_step.bind(-1))
	down.name = "sound_down"
	row.add_child(down)
	_sound_label = _inv_label("", 20, INV_GOLD_HI)
	_sound_label.custom_minimum_size = Vector2(110, 0)
	_sound_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_sound_label)
	var up := _inv_button("+", _sound_step.bind(1))
	up.name = "sound_up"
	row.add_child(up)

	_sound_slider = HSlider.new()
	_sound_slider.name = "sound_slider"
	_sound_slider.min_value = 0
	_sound_slider.max_value = SoundSettings.MAX
	_sound_slider.step = SoundSettings.STEP
	_sound_slider.tick_count = SoundSettings.MAX / SoundSettings.STEP + 1
	_sound_slider.ticks_on_borders = true
	_sound_slider.custom_minimum_size = Vector2(0, 32)
	_sound_slider.value_changed.connect(func(value: float) -> void: _set_sound(roundi(value)))
	side.add_child(_sound_slider)
	_show_sound(SoundSettings.volume())


func _toggle_sound_panel() -> void:
	_sound_panel.visible = not _sound_panel.visible
	if _sound_panel.visible:
		_sound_panel.get_parent().move_to_front()
		_show_sound(SoundSettings.volume())


func _sound_step(dir: int) -> void:
	_set_sound(SoundSettings.volume() + dir * SoundSettings.STEP)


func _set_sound(value: int) -> void:
	_show_sound(SoundSettings.set_volume(value))


## 글자와 손잡이를 건 값에 맞춘다 — 손잡이는 신호 없이 (신호를 내면 다시 거는 되먹임이 된다)
func _show_sound(value: int) -> void:
	_sound_label.text = "%d%%" % value if value > 0 else "소리 끔"
	_sound_slider.set_value_no_signal(value)


func _drink_potion() -> void:
	_transport.send(&"potion", {})


## 물약 설정 창 — 저절로 마실 HP % 를 −/+ 로 고른다. 값은 판정(`World.set_potion_pct`)이
## 자르고 저장한다. 창은 스냅샷(me.potion_pct)만 보고 글자를 바꾼다
func _build_potion_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(center)
	_potion_panel = _window_panel()
	_potion_panel.name = "potion_panel"
	center.add_child(_potion_panel)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_constant_override("separation", 12)
	_potion_panel.add_child(side)
	_stone_title(side, "물약 설정", 20, "ui_icon_potion")
	side.add_child(_inv_label("HP 가 이만큼 떨어지면 물약을 저절로 마신다", 14, INV_TEXT))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	side.add_child(row)
	# ASCII "-" 다 — 빼기 기호(U+2212)는 한글 폰트 부분집합에 없어 **빈 단추로 나왔다** (2026-09-26 지적)
	var down := _inv_button("-", _potion_step.bind(-1))
	down.name = "potion_down"
	row.add_child(down)
	_potion_pct_label = _inv_label("", 20, INV_GOLD_HI)
	_potion_pct_label.custom_minimum_size = Vector2(110, 0)
	_potion_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_potion_pct_label)
	var up := _inv_button("+", _potion_step.bind(1))
	up.name = "potion_up"
	row.add_child(up)

	# 슬라이더로도 고른다 (2026-09-26 요청). 끌면 칸(10%p)마다 판정에 보내고,
	# 판정이 자른 값이 스냅샷으로 돌아오면 `_refresh_potion` 이 손잡이를 거기 맞춘다
	_potion_slider = HSlider.new()
	_potion_slider.name = "potion_slider"
	_potion_slider.min_value = 0
	_potion_slider.max_value = int(GameData.combat().get("potionAutoMax", 90))
	_potion_slider.step = int(GameData.combat().get("potionAutoStep", 10))
	_potion_slider.tick_count = int(_potion_slider.max_value / _potion_slider.step) + 1
	_potion_slider.ticks_on_borders = true
	_potion_slider.custom_minimum_size = Vector2(0, 32)
	_potion_slider.value_changed.connect(
		func(value: float) -> void: _transport.send(&"potionPct", {"pct": roundi(value)})
	)
	side.add_child(_potion_slider)

	var rules := GameData.combat()
	side.add_child(_inv_label(
		"쿨타임 %d초 · 최대 HP %d%% 회복 · 칸을 누르면 바로 마신다" % [
			int(rules.get("potionCooldownMs", 10000)) / 1000,
			roundi(float(rules.get("potionHealRatio", 0.3)) * 100.0),
		],
		12, INV_GOLD,
	))


func _toggle_potion_panel() -> void:
	_potion_panel.visible = not _potion_panel.visible
	if _potion_panel.visible:
		_potion_panel.get_parent().move_to_front()
		_refresh_potion(_me())


## −/+ 한 번 — 설정 폭(10%p)만큼. 0 아래로 내리면 "자동 끔"
func _potion_step(dir: int) -> void:
	var rules := GameData.combat()
	var step := int(rules.get("potionAutoStep", 10))
	var pct := clampi(int(_me().get("potion_pct", 0)) + dir * step, 0, int(rules.get("potionAutoMax", 90)))
	_transport.send(&"potionPct", {"pct": pct})


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
## 파란 고리는 **눌러 둔 자리만** 가리킨다. 자동 사냥의 앵커는 그리지 않는다
## (2026-09-28 요청) — 켜는 순간 발 밑에 떠서 클릭 이펙트로 읽혔고, 마을처럼
## 잡을 것이 없는 곳에서는 고리만 뜬 채 서 있는 것처럼 보였다
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
## 반경만 보면 몇 마리가 걸렸는지 모른다 (명수 상한은 없다 — 안에 들면 다 맞는다)
func _show_skill_range(payload: Dictionary) -> void:
	if _zone_node == null:
		return
	_range_marks.append(SkillRange.show_cast(_zone_node, payload))
	_range_label.text = "%s  %.1fm · %d° · %d 마리" % [
		Skills.all().get(str(payload.get("skill", "")), {}).get("name", "스킬"),
		float(payload.get("reach", 0.0)),
		roundi(rad_to_deg(float(payload.get("arc", 0.0)))),
		int(payload.get("hits", 0)),
	]
