#!/usr/bin/env bash
# 에셋을 다시 받아 public/assets 에 배치한다.
# 원본(zip/hdr/glb)은 저장소에 커밋하지 않으므로, 새로 클론했을 때 이 스크립트를 돌린다.
# 출처와 라이선스는 docs/ASSETS.md 참고 — 받아 온 외부 에셋은 전부 CC0 1.0 이고,
# VARCO 로 만든 바닥 텍스처와 캐릭터는 우리가 직접 생성한 것이다.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p assets-src/textures public/assets/textures public/assets/hdri public/assets/basis

# 바닥 텍스처 — 바르코로 만든 타일 이미지 7장(map1~7.png). 출처와 약관은 docs/ASSETS.md.
# 결과물 주소를 아직 못 박았다 — 받아 둔 원본(assets-src/textures/varco/map*.png)이 있을 때만 만든다.
# 여기서는 JPEG(색 + 밝기로 만든 노멀)까지만 만든다. 배포되는 .ktx2 는 `npm run compress` 가 누른다.
if [ -f assets-src/textures/varco/map1.png ]; then
  node scripts/build-ground-textures.mjs
else
  echo "건너뜀: 바닥 텍스처 — 원본(assets-src/textures/varco/map1~7.png)이 없다"
fi

if [ ! -f assets-src/sky_2k.hdr ]; then
  echo "받는 중: HDRI"
  curl -sL --max-time 300 -o assets-src/sky_2k.hdr \
    "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
fi
cp assets-src/sky_2k.hdr public/assets/hdri/sky_2k.hdr
echo "  -> public/assets/hdri/sky_2k.hdr"

# ---------------------------------------------------------------- VARCO 캐릭터

# 바르코(3d.varco.ai) 커스텀 워크플로우의 결과물로 캐릭터를 만든다.
# 리깅된 메시 하나 + 동작들이 **파일 여럿**으로 나온다. 각 파일에 메시와
# 2048² 텍스처가 통째로 다시 들어 있어서 그대로 받으면 수십 MB 다 — 애니메이션만
# 뽑아 한 파일로 합치고 텍스처를 1024² JPEG 으로 줄인다.
#
# 박아 두는 주소는 워크플로우를 한 번 돌린 **결과물**이다. 다시 돌리면 다른
# 캐릭터가 나오므로(생성 모델이라 같은 프롬프트로도 같은 결과가 안 나온다)
# 프롬프트가 아니라 결과물 주소를 박아 둔다. 주소가 죽으면 워크플로우를
# 다시 돌리고 여기 해시를 갈아 끼운다.
#
# **기사는 2026-09-17 에 지웠다** (요청: 격투가를 기본 캐릭터로). 기사 메시
# (`knight_rigged`)와 그 동작 여섯(`anim_*`)의 주소도 같이 뺐다 — 되살릴 일이
# 생기면 이 커밋 이전의 `git show` 로 꺼낸다.
VARCO="https://3d.varco.ai/api/objects"

fetch_varco() { # $1=객체 해시  $2=출력 이름
  if [ ! -f "assets-src/models/varco/$2.glb" ]; then
    echo "받는 중: varco/$2.glb"
    curl -sL --max-time 300 -o "assets-src/models/varco/$2.glb" "${VARCO}/$1.glb"
  fi
}

mkdir -p assets-src/models/varco

mkdir -p assets-src/textures/varco

# '천붕각' 의 떨어지는 발(fx/sky_foot.png)은 **받아 올 주소가 없다** — 워크플로우 화면을
# 찍은 것이라 출력물 URL 이 아니다. 원본은 assets-src/textures/varco/fx_sky_foot_src.png,
# 게임이 쓰는 512² **회색조** 판은 커밋해 두었다. 만드는 법은 docs/ASSETS.md.
# 먼지 구름(fx/dust.png)도 여기서 안 받는다 — 바르코가 아니라 코드로 만든 그림이다.
# (예전에 쓰던 kick_flurry.png 는 지웠다. 주소가 필요하면 이 파일의 이력에 있다)

# 호포각 — 포효하는 호랑이 머리. 받는 원본은 주황이지만, 게임에 쓰는 판은
# **회색조로 바꿔서** 커밋했다 (sharp 의 grayscale + linear(1.25)). 그래야 코드에서
# 색을 입힐 수 있다 — 주황 그림에 파랑을 곱하면 탁한 녹색이 된다.
# 까만 바탕에 **불꽃 선으로만** 그려서
# 가산 혼합에 얹으면 바탕이 저절로 빠지고 겹쳐도 뭉개지지 않는다.
# 같은 실행에서 두 장이 나왔는데(다른 하나는 d597eed9…) 속을 색으로 채운 쪽이라 안 썼다.
if [ ! -f assets-src/textures/varco/fx_tiger_roar.png ]; then
  echo "받는 중: textures/varco/fx_tiger_roar.png"
  curl -sL --max-time 120 -o assets-src/textures/varco/fx_tiger_roar.png "${VARCO}/7e7e10aa5498c117edb792114d0a65cb.png"
fi

# 백호격 — 오른쪽으로 도약하는 백호 옆모습. **옆모습이라 방향이 있다**: 코드가 화면에서
# 왼쪽으로 갈 때 좌우로 뒤집는다 (skillFx 의 flipX). 같은 실행의 다른 판(4ef9eaad…)은
# 몸이 위로 솟아 도약에 가까웠고, 이쪽이 수평으로 길게 뻗어 달리는 것으로 읽혔다.
if [ ! -f assets-src/textures/varco/fx_white_tiger.png ]; then
  echo "받는 중: textures/varco/fx_white_tiger.png"
  curl -sL --max-time 120 -o assets-src/textures/varco/fx_white_tiger.png "${VARCO}/d936deb7ebf6fe5c48389f90ec878465.png"
fi

# 캐릭터 피격 — 발톱 자국과 붉은 불티. 작게 뜨므로 사방으로 고르게 퍼진 판을 골랐다
# (발톱 자국이 더 또렷한 7c6d0d07… 도 같이 나왔다).
if [ ! -f assets-src/textures/varco/fx_hit.png ]; then
  echo "받는 중: textures/varco/fx_hit.png"
  curl -sL --max-time 120 -o assets-src/textures/varco/fx_hit.png "${VARCO}/714ba0443e09383d73e4424237ceae53.png"
fi

# 차원문 — 바르코 워크플로우 "포탈". 3D 는 움직이지 않는 돌 아치 하나(1×1×1 로 정규화,
# 가운데가 원점). 원본은 2048 PNG 텍스처 셋이라 10MB 인데 1024 JPEG 으로 줄여 커밋한다(0.8MB).
fetch_varco 9af24ed7f19f04fc1b5d5b0c3bef567a portal
node scripts/shrink-glb-textures.mjs assets-src/models/varco/portal.glb public/assets/models/varco_portal.glb 1024

# 차원문 창 UI 조각 — 같은 워크플로우. 창 바탕·소용돌이 칸·별 칸을 **따로** 받아 고도에서
# 조립한다 (docs/features/portal-ui.md). 원화 두 장(9fbb5d1f… 9dfeff2c…)은 3D 를 뽑은 그림이라 안 받는다.
fetch_ui() { # $1=객체 해시  $2=출력 이름
  if [ ! -f "assets-src/textures/varco/$2.png" ]; then
    echo "받는 중: textures/varco/$2.png"
    curl -sL --max-time 120 -o "assets-src/textures/varco/$2.png" "${VARCO}/$1.png"
  fi
}
fetch_ui df878fd4c5f48b8454dc6c40228e7803 ui_panel
fetch_ui 4d62d8a36f11dac8d3388b657a8bed00 ui_gate_here
fetch_ui f97809fc5aefbfd9987fd6e2dcdd5454 ui_gate_go
node scripts/build-ui.mjs

# 클립 이름 = 파일. **역슬래시로 줄을 잇지 않는다** — 이 파일은 CRLF 라서
# 줄 끝 역슬래시 다음에 CR 이 오면 bash 가 줄바꿈이 아니라 CR 이스케이프로 읽고 거기서 끊는다.
# #loop = 반복 재생이라 한 주기로 잘라 시작·끝을 맞춘다
# #face = 클립에 구워진 몸 방향을 되돌린다 — 둘 다 build 스크립트의 closeLoop

# 마법사 — 대기·달리기·공격 세 파일. 리깅 결과물을 따로 안 받고 대기 파일을
# 기본으로 쓴다: 세 파일의 뼈대가 Root 의 쉬는 위치만 빼고 같고, Root 위치는
# 모든 클립이 움직이므로 어느 걸 기본으로 써도 같다.
# **결과물 주소를 아직 못 박았다.** 받아 둔 원본(assets-src/models/varco/mage_*.glb)
# 이 있을 때만 만든다. 주소를 알게 되면 위처럼 fetch_varco 줄로 바꾼다.
MAGE_CLIPS=()
MAGE_CLIPS+=("Idle=assets-src/models/varco/mage_idle.glb")
# 달리기에 구워진 방향은 -94.6° 였다
MAGE_CLIPS+=("Run=assets-src/models/varco/mage_run.glb#loop#face")
MAGE_CLIPS+=("Attack=assets-src/models/varco/mage_attack.glb")
MAGE_CLIPS+=("Death=assets-src/models/varco/mage_death.glb")
if [ -f assets-src/models/varco/mage_idle.glb ] && [ -f assets-src/models/varco/mage_run.glb ] && [ -f assets-src/models/varco/mage_attack.glb ] && [ -f assets-src/models/varco/mage_death.glb ]; then
  node scripts/build-varco-character.mjs public/assets/models/varco_mage.glb assets-src/models/varco/mage_idle.glb "${MAGE_CLIPS[@]}"
else
  echo "건너뜀: varco_mage — 원본이 없다 (마법사는 절차적 리그로 나온다)"
fi

# 궁수 — 마법사와 같은 방식(받은 파일 넷, 대기 파일이 기본)
ARCHER_CLIPS=()
ARCHER_CLIPS+=("Idle=assets-src/models/varco/archer_idle.glb")
ARCHER_CLIPS+=("Run=assets-src/models/varco/archer_run.glb#loop#face")
ARCHER_CLIPS+=("Attack=assets-src/models/varco/archer_attack.glb")
ARCHER_CLIPS+=("Death=assets-src/models/varco/archer_death.glb")
if [ -f assets-src/models/varco/archer_idle.glb ] && [ -f assets-src/models/varco/archer_run.glb ] && [ -f assets-src/models/varco/archer_attack.glb ] && [ -f assets-src/models/varco/archer_death.glb ]; then
  node scripts/build-varco-character.mjs public/assets/models/varco_archer.glb assets-src/models/varco/archer_idle.glb "${ARCHER_CLIPS[@]}"
else
  echo "건너뜀: varco_archer — 원본이 없다 (궁수는 절차적 리그로 나온다)"
fi

# 격투가 — 궁수와 같은 방식. 받은 파일: 격투가-Animate-격투가-1 = 대기, -1-2 = 달리기, -1-3 = 공격, -1-4 = 사망
# (클립 이름이 비어 있어 길이·동작 폭을 재서 가렸다 — characters-and-animation.md)
# 공격은 #face 를 안 붙인다: 골반이 -70° 쯤 틀어진 건 격투 자세이고, 차는 발은 정면(7°)으로 나간다.
FIGHTER_CLIPS=()
FIGHTER_CLIPS+=("Idle=assets-src/models/varco/fighter_idle.glb")
FIGHTER_CLIPS+=("Run=assets-src/models/varco/fighter_run.glb#loop#face")
FIGHTER_CLIPS+=("Attack=assets-src/models/varco/fighter_attack.glb")
FIGHTER_CLIPS+=("Death=assets-src/models/varco/fighter_death.glb")
if [ -f assets-src/models/varco/fighter_idle.glb ] && [ -f assets-src/models/varco/fighter_run.glb ] && [ -f assets-src/models/varco/fighter_attack.glb ] && [ -f assets-src/models/varco/fighter_death.glb ]; then
  node scripts/build-varco-character.mjs public/assets/models/varco_fighter.glb assets-src/models/varco/fighter_idle.glb "${FIGHTER_CLIPS[@]}"
else
  echo "건너뜀: varco_fighter — 원본이 없다 (격투가는 절차적 리그로 나온다)"
fi

# 오우거 5종 — 몬스터 외형. 지금은 varco_ogre1 만 초원에 걸었다 (monsters.ts 의 TIERS[].look).
# 바르코 워크플로우 "오우거" 의 Type1~5. 생김새만 다르고 동작 넷은 같다.
# 받은 파일 순서가 타입마다 같다: 오우거-Animate-오우거-1 = 대기, -2 = 달리기, -3 = 공격, -4 = 사망
# (파일에 클립 이름이 비어 있어 동작 데이터를 재서 가렸다 — characters-and-animation.md)
# **결과물 주소를 아직 못 박았다.** 받아 둔 원본(assets-src/models/varco/ogre<N>_*.glb)이 있을 때만 만든다.
for n in 1 2 3 4 5; do
  O="assets-src/models/varco/ogre${n}"
  if [ -f "${O}_idle.glb" ] && [ -f "${O}_run.glb" ] && [ -f "${O}_attack.glb" ] && [ -f "${O}_death.glb" ]; then
    # 달리기는 마법사와 같은 클립이다 (구워진 방향 -94.6°)
    node scripts/build-varco-character.mjs "public/assets/models/varco_ogre${n}.glb" "${O}_idle.glb" "Idle=${O}_idle.glb" "Run=${O}_run.glb#loop#face" "Attack=${O}_attack.glb" "Death=${O}_death.glb"
  else
    echo "건너뜀: varco_ogre${n} — 원본이 없다"
  fi
done

# ------------------------------------------------------------ 가방·장비 아이콘

# 바르코 커스텀 워크플로우 "인벤토리 UI" 의 출력물 11장. 연한 청백색 선화 한 벌이라
# 창 안에서 서로 겉돌지 않는다. 배경이 검은 것과 흰 것이 섞여 있어(프롬프트마다 다르다)
# build-item-icons.mjs 가 걷어내고 128px 로 굽는다 → public/assets/icons (커밋한다).
#
# glove·belt 는 **아직 어느 칸에 쓸지 안 정했다** — 받아만 두고 고도로는 안 넘긴다
# (sync-godot-assets.mjs 의 ICONS). offhand(방패)는 2026-09-18 에 슬롯 자체를 없애
# 받기는 하되 고도로 안 넘긴다. 테두리 둘(frame_*)은 같은 워크플로우에서 나중에 만들었다.
mkdir -p assets-src/icons

fetch_icon() { # $1=객체 해시  $2=출력 이름
  if [ ! -f "assets-src/icons/$2.png" ]; then
    echo "받는 중: icons/$2.png"
    curl -sL --max-time 120 -o "assets-src/icons/$2.png" "${VARCO}/$1.png"
  fi
}

fetch_icon 5e1236b3e6ad6dc7fec570a9bd187a9f weapon    # 검
fetch_icon 5c25daa856bca458f26f703fe63424f4 offhand   # 방패
fetch_icon 756fe1b855b1e5cff5038c21253b244a helmet    # 투구
fetch_icon 0779fa082cdcbc922c8bf8104e9212ea armor     # 갑옷
fetch_icon 9fc33631108021fa8ec41db82b8ed378 boots     # 장화
fetch_icon 7798ba00c5755e15d7a9fa28c38083ef ring      # 반지
fetch_icon 624e1a1a10e8576c2ce473e0155dd4f0 necklace  # 목걸이
fetch_icon 5fd4ab55b5c3e682f35f8cf81b2a266d bag       # 가방
fetch_icon 0f5c8a9b06c498361643b69fc4b3d97c gold      # 동전
fetch_icon 36ce4590784bd702b644bcd409e50f0b glove     # 장갑 (미사용)
fetch_icon dbc3fc75337294133bfc32ab2628ba5b belt      # 벨트 (미사용)
# 창을 짓는 그림. 전부 9조각으로 늘여 쓴다 (game.gd 의 _frame_box).
# 처음 구운 frame_panel·frame_slot 은 2026-09-18 에 ui_* 한 벌로 갈아치웠다 —
# 판·칸·탭·단추가 한 벌로 맞아야 창이 임시로 안 보인다.
# 2026-09-20 에 **HUD 아이콘 셋을 참고 그림으로 물려** 한 벌로 다시 뽑았다 —
# 어두운 판 + 머리카락처럼 얇은 금테 + 상아빛 포인트. 옛 청록 조각을 갈아치운 것이다
fetch_icon 3d1e49ad807577737bed8fa2449e8a8f ui_panel     # 창 바탕 (모서리 장식)
fetch_icon 7fe4055eec2fdebd37b6dc157d4f30ae ui_subpanel  # 이름표·스탯 상자
fetch_icon dac29087bdffce5bdaa23666f2872afe ui_slot      # 칸
fetch_icon 1344b8afc27c134af2b2f5942b111bbf ui_tab_on    # 고른 탭 (상아빛 — 글자는 어둡게 얹는다)
fetch_icon 757608f70e49e1a099e5f1cb2b67710f ui_tab_off   # 안 고른 탭
fetch_icon 9768fc8560a2ece9c040596698357747 ui_button    # 단추
fetch_icon 70f1e1a287f9e93cc1abb39f5759dccb ui_figure    # 장착 칸 사이 캐릭터
# 스킬창·퀵슬롯 (2026-09-19). 조각 둘은 ui_slot 을 참고 그림으로 넣어 결을 맞췄다.
# 스킬 아이콘은 **꽉 찬 그림**이라 배경을 걷지 않는다 (build-item-icons.mjs 의 FULL)
fetch_icon 67616623f2d7038e61f1a6aa35f63113 ui_skill_slot  # 스킬창 장착 칸 (2026-09-20 에 창 결로 맞췄다)
fetch_icon 09535596db087ab0c6d3b9de0ae6b086 ui_slot_pick   # 고른 칸 테두리 (안쪽을 뚫는다, 2026-09-20)
fetch_icon 6688952f8b0187efe7f96935796fa7a8 skill_rising_kick
fetch_icon 3335dffd51390210007c5b2eb5a8adb7 skill_tiger_roar
fetch_icon 844c2e93d9c7b8f9d6c3717b2334b9ca skill_white_tiger
fetch_icon 3d66ba0be1ec8bec0bc0b2a11fcce4f9 skill_sky_breaker
fetch_icon 627417215a6f50209f7d0a20cbd1c607 skill_thunder_fall
# 메인 HUD. 아트를 **두 번** 갈았다 — 처음 뽑은 두꺼운 금테가 "너무 두껍다" 는
# 지적을 받고(2026-09-20), 받은 그림대로 **머리카락처럼 얇은 금선**과 **테 없는
# 선화 아이콘**으로 다시 뽑았다. 아래 주소가 그 두 번째 것이다.
#
# 막대 채움은 **흰 것 한 장**이고 붉은 체력은 색만 입혀 쓴다.
# 퀵슬롯 칸은 `ui_quick_slot` 으로 따로 둔다 — `ui_skill_slot` 을 덮으면
# 스킬창 장착 칸까지 바뀌어 창 안에서 목록 칸(ui_slot)과 결이 어긋난다.
# 막대 홈·배지·칸은 **안쪽이 어두운 채로** 받는다 (뚫으면 땅이 비친다)
fetch_icon 9824f75b67284f12e744b40c4b54921f ui_bar_frame   # 체력 막대 홈 (얇은 금선)
fetch_icon b58dcdbd6894b815fcfa09d0cb7e7340 ui_bar_fill    # 막대 채움 (색은 코드가 입힌다)
fetch_icon c41890b49bcfb31cf91861287fe65fd5 ui_level_badge # 레벨 배지 (얇은 금색 원)
fetch_icon 66d3b2ea079339e5a22b09546c956903 ui_quick_slot  # 퀵슬롯·자동사냥 칸 (얇은 선)
# 아이콘 셋은 **밝게 칠한 것**이다 — 선화로 뽑았더니 어두운 실루엣이 되어
# 밤 사냥터에서 묻혔다 (2026-09-20 지적). 프롬프트에 "FULLY COLORED and BRIGHT,
# NOT a dark silhouette, NOT black" 을 넣어야 칠해서 준다
# 아이콘 셋은 **받은 스크린샷을 참고 그림으로 물려** 뽑았다 (2026-09-20).
# 상아빛 흰색 + 금색에 얇은 어두운 윤곽 — 받은 화면의 메뉴 아이콘과 같은 결이다
fetch_icon e5157077f125b146e546c1c91b818096 ui_icon_skill  # 오른쪽 위 스킬 (펼친 책 + 룬)
fetch_icon 7542d36d9687956d7335787965b4f16d ui_icon_bag    # 오른쪽 위 가방 (배낭)
fetch_icon 9f519882b9a58b99a928564c0fb70efd ui_icon_auto   # 자동사냥 — 검 두 자루가 X자
fetch_icon 74df64ad7717d61a8ba37c600568f827 ui_auto_spin   # 자동사냥 고리 (굵은 화살표 — 얇은 것은 안 보였다)
fetch_icon 69c32b07ca637a710819a6ba08020abf ui_close       # 모든 창 오른쪽 위 닫기 X
fetch_icon 029c2be72082608b40dfaf00bebe782a ui_portrait    # 옛 초상 테두리 (미사용 — 상태판을 내리면서 빠졌다)

node scripts/build-item-icons.mjs

echo "완료. 총 $(du -sh public/assets | cut -f1)"
