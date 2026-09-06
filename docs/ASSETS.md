# 에셋 출처와 라이선스

이 프로젝트에 포함된 모든 외부 에셋은 **CC0 1.0 (퍼블릭 도메인)** 이다.
출처 표기 의무가 없고 상업적 사용에 제한이 없다.

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

| 팩 | 원본 | 우리 파일 | 쓰는 곳 |
|---|---|---|---|
| Animals | `Wolf.glb` | `wolf.glb` | 늑대류 (초원·서리고원·그림자계곡) |
| Animals | `Husky.glb` | `husky.glb` | 사냥개류 (잿빛황야·화산재) |
| Animals | `Bull.glb` | `bull.glb` | 멧돼지·곰류 (덤불숲·검은삼림) |
| Animals | `Stag.glb` | `stag.glb` | 뿔짐승 (협곡·소금평원·창백한고원) |
| Easy Enemies | `Spider.glb` | `spider.glb` | 벌레류 (늪·사막·심연) |
| Dinosaurs | `Trex.glb` | `trex.glb` | 종말의 대지 + 보스 |
| Dinosaurs | `Velociraptor.glb` | `velociraptor.glb` | 도마뱀류 + 보스 |
| Dinosaurs | `Triceratops.glb` | `triceratops.glb` | 골렘·수호자류 + 보스 |
| Dinosaurs | `Stegosaurus.glb` | `stegosaurus.glb` | 수호병·고목류 + 보스 |

각 파일에 **대기·걷기·달리기·공격·사망** 다섯 클립만 남겼다 (원본 12~13개).
종류마다 뼈대가 달라서 클립을 공유할 수 없다 — 파일마다 자기 것을 들고 있다.

색은 몬스터 종류의 `bodyColor` 를 곱해서 낸다. 그냥 곱하면 어두워지므로
밝기를 1 로 되돌린 뒤 색조만 입힌다 (`modelRig.tintedMaterial`).

**부팅 때 다 받지 않는다.** 사냥터 하나에 두세 종뿐이라, 존을 옮길 때
필요한 것만 받는다 (`Models.ensureBeasts`). 마을에서는 한 개도 안 받는다.

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
