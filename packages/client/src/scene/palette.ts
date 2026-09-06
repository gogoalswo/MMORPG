/**
 * 레퍼런스 스크린샷에서 뽑은 색 팔레트.
 * 전체적으로 채도가 낮고 살짝 따뜻하다. PBR 금속감 없음.
 */
export const PALETTE = {
  grassDark: '#5c6a3c',
  grassMid: '#6f7d4a',
  grassLight: '#82905a',
  dirt: '#a8916c',
  dirtLight: '#b9a37e',

  wallCream: '#e6dec9',
  timber: '#c49a68',
  timberDark: '#a87f4f',
  roofTile: '#c07d5e',
  roofRidge: '#a96a4e',
  door: '#8a6a44',
  window: '#dfe6e8',

  trunk: '#6b5540',
  leafLight: '#9dc05e',
  leafMid: '#89ad51',

  skyTop: '#b9c9d8',
  fog: '#c2c8b8',
} as const;

/** 해시 기반 값 노이즈 (지형 텍스처와 배치 지터에 사용) */
export function hash2(x: number, y: number): number {
  const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return s - Math.floor(s);
}

export function valueNoise(x: number, y: number): number {
  const xi = Math.floor(x);
  const yi = Math.floor(y);
  const xf = x - xi;
  const yf = y - yi;
  // smoothstep
  const u = xf * xf * (3 - 2 * xf);
  const v = yf * yf * (3 - 2 * yf);
  const a = hash2(xi, yi);
  const b = hash2(xi + 1, yi);
  const c = hash2(xi, yi + 1);
  const d = hash2(xi + 1, yi + 1);
  return a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + d * u * v;
}

export function fbm(x: number, y: number, octaves = 4): number {
  let sum = 0;
  let amp = 0.5;
  let freq = 1;
  for (let i = 0; i < octaves; i++) {
    sum += valueNoise(x * freq, y * freq) * amp;
    freq *= 2;
    amp *= 0.5;
  }
  return sum;
}
