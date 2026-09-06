import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

/**
 * 캐릭터·몬스터 3D 모델.
 *
 * 예전에는 캡슐과 상자를 쌓아 사람을 만들었다. 아무리 잘 움직여도 마네킹이라
 * 한계가 분명해서, **리깅된 모델과 애니메이션 클립**으로 갈아탔다.
 * 전부 CC0 이고 출처는 docs/ASSETS.md 에 있다.
 *
 * 두 종류를 다르게 다룬다.
 *  - **사람**: 다섯 모델이 같은 41본 뼈대를 써서 클립을 공유한다. 어느 존에서든
 *    필요하므로(다른 플레이어의 직업을 고를 수 없다) 부팅 때 전부 받는다.
 *  - **짐승**: 종류마다 뼈대도 클립도 다르다. 한 사냥터에 두세 종뿐이므로
 *    **존을 옮길 때 필요한 것만** 받는다. 전부 받으면 3MB 를 마을에서도 들고 있게 된다.
 */

/** 파일 이름 = 모델 이름 */
export const CHARACTER_MODELS = ['knight', 'mage', 'rogue', 'rogue_hooded', 'barbarian'] as const;

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
  /** 다섯 사람 모델이 공유하는 클립 */
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

  const entries = await Promise.all(
    CHARACTER_MODELS.map(async (name) => {
      const gltf = await loader.loadAsync(`/assets/models/${name}.glb`);
      return [name, gltf] as const;
    })
  );

  const characters: Record<string, LoadedModel> = {};
  let clips: Record<string, THREE.AnimationClip> = {};

  for (const [name, gltf] of entries) {
    const scene = gltf.scene as THREE.Group;
    prepare(scene);
    characters[name] = { scene, ...measure(scene) };
    if (gltf.animations.length > 0) clips = byName(gltf.animations);
  }

  // 화살통 — 없어도 게임은 돈다. 궁수 등이 비어 보일 뿐이다.
  const accessories: Record<string, THREE.Object3D> = {};
  try {
    const quiver = await loader.loadAsync('/assets/models/accessories/quiver.gltf');
    prepare(quiver.scene);
    accessories.quiver = quiver.scene;
  } catch (err) {
    console.warn('[models] 화살통을 못 불러왔다', err);
  }

  const beasts: Record<string, Beast> = {};
  // 같은 짐승을 동시에 두 번 받지 않도록 진행 중인 것도 기억한다
  const pending = new Map<string, Promise<void>>();

  async function fetchBeast(name: string): Promise<void> {
    try {
      const gltf = await loader.loadAsync(`/assets/models/${name}.glb`);
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
