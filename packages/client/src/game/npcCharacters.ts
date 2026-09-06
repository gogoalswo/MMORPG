import * as THREE from 'three';
import {
  ARM_X,
  HAND_Y,
  HEAD,
  SHOULDER_Y,
  SURFACE,
  Y,
  type AddPart,
  type CharacterColors,
  type ClassProfile,
} from './characterRig';

/**
 * NPC 외형.
 *
 * 예전에는 NPC 가 **플레이어 직업 외형을 그대로 썼다.** 대장장이는 기사와,
 * 상인은 마법사와 똑같이 생겨서, 이름표를 읽기 전에는 누가 누군지 알 수 없었다.
 * 마을에 서 있는 사람은 직업이 아니라 **하는 일**로 구분돼야 한다.
 *
 * 만드는 방법은 직업과 같다 — 몸은 buildBody 가 만들고, 여기서는 그 위에
 * 그 사람을 그 사람으로 만드는 것(앞치마, 모자, 망치)만 얹는다.
 */

const RIGHT_X = -ARM_X;
const LEFT_X = ARM_X;

/** 수염. 얼굴 아래를 덮어 나이와 성격을 한 번에 준다 */
function beard(add: AddPart, color: string, long: boolean): void {
  const y = Y.chin + HEAD / 2;
  const jaw = new THREE.SphereGeometry(HEAD / 2 * 0.82, 12, 10, 0, Math.PI * 2, Math.PI * 0.42, Math.PI * 0.58);
  jaw.scale(1, long ? 1.5 : 1.05, 1.02);
  jaw.translate(0, y - 0.03, 0.006);
  add(jaw, 'head', color, SURFACE.cloth);

  if (long) {
    const hang = new THREE.BoxGeometry(0.075, 0.11, 0.055);
    hang.translate(0, y - 0.115, 0.052);
    add(hang, 'head', color, SURFACE.cloth);
  }

  // 콧수염 — 없으면 턱만 덮인 이상한 얼굴이 된다
  const mustache = new THREE.BoxGeometry(0.072, 0.018, 0.03);
  mustache.translate(0, y - 0.024, HEAD / 2 * 0.86);
  add(mustache, 'head', color, SURFACE.cloth);
}

/** 챙 모자 */
function hat(add: AddPart, crown: string, brim: string): void {
  const y = Y.chin + HEAD / 2;
  const cap = new THREE.CylinderGeometry(0.088, 0.098, 0.1, 12);
  cap.translate(0, y + 0.095, 0);
  add(cap, 'head', crown, SURFACE.cloth);

  const disc = new THREE.CylinderGeometry(0.165, 0.175, 0.014, 14);
  disc.translate(0, y + 0.048, 0.01);
  add(disc, 'head', brim, SURFACE.cloth);

  const band = new THREE.CylinderGeometry(0.1, 0.1, 0.024, 12);
  band.translate(0, y + 0.058, 0);
  add(band, 'head', brim, SURFACE.leather);
}

/** 가슴부터 허벅지까지 덮는 앞치마 */
function apron(add: AddPart, color: string): void {
  const bib = new THREE.BoxGeometry(0.2, 0.26, 0.03);
  bib.translate(0, SHOULDER_Y - 0.19, 0.11);
  add(bib, 'chest', color, SURFACE.leather);

  const skirt = new THREE.BoxGeometry(0.28, 0.42, 0.035);
  skirt.translate(0, Y.crotch + 0.03, 0.115);
  add(skirt, 'hips', color, SURFACE.leather);

  for (const side of [1, -1]) {
    const strap = new THREE.BoxGeometry(0.032, 0.22, 0.028);
    strap.translate(side * 0.075, SHOULDER_Y - 0.03, 0.055);
    add(strap, 'chest', color, SURFACE.leather);
  }
}

// ---------------------------------------------------------------- 대장장이

const SMITH_COLORS: CharacterColors = {
  skin: '#c08a5e', // 불 앞에서 그을렸다
  hair: '#3b2b20',
  tunic: '#c08a5e', // 소매가 없어 위팔도 맨살이다
  tunicDark: '#8a5f3c',
  pants: '#4a3d2e',
  boots: '#3a2f22',
  accent: '#6b4526',
};

function equipSmith(add: AddPart, c: CharacterColors): void {
  const headY = Y.chin + HEAD / 2;

  beard(add, '#4a3628', true);

  // 이마 띠 — 대머리라 그냥 두면 정수리가 허전하다
  const band = new THREE.CylinderGeometry(0.116, 0.116, 0.035, 12);
  band.translate(0, headY + 0.03, 0);
  add(band, 'head', c.accent, SURFACE.cloth);

  apron(add, '#6b4a2c');

  // 팔뚝 토시
  for (const side of [1, -1]) {
    const L = side > 0 ? 'L' : 'R';
    const cuff = new THREE.CylinderGeometry(0.055, 0.058, 0.14, 10);
    cuff.translate(side * ARM_X, Y.waist - 0.09, 0);
    add(cuff, 'foreArm' + L, '#5a3f26', SURFACE.leather);
  }

  // --- 망치 ---
  const handle = new THREE.CylinderGeometry(0.017, 0.019, 0.42, 8);
  handle.rotateX(Math.PI / 2.3);
  handle.translate(RIGHT_X, HAND_Y - 0.02, 0.06);
  add(handle, 'handR', '#6b4a2c', SURFACE.leather);

  const headBlock = new THREE.BoxGeometry(0.085, 0.085, 0.16);
  headBlock.rotateX(Math.PI / 2.3);
  headBlock.translate(RIGHT_X, HAND_Y + 0.17, -0.09);
  add(headBlock, 'handR', '#6e747e', SURFACE.metal);
}

// ---------------------------------------------------------------- 상인

const MERCHANT_COLORS: CharacterColors = {
  skin: '#e0bb98',
  hair: '#5a4636',
  tunic: '#7a5e86',
  tunicDark: '#5d4667',
  pants: '#4a4038',
  boots: '#3e3229',
  accent: '#c9a24a',
};

function equipMerchant(add: AddPart, c: CharacterColors): void {
  hat(add, c.tunicDark, '#4a3a2c');
  beard(add, '#5a4636', false);

  // 배 — 상인은 잘 먹는다. 실루엣이 기사·마법사와 확실히 갈린다.
  const belly = new THREE.SphereGeometry(0.17, 12, 10);
  belly.scale(1.15, 0.95, 0.92);
  belly.translate(0, Y.waist - 0.07, 0.02);
  add(belly, 'spine', c.tunic);

  // 조끼
  const vest = new THREE.CylinderGeometry(0.172, 0.152, 0.34, 12, 1, true);
  vest.scale(1.18, 1, 0.8);
  vest.translate(0, SHOULDER_Y - 0.18, 0);
  add(vest, 'chest', c.tunicDark, SURFACE.cloth);

  // 허리 전대와 돈주머니
  const sash = new THREE.CylinderGeometry(0.155, 0.155, 0.07, 12);
  sash.scale(1.2, 1, 0.82);
  sash.translate(0, Y.waist - 0.16, 0);
  add(sash, 'hips', c.accent, SURFACE.cloth);

  const pouch = new THREE.SphereGeometry(0.055, 8, 7);
  pouch.scale(1, 1.15, 0.85);
  pouch.translate(0.14, Y.waist - 0.21, 0.06);
  add(pouch, 'hips', '#6b4a2c', SURFACE.leather);

  // 장부 두루마리
  const scroll = new THREE.CylinderGeometry(0.026, 0.026, 0.2, 8);
  scroll.rotateZ(Math.PI / 2);
  scroll.translate(LEFT_X, HAND_Y + 0.02, 0.03);
  add(scroll, 'handL', '#e2d8bc', SURFACE.cloth);
}

// ---------------------------------------------------------------- 마을 사람

function villagerColors(tunic: string, hair: string, skin: string, pants: string): CharacterColors {
  return { skin, hair, tunic, tunicDark: tunic, pants, boots: '#413428', accent: '#8a7452' };
}

/** 소품 하나씩 — 다 같은 옷이면 복제인간이 서 있는 것처럼 보인다 */
function equipVillagerSack(add: AddPart): void {
  const sack = new THREE.SphereGeometry(0.13, 10, 8);
  sack.scale(1, 1.2, 0.8);
  sack.translate(0, SHOULDER_Y - 0.16, -0.19);
  add(sack, 'chest', '#8a7452', SURFACE.cloth);

  const strap = new THREE.BoxGeometry(0.036, 0.4, 0.02);
  strap.rotateZ(0.3);
  strap.translate(0.05, SHOULDER_Y - 0.16, 0.1);
  add(strap, 'chest', '#5a4630', SURFACE.leather);
}

function equipVillagerApron(add: AddPart): void {
  apron(add, '#9a8f74');
  beard(add, '#6b5b46', false);
}

function equipVillagerHood(add: AddPart, c: CharacterColors): void {
  const y = Y.chin + HEAD / 2;
  const shawl = new THREE.SphereGeometry(HEAD / 2 + 0.028, 12, 10, 0, Math.PI * 2, 0, Math.PI * 0.66);
  shawl.scale(1, 1.02, 1);
  shawl.translate(0, y - 0.012, -0.006);
  add(shawl, 'head', c.tunicDark, SURFACE.cloth);

  const cape = new THREE.CylinderGeometry(0.14, 0.2, 0.3, 12, 1, true);
  cape.translate(0, SHOULDER_Y - 0.15, -0.02);
  add(cape, 'chest', c.tunicDark, SURFACE.cloth);
}

// ---------------------------------------------------------------- 목록

/**
 * NPC 외형 목록.
 *
 * 존 정의(`NpcDef.look`)에서 이름으로 고른다. 없는 이름이면 직업 외형으로
 * 떨어진다 — 존 데이터가 앞서가도 화면이 비지 않게.
 */
export const NPC_LOOKS: Record<string, ClassProfile> = {
  smith: {
    id: 'smith',
    label: '대장장이',
    colors: SMITH_COLORS,
    // 야만전사 모델 — 맨팔에 덩치가 커서 대장장이로 읽힌다.
    // 플레이어 직업 셋(기사·마법사·후드도적)과 겹치지 않는다.
    model: 'barbarian',
    // 대장장이는 도끼를 들고 머리에 두건을 쓴다.
    // 장비 메시는 만들 때 전부 꺼지므로, NPC 는 여기 적은 것만 보인다.
    npcGear: { weapon: 0, helmet: true },
    // 망치를 하루 종일 휘두른 몸. 대머리라 실루엣이 확실히 다르다.
    body: { headwear: 'bald', bulk: 1.3 },
    scale: 1.06,
    weaponHand: 'R',
    equip: equipSmith,
  },
  merchant: {
    id: 'merchant',
    label: '상인',
    colors: MERCHANT_COLORS,
    // 도적 모델(후드 없음) — 가벼운 차림이라 장사꾼으로 읽힌다.
    // 상인은 빈손이다 (npcGear 없음)
    model: 'rogue',
    body: { headwear: 'hair', bulk: 1.14 },
    scale: 0.97,
    equip: equipMerchant,
  },
  villager_sack: {
    id: 'villager_sack',
    label: '마을 사람',
    colors: villagerColors('#7d8a5a', '#3a2c20', '#dcb28e', '#5a5040'),
    model: 'rogue',
    body: { headwear: 'hair', bulk: 0.96 },
    scale: 1.03,
    equip: equipVillagerSack,
  },
  villager_apron: {
    id: 'villager_apron',
    label: '마을 사람',
    colors: villagerColors('#a8916a', '#54432f', '#c9a17c', '#4d4436'),
    model: 'barbarian',
    npcGear: { helmet: true },
    body: { headwear: 'hair', bulk: 1.05 },
    scale: 0.96,
    equip: equipVillagerApron,
  },
  villager_hood: {
    id: 'villager_hood',
    label: '마을 사람',
    colors: villagerColors('#6f7a86', '#2f2620', '#e2c0a2', '#4a4a52'),
    model: 'rogue_hooded',
    body: { headwear: 'bald', bulk: 0.9 },
    scale: 0.93,
    equip: (add, c) => equipVillagerHood(add, c),
  },
  villager_old: {
    id: 'villager_old',
    label: '노인',
    colors: villagerColors('#8a7c66', '#c8c2b4', '#cfae8e', '#544a3c'),
    // 로브 차림 노인 — 마법사 모자를 노인 모자로 쓴다
    model: 'mage',
    npcGear: { helmet: true },
    body: { headwear: 'hair', bulk: 0.88 },
    scale: 0.9,
    equip: (add) => beard(add, '#cfcabc', true),
  },
};
