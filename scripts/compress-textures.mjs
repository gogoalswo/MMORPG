/**
 * JPEG 텍스처를 KTX2(Basis Universal)로 압축한다.
 *
 * JPEG 은 다운로드 용량만 작을 뿐, GPU 에 올라갈 때는 RGBA 로 풀린다.
 * 1024² 한 장이 VRAM 4MB — 텍스처 9장이면 36MB 다.
 * KTX2 는 압축된 상태로 GPU 에 올라가서 다운로드 용량과 VRAM 을 동시에 줄인다.
 *
 * 맵 종류마다 인코딩을 달리한다:
 *  - color  : ETC1S + sRGB. 눈이 색 오차에 관대해서 가장 세게 줄인다.
 *  - normal : UASTC. ETC1S 로 누르면 법선이 뭉개져 요철이 계단처럼 보인다.
 *  - rough  : ETC1S + 선형. 단일 채널 데이터라 오차가 잘 안 보인다.
 *
 * 사용: node scripts/compress-textures.mjs
 */
import { readdir, readFile, writeFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import sharp from 'sharp';
import { encodeToKTX2 } from 'ktx2-encoder';

// 원본 JPEG 은 배포 대상이 아니므로 public/ 밖에 둔다
const SRC_DIR = 'assets-src/textures';
const OUT_DIR = 'public/assets/textures';

/** sharp 로 JPEG 을 풀어 32비트 RGBA 로 넘긴다 (Node 에서는 필수) */
async function imageDecoder(buffer) {
  const { data, info } = await sharp(buffer)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return { width: info.width, height: info.height, data: new Uint8Array(data) };
}

function optionsFor(name) {
  const base = {
    imageDecoder,
    isKTX2File: true,
    generateMipmap: true,
    compressionLevel: 4,
  };

  if (name.endsWith('_normal')) {
    return {
      ...base,
      isUASTC: true,
      isNormalMap: true,
      needSupercompression: true, // UASTC 는 크다. zstd 로 한 번 더 줄인다
      uastcLDRQualityLevel: 2,
      isPerceptual: false,
      isSetKTX2SRGBTransferFunc: false,
    };
  }

  if (name.endsWith('_rough')) {
    return {
      ...base,
      isUASTC: false,
      qualityLevel: 128,
      isPerceptual: false,
      isSetKTX2SRGBTransferFunc: false,
    };
  }

  // 색상 맵
  return {
    ...base,
    isUASTC: false,
    qualityLevel: 190,
    isPerceptual: true,
    isSetKTX2SRGBTransferFunc: true,
  };
}

const files = (await readdir(SRC_DIR)).filter((f) => f.endsWith('.jpg'));
if (files.length === 0) {
  console.error(`${SRC_DIR} 에 .jpg 가 없습니다. scripts/fetch-assets.sh 를 먼저 실행하세요.`);
  process.exit(1);
}

let before = 0;
let after = 0;

for (const file of files.sort()) {
  const name = file.replace(/\.jpg$/, '');
  const src = join(SRC_DIR, file);
  const dst = join(OUT_DIR, `${name}.ktx2`);

  const buffer = await readFile(src);
  const encoded = await encodeToKTX2(new Uint8Array(buffer), optionsFor(name));
  await writeFile(dst, encoded);

  const srcSize = (await stat(src)).size;
  before += srcSize;
  after += encoded.byteLength;

  const kind = name.endsWith('_normal') ? 'UASTC' : 'ETC1S';
  console.log(
    `  ${name.padEnd(16)} ${(srcSize / 1048576).toFixed(2)}MB -> ` +
      `${(encoded.byteLength / 1048576).toFixed(2)}MB  (${kind})`
  );
}

console.log(
  `\n합계 ${(before / 1048576).toFixed(1)}MB -> ${(after / 1048576).toFixed(1)}MB ` +
    `(${((1 - after / before) * 100).toFixed(0)}% 감소)`
);
console.log(`원본은 ${SRC_DIR}, 배포본은 ${OUT_DIR} (.ktx2 만 서빙된다)`);
