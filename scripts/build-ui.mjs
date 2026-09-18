/**
 * UI 조각을 게임이 쓰는 크기로 줄인다 — assets-src/textures/varco/ui_*.png → public/assets/ui/*.png
 *
 * **UI 는 그림 한 장이 아니라 조각이다.** 창 바탕·칸 아이콘을 따로 만들고 고도에서
 * 앵커·NinePatchRect 로 조립한다. 해상도가 바뀌어도 자리를 잡기 위해서다 (CLAUDE.md).
 * 그래서 조각마다 크기가 다르다:
 *  - 창 바탕은 9분할로 늘여 쓰므로 테두리만 살면 된다. 1024 원본의 테두리가 약 26px →
 *    256 으로 줄이면 약 7px 이고, 고도 쪽 여백(`GatePanel.PATCH`)을 12 로 잡았다.
 *  - 칸 아이콘은 화면에서 60px 안팎이라 128 이면 넉넉하다.
 *
 * 받는 곳은 scripts/fetch-assets.sh. 결과물(public/assets/ui)은 작아서 커밋한다.
 *
 *   node scripts/build-ui.mjs
 */
import { existsSync, mkdirSync } from 'node:fs';
import sharp from 'sharp';

const SRC = 'assets-src/textures/varco';
const OUT = 'public/assets/ui';

/** 원본 이름 → [게임 이름, 한 변 px] */
const PIECES = {
  'ui_panel.png': ['panel.png', 256], // 창 바탕 (9분할)
  'ui_gate_here.png': ['gate_here.png', 128], // 차원문 칸 — 지금 서 있는 곳 (소용돌이)
  'ui_gate_go.png': ['gate_go.png', 128], // 차원문 칸 — 갈 수 있는 곳 (별)
};

mkdirSync(OUT, { recursive: true });
for (const [src, [name, size]] of Object.entries(PIECES)) {
  if (!existsSync(`${SRC}/${src}`)) {
    console.log(`건너뜀: ${src} — 원본이 없다`);
    continue;
  }
  await sharp(`${SRC}/${src}`).resize(size, size, { kernel: 'lanczos3' }).png({ compressionLevel: 9 }).toFile(`${OUT}/${name}`);
  console.log(`  -> ${OUT}/${name} (${size}px)`);
}
