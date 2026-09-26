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
# (호포각·백호격 그림도 2026-09-23 에 스킬째 지웠다. 주소가 필요하면 이 파일의 이력에 있다)

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

# 격투가 ★ 2026-09-26 부터 **팬티 차림 몸**이다 (장비 부위를 입히려고 옷을 벗겼다).
# 원화(docs/art/fighter_concept.png)를 바르코 EditImage 로 벗기고 → 주먹을 쥐게 고치고 →
# Generate3D(T 포즈) → Rig(humanoid-fingers). 손은 편 손이다 (주먹 쥐기·이식은 걷었다, 2026-09-26).
# 동작은 새로 뽑지 않고 **옛 몸의 클립을 옮겨 붙인다** — 옛 몸의 클립 11개를 메시 없이 담은
# public/assets/anim/fighter_clips.glb (커밋) 를 `add-clips --retarget` 으로 새 뼈대에 입힌다.
fetch_varco 615f33dfdc24a231f69d43926be1bcf1 fighter_bare_fingers
node scripts/build-varco-character.mjs public/assets/models/varco_fighter.glb assets-src/models/varco/fighter_bare_fingers.glb

# 마을 NPC 7명 (2026-09-26) — 원화(docs/art/npc/*.jpg, 격투가 원화를 결 참고로) → Generate3D(tPose 1,
# 3만 면) → Rig(humanoid) → Animate(standing_idle_1·2 를 번갈아). 대기 하나뿐이라 오우거처럼
# 대기 파일을 기본 메시로도 쓴다. look 이름은 zones.ts 의 NpcDef.look → godot/game/rig.gd 의 FILES
fetch_npc() { # $1=대기 결과물 해시  $2=look
  fetch_varco "$1" "npc_$2_idle"
  node scripts/build-varco-character.mjs "public/assets/models/npc_$2.glb" "assets-src/models/varco/npc_$2_idle.glb" "Idle=assets-src/models/varco/npc_$2_idle.glb"
}
fetch_npc 873b748a81947311b8ed5eedcfe17c84 merchant        # 상인 보리스
fetch_npc 4ec93a0384f80e5d4b8c70d64d634e4f smith           # 대장장이 군터
fetch_npc b890f4305f0990fa0ade869b9085fc5f trainer         # 전직관 레온
fetch_npc b31b48d65104023c965e641dc248a38f villager_sack   # 아네트
fetch_npc 5748431e4991180b5d4607d688ff296f villager_apron  # 요한
fetch_npc 20c5da3110a518f717284b5a41cc98ee villager_hood   # 릴리
fetch_npc e15cff61633c8920a7e71da26fb0d563 villager_old    # 노인 하르트
node scripts/add-clips.mjs public/assets/models/varco_fighter.glb public/assets/models/varco_fighter.glb public/assets/anim/fighter_clips.glb --retarget
node scripts/add-clips.mjs public/assets/models/varco_fighter.glb public/assets/models/varco_fighter.glb public/assets/anim/fighter_moves.glb --retarget
# 대기는 새 몸에서 블렌더로 지었다 (scripts/blender/fighter_idle.py → 커밋된 fighter_idle.glb) — 같은 뼈대라 그대로 붙인다
node scripts/add-clips.mjs public/assets/models/varco_fighter.glb public/assets/models/varco_fighter.glb public/assets/anim/fighter_idle.glb

# 장비 — 등급마다 갑옷·투구·신발 (2026-09-26). 바르코가 몸 그림 + 그 등급 아이콘 셋으로 장비 입은
# 격투가를 뽑아 humanoid-fingers 로 리깅한 것 → build-gear-parts.mjs 가 부위를 떼어 우리 뼈대로 옮긴다.
# 외형은 코드로 짓지 않는다 (CLAUDE.md) → characters-and-animation.md "장비 스킨"
GEAR=(6a7022efbd141b240c84b8979e6dc824 73ee568dc290695eb008cef273f26a7e 7467685d6a4533d172e45fe69d0ac09c
  db450181f7af31740a47d8a1608b4538 8de3c3db9a4812b2f05b1129d741bc5c d4667f3f1849f78c44bb9fdce74ef0aa
  7fd5ba94003f61c25677d1b1c7bb093a)
for g in 1 2 3 4 5 6 7; do
  fetch_varco "${GEAR[$((g-1))]}" "gear_g${g}_rigged"
  node scripts/build-gear-parts.mjs "public/assets/models/gear_g${g}.glb" public/assets/models/varco_fighter.glb "assets-src/models/varco/gear_g${g}_rigged.glb"
done

# (옛 몸) 옷 입은 격투가 — 아래는 fighter_clips.glb 를 다시 뽑아야 할 때만 쓴다. 원본 넷이 있으면
# 옛 몸을 짓고, 그 클립을 fighter_clips.glb 로 옮긴다 (메시는 버린다).
# 격투가 — 궁수와 같은 방식. 받은 파일: 격투가-Animate-격투가-1 = 대기, -1-2 = 달리기, -1-3 = 공격, -1-4 = 사망
# (클립 이름이 비어 있어 길이·동작 폭을 재서 가렸다 — characters-and-animation.md)
# 공격은 #face 를 안 붙인다: 골반이 -70° 쯤 틀어진 건 격투 자세이고, 차는 발은 정면(7°)으로 나간다.
FIGHTER_CLIPS=()
FIGHTER_CLIPS+=("Idle=assets-src/models/varco/fighter_idle.glb")
FIGHTER_CLIPS+=("Run=assets-src/models/varco/fighter_run.glb#loop#face")
FIGHTER_CLIPS+=("Attack=assets-src/models/varco/fighter_attack.glb")
FIGHTER_CLIPS+=("Death=assets-src/models/varco/fighter_death.glb")
if [ -f assets-src/models/varco/fighter_idle.glb ] && [ -f assets-src/models/varco/fighter_run.glb ] && [ -f assets-src/models/varco/fighter_attack.glb ] && [ -f assets-src/models/varco/fighter_death.glb ]; then
  node scripts/build-varco-character.mjs assets-src/models/varco/fighter_clothed.glb assets-src/models/varco/fighter_idle.glb "${FIGHTER_CLIPS[@]}"
  node scripts/add-clips.mjs public/assets/anim/fighter_clips.glb public/assets/anim/fighter_moves.glb assets-src/models/varco/fighter_clothed.glb
else
  echo "건너뜀: 옛 격투가 클립 — 원본이 없다 (커밋된 fighter_clips.glb 를 그대로 쓴다)"
fi

# 오우거 5종 — 몬스터 외형. 사냥터 20곳과 보스가 다섯을 차례로 돌려 쓴다 (monsters.ts 의 TIERS[].look · BOSS_LOOKS).
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
# 등급별 무기 = 건틀릿 (2026-09-23). 사용자가 바르코에서 만든 것 — 등급마다 두 장
# 중 첫 장이다. 일반은 그 워크플로우의 참고 그림(흰 붕대 주먹)이다.
# 이름이 `<슬롯>_g<등급>` 이면 game.gd 의 `_item_icon` 이 슬롯 그림 대신 쓴다
fetch_icon 20b5d75fc0f3cb52c3607c41ff4bc56b weapon_g1 # 일반 — 붕대 감은 주먹
fetch_icon 8b16863b330e87c312eee0d1d2079392 weapon_g2 # 고급 — 가죽 덮개 · 리벳
fetch_icon b5a8a101294b626d7c3f49ca68da5f9c weapon_g3 # 희귀 — 은빛 판금
fetch_icon 7dd9fcea4f4443c8d79a1bb0a7a94c7a weapon_g4 # 영웅 — 보랏빛 보석
fetch_icon 432b36454810c91498d2a86dcf5b3d92 weapon_g5 # 전설 — 용린
fetch_icon 5cdd1dcc38b9efcdbd1ca5d3346244fb weapon_g6 # 초월 — 붉게 갈라진 검은 쇠
fetch_icon 9cb037d770778e71703e7a9b4fe2279c weapon_g7 # 태초 — 빛나는 흰 주먹과 고리
# 나머지 다섯 부위 × 7등급 (2026-09-26). 등급마다 같은 등급의 건틀릿 원본을 참고 그림으로
# 물려 바르코로 만들었다 — 재질·색이 등급끼리 맞는다 (docs/features/inventory-equipment.md)
fetch_icon 942aba995cd9802e722c5d785991e5d8 armor_g1
fetch_icon b208db2a7c3d8f92fc42fd47a9a12b67 armor_g2
fetch_icon b5e4848ea3cd3c526b2d40888a7a14fb armor_g3
fetch_icon 8451956e76f591ac2d1c6c1aae9a840e armor_g4
fetch_icon e2581c491c197332188043c5bcd18b99 armor_g5
fetch_icon 24252cd866beb02ea44d719a9772d418 armor_g6
fetch_icon 3e6188dbcdd79f2e9e957771e129bdd2 armor_g7
fetch_icon 0a0f2cf6c4b4254cd6702a608300fc3d helmet_g1
fetch_icon 85668facde84902d61ca22d484eb89db helmet_g2
fetch_icon cbf3ac7f2d1c42cc8ecb303f58a1c4f8 helmet_g3
fetch_icon a4cf97bed4485512cddfcf9c5dc7bf97 helmet_g4
fetch_icon 9119f0b1ea48175dd5327c5bc136824f helmet_g5
fetch_icon 59d2ffd558e14f12942474b63aaab68c helmet_g6
fetch_icon 76dee2926d678ed1a5f8d32ef028fbb1 helmet_g7
fetch_icon 560e695cd49d1525cbba5393a47ece63 boots_g1
fetch_icon 80f6ce01a1cd8cbd7ce8650c8380ef68 boots_g2
fetch_icon 31d3d8231155153c732d76a7e194e8f1 boots_g3
fetch_icon 3ebf0f3cd2f96c517c69a32e1956721e boots_g4
fetch_icon 19a31c55df2d1d795e407e083ab4843c boots_g5
fetch_icon ca6f31c5600e855f1b3dd994806f1782 boots_g6
fetch_icon 10759c58bd5dab1af1e3fe616e63ddea boots_g7
fetch_icon 0700934bd673c7dc0e22040cf602de01 necklace_g1
fetch_icon c4b13e70459a75ab49f65dee6d5caa2d necklace_g2
fetch_icon 57f83be49ed9fcca9ecb4d4f54721acc necklace_g3
fetch_icon bbd515233f562a91e9769ab8ef1f00a8 necklace_g4
fetch_icon 59b61bc8b852213922341ca8f007049e necklace_g5
fetch_icon 4392e6dbc933f42bc0d50ef5c6240a11 necklace_g6
fetch_icon 2bda84cb934de8afbcf1138b51e812d3 necklace_g7
fetch_icon a29f34ccc91f899c5897e740356b0286 ring_g1
fetch_icon 240a7e95fdfd96cf3148da9428846314 ring_g2
fetch_icon 200bf228b2a324595c4ce7c7fadda5f9 ring_g3
fetch_icon 8078f8d06255a85568061d23e5cb2891 ring_g4
fetch_icon e9ebc1438165a04e124f1ce6d14c0690 ring_g5
fetch_icon 0b6d1c4c065113270b08cca56c51df74 ring_g6
fetch_icon d568940b9d3d9f61e37c60791af11ad9 ring_g7
fetch_icon 5c25daa856bca458f26f703fe63424f4 offhand   # 방패
fetch_icon 756fe1b855b1e5cff5038c21253b244a helmet    # 투구
fetch_icon 0779fa082cdcbc922c8bf8104e9212ea armor     # 갑옷
fetch_icon 9fc33631108021fa8ec41db82b8ed378 boots     # 장화
fetch_icon 7798ba00c5755e15d7a9fa28c38083ef ring      # 반지
# 재료 — 크리스탈 (2026-09-23). 건틀릿 워크플로우에 일반 건틀릿을 참고로 물려 뽑은 두 장 중 첫 장
fetch_icon 6cd39aca0eb28083b14b49c8fab67303 crystal   # 크리스탈
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
# 인벤토리 결 (2026-09-23). 사용자가 준 인벤토리 그림을 **참고 그림으로 물려** 뽑았다 —
# 어두운 판 + 녹슨 청동 테 + 작은 모서리 쇠장식. 장비·상세·인벤토리 세 창이 쓴다
fetch_icon c9df923ad843e039f6d36e16128b1a0e inv_panel    # 창 바탕
fetch_icon 35efeeeb2f3c5e2057c402bcf637a004 inv_slot     # 칸 (움푹한 어두운 칸)
fetch_icon aab8913d12bcb3f6e61792f57591c7c4 inv_tab_on   # 고른 세로 탭 (청동빛 + 금선)
fetch_icon 321697844636399efc7e32efaa490a4f inv_tab_off  # 안 고른 세로 탭
fetch_icon 5e0955210d0ec5ff49a18b04fe9c8845 inv_button   # 정렬·장비·장착 단추
fetch_icon f17150f251000766c28f5692f905204a inv_slot_pick # 고른 칸 금테 (안쪽을 뚫는다)
# 스킬창·퀵슬롯 (2026-09-19). 조각 둘은 ui_slot 을 참고 그림으로 넣어 결을 맞췄다.
# 스킬 아이콘은 **꽉 찬 그림**이라 배경을 걷지 않는다 (build-item-icons.mjs 의 FULL)
fetch_icon 67616623f2d7038e61f1a6aa35f63113 ui_skill_slot  # 스킬창 장착 칸 (2026-09-20 에 창 결로 맞췄다)
fetch_icon 09535596db087ab0c6d3b9de0ae6b086 ui_slot_pick   # 고른 칸 테두리 (안쪽을 뚫는다, 2026-09-20)
fetch_icon 6688952f8b0187efe7f96935796fa7a8 skill_rising_kick
fetch_icon 3d66ba0be1ec8bec0bc0b2a11fcce4f9 skill_sky_breaker
fetch_icon 627417215a6f50209f7d0a20cbd1c607 skill_thunder_fall
# 빙주각 (2026-09-23) — 낙뢰·천붕각 아이콘을 참고 그림으로 물려 결을 맞췄다 (두 장 중 첫 장)
fetch_icon eb9cc29622b3030bd7d35e327ef00e9d skill_frost_pillar
# 메인 HUD. 아트를 **두 번** 갈았다 — 처음 뽑은 두꺼운 금테가 "너무 두껍다" 는
# 지적을 받고(2026-09-20), 받은 그림대로 **머리카락처럼 얇은 금선**과 **테 없는
# 선화 아이콘**으로 다시 뽑았다. 아래 주소가 그 두 번째 것이다.
#
# 막대 채움은 **흰 것 한 장**이고 붉은 체력은 색만 입혀 쓴다.
# 퀵슬롯 칸은 `ui_quick_slot` 으로 따로 둔다 — `ui_skill_slot` 을 덮으면
# 스킬창 장착 칸까지 바뀌어 창 안에서 목록 칸(ui_slot)과 결이 어긋난다.
# 막대 홈·배지·칸은 **안쪽이 어두운 채로** 받는다 (뚫으면 땅이 비친다)
fetch_icon 9824f75b67284f12e744b40c4b54921f ui_bar_frame   # 체력 막대 홈 (얇은 금선)
# 막대 채움(ui_bar_fill)은 **받지 않는다** — `build-item-icons.mjs` 가 직사각
# 그라데이션으로 그려 낸다. 비스듬한 홈 모양으로 자르는 것은 고도가 마스크로 한다
# 배지는 **푸른기가 돌아** 한 번 다시 뽑았다 (2026-09-20 지적: "레벨 UI 도 다른
# UI 들이랑 비슷한 색상으로"). 안쪽이 #2d363d(슬레이트) 였던 것을 #202321 로 —
# 프롬프트에 칸과 같은 값(#191a19)과 "NO blue, NO slate" 를 박아야 나온다
fetch_icon b2d622d7beb6fab02b26d0725c6231a1 ui_level_badge # 레벨 배지 (얇은 금색 원 두 겹)
fetch_icon 66d3b2ea079339e5a22b09546c956903 ui_quick_slot  # 퀵슬롯·자동사냥 칸 (얇은 선)
# 아이콘 셋은 **밝게 칠한 것**이다 — 선화로 뽑았더니 어두운 실루엣이 되어
# 밤 사냥터에서 묻혔다 (2026-09-20 지적). 프롬프트에 "FULLY COLORED and BRIGHT,
# NOT a dark silhouette, NOT black" 을 넣어야 칠해서 준다
# 아이콘 셋은 **받은 스크린샷을 참고 그림으로 물려** 뽑았다 (2026-09-20).
# 상아빛 흰색 + 금색에 얇은 어두운 윤곽 — 받은 화면의 메뉴 아이콘과 같은 결이다
# 차원문 창 줄 아이콘 (2026-09-21). 파란 타일을 쓰다가 금빛 창과 결이 달라 다시 뽑았다 —
# 타일(판) 없이 문장만 있는 그림이다 (docs/features/ui-art-style.md 의 "아이콘류" 틀)
fetch_icon 09d32f50e266215c7ff66542d6d7c016 ui_gate_here   # 지금 서 있는 곳 — 소용돌이
fetch_icon 2209356ad70f42d8872938bc39ffedd4 ui_gate_go     # 갈 수 있는 곳 — 별

fetch_icon e5157077f125b146e546c1c91b818096 ui_icon_skill  # 오른쪽 위 스킬 (펼친 책 + 룬)
fetch_icon 7542d36d9687956d7335787965b4f16d ui_icon_bag    # 오른쪽 위 가방 (배낭)
fetch_icon 106e9eda607b28a595dcf08578270163 ui_icon_dungeon # 가방 옆 던전 — 뿔 달린 보스 머리 (두 장 중 첫째). 아트풍 그대로 둔다
# 던전 종류 카드 썸네일만 실사풍 (2026-09-26, docs/features/dungeons.md). 각 두 장 중 고른 것
fetch_icon 5ba8037d1557db3aaa50724f3773a062 dungeon_raid     # 토벌 — 뿔 달린 오거 보스 머리 (둘째)
fetch_icon 83ade51b31eaabf39062e899b8b4b39d dungeon_trial    # 시련의 탑 — 뾰족 지붕 돌탑 · 횃불 (둘째)
fetch_icon 5eb4149d3844a5afb43f514f86b719ab dungeon_treasure # 보물 창고 — 금테 상자 · 자물쇠 · 금화 (첫째)
fetch_icon 9f519882b9a58b99a928564c0fb70efd ui_icon_auto   # 자동사냥 — 검 두 자루가 X자
# 퀵슬롯 왼쪽 물약 칸 (2026-09-26) — 둥근 유리병 · 코르크 · 붉은 물약. 두 장 중 둘째(정면)
fetch_icon 81fc643bd0233984e748b4bb3416fcc8 ui_icon_potion
fetch_icon 74df64ad7717d61a8ba37c600568f827 ui_auto_spin   # 자동사냥 고리 (굵은 화살표 — 얇은 것은 안 보였다)
fetch_icon 69c32b07ca637a710819a6ba08020abf ui_close       # 모든 창 오른쪽 위 닫기 X
fetch_icon 029c2be72082608b40dfaf00bebe782a ui_portrait    # 옛 초상 테두리 (미사용 — 상태판을 내리면서 빠졌다)

node scripts/build-item-icons.mjs

echo "완료. 총 $(du -sh public/assets | cut -f1)"
