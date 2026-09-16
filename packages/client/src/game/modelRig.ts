import * as THREE from 'three';
import { clone as cloneSkinned } from 'three/examples/jsm/utils/SkeletonUtils.js';
import {
  MONSTER_SWING_MS,
  RUN_SPEED,
  TIER_COLOR,
  beastHeadHeight,
  beastHeight,
  getItem,
  tierIndexOf,
  type MonsterKind,
} from '@mmo/shared';
import { CLIP, pickClip, type Models } from '../scene/models';
import type { CharacterRig, ClassProfile, GearLook } from './characterRig';
import type { MonsterRig } from './monsterRig';
import { HitFlash } from './hitFlash';

/**
 * 불러온 모델로 만드는 리그.
 *
 * 절차적 리그(characterRig / monsterRig)와 **인터페이스가 같다.** 그래서
 * 부르는 쪽은 무엇으로 만들어졌는지 몰라도 된다 — 모델이 아직 안 왔거나
 * 그 이름이 없으면 절차적 리그로 조용히 떨어진다.
 *
 * 포즈를 코드로 만들지 않고 클립을 섞는다. 사람 걸음을 삼각함수로 흉내내는
 * 것보다, 사람이 만든 걸 재생하는 쪽이 언제나 자연스럽다.
 */

/** 대기 <-> 달리기 섞이는 속도 */
const BLEND_RATE = 10;
/** 달리기 클립이 원래 상정한 이동 속도(m/s). 실제 속도에 맞춰 재생 속도를 조절한다 */
const RUN_CLIP_SPEED = 4.6;
/**
 * 모델마다 달리기 클립이 달라서 따로 잡은 값. 없으면 RUN_CLIP_SPEED.
 *
 * VARCO 마법사는 디딤발이 뒤로 쓸려 가는 속도를 이 리그로 재서 잡았다(5.8).
 * 기사 값(4.6)으로 틀면 발이 몸보다 25% 남짓 빨리 쓸려 앞으로 미끄러진다.
 */
const RUN_CLIP_SPEEDS: Record<string, number> = {
  varco_mage: 5.8,
  // 궁수 달리기는 마법사와 같은 클립이다 (46키, 루프 닫기 결과까지 같다)
  varco_archer: 5.8,
  // 격투가도 같은 클립이다 (46키 → 32키, 구워진 방향 -94.6° 까지 같다)
  varco_fighter: 5.8,
};
/** 공격 중에 남겨두는 이동 동작의 비중 */
const ATTACK_LOWER = 0.18;
/**
 * **사람이 움직이기 시작하면 남은 공격 클립을 끊는다** (캐릭터 리그 전용).
 *
 * 공격 경직(`ATTACK_ROOT_MS`, 0.4초)은 클립보다 훨씬 짧다 — 격투가 3.23s ·
 * 마법사 3.27s. 경직이 풀려 다시 걷기 시작해도 클립은 계속 돌아서, 달리는 몸
 * 위에 칼질이 얹힌 채로 남는다. 이게 "공격하면서 이동한다" 로 보이던 것의
 * 나머지 반이다 (앞의 반은 서버가 실제로 옮겨 주던 것).
 *
 * **짐승에는 안 건다.** 사람은 자기가 조작해서 멈출 수 있지만, 짐승은 사람이
 * 한 발짝만 물러나도 서버가 곧바로 쫓게 하므로(`chase`) 매번 휘두르다 만 채로
 * 동작이 사라진다 — 아래 `createBeastRig` 주석 참고.
 *
 * 이 속도(m/s)를 넘으면 끊는다. 0 으로 두면 보정으로 조금씩 흔들리는 것까지
 * 이동으로 쳐서 제자리 공격이 끊긴다.
 */
const ATTACK_CUT_SPEED = 0.6;
/** 끊을 때 섞어 빼는 시간(초). 0 으로 툭 끄면 상체가 한 프레임에 튄다 */
const ATTACK_CUT_FADE = 0.15;
/**
 * **짐승 공격 클립에서 한 번 휘두르는 구간** (초).
 *
 * 바르코가 준 오우거 `Attack` 은 3.73초인데 그 안에 할퀴기가 네 번 들어 있다
 * (FK 로 잰 자리: 0.90~1.05 · 1.80~1.95 · 2.00~2.20 · 2.95~3.40s). 통째로 틀면
 * 한 대 때리는 데 3.7초가 걸려서, 서버가 그만큼 세워 둘 수도 없고 안 세우면
 * **휘두르며 달린다.** 그래서 첫 할퀴기만 잘라 쓴다 — 준비 0.80s 부터 되돌아온
 * 1.45s 까지, 딱 `MONSTER_SWING_MS`(650ms)다.
 *
 * 오우거 5종이 같은 클립이라 한 줄로 맞는다. 표에 없는 짐승은 클립 앞에서
 * 같은 길이만큼 잘라 쓴다 — **길이는 반드시 서버 경직과 같아야 한다.**
 */
const BEAST_ATTACK_WINDOWS: Record<string, { from: number; to: number }> = Object.fromEntries(
  ['varco_ogre1', 'varco_ogre2', 'varco_ogre3', 'varco_ogre4', 'varco_ogre5'].map((look) => [
    look,
    { from: 0.8, to: 0.8 + MONSTER_SWING_MS / 1000 },
  ])
);
/** 표에 없는 짐승 — 클립 앞부터 같은 길이만큼 */
const BEAST_ATTACK_FALLBACK = { from: 0, to: MONSTER_SWING_MS / 1000 };
/**
 * 공격 클립을 어디부터 어디까지 몇 배로 틀지. 없으면 처음부터 끝까지 1배.
 *
 * `swing()` 은 칠 때마다 클립을 되감는다. VARCO 격투가 공격은 3.23s 인데 진짜로
 * 차는 순간(왼발 앞차기, 정면에서 7°)이 1.30s 에 있고, 앞 0.8s 는 몸을 돌려
 * 자세를 잡는 준비다. 공격 간격(700ms)마다 처음으로 되감으면 준비만 되풀이하고
 * 발은 한 번도 안 나간다. 준비를 건너뛰고 빨리 틀어 차는 순간을 당긴다 —
 * 0.8s 부터 1.6배면 0.31s 에 찬다.
 *
 * **`to` 에서 잘라 빼는 이유: 안 자르면 발차기가 두 번 나간다.** 2.30s 에 한 바퀴
 * 도는 뒤돌려차기가 또 있어서, 한 대 치는 데 발이 두 번 나가고 몸이 한 바퀴 돈다.
 *
 * **자르는 자리는 페이드까지 포함해서 고른다.** FK 로 재면 왼발 앞차기가 1.15~1.30s
 * (골반에서 0.52m, 높이 +0.37)에 나가고 1.50s 에 땅에 닿는다. **1.60~1.80s 가 클립에서
 * 가장 조용한 구간**(프레임 움직임 0.37~0.60, 두 발 다 -0.40)이고, 1.85s 부터 오른발이
 * 다시 올라가기 시작한다(2.00s 에 +0.27) — 뒤돌려차기 준비다. 그래서 **1.60s 에 끊는다.**
 * `ATTACK_CUT_FADE`(0.15초)가 덮는 뒤쪽이 통째로 그 조용한 구간 안에 들어와서, 빠지는
 * 동안 새로 시작되는 동작이 없다. 1.92s 에서 끊었을 때 "앞차기 뒤에 뭘 한 번 더 한다"
 * 로 보이던 것이 이 준비 동작이었다 (2026-09-15).
 *
 * 1.6배라 0.8~1.60s 는 0.5초, 페이드까지 0.65초로 공격 간격(700ms) 안에 끝난다.
 * 짐승(`BEAST_ATTACK_WINDOWS`)과 같은 방식이고, 끊는 것도 같은 페이드를 쓴다.
 */
const ATTACK_CLIPS: Record<string, { from: number; to?: number; speed: number }> = {
  varco_fighter: { from: 0.8, to: 1.6, speed: 1.6 },
};
/**
 * 사람 키(m).
 *
 * 모델 팩마다 단위가 다르다 — 이 팩은 한 칸이 2.5 쯤이다. 우리 세계는
 * 절차적 리그 때부터 1.8m 를 사람 키로 잡아왔고, 이동 속도·사거리·카메라
 * 거리가 전부 그 위에 맞춰져 있다. 그래서 **모델을 세계에 맞춘다.**
 */
const HUMAN_HEIGHT = 1.8;
/**
 * 달리기 클립이 **사람 키(1.8m)일 때** 상정한 이동 속도(m/s). 없는 짐승은 섞는 기준(3)을 쓴다.
 *
 * 오우거 달리기는 VARCO 마법사와 같은 클립이라 마법사에서 잰 5.8 을 쓴다
 * (RUN_CLIP_SPEEDS 참고). 같은 클립이라도 몸이 크면 한 걸음에 더 멀리 가므로
 * 실제 값은 키에 비례해 늘린다 — 2.2m 오우거면 7.1 이다.
 */
const BEAST_RUN_CLIP_SPEEDS: Record<string, number> = {
  varco_ogre1: 5.8,
  varco_ogre2: 5.8,
  varco_ogre3: 5.8,
  varco_ogre4: 5.8,
  varco_ogre5: 5.8,
};

function loop(action: THREE.AnimationAction | null, weight: number): void {
  if (!action) return;
  action.setEffectiveWeight(weight);
}

/**
 * 종류별로 물들인 머티리얼.
 *
 * 여우 한 마리를 40종 몬스터로 돌려 쓰므로 색만 바꾼다. 마리마다 clone 하면
 * 같은 색 머티리얼이 수십 벌 생겨 GPU 상태 전환만 늘어난다.
 */
const tintCache = new Map<string, THREE.Material>();
const WHITE = new THREE.Color(0xffffff);

function tintedMaterial(source: THREE.Material, color: string, softness = 0.3): THREE.Material {
  const key = `${source.uuid}#${color}#${softness}`;
  const found = tintCache.get(key);
  if (found) return found;

  const copy = (source as THREE.MeshStandardMaterial).clone();
  // 색을 그냥 곱하면 어두워진다 — 늑대 색(#7b6a55)을 곱하면 밝기가 절반이 되어
  // 텍스처의 명암까지 뭉개진 검은 덩어리가 된다. 밝기는 1 로 되돌리고 색조만
  // 가져온 뒤, 흰색 쪽으로 물러선다. softness 가 클수록 원래 색이 많이 남는다.
  const tint = new THREE.Color(color);
  const peak = Math.max(tint.r, tint.g, tint.b, 0.001);
  tint.multiplyScalar(1 / peak).lerp(WHITE, softness);
  copy.color.multiply(tint);
  tintCache.set(key, copy);
  return copy;
}

/**
 * 갑옷·신발은 갈아입힐 메시가 없다.
 *
 * 그래서 **몸통과 다리 색을 바꾼다.** 통째로 칠하면 직업 구분이 사라지므로
 * 색조만 얹고 원래 색을 많이 남긴다 — 다시 칠하는 게 아니라 물드는 정도다.
 */
const ARMOR_SOFTNESS = 0.45;

/** 이름이 이렇게 끝나는 메시가 그 자리다 */
const BODY_PARTS = ['_Body', '_ArmLeft', '_ArmRight'];
const LEG_PARTS = ['_LegLeft', '_LegRight'];

function tierColorOf(itemId: string): string | null {
  const item = getItem(itemId);
  if (!item) return null;
  return TIER_COLOR[tierIndexOf(item)] ?? null;
}

/**
 * 모델 안에 이미 들어 있는 장비 메시들.
 *
 * KayKit 캐릭터는 손 뼈(handslot.l / handslot.r)에 무기와 방패가 **여러 개
 * 매달린 채로** 온다. 전부 scale 1 이라 그냥 두면 칼 두 자루와 방패 네 개가
 * 겹쳐서 그려진다 — 지금까지 그러고 있었다. 그래서 만들 때 전부 끄고,
 * 장착한 것만 켠다.
 *
 * 배열은 **단계 순서**다. 앞쪽이 낮은 단계, 뒤쪽이 높은 단계에 붙는다.
 * 아이템 280개에 모델이 하나씩 있을 수는 없으니, 20단계를 목록 길이만큼
 * 나눠 쓴다 — 절반쯤 오면 무기가 눈에 띄게 바뀐다.
 */
interface GearMeshes {
  weapon: string[];
  offhand: string[];
  helmet: string | null;
}

const GEAR_MESHES: Record<string, GearMeshes> = {
  knight: {
    weapon: ['1H_Sword', '2H_Sword'],
    offhand: ['Badge_Shield', 'Round_Shield', 'Rectangle_Shield', 'Spike_Shield'],
    helmet: 'Knight_Helmet',
  },
  mage: {
    weapon: ['1H_Wand', '2H_Staff'],
    offhand: ['Spellbook'],
    helmet: 'Mage_Hat',
  },
  rogue: {
    weapon: ['1H_Crossbow', '2H_Crossbow'],
    offhand: ['Knife_Offhand'],
    helmet: null,
  },
  // 화살통이 이 팩에 없다. 궁수의 보조 자리는 아직 안 보인다.
  rogue_hooded: {
    weapon: ['1H_Crossbow', '2H_Crossbow'],
    offhand: [],
    helmet: null,
  },
  barbarian: {
    weapon: ['1H_Axe', '2H_Axe'],
    offhand: ['Barbarian_Round_Shield'],
    helmet: 'Barbarian_Hat',
  },
  /**
   * VARCO 로 만든 기사 — **갈아끼울 메시가 없다.**
   *
   * 이미지 한 장에서 만들어진 모델이라 검·방패·투구가 몸과 한 덩어리로 구워져
   * 있다(메시 1개, 머티리얼 1개). 그래서 장비를 바꿔도 겉모습이 안 바뀐다.
   * 빈 표를 적어 두는 건 이게 누락이 아니라 **사실**임을 남기기 위해서다.
   */
  varco_knight: { weapon: [], offhand: [], helmet: null },
  // VARCO 마법사도 같다 — 지팡이·모자가 몸에 구워져 있다
  varco_mage: { weapon: [], offhand: [], helmet: null },
  varco_archer: { weapon: [], offhand: [], helmet: null },
  // 격투가는 애초에 맨손이다 — 도복·붕대가 몸에 구워져 있다
  varco_fighter: { weapon: [], offhand: [], helmet: null },
};

/** 20단계를 목록 길이만큼 나눠 몇 번째 모양을 쓸지 고른다 */
function variantFor(itemId: string, count: number): number {
  if (count <= 1) return 0;
  const item = getItem(itemId);
  const tier = item ? tierIndexOf(item) : 0;
  return Math.min(count - 1, Math.floor((tier / 20) * count));
}

/** 사람 모델 하나 */
export function createModelCharacterRig(models: Models, profile: ClassProfile): CharacterRig {
  const source = models.characters[profile.model!];
  if (!source) throw new Error('없는 모델: ' + profile.model);

  // SkeletonUtils.clone 은 뼈대까지 복제한다. Object3D.clone 은 뼈대를 공유해서
  // 두 캐릭터가 같은 포즈로 붙어 움직인다.
  const root = cloneSkinned(source.scene) as THREE.Group;

  const group = new THREE.Group();
  group.add(root);
  const scale = profile.scale ?? 1;
  const fit = source.height > 0 ? HUMAN_HEIGHT / source.height : 1;
  group.scale.setScalar(fit * scale);

  const mixer = new THREE.AnimationMixer(root);

  /**
   * 클립 고르기.
   *
   * KayKit 다섯은 뼈대가 같아 **클립을 공유한다**(models.clips). 이름이 팩 그대로라
   * 정확한 이름으로 집으면 된다. 반면 VARCO 로 만든 모델은 제 클립을 파일 안에
   * 들고 오고 이름 규칙이 다르므로(`Idle` `Run` `Attack`) **역할로** 찾는다.
   *
   * 없는 역할은 null 이고, 부르는 쪽이 폴백을 갖고 있다 — 사망 클립이 없으면
   * die() 가 몸을 옆으로 눕힌다.
   */
  const own = source.clips;
  const act = (name: string, ...roles: string[]): THREE.AnimationAction | null => {
    const clip = own ? pickClip(own, name, ...roles) : models.clips[name];
    return clip ? mixer.clipAction(clip) : null;
  };

  const idle = act(CLIP.idle, 'idle');
  const run = act(CLIP.run, 'run', 'walk');
  const attack = act(profile.attackClip ?? CLIP.melee, 'attack');
  const death = act(CLIP.death, 'death');
  const runClipSpeed = RUN_CLIP_SPEEDS[profile.model!] ?? RUN_CLIP_SPEED;
  const attackTrim = ATTACK_CLIPS[profile.model!];

  idle?.play();
  if (run) {
    run.play();
    run.setEffectiveWeight(0);
  }
  if (attack) {
    attack.setLoop(THREE.LoopOnce, 1);
    attack.clampWhenFinished = false;
  }
  // 사망은 짐승과 같은 규칙 — 한 번만 재생하고 마지막 자세에서 멈춘다.
  // 멈추지 않으면 쓰러졌다가 슬그머니 일어선다.
  if (death) {
    death.setLoop(THREE.LoopOnce, 1);
    death.clampWhenFinished = true;
  }

  let moveBlend = 0;
  let dying = false;
  /** 공격 클립을 걷기 때문에 끊었는가 (`ATTACK_CUT_SPEED`) */
  let attackCut = false;

  // --- 장비 메시 ---
  const meshes = GEAR_MESHES[profile.model!] ?? { weapon: [], offhand: [], helmet: null };
  const parts = new Map<string, THREE.Object3D>();
  for (const name of [...meshes.weapon, ...meshes.offhand, ...(meshes.helmet ? [meshes.helmet] : [])]) {
    const node = root.getObjectByName(name);
    if (node) {
      node.visible = false;
      parts.set(name, node);
    }
  }

  const show = (name: string | null | undefined): void => {
    if (name) {
      const node = parts.get(name);
      if (node) node.visible = true;
    }
  };

  // 갑옷·신발로 물들일 메시와, 물들이기 전 원래 머티리얼
  const skin = new Map<THREE.Mesh, { material: THREE.Material; leg: boolean }>();
  root.traverse((o) => {
    const mesh = o as THREE.Mesh;
    if (!mesh.isMesh || Array.isArray(mesh.material)) return;
    if (BODY_PARTS.some((suffix) => mesh.name.endsWith(suffix))) {
      skin.set(mesh, { material: mesh.material, leg: false });
    } else if (LEG_PARTS.some((suffix) => mesh.name.endsWith(suffix))) {
      skin.set(mesh, { material: mesh.material, leg: true });
    }
  });

  const applyGear = (gear: GearLook): void => {
    for (const node of parts.values()) node.visible = false;
    if (gear.weapon) show(meshes.weapon[variantFor(gear.weapon, meshes.weapon.length)]);
    if (gear.offhand) show(meshes.offhand[variantFor(gear.offhand, meshes.offhand.length)]);
    if (gear.helmet) show(meshes.helmet);

    // 화살통은 보조 자리에 낀 게 있을 때만 등에 걸린다
    if (quiver) quiver.visible = Boolean(gear.offhand) && meshes.offhand.length === 0;

    // 갑옷·신발 — 안 낀 자리는 원래 색으로 되돌린다
    const armor = gear.armor ? tierColorOf(gear.armor) : null;
    const boots = gear.boots ? tierColorOf(gear.boots) : null;
    for (const [mesh, origin] of skin) {
      const color = origin.leg ? boots : armor;
      mesh.material = color ? tintedMaterial(origin.material, color, ARMOR_SOFTNESS) : origin.material;
    }
  };

  /**
   * 화살통.
   *
   * 이 팩의 도적 모델에는 화살통이 없다. 별도 파일을 받아 가슴 뼈에 매단다 —
   * 같은 팩이라 크기와 텍스처가 저절로 맞고, 뼈에 붙으니 달릴 때 같이 흔들린다.
   * 화살통 자리(보조)가 모델 안에 따로 있는 직업은 그걸 쓰므로 붙이지 않는다.
   */
  let quiver: THREE.Object3D | null = null;
  if (meshes.offhand.length === 0 && models.accessories.quiver) {
    const chest = root.getObjectByName('chest');
    if (chest) {
      quiver = models.accessories.quiver.clone(true);
      quiver.position.set(0.06, 0.1, -0.16);
      quiver.rotation.set(0.35, 0, -0.4);
      quiver.visible = false;
      chest.add(quiver);
    }
  }

  // NPC 는 장비 정보가 없다. 프로필에 적힌 기본값으로 세운다.
  const npc = profile.npcGear;
  if (npc) {
    show(npc.weapon !== undefined ? meshes.weapon[npc.weapon] : null);
    show(npc.offhand !== undefined ? meshes.offhand[npc.offhand] : null);
    if (npc.helmet) show(meshes.helmet);
  }

  /** 지금 켜져 있는 무기 노드 (없으면 null) */
  const visibleWeapon = (): THREE.Object3D | null => {
    for (const name of meshes.weapon) {
      const node = parts.get(name);
      if (node?.visible) return node;
    }
    return null;
  };

  /** 무기 노드의 지역 경계 상자. 모양은 안 바뀌므로 한 번만 재고 기억한다 */
  const boxCache = new Map<THREE.Object3D, THREE.Box3 | null>();
  const localBox = (node: THREE.Object3D): THREE.Box3 | null => {
    const hit = boxCache.get(node);
    if (hit !== undefined) return hit;
    const mesh = node as THREE.Mesh;
    const geo = mesh.isMesh ? mesh.geometry : null;
    if (geo) geo.computeBoundingBox();
    const box = geo?.boundingBox ?? null;
    boxCache.set(node, box);
    return box;
  };

  /**
   * 맨손일 때 궤적을 그릴 길이 (m).
   *
   * 무기 궤적보다 확실히 짧아야 한다 — 길면 안 보이는 칼을 든 것처럼 보인다.
   * 그렇다고 안 그리면 안 된다: 장비를 안 낀 캐릭터가 대부분이라,
   * 무기가 있을 때만 그리면 이 기능이 거의 항상 죽어 있는 셈이 된다.
   */
  const FIST_REACH = 0.34;

  // 맨손 궤적을 매달 뼈. KayKit 은 무기를 handslot 에 붙이고, 방향은
  // 아래팔 → 손 으로 잡는다 (주먹이 뻗어 나가는 쪽).
  const side = (profile.weaponHand ?? 'R').toLowerCase();
  const long = side === 'l' ? 'Left' : 'Right';
  // 뼈 이름은 팩마다 다르다 — KayKit 은 `handslotr`, VARCO 는 `RightHand` 다.
  // 못 찾으면 궤적이 통째로 안 그려지므로 후보를 늘어놓고 먼저 잡히는 걸 쓴다.
  const bone = (...names: string[]): THREE.Object3D | null => {
    for (const name of names) {
      const found = root.getObjectByName(name);
      if (found) return found;
    }
    return null;
  };
  const handSlot = bone('handslot' + side, 'hand' + side, long + 'Hand');
  const foreArm = bone('lowerarm' + side, 'wrist' + side, long + 'ForeArm');

  const edgeCenter = new THREE.Vector3();
  const edgeSize = new THREE.Vector3();
  const edgeHand = new THREE.Vector3();
  const edgeSwap = new THREE.Vector3();
  const hitFlash = new HitFlash(group);

  return {
    group,
    headHeight: HUMAN_HEIGHT * scale + 0.18,

    flash(): void {
      hitFlash.flash();
    },

    setGear(gear: GearLook): void {
      applyGear(gear);
    },

    swing(): void {
      if (!attack) return;
      attack.reset(); // 페이드 중이었으면 여기서 풀린다 (stopFading)
      attackCut = false;
      if (attackTrim) {
        attack.time = attackTrim.from;
        attack.timeScale = attackTrim.speed;
      }
      attack.setEffectiveWeight(1);
      attack.play();
    },

    die(): void {
      if (dying) return;
      dying = true;
      attack?.stop();
      loop(idle, 0);
      loop(run, 0);
      if (death) {
        death.reset();
        death.setEffectiveWeight(1);
        death.play();
      } else {
        // 클립이 없는 폴백(에셋 미다운로드) — 옆으로 눕힌다
        group.rotation.z = Math.PI * 0.5;
      }
    },

    revive(): void {
      if (!dying) return;
      dying = false;
      death?.stop();
      group.rotation.z = 0;
      idle?.reset().play();
      if (run) run.reset().play();
    },

    /**
     * 지금 보이는 무기의 양 끝을 월드 좌표로 준다 (궤적용).
     *
     * 무기 모양을 종류별로 적어 두지 않는다 — 팩마다 칼·도끼·지팡이가 다르고
     * 장비 단계마다 메시가 바뀐다. 대신 **경계 상자의 가장 긴 축**을 날로 본다.
     * 손 뼈에서 먼 쪽이 끝이다.
     */
    weaponEdge(base: THREE.Vector3, tip: THREE.Vector3): boolean {
      const node = visibleWeapon();

      // --- 맨손 ---
      // 장비를 안 낀 캐릭터가 대부분이다. 무기가 있을 때만 그리면 이 기능은
      // 거의 항상 안 보인다. 주먹 앞으로 짧게 긋는다.
      if (!node) {
        if (!handSlot) return false;
        handSlot.updateWorldMatrix(true, false);
        base.setFromMatrixPosition(handSlot.matrixWorld);
        if (foreArm) {
          foreArm.updateWorldMatrix(true, false);
          edgeHand.setFromMatrixPosition(foreArm.matrixWorld);
          tip.subVectors(base, edgeHand);
        } else {
          tip.set(0, 0, 0);
        }
        // 팔이 접혀 길이가 0 이 되는 순간이 있다. 그때는 위로 세운다.
        if (tip.lengthSq() < 1e-8) tip.set(0, 1, 0);
        tip.normalize().multiplyScalar(FIST_REACH).add(base);
        return true;
      }

      const box = localBox(node);
      if (!box) return false;

      // 뼈 행렬은 렌더 직전에 갱신된다. 궤적은 그 전에 물어보므로 여기서
      // 이 노드만 직접 올려 준다 — 안 하면 한 프레임 뒤처진 자리에 그린다.
      node.updateWorldMatrix(true, false);

      box.getCenter(edgeCenter);
      box.getSize(edgeSize);
      // 가장 긴 축 하나를 고른다
      const axis =
        edgeSize.x >= edgeSize.y && edgeSize.x >= edgeSize.z
          ? 'x'
          : edgeSize.y >= edgeSize.z
            ? 'y'
            : 'z';
      const half = edgeSize[axis] / 2;
      base.copy(edgeCenter);
      tip.copy(edgeCenter);
      base[axis] -= half;
      tip[axis] += half;
      base.applyMatrix4(node.matrixWorld);
      tip.applyMatrix4(node.matrixWorld);

      // 손에서 먼 쪽이 칼끝이다. 축 방향은 모델마다 뒤집혀 있다.
      node.parent?.getWorldPosition(edgeHand);
      if (base.distanceToSquared(edgeHand) > tip.distanceToSquared(edgeHand)) {
        edgeSwap.copy(base);
        base.copy(tip);
        tip.copy(edgeSwap);
      }
      return true;
    },

    update(dt: number, speed: number): void {
      hitFlash.update(dt);
      // 죽어 있으면 사망 클립만 돌린다. 이동 가중치를 계속 섞으면
      // 쓰러진 자세 위로 대기 동작이 얹혀 시체가 숨을 쉰다.
      if (dying) {
        mixer.update(dt);
        return;
      }

      const k = 1 - Math.exp(-BLEND_RATE * dt);
      moveBlend += (THREE.MathUtils.clamp(speed / RUN_SPEED, 0, 1) - moveBlend) * k;

      // 다시 걷기 시작하면 남은 공격 클립을 끊는다 (`ATTACK_CUT_SPEED`).
      // 경직이 클립보다 짧아서, 안 끊으면 달리면서 계속 휘두른다.
      if (attack && !attackCut && attack.isRunning() && speed > ATTACK_CUT_SPEED) {
        attackCut = true;
        attack.fadeOut(ATTACK_CUT_FADE);
      }

      // 자를 끝(`ATTACK_CLIPS` 의 `to`)이 있으면 거기서 뺀다 — 격투가는 뒤에 붙은
      // 뒤돌려차기까지 틀면 한 대에 발이 두 번 나간다.
      if (attack && !attackCut && attackTrim?.to !== undefined && attack.time >= attackTrim.to) {
        attackCut = true;
        attack.fadeOut(ATTACK_CUT_FADE);
      }

      // 공격 중에는 이동 동작을 눌러둔다. 아예 0 으로 하면 하체가 굳어 보인다.
      // 끊는 중인 것은 공격으로 치지 않는다 — 안 그러면 페이드가 끝날 때까지 하체가 눌린다.
      const attacking = attack?.isRunning() === true && !attackCut;
      const base = attacking ? ATTACK_LOWER : 1;
      loop(idle, (1 - moveBlend) * base);
      loop(run, moveBlend * base);

      // 재생 속도를 실제 이동 속도에 맞춘다. 안 그러면 발이 미끄러진다.
      if (run) run.setEffectiveTimeScale(Math.max(0.35, speed / runClipSpeed));

      mixer.update(dt);
    },

    dispose(): void {
      mixer.stopAllAction();
      mixer.uncacheRoot(root);
      group.clear();
    },
  };
}

/**
 * 짐승 모델 하나.
 *
 * 사람과 달리 종류마다 뼈대도 클립 이름도 다르다. 그래서 클립은 이름이 아니라
 * **역할로 찾는다**(pickClip) — 달리기가 어떤 팩에서는 `Run`, 네발짐승 팩에서는
 * `Gallop` 이다.
 *
 * 모델이 아직 안 왔으면 null 을 준다. 부르는 쪽이 절차적 리그로 떨어뜨린다.
 */
export function createModelMonsterRig(models: Models, kind: MonsterKind): MonsterRig | null {
  const beast = models.beasts[kind.look];
  if (!beast) return null;

  const root = cloneSkinned(beast.model.scene) as THREE.Group;

  const target = beastHeight(kind.look, kind.scale);
  const fit = beast.model.height > 0 ? target / beast.model.height : 1;

  const group = new THREE.Group();
  const holder = new THREE.Group();
  holder.add(root);
  group.add(holder);
  group.scale.setScalar(fit);

  // 같은 종류끼리는 색이 같으므로 머티리얼을 공유한다 — 마리마다 clone 하면
  // 늑대 열 마리에 머티리얼이 열 벌 생긴다.
  root.traverse((o) => {
    const mesh = o as THREE.Mesh;
    if (!mesh.isMesh) return;
    const wasArray = Array.isArray(mesh.material);
    const source = wasArray ? (mesh.material as THREE.Material[]) : [mesh.material as THREE.Material];
    const tinted = source.map((m) => tintedMaterial(m, kind.bodyColor));
    mesh.material = wasArray ? tinted : tinted[0]!;
  });

  const mixer = new THREE.AnimationMixer(root);
  const act = (clip: THREE.AnimationClip | null): THREE.AnimationAction | null =>
    clip ? mixer.clipAction(clip) : null;

  // 팩마다 이름이 제각각이다. 벌은 대기가 'Flying' 뿐이고, 개구리는 걷지 않고
  // 뛴다('Jump'). 없는 걸 찾다 끝나면 그 짐승만 굳은 채로 서 있게 된다.
  const idle = act(pickClip(beast.clips, 'idle', 'flying'));
  const move = act(pickClip(beast.clips, 'gallop', 'run', 'walk', 'flying', 'jump'));
  const attack = act(pickClip(beast.clips, 'attack'));
  const death = act(pickClip(beast.clips, 'death'));

  idle?.play();
  if (move) {
    move.play();
    move.setEffectiveWeight(0);
  }
  for (const once of [attack, death]) {
    if (!once) continue;
    once.setLoop(THREE.LoopOnce, 1);
    once.clampWhenFinished = true;
  }

  /** 이 속도에서 이동 동작이 다 섞인다 */
  const moveClipSpeed = 3;
  // 재생 속도는 발이 안 미끄러지는 값에 맞춘다. 잰 값이 없으면 섞는 기준과 같다.
  // 잰 값을 섞는 기준으로까지 쓰면 오우거(7.1)는 추격 속도(3.6)에서 반쯤 선 채로 달린다.
  const measured = BEAST_RUN_CLIP_SPEEDS[kind.look];
  const runClipSpeed = measured ? (measured * target) / HUMAN_HEIGHT : moveClipSpeed;
  let moveBlend = 0;
  let dying = false;
  const beastFlash = new HitFlash(group);
  /** 이번 휘두르기가 창(`BEAST_ATTACK_WINDOWS`) 끝까지 갔는가 */
  let swingDone = true;
  const window = BEAST_ATTACK_WINDOWS[kind.look] ?? BEAST_ATTACK_FALLBACK;

  return {
    group,
    headHeight: beastHeadHeight(kind.look, kind.scale),

    flash(): void {
      beastFlash.flash();
    },

    /**
     * 한 번 휘두른다. **서버가 사람을 때린 순간**(`hit` 메시지) 불린다 —
     * 상태(`state === 'attack'`)로 트는 것이 아니다.
     *
     * 상태로 틀면 사거리 안에 서 있는 내내 클립이 다시 감기는데, 그 재생이
     * 경직(`MONSTER_SWING_MS`)과 어긋나서 **경직이 아닌 때에 시작된 휘두르기가
     * 쫓아가는 동안 이어진다** — 그게 "움직이면서 공격 모션" 으로 보였다.
     * 때린 순간에 맞춰 틀면 클립이 도는 구간과 서버가 세워 두는 구간이 같다.
     */
    swing(): void {
      if (!attack) return;
      attack.reset();
      attack.time = window.from;
      attack.setEffectiveWeight(1);
      attack.play();
      swingDone = false;
    },

    update(dt: number, state: string, speed: number): void {
      beastFlash.update(dt);
      if (state === 'dead') {
        if (!dying) {
          dying = true;
          loop(idle, 0);
          loop(move, 0);
          attack?.stop();
          swingDone = true; // 쓰러진 뒤에 남은 휘두르기를 다시 끝내려 들지 않게
          if (death) {
            death.reset();
            death.setEffectiveWeight(1);
            death.play();
          }
        }
        // 사망 클립이 없는 팩은 옆으로 쓰러뜨린다
        if (!death) holder.rotation.z = Math.min(Math.PI * 0.5, holder.rotation.z + dt * 4);
        mixer.update(dt);
        return;
      }

      if (dying) {
        // 리스폰 — 죽은 자세를 풀고 처음으로 돌린다
        dying = false;
        death?.stop();
        holder.rotation.z = 0;
        idle?.reset().play();
        if (move) move.reset().play();
      }

      const k = 1 - Math.exp(-BLEND_RATE * dt);
      moveBlend += (Math.min(1, speed / moveClipSpeed) - moveBlend) * k;

      /**
       * **창 끝까지 갔으면 거기서 끝낸다.** ★
       *
       * 짐승의 공격 클립은 여러 번 할퀴는 긴 클립이라(오우거 3.73초) 끝까지 두면
       * 서버가 세워 두는 시간(`MONSTER_SWING_MS`)을 한참 넘겨 **쫓아가면서 계속
       * 휘두른다.** 한 번 휘두르는 만큼만 틀고 섞어 뺀다 — 이동 때문에 끊는 게
       * 아니라 **동작이 끝나서** 끝나는 것이라, 도망가도 동작은 온전히 보인다.
       */
      if (attack && !swingDone && attack.time >= window.to) {
        swingDone = true;
        attack.fadeOut(ATTACK_CUT_FADE);
      }

      // 휘두르는 동안에는 이동 동작을 눌러둔다 (끝나고 빠지는 중인 것은 빼고)
      const striking = attack?.isRunning() === true && !swingDone;
      const base = striking ? ATTACK_LOWER : 1;
      loop(idle, (1 - moveBlend) * base);
      loop(move, moveBlend * base);
      if (move) move.setEffectiveTimeScale(Math.max(0.4, speed / runClipSpeed));

      mixer.update(dt);
    },

    dispose(): void {
      mixer.stopAllAction();
      mixer.uncacheRoot(root);
      // 머티리얼은 종류끼리 공유하고, 지오메트리는 원본 모델의 것을 참조한다
      group.clear();
    },
  };
}
