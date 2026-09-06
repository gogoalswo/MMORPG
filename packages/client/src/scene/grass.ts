import * as THREE from 'three';
import type { ZoneEnv } from '@mmo/shared';
import { fbm, hash2 } from './palette';
import type { PathMask } from './ground';
import { createGrassCard } from './textures';

/** 카드 한 장의 크기 (m). 판 하나에 잎 여러 장이 그려져 있다 */
const CARD_W = 0.62;
const CARD_H = 0.5;

export interface GrassField {
  mesh: THREE.InstancedMesh;
  update(elapsed: number): void;
  dispose(): void;
}

/**
 * 카드 지오메트리. 원점이 밑동에 오도록 올려둔다.
 * 세로로 몇 단 나눠야 바람에 휘는 곡선이 부드럽다.
 */
function createCardGeometry(): THREE.BufferGeometry {
  const geo = new THREE.PlaneGeometry(CARD_W, CARD_H, 1, 4);
  geo.translate(0, CARD_H / 2, 0);
  return geo;
}

/**
 * 잔디.
 *
 * 인스턴스 하나 = 잎 하나가 아니라 **잎 여러 장이 그려진 카드 한 장**이다.
 * 같은 인스턴스 수로 밀도가 몇 배가 되고, 단색 판떼기처럼 보이지 않는다.
 *
 * 셰이딩에 트릭이 하나 들어간다. 카드의 실제 법선을 그대로 쓰면 카드가
 * 빛을 향한 각도에 따라 밝고 어두운 판이 뒤섞여 번쩍거린다. 법선을 위쪽으로
 * 끌어당기면 풀밭이 하나의 덩어리처럼 부드럽게 받는다 — 게임에서 흔히 쓰는 방법.
 */
export function createGrass(
  env: ZoneEnv,
  mask: PathMask,
  isBlocked: (x: number, z: number) => boolean
): GrassField {
  const count = env.grassCount;
  const radius = env.grassRadius;

  const geo = createCardGeometry();
  const card = createGrassCard();

  const mat = new THREE.MeshStandardMaterial({
    map: card,
    side: THREE.DoubleSide,
    alphaTest: 0.35,
    roughness: 0.95,
    metalness: 0,
    // 카드 뒷면도 앞면처럼 밝게 — 잎이 빛을 투과하는 느낌
    color: new THREE.Color(env.grassLight).multiplyScalar(1.9),
  });

  let shaderRef: THREE.WebGLProgramParametersWithUniforms | null = null;
  mat.onBeforeCompile = (shader) => {
    shader.uniforms.uTime = { value: 0 };
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nuniform float uTime;')
      .replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
        float sway = clamp(transformed.y / ${CARD_H.toFixed(3)}, 0.0, 1.0);
        #ifdef USE_INSTANCING
          vec3 iPos = vec3(instanceMatrix[3][0], instanceMatrix[3][1], instanceMatrix[3][2]);
        #else
          vec3 iPos = vec3(0.0);
        #endif
        float phase = uTime * 1.6 + iPos.x * 0.32 + iPos.z * 0.28;
        float amp = sway * sway * 0.14;
        transformed.x += sin(phase) * amp;
        transformed.z += cos(phase * 0.73) * amp * 0.65;`
      )
      // 법선을 위로 끌어당긴다. 카드마다 명암이 튀는 걸 막는 핵심.
      .replace(
        '#include <defaultnormal_vertex>',
        `#include <defaultnormal_vertex>
        transformedNormal = normalize( mix( transformedNormal, normalize( ( viewMatrix * vec4( 0.0, 1.0, 0.0, 0.0 ) ).xyz ), 0.75 ) );`
      );
    shaderRef = shader;
  };
  mat.customProgramCacheKey = () => 'grass-card';

  const mesh = new THREE.InstancedMesh(geo, mat, count);
  mesh.castShadow = false; // 잔디 그림자는 비용 대비 효과가 없다
  mesh.receiveShadow = true;
  mesh.frustumCulled = false;
  mesh.name = 'grass';
  // 개체마다 색을 흔든다. 전부 같은 초록이면 카펫처럼 보인다.
  mesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(count * 3), 3);

  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const euler = new THREE.Euler();
  const scale = new THREE.Vector3();
  const posV = new THREE.Vector3();
  const tint = new THREE.Color();

  let placed = 0;
  let attempts = 0;
  const maxAttempts = count * 12;

  while (placed < count && attempts < maxAttempts) {
    attempts++;
    // 원형 영역에 균일 분포
    const a = hash2(attempts, 7.3) * Math.PI * 2;
    const r = Math.sqrt(hash2(attempts, 19.1)) * radius;
    const x = Math.cos(a) * r;
    const z = Math.sin(a) * r;

    if (mask(x, z) > 0.32) continue;
    if (isBlocked(x, z)) continue;

    // 패치 단위로 키가 달라진다 — 갈대처럼 우거진 구역이 생김
    const patch = fbm(x * 0.055 + 40, z * 0.055 + 40, 3);
    const tall = patch > 0.62 ? 1 + (patch - 0.62) * 7 : 1;
    const h = (0.75 + hash2(attempts, 3.1) * 0.5) * tall;
    const w = 0.85 + hash2(attempts, 5.7) * 0.45;

    euler.set(
      (hash2(attempts, 11.3) - 0.5) * 0.24,
      hash2(attempts, 13.9) * Math.PI * 2,
      (hash2(attempts, 17.7) - 0.5) * 0.24
    );
    q.setFromEuler(euler);
    posV.set(x, 0, z);
    scale.set(w, h, w);
    m.compose(posV, q, scale);
    mesh.setMatrixAt(placed, m);

    // 노랗게 마른 풀 ~ 짙은 초록 사이를 오간다
    const dry = hash2(attempts, 23.7);
    const shade = 0.72 + hash2(attempts, 41.3) * 0.5;
    tint.setRGB(
      (0.88 + dry * 0.4) * shade,
      (1.0 - dry * 0.08) * shade,
      (0.8 - dry * 0.3) * shade
    );
    mesh.setColorAt(placed, tint);

    placed++;
  }

  mesh.count = placed;
  mesh.instanceMatrix.needsUpdate = true;
  if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;

  return {
    mesh,
    update(elapsed: number) {
      if (shaderRef) shaderRef.uniforms.uTime.value = elapsed;
    },
    dispose() {
      geo.dispose();
      mat.dispose();
      card.dispose();
    },
  };
}
