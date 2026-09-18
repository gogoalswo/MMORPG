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
/** 내보낼 한 변 크기 */
const SIZE = 128;

/**
 * 가장자리에서 시작해 배경색과 비슷한 픽셀을 따라 번지며 알파를 0 으로 만든다.
 * 이어진 것만 지우므로 그림 안쪽의 같은 색은 남는다.
 *
 * 배경색을 **테두리 전체에서 모은다.** 모서리만 보면 안 된다 — 바르코가 준
 * 아이콘 중 셋(반지·벨트·검)은 배경이 **둥근 사각형**이라 모서리 색(바깥 흰색)과
 * 안쪽 배경색(검정)이 다르다. 모서리 평균으로 잡았더니 모서리 1~7% 만 걷히고
 * 검은 배경이 그대로 남았다.
 */
function cutBackground(data, width, height) {
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

  for (let layer = 0; layer < LAYERS; layer += 1) {
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
      ) <= TOLERANCE);
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
      ) <= TOLERANCE);
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
  const cut = cutBackground(data, info.width, info.height);
  const out = join(DST, basename(name));
  await sharp(data, { raw: { width: info.width, height: info.height, channels: 4 } })
    .resize(SIZE, SIZE, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 })
    .toFile(out);
  const share = ((cut / (info.width * info.height)) * 100).toFixed(0);
  console.log(`  -> public/assets/icons/${basename(name)} (배경 ${share}% 걷어냄)`);
}
