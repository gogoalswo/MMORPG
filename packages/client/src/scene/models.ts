import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

/**
 * 캐릭터·몬스터 3D 모델.
 *
 * 예전에는 캡슐과 상자를 쌓아 사람을 만들었다. 아무리 잘 움직여도 마네킹이라
 * 한계가 분명해서, **리깅된 모델과 애니메이션 클립**으로 갈아탔다.
 * 출처는 docs/ASSETS.md 에 있다.
 *
 * 두 종류를 다르게 다룬다.
 *  - **사람**: VARCO 셋(SOLO_MODELS). 어느 존에서든 필요하므로(다른 플레이어의
 *    직업을 고를 수 없다) 부팅 때 전부 받는다. 41본 뼈대로 클립을 나눠 쓰던
 *    KayKit 다섯은 2026-09-10 에 파일째 뺐다.
 *  - **짐승**: 종류마다 뼈대도 클립도 다르다. 한 사냥터에 두세 종뿐이므로
 *    **존을 옮길 때 필요한 것만** 받는다. 전부 받으면 3MB 를 마을에서도 들고 있게 된다.
 */

/**
 * **제 뼈대에 제 클립을 들고 오는** 사람 모델.
 *
 * VARCO(바르코) 커스텀 워크플로우로 만든 캐릭터다. KayKit 과 뼈 이름도 개수도
 * 다르므로(23본 Mixamo 계열 — Hips/Spine/LeftUpLeg/RightToeBase) 공유 클립을
 * 쓸 수 없고, 클립이 파일 안에 같이 들어 있다. 그래서 클립을 **모델마다** 들고
 * 다닌다(LoadedModel.clips) — 이걸 공유 클립에 섞으면 KayKit 넷이 통째로 굳는다.
 *
 * **없어도 부팅은 된다.** 이 파일은 저장소 밖에서 만들어지므로
 * (scripts/build-varco-character.mjs) 못 받으면 그 직업만 절차적 리그로 떨어진다.
 * KayKit 다섯과 달리 실패를 그 자리에서 삼키는 이유다.
 */
export const SOLO_MODELS = ['varco_knight', 'varco_mage', 'varco_archer', 'varco_fighter'] as const;

/** 사람 애니메이션 클립 이름 — 원본 팩의 이름을 그대로 쓴다 */
export const CLIP = {
  idle: 'Idle',
  walk: 'Walking_A',
  run: 'Running_A',
  melee: '1H_Melee_Attack_Slice_Diagonal',
  ranged: '1H_Ranged_Shoot',
  cast: 'Spellcast_Shoot',
  hit: 'Hit_A',
  death: 'Death_A',
  interact: 'Interact',
} as const;

export interface LoadedModel {
  scene: THREE.Group;
  /** 원래 크기로 두었을 때의 높이(m). 세계 크기에 맞출 때 쓴다 */
  height: number;
  /** 앞뒤 길이 */
  length: number;
  /**
   * 이 모델만의 클립. KayKit 다섯은 없다(공유 클립을 쓴다).
   *
   * 있으면 **이름이 아니라 역할로** 찾는다 — 팩마다 이름 규칙이 다르다.
   */
  clips?: Record<string, THREE.AnimationClip>;
}

export interface Beast {
  model: LoadedModel;
  /** 이 짐승만의 클립. 이름은 팩마다 달라서 pickClip 으로 고른다 */
  clips: Record<string, THREE.AnimationClip>;
}

/**
 * 캐릭터 파일 안에 없는 장비.
 *
 * 무기와 방패는 모델 안에 이미 매달려 있지만 화살통은 없다. 팩의 별도 파일을
 * 받아 등에 붙인다. 같은 팩이라 크기와 텍스처가 자동으로 맞는다.
 */
export interface Models {
  characters: Record<string, LoadedModel>;
  /** 이름 -> 붙일 물건. 못 받았으면 없다 */
  accessories: Record<string, THREE.Object3D>;
  /** KayKit 다섯이 공유하던 클립. 그 팩을 뺐으므로 비어 있다 */
  clips: Record<string, THREE.AnimationClip>;
  /** 지금까지 받아둔 짐승들 */
  beasts: Record<string, Beast>;
  /** 이 이름들이 준비될 때까지 기다린다. 이미 있는 건 다시 받지 않는다 */
  ensureBeasts(names: string[]): Promise<void>;
  dispose(): void;
}

/**
 * 역할에 맞는 클립을 고른다.
 *
 * 팩마다 이름이 제각각이다 — `Idle`, `TRex_Idle`, `Spider_Idle`, 달리기는
 * `Run` 이기도 하고 네발짐승은 `Gallop` 이다. 부르는 쪽이 그걸 다 알 수는 없으니
 * **역할로 찾는다.** 정확히 일치하는 게 있으면 그걸, 없으면 포함하는 것을 쓴다
 * (`Idle` 이 `Idle_2` 보다 먼저 잡혀야 한다).
 */
export function pickClip(
  clips: Record<string, THREE.AnimationClip>,
  ...roles: string[]
): THREE.AnimationClip | null {
  const names = Object.keys(clips);
  for (const role of roles) {
    const want = role.toLowerCase();
    const exact = names.find((n) => n.toLowerCase() === want);
    if (exact) return clips[exact]!;
    const ends = names.find((n) => n.toLowerCase().endsWith('_' + want));
    if (ends) return clips[ends]!;
    const has = names.find((n) => n.toLowerCase().includes(want));
    if (has) return clips[has]!;
  }
  return null;
}

function measure(scene: THREE.Group): { height: number; length: number } {
  const box = new THREE.Box3().setFromObject(scene);
  const size = new THREE.Vector3();
  box.getSize(size);
  return { height: size.y, length: size.z };
}

/** 팩마다 "AnimalArmature|Idle" 처럼 앞에 뼈대 이름이 붙는다. 뒤만 쓴다 */
function byName(clips: THREE.AnimationClip[]): Record<string, THREE.AnimationClip> {
  const out: Record<string, THREE.AnimationClip> = {};
  for (const clip of clips) out[clip.name.slice(clip.name.lastIndexOf('|') + 1)] = clip;
  return out;
}

function prepare(scene: THREE.Group): void {
  // 그림자는 여기서 한 번만 켠다. 복제본은 이 설정을 그대로 물려받는다.
  scene.traverse((o) => {
    const mesh = o as THREE.Mesh;
    if (!mesh.isMesh) return;
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    // 스킨드 메시의 바운딩은 바인드 포즈 기준이라 움직이면 잘못 잘린다
    mesh.frustumCulled = false;
  });
}

export async function loadModels(): Promise<Models> {
  const loader = new GLTFLoader();

  const characters: Record<string, LoadedModel> = {};
  // KayKit 다섯이 나눠 쓰던 공유 클립. 그 팩을 2026-09-10 에 뺐으므로 비어 있다.
  const clips: Record<string, THREE.AnimationClip> = {};

  // 제 클립을 들고 오는 모델 — 한 장이 없어도 나머지는 그대로 간다.
  // 여기서 던지면 나머지 모델까지 같이 날아가 절차적 리그가 된다.
  await Promise.all(
    SOLO_MODELS.map(async (name) => {
      try {
        const gltf = await loader.loadAsync(`${import.meta.env.BASE_URL}assets/models/${name}.glb`);
        const scene = gltf.scene as THREE.Group;
        prepare(scene);
        characters[name] = { scene, ...measure(scene), clips: byName(gltf.animations) };
      } catch (err) {
        console.warn(`[models] ${name} 을 못 불러왔다 — 절차적 리그로 간다`, err);
      }
    })
  );

  // 화살통(KayKit)은 2026-09-10 에 뺐다 — 붙일 물건이 없다.
  const accessories: Record<string, THREE.Object3D> = {};

  const beasts: Record<string, Beast> = {};
  // 같은 짐승을 동시에 두 번 받지 않도록 진행 중인 것도 기억한다
  const pending = new Map<string, Promise<void>>();

  async function fetchBeast(name: string): Promise<void> {
    try {
      const gltf = await loader.loadAsync(`${import.meta.env.BASE_URL}assets/models/${name}.glb`);
      const scene = gltf.scene as THREE.Group;
      prepare(scene);
      beasts[name] = { model: { scene, ...measure(scene) }, clips: byName(gltf.animations) };
    } catch (err) {
      // 한 종류를 못 받아도 그 사냥터 전체가 막히면 안 된다 — 절차적 리그로 나온다
      console.warn(`[models] ${name} 을 못 불러왔다`, err);
    }
  }

  return {
    characters,
    accessories,
    clips,
    beasts,

    async ensureBeasts(names: string[]): Promise<void> {
      const jobs: Promise<void>[] = [];
      for (const name of new Set(names)) {
        if (beasts[name]) continue;
        let job = pending.get(name);
        if (!job) {
          job = fetchBeast(name).finally(() => pending.delete(name));
          pending.set(name, job);
        }
        jobs.push(job);
      }
      await Promise.all(jobs);
    },

    dispose(): void {
      const seen = new Set<THREE.Material | THREE.Texture>();
      const purge = (root: THREE.Object3D) =>
        root.traverse((o) => {
          const mesh = o as THREE.Mesh;
          if (!mesh.isMesh) return;
          mesh.geometry.dispose();
          for (const mat of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
            if (!mat || seen.has(mat)) continue;
            seen.add(mat);
            const std = mat as THREE.MeshStandardMaterial;
            if (std.map && !seen.has(std.map)) {
              seen.add(std.map);
              std.map.dispose();
            }
            mat.dispose();
          }
        });
      for (const model of Object.values(characters)) purge(model.scene);
      for (const beast of Object.values(beasts)) purge(beast.model.scene);
    },
  };
}
