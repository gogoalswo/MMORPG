import * as THREE from 'three';
import type { GroundKind, ZoneEnv } from '@mmo/shared';
import { createMacroVariation } from './textures';
import type { Assets } from './assets';

/**
 * 바닥 텍스처마다 다른 것 — 이미지가 가진 성질이라 존 데이터가 아니라 여기 둔다.
 *
 * 이미지 한 장(1024²)에 무엇이 몇 개 그려져 있느냐가 종류마다 달라서 타일
 * 크기도 따로다. 돌판은 한 장에 판석이 일고여덟 줄이라 6m 로 펴야 한 장이
 * 80cm 쯤 되고, 자갈은 스무 개 남짓이라 8m 에 한 알이 35cm 다 — 4m 로 두면
 * 기본 카메라 거리에서 알이 안 보이고 모래 같은 잡티가 된다. 용암은 재 얼룩이
 * 크게 몇 개뿐이라 12m 보다 좁히면 얼룩이 격자로 늘어선 게 보인다.
 */
interface GroundLook {
  /** 타일 한 장이 덮는 실제 크기(m) */
  tile: number;
  /**
   * 배율이 다른 두 샘플을 섞는 비율 (0 = 안 섞음).
   *
   * 같은 타일을 스무 번 넘게 깔면 격자가 드러난다. 배율 0.37 짜리를 겹치면
   * 반복 주기가 어긋나 깨진다 — 풀·눈·모래처럼 무늬가 흩어진 것에만 쓴다.
   * 돌판·자갈·용암 균열처럼 **모양이 뚜렷한 것**에 쓰면 판석이 두 겹으로
   * 비쳐 보인다.
   */
  blend: number;
  roughness: number;
  /**
   * 텍스처 평균색 (sRGB). build-ground-textures.mjs 가 출력하는 값.
   * 존 틴트는 "이 색을 그 존의 색 쪽으로" 끌어당기는 비율로 건다.
   */
  mean: string;
  /** 스스로 빛나는 정도 — 용암 균열 */
  glow: number;
}

const LOOKS: Record<GroundKind, GroundLook> = {
  stone: { tile: 6, blend: 0, roughness: 0.85, mean: '#51504f', glow: 0 },
  grass: { tile: 4, blend: 0.45, roughness: 0.95, mean: '#4e6536', glow: 0 },
  snow: { tile: 6, blend: 0.45, roughness: 0.7, mean: '#d6dee6', glow: 0 },
  dirt: { tile: 6, blend: 0.45, roughness: 0.95, mean: '#9f8467', glow: 0 },
  sand: { tile: 6, blend: 0.45, roughness: 0.9, mean: '#e6ca9d', glow: 0 },
  cobble: { tile: 8, blend: 0, roughness: 0.8, mean: '#746b5c', glow: 0 },
  lava: { tile: 12, blend: 0, roughness: 0.9, mean: '#3e3837', glow: 1 },
};

/**
 * 바닥 반사율 배율.
 *
 * 조명(태양 2.7·환경광·ACES)은 예전 ambientCG 텍스처에 맞춰져 있었다 — 그
 * 텍스처는 어두웠고 존 색 ×2 를 곱해 썼다. 바르코 이미지는 **이미 화면에
 * 보일 밝기로** 그려져 있어서(눈 평균 #d6dee6) 그대로 깔면 조명이 한 번 더
 * 밝혀 눈·모래·소금 평원이 하얗게 날아가고 무늬가 사라진다. 마을에서 재 보니
 * 반사율 → 화면(선형) 이 3.2배였다. 그 역수쯤을 곱해 화면에 이미지 밝기로 나오게 한다.
 */
const ALBEDO = 0.3;

/**
 * 존 색으로 끌어당기는 비율.
 *
 * 1 이면 텍스처 평균색이 존 색과 같아진다 — 초원과 검은 삼림이 같은 풀
 * 이미지를 쓰면서 확실히 갈리지만, 소금 평원처럼 원래 색과 먼 곳은 텍스처가
 * 제 색을 잃는다. 반쯤이 둘의 타협점이다. 명암(무늬)은 곱셈이라 그대로 남는다.
 */
const TINT_PULL = 0.5;

function tintFor(target: string, mean: string): THREE.Color {
  // three 의 Color 는 선형으로 들고 있다 — 셰이더도 선형으로 곱하므로 비율이 맞다
  const t = new THREE.Color(target);
  const m = new THREE.Color(mean);
  const ratio = (a: number, b: number) => THREE.MathUtils.clamp(a / Math.max(b, 1e-4), 0.3, 2.5);
  return new THREE.Color(
    THREE.MathUtils.lerp(1, ratio(t.r, m.r), TINT_PULL),
    THREE.MathUtils.lerp(1, ratio(t.g, m.g), TINT_PULL),
    THREE.MathUtils.lerp(1, ratio(t.b, m.b), TINT_PULL)
  );
}

export interface Ground {
  mesh: THREE.Mesh;
  dispose(): void;
}

/**
 * 지면.
 *
 * 존마다 바닥 텍스처 한 장(`env.ground`)만 깐다 — 길·풀 잎은 2026-09-10 에
 * 없앴다(요청). 반복 패턴은 저주파 매크로 텍스처를 곱해서 깬다. 사냥터 20곳이
 * 텍스처 여섯을 나눠 쓰므로 존 색(`groundTint`)으로 물들여 가른다.
 */
export function createGround(size: number, env: ZoneEnv, assets: Assets): Ground {
  const base = assets.grounds[env.ground];
  const baseLook = LOOKS[env.ground];

  const macro = createMacroVariation();

  const geo = new THREE.PlaneGeometry(size, size, 1, 1);
  geo.rotateX(-Math.PI / 2);

  const material = new THREE.MeshStandardMaterial({
    map: base.map,
    normalMap: base.normalMap,
    roughness: 1,
    metalness: 0,
    normalScale: new THREE.Vector2(1.0, 1.0),
  });

  const uniforms = {
    uMacro: { value: macro },
    uBaseDetail: { value: size / baseLook.tile },
    uBaseBlend: { value: baseLook.blend },
    // 틴트는 알베도에만 곱한다 — 용암 균열 빛(glow)은 틴트 전 색으로 고른다
    uBaseTint: { value: tintFor(env.groundTint, baseLook.mean).multiplyScalar(ALBEDO) },
    uBaseRough: { value: baseLook.roughness },
    uGlow: { value: baseLook.glow },
  };

  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);

    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        uniform sampler2D uMacro;
        uniform float uBaseDetail;
        uniform float uBaseBlend;
        uniform vec3 uBaseTint;
        uniform float uBaseRough;
        uniform float uGlow;

        // 배율이 다른 두 샘플을 섞으면 반복 주기가 무리수가 되어 격자가 깨진다.
        // 모양이 뚜렷한 텍스처는 blend 0 — 섞으면 두 겹으로 비친다.
        vec4 detailSample( sampler2D tex, vec2 uv, float blend ) {
          vec4 a = texture2D( tex, uv );
          if ( blend <= 0.0 ) return a;
          return mix( a, texture2D( tex, uv * 0.37 + vec2( 0.31, 0.17 ) ), blend );
        }`
      )
      // 알베도: 바닥 한 장에 매크로 노이즈를 곱해 타일 반복감을 깬다
      .replace(
        '#include <map_fragment>',
        `vec3 baseRaw = detailSample( map, vMapUv * uBaseDetail, uBaseBlend ).rgb;
        vec3 blended = baseRaw * uBaseTint;
        blended *= texture2D( uMacro, vMapUv ).r * 1.15;
        diffuseColor *= vec4( blended, 1.0 );`
      )
      // 러프니스 맵이 없다 — 종류마다 상수다
      .replace(
        '#include <roughnessmap_fragment>',
        `float roughnessFactor = roughness * uBaseRough;`
      )
      // 노멀도 색과 같은 배율로 샘플해야 요철이 무늬와 어긋나지 않는다
      .replace(
        '#include <normal_fragment_maps>',
        // tbn 은 상위 청크(normal_fragment_begin)가 이미 만들어 둔다. 다시 선언하면 컴파일이 깨진다.
        `vec3 mapN = detailSample( normalMap, vNormalMapUv * uBaseDetail, uBaseBlend ).xyz * 2.0 - 1.0;
        mapN.xy *= normalScale;
        normal = normalize( tbn * mapN );`
      )
      // 용암 균열은 스스로 빛난다. 붉고 파랑이 빠진 곳만 골라낸다 — 틴트 전의
      // 원래 색으로 고르므로, 어두운 존 색을 곱해도 균열 빛은 안 죽는다.
      .replace(
        '#include <emissivemap_fragment>',
        `#include <emissivemap_fragment>
        float crack = smoothstep( 0.25, 0.6, baseRaw.r - baseRaw.b );
        totalEmissiveRadiance += baseRaw * crack * uGlow * 2.0;`
      );
  };
  material.customProgramCacheKey = () => 'ground-kinds';

  const mesh = new THREE.Mesh(geo, material);
  mesh.receiveShadow = true;
  mesh.name = 'ground';

  return {
    mesh,
    dispose() {
      // 지면 텍스처는 존들이 공유하므로 여기서 해제하지 않는다
      geo.dispose();
      material.dispose();
      macro.dispose();
    },
  };
}
