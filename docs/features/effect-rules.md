# 이펙트 만드는 규칙 ★★

**이펙트를 만들거나 고치기 전에 이 문서를 읽는다.** 2026-09-18 에 사용자가 준
규칙이다 (다른 프로젝트에서 같은 엔진으로 정착시킨 것을 그대로 가져왔다).
앞의 규칙들("전부 파티클로 짓는다")은 이것으로 **대체됐다.**

원문은 다섯 절이다. 이 저장소의 구조가 다른 곳은 **〔여기서는〕** 으로 병기해 둔다.

## 1. 만드는 곳과 도구

- 모델은 바르코, 애니메이션은 블렌더 스크립트, **이펙트는 고도에서 코드로 만든다.**
- 텍스처는 `assets/fx/` 의 흑백 이미지(`impact_flash`, `shockwave_ring`, `fist`,
  `spark`, `scorch` …)를 재활용한다. 웹 버전은 삭제했지만 이 텍스처만 남겼다.
- 흑백 텍스처는 **검은 배경이라 가산(ADD) 혼합 전용.** MIX(알파) 혼합이 필요한
  원형·링은 런타임에 `_alpha_tex()` 가 만든다 (`thunder_fx`, `slam_fx`).
- 새 `class_name` 스크립트를 만들면 한 번 임포트:
  `Godot_v4.7.2-stable_win64_console.exe --headless --path godot --import`

> **〔여기서는〕** `assets/fx/` 흑백 텍스처가 없다 — 이 저장소는 에셋을 안 받은
> 사람도 보여야 해서 **텍스처 없이 코드로만** 짓는다. 그래서 가산/알파 판단은
> 텍스처가 아니라 **무엇을 그리느냐**로 한다: 빛(줄기·섬광)은 가산, 흙(금·파편)은
> 알파. 새 `class_name` 을 만든 뒤 한 번 임포트하는 것은 같다
> (`godot --headless --path godot --import`).

## 2. fx 노드 규격

- `class_name XxxFx extends Node3D`, 파일은 `godot/scripts/xxx_fx.gd`.
- `func setup(point, hit_dir)` 필수. 캐릭터 발 위치까지 필요하면
  `setup_area(point, facing, origin)` 를 두면 `main` 이 `has_method("setup_area")`
  로 그쪽을 먼저 부른다.
- `func tick(dt: float) -> bool` — 시간을 `_process` 로 직접 재지 않고 `main` 이
  `fx_list` 를 돌며 넘겨 준다. **검증 모드의 고정 dt(1/60)와 맞추기 위한 규칙이다.**
  `true` 를 돌려주면 끝난 것으로 보고 목록에서 뺀다.
- 스킬과 연결: `skill_defs.gd` 의 `SKILLS[id]` 에 clip + fx 이름을 적고, `main` 의
  `match` 에 한 줄 추가. 클립의 `hit_at` 비율에서 `character.clip_hit` 시그널이
  나올 때 생성된다.

> **〔여기서는〕** 파일이 `godot/game/xxx_fx.gd` 이고, `World` 가 낸 `skill` 이벤트를
> `game.gd` 의 `_show_skill` 이 받아 `static func` 하나로 띄운다 (`SkillFx.claw`,
> `LightningFx.bolt`). 시간은 각 fx 가 `_process` 로 잰다 — **고정 dt 검증 모드가
> 없어서**다. 헤드리스 확인이 프레임을 세는 방식(`shot.gd`)이라 지금은 이걸로
> 충분하지만, 프레임마다 같은 그림이 나와야 하는 확인이 필요해지면 `tick(dt)`
> 규격으로 옮긴다 → [verification.md](verification.md).

## 3. 표현 방식 규칙 (실측으로 정착한 것) ★★

- **띠·줄기는 `GPUParticles3D` 대신 직접 메시.** 빌보드+속도 정렬이 화면
  세로로만 서서, **양끝이 투명한 마름모/리본 메시**(`SurfaceTool` 정점 색)를
  `MeshInstance3D` 로 만들고 tick 에서 위치·방향·길이·알파를 계산한다.
- **방향은 화면 기준이 아니라 캐릭터 기준.** 길이축은 캐릭터 정면(`dir`)으로 잡고
  **판 법선만 카메라 쪽**(`_to_camera()`)으로 맞춘다. 화면 기준으로 기울인 번개
  시안은 **거절됐다** (늘 왼쪽→오른쪽으로 보임).
- **파티클은 `one_shot`, 만든 다음 프레임에 `emitting` 을 한 번만 켠다.** 같은
  프레임에 켜면 `ThunderFx` 에서 방출이 안 나왔다 (2026-09-18 확인, `SlamFx` 는
  괜찮음 — 원인 미파악).
- 텍스처·재질·바닥 판 만드는 정적 함수는 `SlamFx` 것을 그대로 돌려 쓴다
  (`SlamFx._mat`, `_ground_quad`, `_ease_out`, `_alpha_tex`, `_dust_sheet`).
- **퍼지는 동그란 충격 파동 고리는 쓰지 않는다** — 사용자 요청으로 낙뢰에서 삭제,
  대신 파편을 늘렸다. **번쩍임도 퍼지지 않고 제자리에서 사그라든다.**
- 지면 자국(균열·그을림)은 **연타마다 단계적으로 넓어지고, 마지막 0.8초에
  흐려진다.** 균열 길이는 **캐릭터 키의 1.5~4배.**

> **〔여기서는〕** 캐릭터 키가 1.7m 이므로 균열 길이는 **2.6~6.8m** 다.
> 정적 함수를 돌려 쓰는 자리는 `LightningFx.trail` · `ribbon` · `_half` ·
> `glow` · `dirt` 다 — 다음 이펙트도 이것을 쓴다.

## 4. 확인 방법

화면 밖 창 + 스크린샷이 **필수**다 (창이 사용자 화면을 가리면 지적받는다):

```
Godot_v4.7.2-stable_win64_console.exe --path godot --position 20000,20000 -- \
  --screenshot=out.png --frames=30,45,60 --zoom=14 --skill-at=30:lightning
```

- **프레임 번호 = 시간** (60프레임 = 1초).
- **fps 를 잴 때는 한 장만 찍는다** — 여러 장을 한 번에 찍으면 PNG 저장 지연
  때문에 낮게 나온다.

> **〔여기서는〕** `npm run shot:godot [스킬id]` 가 같은 일을 한다 — 리눅스라
> 창을 옮기는 대신 가상 디스플레이(`xvfb`)에 띄운다. 소프트웨어 렌더라 5~9fps 고
> 고정 프레임이 아니므로 **시간을 0.08배로 늦춰** 여섯 장을 뽑는다
> (`godot/tools/shot.gd`) → [verification.md](verification.md).

## 5. 새 이펙트 시안 낼 때의 경험 규칙 ★★

- **시안은 한 번에 통과하지 않는다.** 낙뢰는 **4차**(주변 7곳 → 강력한 한 방 →
  3연타 → 대각선 겹치기)에서, 곰 발바닥은 할퀴기 거절 후 내리찍기로 정착했다.
- **곁줄기를 따로 기울이면 한 줄기가 세 줄로 갈라져 보이고, 가지가 길면 별개의
  번개처럼 화면을 가로지른다.** 한 줄기를 굵게 보이려면
  **폭만 다른 3겹**(넓은 헤일로 + 색 빛 + 가는 흰 심) +
  **같은 길을 조금 흔든 곁줄기**로 만든다.

## 같이 볼 것

- [skills.md](skills.md) — 스킬별 이펙트가 무엇을 그리는지
- [hit-effects.md](hit-effects.md) — 맞을 때 나는 연출 (숫자·섬광·비네트)
- [verification.md](verification.md) — 찍어서 보는 법
