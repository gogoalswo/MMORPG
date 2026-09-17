/**
 * .glb 안에 박힌 텍스처를 줄인다.
 *
 * 왜 — varco 모델은 1024x1024 텍스처를 셋씩 들고 있는데, 고도가 임포트하면서
 * 데스크톱·모바일 두 포맷으로 구워 **원본 1MB 가 10MB 로 불어난다.** 폰 화면에서
 * 1024 와 512 는 거의 구분이 안 되므로 절반으로 줄이면 네 배가 준다.
 *
 * 고도 임포트 설정으로 줄여 보려 했지만 안 됐다 (2026-09-17):
 *  - `gltf/embedded_image_handling=2`(Basis Universal) → pck 13MB **→ 21.8MB**. 더 커졌다
 *  - 익스포트 프리셋의 `vram_texture_compression/for_desktop=false` → 변화 없음
 * 그래서 원본을 줄이는 쪽으로 한다. 판올림해도 안 깨지는 방법이기도 하다.
 *
 *   node scripts/shrink-glb-textures.mjs 입력.glb 출력.glb 512
 *
 * 원본(public/assets/models)은 건드리지 않는다. 고도가 쓰는 사본만 줄인다.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import sharp from 'sharp';

const JSON_CHUNK = 0x4e4f534a;
const BIN_CHUNK = 0x004e4942;

export async function shrinkGlb(srcPath, dstPath, maxSize) {
  const buf = readFileSync(srcPath);
  if (buf.readUInt32LE(0) !== 0x46546c67) throw new Error('glb 가 아니다: ' + srcPath);

  // 청크 둘을 읽는다 (JSON, BIN)
  let offset = 12;
  let json = null;
  let bin = null;
  while (offset < buf.length) {
    const length = buf.readUInt32LE(offset);
    const type = buf.readUInt32LE(offset + 4);
    const data = buf.subarray(offset + 8, offset + 8 + length);
    if (type === JSON_CHUNK) json = JSON.parse(data.toString('utf8'));
    else if (type === BIN_CHUNK) bin = data;
    offset += 8 + length + ((4 - (length % 4)) % 4);
  }
  if (!json || !bin) throw new Error('JSON/BIN 청크를 못 찾았다');

  // 이미지 bufferView 를 줄인 것으로 바꾼다
  const replaced = new Map();
  for (const image of json.images ?? []) {
    if (image.bufferView === undefined) continue;
    const view = json.bufferViews[image.bufferView];
    const bytes = bin.subarray(view.byteOffset ?? 0, (view.byteOffset ?? 0) + view.byteLength);
    const shrunk = await sharp(bytes)
      .resize(maxSize, maxSize, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 85 })
      .toBuffer();
    replaced.set(image.bufferView, shrunk);
    image.mimeType = 'image/jpeg';
  }

  // BIN 을 처음부터 다시 쌓는다. **순서를 지키고 4바이트로 맞춘다** —
  // accessor 는 bufferView 번호로 가리키므로 번호만 안 바뀌면 된다
  const pieces = [];
  let cursor = 0;
  for (let i = 0; i < json.bufferViews.length; i++) {
    const view = json.bufferViews[i];
    const data =
      replaced.get(i) ?? bin.subarray(view.byteOffset ?? 0, (view.byteOffset ?? 0) + view.byteLength);
    const pad = (4 - (cursor % 4)) % 4;
    if (pad > 0) {
      pieces.push(Buffer.alloc(pad));
      cursor += pad;
    }
    view.byteOffset = cursor;
    view.byteLength = data.length;
    pieces.push(data);
    cursor += data.length;
  }
  const newBin = Buffer.concat(pieces);
  json.buffers[0].byteLength = newBin.length;

  // 다시 GLB 로 묶는다
  const jsonBuf = Buffer.from(JSON.stringify(json), 'utf8');
  const jsonPad = (4 - (jsonBuf.length % 4)) % 4;
  const binPad = (4 - (newBin.length % 4)) % 4;
  const total =
    12 + 8 + jsonBuf.length + jsonPad + 8 + newBin.length + binPad;

  const out = Buffer.alloc(total);
  let p = 0;
  out.writeUInt32LE(0x46546c67, p); p += 4; // glTF
  out.writeUInt32LE(2, p); p += 4;
  out.writeUInt32LE(total, p); p += 4;
  out.writeUInt32LE(jsonBuf.length + jsonPad, p); p += 4;
  out.writeUInt32LE(JSON_CHUNK, p); p += 4;
  jsonBuf.copy(out, p); p += jsonBuf.length;
  out.fill(0x20, p, p + jsonPad); p += jsonPad; // JSON 패딩은 공백
  out.writeUInt32LE(newBin.length + binPad, p); p += 4;
  out.writeUInt32LE(BIN_CHUNK, p); p += 4;
  newBin.copy(out, p); p += newBin.length;

  writeFileSync(dstPath, out);
  return out.length;
}

if (process.argv[1] && process.argv[1].endsWith('shrink-glb-textures.mjs')) {
  const [, , src, dst, size = '512'] = process.argv;
  if (!src || !dst) throw new Error('입력.glb 출력.glb [크기]');
  const bytes = await shrinkGlb(src, dst, Number(size));
  console.log(`${dst}: ${(bytes / 1048576).toFixed(2)}MB`);
}
