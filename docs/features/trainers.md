# PT 트레이너 — 뽑아 모으고, 한 명을 데리고 다니며 같이 싸운다

## 무엇

상점의 **뽑기 → 트레이너** 에서 다이아로 트레이너를 뽑는다. 뽑은 트레이너는 **갖고만 있어도 보유 효과**가
캐릭터에 붙고, 메뉴 판의 **트레이너** 창에서 한 명을 골라 **동행**시키면 곁을 따라다니다가 **내가 친 몬스터를
같이 친다.** 트레이너는 맞지도, 겨눠지지도 않는다.

요청 (2026-10-06):
1. "헬스처럼 새로운 컨텐츠를 만들어서 성장을 돕는 컨텐츠를 추가하고 싶어. 추천해 줘" → 넷을 추천, 사용자가
   **PT 트레이너**를 골랐다.
2. "등급별로 캐릭터의 능력치를 몇 % 계승할지 정하고, 일반 20% · 고급 30% · 희귀 40% · 영웅 60% · 전설 80% …
   플레이어가 때리는 몬스터 같이 때리도록 만들고, 트레이너는 공격 받지 않도록 … 타겟팅 되지 않도록 …
   일반 20종 · 고급 15종 · 희귀 10종 · 영웅 5종 · 전설 3종 … 이미지 및 모델은 다 바르코로 만들어. 그리고
   트레이너마다 기본 획득 능력치가 있으면 좋겠어. 이 부분도 어떤식으로 넣으면 좋을지 추천해 줘"
3. 물어서 정한 것 — 얻는 길 **상점 다이아 뽑기만** · 동행 **1명** · 기본 능력치는 **보유 효과**(추천안 그대로) ·
   바르코는 **원화 확인 없이 3D 까지 한 번에**.

| 등급 | 인원 | 계승 | 보유 효과 | 뽑기 확률 |
|---|---|---|---|---|
| 일반 | 20 | 20% | +1% | 58% |
| 고급 | 15 | 30% | +2% | 30% |
| 희귀 | 10 | 40% | +3% | 9% |
| 영웅 | 5 | 60% | +5% | 2.5% |
| 전설 | 3 | 80% | +8% | 0.5% |

뽑기 값 — **1회 다이아 100 · 10회 1,000** (할인 없음). 확률·보유 효과·값은 추천값이다 (사용자는 계승 % 와 인원만 정했다).

## 어디

| 파일 | 역할 |
|---|---|
| `packages/shared/src/trainers.ts` | **표 원본** — 등급(`TRAINER_GRADES`: 계승 · 보유 효과 · 확률 · 인원), 명단 53명(`ROSTER` → `TRAINERS`), 바르코 원화 프롬프트(`look` + `TRAINER_PROMPT_TAIL`), 뽑기 값, `trainerOwnedBonus` |
| `packages/shared/src/trainers.test.ts` | 인원 20·15·10·5·3 · 계승 % · id/이름 겹침 · 확률 합 100 · 다 모은 보유 효과 |
| `scripts/export-shared.mjs` | `godot/data/trainers.json` (프롬프트는 뺀다) |
| `godot/world/trainers.gd` `Trainers` | 표 읽기 — `trainer` · `grade` · `owned_bonus` · `inherit_of` · `roll`(등급 확률 → 등급 안 고르게) · `clean` · `look` |
| `godot/world/ledger.gd` `trainer_draw` · `trainer_pick` | ★ **판정.** 장부 칸 `trainers {id: 개수}` · `trainer_active` (`KEYS`) |
| `godot/world/world.gd` `stats_of` | 보유 효과 — 공·방·체는 **따로 곱하고**(`trainer_*`), 치명타 둘은 비율에 더한다 |
| `godot/world/world.gd` `_step_buddies` · `_buddy_strike` · `_hit_monster` | ★ **동행 전투** (아래 "동행") · `hunt_focus` |
| `godot/world/world.gd` `trainer_draw` · `trainer_pick` · `debug_diamonds` · `restore` | 요청 → 장부, 테스트 단추(다이아 +1만), 저장 되살리기(표에 있는 것만 · 안 가진 동행은 비움) |
| `godot/world/save.gd` | `trainers` · `trainer_active` 칸 |
| `godot/server/ledger_server.gd` `OPS` | `trainer_draw: "i"` · `trainer_pick: "s"` — 서버에서는 **서버가 굴린다** |
| `godot/server/kill_check.gd` `_pace` | 처치 검증 · 샌드백 상한이 **동행 몫**(평타 × 계승 %)을 더해 본다 |
| `godot/net/local_transport.gd` | `trainerDraw {times}` · `trainerPick {id}` · `debugDiamonds` |
| `godot/game/trainer_panel.gd` `TrainerPanel` | 트레이너 창 + **카드 한 장**(`make_card` — 뽑기 결과도 쓴다) |
| `godot/game/store_panel.gd` | 뽑기 탭 · 다이아 단추(`buy_requested`) · 가진 다이아 · 뽑기 결과 판(`show_draw`) |
| `godot/game/game.gd` `_toggle_trainer` · `_trainer_art` · `_draw_buddy` | 메뉴 단추(상점 옆, ≡ 판 안) · 원화 불러오기 · 동행 모델 그리기, `buddySwing` · `trainerDraw` · `diamonds` 알림 |
| `godot/game/rig.gd` `create` | `trainer_<id>` 는 `FILES` 에 없어도 `trainer_<id>.glb` 로 찾는다 (53줄을 손으로 안 적는다) |
| `godot/tests/trainer_test.gd` | 표 · 뽑기 · 동행 고르기 · 보유 효과 · **동행 전투** · 저장 · 서버 · 창 · 상점 뽑기 |
| `godot/tests/model_test.gd` `_case_trainers` | 53명 전원이 모델로 만들어지고 `Idle` · `Run` · `Attack` 이 있고 키가 표대로다 |
| `scripts/build-trainer-art.mjs` | 원화(9:16) → 카드 그림 240×320 JPG (`public/assets/trainers/`, 커밋) |
| `scripts/fetch-assets.sh` 의 트레이너 줄 | 바르코 결과물 주소 (원화 · 대기 · 달리기 · 펀치) → `build-varco-character.mjs` |

## 규칙

### 보유 효과
- 트레이너마다 능력치 **하나** — 등급 안에서 공격력 → 방어력 → 체력 → 치명타 확률 → 치명타 피해 순으로 돌린다
  (`STAT_CYCLE`). 전설 셋만 따로: 권신 공격력 · 헤라클 체력 · 선녀 치명타 확률.
- 53명을 다 모으면 공격력 +29% · 방어력 +21% · 체력 +29% · 치명타 확률 +29%p · 치명타 피해 +21%p.
- 공·방·체는 **장비·헬스·도감과 따로 곱한다** — 헬스 문서의 이유와 같다(장비 % 에 더하면 태초 풀셋 앞에서 묻힌다).
  캐릭터 정보 창 풀이 줄에 `트레이너 N%` 로 적힌다.
- 같은 트레이너가 또 나오면 **개수만 는다** — 지금은 쓰임이 없다 (중복 강화는 사용자가 안 골랐다).

### 동행 ★
- **한 명만.** 첫 뽑기에서 동행이 없으면 그 뽑기에서 가장 높은 등급이 바로 따라온다(`trainer_draw`).
  트레이너 창의 **동행** / **돌려보내기** 로 바꾼다.
- **맞지 않고 겨눠지지 않는 이유** — 트레이너는 `_monsters` 에도 `_players` 에도 없다. 몬스터가 노릴 사람을 찾는
  `_nearest_player`, 평타·스킬이 맞을 놈을 고르는 `_pick_targets`, 화면의 누르기(`_mob_nodes`) 어디에도 안 들어간다.
  자리는 `player.buddy` 에만 있다 (`{id, x, z, rot, state, next_hit_at}` — 전투 쪽 값이라 장부·저장에 없다).
- **내가 친 놈을 같이 친다** — 내 한 대(`_hit_monster`, 트레이너 것 말고)가 `hunt_focus` 를 남긴다. 그 뒤
  `BUDDY_FOCUS_MS`(4초) 안이면 트레이너가 그 놈에게 달려가(`BUDDY_SPEED_MUL` 내 속도 ×1.25) 주먹 거리
  (`BUDDY_REACH` 1.6m + 몬스터 몸)에서 친다. 손을 떼면 4초 뒤 곁(오른쪽 뒤 `BUDDY_SIDE`·`BUDDY_BACK`, **캐릭터 기준**)으로 돌아온다.
- **한 대 = 내 평타 × 계승 %** — 간격은 내 평타 간격(공속 포함), 피해는 내 최종 공격력 × 계승 %, 치명타·관통은
  내 것 그대로. 그래서 공속 패시브·장비가 트레이너도 같이 키운다. 전설(80%)이면 평타 피해가 1.8배가 된다.
- 잡으면 **내 처치**다 — 경험치·드랍·던전 클리어·샌드백 기록이 다 내 것. 맞은 몬스터는 **나를** 쫓는다.
- 충돌이 없다 — 몬스터·캐릭터 사이를 지나다닌다 (막히면 같이 칠 수 없다). 14m 넘게 떨어지면(존 이동·순간 이동)
  곁으로 옮긴다. 샌드백 카운트 동안은 기다린다.
- 화면 — 트레이너 한 대의 `hit` 은 `buddy: true` 라 **숫자·섬광만** 낸다(소리·히트스톱·흔들림은 내 손맛이라 안 겹친다).
  `buddySwing` 에서 `Attack`(boxing_punch)을 내 발차기와 같은 배속으로 처음부터 튼다. 달리면 `Run`, 서 있으면 `Idle`.

### 서버
- 뽑기는 서버가 굴린다 (`OPS.trainer_draw` — 다이아도 장부가 다시 센다). 동행은 갖고 있는 것만.
- 처치 검증(`KillCheck._pace`)은 동행 몫을 평타 줄에 더한다 — 빼먹으면 전설 동행이 "너무 빨리 잡았다" 로 거절된다.

### 원화 · 모델 (바르코)
- 워크플로우 "Untitled"(`6f4423a3…`) — 트레이너마다 한 줄: `TextInput`(프롬프트) → `GenerateImage`(`nano-banana-pro`,
  9:16, 참고 그림 = **격투가 원화** `e9a9e381…jpg`) → `Generate3D`(tPose 1 · **1만 면** · 텍스처 1024) →
  `Rig`(humanoid) → `Animate` 셋(inPlace): 대기 `standing_idle_1` · 달리기 `run` · 공격 `boxing_punch`.
- **1만 면 · 텍스처 512 인 이유** — 3만 면 모델이 하나 1.9MB(고도, 텍스처 512)라 53벌이면 100MB 가 웹 빌드에 얹힌다.
  동행은 한 번에 한 명이고 화면에서 작다. 텍스처는 고도가 어차피 512 로 넣으므로 `--tex 512` 로 구워도 화면은 같다.
  그래도 **한 벌 1.0MB, 53벌 55MB** 다 (뼈대·클립 셋 몫이 크다) — 웹 빌드가 그만큼 무거워졌다.
- 바르코 작업 메모 — 노드가 380개를 넘자 `get_output_downloads` 를 `nodeId` 없이 부르면 **502** 가 났다.
  Animate 노드마다 따로 받고, 원화 주소는 그래프 출력(`/api/objects/…png`)에서 뽑았다.
- 프롬프트의 공통 꼬리는 마을 NPC 와 같다 — 정면 · 팔은 몸에서 조금 떨어뜨려 · **두 손은 비우고** · 흰 바탕. 손에
  든 물건은 T자세 3D 에서 뭉개지므로 소품은 허리·등에 단다.
- 원화는 카드 그림으로도 쓴다 — `build-trainer-art.mjs` 가 머리~허벅지를 3:4 로 잘라 굽는다 (따로 그리지 않았다).

## 손댈 때

- 등급 수치·인원을 바꾸면 `trainers.ts` → `npm run export:godot` → `npm test` · `npm run test:godot -- trainer`.
- 트레이너를 더하면 `ROSTER` 에 한 줄 + 바르코 한 줄 + `fetch-assets.sh` 주소 + `build-trainer-art.mjs`. 모델·원화
  이름은 표에서 짓는다(`trainer_<id>`) — `rig.gd`·`sync-godot-assets.mjs`·`check-godot-assets.mjs` 는 손댈 것이 없다.
- 동행 피해를 바꾸면 `KillCheck._pace` 의 동행 줄도 같이 고친다.
- 메뉴 단추가 늘면 `ui_test` 의 메뉴 개수(12)도 같이.

## 관련

- [store.md](store.md) — 뽑기 탭 · 다이아 상품 카드
- [fitness.md](fitness.md) · [codex.md](codex.md) — 같은 "따로 곱하는" 성장 축
- [server.md](server.md) — 다이아 · 처치 검증
- [characters-and-animation.md](characters-and-animation.md) — 바르코 캐릭터 빌드(`build-varco-character.mjs`)
- [auto-hunt-and-targeting.md](auto-hunt-and-targeting.md) — 겨누기(트레이너는 대상이 아니다)
