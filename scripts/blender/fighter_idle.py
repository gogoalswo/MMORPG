"""격투가 대기(Idle) 동작을 블렌더에서 키프레임으로 짓는다.

    npm run blender -- --python scripts/blender/fighter_idle.py
    node scripts/add-clips.mjs public/assets/models/varco_fighter.glb public/assets/models/varco_fighter.glb public/assets/anim/fighter_idle.glb

2026-09-26 요청: "평상시에는 손을 펴고 T 자 모양으로 만들고, Idle 상태를 블렌더로 애니메이션 새로
만들어 · 주먹은 틀려 먹은 것 같다". 주먹을 이식하던 것을 걷고 편 손 T 자세 모델로 돌아가면서,
옛 몸(옷 입은 격투가)에서 옮겨 온 바르코 대기 클립 대신 **새 몸에 맞춰 대기를 새로 짓는다.**

- 발은 어깨너비, 무릎을 살짝 굽히고, 팔은 **편 손으로 편하게 내린다** (팔꿈치는 뒤로 조금).
- 3초에 한 번 숨을 쉰다 — 들숨에 가슴이 들리고 몸이 조금 내려앉았다가 돌아온다.
- **첫 키와 끝 키가 같다.** 게임은 대기가 끝나면 처음부터 다시 틀어서(`Rig.play`) 이어 붙인다.
- 자세 도구(2본 IK · 발 붙이기 · 키 박기)는 `fighter_moves.py` 의 것을 그대로 빌린다 —
  좌표 약속도 같다: `+X` 캐릭터 왼쪽 · `-Y` 앞 · `+Z` 위, 키 약 1.0.
- 손 자리는 숫자로 박지 않고 **어깨 자리와 팔 길이에서** 잡는다 — 모델을 바꿔도 팔이 늘거나
  모자라 꺾이지 않게.
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fighter_moves as fm  # noqa: E402

BASE = fm.BASE
OUT = "public/assets/anim/fighter_idle.glb"
# 한 번 숨 쉬는 길이(초)
BREATH = 3.0


def stance(poser, breath):
    """대기 자세 — `breath` 0 이 날숨(기본), 1 이 들숨 끝"""
    spec = {
        "hips": (0.0, 0.0, -0.012 - 0.008 * breath),
        "hipsR": (0, 0, 0),
        # 들숨에 가슴이 조금 들리고(숙임이 준다) 고개도 따라 든다
        "spine": (4 - 2.5 * breath, 0, 0),
        "head": (-3 - 1.5 * breath, 0, 0),
        "lfPole": (0.15, -1, 0), "lfYaw": 6,
        "rfPole": (-0.15, -1, 0), "rfYaw": -6,
    }
    # 발은 **기본 자세의 발목 자리**에 둔다 — 옛 몸의 발목 높이(0.078)를 박았더니 발끝이 땅 밑
    # 5cm 로 들어갔다. 기본(T) 자세는 땅에 선 자세라 그 발목 높이가 곧 땅이다
    for bones, key in ((fm.LEG_L, "lf"), (fm.LEG_R, "rf")):
        ankle = poser.rest[bones[2]].translation
        spec[key] = (ankle.x, ankle.y - 0.01, ankle.z)
    for side, sign, bones, key in (("Left", 1, fm.ARM_L, "lh"), ("Right", -1, fm.ARM_R, "rh")):
        shoulder = poser.rest[bones[0]].translation
        reach = poser.length(bones[0], bones[1]) + poser.length(bones[1], bones[2])
        # 팔을 거의 곧게 내리되 몸에서 조금 떼고, 손목이 허벅지 옆 조금 앞에 온다.
        # 들숨에 팔이 몸에서 조금 더 벌어진다
        # 팔을 거의 곧게 편다 — 팔 길이의 93% 로 두고 팔꿈치를 뒤로 뺐더니 "팔이 너무 뒤로 꺾였다"
        # (2026-09-26). 98.5% 로 늘리고 손목을 조금 앞에 두고, 팔꿈치는 뒤가 아니라 바깥을 본다
        hand = shoulder + Vector((sign * (0.06 + 0.008 * breath), -0.045, -reach * 0.985))
        spec[key] = tuple(hand)
        spec[key + "Pole"] = (sign * 1.0, 0.25, 0.0)
    return spec


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=BASE, bone_heuristic="BLENDER")
    scene = bpy.context.scene
    scene.render.fps = fm.FPS
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    poser = fm.Poser(arm)
    if arm.animation_data is None:
        arm.animation_data_create()
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)

    exhale = stance(poser, 0.0)
    inhale = stance(poser, 1.0)
    keys = [(0.0, exhale, "BEZIER"), (BREATH * 0.45, inhale, "BEZIER"), (BREATH, exhale, "BEZIER")]
    action = bpy.data.actions.new("Idle")
    action.use_fake_user = True
    arm.animation_data.action = action
    last = {}
    for t, spec, interp in keys:
        poser.apply(spec)
        poser.key(action, round(t * fm.FPS), interp, last)
    fm.report(poser, "Idle", keys)

    arm.animation_data.action = None
    for o in list(bpy.data.objects):
        if o != arm:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_step=1,
        export_optimize_animation_size=False,
        export_anim_single_armature=True,
        export_def_bones=False,
        export_skins=False,
        export_materials="NONE",
    )
    print(f"내보냄: {OUT}")


main()
