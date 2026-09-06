import * as THREE from 'three';
import { clone as cloneSkinned } from 'three/examples/jsm/utils/SkeletonUtils.js';
import { RUN_SPEED, getItem, tierIndexOf, type MonsterKind } from '@mmo/shared';
import { CLIP, pickClip, type Models } from '../scene/models';
import type { CharacterRig, ClassProfile, GearLook } from './characterRig';
import type { MonsterRig } from './monsterRig';

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
/** 공격 중에 남겨두는 이동 동작의 비중 */
const ATTACK_LOWER = 0.18;
/**
 * 사람 키(m).
 *
 * 모델 팩마다 단위가 다르다 — 이 팩은 한 칸이 2.5 쯤이다. 우리 세계는
 * 절차적 리그 때부터 1.8m 를 사람 키로 잡아왔고, 이동 속도·사거리·카메라
 * 거리가 전부 그 위에 맞춰져 있다. 그래서 **모델을 세계에 맞춘다.**
 */
const HUMAN_HEIGHT = 1.8;
/**
 * 짐승 종류별 키(m).
 *
 * 높이로 크기를 맞추므로 여기 값이 곧 화면에서 보이는 크기다. 전부 같은 값으로
 * 두면 거미가 티라노사우루스만 해진다. 여기에 몬스터의 `scale`(레벨과 강함으로
 * 정해진다)이 곱해지므로, 보스는 자동으로 더 커진다.
 */
const BEAST_HEIGHT: Record<string, number> = {
  wolf: 0.85,
  husky: 0.8,
  bull: 1.15,
  stag: 1.2,
  spider: 0.65,
  velociraptor: 1.35,
  triceratops: 1.5,
  stegosaurus: 1.5,
  trex: 2.4,
};
const BEAST_HEIGHT_DEFAULT = 0.9;

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

function tintedMaterial(source: THREE.Material, color: string): THREE.Material {
  const key = `${source.uuid}#${color}`;
  const found = tintCache.get(key);
  if (found) return found;

  const copy = (source as THREE.MeshStandardMaterial).clone();
  // 색을 그냥 곱하면 어두워진다 — 늑대 색(#7b6a55)을 곱하면 밝기가 절반이 되어
  // 텍스처의 명암까지 뭉개진 검은 덩어리가 된다. 밝기는 1 로 되돌리고 색조만
  // 가져온 뒤, 흰색 쪽으로 조금 물러선다.
  const tint = new THREE.Color(color);
  const peak = Math.max(tint.r, tint.g, tint.b, 0.001);
  tint.multiplyScalar(1 / peak).lerp(WHITE, 0.3);
  copy.color.multiply(tint);
  tintCache.set(key, copy);
  return copy;
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
 * 아이템 260개에 모델이 하나씩 있을 수는 없으니, 20단계를 목록 길이만큼
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
  const make = (name: string): THREE.AnimationAction | null => {
    const clip = models.clips[name];
    return clip ? mixer.clipAction(clip) : null;
  };

  const idle = make(CLIP.idle);
  const run = make(CLIP.run);
  const attack = make(profile.attackClip ?? CLIP.melee);

  idle?.play();
  if (run) {
    run.play();
    run.setEffectiveWeight(0);
  }
  if (attack) {
    attack.setLoop(THREE.LoopOnce, 1);
    attack.clampWhenFinished = false;
  }

  let moveBlend = 0;

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

  const applyGear = (gear: GearLook): void => {
    for (const node of parts.values()) node.visible = false;
    if (gear.weapon) show(meshes.weapon[variantFor(gear.weapon, meshes.weapon.length)]);
    if (gear.offhand) show(meshes.offhand[variantFor(gear.offhand, meshes.offhand.length)]);
    if (gear.helmet) show(meshes.helmet);
  };

  // NPC 는 장비 정보가 없다. 프로필에 적힌 기본값으로 세운다.
  const npc = profile.npcGear;
  if (npc) {
    show(npc.weapon !== undefined ? meshes.weapon[npc.weapon] : null);
    show(npc.offhand !== undefined ? meshes.offhand[npc.offhand] : null);
    if (npc.helmet) show(meshes.helmet);
  }

  return {
    group,
    headHeight: HUMAN_HEIGHT * scale + 0.18,

    setGear(gear: GearLook): void {
      applyGear(gear);
    },

    swing(): void {
      if (!attack) return;
      attack.reset();
      attack.setEffectiveWeight(1);
      attack.play();
    },

    update(dt: number, speed: number): void {
      const k = 1 - Math.exp(-BLEND_RATE * dt);
      moveBlend += (THREE.MathUtils.clamp(speed / RUN_SPEED, 0, 1) - moveBlend) * k;

      // 공격 중에는 이동 동작을 눌러둔다. 아예 0 으로 하면 하체가 굳어 보인다.
      const attacking = attack?.isRunning() === true;
      const base = attacking ? ATTACK_LOWER : 1;
      loop(idle, (1 - moveBlend) * base);
      loop(run, moveBlend * base);

      // 재생 속도를 실제 이동 속도에 맞춘다. 안 그러면 발이 미끄러진다.
      if (run) run.setEffectiveTimeScale(Math.max(0.35, speed / RUN_CLIP_SPEED));

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

  const target = (BEAST_HEIGHT[kind.look] ?? BEAST_HEIGHT_DEFAULT) * kind.scale;
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

  const idle = act(pickClip(beast.clips, 'idle'));
  const move = act(pickClip(beast.clips, 'gallop', 'run', 'walk'));
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

  /** 이 클립이 상정한 이동 속도. 실제 속도에 맞춰 재생 속도를 조절한다 */
  const moveClipSpeed = 3;
  let moveBlend = 0;
  let dying = false;

  return {
    group,
    headHeight: target + 0.25,

    update(dt: number, state: string, speed: number): void {
      if (state === 'dead') {
        if (!dying) {
          dying = true;
          loop(idle, 0);
          loop(move, 0);
          attack?.stop();
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

      // 공격 중에는 이동 동작을 눌러둔다
      const striking = attack?.isRunning() === true;
      const base = striking ? ATTACK_LOWER : 1;
      loop(idle, (1 - moveBlend) * base);
      loop(move, moveBlend * base);
      if (move) move.setEffectiveTimeScale(Math.max(0.4, speed / moveClipSpeed));

      // 서버는 공격을 '상태'로 보낸다. 한 번 재생이 끝나면 아직 때리는 중일 때
      // 다시 튼다 — 상태가 바뀌기를 기다리면 한 대 치고 굳는다.
      if (state === 'attack' && attack && !attack.isRunning()) {
        attack.reset();
        attack.setEffectiveWeight(1);
        attack.play();
      }

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
