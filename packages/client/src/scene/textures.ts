import * as THREE from 'three';
import { hash2 } from './palette';

/**
 * 절차적 PBR 텍스처 생성.
 *
 * 지금 화면이 "찰흙"처럼 보이는 가장 큰 이유는 텍스처가 아예 없어서다.
 * 단색 표면은 빛을 균일하게 반사해서 재질감이 생기지 않는다.
 * 외부 에셋 없이도 알베도/노멀/러프니스 세 장을 만들면 인상이 크게 달라진다.
 *
 * 모든 텍스처는 **타일링 가능**해야 한다. 지면에 높은 반복 횟수로 깔리기 때문에
 * 이음매가 보이면 바로 티가 난다. 노이즈 격자를 period 로 감아서 해결한다.
 */

/** 격자를 period 로 감은 값 노이즈 — 좌우/상하가 이어진다 */
function tileValueNoise(x: number, y: number, period: number): number {
  const xi = Math.floor(x);
  const yi = Math.floor(y);
  const xf = x - xi;
  const yf = y - yi;
  const u = xf * xf * (3 - 2 * xf);
  const v = yf * yf * (3 - 2 * yf);
  const w = (n: number) => ((n % period) + period) % period;

  const a = hash2(w(xi), w(yi));
  const b = hash2(w(xi + 1), w(yi));
  const c = hash2(w(xi), w(yi + 1));
  const d = hash2(w(xi + 1), w(yi + 1));
  return a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + d * u * v;
}

function tileFbm(x: number, y: number, period: number, octaves: number): number {
  let sum = 0;
  let amp = 0.5;
  let freq = 1;
  let norm = 0;
  for (let i = 0; i < octaves; i++) {
    sum += tileValueNoise(x * freq, y * freq, period * freq) * amp;
    norm += amp;
    freq *= 2;
    amp *= 0.5;
  }
  return sum / norm;
}

export interface SurfaceOptions {
  size?: number;
  /** 노이즈 격자 수. 클수록 잔무늬가 촘촘하다 */
  period?: number;
  /** 어두운 쪽 / 밝은 쪽 색 */
  dark: string;
  light: string;
  /** 드문드문 섞이는 강조색 (마른 풀, 자갈 등) */
  speckle?: string;
  speckleAmount?: number;
  /** 높이 대비 — 노멀맵 요철 강도 */
  bump?: number;
  /** y축으로 늘려 결을 만든다 (풀결) */
  stretch?: number;
  /** 러프니스 범위 */
  roughMin?: number;
  roughMax?: number;
}

export interface SurfaceTextures {
  map: THREE.Texture;
  normalMap: THREE.Texture;
  roughnessMap: THREE.Texture;
  dispose(): void;
}

function hexToRgb(hex: string): [number, number, number] {
  const v = parseInt(hex.slice(1), 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

function makeTexture(canvas: HTMLCanvasElement, srgb: boolean): THREE.CanvasTexture {
  const tex = new THREE.CanvasTexture(canvas);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  tex.anisotropy = 8;
  return tex;
}

/**
 * 하나의 높이장에서 알베도·노멀·러프니스를 함께 뽑는다.
 * 같은 높이장을 공유해야 요철과 색이 따로 놀지 않는다.
 */
export function createSurface(opts: SurfaceOptions): SurfaceTextures {
  const size = opts.size ?? 512;
  const period = opts.period ?? 8;
  const stretch = opts.stretch ?? 1;
  const bump = opts.bump ?? 2.2;
  const roughMin = opts.roughMin ?? 0.72;
  const roughMax = opts.roughMax ?? 0.98;
  const speckleAmount = opts.speckleAmount ?? 0;

  const [dr, dg, db] = hexToRgb(opts.dark);
  const [lr, lg, lb] = hexToRgb(opts.light);
  const speck = opts.speckle ? hexToRgb(opts.speckle) : null;

  // --- 높이장 ---
  const height = new Float32Array(size * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const nx = (x / size) * period;
      const ny = (y / size) * period * stretch;
      // 굵은 얼룩 + 잔결을 겹친다
      const macro = tileFbm(nx * 0.5, ny * 0.5, period, 3);
      const micro = tileFbm(nx * 3, ny * 3, period * 3, 3);
      height[y * size + x] = macro * 0.62 + micro * 0.38;
    }
  }

  // --- 알베도 ---
  const albedoCanvas = document.createElement('canvas');
  albedoCanvas.width = albedoCanvas.height = size;
  const aCtx = albedoCanvas.getContext('2d')!;
  const aImg = aCtx.createImageData(size, size);

  // --- 러프니스 ---
  const roughCanvas = document.createElement('canvas');
  roughCanvas.width = roughCanvas.height = size;
  const rCtx = roughCanvas.getContext('2d')!;
  const rImg = rCtx.createImageData(size, size);

  for (let i = 0; i < size * size; i++) {
    const h = height[i]!;
    // 대비를 세워 밋밋한 회색 덩어리가 되지 않게 한다
    const t = Math.min(1, Math.max(0, (h - 0.35) * 2.1));

    let r = dr + (lr - dr) * t;
    let g = dg + (lg - dg) * t;
    let b = db + (lb - db) * t;

    if (speck && speckleAmount > 0) {
      const s = hash2(i % size, Math.floor(i / size));
      if (s > 1 - speckleAmount) {
        const k = 0.55 + s * 0.45;
        r += (speck[0] - r) * k;
        g += (speck[1] - g) * k;
        b += (speck[2] - b) * k;
      }
    }

    const o = i * 4;
    aImg.data[o] = r;
    aImg.data[o + 1] = g;
    aImg.data[o + 2] = b;
    aImg.data[o + 3] = 255;

    // 높은 곳(마른 부분)이 더 거칠다
    const rough = (roughMin + (roughMax - roughMin) * (1 - t)) * 255;
    rImg.data[o] = rough;
    rImg.data[o + 1] = rough;
    rImg.data[o + 2] = rough;
    rImg.data[o + 3] = 255;
  }
  aCtx.putImageData(aImg, 0, 0);
  rCtx.putImageData(rImg, 0, 0);

  // --- 노멀맵: 높이장 기울기(Sobel) ---
  const normalCanvas = document.createElement('canvas');
  normalCanvas.width = normalCanvas.height = size;
  const nCtx = normalCanvas.getContext('2d')!;
  const nImg = nCtx.createImageData(size, size);
  const at = (x: number, y: number) => height[((y + size) % size) * size + ((x + size) % size)]!;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = (at(x - 1, y) - at(x + 1, y)) * bump;
      const dy = (at(x, y - 1) - at(x, y + 1)) * bump;
      const len = Math.hypot(dx, dy, 1);
      const o = (y * size + x) * 4;
      nImg.data[o] = ((dx / len) * 0.5 + 0.5) * 255;
      nImg.data[o + 1] = ((dy / len) * 0.5 + 0.5) * 255;
      nImg.data[o + 2] = ((1 / len) * 0.5 + 0.5) * 255;
      nImg.data[o + 3] = 255;
    }
  }
  nCtx.putImageData(nImg, 0, 0);

  const map = makeTexture(albedoCanvas, true);
  const normalMap = makeTexture(normalCanvas, false);
  const roughnessMap = makeTexture(roughCanvas, false);

  return {
    map,
    normalMap,
    roughnessMap,
    dispose() {
      map.dispose();
      normalMap.dispose();
      roughnessMap.dispose();
    },
  };
}

/**
 * 넓은 면적에 같은 타일을 반복하면 격자 무늬가 눈에 띈다.
 * 존 전체에 한 번만 깔리는 저주파 텍스처를 곱해서 그 반복감을 깬다.
 */
export function createMacroVariation(size = 256, strength = 0.34): THREE.Texture {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext('2d')!;
  const img = ctx.createImageData(size, size);

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const n = tileFbm((x / size) * 4, (y / size) * 4, 4, 4);
      const v = (1 - strength + n * strength * 2) * 255;
      const o = (y * size + x) * 4;
      img.data[o] = v;
      img.data[o + 1] = v;
      img.data[o + 2] = v;
      img.data[o + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return makeTexture(canvas, false);
}

/**
 * 풀포기 카드.
 *
 * 판 하나에 잎 하나를 그리면 아무리 많이 심어도 종이조각처럼 보인다.
 * 실제 게임은 판 하나에 잎 여러 장을 그린 "포기" 텍스처를 쓴다 —
 * 같은 인스턴스 수로 밀도가 몇 배가 되고 실루엣이 훨씬 자연스럽다.
 *
 * RGB 는 무채색 명암(밑동 어둡고 끝 밝음)만 담는다.
 * 색은 인스턴스별 틴트가 입히므로 텍스처에 색을 굽지 않는다.
 */
export function createGrassCard(size = 256): THREE.Texture {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext('2d')!;
  ctx.clearRect(0, 0, size, size);

  const blades = 7;
  for (let i = 0; i < blades; i++) {
    const baseX = size * (0.1 + (i / (blades - 1)) * 0.8 + (hash2(i, 3.1) - 0.5) * 0.06);
    const height = size * (0.55 + hash2(i, 7.7) * 0.42);
    const lean = (hash2(i, 11.3) - 0.5) * size * 0.42;
    const halfWidth = size * (0.018 + hash2(i, 13.9) * 0.014);

    const tipX = baseX + lean;
    const tipY = size - height;
    const ctrlX = baseX + lean * 0.35;
    const ctrlY = size - height * 0.45;

    // 밑동은 어둡고 끝으로 갈수록 밝다 — 무리 안쪽에 빛이 덜 든다
    const grad = ctx.createLinearGradient(0, size, 0, tipY);
    const dark = 60 + hash2(i, 17.1) * 30;
    const light = 200 + hash2(i, 19.3) * 55;
    grad.addColorStop(0, `rgb(${dark | 0},${dark | 0},${dark | 0})`);
    grad.addColorStop(1, `rgb(${light | 0},${light | 0},${light | 0})`);
    ctx.fillStyle = grad;

    ctx.beginPath();
    ctx.moveTo(baseX - halfWidth, size);
    ctx.quadraticCurveTo(ctrlX - halfWidth * 0.6, ctrlY, tipX, tipY);
    ctx.quadraticCurveTo(ctrlX + halfWidth * 0.6, ctrlY, baseX + halfWidth, size);
    ctx.closePath();
    ctx.fill();
  }

  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.anisotropy = 4;
  return tex;
}

/**
 * 잎 무리 카드 — 나무 수관을 이걸 여러 장 겹쳐서 만든다.
 *
 * 사진스캔 나무는 한 그루에 수십만 폴리곤이라 브라우저 MMO 에 못 쓴다.
 * 잎 카드 방식은 한 그루를 사각형 40~60장으로 끝내면서도 실루엣이 산다.
 */
export function createLeafCard(size = 256): THREE.Texture {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext('2d')!;
  ctx.clearRect(0, 0, size, size);

  const leaves = 26;
  for (let i = 0; i < leaves; i++) {
    // 카드 중심에 몰리게 배치해서 가장자리가 자연스럽게 흩어지도록
    const a = hash2(i, 2.3) * Math.PI * 2;
    const r = Math.pow(hash2(i, 5.9), 0.65) * size * 0.44;
    const cx = size / 2 + Math.cos(a) * r;
    const cy = size / 2 + Math.sin(a) * r;
    const rx = size * (0.055 + hash2(i, 8.1) * 0.05);
    const ry = rx * (1.5 + hash2(i, 9.7) * 0.9);
    const rot = hash2(i, 12.5) * Math.PI;

    // 중심에서 멀수록 어둡게 — 수관 안쪽 그늘을 흉내낸다
    const depth = 1 - r / (size * 0.5);
    const v = 110 + depth * 130 + hash2(i, 15.1) * 25;

    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(rot);
    ctx.fillStyle = `rgb(${v | 0},${v | 0},${v | 0})`;
    ctx.beginPath();
    ctx.ellipse(0, 0, rx, ry, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.anisotropy = 4;
  return tex;
}
