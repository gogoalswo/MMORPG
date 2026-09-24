"""격투가 평타·스킬 동작을 블렌더에서 키프레임으로 짓는다.

    npm run blender -- --python scripts/blender/fighter_moves.py
    node scripts/add-clips.mjs public/assets/models/varco_fighter.glb public/assets/models/varco_fighter.glb public/assets/anim/fighter_moves.glb

바르코가 준 클립은 대기·달리기·발차기·사망 넷뿐이라, 스킬을 써도 전부 같은
발차기가 나갔다. 여기서 **평타 둘(잽·스트레이트)과 스킬 넷**을 새로 짓는다.

**자세는 뼈 각도가 아니라 손발이 갈 자리로 적는다.** 이 뼈대는 뼈마다 축이 틀어져
있어서(격투가 23본, 바르코 리깅) 각도를 직접 넣으면 부호부터 헷갈린다. 그래서
몸통(골반·척추·머리)만 각도로 주고, 팔다리는 손목·발목이 갈 자리와 팔꿈치·무릎이
향할 쪽을 주면 2본 IK 로 푼다. 좌표는 모두 아마추어 공간(블렌더)이다:

    +X = 캐릭터의 왼쪽 · -Y = 앞 · +Z = 위 · 키는 약 1.0 (게임에서 1.8 배)

각도도 같은 축이다 (도 단위). 골반 Z 가 음수면 오른쪽으로 돈다(왼 어깨가 앞으로),
척추 X 가 양수면 앞으로 숙인다.

**부딪히는 순간을 0.1초 안에 둔다.** 이펙트와 판정이 시전하는 그 순간(t=0)에
나가므로(`game.gd` 의 `_show_skill`), 준비 동작을 길게 두면 번개가 먼저 떨어지고
주먹은 나중에 나간다. 준비 자세는 고도가 섞어 넣는 짧은 시간(`MOVE_BLEND`)에 들어간다.

결과물은 **뼈대와 클립만** 든 GLB 다 (메시·텍스처 없음). `add-clips.mjs` 가 뼈
이름으로 이어 `varco_fighter.glb` 에 붙인다 — `build-varco-character.mjs` 와 같은 방식.
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

BASE = "public/assets/models/varco_fighter.glb"
OUT = "public/assets/anim/fighter_moves.glb"
FPS = 30

LEG_L = ("LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase")
LEG_R = ("RightUpLeg", "RightLeg", "RightFoot", "RightToeBase")
ARM_L = ("LeftArm", "LeftForeArm", "LeftHand")
ARM_R = ("RightArm", "RightForeArm", "RightHand")
SPINE = ("Spine", "Spine1", "Spine2")
# 기본(T) 자세에서 팔꿈치·무릎이 굽는 쪽 — 팔은 앞, 다리는 뒤
ARM_FLEX = (0.0, -1.0, 0.0)
LEG_FLEX = (0.0, 1.0, 0.0)

# ------------------------------------------------------------------ 자세

# 싸움 자세 — 왼발 앞, 주먹은 턱 앞. 평타는 여기서 나가서 여기로 돌아온다
GUARD = {
    "hips": (0.0, 0.0, -0.035), "hipsR": (0, 0, -15),
    "spine": (8, 0, -6), "head": (-6, 0, 21),
    "lh": (0.08, -0.17, 0.79), "lhPole": (0.7, 0.2, -1),
    "rh": (-0.05, -0.12, 0.78), "rhPole": (-0.7, 0.2, -1),
    "lf": (0.10, -0.09, 0.078), "lfPole": (0.2, -1, 0),
    "rf": (-0.11, 0.11, 0.078), "rfPole": (-0.3, -1, 0), "rfYaw": -25,
}


def pose(base, **over):
    """자세 하나를 바탕 자세에서 몇 가지만 바꿔 만든다"""
    out = dict(base)
    out.update(over)
    return out


# 잽 — 왼주먹을 곧게 뻗는다. 몸을 오른쪽으로 더 틀어 어깨가 따라 나간다
JAB = pose(GUARD,
           hips=(0.0, -0.02, -0.045), hipsR=(0, 0, -30),
           spine=(11, 0, -12), head=(-6, 0, 40),
           lh=(0.02, -0.46, 0.80), lhPole=(1, 0, -0.6),
           rh=(-0.04, -0.13, 0.79))

# 스트레이트 — 오른주먹. 몸을 왼쪽으로 크게 돌리고 뒤꿈치를 든다
CROSS = pose(GUARD,
             hips=(0.0, -0.035, -0.05), hipsR=(0, 0, 18),
             spine=(12, 0, 16), head=(-6, 0, -32),
             rh=(-0.01, -0.48, 0.79), rhPole=(-1, 0, -0.6),
             lh=(0.09, -0.10, 0.80),
             rf=(-0.10, 0.09, 0.10), rfYaw=0, rfPitch=25)

# 할퀴기 — 넓은 자세에서 오른손·왼손·오른손으로 앞을 가로질러 긁는다.
# 이펙트의 첫 줄기가 캐릭터 오른쪽에서 왼쪽으로 가고 번갈아 돈다 (`SkillFx.local_point`)
CLAW_BASE = pose(GUARD,
                 hips=(0.0, 0.0, -0.06),
                 lf=(0.13, -0.10, 0.078), rf=(-0.13, 0.08, 0.078), rfYaw=-20)
CLAW_R_WIND = pose(CLAW_BASE, hipsR=(0, 0, -25), spine=(10, 0, -10), head=(-6, 0, 35),
                   rh=(-0.36, -0.10, 0.90), rhPole=(-0.3, 0.5, -1),
                   lh=(0.16, -0.20, 0.70))
CLAW_R_DONE = pose(CLAW_BASE, hipsR=(0, 0, 22), spine=(14, 0, 12), head=(-8, 0, -34),
                   rh=(0.20, -0.32, 0.60), rhPole=(-0.3, 0, -1),
                   lh=(0.34, -0.04, 0.88), lhPole=(0.3, 0.5, -1))
CLAW_L_DONE = pose(CLAW_BASE, hipsR=(0, 0, -24), spine=(14, 0, -12), head=(-8, 0, 36),
                   lh=(-0.22, -0.32, 0.62), lhPole=(0.3, 0, -1),
                   rh=(-0.34, -0.02, 0.90), rhPole=(-0.3, 0.5, -1))
CLAW_R_LAST = pose(CLAW_BASE, hips=(0.0, -0.02, -0.08), hipsR=(0, 0, 28),
                   spine=(18, 0, 14), head=(-10, 0, -40),
                   rh=(0.24, -0.34, 0.54), rhPole=(-0.3, 0, -1),
                   lh=(0.15, -0.02, 0.62), lhPole=(0.3, 1, -0.2))

# 낙뢰 — 오른주먹을 머리 위로 치켜들었다가 한쪽 무릎을 꿇으며 **발 앞 바닥에 꽂는다**
# (2026-09-24 요청: "바닥을 주먹으로 꽂는 애니메이션으로"). 번개가 시전자 자리에
# 세 번 떨어지므로(`LightningFx.AHEAD` 0 · `STRIKE_GAP` 0.18) 주먹을 꽂은 채 둘째·셋째에
# 맞춰 몸이 움찔한다. 팔이 짧아(어깨~손목 0.29) 무릎을 꿇고 크게 숙여야 주먹이 땅에 닿는다
THUNDER_RAISE = pose(GUARD,
                     hips=(0.0, 0.02, 0.0), hipsR=(0, 0, -10),
                     spine=(-10, 0, -6), head=(-12, 0, 14),
                     rh=(-0.12, 0.10, 1.12), rhPole=(-1, 0, 0.3),
                     lh=(0.20, -0.12, 0.70), lhPole=(1, 0, -1),
                     lf=(0.11, -0.10, 0.078), rf=(-0.11, 0.12, 0.078))
THUNDER_SLAM = pose(GUARD,
                    hips=(0.0, -0.06, -0.28), hipsR=(45, 0, -10),
                    spine=(42, 0, -6), head=(-55, 0, 12),
                    rh=(-0.07, -0.24, 0.08), rhPole=(-0.6, 0.8, 0),
                    lh=(0.24, 0.12, 0.42), lhPole=(0.5, 1, 0),
                    lf=(0.12, -0.14, 0.078), lfPole=(0.3, -1, 0.3),
                    rf=(-0.11, 0.22, 0.10), rfPole=(0, -0.3, -1), rfYaw=0, rfPitch=-25)
THUNDER_JOLT = pose(THUNDER_SLAM, hips=(0.0, -0.06, -0.30), spine=(48, 0, -6))

# 천붕각 — **웅크렸다 뛰어올라** 정점에서 오른발을 치켜들고, 떨어지며 발뒤꿈치와 두
# 주먹으로 땅을 강하게 찍는다 (2026-09-24 요청: "점프해서 땅을 강하게 내려 찍는").
# 찍는 순간이 0.72초라 판정·이펙트도 그만큼 늦췄다 (`skills.ts` 의 `delayMs` 720 — 같이 고친다).
# 몸은 정점에서 2.4 (게임에서 약 4.3m) 뜬다. 0.26(0.47m) → "너무 낮게 뛴다" 로 0.60(1.1m) →
# "지금의 5배" 로 3.0(5.4m) → "4/5 로 낮춰" 로 2.4. 5m 안팎을 0.42초에 오르내리면 순간이동이라
# 착지를 0.72초로 늦췄다. 카메라(화각 30° · 26.7m · 42°)에서 5.4m 때 머리끝이 화면 중심 위 11.6° 였다
SKY_CROUCH = pose(GUARD,
                  hips=(0.0, 0.0, -0.11), hipsR=(0, 0, 0),
                  spine=(22, 0, 0), head=(-14, 0, 0),
                  lh=(0.20, 0.16, 0.50), lhPole=(0.5, -1, 0),
                  rh=(-0.20, 0.16, 0.50), rhPole=(-0.5, -1, 0),
                  lf=(0.10, -0.02, 0.078), lfPole=(0.2, -1, 0),
                  rf=(-0.10, 0.02, 0.078), rfPole=(-0.2, -1, 0), rfYaw=0)
SKY_TAKEOFF = pose(GUARD,
                   hips=(0.0, -0.01, 0.16), hipsR=(0, 0, 0),
                   spine=(-6, 0, 0), head=(-6, 0, 0),
                   lh=(0.20, -0.16, 1.11), lhPole=(1, 0.3, -0.5),
                   rh=(-0.20, -0.16, 1.11), rhPole=(-1, 0.3, -0.5),
                   lf=(0.09, 0.0, 0.20), lfPole=(0.2, -1, 0), lfPitch=-35,
                   rf=(-0.09, 0.02, 0.20), rfPole=(-0.2, -1, 0), rfYaw=0, rfPitch=-35)
SKY_APEX = pose(GUARD,
                hips=(0.0, 0.0, 0.60), hipsR=(0, 0, 0),
                spine=(-12, 0, 0), head=(-2, 0, 0),
                lh=(0.30, 0.0, 1.64), lhPole=(1, 0, 0),
                rh=(-0.30, 0.0, 1.64), rhPole=(-1, 0, 0),
                rf=(-0.07, -0.30, 1.48), rfPole=(0, 0.5, 1), rfYaw=0, rfPitch=-40,
                lf=(0.08, 0.10, 0.76), lfPole=(0, -1, 0))
SKY_FALL = pose(GUARD,
                hips=(0.0, -0.02, 0.28), hipsR=(8, 0, 0),
                spine=(10, 0, 0), head=(-10, 0, 0),
                lh=(0.28, -0.14, 1.02), lhPole=(1, 0.4, 0),
                rh=(-0.28, -0.14, 1.02), rhPole=(-1, 0.4, 0),
                rf=(-0.08, -0.34, 0.68), rfPole=(0, -0.5, 1), rfYaw=0,
                lf=(0.08, 0.14, 0.50), lfPole=(0, -1, 0))
SKY_SLAM = pose(GUARD,
                hips=(0.0, -0.05, -0.20), hipsR=(12, 0, 0),
                spine=(26, 0, 0), head=(-26, 0, 0),
                lh=(0.24, -0.26, 0.22), lhPole=(0.6, 1, 0),
                rh=(-0.24, -0.26, 0.22), rhPole=(-0.6, 1, 0),
                rf=(-0.08, -0.30, 0.078), rfPole=(-0.1, -1, 0.2), rfYaw=0,
                lf=(0.09, 0.26, 0.11), lfPole=(0.1, -1, -0.6), lfPitch=35)


def lift(base, dz):
    """공중 자세를 통째로 dz 만큼 올린다 — 몸(Root)과 손발 목표점을 같이 올려 팔다리 모양은 그대로다"""
    up = lambda v: (v[0], v[1], v[2] + dz)
    return pose(base, hips=up(base["hips"]), lh=up(base["lh"]), rh=up(base["rh"]),
                lf=up(base["lf"]), rf=up(base["rf"]))


# 높이 — 정점 0.60 → 3.0("5배") → 2.4("4/5 로 낮춰"). 오르는 중·떨어지는 중도 같은 비율(4/5)이다.
# 오르는 중(RISE)은 발을 곧게 늘어뜨린 도약 자세 그대로다
SKY_RISE = lift(SKY_TAKEOFF, 1.52)
SKY_APEX_HIGH = lift(SKY_APEX, 1.80)
SKY_FALL_HIGH = lift(SKY_FALL, 0.68)
# 찍은 반동으로 한 번 더 눌렸다가(0.78) 버틴다
SKY_RECOIL = pose(SKY_SLAM, hips=(0.0, -0.05, -0.235), spine=(32, 0, 0))
SKY_SETTLE = pose(SKY_SLAM, hips=(0.0, -0.05, -0.21), spine=(28, 0, 0))

# 빙주각 — 왼 무릎을 높이 들었다가 짓밟으며 말 탄 자세로 내려앉고 두 손바닥을 땅으로 누른다.
FROST_LIFT = pose(GUARD,
                  hips=(0.0, 0.0, 0.01), hipsR=(0, 0, -6),
                  spine=(-6, 0, 0), head=(-4, 0, 6),
                  lf=(0.09, -0.12, 0.36), lfPole=(0, -1, 0.2),
                  rf=(-0.09, 0.02, 0.078), rfYaw=-10,
                  lh=(0.22, -0.18, 0.96), lhPole=(1, 0, -0.3),
                  rh=(-0.22, -0.18, 0.96), rhPole=(-1, 0, -0.3))
FROST_STOMP = pose(GUARD,
                   hips=(0.0, 0.0, -0.12), hipsR=(0, 0, 0),
                   spine=(14, 0, 0), head=(-10, 0, 0),
                   lf=(0.21, -0.04, 0.078), lfPole=(1, -1, 0), lfYaw=25,
                   rf=(-0.21, 0.04, 0.078), rfPole=(-1, -1, 0), rfYaw=-25,
                   lh=(0.31, -0.15, 0.42), lhPole=(1, 0.3, 0),
                   rh=(-0.31, -0.15, 0.42), rhPole=(-1, 0.3, 0))
FROST_HOLD = pose(FROST_STOMP, hips=(0.0, 0.0, -0.135), spine=(17, 0, 0))

# 클립 — (초, 자세, 그 키에서 다음 키로 가는 보간). 자세 "IDLE" 은 대기 클립의 첫 자세다.
# 부딪히는 키 앞은 LINEAR 로 곧게 들어가고, 뒤는 BEZIER 로 풀어진다
CLIPS = {
    "Jab": [(0.0, GUARD, "LINEAR"), (0.09, JAB, "BEZIER"), (0.18, JAB, "BEZIER"),
            (0.40, GUARD, "BEZIER"), (0.60, GUARD, "BEZIER")],
    "Cross": [(0.0, GUARD, "LINEAR"), (0.10, CROSS, "BEZIER"), (0.20, CROSS, "BEZIER"),
              (0.42, GUARD, "BEZIER"), (0.60, GUARD, "BEZIER")],
    "Claw": [(0.0, CLAW_R_WIND, "LINEAR"), (0.10, CLAW_R_DONE, "LINEAR"),
             (0.18, CLAW_L_DONE, "LINEAR"), (0.28, CLAW_R_LAST, "BEZIER"),
             (0.46, CLAW_R_LAST, "BEZIER"), (0.75, GUARD, "BEZIER"), (1.0, "IDLE", "BEZIER")],
    "Thunder": [(0.0, THUNDER_RAISE, "LINEAR"), (0.12, THUNDER_SLAM, "LINEAR"),
                (0.20, THUNDER_JOLT, "LINEAR"), (0.28, THUNDER_SLAM, "LINEAR"),
                (0.38, THUNDER_JOLT, "BEZIER"), (0.46, THUNDER_SLAM, "BEZIER"),
                (0.70, THUNDER_SLAM, "BEZIER"),
                (1.1, "IDLE", "BEZIER")],
    "SkyBreaker": [(0.0, SKY_CROUCH, "BEZIER"), (0.10, SKY_TAKEOFF, "LINEAR"),
                   (0.24, SKY_RISE, "BEZIER"), (0.42, SKY_APEX_HIGH, "BEZIER"),
                   (0.62, SKY_FALL_HIGH, "LINEAR"), (0.72, SKY_SLAM, "LINEAR"),
                   (0.78, SKY_RECOIL, "BEZIER"), (0.88, SKY_SETTLE, "BEZIER"),
                   (1.10, SKY_SETTLE, "BEZIER"), (1.45, "IDLE", "BEZIER")],
    "FrostStomp": [(0.0, FROST_LIFT, "LINEAR"), (0.10, FROST_STOMP, "BEZIER"),
                   (0.22, FROST_HOLD, "BEZIER"), (0.55, FROST_HOLD, "BEZIER"),
                   (1.0, "IDLE", "BEZIER")],
}

# ------------------------------------------------------------------ 풀기


def euler(deg):
    return Euler(tuple(math.radians(v) for v in deg), "XYZ").to_quaternion()


def two_bone(root, target, l1, l2, pole):
    """어깨(골반)·손목(발목)과 굽는 쪽이 주어지면 팔꿈치(무릎) 자리를 준다"""
    to = target - root
    d = max(1e-4, min(to.length, (l1 + l2) * 0.999))
    axis = to.normalized()
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    bend = pole - axis * pole.dot(axis)
    if bend.length < 1e-6:
        bend = Vector((0, 0, -1))
    return root + axis * a + bend.normalized() * h


class Poser:
    def __init__(self, arm):
        self.arm = arm
        self.pb = arm.pose.bones
        self.rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
        for p in self.pb:
            p.rotation_mode = "QUATERNION"
        self.idle = None

    def update(self):
        bpy.context.view_layer.update()

    def length(self, a, b):
        return (self.rest[b].translation - self.rest[a].translation).length

    def carried(self, name):
        """부모 자세를 따라간 이 뼈의 기본(회전 0) 행렬"""
        p = self.pb[name]
        if p.parent is None:
            return self.rest[name].copy()
        return p.parent.matrix @ (self.rest[p.parent.name].inverted() @ self.rest[name])

    def set_world_rot(self, name, rot3):
        m = self.carried(name)
        full = Matrix.Translation(m.translation) @ rot3.to_4x4()
        self.pb[name].matrix = full
        self.update()

    def rotate(self, name, quat):
        """부모 기준 회전 — 축은 아마추어 축 그대로다"""
        m = self.carried(name).to_3x3()
        self.set_world_rot(name, quat.to_matrix() @ m)

    def aim(self, name, direction):
        m = self.carried(name).to_3x3()
        now = (m @ Vector((0, 1, 0))).normalized()
        turn = now.rotation_difference(direction.normalized()).to_matrix()
        self.set_world_rot(name, turn @ m)

    def limb(self, bones, target, pole, flex):
        """팔다리 하나를 푼다.

        `flex` 는 기본 자세에서 아랫마디가 굽는 쪽이다 — T 자세 팔은 앞(-Y)으로,
        다리는 뒤(+Y)로 굽는다. 윗마디를 겨누기만 하면 비틀림이 제멋대로라 팔꿈치가
        거꾸로 꺾여 보일 수 있다. 그래서 겨눈 뒤 **굽는 쪽이 팔꿈치(무릎) 반대편을
        보도록** 윗마디를 제 축으로 비튼다.
        """
        upper, lower = bones[0], bones[1]
        end = bones[2]
        l1 = self.length(upper, lower)
        l2 = self.length(lower, end)
        root = self.pb[upper].head.copy()
        target = Vector(target)
        joint = two_bone(root, target, l1, l2, Vector(pole))
        self.aim(upper, joint - root)

        # 굽는 쪽 = 팔꿈치에서 손목으로 가는 쪽을 윗마디에 수직으로 뺀 것. 거의 곧게
        # 뻗었으면 그 값이 흔들리므로 팔꿈치가 향하는 반대편으로 대신한다
        axis = (joint - root).normalized()
        want = target - joint
        want = want - axis * want.dot(axis)
        if want.length < 0.02 * l2:
            want = -(Vector(pole) - axis * Vector(pole).dot(axis))
        m = self.pb[upper].matrix.to_3x3()
        local_flex = self.rest[upper].to_3x3().inverted() @ Vector(flex)
        have = m @ local_flex
        have = have - axis * have.dot(axis)
        if want.length > 1e-6 and have.length > 1e-6:
            # 축 둘레로만 돌린다 — rotation_difference 는 180° 에서 축을 제멋대로 골라
            # 윗마디 방향까지 틀어 버린다
            angle = math.atan2(axis.dot(have.cross(want)), have.dot(want))
            self.set_world_rot(upper, Matrix.Rotation(angle, 3, axis) @ m)
        self.aim(lower, target - self.pb[lower].head)

    def foot(self, bones, yaw, pitch):
        """발바닥을 땅에 붙인다 — 쉴 때 발 방향을 yaw 만큼 돌리고 pitch 만큼 든다"""
        rest_dir = (self.rest[bones[3]].translation - self.rest[bones[2]].translation).normalized()
        d = Euler((math.radians(-pitch), 0, math.radians(yaw)), "XYZ").to_matrix() @ rest_dir
        self.aim(bones[2], d)
        self.pb[bones[3]].matrix_basis = Matrix.Identity(4)
        self.update()

    def apply(self, spec):
        for p in self.pb:
            p.matrix_basis = Matrix.Identity(4)
        self.update()
        if spec == "IDLE":
            for name, (loc, rot) in self.idle.items():
                self.pb[name].location = loc
                self.pb[name].rotation_quaternion = rot
            self.update()
            return

        # 몸 높이·앞뒤는 Root 를 옮긴다 — 바르코 클립도 Root 이동만 키로 갖고 Hips 이동은
        # 없다. Hips 를 옮기면 달리기로 끊겼을 때 그 높이가 그대로 남아 몸이 가라앉는다
        root = self.rest["Root"]
        self.pb["Root"].matrix = Matrix.Translation(Vector(spec["hips"])) @ root
        self.update()
        self.rotate("Hips", euler(spec["hipsR"]))
        share = tuple(v / len(SPINE) for v in spec["spine"])
        for name in SPINE:
            self.rotate(name, euler(share))
        self.rotate("Neck", euler(tuple(v * 0.4 for v in spec["head"])))
        self.rotate("Head", euler(tuple(v * 0.6 for v in spec["head"])))
        self.limb(ARM_L, spec["lh"], spec["lhPole"], ARM_FLEX)
        self.limb(ARM_R, spec["rh"], spec["rhPole"], ARM_FLEX)
        self.limb(LEG_L, spec["lf"], spec["lfPole"], LEG_FLEX)
        self.foot(LEG_L, spec.get("lfYaw", 0), spec.get("lfPitch", 0))
        self.limb(LEG_R, spec["rf"], spec["rfPole"], LEG_FLEX)
        self.foot(LEG_R, spec.get("rfYaw", 0), spec.get("rfPitch", 0))

    def key(self, action, frame, interp, last):
        """모든 뼈에 키를 박는다 — 빠진 뼈는 고도에서 앞 클립 자세로 굳는다"""
        for p in self.pb:
            q = p.rotation_quaternion.copy()
            prev = last.get(p.name)
            if prev is not None and prev.dot(q) < 0:
                q.negate()
            p.rotation_quaternion = q
            last[p.name] = q
            p.keyframe_insert("rotation_quaternion", frame=frame)
            p.keyframe_insert("location", frame=frame)
        for fc in action.fcurves:
            for kp in fc.keyframe_points:
                if abs(kp.co.x - frame) < 1e-3:
                    kp.interpolation = interp


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=BASE, bone_heuristic="BLENDER")
    scene = bpy.context.scene
    scene.render.fps = FPS
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    poser = Poser(arm)

    idle = bpy.data.actions["Idle"]
    arm.animation_data.action = idle
    scene.frame_set(int(idle.frame_range[0]))
    poser.idle = {p.name: (p.location.copy(), p.rotation_quaternion.copy()) for p in poser.pb}

    # 바르코 클립은 내보내지 않는다 — 이 파일에는 새 클립만 담는다
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)

    for name, keys in CLIPS.items():
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        arm.animation_data.action = action
        last = {}
        for t, spec, interp in keys:
            poser.apply(spec)
            poser.key(action, round(t * FPS), interp, last)
        report(poser, name, keys)

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


def report(poser, name, keys):
    """키마다 손발 끝이 어디 있는지 찍는다 — 눈으로 보기 전에 숫자로 먼저 본다"""
    for t, spec, _ in keys:
        poser.apply(spec)
        pb = poser.pb
        parts = []
        for bone in ("LeftHand", "RightHand", "LeftFoot", "RightFoot"):
            h = pb[bone].head
            parts.append(f"{bone}=({h.x:+.2f},{h.y:+.2f},{h.z:+.2f})")
        low = min(pb[b].tail.z for b in ("LeftToeBase", "RightToeBase"))
        knee = min(pb[b].head.z for b in ("LeftLeg", "RightLeg"))
        print(f"  {name:10s} {t:4.2f}s  " + " ".join(parts) + f"  발끝최저={low:+.3f}  무릎최저={knee:+.3f}  굽힘맞음={bend_check(poser):+.2f}")


def bend_check(poser):
    """굽은 마디가 해부학적으로 굽는 쪽으로 굽었나 — 가장 나쁜 마디의 코사인 (1 이 맞음, 음수면 거꾸로)"""
    worst = 1.0
    for bones, flex in ((ARM_L, ARM_FLEX), (ARM_R, ARM_FLEX), (LEG_L, LEG_FLEX), (LEG_R, LEG_FLEX)):
        up, lo = poser.pb[bones[0]], poser.pb[bones[1]]
        u = (up.tail - up.head).normalized()
        v = (lo.tail - lo.head).normalized()
        bend = v - u * v.dot(u)
        if bend.length < math.sin(math.radians(10)):
            continue
        f = up.matrix.to_3x3() @ (poser.rest[bones[0]].to_3x3().inverted() @ Vector(flex))
        f = f - u * f.dot(u)
        worst = min(worst, bend.normalized().dot(f.normalized()))
    return worst


main()
