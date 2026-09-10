# 에셋 출처와 라이선스

이 프로젝트에 포함된 모든 **외부** 에셋은 **CC0 1.0 (퍼블릭 도메인)** 이다.
출처 표기 의무가 없고 상업적 사용에 제한이 없다.
예외는 [VARCO 로 직접 생성한 캐릭터](#캐릭터-모델--varco-생성-기사마법사궁수) 셋뿐이다 —
받아온 게 아니라 우리가 만든 것이라 라이선스가 아니라 **약관**이 걸린다.

> 새 에셋을 추가할 때는 **반드시 이 표에 먼저 기록한다.**
> 나중에 상용화 시점에 "이건 어디서 받았더라"를 역추적하는 건 불가능에 가깝다.
> 라이선스가 불분명한 에셋은 넣지 않는다.

## 지면 텍스처 — ambientCG

출처: https://ambientcg.com · 라이선스: CC0 1.0

| 에셋 | 원본 | 사용처 |
|---|---|---|
| Grass005 | `Grass005_1K-JPG.zip` (10.0MB) | 초원 지면 |
| Ground037 | `Ground037_1K-JPG.zip` (10.1MB) | 흙길 |
| Rock063 | `Rock063_1K-JPG.zip` (4.8MB) | 바위·절벽 (아직 미사용) |

각 아카이브에서 **Color / NormalGL / Roughness** 세 장만 꺼내 쓴다.
- AmbientOcclusion → 화면공간 GTAO 가 대신한다
- Displacement → 지면이 평면이라 불필요
- NormalDX → three.js 는 OpenGL 규약이므로 NormalGL 을 쓴다

## 캐릭터 모델 — KayKit (Kay Lousberg)

출처: https://kaylousberg.com · 팩: KayKit Character Pack : Adventurers 1.0
받는 곳: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0
라이선스: **CC0 1.0** (팩 안 LICENSE.txt 에 명시. 출처 표기 의무 없음)

| 원본 | 우리 파일 | 쓰는 곳 |
|---|---|---|
| `Knight.glb` | `knight.glb` | 기사 + **애니메이션 클립 전부** |
| `Mage.glb` | `mage.glb` | 마법사, 노인 NPC |
| `Rogue.glb` | `rogue.glb` | 상인 NPC, 마을 사람 |
| `Rogue_Hooded.glb` | `rogue_hooded.glb` | 궁수, 마을 사람 |
| `Barbarian.glb` | `barbarian.glb` | 대장장이 NPC, 마을 사람 |

다섯이 **같은 41본 뼈대**를 쓴다. 그래서 애니메이션은 `knight.glb` 한 곳에만
남기고 나머지 넷에서는 통째로 잘라냈다 (`scripts/trim-gltf.mjs`).
원본은 한 개가 3.6MB(그 중 80%가 애니메이션 76개)라 다섯이면 18MB 인데,
쓰는 클립 9개만 남기니 전부 합쳐 **2.0MB** 가 됐다.

남긴 클립: `Idle` `Walking_A` `Running_A` `1H_Melee_Attack_Slice_Diagonal`
`1H_Ranged_Shoot` `Spellcast_Shoot` `Death_A` `Hit_A` `Interact`

## 몬스터 모델 — Quaternius

원작자: Quaternius (https://quaternius.com) · 라이선스: **CC0 1.0**
받는 곳: https://github.com/trebeljahr/quaternius-showcase (모델 미러.
저장소 자체의 MIT 는 데모 코드에 붙은 것이고, **모델은 원작자의 CC0** 다)

**사냥터 20곳에 한 종씩, 20개.** 같은 짐승이 두 번 나오면 사냥터를 옮긴
느낌이 나지 않는다. 보스는 덩치 큰 공룡 여섯을 돌려 쓰되, 그 사냥터 잡몹과
같은 모델이 걸리면 다음 것으로 넘긴다.

| 팩 | 우리 파일 | 사냥터 |
|---|---|---|
| Animals | `fox` `shibainu` `wolf` `husky` | 초원 · 검은삼림 · 서리고원 · 잿빛황야 |
| Animals | `bull` `stag` `deer` | 덤불숲 · 협곡 · 소금평원 |
| Animals | `horse` `horse_white` | 그림자계곡 · 창백한고원 |
| Easy Enemies | `spider` `rat` `snake` `frog` `wasp` | 뒤틀린숲 · 화산재 · 붉은사막 · 안개늪 · 유황분지 |
| Dinosaurs | `trex` `velociraptor` `triceratops` | 종말의대지 · 균열지대 · 얼어붙은심연 |
| Dinosaurs | `stegosaurus` `apatosaurus` `parasaurolophus` | 무너진성터 · 심연의문턱 · 폐허도시 |

각 파일에 **대기·걷기·달리기·공격·사망** 다섯 클립만 남겼다 (원본 12~13개).
팩마다 이름이 제각각이라 클립은 이름이 아니라 역할로 찾는다 — 벌은 대기가
`Wasp_Flying` 뿐이고, 개구리는 걷지 않고 뛴다(`Frog_Jump`).
아파토사우루스는 팩에서 사망 클립 이름이 `Stegosaurus_Death` 로 잘못 붙어 있다.
종류마다 뼈대가 달라서 클립을 공유할 수 없다 — 파일마다 자기 것을 들고 있다.

색은 몬스터 종류의 `bodyColor` 를 곱해서 낸다. 그냥 곱하면 어두워지므로
밝기를 1 로 되돌린 뒤 색조만 입힌다 (`modelRig.tintedMaterial`).

**부팅 때 다 받지 않는다.** 사냥터 하나에 두세 종뿐이라, 존을 옮길 때
필요한 것만 받는다 (`Models.ensureBeasts`). 마을에서는 한 개도 안 받는다.

## 캐릭터 모델 — VARCO 생성 (기사·마법사·궁수)

출처: 바르코 3D (https://3d.varco.ai) 커스텀 워크플로우 "기사" 와 마법사·궁수 결과물 · **CC0 아님**

받아온 에셋이 아니라 **우리가 그 서비스로 만든 결과물**이다. 그래서 라이선스가
아니라 VARCO 의 이용약관이 적용된다 — 상용화 전에 생성물 권리 조항을 확인해야
한다. 위 표들과 성격이 다르므로 절을 따로 뒀다.

| 워크플로우 노드 | 우리 파일 | 쓰는 곳 |
|---|---|---|
| Rig(humanoid) 결과 | `assets-src/models/varco/knight_rigged.glb` | 메시·뼈대 |
| Animate `standing_idle_1` | `anim_idle.glb` | `Idle` (노드는 뒤에 `sprint` 로 바뀜 — 고정 주소로 받는다) |
| Animate `run` | `anim_run.glb` | `Run` |
| Animate `sword_slash` | `anim_sword_slash.glb` | `Attack` |
| Animate `two_hand_attack` | `anim_two_hand_attack.glb` | `Attack_Heavy` (아직 안 씀) |
| Animate `staff_spin_attack` | `anim_staff_spin.glb` | `Attack_Spin` (아직 안 씀) |
| Animate `left_side_fall` | `anim_death.glb` | `Death` |
| 합친 결과 | `public/assets/models/varco_knight.glb` (3.1MB) | 기사 직업 |

마법사는 리깅 결과물 없이 **동작 파일 셋**으로 왔다. 대기 파일을 기본(메시·뼈대)으로 쓴다.

| 원본 | 우리 파일 | 쓰는 곳 |
|---|---|---|
| 대기 | `assets-src/models/varco/mage_idle.glb` | 메시·뼈대 + `Idle` |
| 달리기 | `mage_run.glb` | `Run` |
| 공격(시전) | `mage_attack.glb` | `Attack` |
| 사망 | `mage_death.glb` | `Death` |
| 합친 결과 | `public/assets/models/varco_mage.glb` (2.4MB) | 마법사 직업 |

궁수도 같은 방식이다.

| 원본 | 우리 파일 | 쓰는 곳 |
|---|---|---|
| 대기 | `assets-src/models/varco/archer_idle.glb` | 메시·뼈대 + `Idle` |
| 달리기 | `archer_run.glb` | `Run` |
| 공격 | `archer_attack.glb` | `Attack` |
| 사망 | `archer_death.glb` | `Death` |
| 합친 결과 | `public/assets/models/varco_archer.glb` (2.3MB) | 궁수 직업 |

**마법사·궁수는 받은 파일로 만든다** — 결과물 주소는 박지 않았다.
`fetch-assets.sh` 는 원본이 `assets-src/models/varco/` 에 있을 때만 만들고,
없으면 건너뛴다(그 직업은 절차적 리그로 나온다).

**동작 하나가 파일 하나로 나온다.** 그런데 그 파일에 메시와 2048² 텍스처가
통째로 다시 들어 있어서 하나가 14MB, 여섯이면 83MB 다. 여섯의 뼈대가 완전히
같으므로(23본) **메시는 리깅 결과물 하나만 쓰고 나머지에서는 애니메이션만
뽑아 옮겨 붙인다** — `scripts/build-varco-character.mjs`.
채널이 가리키는 노드는 인덱스가 아니라 **이름으로** 다시 잇는다. 인덱스가
파일마다 같다는 보장이 없고, 어긋나면 팔이 다리처럼 움직인다.

텍스처는 2048² PNG 세 장(11.9MB)을 1024² JPEG(1.0MB)으로 줄인다. 쿼터뷰에서
캐릭터는 화면상 100px 남짓이라 그 해상도가 화면에 닿지 않는다. 노멀맵만 품질을
올려 잡는다(92 vs 84) — JPEG 은 색차부터 버리는데 노멀맵은 그게 곧 기울기다.
KTX2 로는 안 넘겼다. `npm run compress` 는 지면 텍스처(`assets-src/textures`)만
보고, 이건 .glb 안에 들어 있다.

**뼈 이름이 KayKit 과 다르다**(`RightHand` vs `handslotr`). 클립도 KayKit 것과
공유할 수 없어서 파일 안에 같이 들고 있다 — 짐승 모델과 같은 취급이다
(`models.ts` 의 `SOLO_MODELS`).

**결과물 주소를 `scripts/fetch-assets.sh` 에 박아 뒀다.** 워크플로우를 다시
돌리면 같은 프롬프트로도 다른 캐릭터가 나오므로(생성 모델이다) 프롬프트가 아니라
결과물을 고정해야 재현이 된다. 주소가 죽으면 워크플로우를 다시 돌리고 해시를
갈아 끼운다.

## 장비 — KayKit 액세서리

같은 Adventurers 팩의 별도 파일. 라이선스 동일 (**CC0 1.0**).

| 원본 | 우리 위치 | 쓰는 곳 |
|---|---|---|
| `quiver.gltf` + `quiver.bin` + `rogue_texture.png` | `public/assets/models/accessories/` | 궁수 등에 매다는 화살통 |

무기·방패·마법서는 캐릭터 `.glb` 안에 이미 매달려 있어서 따로 받지 않는다.
화살통만 도적 모델에 빠져 있다. `.gltf` 가 옆의 `.bin` 과 `.png` 를 상대 경로로
참조하므로 **셋을 같은 폴더에 둬야** 한다.

## HDRI — Poly Haven

출처: https://polyhaven.com · 라이선스: CC0 1.0

| 에셋 | 파일 | 용도 |
|---|---|---|
| Kloofendal 48d Partly Cloudy (Pure Sky) | `sky_2k.hdr` (5.2MB) | 환경광(IBL) |

하늘 배경으로는 쓰지 않는다. 존마다 안개 색이 다른데 실제 하늘 사진을 배경에
깔면 숲 존에서 색이 따로 놀기 때문이다. 조명 용도로만 굽는다.

## 디렉터리 규칙

```
assets-src/          원본 — git 에 커밋하지 않는다 (fetch 스크립트로 재취득)
  *.zip                ambientCG 아카이브
  textures/*.jpg       추출한 원본 맵 (KTX2 재인코딩용)
  models/*.glb         KayKit·Quaternius 원본 (클립을 잘라내기 전)
  models/varco/*.glb   VARCO 워크플로우 결과물 (합치기 전, 기사 6개 83MB + 마법사·궁수 각 4개 48MB 남짓)
  sky_1k.hdr
public/assets/       배포되는 파일만
  textures/*.ktx2      압축된 텍스처
  hdri/sky_1k.hdr
  basis/               KTX2 트랜스코더 (런타임 필수)
```

```bash
./scripts/fetch-assets.sh   # 원본 받기
npm run compress            # JPEG -> KTX2
```

## 압축

JPEG 은 다운로드 용량만 작을 뿐 GPU 에 올라갈 때는 RGBA 로 풀린다 —
1024² 한 장이 VRAM 4MB, 9장이면 36MB 다. KTX2(Basis Universal)는 압축된 채로
GPU 에 올라가서 다운로드와 VRAM 을 동시에 줄인다.

맵 종류마다 인코딩이 다르다:

| 종류 | 방식 | 이유 |
|---|---|---|
| `_color` | ETC1S + sRGB | 눈이 색 오차에 관대하다. 가장 세게 줄인다 (~90% 감소) |
| `_normal` | UASTC + zstd | ETC1S 로 누르면 법선이 뭉개져 요철이 계단처럼 보인다 |
| `_rough` | ETC1S + 선형 | 단일 채널 데이터라 오차가 잘 안 보인다 |

결과: **11.8MB → 4.2MB (65% 감소)**. HDRI 도 2k → 1k 로 낮춰 5.2MB → 1.4MB.
런타임 에셋 합계 17MB → 6.2MB.

## 알려진 과제

- ~~용량~~: KTX2 압축 완료. 런타임 에셋 6.2MB.
  더 줄이려면 노멀맵을 512² 로 낮추거나(UASTC 가 전체의 3/4) 2채널 노멀 압축을 쓴다.
- ~~나무~~: 잎 카드 방식으로 직접 만들었다 (`scene/trees.ts`). 외부 모델 불필요.
- **물**: 별도 에셋 없이 스크롤 노멀맵 + 깊이 페이드 셰이더로 만드는 게 정석이다.
