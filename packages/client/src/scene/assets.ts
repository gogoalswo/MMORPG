import * as THREE from 'three';
import { HDRLoader } from 'three/examples/jsm/loaders/HDRLoader.js';
import { KTX2Loader } from 'three/examples/jsm/loaders/KTX2Loader.js';
import { GROUND_KINDS, type GroundKind } from '@mmo/shared';
import { loadModels, type Models } from './models';

/**
 * 공용 에셋 로딩.
 *
 * 바닥 텍스처 7장은 바르코(VARCO)로 만든 타일 이미지다 — 받아 온 게 아니라
 * 우리가 만든 것이라 CC0 가 아니고 약관이 걸린다. HDRI 는 Poly Haven(CC0).
 * 목록은 docs/ASSETS.md 참고.
 *
 * 존을 넘어가도 이 텍스처들은 공유한다 — 존마다 다시 로드하면
 * 차원문을 지날 때마다 다시 디코딩하게 된다. 일곱 장을 **부팅 때 전부** 받는다.
 * 512² KTX2 라 합쳐도 작고, 다 받아 두면 buildZoneScene 이 동기로 남는다.
 */

/**
 * 바닥 한 종류.
 *
 * 받은 이미지가 색 한 장뿐이라 러프니스 맵이 없다 — 러프니스는 종류마다
 * 상수로 준다(ground.ts 의 LOOKS). 노멀맵은 빌드 때 밝기에서 만든다
 * (scripts/build-ground-textures.mjs).
 */
export interface GroundMaps {
  map: THREE.Texture;
  normalMap: THREE.Texture;
}

export interface Assets {
  grounds: Record<GroundKind, GroundMaps>;
  /** PMREM 으로 구운 환경광 */
  environment: THREE.Texture;
  /**
   * 캐릭터·몬스터 모델.
   *
   * **없어도 게임은 돈다.** 모델은 저장소에 커밋하지 않아서, 새로 클론하고
   * scripts/fetch-assets.sh 를 아직 안 돌린 사람은 이게 null 이다.
   * 그때는 절차적으로 만든 리그로 떨어진다.
   */
  models: Models | null;
  dispose(): void;
}

function configure(tex: THREE.Texture, srgb: boolean, anisotropy: number): THREE.Texture {
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  tex.anisotropy = anisotropy;
  return tex;
}

export async function loadAssets(renderer: THREE.WebGLRenderer): Promise<Assets> {
  // KTX2 는 압축된 채로 GPU 에 올라간다. JPEG 은 RGBA 로 풀려서
  // 한 장이 그대로 VRAM 을 먹는다. 트랜스코더가 기기가 지원하는
  // 포맷(ASTC/BC7/ETC2...)으로 변환해준다.
  const loader = new KTX2Loader()
    .setTranscoderPath(`${import.meta.env.BASE_URL}assets/basis/`)
    .detectSupport(renderer);
  const anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());

  const ground = async (kind: GroundKind): Promise<GroundMaps> => {
    const [map, normalMap] = await Promise.all([
      loader.loadAsync(`${import.meta.env.BASE_URL}assets/textures/ground_${kind}_color.ktx2`),
      loader.loadAsync(`${import.meta.env.BASE_URL}assets/textures/ground_${kind}_normal.ktx2`),
    ]);
    return {
      map: configure(map, true, anisotropy),
      // 노멀맵은 색이 아니라 데이터다. sRGB 변환을 걸면 값이 틀어진다.
      normalMap: configure(normalMap, false, anisotropy),
    };
  };

  // 모델은 실패해도 부팅을 막지 않는다 — 지면 텍스처가 없는 것과는 무게가 다르다
  const modelsPromise = loadModels().catch((err: unknown) => {
    console.warn('[assets] 캐릭터 모델을 못 불러왔다. 절차적 리그로 진행한다.', err);
    return null;
  });

  const [loaded, hdr] = await Promise.all([
    Promise.all(GROUND_KINDS.map(ground)),
    // HDRI 는 PMREM 이 어차피 흐리게 굽는다. 1k 로 충분하다.
    new HDRLoader().loadAsync(`${import.meta.env.BASE_URL}assets/hdri/sky_1k.hdr`),
  ]);
  const grounds = Object.fromEntries(GROUND_KINDS.map((kind, i) => [kind, loaded[i]!])) as Record<
    GroundKind,
    GroundMaps
  >;

  // 실제 하늘 사진에서 환경광을 굽는다. 절차적 그라디언트와 달리
  // 방향마다 색과 밝기가 달라서 금속 표면에 그럴듯한 반사가 생긴다.
  hdr.mapping = THREE.EquirectangularReflectionMapping;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const target = pmrem.fromEquirectangular(hdr);
  hdr.dispose();
  pmrem.dispose();
  // 트랜스코딩용 워커를 정리한다 (로딩은 부팅 때 한 번뿐)
  loader.dispose();

  const models = await modelsPromise;

  return {
    grounds,
    environment: target.texture,
    models,
    dispose() {
      models?.dispose();
      for (const g of Object.values(grounds)) {
        g.map.dispose();
        g.normalMap.dispose();
      }
      target.dispose();
    },
  };
}
