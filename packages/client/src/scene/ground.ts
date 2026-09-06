import * as THREE from 'three';
import type { RoadDef, ZoneEnv } from '@mmo/shared';
import { fbm } from './palette';
import { createMacroVariation } from './textures';
import type { Assets } from './assets';

const SPLAT_SIZE = 512;
/**
 * 타일 한 장이 덮는 실제 크기(m).
 * 작게 잡으면 선명하지만 반복 무늬가 드러난다. 4m 가 두 조건의 타협점.
 */
const TILE_METERS = 4.0;

/** 지면의 흙길 마스크. 0 = 잔디, 1 = 흙길 */
export type PathMask = (x: number, z: number) => number;

/**
 * 존의 길 정의로부터 마스크 함수를 만든다.
 *
 * 지면 텍스처를 그릴 때와 잔디/나무를 심을 때 **같은 함수**를 쓴다 —
 * 그래야 길 위에 풀이 자라거나 나무가 서지 않는다.
 */
export function createPathMask(roads: RoadDef[]): PathMask {
  if (roads.length === 0) return () => 0;

  return (x: number, z: number): number => {
    let strongest = 0;
    for (const road of roads) {
      const along = road.axis === 'z' ? z : x;
      const across = road.axis === 'z' ? x : z;
      const center = road.offset + Math.sin(along * road.waveFreq) * road.wave;
      const dist = Math.abs(across - center);
      const v = 1 - smoothstep(road.width * 0.65, road.width * 1.35, dist);
      if (v > strongest) strongest = v;
    }
    // 가장자리를 노이즈로 흐트러뜨려 자로 자른 것처럼 보이지 않게
    const edge = (fbm(x * 0.08, z * 0.08, 3) - 0.5) * 0.45;
    return clamp01(strongest + edge);
  };
}

function smoothstep(a: number, b: number, t: number): number {
  const x = clamp01((t - a) / (b - a));
  return x * x * (3 - 2 * x);
}

function clamp01(v: number): number {
  return v < 0 ? 0 : v > 1 ? 1 : v;
}

/** 잔디/흙 경계를 담은 마스크 텍스처 (R 채널 = 흙 비율) */
function createSplatTexture(size: number, mask: PathMask): THREE.CanvasTexture {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = SPLAT_SIZE;
  const ctx = canvas.getContext('2d')!;
  const img = ctx.createImageData(SPLAT_SIZE, SPLAT_SIZE);
  const half = size / 2;

  for (let py = 0; py < SPLAT_SIZE; py++) {
    for (let px = 0; px < SPLAT_SIZE; px++) {
      const wx = (px / SPLAT_SIZE) * size - half;
      const wz = (py / SPLAT_SIZE) * size - half;
      const v = mask(wx, wz) * 255;
      const o = (py * SPLAT_SIZE + px) * 4;
      img.data[o] = v;
      img.data[o + 1] = v;
      img.data[o + 2] = v;
      img.data[o + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);

  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.NoColorSpace;
  tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
  return tex;
}

export interface Ground {
  mesh: THREE.Mesh;
  dispose(): void;
}

/**
 * 지면.
 *
 * 예전에는 1024px 텍스처 한 장을 220유닛에 늘려 붙였다 — 픽셀당 0.2유닛이라
 * 가까이 보면 완전히 뭉개졌다. 이제는 타일링 디테일 텍스처를 90번 반복하고
 * (픽셀당 0.005유닛) 스플랫 마스크로 잔디/흙을 섞는다.
 * 반복 패턴은 저주파 매크로 텍스처를 곱해서 깬다.
 */
export function createGround(size: number, env: ZoneEnv, mask: PathMask, assets: Assets): Ground {
  const { grass, dirt } = assets;
  const splat = createSplatTexture(size, mask);
  const macro = createMacroVariation();

  const geo = new THREE.PlaneGeometry(size, size, 1, 1);
  geo.rotateX(-Math.PI / 2);

  const material = new THREE.MeshStandardMaterial({
    map: grass.map,
    normalMap: grass.normalMap,
    roughnessMap: grass.roughnessMap,
    metalness: 0,
    normalScale: new THREE.Vector2(1.0, 1.0),
  });

  const uniforms = {
    uSplat: { value: splat },
    uMacro: { value: macro },
    uDirtMap: { value: dirt.map },
    uDirtNormal: { value: dirt.normalMap },
    uDirtRough: { value: dirt.roughnessMap },
    uDetail: { value: size / TILE_METERS },
    // 존 분위기 색보정. 머티리얼 color 로 하면 잔디와 흙이 같이 물들어
    // 흙길까지 초록이 된다. 그래서 각각 따로 곱한다.
    uGrassTint: { value: new THREE.Color(env.grassLight).multiplyScalar(2.0) },
    uDirtTint: { value: new THREE.Color(env.dirtLight).multiplyScalar(1.9) },
  };

  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);

    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        uniform sampler2D uSplat;
        uniform sampler2D uMacro;
        uniform sampler2D uDirtMap;
        uniform sampler2D uDirtNormal;
        uniform sampler2D uDirtRough;
        uniform float uDetail;
        uniform vec3 uGrassTint;
        uniform vec3 uDirtTint;

        // 같은 타일을 100번 반복하면 격자 무늬가 눈에 띈다.
        // 배율이 다른 두 샘플을 섞으면 반복 주기가 무리수가 되어 패턴이 깨진다.
        vec4 detailSample( sampler2D tex, vec2 uv ) {
          return mix(
            texture2D( tex, uv ),
            texture2D( tex, uv * 0.37 + vec2( 0.31, 0.17 ) ),
            0.45
          );
        }`
      )
      // 알베도: 잔디/흙을 섞고, 매크로 노이즈로 타일 반복감을 깬다
      .replace(
        '#include <map_fragment>',
        `float splat = texture2D( uSplat, vMapUv ).r;
        vec2 detailUv = vMapUv * uDetail;
        vec3 grassCol = detailSample( map, detailUv ).rgb * uGrassTint;
        vec3 dirtCol = detailSample( uDirtMap, detailUv ).rgb * uDirtTint;
        vec3 blended = mix( grassCol, dirtCol, splat );
        blended *= texture2D( uMacro, vMapUv ).r * 1.15;
        diffuseColor *= vec4( blended, 1.0 );`
      )
      .replace(
        '#include <roughnessmap_fragment>',
        `float roughnessFactor = roughness;
        float splatR = texture2D( uSplat, vMapUv ).r;
        vec2 detailUvR = vMapUv * uDetail;
        roughnessFactor *= mix(
          detailSample( roughnessMap, detailUvR ).g,
          detailSample( uDirtRough, detailUvR ).g,
          splatR
        );`
      )
      // 노멀도 같이 섞어야 요철이 색과 어긋나지 않는다
      .replace(
        '#include <normal_fragment_maps>',
        // tbn 은 상위 청크(normal_fragment_begin)가 이미 만들어 둔다. 다시 선언하면 컴파일이 깨진다.
        `float splatN = texture2D( uSplat, vNormalMapUv ).r;
        vec2 detailUvN = vNormalMapUv * uDetail;
        vec3 mapN = mix(
          detailSample( normalMap, detailUvN ).xyz,
          detailSample( uDirtNormal, detailUvN ).xyz,
          splatN
        ) * 2.0 - 1.0;
        mapN.xy *= normalScale;
        normal = normalize( tbn * mapN );`
      );
  };
  material.customProgramCacheKey = () => 'ground-splat';

  const mesh = new THREE.Mesh(geo, material);
  mesh.receiveShadow = true;
  mesh.name = 'ground';

  return {
    mesh,
    dispose() {
      // 지면 텍스처는 존들이 공유하므로 여기서 해제하지 않는다
      geo.dispose();
      material.dispose();
      splat.dispose();
      macro.dispose();
    },
  };
}
