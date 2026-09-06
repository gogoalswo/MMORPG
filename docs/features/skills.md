# 스킬

## 무엇

직업당 10개, 총 30개. 배우고(스킬 포인트) 그중 **4개만 액션바에 올린다.**

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/skills.ts` | 스킬 30개 정의, `canLearn`, `skillForJob` |
| `packages/shared/src/skills.test.ts` | 데이터 규칙 검사 (요구 레벨 순서, 직업 균형, 투사체 짝) |
| `packages/client/src/ui/skillBook.ts` | 스킬창 (K) — 배우기 / 장착 |
| `packages/client/src/ui/actionBar.ts` | 액션바 4칸 + 칸마다 자동시전 `A` 스위치 |
| `packages/server/src/ZoneRoom.ts` | `handleLearnSkill` / `handleSetSkillBar` / `handleSkill` / `tryAutoSkill` |

## 규칙

- 요구 레벨은 세 직업이 **동일**: 1, 6, 12, 20, 35, 55, 80, 120, 150, 200.
  직업마다 배우는 시점이 다르면 그 자체로 강약이 갈린다.
- `SKILL_BAR_SIZE = 4`, `SKILL_POINT_PER_LEVEL = 1`.
- Lv.20 까지 배울 수 있는 스킬이 최소 4개 — 안 그러면 액션바에 빈 칸이 남는다.
- 스킬 필드: `power`(공격 배율) / `range` / `arc` / `maxTargets` / `mpCost` /
  `cooldown` / `projectile?` / `selfHeal?`.
- **회복기는 때리지 않는다** — `power: 0`, `maxTargets: 0`. 둘 다 하면 판정 경로가 갈린다.
- **투사체 규칙**: 한 방향으로(`arc < 2π`) 사거리 4 넘게 쏘는 스킬에는 투사체가
  반드시 있어야 한다. 없으면 멀리서 쏘는데 아무것도 안 날아가고 즉시 맞는 것처럼
  보인다. 반대로 자기 중심 전방위기(`arc >= 2π`, 투사체 없음)는 사거리 8 이하여야
  한다 — 길면 화면 밖 적까지 맞아 무슨 일인지 알 수 없다. 둘 다 테스트가 잡는다.

### 서버 검증
- `handleSkill` 은 **액션바에 올라간 스킬만** 허용한다
  (`viewer.character.skillBar.includes(skill.id)`).
- 직업·쿨타임·마나를 서버가 다시 본다. 클라이언트 액션바의 쿨타임 표시는 안내일 뿐.
- 클라이언트가 서버 응답을 안 기다리고 쿨타임을 먼저 돌리는 이유: 연타 도배 방지.
  서버가 거절하면 쿨타임만 돈 셈이라 손해가 작다.

### 자동 시전
- 액션바 칸의 `A` 스위치. 목록은 `localStorage['mmo.autoSkills']` 에 남고
  접속하자마자 서버로 보낸다.
- 실제 시전은 서버 `tryAutoSkill` 이 한다 → [auto-hunt-and-targeting.md](auto-hunt-and-targeting.md).

## 손댈 때

- 스킬을 추가하면 `npm test` 가 요구 레벨 순서·직업 균형·투사체 짝을 잡아 준다.
  통과 못 하면 데이터가 틀린 것이지 테스트가 틀린 게 아니다 —
  단, 규칙 자체가 현실과 안 맞는 경우도 있었다(자기 중심 폭발기). 그때는 규칙을 고친다.

## 관련

[combat.md](combat.md) · [auto-hunt-and-targeting.md](auto-hunt-and-targeting.md)
