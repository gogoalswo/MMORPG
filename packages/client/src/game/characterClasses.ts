import * as THREE from 'three';
import {
  ARM_X, HAND_Y, HEAD, SHOULDER_Y, Y,
  limb, SURFACE,
  type AddPart, type CharacterColors, type ClassProfile,
} from './characterRig';

/**
 * 직업 정의.
 *
 * 쿼터뷰에서 캐릭터는 화면상 100px 남짓이다. 색만 바꾸면 직업이 구분되지 않는다.
 * 그래서 각 직업은 **실루엣**이 다르게 만든다 —
 * 기사는 투구와 넓은 어깨, 마법사는 로브와 긴 지팡이, 궁수는 후드와 등에 멘 화살통,
 * 격투가는 붉은 머리띠와 붕대 감은 빈손.
 *
 * 장비는 손/가슴 본에 붙으므로 애니메이션을 그대로 따라간다.
 * 전부 같은 SkinnedMesh 에 병합되므로 장비를 아무리 붙여도 드로우콜은 1개다.
 */

export type ClassId = 'knight' | 'mage' | 'archer' | 'fighter';

/** 오른손 x 좌표 (side = -1 쪽) */
const RIGHT_X = -ARM_X;
const LEFT_X = ARM_X;

// ---------------------------------------------------------------- 기사

const KNIGHT_COLORS: CharacterColors = {
  skin: '#d9b394',
  hair: '#4a3a2c',
  tunic: '#9aa0ac', // 판금
  tunicDark: '#767d8a',
  pants: '#4b4f57',
  boots: '#3a3e46',
  accent: '#8c3a3a', // 문장 붉은색
};

function equipKnight(add: AddPart, c: CharacterColors): void {
  const headY = Y.chin + HEAD / 2;

  // --- 투구: 머리를 완전히 덮고 얼굴 가리개가 앞으로 나온다 ---
  const dome = new THREE.SphereGeometry(HEAD / 2 + 0.022, 12, 8, 0, Math.PI * 2, 0, Math.PI * 0.62);
  dome.scale(0.96, 1.05, 0.94);
  dome.translate(0, headY - 0.005, 0);
  add(dome, 'head', c.tunic, SURFACE.metal);

  const faceGuard = new THREE.BoxGeometry(0.17, 0.135, 0.075);
  faceGuard.translate(0, headY - 0.045, 0.075);
  add(faceGuard, 'head', c.tunicDark, SURFACE.metal);

  // 시야 틈
  const slit = new THREE.BoxGeometry(0.13, 0.022, 0.03);
  slit.translate(0, headY - 0.02, 0.115);
  add(slit, 'head', '#1a1c20');

  // 볏 — 위에서 내려다보는 시점이라 실루엣 구분에 크게 기여한다
  const crest = new THREE.BoxGeometry(0.028, 0.075, 0.19);
  crest.translate(0, headY + 0.105, -0.01);
  add(crest, 'head', c.accent, SURFACE.cloth);

  // --- 흉갑 위에 덧대는 가슴판 + 문장 ---
  const plate = new THREE.CylinderGeometry(0.175, 0.145, 0.3, 10);
  plate.scale(1.2, 1, 0.76);
  plate.translate(0, SHOULDER_Y - 0.19, 0);
  add(plate, 'chest', c.tunic, SURFACE.metal);

  const tabard = new THREE.BoxGeometry(0.16, 0.42, 0.02);
  tabard.translate(0, Y.waist - 0.02, 0.135);
  add(tabard, 'chest', c.accent, SURFACE.cloth);

  // --- 허리 갑주 (탯싯) ---
  const tasset = new THREE.CylinderGeometry(0.15, 0.21, 0.24, 10, 1, true);
  tasset.scale(1.1, 1, 0.85);
  tasset.translate(0, Y.crotch + 0.02, 0);
  add(tasset, 'hips', c.tunicDark, SURFACE.metal);

  for (const side of [1, -1]) {
    const L = side > 0 ? 'L' : 'R';
    // 큰 어깨 갑주 — 기사 실루엣의 핵심
    const pauldron = new THREE.SphereGeometry(0.105, 10, 8, 0, Math.PI * 2, 0, Math.PI * 0.62);
    pauldron.scale(1.05, 1, 1.05);
    pauldron.translate(side * 0.225, SHOULDER_Y + 0.03, 0);
    add(pauldron, 'upperArm' + L, c.tunic, SURFACE.metal);

    // 팔뚝 보호대
    add(limb(side * ARM_X, Y.waist - 0.02, Y.crotch + 0.02, 0.056), 'foreArm' + L, c.tunicDark, SURFACE.metal);
    // 정강이 보호대
    add(limb(side * 0.1, Y.knee - 0.02, Y.ankle + 0.02, 0.07), 'shin' + L, c.tunic, SURFACE.metal);
  }

  // --- 오른손 장검 ---
  const grip = new THREE.CylinderGeometry(0.019, 0.019, 0.13, 6);
  grip.translate(RIGHT_X, HAND_Y, 0);
  add(grip, 'handR', '#4a3a2c', SURFACE.leather);

  const pommel = new THREE.SphereGeometry(0.028, 8, 6);
  pommel.translate(RIGHT_X, HAND_Y + 0.075, 0);
  add(pommel, 'handR', c.accent, SURFACE.gold);

  const guard = new THREE.BoxGeometry(0.19, 0.032, 0.045);
  guard.translate(RIGHT_X, HAND_Y - 0.075, 0);
  add(guard, 'handR', c.tunicDark, SURFACE.metal);

  const blade = new THREE.BoxGeometry(0.062, 0.68, 0.022);
  blade.translate(RIGHT_X, HAND_Y - 0.42, 0);
  add(blade, 'handR', '#c9ced8', SURFACE.metal);

  // --- 왼팔 방패 ---
  const shield = new THREE.CylinderGeometry(0.23, 0.23, 0.035, 6);
  shield.scale(1, 1, 1.15);
  shield.rotateX(Math.PI / 2); // 평면이 옆을 보도록
  shield.rotateZ(Math.PI / 6);
  shield.translate(LEFT_X + 0.075, Y.waist - 0.11, 0.02);
  add(shield, 'foreArmL', c.tunicDark, SURFACE.metal);

  const boss = new THREE.SphereGeometry(0.055, 8, 6);
  boss.scale(1, 1, 0.6);
  boss.translate(LEFT_X + 0.11, Y.waist - 0.11, 0.02);
  add(boss, 'foreArmL', c.accent, SURFACE.gold);
}

// ---------------------------------------------------------------- 마법사

const MAGE_COLORS: CharacterColors = {
  skin: '#e0c0a2',
  hair: '#6b5a48',
  tunic: '#454273', // 로브 본체
  tunicDark: '#35335c',
  pants: '#35335c',
  boots: '#2a2846',
  accent: '#c8a95a', // 금장식
};

function equipMage(add: AddPart, c: CharacterColors): void {
  const headY = Y.chin + HEAD / 2;

  // --- 뾰족한 후드: 뒤로 넘어간 원뿔 ---
  const hood = new THREE.ConeGeometry(HEAD / 2 + 0.045, 0.42, 8);
  hood.rotateX(0.42); // 뒤로 젖힌다
  hood.translate(0, headY + 0.12, -0.075);
  add(hood, 'head', c.tunic);

  // 얼굴을 덮는 그늘 — 후드 안쪽이 어두워야 후드로 읽힌다
  const shade = new THREE.SphereGeometry(HEAD / 2 + 0.012, 10, 8, 0, Math.PI * 2, 0, Math.PI * 0.55);
  shade.scale(0.98, 0.85, 0.98);
  shade.translate(0, headY + 0.01, -0.012);
  add(shade, 'head', c.tunicDark);

  // 목을 감싸는 깃
  const collar = new THREE.CylinderGeometry(0.115, 0.16, 0.14, 10);
  collar.scale(1.15, 1, 0.85);
  collar.translate(0, Y.chin - 0.09, 0);
  add(collar, 'chest', c.tunicDark);

  // --- 발목까지 내려오는 로브 ---
  const robe = new THREE.CylinderGeometry(0.175, 0.36, Y.waist - 0.12, 12, 1, true);
  robe.scale(1.05, 1, 0.92);
  robe.translate(0, (Y.waist - 0.06) / 2 + 0.02, 0);
  add(robe, 'hips', c.tunic);

  // 로브 앞자락 금색 띠
  const trim = new THREE.BoxGeometry(0.075, Y.waist - 0.2, 0.02);
  trim.translate(0, (Y.waist - 0.1) / 2, 0.235);
  add(trim, 'hips', c.accent, SURFACE.gold);

  const sash = new THREE.CylinderGeometry(0.145, 0.145, 0.06, 10);
  sash.scale(1.18, 1, 0.8);
  sash.translate(0, Y.waist - 0.15, 0);
  add(sash, 'hips', c.accent, SURFACE.gold);

  // --- 넓게 퍼지는 소매 ---
  for (const side of [1, -1]) {
    const L = side > 0 ? 'L' : 'R';
    const sleeve = new THREE.CylinderGeometry(0.075, 0.15, 0.3, 8, 1, true);
    sleeve.translate(side * ARM_X, Y.crotch + 0.08, 0);
    add(sleeve, 'foreArm' + L, c.tunicDark);
  }

  // --- 오른손 지팡이 ---
  const shaft = new THREE.CylinderGeometry(0.032, 0.038, 1.55, 6);
  shaft.translate(RIGHT_X - 0.04, HAND_Y + 0.42, 0.03);
  add(shaft, 'handR', '#6b5540', SURFACE.leather);

  const ferrule = new THREE.CylinderGeometry(0.052, 0.052, 0.07, 6);
  ferrule.translate(RIGHT_X - 0.04, HAND_Y + 1.09, 0.03);
  add(ferrule, 'handR', c.accent, SURFACE.gold);

  // 끝의 보석 — 어두운 로브 위에서 눈에 띄는 밝은 점
  const orb = new THREE.IcosahedronGeometry(0.105, 0);
  orb.translate(RIGHT_X - 0.04, HAND_Y + 1.2, 0.03);
  add(orb, 'handR', '#7fd8ff', SURFACE.gem);
}

// ---------------------------------------------------------------- 궁수

const ARCHER_COLORS: CharacterColors = {
  skin: '#d9b394',
  hair: '#3a2d24',
  tunic: '#4d5c3a', // 가죽 녹색
  tunicDark: '#3a462b',
  pants: '#5a4a35',
  boots: '#3d3125',
  accent: '#8a6a3f', // 가죽 갈색
};

function equipArcher(add: AddPart, c: CharacterColors): void {
  const headY = Y.chin + HEAD / 2;

  // --- 짧은 후드 (마법사보다 낮고 둥글다) ---
  const hood = new THREE.SphereGeometry(HEAD / 2 + 0.032, 10, 8, 0, Math.PI * 2, 0, Math.PI * 0.66);
  hood.scale(1, 1.02, 1.06);
  hood.translate(0, headY - 0.012, -0.012);
  add(hood, 'head', c.tunic);

  const peak = new THREE.ConeGeometry(0.075, 0.16, 6);
  peak.rotateX(1.15); // 뒤로 처진 꼬리
  peak.translate(0, headY + 0.055, -0.13);
  add(peak, 'head', c.tunicDark);

  // --- 한쪽 어깨만 덮는 짧은 망토 ---
  const cape = new THREE.CylinderGeometry(0.185, 0.245, 0.34, 10, 1, true);
  cape.scale(1.1, 1, 0.9);
  cape.translate(0, SHOULDER_Y - 0.15, -0.03);
  add(cape, 'chest', c.tunicDark);

  // --- 등에 멘 화살통 ---
  const quiver = new THREE.CylinderGeometry(0.062, 0.055, 0.4, 8);
  quiver.rotateX(-0.3);
  quiver.rotateZ(0.32);
  quiver.translate(0.13, Y.chest - 0.12, -0.16);
  add(quiver, 'chest', c.accent, SURFACE.leather);

  for (let i = 0; i < 3; i++) {
    const shaft = new THREE.CylinderGeometry(0.008, 0.008, 0.3, 4);
    shaft.rotateX(-0.3);
    shaft.rotateZ(0.32);
    shaft.translate(0.115 + i * 0.022, Y.chest + 0.16, -0.2 - i * 0.012);
    add(shaft, 'chest', '#8a7a5c');

    const fletch = new THREE.BoxGeometry(0.005, 0.07, 0.05);
    fletch.rotateX(-0.3);
    fletch.rotateZ(0.32);
    fletch.translate(0.128 + i * 0.022, Y.chest + 0.25, -0.23 - i * 0.012);
    add(fletch, 'chest', '#c4c9b8');
  }

  // --- 가죽 흉갑과 팔목 보호대 ---
  const harness = new THREE.BoxGeometry(0.075, 0.4, 0.02);
  harness.rotateZ(-0.35);
  harness.translate(0.02, Y.chest - 0.09, 0.14);
  add(harness, 'chest', c.accent, SURFACE.leather);

  for (const side of [1, -1]) {
    const L = side > 0 ? 'L' : 'R';
    add(limb(side * ARM_X, Y.crotch + 0.19, Y.crotch + 0.02, 0.052), 'foreArm' + L, c.accent, SURFACE.leather);
  }

  // --- 왼손 활 ---
  // 토러스는 XY 평면에 그려지므로, 활 곡선이 앞뒤(Z)로 열리도록 YZ 평면으로 눕힌다
  const arc = Math.PI * 1.15;
  const bow = new THREE.TorusGeometry(0.38, 0.026, 5, 14, arc);
  bow.rotateZ(Math.PI / 2 - arc / 2); // 곡선을 +Y 축 기준으로 대칭
  bow.rotateY(Math.PI / 2);
  bow.translate(LEFT_X + 0.03, HAND_Y + 0.02, 0.05);
  add(bow, 'handL', '#6b5540', SURFACE.leather);

  // 시위
  const half = Math.sin(arc / 2) * 0.36;
  const string = new THREE.BoxGeometry(0.006, half * 2, 0.006);
  string.translate(LEFT_X + 0.03, HAND_Y + 0.02, 0.05 + Math.cos(arc / 2) * 0.36);
  add(string, 'handL', '#d8d2c0');
}

// ---------------------------------------------------------------- 격투가

const FIGHTER_COLORS: CharacterColors = {
  skin: '#d6a785',
  hair: '#2b2420',
  tunic: '#e6dfd2', // 흰 도복
  tunicDark: '#c4bba9',
  pants: '#dcd4c6',
  boots: '#4a3b30', // 얇은 천신
  accent: '#262b33', // 검은 띠
};

/** 머리띠 — 흰 도복 위에서 눈에 띄는 붉은색 */
const FIGHTER_RED = '#b8322e';
/** 손에 감은 붕대 */
const WRAP = '#efe9dc';

function equipFighter(add: AddPart, c: CharacterColors): void {
  const headY = Y.chin + HEAD / 2;

  // --- 머리띠: 이마를 두르고 뒤로 두 가닥이 늘어진다 ---
  // 무기도 투구도 없어서, 위에서 내려다볼 때 실루엣은 이것과 빈손이 만든다
  const band = new THREE.CylinderGeometry(HEAD / 2 + 0.014, HEAD / 2 + 0.014, 0.035, 14, 1, true);
  band.translate(0, headY + 0.035, 0);
  add(band, 'head', FIGHTER_RED, SURFACE.cloth);

  for (const side of [1, -1]) {
    const tail = new THREE.BoxGeometry(0.03, 0.17, 0.012);
    tail.rotateZ(side * 0.3);
    tail.translate(side * 0.035, headY - 0.04, -HEAD / 2 - 0.025);
    add(tail, 'head', FIGHTER_RED, SURFACE.cloth);
  }

  // --- 검은 띠와 앞으로 늘어진 매듭 ---
  const belt = new THREE.CylinderGeometry(0.16, 0.16, 0.055, 12, 1, true);
  belt.scale(1.1, 1, 0.85);
  belt.translate(0, Y.waist - 0.03, 0);
  add(belt, 'hips', c.accent, SURFACE.cloth);

  for (const side of [1, -1]) {
    const end = new THREE.BoxGeometry(0.045, 0.16, 0.015);
    end.rotateZ(side * 0.12);
    end.translate(0.03 + side * 0.03, Y.waist - 0.13, 0.14);
    add(end, 'hips', c.accent, SURFACE.cloth);
  }

  // --- 붕대 감은 팔목과 주먹 — 무기가 이것이다 ---
  for (const side of [1, -1]) {
    const L = side > 0 ? 'L' : 'R';
    add(limb(side * ARM_X, Y.crotch + 0.16, Y.crotch + 0.02, 0.05), 'foreArm' + L, WRAP, SURFACE.cloth);
    const fist = new THREE.SphereGeometry(0.06, 8, 6);
    fist.translate(side * ARM_X, HAND_Y, 0.01);
    add(fist, 'hand' + L, WRAP, SURFACE.cloth);
  }
}

// ----------------------------------------------------------------

export const CLASSES: Record<ClassId, ClassProfile> = {
  knight: {
    id: 'knight',
    label: '기사',
    colors: KNIGHT_COLORS,
    // VARCO 커스텀 워크플로우로 만든 기사. 이 파일이 없으면 아래 equipKnight 로
    // 떨어진다 — rigFactory 의 MODEL_RIGS 참고.
    model: 'varco_knight',
    attackClip: '1H_Melee_Attack_Slice_Diagonal',
    // 생성 화면 미리보기용. 월드에서는 서버가 내려준 장비로 덮인다.
    npcGear: { weapon: 0, offhand: 1, helmet: true },
    // 갑옷을 입어 몸통이 두껍다
    body: { headwear: 'helmet', bulk: 1.12 },
    weaponHand: 'R', // 장검
    // 손잡이 바로 아래(가드)부터 칼끝까지 — equipKnight 의 blade 와 같은 자리
    weaponReach: [
      [RIGHT_X, HAND_Y - 0.08, 0],
      [RIGHT_X, HAND_Y - 0.76, 0],
    ],
    equip: equipKnight,
  },
  mage: {
    id: 'mage',
    label: '마법사',
    colors: MAGE_COLORS,
    // VARCO 커스텀 워크플로우로 만든 마법사. 없으면 equipMage 로 떨어진다.
    model: 'varco_mage',
    attackClip: 'Spellcast_Shoot',
    npcGear: { weapon: 1, offhand: 0, helmet: true },
    // 로브가 하반신을 덮는다
    body: { headwear: 'hood', robe: true, bulk: 0.94 },
    weaponHand: 'R', // 지팡이
    // 휘두를 때 실제로 호를 그리는 건 손 위쪽 지팡이다
    weaponReach: [
      [RIGHT_X - 0.04, HAND_Y + 0.2, 0.03],
      [RIGHT_X - 0.04, HAND_Y + 1.2, 0.03],
    ],
    equip: equipMage,
  },
  archer: {
    id: 'archer',
    label: '궁수',
    colors: ARCHER_COLORS,
    // VARCO 커스텀 워크플로우로 만든 궁수. 없으면 equipArcher 로 떨어진다.
    model: 'varco_archer',
    attackClip: '1H_Ranged_Shoot',
    npcGear: { weapon: 1 },
    body: { headwear: 'hood', bulk: 0.98 },
    weaponHand: 'L', // 활
    // 활은 후려치는 자세라 활대 전체가 지나간다
    weaponReach: [
      [LEFT_X + 0.03, HAND_Y - 0.34, 0.05],
      [LEFT_X + 0.03, HAND_Y + 0.4, 0.05],
    ],
    equip: equipArcher,
  },
  fighter: {
    id: 'fighter',
    label: '격투가',
    colors: FIGHTER_COLORS,
    // VARCO 커스텀 워크플로우로 만든 격투가. 없으면 equipFighter 로 떨어진다.
    model: 'varco_fighter',
    body: { headwear: 'hair', bulk: 1.02 },
    weaponHand: 'R', // 오른 주먹
    // 손목에서 주먹 끝까지 — equipFighter 의 fist 와 같은 자리
    weaponReach: [
      [RIGHT_X, HAND_Y + 0.06, 0],
      [RIGHT_X, HAND_Y - 0.08, 0.02],
    ],
    equip: equipFighter,
  },
};

export const CLASS_ORDER: ClassId[] = ['knight', 'mage', 'archer', 'fighter'];
