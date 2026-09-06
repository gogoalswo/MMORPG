import * as THREE from 'three';
import type { ZoneEnv } from '@mmo/shared';

export interface Sun {
  light: THREE.DirectionalLight;
  /** 존이 바뀌면 하늘/안개/광량을 갈아끼운다 */
  applyEnv(scene: THREE.Scene, env: ZoneEnv): void;
  /** 그림자 프러스텀을 좁게 유지하려면 태양을 플레이어와 함께 움직여야 한다 */
  follow(target: THREE.Vector3): void;
}

const SUN_OFFSET = new THREE.Vector3(34, 46, 24);

export function setupLighting(scene: THREE.Scene): Sun {
  // 하늘/땅 반사광 — 그림자 안쪽이 새까맣게 죽는 걸 막는다
  // 환경맵(IBL)이 앰비언트를 담당한다. hemisphere 는 보조로만 약하게.
  const hemi = new THREE.HemisphereLight(0xffffff, 0x808080, 0.35);
  scene.add(hemi);


  const light = new THREE.DirectionalLight(0xfff2df, 2.7);
  light.position.copy(SUN_OFFSET);
  light.castShadow = true;

  const cam = light.shadow.camera;
  const extent = 42;
  cam.left = -extent;
  cam.right = extent;
  cam.top = extent;
  cam.bottom = -extent;
  cam.near = 1;
  cam.far = 170;
  light.shadow.mapSize.set(4096, 4096);
  light.shadow.bias = -0.0004;
  light.shadow.normalBias = 0.025;

  scene.add(light);
  scene.add(light.target);

  return {
    light,
    applyEnv(target: THREE.Scene, env: ZoneEnv) {
      target.background = new THREE.Color(env.skyColor);
      target.fog = new THREE.Fog(new THREE.Color(env.fogColor), env.fogNear, env.fogFar);
      hemi.color.set(env.skyColor);
      hemi.groundColor.set(env.grassDark);
      hemi.intensity = env.hemiIntensity * 0.3;
      light.intensity = env.sunIntensity;
    },
    follow(target: THREE.Vector3) {
      light.position.copy(target).add(SUN_OFFSET);
      light.target.position.copy(target);
      light.target.updateMatrixWorld();
    },
  };
}
