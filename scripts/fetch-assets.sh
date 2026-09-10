#!/usr/bin/env bash
# 에셋을 다시 받아 public/assets 에 배치한다.
# 원본(zip/hdr/glb)은 저장소에 커밋하지 않으므로, 새로 클론했을 때 이 스크립트를 돌린다.
# 출처와 라이선스는 docs/ASSETS.md 참고 — 외부 에셋은 전부 CC0 1.0 이고,
# 맨 끝 VARCO 캐릭터만 우리가 직접 생성한 것이다.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p assets-src/textures public/assets/textures public/assets/hdri public/assets/basis

fetch_material() { # $1=ambientCG 자산명  $2=출력 이름
  local id="$1" out="$2"
  if [ ! -f "assets-src/${id}_1K-JPG.zip" ]; then
    echo "받는 중: $id"
    curl -sL --max-time 300 -o "assets-src/${id}_1K-JPG.zip" \
      "https://ambientcg.com/get?file=${id}_1K-JPG.zip"
  fi
  rm -rf "assets-src/${id}_1K-JPG"
  unzip -q -o "assets-src/${id}_1K-JPG.zip" -d "assets-src/${id}_1K-JPG"
  # Color/NormalGL/Roughness 만 쓴다 (이유는 docs/ASSETS.md).
  # 원본 JPEG 은 public/ 밖에 둔다 — 배포되는 건 압축한 .ktx2 뿐이다.
  cp "assets-src/${id}_1K-JPG/${id}_1K-JPG_Color.jpg"     "assets-src/textures/${out}_color.jpg"
  cp "assets-src/${id}_1K-JPG/${id}_1K-JPG_NormalGL.jpg"  "assets-src/textures/${out}_normal.jpg"
  cp "assets-src/${id}_1K-JPG/${id}_1K-JPG_Roughness.jpg" "assets-src/textures/${out}_rough.jpg"
  echo "  -> assets-src/textures/${out}_*.jpg"
}

fetch_material Grass005  grass
fetch_material Ground037 dirt
fetch_material Rock063   rock

if [ ! -f assets-src/sky_2k.hdr ]; then
  echo "받는 중: HDRI"
  curl -sL --max-time 300 -o assets-src/sky_2k.hdr \
    "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
fi
cp assets-src/sky_2k.hdr public/assets/hdri/sky_2k.hdr
echo "  -> public/assets/hdri/sky_2k.hdr"

# ---------------------------------------------------------------- 캐릭터 모델

# KayKit 캐릭터 팩(CC0). 다섯이 같은 뼈대를 쓰므로 애니메이션은 knight 한 곳에만
# 남기고 나머지는 통째로 잘라낸다 — 원본 그대로면 다섯이 18MB, 잘라내면 2MB 다.
KAYKIT="https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/main/addons/kaykit_character_pack_adventures/Characters/gltf"

# 우리가 실제로 쓰는 클립만 남긴다 (원본은 76개)
KEEP_CLIPS="Idle Walking_A Running_A 1H_Melee_Attack_Slice_Diagonal 1H_Ranged_Shoot Spellcast_Shoot Death_A Hit_A Interact"

mkdir -p assets-src/models public/assets/models

fetch_character() { # $1=원본 이름  $2=출력 이름  $3=남길 클립("--none" 이면 전부 제거)
  local src="$1" out="$2"
  if [ ! -f "assets-src/models/${src}.glb" ]; then
    echo "받는 중: ${src}.glb"
    curl -sL --max-time 300 -o "assets-src/models/${src}.glb" "${KAYKIT}/${src}.glb"
  fi
  shift 2
  node scripts/trim-gltf.mjs "assets-src/models/${src}.glb" "public/assets/models/${out}.glb" "$@"
}

fetch_character Knight       knight       $KEEP_CLIPS
fetch_character Mage         mage         --none
fetch_character Rogue        rogue        --none
fetch_character Rogue_Hooded rogue_hooded --none
fetch_character Barbarian    barbarian    --none

# ---------------------------------------------------------------- 몬스터 모델

# Quaternius 짐승들(CC0). 종류마다 뼈대와 클립 이름이 달라서 파일마다 따로 자른다.
# 대기·걷기·달리기·공격·사망 다섯이면 충분하다 (원본은 12~13개).
QUAT="https://raw.githubusercontent.com/trebeljahr/quaternius-showcase/main/public/glb"

fetch_beast() { # $1=팩/파일  $2=출력 이름  $3...=남길 클립
  local path="$1" out="$2" src
  src=$(basename "$path")
  if [ ! -f "assets-src/models/${src}.glb" ]; then
    echo "받는 중: ${src}.glb"
    curl -sL --max-time 300 -o "assets-src/models/${src}.glb" "${QUAT}/${path}.glb"
  fi
  shift 2
  node scripts/trim-gltf.mjs "assets-src/models/${src}.glb" "public/assets/models/${out}.glb" "$@"
}

# 사냥터 20곳에 한 종씩. 같은 짐승이 두 번 나오면 사냥터를 옮긴 느낌이 안 난다.
fetch_beast animals_pack/Fox         fox         Idle Walk Gallop Attack Death
fetch_beast animals_pack/ShibaInu    shibainu    Idle Walk Gallop Attack Death
fetch_beast animals_pack/Wolf        wolf        Idle Walk Gallop Attack Death
fetch_beast animals_pack/Husky       husky       Idle Walk Gallop Attack Death
fetch_beast animals_pack/Bull        bull        Idle Walk Gallop Attack_Headbutt Death
fetch_beast animals_pack/Stag        stag        Idle Walk Gallop Attack_Headbutt Death
fetch_beast animals_pack/Deer        deer        Idle Walk Gallop Attack_Headbutt Death
fetch_beast animals_pack/Horse       horse       Idle Walk Gallop Attack_Kick Death
fetch_beast animals_pack/Horse_White horse_white Idle Walk Gallop Attack_Kick Death

fetch_beast easy_enemies_pack/Spider spider Spider_Idle Spider_Walk Spider_Attack Spider_Death
fetch_beast easy_enemies_pack/Rat    rat    Rat_Idle Rat_Walk Rat_Run Rat_Attack Rat_Death
fetch_beast easy_enemies_pack/Snake  snake  Snake_Idle Snake_Walk Snake_Attack
fetch_beast easy_enemies_pack/Frog   frog   Frog_Idle Frog_Jump Frog_Attack Frog_Death
fetch_beast easy_enemies_pack/Wasp   wasp   Wasp_Flying Wasp_Attack Wasp_Death

fetch_beast dinosaurs_pack/Trex         trex         TRex_Idle TRex_Walk TRex_Run TRex_Attack TRex_Death
fetch_beast dinosaurs_pack/Velociraptor velociraptor Velociraptor_Idle Velociraptor_Walk Velociraptor_Run Velociraptor_Attack Velociraptor_Death
fetch_beast dinosaurs_pack/Triceratops  triceratops  Triceratops_Idle Triceratops_Walk Triceratops_Run Triceratops_Attack Triceratops_Death
fetch_beast dinosaurs_pack/Stegosaurus  stegosaurus  Stegosaurus_Idle Stegosaurus_Walk Stegosaurus_Run Stegosaurus_Attack Stegosaurus_Death
# 사망 클립 이름이 팩에서 잘못 붙어 있다 (Stegosaurus_Death). 원본대로 받는다.
fetch_beast dinosaurs_pack/Apatosaurus     apatosaurus     Apatosaurus_Idle Apatosaurus_Walk Apatosaurus_Run Apatosaurus_Attack Stegosaurus_Death
fetch_beast dinosaurs_pack/Parasaurolophus parasaurolophus Parasaurolophus_Idle Parasaurolophus_Walk Parasaurolophus_Run Parasaurolophus_Attack Parasaurolophus_Death

# 화살통 — 캐릭터 모델 안에 없어서 따로 받는다. .gltf 는 옆의 .bin 과 .png 를
# 상대 경로로 참조하므로 셋을 같은 폴더에 둔다.
mkdir -p public/assets/models/accessories
for f in quiver.gltf quiver.bin rogue_texture.png; do
  if [ ! -f "public/assets/models/accessories/$f" ]; then
    echo "받는 중: $f"
    curl -sL --max-time 120 -o "public/assets/models/accessories/$f"       "https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/main/addons/kaykit_character_pack_adventures/Assets/gltf/$f"
  fi
done

# ---------------------------------------------------------------- VARCO 캐릭터

# 바르코(3d.varco.ai) 커스텀 워크플로우 "기사" 의 결과물.
# 리깅된 메시 하나 + 동작 여섯이 **파일 일곱 개**로 나온다. 각 파일에 메시와
# 2048² 텍스처가 통째로 다시 들어 있어서 그대로 받으면 97MB 다 — 애니메이션만
# 뽑아 한 파일로 합치고 텍스처를 1024² JPEG 으로 줄여 3MB 로 만든다.
#
# 이 주소들은 그 워크플로우를 한 번 돌린 **결과물**이다. 다시 돌리면 다른
# 캐릭터가 나오므로(생성 모델이라 같은 프롬프트로도 같은 결과가 안 나온다)
# 프롬프트가 아니라 결과물 주소를 박아 둔다. 주소가 죽으면 워크플로우를
# 다시 돌리고 여기 해시를 갈아 끼운다.
VARCO="https://3d.varco.ai/api/objects"

fetch_varco() { # $1=객체 해시  $2=출력 이름
  if [ ! -f "assets-src/models/varco/$2.glb" ]; then
    echo "받는 중: varco/$2.glb"
    curl -sL --max-time 300 -o "assets-src/models/varco/$2.glb" "${VARCO}/$1.glb"
  fi
}

mkdir -p assets-src/models/varco
fetch_varco 9a40444d68ddcce196fc6fa1ec711441 knight_rigged
fetch_varco 2a6f6d32f109d27ce2cf512079521170 anim_idle
fetch_varco 14e6288b273526a4bcb75ca2fb9a8af6 anim_run
fetch_varco a93c151d72acf6ef215eee6b69e347f8 anim_sword_slash
fetch_varco cf5ba760a2b2a8cfad130107f63a37b1 anim_two_hand_attack
fetch_varco b6a60400c72d6338f2fbe0391251bef0 anim_staff_spin
fetch_varco 81b1f814d822bf04983d4cdbd61f60f3 anim_death

# 클립 이름 = 파일. **역슬래시로 줄을 잇지 않는다** — 이 파일은 CRLF 라서
# 줄 끝 역슬래시 다음에 CR 이 오면 bash 가 줄바꿈이 아니라 CR 이스케이프로 읽고 거기서 끊는다.
VARCO_CLIPS=()
# 대기 노드는 뒤에 워크플로우에서 sprint 로 바뀌었다. 주소가 고정이라 상관없다
VARCO_CLIPS+=("Idle=assets-src/models/varco/anim_idle.glb")
# #loop = 반복 재생이라 한 주기로 잘라 시작·끝을 맞춘다
# #face = 클립에 구워진 몸 방향(-83.2°)을 되돌린다 — 둘 다 build 스크립트의 closeLoop
VARCO_CLIPS+=("Run=assets-src/models/varco/anim_run.glb#loop#face")
VARCO_CLIPS+=("Attack=assets-src/models/varco/anim_sword_slash.glb")
VARCO_CLIPS+=("Attack_Heavy=assets-src/models/varco/anim_two_hand_attack.glb")
VARCO_CLIPS+=("Attack_Spin=assets-src/models/varco/anim_staff_spin.glb")
# 사망 = Animate left_side_fall. 한 번 재생이라 #loop 없음. #face 는 루프에만 걸리므로
# 시작 자세에 구워진 몸 방향(-23°)은 그대로 남는다
VARCO_CLIPS+=("Death=assets-src/models/varco/anim_death.glb")

node scripts/build-varco-character.mjs public/assets/models/varco_knight.glb assets-src/models/varco/knight_rigged.glb "${VARCO_CLIPS[@]}"

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

echo "완료. 총 $(du -sh public/assets | cut -f1)"
