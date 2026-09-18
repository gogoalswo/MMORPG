# 차원문 모델과 창

모든 존의 차원문 자리에 **돌 아치 모델**을 세우고 구멍에서 **소용돌이**가 돈다.
그 문을 **누르면**(멀리 서 있어도, 또는 걸어 들어가면) 어디로 갈지 고르는 **창**이
뜬다. 창은 그림 한 장이 아니라 **조각을 조립**한 것이고, 목록은 휠로도 **끌어서도**
내려간다.

## 어디

| 파일 | 역할 |
|---|---|
| `godot/game/portal.gd` | `Portal.create(gate)` — 아치 모델을 세운다. 없으면 빛나는 원판. `Portal.hit` — 화면에서 쏜 선이 문에 닿나 |
| `godot/game/portal_swirl.gd` | `PortalSwirl` — 아치 구멍에서 **빨려들어가는 소용돌이**. 나선 팔 5개 + 끌려드는 알갱이 + 가운데 빛 |
| `godot/game/gate_panel.gd` | `GatePanel` — 창. 바탕·칸·글자를 앵커로 조립한다. 목록은 **끌어서** 내린다(`_on_list_input`). 고르면 `picked(zone_id)` |
| `godot/game/game.gd` | `_gate_tapped`(누름 판정) · `_on_gate_tapped`(문 안이면 열고 멀면 걸어감) · `_open_gate` · `_on_gate_pick`(`travel` 요청) |
| `scripts/build-ui.mjs` | UI 조각 원본(1024²)을 쓰는 크기로 줄인다 → `public/assets/ui/` |
| `scripts/fetch-assets.sh` | 바르코 결과물 주소. 포탈 GLB 는 여기서 1024 JPEG 로 줄여 커밋본을 만든다 |
| `scripts/sync-godot-assets.mjs` | `MODELS` 에 `varco_portal.glb`, `UI` 에 조각 셋 |
| `godot/tests/ui_test.gd` | 줄 수·막힌 줄·칸 아이콘·가운데 앵커·아치 윗부분 누르기 |

## 규칙

### UI 는 조각을 조립한다 ★

**그림 한 장으로 그린 창을 붙이지 않는다** (2026-09-18 지시, CLAUDE.md 에도 있다).
해상도가 바뀌어도 앵커로 자리를 잡아야 하기 때문이다.

```
NinePatchRect (panel.png, 여백 PATCH=12) ─ 앵커: 가로 가운데 WIDTH=520, 세로 위아래 6% 비움
 └ MarginContainer (PAD=26)
    └ VBox ─ HBox [제목 "차원문"][닫기]
           └ ScrollContainer ─ VBox ─ 줄마다 Button(flat) [칸 아이콘 ICON=60][존 이름]
```

- 창 바탕은 9분할이라 **어떤 크기로 늘여도 테두리 두께가 그대로**다. 원본 1024 의 테두리가
  약 26px → 256 으로 줄여 7px → 여백 12.
- 글자는 이미지에 굽지 않고 `Label`/`Button.text` 로 얹는다. 존 이름이 바뀌어도 그림을 다시 안 뽑는다.
- 조각이 없어도(`sync:godot` 을 안 돌렸어도) 창은 뜬다 — 바탕 대신 어두운 `ColorRect`.

### 칸 아이콘 둘

참고 그림(디아블로 웨이포인트)처럼 **지금 서 있는 곳만 소용돌이**에 흐린 글씨로
막고, 나머지는 **별**이다. 잠긴 곳은 없다 — 아무 사냥터나 갈 수 있다는 규칙은
그대로다 ([world-zones.md](world-zones.md) 의 "잠그지 않는다").

### 문을 누르면 ★

- **판정은 바닥 점이 아니라 화면에서 쏜 선**으로 한다. 아치는 높이(`HIT_HEIGHT=5`)가
  있어서 윗부분을 누르면 바닥 점은 문 뒤의 땅이 된다. 선에서 높이 0~5 구간을 잘라
  문 축과의 수평 거리가 반지름 안이면 문이다.
- **거리와 상관없이 바로 창이 뜬다** (2026-09-18 요청: "포탈까지 안 걸어가도
  클릭하면 UI 열리게"). 그 전에는 문 밖에서 누르면 문 가운데로 **걸어갔고**,
  들어서야 `gate` 이벤트가 창을 열었다 — 멀리서 한 번 누르고 기다려야 했다.
- 걸어 들어가는 길은 그대로다. 문 안에 들어서면 `World` 가 `gate` 이벤트를 내고
  그것도 창을 연다 — 창을 닫고 다시 열려면 문을 한 번 벗어나야 한다(`player.at_gate`).
- 고른 곳은 여전히 `travel` 요청이고 **있는 존인지 `World` 가 다시 본다.**

### 목록은 끌어서 내린다 ★

휠로만 내려가던 것을 **누른 채 끌어서**도 내려가게 했다 (2026-09-18 요청).
`ScrollContainer` 에 오는 입력을 `GatePanel._on_list_input` 이 직접 받는다:

- 누른 자리에서 **`DEADZONE`(14px) 넘게 움직이면 끌기**, 그 자리에서 떼면 **고르기**다.
  그래서 목록을 쓸어 넘기다가 손을 뗀 자리의 사냥터로 떠나 버리지 않는다.
- 줄(`Button`)은 **입력을 받지 않는다**(`MOUSE_FILTER_IGNORE`). 줄이 먼저 받으면
  끌다 뗀 자리에서 `pressed` 가 나온다. 어느 줄을 골랐는지는 `_pick_at` 이 줄
  상자와 견줘 정하고, 존 id 는 줄의 `set_meta("zone", …)` 에 있다.
- **엔진에도 끌기가 있지만 쓰지 않는다.** `ScrollContainer` 의 것은 터치 화면일
  때만 켜지고(`emulate_touch_from_mouse` 로 켤 수는 있다), 그러면 폰에서는 손가락
  이벤트와 **엔진이 흉내 낸 마우스 이벤트가 겹쳐 두 배로** 내려간다. 그래서
  손가락 이벤트는 `_on_list_input` 이 삼키고, 흉내 낸 마우스 쪽만 쓴다.
- 휠은 그대로 `ScrollContainer` 가 받는다 (`accept_event` 를 안 부른다).
- 막대 굵기는 `BAR_WIDTH`(18) — 손가락으로 집을 수 있어야 한다.

### 소용돌이 ★

아치 구멍 가운데에서 **빨려들어가는 소용돌이**가 돈다 (2026-09-18 요청).
[effect-rules.md](effect-rules.md) 대로 **고도에서 코드로** 만들었고, 띠는
파티클이 아니라 직접 메시다 (`LightningFx._half` · `glow` 를 돌려 쓴다).

- **로그 나선 팔 5개.** 자기닮음 곡선이라 **돌리기만 하면 무늬가 안으로 흘러
  보인다**(회전 = 축소). 그래서 부호가 중요하다 — `+` 로 돌리면 뿜어 나오는 것이 된다.
- **알갱이 18개**가 안쪽으로 끌려 들어간다. 각속도는 1/r 이라 가운데에서 빨라지고,
  작아지다 삼켜지면 바깥에서 다시 나온다.
- **가운데 빛**과 문 색 등(`OmniLight3D`) 하나. 등은 밤 사냥터에서 문만 떠 있지
  않게 바닥을 물들인다.
- 크기는 **문 반지름의 비율**이다(`CENTER` 0.47 · `SPAN` 0.22). 모델이 1×1×1 로
  정규화돼 있어 비율로 두면 문이 커져도 구멍 한가운데에 남는다.
- **깊이 검사를 켠다.** 스킬 이펙트는 몸 앞을 스치고 사라져서 껐지만, 이건 월드에
  계속 서 있는 것이라 끄면 앞을 지나는 캐릭터를 뚫고 보인다.
- 모델이 없어도(에셋을 안 받았어도) 원판 위에서 그대로 돈다.
- 확인은 `npm run shot:godot -- portal` ([verification.md](verification.md)).

### 모델

바르코 3D 는 **1×1×1 로 정규화, 원점이 한가운데**로 나온다. `Portal.create` 가
받침 폭 = 2 × 반지름(문 판정 원)으로 늘리고 바닥에 앉히고, 정면(+z)을 카메라
쪽(`CameraRig.YAW`)으로 돌린다. 움직이지 않는 모델이라 `Rig` 을 거치지 않는다.

원본은 2048 PNG 텍스처 셋이라 10MB → 커밋본은 1024 JPEG 0.8MB →
고도 사본은 다른 모델처럼 512 ([godot-migration.md](godot-migration.md) 의 "512px").

## 손댈 때

- 창 크기·글자 크기·아이콘 크기는 `GatePanel` 맨 위 상수다. 바탕 그림을 바꾸면 테두리를 재서 `PATCH` 를 맞춘다.
- 소용돌이 모양·빠르기는 `PortalSwirl` 맨 위 상수다. **고쳤으면 찍어서 보고 나서** "됐다" 고 한다.
- 조각을 새로 받으면 `fetch-assets.sh` 에 `fetch_ui` 줄, `build-ui.mjs` 의 `PIECES`, `sync-godot-assets.mjs` 의 `UI` 셋을 같이 고친다.
- 문 자리·반지름·색은 `packages/shared` 의 `GATE_*` 다 ([world-zones.md](world-zones.md)).

## 관련

- [effect-rules.md](effect-rules.md) — 이펙트 규칙(소용돌이를 만든 근거)
- [world-zones.md](world-zones.md) — 차원문 규칙(모든 존의 같은 자리, 마을이 맨 위)
- [godot-migration.md](godot-migration.md) — "차원문은 알리기만 한다", 에셋 복사
- [../ASSETS.md](../ASSETS.md) — 바르코 결과물 출처
