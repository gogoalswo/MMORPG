# 전직

## 무엇

레벨 **30 · 70 · 120 · 180** 이 되면 마을의 **전직 NPC(전직관 레온)** 에게서 다음 전직을
받는다. 버튼을 누르면 **전직 시험(존)** 으로 옮겨지고, 거기 선 **보스를 잡으면 전직**이 되며
그 단계의 스킬이 풀린다 (2026-09-26 요청).

```
전직관 레온 ─ 창: "지금: 2차 전직" · "Lv.120 · 보스 ○○ 처치 · 해금: 천붕각" · [3차 전직]
     │  (레벨이 모자라면 버튼이 흐리고 "(Lv.120 필요)")
     ▼
3차 전직 시험 (job_3, 보스 한 마리) ── 잡으면 ──▶ 3차 전직 · 천붕각 해금
```

| 단계 | 레벨 | 시험 존 | 보스 | 푸는 스킬 (격투가) |
|---|---|---|---|---|
| 기본 | 1 | — | — | 할퀴기 |
| 1차 | 30 | `job_1` | `boss02` Lv.29 | 낙뢰 |
| 2차 | 70 | `job_2` | `boss06` Lv.69 | 빙주각 |
| 3차 | 120 | `job_3` | `boss11` Lv.119 | 천붕각 |
| 4차 | 180 | `job_4` | `boss17` Lv.179 | **아직 없음** (스킬을 안 만들었다) |

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/jobAdvance.ts` | **표.** `JOB_ADVANCE_LEVELS` · `JOB_ADVANCES`(단계·레벨·존·보스) · `jobAdvanceZones(gate)` |
| `packages/shared/src/skills.ts` | 스킬의 **`tier`**(전직 단계) · `canLearn(…, jobTier)` |
| `packages/shared/src/zones.ts` | 마을 NPC `전직관 레온`(`role: 'jobs'`, (7, 7)) · `ZONES` 에 시험 존 넷 |
| `packages/shared/src/jobAdvance.test.ts` | 레벨 · 존마다 보스 하나 · 보스 = 전직 레벨 - 1 · 격투가 스킬 단계 · 잠금 |
| `scripts/export-shared.mjs` | `skills.json` 의 `jobAdvances` 로 내보낸다 |
| `godot/world/skills.gd` | `tier_of` · `job_advance(tier)` · `job_tier_of_zone` · `unlocked_at` · `can_learn(…, job_tier)` |
| `godot/world/world.gd` | `player.job_tier` · `_job_state`(NPC 창에 싣는 것) · **`job_advance`**(버튼) · **`_check_job_trial`**(보스 처치 → 전직) · `travel` 이 시험 존을 거른다 · `learn_skill`·`cast` 의 잠금 |
| `godot/world/save.gd` | `job_tier` 저장 (옛 저장은 0) |
| `godot/net/local_transport.gd` | `jobAdvance` 요청 |
| **`godot/game/job_panel.gd`** | ★ **전직 창** (`JobPanel`) — 조각으로 조립한다. 아래 "창" |
| `godot/game/game.gd` | `_build_npc_panel` 이 전직 창을 상점·대장간 창과 같은 **HUD 위 층(`NpcLayer`, 10)** 에 단다 · `_show_npc` 가 `jobs` 면 전직 창을 채운다 · 스킬창의 "N차 전직" 표시(`_redraw_skills`) · `jobAdvanced` 이벤트 |
| `godot/tools/shot.gd` `_job` | `npm run shot:godot -- job` — 1차를 마친 Lv.70 이 말을 건 창을 찍는다 |
| `godot/tests/job_advance_test.gd` | 잠금 · NPC 창 상태 · 시험 → 처치 → 전직 · 지름길 막기 · 저장 · 창 버튼 · 치트 "스킬 모두 배우기"(화면 안인가 · 다 배웠나 · 낙뢰가 나가나) |

## 규칙

- **버튼은 다음 전직 하나만** 뜬다 — 2차면 "3차 전직". 4차를 마치면 "모든 전직을 마쳤습니다".
- **버튼이 눌리는지는 World 가 정한다** (`_job_state.ready`). 누르면 `jobAdvance` 요청 —
  NPC 곁인지(`NPC_REACH`) · 레벨 · 다음 단계인지를 `job_advance` 가 **다시 본다.**
- **전직은 보스를 잡아야 된다.** 시험에 들어가기만 해서는 안 된다. `_kill` →
  `_check_job_trial` 이 "지금 존이 시험이고 · 잡은 게 보스이고 · 그 시험이 **바로 다음
  단계**이고 · 레벨이 되는지" 를 보고 `job_tier` 를 올린다. 지난 시험을 다시 잡아도 안 오른다.
- **시험 존은 전직 NPC 로만 간다.** `travel`(차원문 · 던전 창)은 시험 존을 버린다.
  차원문 목록에도 던전 창에도 없다. **나오는 길은 차원문**이다 (다른 존과 같은 자리).
- **보스는 사냥터 보스를 그대로 쓴다** — 전직 레벨 L 에 `bossIdFor(L/10 - 1)`(Lv. L-1).
  던전과 같은 이유로 새 종·새 모델을 짓지 않았다. 존 틀(보스 자리 · 어두운 돌길)도
  던전 것(`DUNGEON_BOSS_SPOT` · `DUNGEON_ENV`)을 쓴다 → [dungeons.md](dungeons.md).
- **전직 잠금은 테스트 스위치(`unlockAll`)와 무관하다.** 스위치는 레벨 · 포인트만 푼다.
  전직 스킬은 배우기(`learn_skill`)와 **쓰기(`cast`) 둘 다** 막힌다 — 전직이 생기기 전
  저장에 배운 채로 남은 낙뢰도 전직 전에는 안 나간다(배운 목록에서 지우지는 않는다).
- 스킬의 **요구 레벨을 전직 레벨에 맞췄다** (낙뢰 30 · 빙주각 70 · 천붕각 120). 스킬창의
  "Lv.N" 과 전직 레벨이 같은 수를 가리키고, 목록 순서(요구 레벨 순)가 전직 순서가 된다.
  스킬창은 전직이 모자라면 "N차 전직" 배지 · "N차 전직 후 배웁니다" 를 적는다.
- **테스트 모드(Lv.200)도 전직은 직접 해야 한다.** 무적이라 네 번 다 금방 돈다.
  건너뛰려면 치트 목록의 **"스킬 모두 배우기"** (`World.debug_learn_all`, 2026-09-26 요청) —
  **전직을 끝까지(4차) 올리고** 그 직업 스킬을 전부 배워 액션바 빈 칸에 차례로 올린다.
  배우기만 하면 전직 잠금 때문에 안 나가서 전직도 같이 올린다. 레벨·포인트는 안 본다.
- 옛 Colyseus 서버는 전직을 모른다 — `canLearn` 의 `jobTier` 를 안 넘기면 잠금을 안 본다.

### 창 ★

```
┌ 전직                                         [X] ┐   ui_panel (금테 창)
│ 전직관 레온                                       │
│ ───────────────────────────────────────────────── │
│  ●━━━━━◉─────○─────○─────○                        │   단계 줄 — 마침(짙은 금) · 지금(밝은 금 + 빛)
│ 기본   1차   2차   3차   4차                       │            · 아직(어두운 판 + 흐린 테)
│ Lv.1  Lv.30 Lv.70 Lv.120 Lv.180                   │
│ ┌──────────────────────────────────────────────┐ │   ui_slot (카드)
│ │ [빙주각]  2차 전직                            │ │   해금 스킬 아이콘(skill_<id>) — 4차는 "?"
│ │ [아이콘]  레벨 70  (지금 70)   ← 되면 초록, 모자라면 붉게
│ │           시험 보스  삼림의 폭군  Lv.69        │ │
│ │           해금  빙주각                         │ │
│ └──────────────────────────────────────────────┘ │
│ [          2차 전직 시험 입장           ]          │   ui_button — 모자라면 흐리고 "Lv.70 에 열립니다"
└───────────────────────────────────────────────────┘
```

- **처음 판은 고도 기본 패널에 글자·단추만 쌓았다 → "UI 가 너무 엉성해" (2026-09-26).**
  스킬창·차원문 창과 같은 얇은 금테 조각(`ui_panel`·`ui_slot`·`ui_button`·`ui_close`)으로
  다시 지었다 → [ui-art-style.md](ui-art-style.md). 색도 그 문서의 표에서 가져왔다.
- **상점·대장간 창(`_npc_panel`)과 따로 뗐다.** 그 창은 목록 + 탭이고, 전직은 단계 줄 +
  카드 하나라 모양이 다르다. 전직관을 누르면 상점 창은 닫힌다.
- **HUD 위 층(`CanvasLayer` 10)에 단다.** `_ui_root` 에 두었더니 체력 막대·퀵슬롯·레벨
  배지가 아래쪽 단추를 덮었다 (찍어서 봤다). 한글 폰트는 `_ui_root.theme` 을 물려준다.
- 단계 점은 조각이 아니라 **코드로 그린 둥근 판**(`StyleBoxFlat`)이다 — 점 다섯에 그림을
  받을 만큼의 것이 아니고, 조각이 없는 사람에게도 같게 보인다.
- 창은 **그리기만** 한다. 무엇을 그릴지(`_job_state`)와 단추가 되는지(`ready`)는 World 가
  정하고, 단추는 `advance` 신호 → `jobAdvance` 요청뿐이다.
- 테스트(`job_advance_test._check_layout`): 화면 가운데 안 · 점 다섯 · 마친 점과 아직 점의
  색이 다른가 · 해금 스킬 아이콘 · 조건 줄 · 단추가 창 안 · X 가 오른쪽 위 · 모자라면 막힘.

## 손댈 때

- 4차 스킬을 만들면 스킬 표에 `tier: 4` · `reqLevel: 180` 만 넣으면 NPC 창 · 잠금이 따라온다.
- 전직 레벨을 바꾸면 `JOB_ADVANCE_LEVELS` → `npm run export:godot`. 스킬의 `reqLevel` 도 같이
  고친다 (`jobAdvance.test.ts` 가 둘이 같은지 본다). 레벨은 10의 배수여야 보스가 맞는다.
- 존 수가 바뀌므로 `godotExport.test.ts` 의 존 수(지금 45)도 고친다.
- 스킬 판정을 보는 고도 테스트는 캐릭터를 **3차까지 마친 것으로** 두고 쏜다
  (`skill_test._setup` · `ui_test._case_skills` · 이펙트 테스트들의 `job_tier`).

## 관련

[npc-town.md](npc-town.md) · [skills.md](skills.md) · [dungeons.md](dungeons.md) · [godot-migration.md](godot-migration.md)
