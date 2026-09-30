"""저레벨 몬스터 여섯 종 — 바르코 메시에 뼈대를 달고 동작 넷을 지어 GLB 로 낸다.

    npm run blender -- --python scripts/blender/mob_moves.py              # 여섯 전부
    npm run blender -- --python scripts/blender/mob_moves.py -- slime     # 하나만
    npm run sync:godot

입력  assets-src/models/varco/mob_<종>_mesh.glb   (바르코 원화 → 3D. fetch-assets.sh 가 받는다)
출력  public/assets/models/mob_<종>.glb            (메시 + 뼈대 + Idle · Run · Attack · Death)

**왜 블렌더에서 뼈대까지 다나.** 바르코의 뼈대 달기(`Rig`)는 사람 몸만 된다. 슬라임·토끼·
버섯·사마귀·전갈은 몸이 사람이 아니라서 여기서 뼈를 세운다. 코볼트는 사람 몸이지만 여섯을
한 길로 만들려고 같이 한다 (꼬리 뼈도 필요했다). 2026-09-29 지시: "애니메이션은 블렌더로 만들어".

**뼈 자리는 정점 분포에서 읽었다.** 메시는 크기 1 로 맞춰져 오고(가장 긴 변 = 1), 여기서
발바닥을 z = 0 으로 내린다. `BONES` 의 좌표가 그 공간이다 — 정점을 격자로 찍어 다리·머리·
꼬리 자리를 읽고 적었다.

**무게는 가까운 뼈에서 준다.** 정점마다 뼈 선분까지 거리를 재서 가까운 셋에 1/거리⁵ 로
나눈다. 자동 무게(bone heat)는 바르코 메시처럼 닫히지 않은 메시에서 자주 실패한다.

**자세는 아마추어 공간의 각도로 적는다** (fighter_moves.py 와 같은 축):

    +X = 몬스터의 왼쪽 · -Y = 앞 · +Z = 위

    X 양수 = 앞으로 숙인다 (위로 선 뼈) / 뒤로 찬다 (아래로 선 다리)
    Y 양수 = 몬스터 왼쪽(+X)으로 기운다 · Z 양수 = 왼쪽으로 돈다

각 뼈의 회전은 **그 뼈가 쉬는 자세에서** 이 축으로 돈 만큼이다. 부모가 돌면 자식은 그 위에
얹힌다. `l` 은 옮기기(아마추어 축), `s` 는 뼈 축 크기(뼈 길이 방향이 두 번째 값)다.

**클립 길이·시각은 고도에 맞춘다.**
- `Attack` 은 고도가 **0.8초부터 0.65초**만 튼다 (`game.gd` 의 `MOB_SWING_FROM`, 서버 경직
  `monsterSwingMs`). 그래서 0~0.8 은 대기 자세로 두고, 0.95 에 움츠렸다 1.08 에 친다.
- `Idle`·`Run` 은 고도가 끝나면 다시 틀어 반복한다 — 첫 키와 끝 키를 같게 둔다(`loop`).
- `Death` 는 끝 자세에 멈춘다.
- **모든 클립이 모든 뼈에 키를 가진다.** 없는 뼈는 앞 클립 자세가 남아 섞인다.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 30
SRC = 'assets-src/models/varco/mob_{}_mesh.glb'
OUT = 'public/assets/models/mob_{}.glb'
# 텍스처 한 변 상한. 바르코가 1024 · 2048 두 장을 주는데 고도로 옮길 때 512 로 줄인다
# (sync-godot-assets.mjs) — 저장소에 2048 을 둘 까닭이 없다
TEX_MAX = 1024
AXES = {'x': Vector((1, 0, 0)), 'y': Vector((0, 1, 0)), 'z': Vector((0, 0, 1))}


def r(*pairs):
    """r('x', 10, 'z', -5) → 앞의 것부터 차례로 돈다"""
    return [(pairs[i], pairs[i + 1]) for i in range(0, len(pairs), 2)]


def mirror(bones):
    """이름에 L 이 붙은 뼈를 R 로 한 벌 더 (x 를 뒤집는다)"""
    out = []
    for name, head, tail, parent in bones:
        out.append((name, head, tail, parent))
        if name.endswith('L'):
            flip = lambda p: (-p[0], p[1], p[2])
            rp = parent[:-1] + 'R' if parent and parent.endswith('L') else parent
            out.append((name[:-1] + 'R', flip(head), flip(tail), rp))
    return out


def side(pose, **pairs):
    """왼쪽 자세를 오른쪽에 거울로 — 'x' 는 그대로, 'y'·'z' 는 부호를 뒤집는다"""
    out = dict(pose)
    for name, spec in list(pose.items()):
        if name.endswith('L') and name[:-1] + 'R' not in pose:
            m = {}
            if 'r' in spec:
                m['r'] = [(a, d if a == 'x' else -d) for a, d in spec['r']]
            if 'l' in spec:
                x, y, z = spec['l']
                m['l'] = (-x, y, z)
            if 's' in spec:
                m['s'] = spec['s']
            out[name[:-1] + 'R'] = m
    return out


def merge(*poses):
    """자세 여럿을 겹친다 — 회전은 이어 붙이고 옮기기는 더한다"""
    out = {}
    for pose in poses:
        for name, spec in pose.items():
            cur = out.setdefault(name, {})
            if 'r' in spec:
                cur['r'] = cur.get('r', []) + list(spec['r'])
            if 'l' in spec:
                a = cur.get('l', (0, 0, 0))
                cur['l'] = tuple(a[i] + spec['l'][i] for i in range(3))
            if 's' in spec:
                a = cur.get('s', (1, 1, 1))
                cur['s'] = tuple(a[i] * spec['s'][i] for i in range(3))
    return out


# ---------------------------------------------------------------- 슬라임
# 뼈 셋을 위로 쌓아 크기로 출렁인다. 통통 튀며 다가와 몸으로 덮친다
SLIME = {
    'bones': [
        ('Base', (0, 0, 0.0), (0, 0, 0.28), 'Root'),
        ('Mid', (0, 0, 0.28), (0, 0, 0.56), 'Base'),
        ('Top', (0, 0, 0.56), (0, 0, 0.85), 'Mid'),
    ],
    'clips': {
        'Idle': (2.0, True, [
            (0.0, {}),
            (1.0, {'Base': {'s': (1.04, 0.93, 1.04)}, 'Top': {'r': r('x', 3)}}),
        ]),
        'Run': (0.6, True, [
            (0.0, {'Base': {'s': (1.14, 0.78, 1.14)}}),
            (0.12, {'Base': {'s': (0.9, 1.18, 0.9)}, 'Root': {'l': (0, 0, 0.1)}, 'Mid': {'r': r('x', 8)}}),
            (0.3, {'Base': {'s': (0.97, 1.06, 0.97)}, 'Root': {'l': (0, 0, 0.22)}, 'Mid': {'r': r('x', 4)}}),
            (0.48, {'Base': {'s': (1.0, 1.0, 1.0)}, 'Root': {'l': (0, 0, 0.08)}, 'Mid': {'r': r('x', -4)}}),
        ]),
        'Attack': (1.5, False, [
            (0.0, {}),
            (0.8, {}),
            (0.95, {'Base': {'s': (1.18, 0.72, 1.18)}, 'Mid': {'r': r('x', -12)}}),
            (1.08, {'Base': {'s': (0.86, 1.22, 0.86)}, 'Mid': {'r': r('x', 20)},
                    'Root': {'l': (0, -0.35, 0.14)}}),
            (1.18, {'Base': {'s': (1.25, 0.7, 1.25)}, 'Mid': {'r': r('x', 8)},
                    'Root': {'l': (0, -0.35, 0.0)}}),
            (1.45, {}),
            (1.5, {}),
        ]),
        'Death': (1.2, False, [
            (0.0, {}),
            (0.25, {'Base': {'s': (0.94, 1.12, 0.94)}}),
            (0.7, {'Base': {'s': (1.5, 0.16, 1.5)}}),
            (1.2, {'Base': {'s': (1.6, 0.08, 1.6)}}),
        ]),
    },
}

# ---------------------------------------------------------------- 뿔토끼
# 네 발로 뛰고, 뒷발로 박차 뿔로 들이받는다
HARE_BONES = mirror([
    ('Spine', (0, 0.30, 0.42), (0, 0.05, 0.44), 'Root'),
    ('Chest', (0, 0.05, 0.44), (0, -0.16, 0.48), 'Spine'),
    ('Neck', (0, -0.16, 0.48), (0, -0.26, 0.58), 'Chest'),
    ('Head', (0, -0.26, 0.58), (0, -0.42, 0.66), 'Neck'),
    ('EarL', (0.05, -0.24, 0.70), (0.06, -0.22, 0.94), 'Head'),
    ('ArmL', (0.09, -0.12, 0.34), (0.09, -0.12, 0.16), 'Chest'),
    ('HandL', (0.09, -0.12, 0.16), (0.09, -0.14, 0.0), 'ArmL'),
    ('ThighL', (0.10, 0.26, 0.36), (0.10, 0.34, 0.18), 'Spine'),
    ('FootL', (0.10, 0.34, 0.18), (0.10, 0.24, 0.0), 'ThighL'),
    ('Tail', (0, 0.44, 0.44), (0, 0.50, 0.52), 'Spine'),
])
HARE_RUN_OUT = side({'ArmL': {'r': r('x', -38)}, 'HandL': {'r': r('x', -10)},
                     'ThighL': {'r': r('x', 34)}, 'FootL': {'r': r('x', 12)},
                     'Spine': {'r': r('x', -5)}, 'Root': {'l': (0, 0, 0.10)}})
HARE_RUN_IN = side({'ArmL': {'r': r('x', 26)}, 'HandL': {'r': r('x', 20)},
                    'ThighL': {'r': r('x', -32)}, 'FootL': {'r': r('x', -18)},
                    'Spine': {'r': r('x', 6)}})
HARE_EARS_BACK = side({'EarL': {'r': r('x', -22)}, 'Head': {'r': r('x', -6)}})
HARE = {
    'bones': HARE_BONES,
    'clips': {
        'Idle': (2.4, True, [
            (0.0, {}),
            (0.6, side({'EarL': {'r': r('y', 4)}, 'Head': {'r': r('x', 3)}})),
            (1.2, {'Chest': {'r': r('x', -2)}}),
            (1.8, side({'EarL': {'r': r('y', -3)}, 'Head': {'r': r('z', 5)}})),
        ]),
        'Run': (0.5, True, [
            (0.0, merge(HARE_RUN_OUT, HARE_EARS_BACK)),
            (0.25, merge(HARE_RUN_IN, HARE_EARS_BACK)),
        ]),
        'Attack': (1.5, False, [
            (0.0, {}),
            (0.8, {}),
            (0.95, side({'Root': {'l': (0, 0.04, -0.04)}, 'Spine': {'r': r('x', -6)},
                         'Head': {'r': r('x', -18)}, 'ThighL': {'r': r('x', -20)},
                         'ArmL': {'r': r('x', 10)}, 'EarL': {'r': r('x', -15)}})),
            (1.08, side({'Root': {'l': (0, -0.26, 0.06)}, 'Chest': {'r': r('x', 10)},
                         'Head': {'r': r('x', 28)}, 'ArmL': {'r': r('x', -40)},
                         'ThighL': {'r': r('x', 42)}, 'FootL': {'r': r('x', 20)},
                         'EarL': {'r': r('x', -30)}})),
            (1.2, side({'Root': {'l': (0, -0.26, 0.0)}, 'Head': {'r': r('x', 22)},
                        'ArmL': {'r': r('x', -10)}, 'ThighL': {'r': r('x', 10)}})),
            (1.45, {}),
            (1.5, {}),
        ]),
        'Death': (1.2, False, [
            (0.0, {}),
            (0.3, side({'Root': {'l': (0, 0, 0.04)}, 'Head': {'r': r('x', -20)}})),
            (0.8, side({'Root': {'r': r('y', 82)}, 'Head': {'r': r('x', 15)},
                        'ArmL': {'r': r('x', -20)}, 'ThighL': {'r': r('x', 20)}, 'EarL': {'r': r('x', -20)}})),
            (1.2, side({'Root': {'r': r('y', 86)}, 'Head': {'r': r('x', 20)},
                        'ArmL': {'r': r('x', -25)}, 'ThighL': {'r': r('x', 25)}, 'EarL': {'r': r('x', -25)}})),
        ]),
    },
}

# ---------------------------------------------------------------- 버섯괴물
# 뒤뚱뒤뚱 걷고, 갓을 뒤로 젖혔다 내리찍는다
MUSHROOM = {
    'bones': mirror([
        ('Body', (0, 0, 0.12), (0, 0, 0.5), 'Root'),
        ('Cap', (0, 0, 0.5), (0, 0, 0.98), 'Body'),
        ('ArmL', (0.22, 0, 0.34), (0.34, 0, 0.30), 'Body'),
        ('HandL', (0.34, 0, 0.30), (0.44, -0.02, 0.26), 'ArmL'),
        ('LegL', (0.16, -0.03, 0.14), (0.16, -0.05, 0.0), 'Root'),
    ]),
    'clips': {
        'Idle': (2.4, True, [
            (0.0, {}),
            (1.2, side({'Cap': {'r': r('y', 3)}, 'Body': {'r': r('x', 2)}, 'ArmL': {'r': r('y', -6)}})),
        ]),
        'Run': (0.6, True, [
            (0.0, {'LegL': {'r': r('x', -28)}, 'LegR': {'r': r('x', 24)}, 'Body': {'r': r('y', -7)},
                   'ArmL': {'r': r('z', 18)}, 'ArmR': {'r': r('z', 18)}}),
            (0.15, {'Root': {'l': (0, 0, 0.05)}, 'Cap': {'r': r('y', 4)}}),
            (0.3, {'LegL': {'r': r('x', 24)}, 'LegR': {'r': r('x', -28)}, 'Body': {'r': r('y', 7)},
                   'ArmL': {'r': r('z', -18)}, 'ArmR': {'r': r('z', -18)}}),
            (0.45, {'Root': {'l': (0, 0, 0.05)}, 'Cap': {'r': r('y', -4)}}),
        ]),
        'Attack': (1.5, False, [
            (0.0, {}),
            (0.8, {}),
            (0.95, side({'Body': {'r': r('x', -16)}, 'Cap': {'r': r('x', -10)},
                         'ArmL': {'r': r('y', -40)}, 'Root': {'l': (0, 0.05, 0)}})),
            (1.08, side({'Body': {'r': r('x', 34)}, 'Cap': {'r': r('x', 16)},
                         'ArmL': {'r': r('y', 20)}, 'Root': {'l': (0, -0.12, 0)},
                         'LegL': {'r': r('x', -20)}})),
            (1.2, side({'Body': {'r': r('x', 28)}, 'Cap': {'r': r('x', 10)}, 'Root': {'l': (0, -0.12, 0)},
                        'LegL': {'r': r('x', -16)}})),
            (1.45, {}),
            (1.5, {}),
        ]),
        'Death': (1.2, False, [
            (0.0, {}),
            (0.3, side({'Body': {'r': r('x', 12)}, 'ArmL': {'r': r('y', -30)}})),
            (0.9, side({'Root': {'r': r('x', -84)}, 'Cap': {'r': r('x', -12)}, 'ArmL': {'r': r('y', 30)}})),
            (1.2, side({'Root': {'r': r('x', -88)}, 'Cap': {'r': r('x', -14)}, 'ArmL': {'r': r('y', 34)}})),
        ]),
    },
}

# ---------------------------------------------------------------- 사마귀
# 네 다리로 종종걸음, 낫을 치켜들었다 내리벤다
MANTIS = {
    'bones': mirror([
        ('Thorax', (0, 0.0, 0.24), (0, -0.30, 0.46), 'Root'),
        ('Abdomen', (0, 0.0, 0.24), (0, 0.5, 0.28), 'Root'),
        ('Head', (0, -0.32, 0.52), (0, -0.40, 0.66), 'Thorax'),
        ('ScytheL', (0.06, -0.30, 0.44), (0.26, -0.40, 0.76), 'Thorax'),
        ('BladeL', (0.26, -0.40, 0.76), (0.36, -0.46, 0.52), 'ScytheL'),
        ('WingL', (0.06, -0.10, 0.42), (0.42, -0.10, 0.46), 'Thorax'),
        ('FrontL', (0.06, -0.25, 0.24), (0.20, -0.40, 0.20), 'Thorax'),
        ('FrontShinL', (0.20, -0.40, 0.20), (0.34, -0.46, 0.0), 'FrontL'),
        ('BackL', (0.06, -0.02, 0.22), (0.26, 0.0, 0.24), 'Root'),
        ('BackShinL', (0.26, 0.0, 0.24), (0.42, 0.02, 0.0), 'BackL'),
    ]),
    'clips': {
        'Idle': (2.0, True, [
            (0.0, {}),
            (0.7, side({'Thorax': {'r': r('y', 4)}, 'Head': {'r': r('z', 8)}, 'BladeL': {'r': r('x', -6)},
                        'Abdomen': {'r': r('x', 3)}})),
            (1.4, side({'Thorax': {'r': r('y', -3)}, 'Head': {'r': r('z', -6)}, 'WingL': {'r': r('y', 3)}})),
        ]),
        'Run': (0.5, True, [
            (0.0, {'FrontL': {'r': r('z', 22)}, 'BackR': {'r': r('z', 22)},
                   'FrontR': {'r': r('z', 22)}, 'BackL': {'r': r('z', 22)},
                   'Thorax': {'r': r('y', 4)}}),
            (0.125, {'Root': {'l': (0, 0, 0.03)}, 'FrontShinL': {'r': r('x', -15)}, 'BackShinR': {'r': r('x', 15)}}),
            (0.25, {'FrontL': {'r': r('z', -22)}, 'BackR': {'r': r('z', -22)},
                    'FrontR': {'r': r('z', -22)}, 'BackL': {'r': r('z', -22)},
                    'Thorax': {'r': r('y', -4)}}),
            (0.375, {'Root': {'l': (0, 0, 0.03)}, 'FrontShinR': {'r': r('x', -15)}, 'BackShinL': {'r': r('x', 15)}}),
        ]),
        'Attack': (1.5, False, [
            (0.0, {}),
            (0.8, {}),
            (0.95, side({'Thorax': {'r': r('x', -12)}, 'ScytheL': {'r': r('x', -28)}, 'BladeL': {'r': r('x', -34)},
                         'WingL': {'r': r('y', 12)}, 'Root': {'l': (0, 0.05, 0)}})),
            (1.08, side({'Thorax': {'r': r('x', 22)}, 'ScytheL': {'r': r('x', 58)}, 'BladeL': {'r': r('x', 44)},
                         'Head': {'r': r('x', 10)}, 'Root': {'l': (0, -0.14, 0)}})),
            (1.2, side({'Thorax': {'r': r('x', 18)}, 'ScytheL': {'r': r('x', 50)}, 'BladeL': {'r': r('x', 40)},
                        'Root': {'l': (0, -0.14, 0)}})),
            (1.45, {}),
            (1.5, {}),
        ]),
        'Death': (1.2, False, [
            (0.0, {}),
            (0.3, side({'Thorax': {'r': r('x', -15)}, 'ScytheL': {'r': r('x', -20)}})),
            (0.9, side({'Root': {'r': r('y', 84)}, 'ScytheL': {'r': r('x', 40)}, 'BladeL': {'r': r('x', 40)},
                        'FrontShinL': {'r': r('x', -40)}, 'BackShinL': {'r': r('x', 40)}})),
            (1.2, side({'Root': {'r': r('y', 88)}, 'ScytheL': {'r': r('x', 46)}, 'BladeL': {'r': r('x', 46)},
                        'FrontShinL': {'r': r('x', -46)}, 'BackShinL': {'r': r('x', 46)}})),
        ]),
    },
}

# ---------------------------------------------------------------- 전갈
# 여덟 다리로 기고, 집게를 벌렸다 꼬리 독침을 앞으로 내리꽂는다
SCORPION_LEGS = []
for i, (hip_y, foot_y) in enumerate([(-0.06, -0.06), (0.0, 0.04), (0.06, 0.14), (0.12, 0.24)]):
    SCORPION_LEGS += [
        (f'Leg{i}L', (0.1, hip_y, 0.12), (0.26, (hip_y + foot_y) / 2, 0.15), 'Body'),
        (f'Leg{i}FootL', (0.26, (hip_y + foot_y) / 2, 0.15), (0.38, foot_y, 0.0), f'Leg{i}L'),
    ]
SCORPION = {
    'bones': mirror([
        ('Body', (0, 0.14, 0.12), (0, -0.16, 0.12), 'Root'),
        ('ArmL', (0.10, -0.14, 0.10), (0.26, -0.24, 0.10), 'Body'),
        ('ClawL', (0.26, -0.24, 0.10), (0.27, -0.48, 0.06), 'ArmL'),
        ('Tail1', (0, 0.14, 0.14), (0, 0.30, 0.20), 'Body'),
        ('Tail2', (0, 0.30, 0.20), (0, 0.42, 0.32), 'Tail1'),
        ('Tail3', (0, 0.42, 0.32), (0, 0.42, 0.48), 'Tail2'),
        ('Tail4', (0, 0.42, 0.48), (0, 0.30, 0.58), 'Tail3'),
        ('Sting', (0, 0.30, 0.58), (0, 0.12, 0.52), 'Tail4'),
    ] + SCORPION_LEGS),
}
_EVEN = {'r': r('z', 18)}
_ODD = {'r': r('z', -18)}
SCORPION['clips'] = {
    'Idle': (2.0, True, [
        (0.0, {}),
        (0.7, side({'Tail3': {'r': r('y', 5)}, 'Tail4': {'r': r('y', 4)}, 'ClawL': {'r': r('z', 8)}})),
        (1.4, side({'Tail3': {'r': r('y', -4)}, 'ClawL': {'r': r('z', -4)}, 'Body': {'r': r('x', 2)}})),
    ]),
    'Run': (0.4, True, [
        (0.0, {'Leg0L': _EVEN, 'Leg2L': _EVEN, 'Leg1R': {'r': r('z', 18)}, 'Leg3R': {'r': r('z', 18)},
               'Leg1L': _ODD, 'Leg3L': _ODD, 'Leg0R': {'r': r('z', -18)}, 'Leg2R': {'r': r('z', -18)},
               'Tail3': {'r': r('y', 3)}}),
        (0.2, {'Leg0L': _ODD, 'Leg2L': _ODD, 'Leg1R': {'r': r('z', -18)}, 'Leg3R': {'r': r('z', -18)},
               'Leg1L': _EVEN, 'Leg3L': _EVEN, 'Leg0R': {'r': r('z', 18)}, 'Leg2R': {'r': r('z', 18)},
               'Tail3': {'r': r('y', -3)}, 'Root': {'l': (0, 0, 0.015)}}),
    ]),
    'Attack': (1.5, False, [
        (0.0, {}),
        (0.8, {}),
        (0.95, side({'Tail2': {'r': r('x', -14)}, 'Tail3': {'r': r('x', -20)}, 'Tail4': {'r': r('x', -10)},
                     'ClawL': {'r': r('z', -16)}, 'ArmL': {'r': r('z', -10)}, 'Body': {'r': r('x', -4)}})),
        (1.08, side({'Tail1': {'r': r('x', 18)}, 'Tail2': {'r': r('x', 34)}, 'Tail3': {'r': r('x', 34)},
                     'Tail4': {'r': r('x', 22)}, 'Sting': {'r': r('x', 10)},
                     'ClawL': {'r': r('z', 12)}, 'ArmL': {'r': r('z', 8)}, 'Body': {'r': r('x', 6)},
                     'Root': {'l': (0, -0.06, 0)}})),
        (1.2, side({'Tail1': {'r': r('x', 14)}, 'Tail2': {'r': r('x', 28)}, 'Tail3': {'r': r('x', 28)},
                    'Tail4': {'r': r('x', 18)}, 'Root': {'l': (0, -0.06, 0)}})),
        (1.45, {}),
        (1.5, {}),
    ]),
    'Death': (1.2, False, [
        (0.0, {}),
        (0.3, side({'Tail2': {'r': r('x', -10)}, 'ClawL': {'r': r('z', -20)}})),
        (0.9, side({'Root': {'l': (0, 0, -0.06)}, 'Tail1': {'r': r('x', -20)}, 'Tail2': {'r': r('x', -30)},
                    'Tail3': {'r': r('x', -20)}, 'ArmL': {'r': r('z', -20)},
                    **{f'Leg{i}L': {'r': r('y', 22)} for i in range(4)}})),
        (1.2, side({'Root': {'l': (0, 0, -0.07)}, 'Tail1': {'r': r('x', -24)}, 'Tail2': {'r': r('x', -34)},
                    'Tail3': {'r': r('x', -24)}, 'ArmL': {'r': r('z', -24)},
                    **{f'Leg{i}L': {'r': r('y', 26)} for i in range(4)}})),
    ]),
}

# ---------------------------------------------------------------- 코볼트
# T 자세로 받는다. 팔을 내린 대기 자세를 바탕에 깔고, 오른손 단검으로 찌른다
KOBOLD_BONES = mirror([
    ('Hips', (0.01, -0.06, 0.26), (0.01, -0.07, 0.40), 'Root'),
    ('Spine', (0.01, -0.07, 0.40), (0.01, -0.08, 0.54), 'Hips'),
    ('Chest', (0.01, -0.08, 0.54), (0.01, -0.08, 0.66), 'Spine'),
    ('Neck', (0.01, -0.08, 0.66), (0.01, -0.10, 0.74), 'Chest'),
    ('Head', (0.01, -0.10, 0.74), (0.01, -0.22, 0.88), 'Neck'),
    ('UpperArmL', (0.10, -0.09, 0.68), (0.26, -0.09, 0.68), 'Chest'),
    ('ForeArmL', (0.26, -0.09, 0.68), (0.40, -0.09, 0.68), 'UpperArmL'),
    ('HandL', (0.40, -0.09, 0.68), (0.48, -0.09, 0.68), 'ForeArmL'),
    ('ThighL', (0.10, -0.06, 0.28), (0.11, -0.10, 0.15), 'Hips'),
    ('ShinL', (0.11, -0.10, 0.15), (0.11, -0.04, 0.05), 'ThighL'),
    ('FootL', (0.11, -0.04, 0.05), (0.11, -0.18, 0.0), 'ShinL'),
    ('Tail1', (0.01, 0.02, 0.24), (0.08, 0.14, 0.18), 'Hips'),
    ('Tail2', (0.08, 0.14, 0.18), (0.20, 0.22, 0.12), 'Tail1'),
    ('Tail3', (0.20, 0.22, 0.12), (0.36, 0.20, 0.14), 'Tail2'),
])
# 팔은 쉬는 자세(T)에서 몸 옆으로 내리고(왼팔 +Y 회전), 팔꿈치를 앞으로 굽힌다(Z)
KOBOLD_STAND = side({
    'UpperArmL': {'r': r('y', 68)}, 'ForeArmL': {'r': r('z', -24)},
    'ThighL': {'r': r('x', -12)}, 'ShinL': {'r': r('x', 20)}, 'FootL': {'r': r('x', -8)},
    'Spine': {'r': r('x', 8)}, 'Root': {'l': (0, 0, -0.012)},
})
KOBOLD = {
    'bones': KOBOLD_BONES,
    'base': KOBOLD_STAND,
    'clips': {
        'Idle': (2.0, True, [
            (0.0, {}),
            (1.0, {'Chest': {'r': r('x', -3)}, 'Head': {'r': r('z', 6)}, 'Tail2': {'r': r('z', 8)},
                   'Tail3': {'r': r('z', 8)}}),
        ]),
        'Run': (0.6, True, [
            (0.0, {'ThighL': {'r': r('x', -38)}, 'ShinL': {'r': r('x', 10)}, 'ThighR': {'r': r('x', 28)},
                   'ShinR': {'r': r('x', 40)}, 'UpperArmL': {'r': r('x', 25)}, 'UpperArmR': {'r': r('x', -25)},
                   'Spine': {'r': r('x', 12)}, 'Tail2': {'r': r('z', -6)}}),
            (0.15, {'Root': {'l': (0, 0, 0.04)}, 'Spine': {'r': r('x', 12)}}),
            (0.3, {'ThighR': {'r': r('x', -38)}, 'ShinR': {'r': r('x', 10)}, 'ThighL': {'r': r('x', 28)},
                   'ShinL': {'r': r('x', 40)}, 'UpperArmR': {'r': r('x', 25)}, 'UpperArmL': {'r': r('x', -25)},
                   'Spine': {'r': r('x', 12)}, 'Tail2': {'r': r('z', 6)}}),
            (0.45, {'Root': {'l': (0, 0, 0.04)}, 'Spine': {'r': r('x', 12)}}),
        ]),
        'Attack': (1.5, False, [
            (0.0, {}),
            (0.8, {}),
            # 오른팔(-X 로 뻗은 뼈)은 대기 자세의 Y -68 위에 얹는다. **앞뒤로 휘두르는 건 Z 축이다** —
            # 옆으로 뻗은 팔을 X 축으로 돌리면 제자리에서 비틀리기만 한다 (처음에 그렇게 짜서 칼이 안 나갔다)
            (0.95, {'UpperArmR': {'r': r('y', 40, 'z', -38)}, 'ForeArmR': {'r': r('z', 50)},
                    'Chest': {'r': r('z', -20)}, 'Spine': {'r': r('x', -4)},
                    'ThighR': {'r': r('x', 10)}}),
            (1.08, {'UpperArmR': {'r': r('y', 64, 'z', 82)}, 'ForeArmR': {'r': r('z', -22)},
                    'Chest': {'r': r('z', 26)}, 'Spine': {'r': r('x', 14)},
                    'ThighL': {'r': r('x', -30)}, 'ShinL': {'r': r('x', 10)}, 'ThighR': {'r': r('x', 16)},
                    'Root': {'l': (0, -0.1, -0.02)}}),
            (1.2, {'UpperArmR': {'r': r('y', 60, 'z', 76)}, 'ForeArmR': {'r': r('z', -18)},
                   'Chest': {'r': r('z', 22)}, 'Spine': {'r': r('x', 12)},
                   'ThighL': {'r': r('x', -26)}, 'Root': {'l': (0, -0.1, -0.02)}}),
            (1.45, {}),
            (1.5, {}),
        ]),
        'Death': (1.2, False, [
            (0.0, {}),
            (0.3, {'Spine': {'r': r('x', -14)}, 'Head': {'r': r('x', -20)}, 'Root': {'l': (0, 0.03, 0)}}),
            (0.9, side({'Root': {'r': r('x', -80)}, 'UpperArmL': {'r': r('y', -40)}, 'Head': {'r': r('x', -10)},
                        'ThighL': {'r': r('x', -20)}})),
            (1.2, side({'Root': {'r': r('x', -86)}, 'UpperArmL': {'r': r('y', -50)}, 'Head': {'r': r('x', -12)},
                        'ThighL': {'r': r('x', -24)}})),
        ]),
    },
}

MOBS = {'slime': SLIME, 'hare': HARE, 'mushroom': MUSHROOM, 'mantis': MANTIS,
        'scorpion': SCORPION, 'kobold': KOBOLD}


def load_mesh(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=path)
    mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
    # 가져온 변환을 메시에 굽고, 발바닥을 z = 0 · 가로 가운데를 0 으로 옮긴다
    mesh.data.transform(mesh.matrix_world)
    mesh.matrix_world = Matrix.Identity(4)
    for o in list(bpy.context.scene.objects):
        if o is not mesh:
            bpy.data.objects.remove(o)
    vs = [v.co for v in mesh.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    mesh.data.transform(Matrix.Translation(-Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))))
    for img in bpy.data.images:
        w, h = img.size
        if max(w, h) > TEX_MAX:
            img.scale(TEX_MAX, TEX_MAX)
    return mesh


def build_armature(bones):
    data = bpy.data.armatures.new('Armature')
    arm = bpy.data.objects.new('Armature', data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    root = data.edit_bones.new('Root')
    root.head, root.tail = (0, 0, 0), (0, 0, 0.12)
    for name, head, tail, _ in bones:
        eb = data.edit_bones.new(name)
        eb.head, eb.tail, eb.roll = head, tail, 0
    for name, _, _, parent in bones:
        data.edit_bones[name].parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def skin(mesh, arm, bones):
    """정점마다 가까운 뼈 셋 — 1/거리⁵ 로 나눈다"""
    segs = [(name, Vector(h), Vector(t)) for name, h, t, _ in bones]
    groups = {name: mesh.vertex_groups.new(name=name) for name, _, _ in segs}
    for v in mesh.data.vertices:
        ds = sorted((seg_dist(v.co, a, b), name) for name, a, b in segs)[:3]
        ws = [(1.0 / max(d, 0.004) ** 5, name) for d, name in ds]
        total = sum(w for w, _ in ws)
        for w, name in ws:
            if w / total > 0.02:
                groups[name].add([v.index], w / total, 'REPLACE')
    mesh.parent = arm
    mod = mesh.modifiers.new('Armature', 'ARMATURE')
    mod.object = arm


def set_pose(arm, pose, frame):
    for pb in arm.pose.bones:
        spec = pose.get(pb.name, {})
        rest = pb.bone.matrix_local.to_quaternion()
        q = Quaternion()
        for axis, deg in spec.get('r', []):
            q = Quaternion(AXES[axis], math.radians(deg)) @ q
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        pb.location = rest.inverted() @ Vector(spec.get('l', (0, 0, 0)))
        pb.scale = spec.get('s', (1, 1, 1))
        for path in ('rotation_quaternion', 'location', 'scale'):
            pb.keyframe_insert(path, frame=frame)


def make_clips(arm, mob):
    base = mob.get('base', {})
    arm.animation_data_create()
    for name, (length, loop, keys) in mob['clips'].items():
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        arm.animation_data.action = action
        keys = list(keys)
        if loop:
            keys.append((length, keys[0][1]))
        for t, pose in keys:
            set_pose(arm, merge(base, pose), t * FPS)
    arm.animation_data.action = None


def export(path):
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_force_sampling=True,
        export_anim_slide_to_zero=True,
        export_def_bones=False,
        export_image_format='JPEG',
        export_jpeg_quality=88,
        export_morph=False,
        export_reset_pose_bones=True,
    )


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    for name in args or list(MOBS):
        mob = MOBS[name]
        mesh = load_mesh(SRC.format(name))
        arm = build_armature(mob['bones'])
        skin(mesh, arm, mob['bones'])
        make_clips(arm, mob)
        # 쉬는 자세로 돌려놓고 낸다 — 고도는 클립이 없을 때 이 자세를 본다
        for pb in arm.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)
        out = OUT.format(name)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        export(out)
        print(f'MOB {name}: 뼈 {len(mob["bones"]) + 1} · 클립 {", ".join(mob["clips"])} → {out} '
              f'{os.path.getsize(out) / 1e6:.2f}MB')


main()
