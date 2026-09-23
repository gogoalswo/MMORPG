/**
 * 던전 종류 카드 그림 중 **바르코 없이 코드로 그린 두 장**을 원본으로 뽑는다.
 *
 *   node scripts/draw-dungeon-art.mjs && node scripts/build-item-icons.mjs
 *
 * 2026-09-23 — 카드에 그림을 넣으라는 요청을 받았는데 그 세션에 바르코가 끊겨 있었다.
 * 사용자가 "일단 그렇게 그려봐" 라고 해서 **아트풍 문서의 아이콘 틀**(검은 바탕 위
 * 상아빛·옅은 금색으로 칠한 문장, 얇고 어두운 윤곽, 판·원판 없음)대로 SVG 로 그렸다
 * → docs/features/ui-art-style.md. 토벌(보스 머리)은 바르코 원본을 그대로 쓴다
 * (`fetch-assets.sh` 의 `dungeon_raid`). **바르코로 다시 뽑으면 이 스크립트는 지운다.**
 *
 * 결과는 assets-src/icons/dungeon_<id>.png (1024², 커밋하지 않는다) — 굽는 것은
 * build-item-icons.mjs 가 다른 아이콘과 똑같이 한다 (배경 걷기 · 줄이기).
 */
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'assets-src/icons');

// 색은 아트풍 문서의 표에서 그대로 가져왔다
const IVORY = '#eeead7';
const IVORY_SHADE = '#cfc6a6';
const GOLD = '#dfc97a';
const GOLD_SHADE = '#b9a46c';
const METAL = '#86714d';
const HOLE = '#241f16';
const LINE = '#16130e';
const W = 12;

const svg = (body) => `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<rect width="1024" height="1024" fill="#000"/>
<g stroke="${LINE}" stroke-width="${W}" stroke-linejoin="round" stroke-linecap="round">${body}</g>
</svg>`;

/** 네 갈래 반짝임 — 보물 창고 위에 뜬다 */
const sparkle = (x, y, r) =>
  `<path d="M${x} ${y - r} Q${x + r * 0.18} ${y - r * 0.18} ${x + r} ${y} Q${x + r * 0.18} ${y + r * 0.18} ${x} ${y + r} Q${x - r * 0.18} ${y + r * 0.18} ${x - r} ${y} Q${x - r * 0.18} ${y - r * 0.18} ${x} ${y - r} Z" fill="${GOLD}" stroke-width="8"/>`;

/** 창문 — 위가 둥근 좁은 구멍 */
const window = (x, y, w, h) =>
  `<path d="M${x - w / 2} ${y + h} V${y + w / 2} A${w / 2} ${w / 2} 0 0 1 ${x + w / 2} ${y + w / 2} V${y + h} Z" fill="${HOLE}"/>`;

// 시련의 탑 — 뾰족 지붕 + 성가퀴 띠 + 돌 몸통(아래로 넓어진다) + 아치 문
const trial = svg(`
  <rect x="300" y="862" width="424" height="62" rx="6" fill="${GOLD}"/>
  <rect x="300" y="894" width="424" height="30" fill="${GOLD_SHADE}" stroke="none"/>
  <rect x="300" y="862" width="424" height="62" rx="6" fill="none"/>
  <polygon points="378,392 646,392 690,864 334,864" fill="${IVORY}"/>
  <polygon points="512,392 646,392 690,864 512,864" fill="${IVORY_SHADE}" stroke="none"/>
  <polygon points="378,392 646,392 690,864 334,864" fill="none"/>
  <g stroke-width="7">
    <path d="M372 470 H652 M366 560 H658 M358 650 H666 M350 740 H674" fill="none"/>
    <path d="M440 392 V470 M584 392 V470 M470 470 V560 M556 470 V560 M420 560 V650 M604 560 V650 M456 650 V740 M570 650 V740 M400 740 V864 M624 740 V864" fill="none"/>
  </g>
  <rect x="354" y="600" width="316" height="36" fill="${GOLD}"/>
  ${window(512, 462, 58, 98)}
  <path d="M446 864 V780 A66 66 0 0 1 578 780 V864 Z" fill="${HOLE}"/>
  <path d="M446 864 V780 A66 66 0 0 1 578 780 V864" fill="none" stroke="${GOLD}" stroke-width="16"/>
  <path d="M446 864 V780 A66 66 0 0 1 578 780 V864" fill="none"/>
  <rect x="340" y="330" width="344" height="70" fill="${GOLD}"/>
  <rect x="512" y="330" width="172" height="70" fill="${GOLD_SHADE}" stroke="none"/>
  <rect x="340" y="330" width="344" height="70" fill="none"/>
  <path d="M340 330 V270 H392 V304 H440 V270 H490 V304 H534 V270 H584 V304 H632 V270 H684 V330 Z" fill="${IVORY}"/>
  <polygon points="512,92 640,270 384,270" fill="${GOLD}"/>
  <polygon points="512,92 640,270 512,270" fill="${GOLD_SHADE}" stroke="none"/>
  <polygon points="512,92 640,270 384,270" fill="none"/>
  <path d="M512 92 V40" fill="none" stroke-width="10"/>
  <path d="M512 42 L580 60 L512 80 Z" fill="${IVORY}" stroke-width="8"/>
`);

// 보물 창고 — 둥근 뚜껑 상자, 금 띠 둘 · 가운데 자물쇠, 위에 반짝임
const treasure = svg(`
  <path d="M206 560 V440 Q206 300 512 300 Q818 300 818 440 V560 Z" fill="${IVORY}"/>
  <path d="M512 300 Q818 300 818 440 V560 H512 Z" fill="${IVORY_SHADE}" stroke="none"/>
  <path d="M206 560 V440 Q206 300 512 300 Q818 300 818 440 V560 Z" fill="none"/>
  <rect x="206" y="560" width="612" height="300" rx="8" fill="${IVORY}"/>
  <rect x="512" y="560" width="306" height="300" fill="${IVORY_SHADE}" stroke="none"/>
  <rect x="206" y="560" width="612" height="300" rx="8" fill="none"/>
  <g stroke-width="7" fill="none">
    <path d="M226 640 H286 M382 640 H642 M738 640 H798 M226 740 H286 M382 740 H642 M738 740 H798"/>
    <path d="M230 420 Q260 360 296 342 M728 342 Q764 360 794 420"/>
  </g>
  <path d="M286 324 Q318 312 350 306 V860 H286 Z" fill="${GOLD}"/>
  <path d="M674 306 Q706 312 738 324 V860 H674 Z" fill="${GOLD_SHADE}"/>
  <rect x="192" y="540" width="640" height="44" rx="6" fill="${GOLD}"/>
  <rect x="512" y="540" width="320" height="44" fill="${GOLD_SHADE}" stroke="none"/>
  <rect x="192" y="540" width="640" height="44" rx="6" fill="none"/>
  <rect x="192" y="840" width="640" height="40" rx="6" fill="${GOLD}"/>
  <path d="M452 504 H572 V620 Q572 660 512 676 Q452 660 452 620 Z" fill="${GOLD}"/>
  <path d="M512 504 H572 V620 Q572 660 512 676 Z" fill="${GOLD_SHADE}" stroke="none"/>
  <path d="M452 504 H572 V620 Q572 660 512 676 Q452 660 452 620 Z" fill="none"/>
  <circle cx="512" cy="570" r="18" fill="${HOLE}" stroke-width="6"/>
  <path d="M504 580 L496 626 H528 L520 580 Z" fill="${HOLE}" stroke-width="6"/>
  <g fill="${METAL}" stroke-width="6">
    <circle cx="318" cy="600" r="10"/><circle cx="318" cy="800" r="10"/>
    <circle cx="706" cy="600" r="10"/><circle cx="706" cy="800" r="10"/>
  </g>
  ${sparkle(300, 190, 54)}
  ${sparkle(740, 150, 70)}
  ${sparkle(560, 196, 34)}
`);

mkdirSync(OUT, { recursive: true });
for (const [name, body] of [['dungeon_trial', trial], ['dungeon_treasure', treasure]]) {
  const out = join(OUT, `${name}.png`);
  await sharp(Buffer.from(body)).png().toFile(out);
  console.log(`그렸다: ${out}`);
}
