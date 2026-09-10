import * as THREE from 'three';
import { HitFlash } from './hitFlash';
import { RUN_SPEED } from '@mmo/shared';
import { mergeAll } from '../scene/geometry';

/**
 * 8등신 비율의 저폴리 인간형 캐릭터.
 *
 * 부위를 개별 메시로 쌓으면 캐릭터당 드로우콜이 15개씩 늘어난다.
 * 그래서 본 스켈레톤에 리지드 스키닝한 SkinnedMesh 하나로 만든다 — 장비를 다 붙여도 드로우콜 1개.
 * 색은 정점 컬러로 넣어 머티리얼도 하나만 쓴다.
 *
 * 나중에 .glb 로 교체해도 update() 의 포즈 로직은 본 이름만 맞추면 그대로 쓸 수 있다.
 */

/** 총 신장 1.8m, 머리 하나 = 0.225m (8등신 정석 비율) */
export const HEIGHT = 1.8;
export const HEAD = HEIGHT / 8;

/** 정수리에서 머리 하나씩 내려온 기준선 */
export const Y = {
  chin: HEIGHT - HEAD, // 1.575
  chest: HEIGHT - HEAD * 2, // 1.350
  waist: HEIGHT - HEAD * 3, // 1.125 — 팔꿈치도 이 높이
  crotch: HEIGHT - HEAD * 4, // 0.900 — 손목도 이 높이, 신장의 정확히 절반
  knee: 0.48,
  ankle: 0.09,
};

/** 어깨 높이 (겨드랑이보다 살짝 위) */
export const SHOULDER_Y = 1.45;
/** 팔이 지나가는 x 위치 */
export const ARM_X = 0.235;
/** 손의 바인드 포즈 높이 */
export const HAND_Y = Y.crotch - 0.045;

export interface CharacterColors {
  skin: string;
  hair: string;
  tunic: string;
  tunicDark: string;
  pants: string;
  boots: string;
  /** 장비 강조색 (문장, 금장식 등) */
  accent: string;
}

/** 표면 재질. 금속 갑옷과 천 로브가 같은 반사를 하면 둘 다 가짜로 보인다 */
export interface SurfaceSpec {
  roughness: number;
  metalness: number;
}

export const SURFACE = {
  skin: { roughness: 0.72, metalness: 0 },
  cloth: { roughness: 0.92, metalness: 0 },
  leather: { roughness: 0.62, metalness: 0 },
  metal: { roughness: 0.34, metalness: 0.85 },
  gold: { roughness: 0.28, metalness: 0.95 },
  gem: { roughness: 0.08, metalness: 0.2 },
} as const satisfies Record<string, SurfaceSpec>;

/** 부위 하나를 등록한다. geo 는 "바인드 포즈 월드 좌표"로 만들어야 한다. */
export type AddPart = (
  geo: THREE.BufferGeometry,
  bone: string,
  color: string,
  surface?: SurfaceSpec
) => void;

export interface BodyOptions {
  headwear: 'hair' | 'helmet' | 'hood' | 'bald';
  /** 하반신을 로브로 덮는다 (허벅지 생략) */
  robe?: boolean;
  /** 몸통 두께 배율 — 기사는 갑옷 때문에 두껍다 */
  bulk?: number;
}

export interface ClassProfile {
  id: string;
  /** UI에 보여줄 이름 */
  label: string;
  colors: CharacterColors;
  body: BodyOptions;
  /**
   * 쓸 3D 모델 이름 (public/assets/models/<이름>.glb).
   *
   * 있으면 이걸로 만들고, 파일이 없으면 아래 절차적 정의로 떨어진다.
   * 모델을 쓰는 경우 colors/body/equip 은 쓰이지 않는다.
   */
  model?: string;
  /** 공격에 쓸 애니메이션 클립 이름. 없으면 근접 베기 */
  attackClip?: string;
  /**
   * 장비 정보가 없는 경우(NPC)에 기본으로 보여줄 것.
   *
   * 숫자는 모델이 들고 있는 무기·보조 목록에서 몇 번째를 쓸지다.
   * 없으면 빈손으로 선다.
   */
  npcGear?: { weapon?: number; offhand?: number; helmet?: boolean };
  /**
   * 키 배율.
   *
   * 마을 사람이 전부 같은 키로 서 있으면 복제인간처럼 보인다. 비율(8등신)은
   * 그대로 두고 전체 크기만 흔든다 — 비율까지 건드리면 장비 위치가 어긋난다.
   */
  scale?: number;
  /**
   * 무기를 든 손. 이 팔은 스윙을 줄인다 —
   * 팔을 그대로 휘두르면 검이 창처럼 앞으로 튀어나오고 지팡이가 눕는다.
   */
  weaponHand?: 'L' | 'R';
  /**
   * 궤적을 그릴 날 구간 — **기본 자세(bind pose) 모델 좌표** `[뿌리, 끝]`.
   *
   * 절차적 리그는 무기가 지오메트리에 통째로 병합돼 있어서 무기 노드를 따로
   * 집을 수가 없다. 그래서 `equip` 에 적은 좌표를 여기에 한 번 더 적어 둔다.
   * 모델 리그는 무기가 별도 노드라 이 값이 필요 없다 (경계 상자로 구한다).
   */
  weaponReach?: [[number, number, number], [number, number, number]];
  /** 직업 고유 장비 */
  equip?(add: AddPart, c: CharacterColors): void;
}

/**
 * 달리기 보행 파라미터. 이동은 달리기 한 가지뿐이라 보간할 필요가 없다.
 *
 * radPerMeter 가 핵심이다. 위상을 프레임이 아니라 **이동 거리**에 묶어야
 * 발이 미끄러지지 않는다. 2.1 rad/m -> 보폭 1.5m, 초당 약 3.1보.
 */
const GAIT = {
  radPerMeter: 2.1,
  thighSwing: 1.0,
  kneeBend: 1.6,
  ankleToe: 0.5,
  armSwing: 0.85,
  /** 달릴 때 팔꿈치는 90도 가까이 접힌다 */
  elbowBend: 1.15,
  /** 상체 전방 기울기 */
  lean: 0.24,
  /** 상하 반동 */
  bob: 0.075,
  /** 골반/가슴 반대 비틀림 */
  twist: 0.15,
  /** 한 발로 디딜 때 반대쪽 골반이 내려앉는다 (사람 걸음의 가장 큰 특징) */
  pelvisDrop: 0.075,
  /** 착지 충격으로 몸이 한 번 더 주저앉는다 */
  impact: 0.03,
  /** 팔이 몸 앞을 가로지르는 정도 */
  armCross: 0.16,
} as const;

/**
 * 가만히 서 있을 때의 기본 자세.
 *
 * 여기가 비어 있으면 팔이 **완전히 곧게 펴진 채 옆구리에 붙는다.** 사람은 서
 * 있을 때도 팔꿈치가 조금 굽어 있고 팔이 몸에서 살짝 떨어져 있다. 이게 없으면
 * 뒤에서 아무리 잘 움직여도 마네킹이 움직이는 것으로 보인다.
 */
const REST = {
  /** 팔을 몸에서 벌리는 각 */
  armSpread: 0.14,
  /** 팔을 살짝 앞으로 */
  armForward: 0.1,
  /** 팔꿈치 기본 굽힘 */
  elbow: 0.24,
  /** 무릎도 완전히 펴지지 않는다 */
  knee: 0.06,
} as const;

/** 대기 동작 — 숨쉬기와 무게중심 이동. 서 있을 때만 실린다 */
const IDLE = {
  breathRate: 1.1,
  breathDepth: 0.026,
  /** 좌우로 무게를 옮긴다 */
  swayRate: 0.37,
  swayDepth: 0.05,
  armSwayRate: 0.79,
  armSwayDepth: 0.06,
  /** 가끔 고개를 돌린다 */
  lookRate: 0.23,
  lookDepth: 0.34,
} as const;

/** 무기를 든 팔의 스윙/팔꿈치 억제 비율 */
const WEAPON_ARM_SWING = 0.25;
const WEAPON_ARM_ELBOW = 0.45;

/**
 * 공격 한 번의 길이(초)와 구간.
 *
 * 예전에는 팔 하나만 휘둘렀다. 사람은 팔로 때리지 않는다 — 발로 땅을 딛고
 * 골반을 돌려 그 힘을 팔로 보낸다. 그래서 몸 전체가 세 구간을 지나간다.
 */
const SWING_TIME = 0.44;
/** 쓰러지는 데 걸리는 시간. 툭 눕히면 인형을 넘어뜨린 것으로 보인다 */
const FALL_TIME = 0.6;
/** 뒤로 당기는 구간이 끝나는 지점 (0~1) */
const SWING_WIND = 0.34;
/** 내리치는 구간이 끝나는 지점 */
const SWING_HIT = 0.62;

interface BoneDef {
  name: string;
  parent: string | null;
  /** 부모 기준 로컬 오프셋 */
  pos: [number, number, number];
}

const BONE_DEFS: BoneDef[] = [
  { name: 'hips', parent: null, pos: [0, 0.95, 0] },
  { name: 'spine', parent: 'hips', pos: [0, 0.2, 0] },
  { name: 'chest', parent: 'spine', pos: [0, 0.23, 0] },
  { name: 'neck', parent: 'chest', pos: [0, 0.15, 0] },
  { name: 'head', parent: 'neck', pos: [0, 0.07, 0] },

  { name: 'shoulderL', parent: 'chest', pos: [0.09, 0.07, 0] },
  { name: 'upperArmL', parent: 'shoulderL', pos: [0.145, 0, 0] },
  { name: 'foreArmL', parent: 'upperArmL', pos: [0, -(SHOULDER_Y - Y.waist), 0] },
  { name: 'handL', parent: 'foreArmL', pos: [0, -(Y.waist - Y.crotch), 0] },

  { name: 'shoulderR', parent: 'chest', pos: [-0.09, 0.07, 0] },
  { name: 'upperArmR', parent: 'shoulderR', pos: [-0.145, 0, 0] },
  { name: 'foreArmR', parent: 'upperArmR', pos: [0, -(SHOULDER_Y - Y.waist), 0] },
  { name: 'handR', parent: 'foreArmR', pos: [0, -(Y.waist - Y.crotch), 0] },

  { name: 'thighL', parent: 'hips', pos: [0.1, -0.05, 0] },
  { name: 'shinL', parent: 'thighL', pos: [0, -(Y.crotch - Y.knee), 0] },
  { name: 'footL', parent: 'shinL', pos: [0, -(Y.knee - Y.ankle), 0] },

  { name: 'thighR', parent: 'hips', pos: [-0.1, -0.05, 0] },
  { name: 'shinR', parent: 'thighR', pos: [0, -(Y.crotch - Y.knee), 0] },
  { name: 'footR', parent: 'shinR', pos: [0, -(Y.knee - Y.ankle), 0] },
];

/** 두 높이를 잇는 캡슐 (팔다리) */
export function limb(x: number, yTop: number, yBottom: number, radius: number): THREE.BufferGeometry {
  const span = yTop - yBottom;
  // 분할을 3x8 에서 올렸다. 저폴리라도 팔다리는 실루엣에 계속 노출되는 부위라
  // 각이 지면 바로 눈에 띈다. 전부 한 메시로 병합되므로 드로우콜은 그대로 1개다.
  const geo = new THREE.CapsuleGeometry(radius, Math.max(span - radius * 2, 0.01), 4, 12);
  geo.translate(x, (yTop + yBottom) / 2, 0);
  return geo;
}

/**
 * 얼굴.
 *
 * 예전에는 머리가 **민무늬 구**였다. 쿼터뷰라 얼굴이 작게 나오지만, 이목구비가
 * 하나도 없으면 어느 각도에서도 사람이 아니라 마네킹으로 읽힌다. 반대로 눈코입
 * 위치만 잡혀 있으면 화면에서 몇 픽셀이어도 얼굴로 보인다.
 *
 * 투구처럼 얼굴을 덮는 머리쓰개에는 붙이지 않는다 (안 보이는 폴리곤).
 */
function buildFace(add: AddPart, c: CharacterColors): void {
  const y = Y.chin + HEAD / 2;
  const r = HEAD / 2;
  const shade = new THREE.Color(c.skin).multiplyScalar(0.82).getStyle();

  // 눈두덩 — 눈 위를 살짝 덮어 시선이 생긴다
  const brow = new THREE.BoxGeometry(0.088, 0.016, 0.03);
  brow.translate(0, y + 0.026, r * 0.82);
  add(brow, 'head', shade, SURFACE.skin);

  const nose = new THREE.ConeGeometry(0.018, 0.045, 5);
  nose.rotateX(Math.PI / 2.1);
  nose.translate(0, y - 0.002, r * 0.88);
  add(nose, 'head', c.skin, SURFACE.skin);

  const mouth = new THREE.BoxGeometry(0.036, 0.008, 0.012);
  mouth.translate(0, y - 0.042, r * 0.85);
  add(mouth, 'head', shade, SURFACE.skin);

  for (const side of [1, -1]) {
    const eye = new THREE.SphereGeometry(0.014, 7, 6);
    eye.scale(1, 0.85, 0.6);
    eye.translate(side * 0.032, y + 0.008, r * 0.83);
    add(eye, 'head', '#2b2119', SURFACE.gem);

    const ear = new THREE.SphereGeometry(0.019, 6, 5);
    ear.scale(0.5, 1.15, 1);
    ear.translate(side * (r * 0.92), y - 0.004, 0.004);
    add(ear, 'head', c.skin, SURFACE.skin);
  }
}

function buildBody(add: AddPart, c: CharacterColors, opt: BodyOptions): void {
  const bulk = opt.bulk ?? 1;

  // --- 머리 ---
  // 분할을 늘렸다. 예전 12x10 은 옆에서 보면 각이 그대로 드러났다.
  const skull = new THREE.SphereGeometry(HEAD / 2, 16, 14);
  skull.scale(0.92, 1, 0.9);
  skull.translate(0, Y.chin + HEAD / 2, 0);
  add(skull, 'head', c.skin, SURFACE.skin);

  // 턱 — 구만 있으면 얼굴이 공처럼 둥글다
  const jaw = new THREE.SphereGeometry(HEAD / 2 * 0.78, 10, 8);
  jaw.scale(0.94, 0.72, 0.98);
  jaw.translate(0, Y.chin + HEAD * 0.3, 0.008);
  add(jaw, 'head', c.skin, SURFACE.skin);

  if (opt.headwear !== 'helmet') buildFace(add, c);

  if (opt.headwear === 'hair') {
    const hair = new THREE.SphereGeometry(HEAD / 2 + 0.012, 14, 10, 0, Math.PI * 2, 0, Math.PI * 0.58);
    hair.scale(0.94, 1, 0.92);
    hair.translate(0, Y.chin + HEAD / 2 + 0.005, 0);
    add(hair, 'head', c.hair, SURFACE.skin);

    // 뒷머리 — 뒤통수가 훤히 비면 대머리로 보인다
    const back = new THREE.SphereGeometry(HEAD / 2 + 0.008, 12, 10, 0, Math.PI * 2, Math.PI * 0.28, Math.PI * 0.42);
    back.scale(0.95, 1, 0.94);
    back.translate(0, Y.chin + HEAD / 2 + 0.005, -0.012);
    add(back, 'head', c.hair, SURFACE.skin);
  }

  const neck = new THREE.CylinderGeometry(0.045, 0.05, 0.09, 8);
  neck.translate(0, Y.chin - 0.03, 0);
  add(neck, 'neck', c.skin, SURFACE.skin);

  // --- 몸통: 어깨가 넓고 허리로 갈수록 좁아진다 ---
  const chest = new THREE.CylinderGeometry(0.15 * bulk, 0.12 * bulk, SHOULDER_Y - Y.waist, 10);
  chest.scale(1.2, 1, 0.72); // 앞뒤로 납작하게
  chest.translate(0, (SHOULDER_Y + Y.waist) / 2, 0);
  add(chest, 'chest', c.tunic);

  const abdomen = new THREE.CylinderGeometry(0.125 * bulk, 0.13, 0.2, 10);
  abdomen.scale(1.2, 1, 0.75);
  abdomen.translate(0, Y.waist - 0.06, 0);
  add(abdomen, 'spine', c.tunic);

  const belt = new THREE.CylinderGeometry(0.134, 0.134, 0.045, 10);
  belt.scale(1.2, 1, 0.78);
  belt.translate(0, Y.waist - 0.15, 0);
  add(belt, 'hips', c.boots, SURFACE.leather);

  const pelvis = new THREE.CylinderGeometry(0.13, 0.115, 0.16, 10);
  pelvis.scale(1.18, 1, 0.78);
  pelvis.translate(0, Y.crotch + 0.05, 0);
  add(pelvis, 'hips', c.pants);

  for (const side of [1, -1]) {
    const L = side > 0 ? 'L' : 'R';
    const ax = side * ARM_X;

    const pad = new THREE.SphereGeometry(0.072 * bulk, 10, 8);
    pad.scale(1, 0.85, 1);
    pad.translate(side * 0.215, SHOULDER_Y + 0.015, 0);
    add(pad, 'upperArm' + L, c.tunicDark);

    add(limb(ax, SHOULDER_Y, Y.waist, 0.05), 'upperArm' + L, c.tunic);
    add(limb(ax, Y.waist, Y.crotch, 0.044), 'foreArm' + L, c.skin, SURFACE.skin);

    const hand = new THREE.SphereGeometry(0.05, 8, 6);
    hand.scale(1, 1.15, 0.8);
    hand.translate(ax, HAND_Y, 0);
    add(hand, 'hand' + L, c.skin, SURFACE.skin);

    // --- 다리 ---
    const hx = side * 0.1;
    // 로브가 허벅지를 완전히 덮으므로 생략한다 (안 보이는 폴리곤)
    if (!opt.robe) add(limb(hx, Y.crotch + 0.03, Y.knee, 0.077), 'thigh' + L, c.pants);
    add(limb(hx, Y.knee, Y.ankle, 0.06), 'shin' + L, c.boots, SURFACE.leather);

    const foot = new THREE.BoxGeometry(0.095, 0.075, 0.21);
    foot.translate(hx, Y.ankle - 0.048, 0.045);
    add(foot, 'foot' + L, c.boots, SURFACE.leather);
  }
}

/** 화면에 그려지는 장비 — 무기·보조·투구의 아이템 id (빈 문자열이면 없음) */
export interface GearLook {
  weapon: string;
  offhand: string;
  helmet: string;
  armor: string;
  boots: string;
}

/**
 * 무기의 날 구간을 월드 좌표로 알려주는 것.
 *
 * 궤적(`swingTrails`)이 매 프레임 이걸 물어서 리본을 잇는다. 리그마다 무기가
 * 붙는 방식이 달라서(절차적 리그는 지오메트리에 병합, 모델 리그는 별도 노드)
 * "어디가 날인가" 는 리그가 알고 있어야 한다.
 */
export interface WeaponEdge {
  /**
   * 지금 들고 있는 무기의 뿌리와 끝을 채운다.
   * 무기가 없으면 `false` 를 돌려주고 인자는 건드리지 않는다.
   */
  weaponEdge(base: THREE.Vector3, tip: THREE.Vector3): boolean;
}

export interface CharacterRig extends WeaponEdge {
  group: THREE.Group;
  /** 이름표를 띄울 높이 */
  headHeight: number;
  update(dt: number, speed: number): void;
  /** 공격 모션을 한 번 재생한다 */
  swing(): void;
  /** 한 대 맞았다 — 잠깐 하얗게 번쩍인다 */
  flash(): void;
  /**
   * 쓰러진다. 마지막 자세에서 멈춘 채로 있는다.
   *
   * 죽은 걸 화면으로 알리는 유일한 신호다 — 예전에는 HP 만 0 이 되고 서 있어서,
   * 조작이 안 먹는 이유를 알 수 없었다.
   */
  die(): void;
  /** 다시 살아났다. 죽은 자세를 풀고 대기로 돌린다 */
  revive(): void;
  /**
   * 손에 든 것과 투구를 맞춘다.
   *
   * 절차적 리그에서는 아무것도 하지 않는다 — 장비가 지오메트리에 통째로
   * 병합돼 있어서 나중에 갈아끼울 수가 없다. 모델 리그에서만 동작한다.
   */
  setGear(gear: GearLook): void;
  dispose(): void;
}

export function createCharacterRig(profile: ClassProfile): CharacterRig {
  // --- 본 계층 ---
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
  const root = byName.get('hips')!;

  // --- 부위 수집 ---
  interface Part {
    geo: THREE.BufferGeometry;
    bone: string;
    color: string;
    surface: SurfaceSpec;
  }
  const parts: Part[] = [];
  const add: AddPart = (geo, bone, color, surface) =>
    parts.push({ geo, bone, color, surface: surface ?? SURFACE.cloth });

  buildBody(add, profile.colors, profile.body);
  profile.equip?.(add, profile.colors);

  // --- 정점 컬러와 스킨 가중치를 심고 하나로 병합 ---
  const boneIndex = new Map(bones.map((b, i) => [b.name, i]));
  const color = new THREE.Color();

  for (const part of parts) {
    const count = part.geo.attributes.position.count;
    const idx = boneIndex.get(part.bone);
    if (idx === undefined) throw new Error('알 수 없는 본: ' + part.bone);

    color.set(part.color);
    const colors3 = new Float32Array(count * 3);
    const surface2 = new Float32Array(count * 2);
    const skinIndex = new Uint16Array(count * 4);
    const skinWeight = new Float32Array(count * 4);
    for (let i = 0; i < count; i++) {
      surface2[i * 2] = part.surface.roughness;
      surface2[i * 2 + 1] = part.surface.metalness;
      colors3[i * 3] = color.r;
      colors3[i * 3 + 1] = color.g;
      colors3[i * 3 + 2] = color.b;
      // 리지드 바인딩: 정점 하나는 본 하나에 100% 붙는다.
      // 관절이 살짝 꺾여 보이지만 저폴리 룩에서는 오히려 어울린다.
      skinIndex[i * 4] = idx;
      skinWeight[i * 4] = 1;
    }
    part.geo.setAttribute('color', new THREE.BufferAttribute(colors3, 3));
    part.geo.setAttribute('surface', new THREE.BufferAttribute(surface2, 2));
    part.geo.setAttribute('skinIndex', new THREE.BufferAttribute(skinIndex, 4));
    part.geo.setAttribute('skinWeight', new THREE.BufferAttribute(skinWeight, 4));
  }

  const geometry = mergeAll(parts.map((p) => p.geo));

  // 머티리얼은 하나지만(드로우콜 1개) 러프니스/메탈니스는 정점마다 다르다.
  // 이래야 같은 메시 안에서 강철 갑옷과 가죽이 다르게 반사한다.
  const material = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, metalness: 1 });
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
      .replace('#include <roughnessmap_fragment>', 'float roughnessFactor = vSurface.x;')
      .replace('#include <metalnessmap_fragment>', 'float metalnessFactor = vSurface.y;');
  };
  material.customProgramCacheKey = () => 'character-surface';

  const mesh = new THREE.SkinnedMesh(geometry, material);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  mesh.add(root);
  const skeleton = new THREE.Skeleton(bones);
  mesh.bind(skeleton);

  const group = new THREE.Group();
  group.add(mesh);
  const scale = profile.scale ?? 1;
  if (scale !== 1) group.scale.setScalar(scale);

  /**
   * 궤적 앵커 — 손 뼈에 매단 빈 오브젝트 둘.
   *
   * 뼈의 자식으로 두면 애니메이션이 알아서 끌고 다니므로, 매 프레임 스키닝
   * 행렬을 손으로 풀 필요가 없다. 위치는 기본 자세에서 한 번만 계산한다.
   */
  let edgeBase: THREE.Object3D | null = null;
  let edgeTip: THREE.Object3D | null = null;
  if (profile.weaponReach) {
    const handBone = byName.get('hand' + (profile.weaponHand ?? 'R'));
    if (handBone) {
      // 아직 씬에 안 붙어 있어서 group 의 행렬은 단위행렬이다 —
      // 즉 지금의 월드 좌표가 곧 모델 좌표다.
      group.updateMatrixWorld(true);
      const [from, to] = profile.weaponReach;
      edgeBase = new THREE.Object3D();
      edgeTip = new THREE.Object3D();
      edgeBase.position.copy(handBone.worldToLocal(new THREE.Vector3(...from)));
      edgeTip.position.copy(handBone.worldToLocal(new THREE.Vector3(...to)));
      handBone.add(edgeBase, edgeTip);
    }
  }

  // --- 애니메이션 상태 ---
  const b = (name: string) => byName.get(name)!;
  const hipsRestY = root.position.y;
  const hipsRestX = root.position.x;
  let phase = 0;
  let idlePhase = Math.random() * Math.PI * 2; // 다들 같은 자세로 서 있지 않도록
  let moveBlend = 0; // 0 = 대기, 1 = 달리기
  /** 남은 공격 모션 시간(초). 0 이면 안 하고 있다 */
  let swingT = 0;
  /** 쓰러진 뒤 지난 시간. 음수면 살아 있다 */
  let fallT = -1;

  const hitFlash = new HitFlash(group);

  return {
    group,
    headHeight: (HEIGHT + 0.16) * (profile.scale ?? 1),

    flash(): void {
      hitFlash.flash();
    },

    swing(): void {
      swingT = SWING_TIME;
    },

    die(): void {
      if (fallT >= 0) return;
      fallT = 0;
      swingT = 0;
    },

    revive(): void {
      fallT = -1;
      group.rotation.z = 0;
      group.position.y = 0;
    },

    weaponEdge(base: THREE.Vector3, tip: THREE.Vector3): boolean {
      if (!edgeBase || !edgeTip) return false;
      // 뼈 행렬은 렌더 직전에 갱신된다. 궤적은 그 전에 물어보므로 여기서
      // 이 두 개만 직접 올려 준다 — 안 하면 한 프레임 뒤처진 자리에 그린다.
      edgeBase.updateWorldMatrix(true, false);
      edgeTip.updateWorldMatrix(true, false);
      base.setFromMatrixPosition(edgeBase.matrixWorld);
      tip.setFromMatrixPosition(edgeTip.matrixWorld);
      return true;
    },

    setGear(): void {
      // 절차적 리그는 장비를 갈아끼울 수 없다 (지오메트리에 병합돼 있다)
    },

    update(dt: number, speed: number): void {
      hitFlash.update(dt);
      // 쓰러지는 중/쓰러진 뒤 — 포즈를 그대로 두고 몸만 옆으로 넘긴다.
      // 클립이 없는 리그라 자세를 만들 수 없다. 넘어가는 것만으로도
      // "서 있다"와는 확실히 구분된다.
      if (fallT >= 0) {
        fallT = Math.min(FALL_TIME, fallT + dt);
        const t = fallT / FALL_TIME;
        const ease = 1 - (1 - t) * (1 - t); // 처음엔 천천히, 바닥에서 빨리
        group.rotation.z = ease * Math.PI * 0.5;
        group.position.y = -ease * 0.12; // 어깨가 땅에 묻히지 않을 만큼만
        return;
      }

      if (swingT > 0) swingT = Math.max(0, swingT - dt);
      // 대기 <-> 달리기 전환만 부드럽게 섞는다
      const k = 1 - Math.exp(-12 * dt);
      moveBlend += (THREE.MathUtils.clamp(speed / RUN_SPEED, 0, 1) - moveBlend) * k;

      phase += speed * dt * GAIT.radPerMeter;
      idlePhase += dt;

      const s = Math.sin(phase);
      const c = Math.cos(phase);
      const m = moveBlend;
      const still = 1 - m;

      const thigh = GAIT.thighSwing * m;
      const knee = GAIT.kneeBend * m;
      const toe = GAIT.ankleToe * m;
      const arm = GAIT.armSwing * m;
      const elbow = GAIT.elbowBend * m;
      const lean = GAIT.lean * m;
      const twist = GAIT.twist * m;

      // --- 대기 동작 ---
      // 숨쉬기와 무게중심 이동. 목표는 "살아 있다"로 읽히는 것뿐이라 아주 작다.
      const breath = Math.sin(idlePhase * IDLE.breathRate);
      const sway = Math.sin(idlePhase * IDLE.swayRate);
      const armSway = Math.sin(idlePhase * IDLE.armSwayRate);
      const look = Math.sin(idlePhase * IDLE.lookRate);

      // --- 다리 ---
      // 허벅지: +는 뒤로. phase=pi/2 에서 최대로 뒤(디딤 끝), 3pi/2 에서 최대로 앞(착지 직전)
      b('thighL').rotation.x = s * thigh;
      b('thighR').rotation.x = -s * thigh;

      // 무릎은 다리가 앞으로 나오는 유상기(phase pi/2 ~ 3pi/2)에만 접힌다.
      // 이 위상이 어긋나면 디딤발이 꺾여서 걸음이 무너져 보인다.
      // 서 있을 때도 REST.knee 만큼은 굽어 있다 — 완전히 편 다리는 죽마처럼 보인다.
      b('shinL').rotation.x = Math.max(0, -c) * knee + knee * 0.1 + REST.knee * still;
      b('shinR').rotation.x = Math.max(0, c) * knee + knee * 0.1 + REST.knee * still;

      // 발끝: 디딤 끝에서 차고(+), 착지 직전엔 살짝 들어올린다(-)
      b('footL').rotation.x = (s > 0 ? s : s * 0.35) * toe;
      b('footR').rotation.x = (-s > 0 ? -s : -s * 0.35) * toe;

      // --- 팔: 다리와 반대 위상. 무기 든 팔은 억제한다 ---
      const armL = arm * (profile.weaponHand === 'L' ? WEAPON_ARM_SWING : 1);
      const armR = arm * (profile.weaponHand === 'R' ? WEAPON_ARM_SWING : 1);
      const elbowL = elbow * (profile.weaponHand === 'L' ? WEAPON_ARM_ELBOW : 1);
      const elbowR = elbow * (profile.weaponHand === 'R' ? WEAPON_ARM_ELBOW : 1);

      // 기본 자세(굽은 팔꿈치, 벌린 팔) 위에 달리기 스윙과 대기 흔들림을 얹는다
      const restArm = REST.armForward * still;
      const swayArm = armSway * IDLE.armSwayDepth * still;
      b('upperArmL').rotation.x = -s * armL + restArm + swayArm;
      b('upperArmR').rotation.x = s * armR + restArm - swayArm;

      // 팔은 서 있을 때 벌어지고 달릴 때 몸에 붙는다
      const spread = REST.armSpread * (0.35 + 0.65 * still);
      b('upperArmL').rotation.z = -spread;
      b('upperArmR').rotation.z = spread;
      // 달릴 때 팔이 몸 앞을 조금 가로지른다 — 없으면 팔이 한 평면에서만 움직인다
      b('upperArmL').rotation.y = -Math.max(0, -s) * GAIT.armCross * m;
      b('upperArmR').rotation.y = Math.max(0, s) * GAIT.armCross * m;

      b('foreArmL').rotation.x = -(REST.elbow * still + elbowL + Math.max(0, -s) * elbowL * 0.35);
      b('foreArmR').rotation.x = -(REST.elbow * still + elbowR + Math.max(0, s) * elbowR * 0.35);

      // --- 상체 ---
      // 기울기는 spine 에 준다. hips 에 주면 다리까지 같이 넘어간다.
      b('spine').rotation.x = lean;
      b('hips').rotation.y = -s * twist;
      b('chest').rotation.y = s * twist * 1.3;
      // 숨쉬기: 가슴이 들리고 목이 아주 조금 따라 움직인다
      b('chest').rotation.x = -lean * 0.3 - breath * IDLE.breathDepth * still;
      b('neck').rotation.x = breath * IDLE.breathDepth * 0.4 * still;

      // 한 발로 디딜 때 반대쪽 골반이 내려앉고 가슴이 반대로 기운다.
      // 사람 걸음에서 가장 눈에 띄는 좌우 움직임이라, 없으면 평면적으로 보인다.
      b('hips').rotation.z = -s * GAIT.pelvisDrop * m + sway * IDLE.swayDepth * 0.5 * still;
      b('chest').rotation.z = s * GAIT.pelvisDrop * 0.55 * m;

      // 머리는 기울기를 상쇄해 수평을 유지하고, 서 있을 때는 가끔 둘러본다
      b('head').rotation.x = -lean * 0.6 - breath * 0.012 * still;
      b('head').rotation.y = look * IDLE.lookDepth * still;
      b('head').rotation.z = -sway * IDLE.swayDepth * 0.35 * still;

      // 상하 반동: 두 다리가 모이는 순간(phase 0, pi)이 가장 높다.
      // 착지 직후 한 번 더 주저앉는다 — 무게가 실리는 느낌을 준다.
      const land = Math.max(0, -Math.cos(phase * 2));
      root.position.y = hipsRestY + (Math.abs(c) * GAIT.bob - land * GAIT.impact) * m;
      root.position.x = hipsRestX + sway * 0.012 * still;

      // --- 공격 스윙 ---
      // 팔만 휘두르면 허수아비가 된다. 발로 딛고 골반을 돌려 그 힘을 팔로 보낸다.
      if (swingT > 0) {
        const t = 1 - swingT / SWING_TIME; // 0 -> 1
        const wind = Math.sin(Math.min(1, t / SWING_WIND) * Math.PI * 0.5);
        const hitRaw = THREE.MathUtils.clamp((t - SWING_WIND) / (SWING_HIT - SWING_WIND), 0, 1);
        // 칠 때는 앞이 빠르다 (ease-out)
        const hit = 1 - (1 - hitRaw) * (1 - hitRaw);
        const back = THREE.MathUtils.clamp((t - SWING_HIT) / (1 - SWING_HIT), 0, 1);

        const hand = profile.weaponHand ?? 'R';
        const dir = hand === 'R' ? 1 : -1;

        // 세 구간이 이어지도록 값을 직접 잇는다.
        // 뒤로 +0.9 -> 앞으로 -2.4 -> 제자리(0)
        const armX =
          t < SWING_WIND ? 0.9 * wind : t < SWING_HIT ? 0.9 - 3.3 * hit : -2.4 * (1 - back);
        const foreX =
          t < SWING_WIND ? -(0.5 + 0.8 * wind) : t < SWING_HIT ? -(1.3 - 0.95 * hit) : -(0.35 - 0.11 * back);
        // 골반 -> 가슴 순서로 돌아간다. 이 시간차가 "힘이 전달된다"로 읽힌다.
        const turn =
          t < SWING_WIND ? 0.28 * wind : t < SWING_HIT ? 0.28 - 0.78 * hit : -0.5 * (1 - back);
        const power = t < SWING_WIND ? wind : t < SWING_HIT ? 1 : 1 - back;

        b('upperArm' + hand).rotation.x = armX;
        b('foreArm' + hand).rotation.x = foreX;

        b('hips').rotation.y += dir * turn;
        b('chest').rotation.y += dir * turn * 1.3;
        b('head').rotation.y += dir * turn * 0.5;
        b('spine').rotation.x += -wind * 0.12 + hit * 0.22 * (1 - back);

        // 반대 팔은 균형을 잡으려 반대로 간다
        const off = hand === 'R' ? 'L' : 'R';
        b('upperArm' + off).rotation.x += -turn * 1.2;
        b('foreArm' + off).rotation.x += -0.4 * power;

        // 앞발로 딛고 들어간다
        const front = dir > 0 ? 'L' : 'R';
        b('thigh' + front).rotation.x += (-0.42 * hit + 0.1 * wind) * (1 - back);
        b('shin' + front).rotation.x += 0.3 * hit * (1 - back);
      }
    },

    dispose(): void {
      hitFlash.dispose();
      geometry.dispose();
      material.dispose();
      skeleton.dispose();
    },
  };
}
