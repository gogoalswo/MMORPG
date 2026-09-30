# 전직 — 지웠다 (2026-09-29)

## 무엇

**전직은 없다.** 2026-09-29 요청("공속을 성장시켜서 빠르게 때리는 스타일로 전투 스타일을 바꿀거야.
그래서 전직 시험 제거하고", "전직관 삭제해")으로 통째로 걷었다. 대신 레벨이 오르면 **패시브 질풍각**으로
평타가 빨라진다 → [passives.md](passives.md).

그 전(2026-09-26 ~ 09-29)에는 Lv.30·70·120·180 에 마을의 전직관 레온에게서 "N차 전직" 을 받아 시험 존
(`job_1`~`job_4`, 사냥터 보스 한 마리)의 보스를 잡으면 전직되고 그 단계 스킬이 풀렸다.

## 지운 것

| 무엇 | 자리 |
|---|---|
| 표 `JOB_ADVANCE_LEVELS` · `JOB_ADVANCES` · `jobAdvanceZones` | `packages/shared/src/jobAdvance.ts` (+ 시험) |
| 시험 존 넷 (`job_1`~`job_4`) — 존 수 65 → 61 | `zones.ts` · `godotExport.test.ts` |
| 전직관 레온 (`role: 'jobs'`) — 마을에 아무도 안 선다 | `zones.ts` 의 마을 `npcs` → [npc-town.md](npc-town.md) |
| 전직 창 `JobPanel` · `jobAdvance` 요청 · `jobAdvanced` 이벤트 | `godot/game/job_panel.gd` · `game.gd` · `local_transport.gd` |
| `World.job_advance` · `_job_state` · `travel` 의 시험 존 거르기 | `world.gd` |
| `Ledger._check_job_trial` · 장부 칸 `job_tier` · 서버 입장 잠금(`zone_locked`) | `ledger.gd` · `ledger_server.gd` |
| 배우기·쓰기의 전직 잠금 (`canLearn` 의 `jobTier`, `Skills.tier_of` 잠금) | `skills.ts` · `skills.gd` · `world.gd` `cast` |
| 저장 칸 `job_tier` — 옛 저장에 남아 있어도 읽지 않는다 | `save.gd` |
| 찍기 `npm run shot:godot -- job` · 시험 `job_advance_test.gd` | `tools/shot.gd` · `godot/tests/` |

## 남은 것

- 스킬 표의 **`tier`** — 잠금이 아니라 **스킬 강화 필요 경험치 등급**(`SKILL_UPGRADE_EXP_BY_TIER`)을 고르는 값으로만 쓴다.
- 레온의 모델 `npc_trainer.glb` · `rig.gd` 의 `trainer` — 마을 `npcs` 에 줄을 되살리면 곧바로 선다.
- `balance.ts` 의 `JOB_ADVANCES`(40레벨마다 5단계)는 **밸런스 설계 시뮬레이터용**이라 게임과 무관하다 — 그대로 뒀다.
- 옛 Colyseus 서버의 `jobs` 역할(직업 바꾸기)은 다른 것이다 — 그대로다.

## 관련

[passives.md](passives.md) · [skills.md](skills.md) · [npc-town.md](npc-town.md)
