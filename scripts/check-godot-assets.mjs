/**
 * **고도 코드가 부르는 에셋이 `sync-godot-assets.mjs` 목록에 다 있는지** 본다 (2026-10-02).
 *
 * 왜 — `_icon()` 은 그림이 없으면 조용히 null 을 돌려주고, 모델도 없으면 기둥으로
 * 대신 그린다. 목록에 이름을 안 넣으면 **아무 테스트도 깨지지 않고 배포 화면에서만
 * 그림이 빠진다.** 목록에 있는데 파일이 없거나 커밋이 안 된 것은 동기화가 잡는다
 * (`sync-godot-assets.mjs` 의 problems) — 이 검사는 그 반대쪽, "목록에 없는 것" 이다.
 *
 *   node scripts/check-godot-assets.mjs     (npm run test:godot 이 동기화 뒤에 부른다)
 *
 * 부르는 이름은 두 곳에서 모은다.
 *   1. 코드의 문자열 — 확장자가 붙은 것(`"varco_tomb.glb"`), `"ui_…"`, `_icon("…")`·`_add_icon(…, "…"`
 *   2. 데이터 규칙 — 스킬 `skill_<icon_of>` · 재료 `<id>` · 장비 `<슬롯>_g<등급>`
 *      (game.gd 의 `_fill_skill_cell` · `_item_icon` 과 같은 규칙)
 *
 * 이름을 조립하는 규칙을 game.gd 에서 바꾸면 여기 2번도 같이 고친다.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { jobs } from './sync-godot-assets.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const GODOT = join(ROOT, 'godot');

/** 확장자 → 고도 쪽 폴더. 목록의 `to` 와 맞춘다 */
const EXT_DIR = { glb: 'models', png: 'icons', ttf: 'fonts', ktx2: 'textures', wav: 'sfx' };

/**
 * 고를 수 있는 직업. 지금은 격투가 고정이라 마법사·궁수 스킬(옛 표에 남아 있다)은
 * 그림을 안 받았다. 직업이 늘면 여기 더한다 (sync-godot-assets.mjs 의 MODELS 처럼)
 */
const JOBS = ['fighter'];

/** 일부러 그림 없이 두는 이름 — 코드가 글자로 대신한다. 넣을 때는 이유를 적는다 */
const NO_ASSET = new Set([]);

const listed = new Set(
  jobs.flatMap((job) => job.names.map((name) => `${basename(job.to)}/${name}`)),
);

/** 이름 → 처음 나온 자리 (보고용) */
const wanted = new Map();
const want = (path, where) => {
  if (!wanted.has(path)) wanted.set(path, where);
};

// 1. 코드의 문자열. 테스트는 뺀다 — 없는 것을 일부러 부르기도 한다
for (const dir of ['game', 'world', 'net']) {
  for (const file of gdFiles(join(GODOT, dir))) {
    const rel = file.slice(GODOT.length + 1).replaceAll('\\', '/');
    readFileSync(file, 'utf8').split(/\r?\n/).forEach((line, i) => {
      const code = line.replace(/^\s*#.*$/, '');
      const where = `${rel}:${i + 1}`;
      for (const [, name, ext] of code.matchAll(/"(?:res:\/\/assets\/[a-z]+\/)?([A-Za-z0-9_-]+)\.(glb|png|ttf|ktx2|wav)"/g)) {
        want(`${EXT_DIR[ext]}/${name}.${ext}`, where);
      }
      for (const [, name] of code.matchAll(/"(ui_[a-z0-9_]*[a-z0-9])"/g)) want(`icons/${name}.png`, where);
      for (const [, name] of code.matchAll(/_icon\("([a-z0-9_]+)"\)/g)) want(`icons/${name}.png`, where);
      for (const [, name] of code.matchAll(/_add_icon\([^,]+,\s*"([a-z0-9_]+)"/g)) want(`icons/${name}.png`, where);
    });
  }
}

// 2. 데이터 규칙
const data = (name) => JSON.parse(readFileSync(join(GODOT, 'data', `${name}.json`), 'utf8'));
const skills = data('skills');
const items = data('items');
const iconOf = (id) => skills.passives.find((p) => p.id === id)?.icon ?? id;
const skillIds = [...Object.values(skills.skills), ...skills.passives]
  .filter((s) => JOBS.includes(s.job))
  .map((s) => s.id);
for (const id of skillIds) {
  want(`icons/skill_${iconOf(id)}.png`, 'skills.json → skill_<icon_of>');
}
for (const id of Object.keys(materialsById(items.materials))) want(`icons/${id}.png`, 'items.json materials');
for (const slot of items.slots) {
  for (let g = items.gradeMin; g <= items.gradeMax; g++) want(`icons/${slot}_g${g}.png`, 'items.json <슬롯>_g<등급>');
}

const missing = [...wanted].filter(([path]) => !listed.has(path) && !NO_ASSET.has(path));
if (missing.length > 0) {
  console.log(`고도가 부르는 에셋 ${missing.length}개가 sync-godot-assets.mjs 목록에 없다 — 배포 화면에서 빠진다:`);
  for (const [path, where] of missing) console.log(`  ${path.padEnd(32)} ← ${where}`);
  console.log('목록에 넣고 public/assets 에 커밋한다. 일부러 없는 것이면 check-godot-assets.mjs 의 NO_ASSET 에 이유와 함께 적는다');
  process.exit(1);
}

function* gdFiles(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) yield* gdFiles(path);
    else if (entry.name.endsWith('.gd')) yield path;
  }
}

/** materials 는 배열이거나 id 를 키로 둔 사전이다 */
function materialsById(materials) {
  if (!Array.isArray(materials)) return materials;
  return Object.fromEntries(materials.map((m) => [m.id, m]));
}
