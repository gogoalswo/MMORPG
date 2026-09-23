# 에셋 출처와 라이선스

이 프로젝트에 포함된 모든 **외부** 에셋은 **CC0 1.0 (퍼블릭 도메인)** 이다.
출처 표기 의무가 없고 상업적 사용에 제한이 없다.
예외는 VARCO 로 직접 생성한 것 — [바닥 텍스처](#지면-텍스처--varco-생성) 7장과
[캐릭터](#캐릭터-모델--varco-생성-격투가마법사궁수) 셋, 오우거 다섯, 격투가 스킬 그림 한 장이다 —
받아온 게 아니라 우리가 만든 것이라 라이선스가 아니라 **약관**이 걸린다.

> 새 에셋을 추가할 때는 **반드시 이 표에 먼저 기록한다.**
> 나중에 상용화 시점에 "이건 어디서 받았더라"를 역추적하는 건 불가능에 가깝다.
> 라이선스가 불분명한 에셋은 넣지 않는다.

## 한글 폰트 — Noto Sans KR (SIL OFL 1.1)

출처: Google Fonts (https://fonts.google.com/noto/specimen/Noto+Sans+KR) · **SIL Open Font License 1.1**

CC0 는 아니지만 OFL 은 **임베딩·상업적 사용에 제한이 없다.** 폰트 파일을 팔지만
않으면 된다. 저작권 표시는 폰트 파일 안에 그대로 들어 있다.

| 파일 | 크기 | 쓰는 곳 |
|---|---|---|
| `public/assets/fonts/NotoSansKR-subset.ttf` | 436KB | 고도 클라이언트 UI 전부 |

원본 5.9MB 에서 **완성형(KS X 1001) 2350자 + ASCII 만 남겼다.** 웹 빌드가 이미
51MB 라 통째로 넣으면 폰에서 받을 것만 늘어난다. 다시 만들려면:

```bash
pip install fonttools
python3 scripts/build-korean-font.py 받아둔/NotoSansKR.ttf
```

**결과물을 커밋하므로 보통은 돌릴 일이 없다.** 글꼴을 바꾸거나 없는 글자가
네모로 나올 때만 돌린다. 고도가 쓰는 자리로는 `npm run sync:godot` 이 복사한다.

## 지면 텍스처 — VARCO 생성

출처: 바르코 3D (https://3d.varco.ai) 로 만든 타일 이미지 · **CC0 아님** (약관은 아래 캐릭터 절과 같다)

| 원본 | 바닥 종류 | 쓰는 곳 |
|---|---|---|
| `map1.png` 돌판 | `stone` | 마을 |
| `map2.png` 풀 | `grass` | 초원·덤불숲·안개 늪·검은 삼림·뒤틀린 숲·빛바랜 고원 |
| `map3.png` 눈 | `snow` | 서리 고원·얼어붙은 심연 |
| `map4.png` 마른 땅 | `dirt` | 메마른 협곡·잿빛 황야·소금 평원·그림자 계곡 |
| `map5.png` 모래 | `sand` | 붉은 사막·유황 분지 |
| `map6.png` 자갈 | `cobble` | 무너진 성터·폐허 도시·심연의 문턱 |
| `map7.png` 용암 균열 | `lava` | 화산재 언덕·균열 지대·종말의 대지 |

1024² PNG **색 한 장씩**이다(합쳐 14MB). 일곱 장 모두 이음새 없이 이어진다 —
이어 붙이는 자리의 픽셀 차이가 이미지 안쪽 이웃 픽셀 차이의 0.97~1.65배다
(눈이 가장 크지만 명암이 옅어 안 보인다). `scripts/build-ground-textures.mjs` 가
- 2×2 평균으로 512² 로 줄인다 — sharp 의 resize 는 가장자리를 복제해서 타일 이음새에 줄이 생긴다
- **밝기를 높이로 봐서 노멀맵을 만든다.** 받은 게 색뿐이다. 러프니스는 종류마다 상수(`ground.ts` 의 `LOOKS`)
- `assets-src/textures/ground_<종류>_{color,normal}.jpg` 로 쓴다 → `npm run compress` 가 KTX2 로
  누른다(색 ETC1S, 노멀 UASTC) → 14장 **2.5MB**, 부팅 때 전부 받는다

원본은 `assets-src/textures/varco/map1~7.png`. **결과물 주소가 없다** — 받아 둔 파일로
만들었다. `fetch-assets.sh` 는 원본이 있을 때만 만든다.

예전 ambientCG 텍스처(Grass005·Ground037·Rock063, CC0)는 2026-09-10 에 뺐다.
`fetch-assets.sh` 도 더는 받지 않는다.

## 캐릭터 모델 — KayKit (뺐다)

KayKit Character Pack : Adventurers 1.0 (Kay Lousberg, CC0) 다섯
(`knight` `mage` `rogue` `rogue_hooded` `barbarian`)과 화살통(`accessories/quiver.*`)은
**2026-09-10 에 뺐다.** 직업 셋은 VARCO 모델로 갈아탔고, NPC 는 원래 절차적 리그라
쓰는 곳이 없었다. 되살리려면 git 기록에서 `fetch-assets.sh` 의 `fetch_character` 줄을 찾는다.

## 몬스터 모델 — Quaternius (뺐다)

Quaternius 짐승·공룡 20종(CC0, 미러 trebeljahr/quaternius-showcase)은
**2026-09-10 에 뺐다.** 몬스터는 VARCO 오우거(아래 캐릭터 절)로 갈아탈 예정이고,
배치 전까지는 전부 절차적 리그로 나온다. 되살리려면 git 기록에서
`fetch-assets.sh` 의 `fetch_beast` 줄을 찾는다.

## 캐릭터 모델 — VARCO 생성 (격투가·마법사·궁수)

출처: 바르코 3D (https://3d.varco.ai) 커스텀 워크플로우 격투가·마법사·궁수 결과물 · **CC0 아님**

받아온 에셋이 아니라 **우리가 그 서비스로 만든 결과물**이다. 그래서 라이선스가
아니라 VARCO 의 이용약관이 적용된다 — 상용화 전에 생성물 권리 조항을 확인해야
한다. 위 표들과 성격이 다르므로 절을 따로 뒀다.

**기사(`varco_knight.glb`)는 2026-09-17 에 지웠다** — 요청대로 격투가를 기본
캐릭터로 삼으면서 모델 파일과 `fetch-assets.sh` 의 취득 주소(`knight_rigged` ·
동작 여섯 `anim_*`)를 같이 뺐다. 되살릴 일이 생기면 그 커밋 이전의 `git show` 로
꺼낸다. 기사만 리깅 결과물을 따로 받았고, 남은 셋은 아래처럼 동작 파일로 왔다.

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

격투가도 같은 방식이다 (2026-09-11). 받은 파일 이름(`격투가-Animate-격투가-1`, `-1-2`, `-1-3`, `-1-4`)에
동작이 안 드러나서 재서 가렸다 — [characters-and-animation.md](features/characters-and-animation.md).

| 원본 | 우리 파일 | 쓰는 곳 |
|---|---|---|
| `-1` 대기 | `assets-src/models/varco/fighter_idle.glb` | 메시·뼈대 + `Idle` |
| `-1-2` 달리기 | `fighter_run.glb` | `Run` |
| `-1-3` 공격(차기) | `fighter_attack.glb` | `Attack` |
| `-1-4` 사망 | `fighter_death.glb` | `Death` |
| 합친 결과 | `public/assets/models/varco_fighter.glb` (2.4MB) | 격투가 직업 |
| 같이 온 `skill.png` (1024², 빛나는 주먹) | `public/assets/fx/fist.png` (256², 69KB) | 격투가 스킬 명중 이펙트 (`SkillFx.fist`) |
| GenerateImage (나노바나나 프로·영어 프롬프트, 2026-09-12) — 발톱 자국과 붉은 불티가 사방으로 터지는 충격 (발톱 자국이 더 또렷한 판도 같이 나왔지만, 작게 떠도 어느 방향에서나 읽히는 이쪽을 골랐다) | `public/assets/fx/hit.png` (256², 80KB), 원본 `assets-src/textures/varco/fx_hit.png` (1024²) | **캐릭터 피격** 이펙트 (`SkillFx.hurt`) — 몬스터가 맞을 때는 안 쓴다 |
| 바르코 **워크플로우 화면을 찍은 것** (2026-09-16) — 까만 바탕에 파랑·초록 네온 선으로 그린 맹금의 발, 발톱 끝에 주황 불빛 | `public/assets/fx/sky_foot.png` (512², **회색조**, 83KB), 원본 `assets-src/textures/varco/fx_sky_foot_src.png` (217×417) | **'천붕각' 의 떨어지는 발** (`SkillFx.skyBreaker`). 예전에 쓰던 `kick_flurry.png` 를 갈아 끼웠다. **회색조로 커밋한다** — 코드가 금색(0xffc23c)을 입힌다 |
| **우리가 코드로 만든다** (외부 에셋이 아니다) — 흐릿한 덩이 열한 개를 뭉친 먼지 구름 | `public/assets/fx/dust.png` (256², **RGBA**, 16KB) | '천붕각' 이 밟은 자리에서 터지는 먼지 (`SkillFx.skyBreaker` 의 `DUST`). **알파가 있어야 한다** — 이것만 보통 혼합으로 그리므로, 알파가 없으면 까만 네모가 된다 |

`fist.png`·`sky_foot.png`·`hit.png`·`dust.png` 는 한 번 만들어 **그대로 커밋한다** — `fetch-assets.sh` 가 다시 만들지 않는다.

### 천붕각의 발 (`sky_foot.png`) 은 출력물이 아니라 화면 캡처다 ★

다른 그림은 전부 GenerateImage 의 **출력물 주소**를 `fetch-assets.sh` 에 박아 두었는데,
이것만 워크플로우 편집기 화면을 찍은 것이라 **받아 올 주소가 없다.** 원본을
`assets-src/textures/varco/fx_sky_foot_src.png` 로 남겨 두었고, 게임이 쓰는 판은
거기서 sharp 로 이렇게 만들었다.

1. `trim({threshold:18})` — 캡처의 테두리를 뗀다 (208×373 이 남는다)
2. 512² 까만 판 한가운데에 비율을 지켜 앉힌다 (긴 쪽 452px, 여백 6%)
3. **회색조로 바꾼다** (`grayscale().linear(1.35)`) — 색은 코드가 입힌다
4. **번짐을 더한다** — `blur(5)×0.85` 와 `blur(16)×0.5` 를 가산 합성. 네온 선이
   1~2픽셀이라 그냥 쓰면 거리 40 짜리 카메라에서 사라진다
5. **위쪽 42% 를 smoothstep 으로 지운다** — 원본 캡처에 **다리가 잘려** 들어 있어서,
   그대로 쓰면 하늘에서 싹둑 잘린 채로 내려온다 (2026-09-16 지적)

**`grayscale()` 은 `composite` 와 같은 파이프라인에 두면 안 먹는다.** 붙여 놓고 돌렸더니
색이 그대로 남아 있었다 — `toColourspace('srgb')` 가 뒤에 오면 회색조 지정이 덮인다.
앉히기까지 한 판을 버퍼로 꺼내 **회색조는 따로 한 번 더** 돌린다.

**512² 인 이유도 그것이다.** 다른 그림은 256² 인데, 이건 가는 선뿐이라 256 으로 줄이면
선이 뭉개진다. 화면에서 6.5m(세로의 31%, 1080p 기준 330픽셀)로 뜨므로 512 가 맞다.

**회색조로 커밋하는 이유.** 처음엔 원본의 네온색(파랑·초록)을 살리려고 코드에서 흰빛으로
띄웠다. 그런데 "노랑으로 바꿔 달라" 는 요청이 오자 **방법이 없었다** — 파란 그림에 노랑을
곱하면 까맣게 죽는다. 호포각에서 이미 겪은 일이고 답도 같다. 회색조면 색은 `skillColor`
한 줄이다 (지금은 0xffc23c).

### 먼지 구름 (`dust.png`) 은 코드로 만든다

바르코에 맡길 것이 아니다 — 필요한 건 **흐릿한 덩이 하나**뿐이고, 그건 난수 몇 줄이면 된다.
흰 덩이 열한 개를 중심 근처에 뿌려 `(1−d²)^1.6` 로 겹치고, `blur(6)` 으로 뭉갠 뒤,
**가장자리를 확실히 0 으로** 깎는다 (텍스처 테두리에 잘린 자국이 남으면 네모로 보인다).

**RGB 는 전부 흰색이고 모양은 알파에만 넣는다.** 이 그림만 보통 혼합(`blend: 'normal'`)으로
그리기 때문이다 — 알파 없이 까만 바탕을 두면 보통 혼합에서는 **까만 네모**가 그려진다
(가산 혼합이면 까만 바탕이 저절로 빠지므로 다른 그림들은 RGB 로 둔다).

**마법사·궁수·격투가는 받은 파일로 만든다** — 결과물 주소는 박지 않았다.
`fetch-assets.sh` 는 원본이 `assets-src/models/varco/` 에 있을 때만 만들고,
없으면 건너뛴다(그 직업은 절차적 리그로 나온다).

**오우거 5종**(워크플로우 "오우거" Type1~5)도 같은 방식이다. 몬스터 외형으로 쓸
리소스다. 지금은 `varco_ogre1` 만 초원 몬스터에 걸었다. 받은 파일 이름에 동작이 안
드러나서 동작 데이터를 재서 가렸다 (다섯 타입의 순서가 같다).

| 원본 | 우리 파일 (N = 1~5) | 쓰는 곳 |
|---|---|---|
| `오우거-Animate-오우거-1` | `assets-src/models/varco/ogreN_idle.glb` | 메시·뼈대 + `Idle` |
| `…-1-2` | `ogreN_run.glb` | `Run` |
| `…-1-3` | `ogreN_attack.glb` | `Attack` |
| `…-1-4` | `ogreN_death.glb` | `Death` |
| 합친 결과 | `public/assets/models/varco_ogreN.glb` (2.4~2.8MB) | 몬스터 외형 — 지금은 `varco_ogre1` 만 초원 |

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

## 장비 — KayKit 액세서리 (뺐다)

화살통(`quiver.gltf` + `quiver.bin` + `rogue_texture.png`, CC0)은 KayKit 캐릭터와
함께 **2026-09-10 에 뺐다.** VARCO 궁수에는 매달 `chest` 뼈가 없어서 원래 붙지 않았다.

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
  textures/varco/map1~7.png   바닥 원본 (VARCO, 1024² 색 한 장씩)
  textures/ground_*.jpg       build-ground-textures 가 만든 색·노멀 (KTX2 재인코딩용)
  models/*.glb         KayKit·Quaternius 원본 — 2026-09-10 에 뺀 것. 남아 있으면 지워도 된다
  models/varco/*.glb   VARCO 워크플로우 결과물 (합치기 전, 격투가·마법사·궁수 각 4개 48~51MB 남짓 + 오우거 5종 각 4개 52~60MB)
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
1024² 한 장이 VRAM 4MB 다. KTX2(Basis Universal)는 압축된 채로
GPU 에 올라가서 다운로드와 VRAM 을 동시에 줄인다.

맵 종류마다 인코딩이 다르다:

| 종류 | 방식 | 이유 |
|---|---|---|
| `_color` | ETC1S + sRGB | 눈이 색 오차에 관대하다. 가장 세게 줄인다 (~90% 감소) |
| `_normal` | UASTC + zstd | ETC1S 로 누르면 법선이 뭉개져 요철이 계단처럼 보인다 |
| `_rough` | ETC1S + 선형 | 단일 채널 데이터라 오차가 잘 안 보인다 |

지금 바닥 14장(512², 색 ETC1S 50~75KB · 노멀 UASTC 0.3MB)은 JPEG 1.8MB → KTX2
**2.5MB** 로 오히려 커진다 — 대신 GPU 에 압축된 채로 올라간다. `_rough` 는 지금 쓰는
파일이 없다(바닥 러프니스는 상수). 예전 ambientCG 9장(1024²)은 11.8MB → 4.2MB 였다.
HDRI 는 2k → 1k 로 낮춰 5.2MB → 1.4MB.

## 알려진 과제

- 바닥 용량의 85% 가 노멀맵(UASTC)이다. 더 줄이려면 노멀을 256² 로 낮추거나
  2채널 노멀 압축을 쓴다.
- ~~나무~~: 잎 카드 방식으로 직접 만들었다 (`scene/trees.ts`). 외부 모델 불필요.
- **물**: 별도 에셋 없이 스크롤 노멀맵 + 깊이 페이드 셰이더로 만드는 게 정석이다.

## 차원문 모델·창 UI — VARCO 생성

출처: 바르코 3D 커스텀 워크플로우 **"포탈"** 결과물 · **CC0 아님** (위 캐릭터 절과 같은 약관).
받는 주소는 `scripts/fetch-assets.sh`, 쓰는 법은 [features/portal-ui.md](features/portal-ui.md).

| 원본 | 우리 파일 | 쓰는 곳 |
|---|---|---|
| 돌 아치 3D (2048 PNG ×3, 10MB) | `public/assets/models/varco_portal.glb` (1024 JPEG, 0.8MB) | 모든 존의 차원문 |
| 창 바탕 (1024²) | `public/assets/ui/panel.png` (256², 9분할) | 차원문 창 |
| 소용돌이 칸 | `public/assets/ui/gate_here.png` (128²) | 지금 서 있는 곳 |
| 별 칸 | `public/assets/ui/gate_go.png` (128²) | 갈 수 있는 곳 |
