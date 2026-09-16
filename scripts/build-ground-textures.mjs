/**
 * 바닥 이미지(바르코로 만든 타일 텍스처 7장)를 지면 텍스처로 만든다.
 *
 * 받은 건 1024² PNG **색 한 장씩**이다. 노멀맵·러프니스맵이 없다.
 *  - 러프니스는 종류마다 상수로 준다 (client `ground.ts` 의 LOOKS)
 *  - 노멀맵은 **밝기를 높이로 보고** 여기서 만든다. 돌판 이음매·자갈 틈이
 *    어둡게 그려져 있어서 밝기가 곧 높이에 가깝다. 없으면 빛이 비껴 들어도
 *    바닥이 벽지처럼 평평하다.
 *
 * 512² 로 줄인다. 쿼터뷰에서 바닥은 화면 한 픽셀이 3cm 쯤인데, 4~8m 타일을
 * 512 로 찍으면 한 텍셀이 1cm 남짓이라 이미 넘친다.
 * 줄일 때 **2×2 평균**을 쓴다 — sharp 의 resize 는 가장자리를 복제해서 채우므로
 * 타일 이음새에 한 줄 얼룩이 생긴다. 높이 흐림·기울기도 반대편 가장자리와
 * 이어서(랩) 계산한다. 같은 이유다.
 *
 *   node scripts/build-ground-textures.mjs
 *   → assets-src/textures/ground_<종류>_color.jpg, ground_<종류>_normal.jpg
 *   → npm run compress 가 public/assets/textures/*.ktx2 로 누른다
 */
import { mkdirSync } from 'node:fs';
import sharp from 'sharp';

const SRC_DIR = 'assets-src/textures/varco';
const OUT_DIR = 'assets-src/textures';
const SIZE = 512;

/** 이미지 → 바닥 종류. docs/ASSETS.md 의 표와 같다 */
const SOURCES = {
  stone: 'map1',
  grass: 'map2',
  snow: 'map3',
  dirt: 'map4',
  sand: 'map5',
  cobble: 'map6',
  lava: 'map7',
};

/** 밝기를 높이로 볼 때의 기울기 배율. 돌판·자갈은 틈이 깊고, 눈·모래는 얕다 */
const BUMP = { stone: 6, grass: 3, snow: 4, dirt: 4, sand: 3, cobble: 7, lava: 5 };

/** 2×2 평균으로 반으로 줄인다. 이음새를 건드리지 않는 유일한 방법이다 */
function halve(data, size, channels) {
  const half = size / 2;
  const out = new Uint8Array(half * half * channels);
  for (let y = 0; y < half; y += 1) {
    for (let x = 0; x < half; x += 1) {
      for (let k = 0; k < channels; k += 1) {
        const at = (yy, xx) => data[((y * 2 + yy) * size + x * 2 + xx) * channels + k];
        out[(y * half + x) * channels + k] = Math.round((at(0, 0) + at(0, 1) + at(1, 0) + at(1, 1)) / 4);
      }
    }
  }
  return out;
}

mkdirSync(OUT_DIR, { recursive: true });

for (const [kind, file] of Object.entries(SOURCES)) {
  const src = `${SRC_DIR}/${file}.png`;
  const { data, info } = await sharp(src).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  let size = info.width;
  if (info.width !== info.height || size < SIZE || (size & (size - 1)) !== 0) {
    throw new Error(`${src}: ${info.width}x${info.height} — ${SIZE} 이상인 2의 거듭제곱 정사각형이어야 한다`);
  }
  let color = new Uint8Array(data);
  while (size > SIZE) {
    color = halve(color, size, 3);
    size /= 2;
  }

  // 높이 = 밝기, 3×3 로 한 번 흐려 잡티가 요철로 번쩍이지 않게 한다
  const wrap = (v) => (v + size) % size;
  const lum = new Float32Array(size * size);
  for (let i = 0; i < size * size; i += 1) {
    lum[i] = (0.299 * color[i * 3] + 0.587 * color[i * 3 + 1] + 0.114 * color[i * 3 + 2]) / 255;
  }
  const height = new Float32Array(size * size);
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      let sum = 0;
      for (let dy = -1; dy <= 1; dy += 1) for (let dx = -1; dx <= 1; dx += 1) sum += lum[wrap(y + dy) * size + wrap(x + dx)];
      height[y * size + x] = sum / 9;
    }
  }

  // OpenGL 규약(three.js) — +Y 가 텍스처 위쪽이다. 이미지 행은 아래로 늘어나므로 y 기울기의 부호가 뒤집힌다.
  const normal = new Uint8Array(size * size * 3);
  const bump = BUMP[kind];
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const dx = (height[y * size + wrap(x + 1)] - height[y * size + wrap(x - 1)]) * bump;
      const dy = (height[wrap(y + 1) * size + x] - height[wrap(y - 1) * size + x]) * bump;
      const len = Math.hypot(dx, dy, 1);
      const o = (y * size + x) * 3;
      normal[o] = Math.round(((-dx / len) * 0.5 + 0.5) * 255);
      normal[o + 1] = Math.round(((dy / len) * 0.5 + 0.5) * 255);
      normal[o + 2] = Math.round(((1 / len) * 0.5 + 0.5) * 255);
    }
  }

  const raw = { raw: { width: size, height: size, channels: 3 } };
  await sharp(Buffer.from(color), raw).jpeg({ quality: 90, chromaSubsampling: '4:4:4' }).toFile(`${OUT_DIR}/ground_${kind}_color.jpg`);
  await sharp(Buffer.from(normal), raw).jpeg({ quality: 95, chromaSubsampling: '4:4:4' }).toFile(`${OUT_DIR}/ground_${kind}_normal.jpg`);

  // 평균색 — client ground.ts 의 LOOKS[].mean 이 이 값이어야 틴트가 맞는다
  const mean = [0, 0, 0];
  for (let i = 0; i < size * size; i += 1) for (let k = 0; k < 3; k += 1) mean[k] += color[i * 3 + k];
  const hex = '#' + mean.map((v) => Math.round(v / (size * size)).toString(16).padStart(2, '0')).join('');
  console.log(`  ${kind.padEnd(7)} ← ${file}.png  ${size}²  평균색 ${hex}`);
}
