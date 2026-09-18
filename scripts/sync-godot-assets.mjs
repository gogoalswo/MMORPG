/**
 * 고도가 쓸 에셋을 godot/assets/ 로 복사한다.
 *
 * 왜 복사하나 — 고도는 프로젝트 폴더(res://) 밖의 파일을 임포트하지 못한다.
 * 그렇다고 저장소에 같은 GLB 를 두 벌 두면 24MB 가 이력에 두 번 쌓이므로,
 * `godot/assets/` 는 커밋하지 않고 이 스크립트로 만든다 (fetch-assets.sh 와 같은 방식).
 *
 *   npm run sync:godot
 *
 * **쓰는 것만 복사한다.** 웹 빌드는 여기 있는 파일을 전부 담으므로, 안 쓰는
 * 모델을 넣으면 폰에서 받을 용량만 커진다. 직업이 늘면 여기 줄을 더한다.
 */
import { copyFileSync, mkdirSync, statSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { shrinkGlb } from './shrink-glb-textures.mjs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 복사할 것. 없으면 건너뛰고 화면은 기둥으로 대신 그린다 */
const MODELS = [
  'varco_fighter.glb', // 캐릭터 (기본 직업 격투가 고정)
  'varco_ogre1.glb', // 초원 몬스터 (mob003 · mob008 의 look)
  'varco_portal.glb', // 차원문 (모든 존의 GATE_SPOT)
];

/** UI 조각. 이미 build-ui.mjs 가 줄여 둔 것이라 그대로 복사한다 */
const UI = ['panel.png', 'gate_here.png', 'gate_go.png'];

/** 한글 폰트. 고도 기본 폰트에는 한글 글리프가 없어 넣지 않으면 네모로 나온다 */
const FONTS = ['NotoSansKR-subset.ttf'];

/**
 * 가방·장착 창 아이콘과 테두리. 바르코로 만들고 `scripts/build-item-icons.mjs` 가
 * 배경을 걷어 구운 것이다 (public/assets/icons).
 *
 * **쓰는 것만 복사한다.** 슬롯 6칸이 전부 그림을 갖췄다. 받아 둔 장갑(glove)·
 * 벨트(belt)는 어느 칸에 쓸지 안 정해서 뺐고, 보조(offhand)는 슬롯 자체를 없앴다.
 */
const ICONS = [
  'weapon.png', 'armor.png', 'helmet.png',
  'boots.png', 'necklace.png', 'ring.png',
  'bag.png', 'gold.png',
  'frame_panel.png', 'frame_slot.png',
];

/**
 * 바닥 텍스처 7종(색 + 노멀). **고도가 .ktx2 를 그대로 읽는다** — 시험해 보고
 * 확인했다 (2026-09-17). 일곱 장을 전부 넣는다: 존마다 받으면 존 구성이
 * 비동기가 되는데 그만한 크기가 아니다 (14장 2.5MB).
 */
const GROUND = [
  'stone', 'grass', 'snow', 'dirt', 'sand', 'cobble', 'lava',
].flatMap((kind) => [`ground_${kind}_color.ktx2`, `ground_${kind}_normal.ktx2`]);

/**
 * 모델 텍스처를 얼마나 줄이나. 1024 짜리를 그대로 두면 고도가 두 포맷으로 구워
 * pck 가 13MB 가 된다 (scripts/shrink-glb-textures.mjs 에 재 본 값이 있다).
 * 폰 화면에서 512 와 1024 는 거의 구분되지 않는다.
 */
const MAX_TEXTURE = 512;

const jobs = [
  {
    names: MODELS,
    from: join(ROOT, 'public', 'assets', 'models'),
    to: join(ROOT, 'godot', 'assets', 'models'),
    shrink: true,
  },
  { names: UI, from: join(ROOT, 'public', 'assets', 'ui'), to: join(ROOT, 'godot', 'assets', 'ui') },
  { names: FONTS, from: join(ROOT, 'public', 'assets', 'fonts'), to: join(ROOT, 'godot', 'assets', 'fonts') },
  { names: ICONS, from: join(ROOT, 'public', 'assets', 'icons'), to: join(ROOT, 'godot', 'assets', 'icons') },
  { names: GROUND, from: join(ROOT, 'public', 'assets', 'textures'), to: join(ROOT, 'godot', 'assets', 'ground') },
];

let copied = 0;
for (const job of jobs) copied += await run(job);
console.log(`${copied}개 새로 복사했다 -> godot/assets/`);

async function run({ names, from, to, shrink }) {
  mkdirSync(to, { recursive: true });
  // 원본이 안 바뀌었으면 다시 쓰지 않는다. 고도가 매번 다시 임포트하지 않게.
  // 줄인 파일은 크기가 원본과 다르므로 무엇으로 만들었는지를 따로 적어 둔다
  const stampPath = join(to, '.source.json');
  const stamp = existsSync(stampPath) ? JSON.parse(readFileSync(stampPath, 'utf8')) : {};
  let n = 0;

  for (const name of names) {
    const src = join(from, name);
    if (!existsSync(src)) {
      console.log(`${name.padEnd(24)} 원본이 없다 — 건너뛴다`);
      continue;
    }
    const dst = join(to, name);
    const key = `${statSync(src).size}:${shrink ? MAX_TEXTURE : 0}`;
    if (existsSync(dst) && stamp[name] === key) {
      console.log(`${name.padEnd(24)} 그대로`);
      continue;
    }

    if (shrink) await shrinkGlb(src, dst, MAX_TEXTURE);
    else copyFileSync(src, dst);
    stamp[name] = key;
    n++;
    const before = statSync(src).size / 1048576;
    const after = statSync(dst).size / 1048576;
    const note = shrink ? ` (원본 ${before.toFixed(1)}MB, 텍스처 ${MAX_TEXTURE}px)` : '';
    console.log(`${name.padEnd(24)} ${after.toFixed(1)}MB${note}`);
  }

  writeFileSync(stampPath, JSON.stringify(stamp, null, 2) + '\n');
  return n;
}
