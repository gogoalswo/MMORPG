# 샌드백 랭킹전

## 무엇

누가 더 센 피해를 넣는지 겨루는 콘텐츠. 메뉴 판의 **"샌드백"** 단추 → 입장 창 → **입장** 하면 캐릭터와
샌드백이 나란히 서 있고, **3초 카운트** 뒤 **15초 동안** 샌드백에 넣은 피해를 더한다. 그 주의 **최고 기록 한 판**으로
순위를 매기고, **월요일 0시(한국)** 에 지난주 순위대로 **옐로우 크리스탈**(3차 옵션 재료)을 준다.

2026-10-02 요청: "누가 더 가장 쎈 데미지를 넣었는지 겨루는 컨텐츠 … 샌드백 랭킹전. 맵 입장하면 캐릭터와 샌드백이
나란히 서 있고, 3초 카운트를 세. 그리고 15초 동안 얼마만큼 데미지를 입히는지 누적해서 랭킹에 따라 보상을 지급".
갈래는 사용자가 골랐다 — 입장은 **HUD 별도 단추**, 정산은 **매주**, 보상은 **"3차 옵션 재료 만들자 / 옐로우 크리스탈"**,
샌드백은 **바르코로 새로**.

```
 메뉴 판 [샌드백] ─▶ ┌ [샌드백] 샌드백 랭킹전 ─────────── X ┐
                     │ 15초 동안 샌드백에 넣은 피해를 겨룹니다. │
                     │ 주간 보상 — 옐로우 크리스탈            │
                     │  1위 x30   2위 x25   3위 x20  4~10위 x15 … │
                     │ 이번 주 순위 (위 50명, 굴림)           │
                     │ 내 기록 12,345 · 2위 / 8명   [ 입장 ] │
                     │ 정산까지 3일 5시간                     │
                     └───────────────────────────────────────┘
 입장 ─▶  (나)  [샌드백]        가운데 큰 글자 3 · 2 · 1 · 시작!   (물약·자동사냥 칸 없음)
          시작! 부터 누르지 않아도 저절로 친다 (자동사냥)
          시계 줄 "남은 시간 12초   누적 피해 8,420"
 15초 ─▶ 결과창 "샌드백 랭킹전" · 큰 글자 넣은 피해 · "이번 주 최고 N  새 기록!" · 확인 → 마을  (보상 칸 없음)
```

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/sandbag.ts` | **표.** 존(`SANDBAG_ZONE_DEF`) · 카운트 3 · 재는 시간 15 · 자리 둘 · 샌드백 종(`SANDBAG_KIND`, `dummy`) · 주 번호(`sandbagWeek`) · 날 번호(`sandbagDay`) · 날짜별 기록 7일(`SANDBAG_HISTORY_DAYS`) · 순위 보상(`SANDBAG_REWARDS`) |
| `packages/shared/src/sandbag.test.ts` | 3초 → 15초 · 과녁 하나 · 사거리 안 · 주 경계(월 0시 KST) · 날 경계(0시 KST) · 보상 줄 빈틈 없음 |
| `packages/shared/src/zones.ts` | `ZONES` 에 샌드백 존을 넣는다 |
| `scripts/export-shared.mjs` | `zones.json` 의 `sandbag`(규칙) · `monsters.json` 의 `kinds.sandbag`(몬스터 60종 밖에서 붙인다) |
| `godot/world/sandbag.gd` | `Sandbag` — 표 읽기 · `week` · `week_end` · `day` · `add_day`(날짜별 기록 얹기 · 7일 넘은 날 버리기) · `day_label` · `reward` · `reward_label` |
| `godot/world/world.gd` | **판** — `_start_sandbag`(존을 열 때) · `input_move`(샌드백 존이면 안 걷는다) · `_counting_down`(평타·스킬 막기) · `_drive_sandbag_auto`(재는 동안 자동사냥 켜기) · `_count_sandbag_damage`(`_hit_monster` 에서) · `_finish_sandbag`(시간 끝 → 기록 · 결과) · `_check_sandbag_week`(로컬 정산) · `join` 이 샌드백을 보고 서게 |
| `godot/world/ledger.gd` | **장부** — `sandbag` 칸 `{week, best, unpaid?, days?}` · `sandbag_record` · `sandbag_close_week(순위)` · `sandbag_pay` · `sandbag_day` |
| `godot/server/ledger_server.gd` | **서버** — `OPS.sandbag_record` · `_check_sandbag`(들어온 지 18초 · 한 판 한 번 · 상한) · `_sandbag_board`(이번 주) · `_ranks_of`(닫힌 주를 파일로 굳힘) · `_settle_sandbag`(hello · op 마다) · `_sandbag_rank`(내 `days` · `today` 도 싣는다) |
| `godot/server/kill_check.gd` | `max_damage` — 처치 시간과 같은 식으로 "15초에 넣을 수 있는 피해의 상한" |
| `godot/server/account_store.gd` | `find_sandbag_ranks` · `write_sandbag_ranks` — `sandbag/<주>.json` |
| `godot/net/server_ledger.gd` · `local_transport.gd` | `ask_sandbag_rank` / `sandbag_ranked` · 서버가 없으면 `_local_sandbag_board`(나 하나) |
| `godot/game/game.gd` | 메뉴 칸 "샌드백" · `_refresh_sandbag_dock`(샌드백 존에서 물약·자동사냥 칸 숨김) · `_build_sandbag_panel`(전체 화면) · `_toggle_sandbag` · `_fill_sandbag` · `_fill_sandbag_days`(날짜별 기록) · `_on_sandbag_enter` · `_draw_sandbag_hud`(가운데 카운트 · 시계 줄) · 이벤트 `sandbagRank` · `sandbagRecord` · `sandbagReward`(채팅) |
| `godot/game/dungeon_result.gd` | `_show_sandbag`(보상 칸을 숨긴다 — `_show_rewards(false)`) · `show_sandbag_best` · `comma` — 결과창을 같이 쓴다 |
| `godot/game/rig.gd` | `FILES.sandbag` → `varco_sandbag.glb` (클립 없음) |
| `public/assets/models/varco_sandbag.glb` | 바르코 모델 (원화 → 3D, **원점 바닥**, 텍스처 1024). 주소는 `fetch-assets.sh` |
| `public/assets/icons/ui_icon_sandbag.png` | 메뉴 단추 그림 (HUD 아이콘 기준 프롬프트 그대로, 세 장 중 둘째) |
| `godot/tests/sandbag_test.gd` | 존 · 카운트 중 막힘 · 걷기 막힘(카운트 · 재는 동안 · 자동사냥 안 꺼짐) · 끝나면 저절로 침 · 결과 뒤 멈춤 · 센 피해 = 맞은 피해 · 안 죽고 안 움직임 · 결과 한 번 · 낮은 기록은 최고를 안 덮음 · 로컬 주 정산(1위 30개 · 한 번만 · 가방 꽉 차면 남겼다 준다) · 날짜별 기록(하루 최고 · 다음 날 · 주 정산에도 남음 · 7일 넘으면 버림 · 날짜 글자) · 저장 · 옐로우 크리스탈 3차 · 서버(18초 · 상한 · 한 번 · 순위 · 굳힌 순위로 정산 · 새 주 비움) |
| `godot/tests/ui_test.gd` | `_case_sandbag` — 메뉴 → 창(전체 화면 · 설명 한 줄 · 보상 일곱 줄 · 기록 없음 · 100줄이면 굴린다) → 입장 → 카운트 "3" · 물약·자동사냥 칸 숨김 → 누적 피해 → 결과창(보상 칸 없음) → 다시 열면 1위 · 날짜별 기록 맨 위가 방금 기록 → 확인 → 마을 · 글자가 폰트에 있나 |

## 규칙

### 판 — 3초 카운트 → 15초 ★

- 존을 열면(`World.open` → `_start_run` → `_start_sandbag`) `starts_at = 지금 + 3초`, `ends_at = starts_at + 15초`.
- **카운트 동안은 평타·스킬이 막힌다**(`attack`·`cast` 머리의 `_counting_down`).
- **샌드백 존에서는 판 내내 걷지 못한다** (2026-10-02 요청 "샌드백 입장하면 이동도 내가 못 하게 막아"). `input_move` 가
  존이 샌드백이면 순번만 갱신하고 돌려보낸다 — `_take_manual` 보다 앞이라 조이스틱을 밀어도 자동사냥이 안 꺼진다.
  자동사냥은 `input_move` 를 거치지 않고 걷지만 샌드백이 사거리 안이라 걸을 일이 없다(평타에 실린 짧은 전진 0.07m 는 그대로다).
  처음엔 "걷기는 된다" 였다.
- **카운트가 끝나면 저절로 친다** (2026-10-02 요청 "물약이랑 자동사냥 버튼 없애고, 카운트 끝나면 자동으로 공격하도록").
  `step` 의 `_drive_sandbag_auto` 가 재는 동안 매 틱 자동사냥(`set_auto`)을 켠다 — 평소 자동사냥과 같은 `_drive_auto`
  라 스킬 순서·평타·날라차기가 그대로다. 결과가 나면 `_finish_sandbag` 이 끄고, 존을 옮기면 `join` 이 끈다.
  화면은 샌드백 존에서 **물약 칸 · 자동사냥 칸(과 그 앞뒤 틈)을 숨긴다**(`_refresh_sandbag_dock`, `_build_zone` 에서).
  샌드백은 때리지 않으니 물약은 쓸 일이 없고, 자동사냥은 판정이 켜므로 단추가 필요 없다.
- 피해는 `_hit_monster` 한 곳에서 센다 — 평타 · 스킬 · 연타(`_run_combos`) · 지대(`_run_zones`) 전부 거기로 온다.
  `starts_at ≤ 지금 < ends_at` 인 것만. 치명타·관통·공속이 그대로 실린다 — **그게 겨루는 것**이다.
- `step` 의 `_check_run_time` 이 `ends_at` 을 넘기면 `_finish_sandbag` — 장부에 `sandbag_record(피해)` 를 청하고
  `dungeonResult`(`dungeon: "sandbag"`, `damage`, `best`, `new_best`) 하나를 낸다. 실패는 없다.
- 결과창에는 **보상 칸이 없다** — 가르는 선 · "보상" · 정산 안내를 통째로 숨긴다(`DungeonResult._show_rewards(false)`,
  다른 던전 결과는 다시 켠다). 2026-10-02 요청 "샌드백 결과창에서 보상 설명칸 제거해". 처음엔 그 자리에
  "주간 보상은 월요일 0시에 … 정산합니다" 를 적었다.
- 나가는 길은 결과창 **확인**(마을가기) 하나, 또는 위쪽 마을가기. 차원문은 없다.
- 입장 횟수는 묶지 않는다 — 다시 들어오면 새 판이다(존을 열 때마다 판이 새로 선다).

### 샌드백 — 안 죽고 안 움직이고 안 때린다 ★

- 몬스터 표(`MONSTER_KINDS`, 60종)에 넣지 않았다 — 넣으면 레벨 곡선 · 드랍 · 경험치 검사가 다 걸린다.
  `sandbag.ts` 의 `SANDBAG_KIND` 를 내보낼 때만 `monsters.json` 에 붙인다(그래서 내보낸 종은 61).
- `dummy: true` → `World.make_monster` 가 `dummy` 칸을 단다 → `_hit_monster` 는 체력을 안 깎고(처치 없음 · 장부 `kill` 없음)
  판에 더하고, `_step_monsters` 는 건너뛴다(쫓기 · 휘두르기 · 순찰 · 범위 공격 없음).
- **방어력 0 · 치명타 저항 0** — 누구나 같은 과녁을 친다. 레벨 차로 깎이는 것이 없어 장비·패시브가 그대로 기록이 된다.
- 자리 — 캐릭터 `(-0.64, 0.64)`, 샌드백 `(0.64, -0.64)`. 카메라가 남동쪽 45° 에서 보므로 **화면에서 좌우로 나란히**다.
  가운데 거리 1.8m 는 격투가 사거리(2.2)보다 짧아 걷지 않고 친다. 평타는 정면 부채꼴만 치므로 `join` 이 샌드백을 보고 세운다.
- 모델 키 1.56m(`BEAST_HEIGHT.sandbag` 1.2 × `scale` 1.3). 맞으면 다른 몬스터처럼 붉어지고 튕긴다(`HitFx`).
- 바르코 GLB 는 기본이 **원점 = 몸 가운데**라 땅에 반쯤 묻혔다 — `get_output_downloads` 에 `pivotToBottom: true` 로 다시 받았다.

### 기록 — 그 주의 최고 한 판 ★

- 장부 칸 `sandbag = {week, best, unpaid?}`. `sandbag_record` 가 이번 주면 큰 쪽을 남기고, 지난 주 칸이면 새 주로 바꾼 뒤 남긴다.
- **기록을 남기기 전에 정산을 먼저 한다** — 지난 기록을 덮으면 보상이 사라진다. 로컬은 `_finish_sandbag` 가
  `_check_sandbag_week(force)` 부터, 서버는 `_op` 가 판정 전에 `_settle_sandbag` 부터 한다.
- 이벤트 `sandbagRecord {damage, best, new_best, week}` — 서버에 붙어 있으면 결과창이 먼저 뜨고 이것이 늦게 와서
  "이번 주 최고" 줄을 고친다(`show_sandbag_best`).

### 날짜별 기록 — 하루 최고 한 판 · 최근 7일 ★ (2026-10-02 요청)

요청: "매일 가장 강한 기록 날짜별로 기록하고, 최대 일주일. 날짜별로 샌드백 기록 볼 수 있게 적어".

- 장부 `sandbag.days = [{day, best}]`(최근 → 옛날). `sandbag_record` 가 판마다 `Sandbag.add_day` 로 얹는다 —
  그날 최고보다 크면 갈아 끼우고, **오늘 포함 7일(`historyDays`)을 넘은 날은 버린다.** 판을 안 돈 날은 줄이 없다.
- 날은 **한국 0시**에 바뀐다(`day = floor((유닉스 초 + 9시간) / 하루)`, `sandbagDay` · `Sandbag.day`). 던전 하루 입장(5시)과
  다르다 — 주 경계(월요일 0시)와 맞추려고. 날 번호 × 하루를 UTC 로 읽으면 그날 한국 날짜다(`day_label` "10월 2일 (금)").
- **주와 따로 논다** — 주 정산(`sandbag_close_week`)도, 새 주의 첫 기록도 `days` 를 들고 넘어간다. 순위·보상은 여전히 주 최고 하나로.
- 화면 — 입장 창 **맨 오른쪽 칸 "날짜별 기록"**(250 폭). 오늘이 맨 위(금빛)로 일곱 줄, 기록 없는 날은 "-".
  값은 순위 답(`sandbagRank`)의 `days` · `today` — 서버는 그 계정 장부와 서버 시계, 로컬은 기기 장부와 기기 시계.
- 서버에서는 `_check_sandbag` 를 통과한 판만 남는다(거절된 판은 장부에 안 닿는다).

### 주 — 월요일 0시(한국) ★

`week = floor((유닉스 초 + 9시간 + 3일) / 7일)`. 1970-01-01 이 목요일이라 사흘을 더한다. TS(`sandbagWeek`)와
고도(`Sandbag.week`)가 같은 식이고 경계는 `sandbag.test.ts` 가 박아 둔다. 시계는 판정하는 쪽 것이다 —
로컬은 기기 시계(`Ledger.unix_now`), 서버는 서버 시계. 테스트는 `World.set_unix_clock` · `ledger.unix_now` 를 바꿔 끼운다.

### 정산 — 지난주 순위로 옐로우 크리스탈 ★★

| 순위 | 1 | 2 | 3 | 4~10 | 11~50 | 51~100 | 101~ |
|---|---|---|---|---|---|---|---|
| 옐로우 크리스탈 | 30 | 25 | 20 | 15 | 10 | 5 | 2 |

- **2026-10-02 에 제안한 값이다** — 손볼 곳은 `SANDBAG_REWARDS` 하나. 기록이 0 인 주는 아무것도 안 준다.
- 장부의 `sandbag_close_week(순위)` 가 `unpaid = {week, rank, best, crystals}` 를 얹고 새 주로 넘긴 뒤 `sandbag_pay` 로 바로 넣는다.
  **가방이 꽉 차 안 들어가면 `unpaid` 로 남겨 두고** 존을 옮길 때 · 불러올 때 · 판이 끝날 때 다시 넣어 본다
  (매초 해 보면 "가방이 가득 차…" 가 매초 뜬다). 들어가면 이벤트 `sandbagReward` → 채팅창 "지난주 N위 · 옐로우 크리스탈 xN".
- **로컬(서버 없음 · 테스트 모드)은 혼자라 늘 1위**다 — `World._check_sandbag_week` 가 1초마다 주를 보고, 지난주 기록이
  있으면 1위로 닫는다. 지금 GitHub Pages 화면은 서버가 없어서 이 길이다.
- **서버** — 주가 바뀐 뒤 그 주를 **처음 정산하는 순간** 그 주 기록이 남은 계정 전부를 줄 세워
  `sandbag/<주>.json` 에 굳힌다(`_ranks_of`). 계정은 들어올 때(hello)나 요청할 때(op) 그 파일의 제 순위로 받는다.
  정산한 계정은 장부가 새 주로 넘어가 다시는 그 주 줄에 안 잡히므로, 굳히기 전에 정산된 계정은 없다.
  모든 계정 파일을 한꺼번에 고쳐 쓰지 않으려고 이렇게 했다 (계정 하나 = 파일 하나 → [server.md](server.md) "저장").
- 같은 기록이면 계정 id 순 — 먼저 낸 사람을 앞에 두려면 낸 시각을 남겨야 한다(지금은 없다, 레벨 랭킹과 같다).

### 서버가 기록을 믿는 근거 ★

전투가 기기에 있는 이상 "N 을 넣었다" 는 주장이다 ([server.md](server.md) "처치 보고를 어떻게 믿나"). 셋을 본다:

1. **샌드백 존에 들어와서(`enter`) 3 + 15초가 지났나** (흔들림 `SLACK_MS` 1.5초) — `too_early`.
2. **한 번 들어와 한 판만** — `claimed`. 다시 치려면 나갔다 들어온다.
3. **상한** — `KillCheck.max_damage(장부, 샌드백, 15초)`: 처치 시간과 같은 식(모든 스킬을 쿨마다 동시에 · 치명타는 늘)이라
   실제보다 늘 크고, 거기에 `HEADROOM`(0.5)만큼 두 배를 더 봐준다 — `too_much`. 정상 플레이를 거절하는 쪽이 훨씬 나쁘다.

거절은 기록만 하고(서버 로그) 제재는 사람이 한다. 처치 검증과 같다.

### 입장 창 — 전체 화면 ★ (2026-10-02 둘째 요청)

요청(첫 판 스크린샷과 함께): "HUD UI 이름 샌드백으로 바꾸고 … UI 설명을 15초 동안 샌드백에 넣은 피해를 겨룹니다. 이것만 적어.
그리고 UI를 전체 화면으로 만들고 순위는 100위까지 스크롤 가능하게".

- 메뉴 단추 글자는 **"샌드백"** (처음엔 "랭킹전").
- 첫 판은 가방 결의 가운데 작은 창이었다. 지금은 **헬스·도감 창과 같은 층(`GateLayer`)·같은 결** — 돌판 틀(`ui_dungeon_card`)
  전체 화면 + 뒤에 불투명한 판. 왼쪽 칸(480)은 제목 · 설명 한 줄 · 주간 보상 표 · 내 기록 · 입장, 오른쪽은 이번 주 순위.
- **주간 보상 표는 한 줄에 한 순위** (`SandbagRewards`, 두 칸 — 순위 | 그림 + 개수). 처음엔 두 벌씩 한 줄이었는데
  "1열 2행으로 만들지 말고, 1열 1행으로" (같은 날 셋째 요청). 개수 앞에 **옐로우 크리스탈 그림**(`yellow_crystal`,
  가방 칸과 같은 그림 · 한 변 `SANDBAG_GEM` 26) — 그림을 안 받았으면 개수만.
- **내 기록 글자와 입장 단추는 한 줄**(`SandbagFoot`) — 글자는 왼쪽에 늘고 단추는 오른쪽, 둘 다 세로 가운데.
  단추는 가방 단추(76×40)였다가 "너무 작아 … 텍스트 옆에 줄 맞춰서" 로 **던전 창 입장과 같은 조각·크기**
  (`ui_button`, `DungeonPanel.ENTER_SIZE` 200×60, 글자 28). 그래서 왼쪽 칸을 420 → 480 으로 넓혔다.
- 설명은 **"15초 동안 샌드백에 넣은 피해를 겨룹니다." 한 줄뿐**이다 (카운트 · 정산 안내는 뺐다 — 정산까지 남은 시간은 내 기록 줄에 있다).
- 같은 층의 전체 화면 창(차원문 · 던전 · 헬스 · 도감)과는 서로 닫는다.

### 순위 창

- 창을 열 때마다 새로 묻는다(`sandbagRank`) — 서버는 이번 주 **위 100명**(`SANDBAG_RANK_TOP`, 레벨 랭킹 50 과 따로) + 내 줄 + 주 끝 시각, 로컬은 나 하나.
- **순위는 1분마다 다시 센다** ★ (2026-10-02 요청 "샌드백 랭킹 갱신은 1분마다 하도록 수정하고 UI에도 명시해").
  간격은 표 `SANDBAG_RANK_REFRESH_SECONDS`(60, `zones.json` 의 `sandbag.rankRefresh` → `Sandbag.rank_refresh_ms`).
  서버(`LedgerServer._sandbag_rank`)는 마지막으로 줄 세운 시각(`_sandbag_order_at`)에서 1분이 지나야 다시 세고,
  그 사이 낸 기록은 다음 갱신에 잡힌다 — 그 전에는 기록이 들어올 때마다 다시 셌다. 주가 바뀌면 바로 비우고 다시 센다.
  창은 제목 오른쪽에 **"순위는 1분마다 갱신됩니다"**(`SandbagRefresh`)를 적고, 열려 있는 동안 1분마다 다시 묻는다(`SandbagRefreshTimer`).
- 표가 넘치면 **끌어서 굴린다** — `DragScroll`(가방 격자와 같다. 엔진의 끌기는 터치 화면에서만 켜져서 PC 에서도 되게).
- 1~3위 밝은 금빛, 내 줄 청록 — 레벨 랭킹 창과 같다. 아래 줄에 "내 기록 · N위 / M명" 과 **"정산까지 N일 N시간"**.
- 레벨 랭킹 단추는 서버에 붙었을 때만 서지만 **샌드백 단추는 늘 선다** — 혼자서도 판을 돌고 보상을 받기 때문이다.

### 옐로우 크리스탈 — 3차 옵션 재료

같은 날 열었다 → [items.md](items.md) "옵션 차수와 크리스탈". 크리스탈과 같은 틀(재료 · 한 칸에 겹침 · 크리스탈 창)이고,
**3차 칸만** 통째로 다시 굴린다. 몬스터는 안 떨군다 — 이 랭킹전 보상이 유일한 길이다.

## 손댈 때

- 보상 개수 → `SANDBAG_REWARDS` 하나 (테스트가 "줄이 빈틈없이 · 아래로 갈수록 적게" 를 본다).
- 카운트·시간 → `SANDBAG_COUNTDOWN_SECONDS` · `SANDBAG_SECONDS`. 서버의 "18초 지났나" 도 이 값을 읽는다.
- 피해에 새 효과(스킬 · 강화 칸)를 넣으면 `KillCheck` 의 `KNOWN_*_KEYS` 를 같이 고친다 — 안 그러면 상한이 낮아져 정상 기록이 `too_much` 로 거절된다.
- 장부 칸을 바꾸면 `Ledger.KEYS` · `fresh` · `World.join` · `restore` · `Save` 다섯 곳.
- 화면 글자를 늘리면 폰트(완성형 2350자)에 있는지 `ui_test` 의 `_case_sandbag` 가 본다.

## 관련

- [dungeons.md](dungeons.md) — 판(`_run`) · 결과창을 같이 쓴다
- [items.md](items.md) — 옐로우 크리스탈(3차)
- [server.md](server.md) — 장부 요청 · 처치 검증 · 랭킹
- [hud.md](hud.md) — 메뉴 판 · 메뉴 아이콘
- [combat.md](combat.md) — 피해 공식 (`_hit_monster`)
