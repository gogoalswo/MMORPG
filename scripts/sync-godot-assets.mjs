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
  'varco_knight.glb', // 캐릭터 (지금은 기사 고정)
  'varco_ogre1.glb', // 초원 몬스터 (mob003 · mob008 의 look)
];

/** 한글 폰트. 고도 기본 폰트에는 한글 글리프가 없어 넣지 않으면 네모로 나온다 */
const FONTS = ['NotoSansKR-subset.ttf'];

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
  { names: FONTS, from: join(ROOT, 'public', 'assets', 'fonts'), to: join(ROOT, 'godot', 'assets', 'fonts') },
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
