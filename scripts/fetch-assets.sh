#!/usr/bin/env bash
# CC0 에셋을 다시 받아 public/assets 에 배치한다.
# 원본(zip/hdr)은 저장소에 커밋하지 않으므로, 새로 클론했을 때 이 스크립트를 돌린다.
# 출처와 라이선스는 docs/ASSETS.md 참고 — 전부 CC0 1.0.
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

fetch_beast animals_pack/Wolf   wolf  Idle Walk Gallop Attack Death
fetch_beast animals_pack/Husky  husky Idle Walk Gallop Attack Death
fetch_beast animals_pack/Bull   bull  Idle Walk Gallop Attack_Headbutt Death
fetch_beast animals_pack/Stag   stag  Idle Walk Gallop Attack_Headbutt Death
fetch_beast easy_enemies_pack/Spider spider Spider_Idle Spider_Walk Spider_Attack Spider_Death

fetch_beast dinosaurs_pack/Trex         trex         TRex_Idle TRex_Walk TRex_Run TRex_Attack TRex_Death
fetch_beast dinosaurs_pack/Velociraptor velociraptor Velociraptor_Idle Velociraptor_Walk Velociraptor_Run Velociraptor_Attack Velociraptor_Death
fetch_beast dinosaurs_pack/Triceratops  triceratops  Triceratops_Idle Triceratops_Walk Triceratops_Run Triceratops_Attack Triceratops_Death
fetch_beast dinosaurs_pack/Stegosaurus  stegosaurus  Stegosaurus_Idle Stegosaurus_Walk Stegosaurus_Run Stegosaurus_Attack Stegosaurus_Death

echo "완료. 총 $(du -sh public/assets | cut -f1)"
