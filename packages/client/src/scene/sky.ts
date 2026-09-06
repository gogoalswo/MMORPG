import * as THREE from 'three';
import type { ZoneEnv } from '@mmo/shared';

/**
 * 절차적 하늘 + 환경광(IBL).
 *
 * 방향광 하나만 쓰면 그림자 안쪽이 단색으로 죽어서 플라스틱처럼 보인다.
 * 하늘 그라디언트를 환경맵으로 구워 넣으면 표면마다 방향에 따라 다른 하늘빛을
 * 받게 되고, 금속·젖은 표면에 반사가 생긴다. 실사 인상의 절반은 여기서 나온다.
 */

const EQUIRECT_W = 256;
const EQUIRECT_H = 128;

function lerpColor(a: THREE.Color, b: THREE.Color, t: number, out: THREE.Color): THREE.Color {
  return out.copy(a).lerp(b, t);
}

/** 천정 → 지평선 → 지면 순으로 이어지는 등장방형 하늘 이미지 */
function drawSky(env: ZoneEnv): HTMLCanvasElement {
  const canvas = document.createElement('canvas');
  canvas.width = EQUIRECT_W;
  canvas.height = EQUIRECT_H;
  const ctx = canvas.getContext('2d')!;
  const img = ctx.createImageData(EQUIRECT_W, EQUIRECT_H);

  const zenith = new THREE.Color(env.skyColor).multiplyScalar(0.95);
  const horizon = new THREE.Color(env.fogColor).lerp(new THREE.Color(0xffffff), 0.25);
  const ground = new THREE.Color(env.grassDark).multiplyScalar(0.7);
  const tmp = new THREE.Color();

  for (let y = 0; y < EQUIRECT_H; y++) {
    // 0 = 천정, 1 = 바닥
    const v = y / (EQUIRECT_H - 1);
    let color: THREE.Color;
    if (v < 0.5) {
      // 지평선에 가까울수록 밝고 따뜻하게 — 실제 하늘의 감쇠
      const t = Math.pow(v / 0.5, 0.55);
      color = lerpColor(zenith, horizon, t, tmp);
    } else {
      const t = Math.min(1, (v - 0.5) / 0.18);
      color = lerpColor(horizon, ground, t, tmp);
    }

    for (let x = 0; x < EQUIRECT_W; x++) {
      const o = (y * EQUIRECT_W + x) * 4;
      img.data[o] = color.r * 255;
      img.data[o + 1] = color.g * 255;
      img.data[o + 2] = color.b * 255;
      img.data[o + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);

  // 태양 방향에 부드러운 밝은 원 — 금속 표면의 하이라이트가 여기서 나온다
  const sunX = EQUIRECT_W * 0.62;
  const sunY = EQUIRECT_H * 0.28;
  const radius = EQUIRECT_H * 0.34;
  const gradient = ctx.createRadialGradient(sunX, sunY, 0, sunX, sunY, radius);
  const glow = new THREE.Color(0xfff3dd);
  gradient.addColorStop(0, `rgba(${glow.r * 255 | 0}, ${glow.g * 255 | 0}, ${glow.b * 255 | 0}, 0.95)`);
  gradient.addColorStop(0.35, 'rgba(255, 240, 215, 0.35)');
  gradient.addColorStop(1, 'rgba(255, 240, 215, 0)');
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, EQUIRECT_W, EQUIRECT_H);

  return canvas;
}

export interface SkyEnvironment {
  texture: THREE.Texture;
  dispose(): void;
}

/** 존 분위기에 맞는 환경맵을 굽는다 (PMREM — 러프니스별 밉맵) */
export function createSkyEnvironment(renderer: THREE.WebGLRenderer, env: ZoneEnv): SkyEnvironment {
  const canvas = drawSky(env);
  const source = new THREE.CanvasTexture(canvas);
  source.mapping = THREE.EquirectangularReflectionMapping;
  source.colorSpace = THREE.SRGBColorSpace;

  const pmrem = new THREE.PMREMGenerator(renderer);
  pmrem.compileEquirectangularShader();
  const target = pmrem.fromEquirectangular(source);

  source.dispose();
  pmrem.dispose();

  return {
    texture: target.texture,
    dispose() {
      target.dispose();
    },
  };
}
