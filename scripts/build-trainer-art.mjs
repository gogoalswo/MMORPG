/**
 * PT 트레이너 원화 → 카드 그림 (docs/features/trainers.md "원화").
 *
 * 바르코 원화(9:16, 전신, 흰 바탕 · 약 1MB)를 **머리부터 허리 아래까지 3:4 로 잘라** 240×320 JPG 로 굽는다
 * (한 장 20KB 남짓 — 53장이 1MB 대라 커밋한다). 카드(126×168)와 상세 창(240×320)이 같은 그림을 쓴다.
 *
 *   node scripts/build-trainer-art.mjs        assets-src/trainers/<id>.png → public/assets/trainers/trainer_<id>.jpg
 *
 * 원본은 `scripts/fetch-assets.sh` 의 트레이너 줄이 받는다 (커밋하지 않는다).
 */
import { readdirSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname, basename, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'assets-src', 'trainers');
const OUT = join(ROOT, 'public', 'assets', 'trainers');
const WIDTH = 240;
const HEIGHT = 320;
/** 위에서 이만큼(원화 높이 대비)을 자른다 — 머리 위 여백 3% 를 빼고 허벅지 중간까지 */
const TOP = 0.03;
const SPAN = 0.6;

// 뽑기 연출의 바닥판 (2026-10-06, docs/features/trainers.md "뽑기 연출") — 바르코 그림(8×8 칸, 1024²)을 그대로 JPG 로
const BOARD = join(ROOT, 'assets-src', 'textures', 'varco', 'trainer_board.png');
if (existsSync(BOARD)) {
  mkdirSync(OUT, { recursive: true });
  await sharp(BOARD).jpeg({ quality: 84, mozjpeg: true }).toFile(join(OUT, 'trainer_board.jpg'));
  console.log('뽑기 바닥판 → public/assets/trainers/trainer_board.jpg');
}

if (!existsSync(SRC)) {
  console.log(`원본이 없다: ${SRC} — scripts/fetch-assets.sh 를 먼저 돌린다`);
  process.exit(0);
}
mkdirSync(OUT, { recursive: true });
let count = 0;
for (const file of readdirSync(SRC).sort()) {
  if (!/\.(png|jpe?g|webp)$/i.test(file)) continue;
  const id = basename(file, extname(file));
  const src = sharp(join(SRC, file));
  const { width, height } = await src.metadata();
  const cropH = Math.round(height * SPAN);
  const cropW = Math.min(width, Math.round((cropH * WIDTH) / HEIGHT));
  await src
    .extract({ left: Math.round((width - cropW) / 2), top: Math.round(height * TOP), width: cropW, height: cropH })
    .resize(WIDTH, HEIGHT)
    .flatten({ background: '#ffffff' })
    .jpeg({ quality: 82, mozjpeg: true })
    .toFile(join(OUT, `trainer_${id}.jpg`));
  count++;
}
console.log(`트레이너 원화 ${count}장 → public/assets/trainers/`);

