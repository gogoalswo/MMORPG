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
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 복사할 것. 없으면 건너뛰고 화면은 기둥으로 대신 그린다 */
const MODELS = [
  'varco_fighter.glb', // 캐릭터 (기본 직업 격투가 고정)
  // 몬스터 — 사냥터 20곳이 오우거 5종을 차례로 돌려 쓴다 (monsters.ts 의 TIERS[].look · BOSS_LOOKS)
  'varco_ogre1.glb', 'varco_ogre2.glb', 'varco_ogre3.glb', 'varco_ogre4.glb', 'varco_ogre5.glb',
  'varco_portal.glb', // 차원문 (모든 존의 GATE_SPOT)
];

/** UI 조각. 이미 build-ui.mjs 가 줄여 둔 것이라 그대로 복사한다 */
/**
 * **차원문 창이 쓰던 옛 조각.** 2026-09-21 에 창을 다른 UI 와 같은 결로 바꾸면서
 * (창 바탕 `ui_panel`, 줄 아이콘 `ui_gate_*`) 아무도 안 쓰게 됐다. 파일은
 * public/assets/ui 에 남겨 두지만 **고도로는 안 옮긴다** — pck 만 늘어난다
 */
const UI = [];

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
  // 등급별 무기 = 건틀릿 일곱 장 (2026-09-23) — `_item_icon` 이 슬롯 그림보다 먼저 찾는다
  'weapon_g1.png', 'weapon_g2.png', 'weapon_g3.png', 'weapon_g4.png',
  'weapon_g5.png', 'weapon_g6.png', 'weapon_g7.png',
  // 나머지 다섯 부위도 등급별 일곱 장씩 (2026-09-26) — 이름은 무기와 같은 `<슬롯>_g<등급>`
  ...['armor', 'helmet', 'boots', 'necklace', 'ring']
    .flatMap((slot) => [1, 2, 3, 4, 5, 6, 7].map((g) => `${slot}_g${g}.png`)),
  'boots.png', 'necklace.png', 'ring.png',
  // 재료 — 크리스탈 (2026-09-23). `_item_icon` 이 재료는 id 를 그림 이름으로 쓴다
  'crystal.png',
  'bag.png', 'gold.png',
  // 창을 짓는 그림들. 9조각으로 늘여 쓴다 (game.gd 의 _frame_box)
  'ui_panel.png', 'ui_subpanel.png', 'ui_slot.png',
  'ui_tab_on.png', 'ui_tab_off.png', 'ui_button.png',
  // 장착 칸 사이에 서는 캐릭터 그림자
  'ui_figure.png',
  // 스킬창·퀵슬롯 — 칸 테두리, 고른 칸 표시, 격투가 스킬 아이콘 (이름 = skill_<id>)
  'ui_skill_slot.png', 'ui_slot_pick.png',
  'skill_rising_kick.png',
  'skill_sky_breaker.png', 'skill_thunder_fall.png', 'skill_frost_pillar.png',
  // 메인 HUD — 왼쪽 위 상태판(초상 테두리·막대 홈·막대 채움),
  // 오른쪽 위 메뉴 단추 둘, 자동사냥 칸과 켜졌을 때 도는 고리
  // 2026-09-20 에 받은 그림대로 어두운 쇠 + 금테로 갈아 끼웠다 (막대·칸·단추),
  // 레벨 배지가 새로 들어왔고 초상(ui_portrait)은 빠졌다
  'ui_bar_frame.png', 'ui_bar_fill.png', 'ui_level_badge.png', 'ui_quick_slot.png',
  'ui_icon_skill.png', 'ui_icon_bag.png', 'ui_icon_auto.png', 'ui_auto_spin.png',
  // 던전 단추 — 뿔 달린 보스 머리 (2026-09-23, docs/features/dungeons.md)
  'ui_icon_dungeon.png',
  // 던전 종류 카드 그림 셋 — 토벌(보스 머리) · 시련의 탑 · 보물 창고 (2026-09-23)
  'dungeon_raid.png', 'dungeon_trial.png', 'dungeon_treasure.png',
  // 모든 창의 오른쪽 위 닫기 X (2026-09-20)
  'ui_close.png',
  // 인벤토리 결 — 장비·상세·인벤토리 세 창 (2026-09-23)
  'inv_panel.png', 'inv_slot.png', 'inv_slot_pick.png',
  'inv_tab_on.png', 'inv_tab_off.png', 'inv_button.png',
  // 차원문 창 줄 아이콘 — 지금 서 있는 곳은 소용돌이, 갈 곳은 별 (2026-09-21)
  'ui_gate_here.png', 'ui_gate_go.png',
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
  // 보내는 쪽과 받는 쪽 폴더 이름을 같게 둔다 — play.bat 이 public/assets 를 통째로
  // 미러링하므로, 이름이 어긋나면 PC 에서만 바닥이 빠진다 (2026-09-19 에 맞췄다)
  { names: GROUND, from: join(ROOT, 'public', 'assets', 'textures'), to: join(ROOT, 'godot', 'assets', 'textures') },
];

let copied = 0;
for (const job of jobs) copied += await run(job);
console.log(`${copied}개 새로 복사했다 -> godot/assets/`);

async function run({ names, from, to, shrink }) {
  mkdirSync(to, { recursive: true });
  // 원본이 안 바뀌었으면 다시 쓰지 않는다. 고도가 매번 다시 임포트하지 않게.
  // 줄인 파일은 크기가 원본과 다르므로 무엇으로 만들었는지를 따로 적어 둔다.
  // **크기가 아니라 내용 해시로 본다** — 블렌더 동작을 다시 붙이면 키 값만 바뀌어
  // 크기가 같은데, 크기로 보면 옛 모델이 남아 테스트가 옛것으로 돈다 (2026-09-24)
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
    const hash = createHash('sha1').update(readFileSync(src)).digest('hex');
    const key = `${hash}:${shrink ? MAX_TEXTURE : 0}`;
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
