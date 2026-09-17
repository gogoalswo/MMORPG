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
import { copyFileSync, mkdirSync, statSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 복사할 것. 없으면 건너뛰고 화면은 기둥으로 대신 그린다 */
const MODELS = [
  'varco_knight.glb', // 캐릭터 (지금은 기사 고정)
  'varco_ogre1.glb', // 초원 몬스터 (mob003 · mob008 의 look)
];

const from = join(ROOT, 'public', 'assets', 'models');
const to = join(ROOT, 'godot', 'assets', 'models');
mkdirSync(to, { recursive: true });

let copied = 0;
for (const name of MODELS) {
  const src = join(from, name);
  if (!existsSync(src)) {
    console.log(`${name.padEnd(20)} 원본이 없다 — 건너뛴다`);
    continue;
  }
  const dst = join(to, name);
  // 같은 크기면 다시 쓰지 않는다. 고도가 매번 다시 임포트하지 않게
  if (existsSync(dst) && statSync(dst).size === statSync(src).size) {
    console.log(`${name.padEnd(20)} 그대로`);
    continue;
  }
  copyFileSync(src, dst);
  copied++;
  console.log(`${name.padEnd(20)} ${(statSync(dst).size / 1048576).toFixed(1)}MB 복사`);
}
console.log(`${copied}개 새로 복사했다 -> godot/assets/models/`);
