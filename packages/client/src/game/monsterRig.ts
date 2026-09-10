import * as THREE from 'three';
import type { MonsterKind } from '@mmo/shared';
import { mergeAll } from '../scene/geometry';
import { HitFlash } from './hitFlash';

/**
 * 네발 몬스터.
 *
 * 캐릭터와 같은 방식이다 — 본에 리지드 스키닝한 SkinnedMesh 하나로 만들어
 * 몬스터 한 마리당 드로우콜 1개를 유지한다.
 *
 * 다리는 **위·아래 두 마디**다. 예전에는 한 마디짜리 막대가 어깨에서 통째로
 * 흔들려서, 걷는 게 아니라 시계추가 매달린 것처럼 보였다. 무릎(뒷다리는 비절)이
 * 접혀야 발이 땅에서 떨어졌다 붙는 것으로 읽힌다.
 */

interface BoneDef {
  name: string;
  parent: string | null;
  pos: [number, number, number];
}

/** 어깨 높이 0.75m, 몸통 길이 1.3m 기준 (kind.scale 로 배율) */
const HIP_Y = 0.5;
const KNEE_Y = 0.28;
const PAW_Y = 0.08;

/** [본 접미사, x, z, 앞다리인가] */
const LEGS: [string, number, number, boolean][] = [
  ['FL', 0.19, 0.32, true],
  ['FR', -0.19, 0.32, true],
  ['BL', 0.2, -0.34, false],
  ['BR', -0.2, -0.34, false],
];

const BONE_DEFS: BoneDef[] = [
  { name: 'body', parent: null, pos: [0, 0.62, 0] },
  { name: 'neck', parent: 'body', pos: [0, 0.1, 0.42] },
  { name: 'head', parent: 'neck', pos: [0, 0.05, 0.22] },
  { name: 'tail', parent: 'body', pos: [0, 0.04, -0.5] },
  { name: 'tailTip', parent: 'tail', pos: [0, -0.02, -0.22] },
  ...LEGS.flatMap(([id, x, z]): BoneDef[] => [
    { name: 'leg' + id, parent: 'body', pos: [x, HIP_Y - 0.62, z] },
    { name: 'shin' + id, parent: 'leg' + id, pos: [0, -(HIP_Y - KNEE_Y), 0] },
    { name: 'paw' + id, parent: 'shin' + id, pos: [0, -(KNEE_Y - PAW_Y), 0] },
  ]),
];

/**
 * 네발 걸음.
 *
 * 대각선끼리 짝을 이룬다(속보). 위상을 이동 **거리**에 묶어야 발이 미끄러지지 않는다.
 */
const GAIT = {
  radPerMeter: 2.6,
  hipSwing: 0.62,
  /** 발이 뜨는 구간에서만 접힌다 */
  kneeBend: 0.85,
  /** 서 있을 때도 이만큼은 굽어 있다 — 곧게 편 다리는 식탁 다리처럼 보인다 */
  kneeRest: 0.22,
  bob: 0.035,
  /** 앞뒤로 까딱이는 정도 */
  pitch: 0.05,
  /** 좌우로 기우는 정도 */
  roll: 0.045,
} as const;

const IDLE = {
  breathRate: 1.25,
  breathDepth: 0.009,
  lookRate: 0.27,
  lookDepth: 0.3,
  tailRate: 2.1,
  tailDepth: 0.22,
} as const;

interface Part {
  geo: THREE.BufferGeometry;
  bone: string;
  color: string;
  rough: number;
}

export interface MonsterRig {
  group: THREE.Group;
  headHeight: number;
  /** 한 대 맞았다 — 잠깐 하얗게 번쩍인다 */
  flash(): void;
  /** state: idle | chase | attack | cast(범위 공격 예고) | dead */
  update(dt: number, state: string, speed: number): void;
  dispose(): void;
}

/** x,z 자리에 세로로 선 캡슐 (다리 한 마디) */
function segment(
  x: number,
  z: number,
  yTop: number,
  yBottom: number,
  radius: number
): THREE.BufferGeometry {
  const span = yTop - yBottom;
  const geo = new THREE.CapsuleGeometry(radius, Math.max(span - radius * 2, 0.01), 4, 10);
  geo.translate(x, (yTop + yBottom) / 2, z);
  return geo;
}

function buildParts(kind: MonsterKind): Part[] {
  const parts: Part[] = [];
  const add = (geo: THREE.BufferGeometry, bone: string, color: string, rough = 0.85) =>
    parts.push({ geo, bone, color, rough });

  // --- 몸통: 앞이 굵고 뒤가 가늘다 ---
  const torso = new THREE.CapsuleGeometry(0.26, 0.66, 5, 14);
  torso.rotateX(Math.PI / 2);
  torso.scale(1, 0.86, 1);
  torso.translate(0, 0.62, 0);
  add(torso, 'body', kind.bodyColor);

  // 어깨·엉덩이 덩어리 — 원통 하나만 있으면 통나무처럼 보인다
  for (const [z, r] of [
    [0.3, 0.25],
    [-0.3, 0.23],
  ] as const) {
    const mass = new THREE.SphereGeometry(r, 12, 10);
    mass.scale(1.02, 0.88, 1);
    mass.translate(0, 0.62, z);
    add(mass, 'body', kind.bodyColor);
  }

  // 등줄기 — 색을 달리해 실루엣에 방향감을 준다
  const ridge = new THREE.BoxGeometry(0.1, 0.07, 0.8);
  ridge.translate(0, 0.86, -0.02);
  add(ridge, 'body', kind.accentColor);

  const neck = new THREE.CapsuleGeometry(0.17, 0.18, 4, 10);
  neck.rotateX(Math.PI / 2.6);
  neck.translate(0, 0.74, 0.44);
  add(neck, 'neck', kind.bodyColor);

  // --- 머리 ---
  const skull = new THREE.CapsuleGeometry(0.15, 0.16, 4, 10);
  skull.rotateX(Math.PI / 2);
  skull.translate(0, 0.8, 0.68);
  add(skull, 'head', kind.bodyColor);

  const snout = new THREE.BoxGeometry(0.14, 0.12, 0.22);
  snout.translate(0, 0.76, 0.86);
  add(snout, 'head', kind.accentColor);

  // 코와 아래턱 — 상자 하나로 끝나면 옆에서 볼 때 얼굴이 없다
  const nose = new THREE.SphereGeometry(0.045, 8, 6);
  nose.scale(1, 0.8, 0.7);
  nose.translate(0, 0.79, 0.96);
  add(nose, 'head', '#2b2420', 0.4);

  const jaw = new THREE.BoxGeometry(0.11, 0.05, 0.18);
  jaw.translate(0, 0.71, 0.85);
  add(jaw, 'head', kind.bodyColor);

  for (const side of [1, -1]) {
    const ear = new THREE.ConeGeometry(0.06, 0.16, 5);
    ear.translate(side * 0.09, 0.95, 0.64);
    add(ear, 'head', kind.accentColor);

    // 눈 — 작지만 있으면 생물로 읽힌다
    const eye = new THREE.SphereGeometry(0.028, 7, 6);
    eye.translate(side * 0.085, 0.83, 0.79);
    add(eye, 'head', '#e8d24a', 0.25);

    const pupil = new THREE.SphereGeometry(0.014, 6, 5);
    pupil.scale(0.7, 1, 0.7);
    pupil.translate(side * 0.085, 0.83, 0.806);
    add(pupil, 'head', '#141210', 0.2);
  }

  const tail = new THREE.CapsuleGeometry(0.06, 0.26, 4, 8);
  tail.rotateX(Math.PI / 2.2);
  tail.translate(0, 0.68, -0.58);
  add(tail, 'tail', kind.accentColor);

  const tip = new THREE.CapsuleGeometry(0.042, 0.2, 4, 8);
  tip.rotateX(Math.PI / 2.4);
  tip.translate(0, 0.62, -0.82);
  add(tip, 'tailTip', kind.accentColor);

  // --- 다리: 위·아래 두 마디 + 발 ---
  for (const [id, x, z] of LEGS) {
    add(segment(x, z, HIP_Y, KNEE_Y, 0.075), 'leg' + id, kind.bodyColor);
    add(segment(x, z, KNEE_Y, PAW_Y, 0.055), 'shin' + id, kind.bodyColor);

    const paw = new THREE.BoxGeometry(0.13, 0.075, 0.17);
    paw.translate(x, PAW_Y - 0.03, z + 0.02);
    add(paw, 'paw' + id, kind.accentColor);
  }

  return parts;
}

export function createMonsterRig(kind: MonsterKind): MonsterRig {
  const bones: THREE.Bone[] = [];
  const byName = new Map<string, THREE.Bone>();
  for (const def of BONE_DEFS) {
    const bone = new THREE.Bone();
    bone.name = def.name;
    bone.position.set(def.pos[0], def.pos[1], def.pos[2]);
    byName.set(def.name, bone);
    bones.push(bone);
    if (def.parent) byName.get(def.parent)!.add(bone);
  }
  const root = byName.get('body')!;

  const boneIndex = new Map(bones.map((b, i) => [b.name, i]));
  const parts = buildParts(kind);
  const color = new THREE.Color();

  for (const part of parts) {
    const count = part.geo.attributes.position.count;
    const idx = boneIndex.get(part.bone);
    if (idx === undefined) throw new Error('알 수 없는 본: ' + part.bone);
    color.set(part.color);

    const colors = new Float32Array(count * 3);
    const surface = new Float32Array(count * 2);
    const skinIndex = new Uint16Array(count * 4);
    const skinWeight = new Float32Array(count * 4);
    for (let i = 0; i < count; i++) {
      colors[i * 3] = color.r;
      colors[i * 3 + 1] = color.g;
      colors[i * 3 + 2] = color.b;
      surface[i * 2] = part.rough;
      surface[i * 2 + 1] = 0;
      skinIndex[i * 4] = idx;
      skinWeight[i * 4] = 1;
    }
    part.geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    part.geo.setAttribute('surface', new THREE.BufferAttribute(surface, 2));
    part.geo.setAttribute('skinIndex', new THREE.BufferAttribute(skinIndex, 4));
    part.geo.setAttribute('skinWeight', new THREE.BufferAttribute(skinWeight, 4));
  }

  const geometry = mergeAll(parts.map((p) => p.geo));
  const material = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, metalness: 0 });
  material.onBeforeCompile = (shader) => {
    shader.vertexShader = shader.vertexShader
      .replace(
        '#include <common>',
        `#include <common>
        attribute vec2 surface;
        varying vec2 vSurface;`
      )
      .replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
        vSurface = surface;`
      );
    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        varying vec2 vSurface;`
      )
      .replace('#include <roughnessmap_fragment>', 'float roughnessFactor = vSurface.x;');
  };
  material.customProgramCacheKey = () => 'monster-surface';

  const mesh = new THREE.SkinnedMesh(geometry, material);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  mesh.add(root);
  const skeleton = new THREE.Skeleton(bones);
  mesh.bind(skeleton);

  const group = new THREE.Group();
  group.scale.setScalar(kind.scale);
  group.add(mesh);

  const b = (name: string) => byName.get(name)!;
  const restBodyY = root.position.y;
  const restBodyZ = root.position.z;
  let phase = 0;
  let idlePhase = Math.random() * Math.PI * 2;
  let moveBlend = 0;
  let attackAnim = 0;
  let deadFade = 0;
  const hitFlash = new HitFlash(group);

  return {
    group,
    headHeight: 1.25 * kind.scale,

    flash(): void {
      hitFlash.flash();
    },

    update(dt: number, state: string, speed: number): void {
      hitFlash.update(dt);
      idlePhase += dt;

      if (state === 'dead') {
        // 옆으로 쓰러진다. 넘어가면서 한 번 출렁였다가 자리를 잡는다 —
        // 딱 90도에서 멈추면 인형을 눕혀 놓은 것처럼 보인다.
        deadFade = Math.min(1, deadFade + dt * 3);
        const settle = Math.sin(deadFade * Math.PI) * 0.12;
        group.rotation.z = deadFade * Math.PI * 0.5 + settle;
        root.position.y = restBodyY - deadFade * 0.25;
        root.position.z = restBodyZ;
        root.rotation.set(0, 0, 0);
        // 다리가 힘없이 펴진다
        for (const [id] of LEGS) {
          b('leg' + id).rotation.x = -0.25 * deadFade;
          b('shin' + id).rotation.x = GAIT.kneeRest * (1 - deadFade);
          b('paw' + id).rotation.x = 0;
        }
        b('neck').rotation.x = -0.15 - deadFade * 0.4;
        b('head').rotation.set(0, 0, 0);
        return;
      }
      deadFade = 0;
      group.rotation.z = 0;

      // 걸음 <-> 정지를 섞는다. 예전에는 speed 를 바로 곱해서 멈추는 순간
      // 다리가 그 자세 그대로 얼어붙었다.
      const k = 1 - Math.exp(-10 * dt);
      moveBlend += (Math.min(1, speed / 3) - moveBlend) * k;
      const m = moveBlend;
      const still = 1 - m;

      phase += speed * dt * GAIT.radPerMeter;
      const c = Math.cos(phase);
      const s = Math.sin(phase);

      // --- 다리: 대각선끼리 짝 (속보) ---
      for (const [id, , , front] of LEGS) {
        const same = id === 'FL' || id === 'BR';
        const ph = same ? phase : phase + Math.PI;
        const sw = Math.sin(ph);
        // 발이 떠 있는 구간에서만 접는다. 디딤발이 접히면 걸음이 무너져 보인다.
        const lift = Math.max(0, -Math.cos(ph));

        const hip = sw * GAIT.hipSwing * m;
        // 앞다리 무릎은 뒤로, 뒷다리 비절은 앞으로 접힌다 (개·늑대의 뒷다리)
        const bend = (front ? -1 : 1) * (lift * GAIT.kneeBend * m + GAIT.kneeRest);

        b('leg' + id).rotation.x = hip;
        b('shin' + id).rotation.x = bend;
        // 발바닥은 땅과 평행을 유지한다 — 없으면 발끝으로 찍고 다닌다
        b('paw' + id).rotation.x = -hip - bend * 0.75;
      }

      // --- 몸통 ---
      // 위아래로 뛰고, 앞뒤로 까딱이고, 좌우로 기운다. 셋 다 있어야 무게가 느껴진다.
      const breath = Math.sin(idlePhase * IDLE.breathRate);
      root.position.y =
        restBodyY + Math.abs(c) * GAIT.bob * m + breath * IDLE.breathDepth * still;
      root.rotation.x = Math.sin(phase * 2) * GAIT.pitch * m;
      root.rotation.z = s * GAIT.roll * m;

      // 공격하면 앞으로 몸을 던지며 물어뜯는다.
      // 범위 공격 예고(cast) 중에도 같은 자세를 쓰되 더 천천히 힘을 준다 —
      // 가만히 서 있으면 바닥의 원이 왜 생겼는지 몸에서 읽히지 않는다.
      const lunging = state === 'attack' || state === 'cast';
      attackAnim = lunging
        ? Math.min(1, attackAnim + dt * (state === 'cast' ? 2.2 : 7))
        : Math.max(0, attackAnim - dt * 4.5);
      root.position.z = restBodyZ + attackAnim * 0.16;
      root.rotation.x += attackAnim * 0.18;

      // --- 목·머리·꼬리 ---
      // 머리는 몸통 까딱임을 절반쯤 상쇄해 시선이 덜 흔들린다
      b('neck').rotation.x =
        -0.15 - root.rotation.x * 0.5 + breath * 0.02 * still - attackAnim * 0.5;
      b('head').rotation.x = attackAnim * 0.45 - root.rotation.x * 0.3;
      // 쉬는 동안 주위를 둘러본다
      b('head').rotation.y = Math.sin(idlePhase * IDLE.lookRate) * IDLE.lookDepth * still;

      const wag = Math.sin(idlePhase * IDLE.tailRate + phase);
      b('tail').rotation.x = -0.4 + wag * IDLE.tailDepth * 0.6;
      b('tail').rotation.y = wag * IDLE.tailDepth;
      b('tailTip').rotation.y = Math.sin(idlePhase * IDLE.tailRate - 0.7) * IDLE.tailDepth * 1.4;
    },

    dispose(): void {
      geometry.dispose();
      material.dispose();
      skeleton.dispose();
    },
  };
}
