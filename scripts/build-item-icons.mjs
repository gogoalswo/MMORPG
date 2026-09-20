/**
 * 바르코로 만든 아이콘 원본을 UI 가 쓸 PNG 로 굽는다.
 *
 *   node scripts/build-item-icons.mjs
 *
 * 원본(assets-src/icons/*.png)은 1024² 에 **배경이 칠해져 있다** — 검은 것도
 * 흰 것도 섞여 있다 (바르코가 프롬프트마다 다르게 준다). 그대로 UI 칸에 넣으면
 * 흰 배경 아이콘이 어두운 창에서 흰 사각형으로 번쩍인다.
 *
 * 그래서 두 가지를 한다:
 *  1. **테두리에서 번져 들어가는 배경만** 투명으로 만든다. 밝기로 자르면
 *     안쪽의 흰 칠(동전·장화)까지 뚫려서 속이 빈다 — 그래서 가장자리에서
 *     시작하는 채우기(BFS)로 이어진 배경만 걷어낸다.
 *  2. 128px 로 줄인다. 칸이 폰에서 96~112px 이라 그 이상은 용량만 먹는다.
 *
 * 결과는 public/assets/icons/ 에 남고 **커밋한다** (public/assets/fx 와 같다).
 * 원본은 커밋하지 않는다 — fetch-assets.sh 가 주소를 들고 있다.
 */
import { readdirSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'assets-src/icons');
const DST = join(ROOT, 'public/assets/icons');

/**
 * 배경으로 볼 색 차이. **넉넉히 주면 안 된다** — 46 으로 뒀더니 동전의 얇은
 * 외곽선을 뚫고 번져서 앞면(흰 칠)까지 먹었다. 배경은 어차피 단색이라 좁아도 잡힌다
 */
const TOLERANCE = 24;
/**
 * 배경을 몇 겹까지 벗기나. 검 아이콘은 **흰 여백 안에 검은 둥근 사각형**이 또 있어서
 * 한 번만 벗기면 검은 판이 그대로 남는다 (7% 만 걷혔다)
 */
const LAYERS = 3;
/**
 * 한 겹을 더 벗길지 정하는 선. 첫 겹이 이만큼 이상 걷어냈으면 **거기가 진짜 배경**이고
 * 다음 겹은 그림이다 — 조건 없이 세 겹을 벗겼더니 동전이 통째로 지워졌다(100%).
 * 검처럼 바깥이 얇은 여백(7%)일 때만 한 겹 더 들어간다
 */
const THIN_MARGIN = 0.25;
/**
 * 내보낼 한 변 크기. 테두리는 9조각으로 늘여 쓴다 — **모서리 조각은 원본 픽셀
 * 크기 그대로 그려지므로** 칸(88px)보다 큰 텍스처를 쓰면 모서리가 서로 겹쳐
 * 뭉갠다. 그래서 칸 테두리는 128, 창 테두리는 넓으니 256 으로 굽는다
 */
const SIZE = 128;
const FRAME_SIZE = {
  'frame_panel.png': 256,
  'frame_slot.png': 128,
  'ui_panel.png': 256,
  'ui_subpanel.png': 192,
  'ui_slot.png': 128,
  'ui_tab_on.png': 192,
  'ui_tab_off.png': 192,
  'ui_button.png': 192,
  'ui_figure.png': 384,
  'ui_skill_slot.png': 128,
  'ui_slot_pick.png': 128,
  // HUD 조각 (2026-09-19). 막대는 가로로 길어 긴 변을 256 으로 맞춘다 —
  // 9조각으로 늘여 쓰므로 끝 모서리가 원본 픽셀 크기 그대로 그려진다
  'ui_bar_frame.png': 256,
  'ui_bar_fill.png': 256,
  'ui_auto_spin.png': 192,
  'ui_level_badge.png': 192,
  'ui_quick_slot.png': 128,
};
/**
 * **배경을 걷지 않는 것.** 스킬 아이콘은 칸을 꽉 채운 그림이라 가장자리가 곧 그림이다.
 * 테두리에서 번지는 채우기를 돌리면 가장자리와 비슷한 색(어두운 연기·하늘)을 따라
 * 그림 속까지 파먹는다. 줄이기만 한다
 */
const FULL = /^skill_/;
/**
 * **알파 경계로 잘라내는 것.** 바르코는 그림 둘레에 배경을 넉넉히 남기는데,
 * 9조각으로 늘여 쓰려면 테가 그림 가장자리에 닿아 있어야 여백을 재기 쉽다.
 * 배경을 걷은 다음 남은 부분에 딱 맞게 자른다. 비율은 그대로 두고 긴 변을 맞춘다
 */
const TRIM = /^ui_/;
/**
 * **안쪽도 뚫는 것.** 칸 테두리는 가운데가 흰 판으로 차 있는데, 테두리에서
 * 번져 들어가는 채우기로는 닿지 못한다 (테가 막고 있다). 이 이름들은 한가운데에서
 * 한 번 더 번지게 한다. 창 테두리(frame_panel)는 **안쪽을 남긴다** — 그게 창 바탕이다
 */
const HOLLOW = new Set([
  'frame_slot.png',
  'ui_slot_pick.png',
  // 고리 한가운데는 비어야 한다 — 칸 아이콘 위에서 도는 것이라
  'ui_auto_spin.png',
]);
/**
 * **배경을 한 겹만 걷는 것.** ★ 얇은 선으로 그린 HUD 조각(막대 홈·배지·칸)은
 * 안쪽이 어두운 판인데, 그림이 화면을 꽉 채워 첫 겹이 조금밖에 못 걷는다.
 * 그러면 `THIN_MARGIN` 규칙이 한 겹 더 들어가 **안쪽 어두운 판까지 먹는다**
 * (2026-09-20). 이 조각들은 안쪽을 남겨야 한다 — 막대 빈 쪽 바닥이 그것이다
 */
const SINGLE_LAYER = new Set([
  'ui_bar_frame.png',
  'ui_level_badge.png',
  'ui_quick_slot.png',
  // 인벤토리 조각도 같은 사정이다 — 안쪽이 어두운 판이라 두 겹째가 그 판을 먹는다
  'ui_panel.png',
  'ui_subpanel.png',
  'ui_slot.png',
  'ui_tab_on.png',
  'ui_tab_off.png',
  'ui_button.png',
]);
/**
 * **배경을 넓은 폭으로 걷는 것.** ★ 칠해서 받은 조각은 테 바깥에 **흰 배경과
 * 미묘하게 다른 밝은 회색 번짐**이 깔려 있다. 기본 폭(24)으로는 그것이 안 걷혀
 * **칸마다 흰 테가 둘러진다** (2026-09-20, 찍어서 봤다). 안쪽은 어두운 판이라
 * 폭을 넓혀도 안쪽까지는 넘어오지 못한다
 */
const WIDE = 96;
const WIDE_TOLERANCE = new Set([
  // ui_panel 은 넣지 않는다 — 넓은 폭으로 걷었더니 **창 바탕까지 걷혀**
  // 금테만 남고 안이 뚫렸다 (2026-09-20, 찍어서 봤다)
  'ui_subpanel.png',
  'ui_slot.png',
  'ui_slot_pick.png',
  'ui_tab_on.png',
  'ui_tab_off.png',
  'ui_button.png',
  'ui_figure.png',
]);

/** 알파가 남아 있는 칸의 바깥 테두리 상자 */
function alphaBounds(data, width, height) {
  let x0 = width;
  let y0 = height;
  let x1 = -1;
  let y1 = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (data[(y * width + x) * 4 + 3] <= 8) continue;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  if (x1 < 0) return null;
  return { left: x0, top: y0, width: x1 - x0 + 1, height: y1 - y0 + 1 };
}

/**
 * 가장자리에서 시작해 배경색과 비슷한 픽셀을 따라 번지며 알파를 0 으로 만든다.
 * 이어진 것만 지우므로 그림 안쪽의 같은 색은 남는다.
 *
 * 배경색을 **테두리 전체에서 모은다.** 모서리만 보면 안 된다 — 바르코가 준
 * 아이콘 중 셋(반지·벨트·검)은 배경이 **둥근 사각형**이라 모서리 색(바깥 흰색)과
 * 안쪽 배경색(검정)이 다르다. 모서리 평균으로 잡았더니 모서리 1~7% 만 걷히고
 * 검은 배경이 그대로 남았다.
 */
function cutBackground(data, width, height, layers = LAYERS, tolerance = TOLERANCE) {
  const count = width * height;
  const cut = new Uint8Array(count);

  /** 바깥(테두리 밖 또는 이미 걷어낸 자리)에 닿아 있는 칸들 */
  const rim = () => {
    const out = [];
    for (let p = 0; p < count; p += 1) {
      if (cut[p]) continue;
      const x = p % width;
      const y = (p - x) / width;
      if (x === 0 || y === 0 || x === width - 1 || y === height - 1) {
        out.push(p);
        continue;
      }
      if (cut[p - 1] || cut[p + 1] || cut[p - width] || cut[p + width]) out.push(p);
    }
    return out;
  };

  for (let layer = 0; layer < layers; layer += 1) {
    if (layer > 0 && cut.reduce((sum, v) => sum + v, 0) >= count * THIN_MARGIN) break;
    const seeds = rim();
    if (seeds.length === 0) break;

    // 그 자리에 실제로 있는 색들을 후보로 모은다. 충분히 많이 나온 색만 배경으로
    // 본다 — 그림이 테두리에 살짝 닿아도 그 색까지 지우지 않도록
    const candidates = [];
    for (const p of seeds) {
      const i = p * 4;
      const near = candidates.find((c) => (
        Math.abs(c.r - data[i]) + Math.abs(c.g - data[i + 1]) + Math.abs(c.b - data[i + 2])
      ) <= tolerance);
      if (near) near.count += 1;
      else candidates.push({ r: data[i], g: data[i + 1], b: data[i + 2], count: 1 });
    }
    const colors = candidates.filter((c) => c.count >= seeds.length * 0.08);
    if (colors.length === 0) break;

    const queue = [];
    const push = (p) => {
      if (p < 0 || p >= count || cut[p]) return;
      const i = p * 4;
      const near = colors.some((c) => (
        Math.abs(data[i] - c.r) + Math.abs(data[i + 1] - c.g) + Math.abs(data[i + 2] - c.b)
      ) <= tolerance);
      if (!near) return;
      cut[p] = 1;
      queue.push(p);
    };

    for (const p of seeds) push(p);
    while (queue.length > 0) {
      const p = queue.pop();
      data[p * 4 + 3] = 0;
      const x = p % width;
      if (x > 0) push(p - 1);
      if (x < width - 1) push(p + 1);
      push(p - width);
      push(p + width);
    }
  }
  return cut.reduce((sum, v) => sum + v, 0);
}

/** 한가운데에서 번지며 같은 색이 이어지는 만큼 뚫는다 (테 안쪽 판을 걷을 때) */
function cutCenter(data, width, height) {
  const count = width * height;
  const start = (height >> 1) * width + (width >> 1);
  const i0 = start * 4;
  if (data[i0 + 3] === 0) return 0;
  const near = (p) => {
    const i = p * 4;
    return data[i + 3] !== 0
      && Math.abs(data[i] - data[i0]) + Math.abs(data[i + 1] - data[i0 + 1])
        + Math.abs(data[i + 2] - data[i0 + 2]) <= TOLERANCE;
  };
  const queue = [start];
  let n = 0;
  while (queue.length > 0) {
    const p = queue.pop();
    if (!near(p)) continue;
    data[p * 4 + 3] = 0;
    n += 1;
    const x = p % width;
    if (x > 0) queue.push(p - 1);
    if (x < width - 1) queue.push(p + 1);
    if (p >= width) queue.push(p - width);
    if (p + width < count) queue.push(p + width);
  }
  return n;
}

if (!existsSync(SRC)) {
  console.log(`건너뜀: 아이콘 원본이 없다 (${SRC}) — scripts/fetch-assets.sh 를 돌린다`);
  process.exit(0);
}

mkdirSync(DST, { recursive: true });

for (const name of readdirSync(SRC).filter((f) => f.endsWith('.png')).sort()) {
  const src = join(SRC, name);
  const { data, info } = await sharp(src)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  let cut = FULL.test(name)
    ? 0
    : cutBackground(
      data,
      info.width,
      info.height,
      SINGLE_LAYER.has(name) ? 1 : LAYERS,
      WIDE_TOLERANCE.has(name) ? WIDE : TOLERANCE,
    );
  if (HOLLOW.has(name)) cut += cutCenter(data, info.width, info.height);
  const out = join(DST, basename(name));
  const size = FRAME_SIZE[name] ?? SIZE;
  const raw = { width: info.width, height: info.height, channels: 4 };
  let image = sharp(data, { raw });
  let note = '';

  if (TRIM.test(name)) {
    // 남은 그림에 딱 맞게 자르고, 비율을 지킨 채 긴 변을 맞춘다
    const box = alphaBounds(data, info.width, info.height);
    if (box != null) {
      image = image.extract(box);
      const scale = size / Math.max(box.width, box.height);
      image = image.resize(
        Math.max(1, Math.round(box.width * scale)),
        Math.max(1, Math.round(box.height * scale))
      );
      note = ` ${Math.round(box.width * scale)}x${Math.round(box.height * scale)}`;
    }
  } else {
    image = image.resize(size, size, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    });
  }

  await image.png({ compressionLevel: 9 }).toFile(out);
  const share = ((cut / (info.width * info.height)) * 100).toFixed(0);
  console.log(`  -> public/assets/icons/${basename(name)} (배경 ${share}% 걷어냄)${note}`);
}
