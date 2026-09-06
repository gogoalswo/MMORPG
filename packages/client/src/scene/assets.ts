import * as THREE from 'three';
import { HDRLoader } from 'three/examples/jsm/loaders/HDRLoader.js';
import { KTX2Loader } from 'three/examples/jsm/loaders/KTX2Loader.js';
import { loadModels, type Models } from './models';

/**
 * 공용 에셋 로딩.
 *
 * 전부 CC0 다. ambientCG(지면 PBR 텍스처)와 Poly Haven(HDRI) 에서 받았고
 * 출처 표기 의무나 상업적 사용 제한이 없다. 목록은 docs/ASSETS.md 참고.
 *
 * 존을 넘어가도 이 텍스처들은 공유한다 — 존마다 다시 로드하면
 * 포탈을 지날 때마다 몇 MB 를 다시 디코딩하게 된다.
 */

export interface SurfaceMaps {
  map: THREE.Texture;
  normalMap: THREE.Texture;
  roughnessMap: THREE.Texture;
}

export interface Assets {
  grass: SurfaceMaps;
  dirt: SurfaceMaps;
  rock: SurfaceMaps;
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
  // 1024x1024 한 장이 VRAM 4MB 를 먹는다 (9장이면 36MB).
  // 트랜스코더가 기기가 지원하는 포맷(ASTC/BC7/ETC2...)으로 변환해준다.
  const loader = new KTX2Loader()
    .setTranscoderPath('/assets/basis/')
    .detectSupport(renderer);
  const anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());

  const surface = async (name: string): Promise<SurfaceMaps> => {
    const [map, normalMap, roughnessMap] = await Promise.all([
      loader.loadAsync(`/assets/textures/${name}_color.ktx2`),
      loader.loadAsync(`/assets/textures/${name}_normal.ktx2`),
      loader.loadAsync(`/assets/textures/${name}_rough.ktx2`),
    ]);
    return {
      map: configure(map, true, anisotropy),
      // 노멀맵과 러프니스는 색이 아니라 데이터다. sRGB 변환을 걸면 값이 틀어진다.
      normalMap: configure(normalMap, false, anisotropy),
      roughnessMap: configure(roughnessMap, false, anisotropy),
    };
  };

  // 모델은 실패해도 부팅을 막지 않는다 — 지면 텍스처가 없는 것과는 무게가 다르다
  const modelsPromise = loadModels().catch((err: unknown) => {
    console.warn('[assets] 캐릭터 모델을 못 불러왔다. 절차적 리그로 진행한다.', err);
    return null;
  });

  const [grass, dirt, rock, hdr] = await Promise.all([
    surface('grass'),
    surface('dirt'),
    surface('rock'),
    // HDRI 는 PMREM 이 어차피 흐리게 굽는다. 1k 로 충분하다.
    new HDRLoader().loadAsync('/assets/hdri/sky_1k.hdr'),
  ]);

  // 실제 하늘 사진에서 환경광을 굽는다. 절차적 그라디언트와 달리
  // 방향마다 색과 밝기가 달라서 금속 표면에 그럴듯한 반사가 생긴다.
  hdr.mapping = THREE.EquirectangularReflectionMapping;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const target = pmrem.fromEquirectangular(hdr);
  hdr.dispose();
  pmrem.dispose();
  // 트랜스코딩용 워커를 정리한다 (로딩은 부팅 때 한 번뿐)
  loader.dispose();

  const all = [grass, dirt, rock];
  const models = await modelsPromise;

  return {
    grass,
    dirt,
    rock,
    environment: target.texture,
    models,
    dispose() {
      models?.dispose();
      for (const s of all) {
        s.map.dispose();
        s.normalMap.dispose();
        s.roughnessMap.dispose();
      }
      target.dispose();
    },
  };
}
