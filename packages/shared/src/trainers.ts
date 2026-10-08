/**
 * PT 트레이너 — 상점에서 **다이아로 뽑아** 모으고, 한 명을 데리고 다니면 **같이 때린다**
 * (2026-10-06 요청: "PT 트레이너로 하자 … 등급별로 캐릭터의 능력치를 몇 % 계승할지 정하고 …
 * 플레이어가 때리는 몬스터 같이 때리도록 … 공격 받지 않도록 … 타겟팅 되지 않도록").
 *
 * - **계승** — 동행 트레이너는 캐릭터 최종 능력치의 등급 % 로 싸운다 (일반 20 ~ 전설 80).
 *   공격력·방어력·체력에 % 를 곱하고, 공속·치명타·관통은 비율이라 **그대로** 쓴다.
 *   그래서 동행 트레이너의 피해 = 캐릭터 평타 피해 × 계승 % 다.
 * - **보유 효과** — 뽑아서 갖고만 있어도 캐릭터에 붙는다 (2026-10-06 사용자가 고른 "보유 효과").
 *   트레이너마다 능력치 하나, 등급마다 1 · 2 · 3 · 5 · 8 %. 공격력·방어력·체력은 다른 몫(장비·헬스·도감)과
 *   **따로 곱하고**, 치명타 확률·치명타 피해는 비율에 더한다.
 * - **동행은 한 명** (사용자가 고른 것). 같은 트레이너가 또 나오면 개수가 는다.
 * - **합성** (2026-10-06 요청: "중복으로 나온 트레이너는 합성해서 다음 등급으로 올릴 수 있는 기능 … 확률에 따라서.
 *   트레이너 3장당 다음 등급 도전") — 같은 등급 **여분**(트레이너마다 1장은 남긴다) 3장을 넣어 `fuse` 확률로
 *   다음 등급 무작위 1명. 실패하면 3장만 사라진다. 확률은 사용자가 정했다 — 20 · 20 · 10 · 10 %.
 * - 판정은 장부(`Ledger.trainer_draw` · `trainer_pick`)가 한다 → docs/features/trainers.md
 */

export type TrainerStat = 'attack' | 'defense' | 'maxHp' | 'crit' | 'critDamage';

export const TRAINER_STAT_NAME: Record<TrainerStat, string> = {
  attack: '공격력',
  defense: '방어력',
  maxHp: '체력',
  crit: '치명타 확률',
  critDamage: '치명타 피해',
};

export interface TrainerGrade {
  /** 1 ~ 5 — 장비 등급 이름·색과 같은 번호 (`GRADE_NAME`) */
  grade: number;
  name: string;
  /** 동행할 때 캐릭터 능력치를 몇 % 이어받나 */
  inherit: number;
  /** 보유 효과 % (치명타 둘은 %p) */
  owned: number;
  /** 뽑기에서 이 등급이 나올 확률(%) — 등급 안에서는 고르게 */
  chance: number;
  count: number;
  /** 이 등급 여분 `TRAINER_FUSE_COST` 장으로 다음 등급에 도전할 때의 성공 확률(%) — 전설은 0(더 위가 없다) */
  fuse: number;
}

export const TRAINER_GRADES: TrainerGrade[] = [
  { grade: 1, name: '일반', inherit: 20, owned: 1, chance: 58, count: 20, fuse: 20 },
  { grade: 2, name: '고급', inherit: 30, owned: 2, chance: 30, count: 15, fuse: 20 },
  { grade: 3, name: '희귀', inherit: 40, owned: 3, chance: 9, count: 10, fuse: 10 },
  { grade: 4, name: '영웅', inherit: 60, owned: 5, chance: 2.5, count: 5, fuse: 10 },
  { grade: 5, name: '전설', inherit: 80, owned: 8, chance: 0.5, count: 3, fuse: 0 },
];

/** 합성 한 번에 넣는 같은 등급 여분 */
export const TRAINER_FUSE_COST = 3;

/**
 * 합성 창의 등록 칸 — 한 번에 넣을 수 있는 카드 수. `TRAINER_FUSE_COST` 의 배수라 칸 한 줄(3장)이 도전 한 번이다
 * (2026-10-08 요청: 등급 탭 → 카드를 눌러 칸에 등록 → 합성). 장부도 이보다 많이 넣으면 거절한다
 */
export const TRAINER_FUSE_SLOTS = 9;

/** 뽑기 값 — 다이아. 10회는 한 번에 열 번 굴린다 (할인 없음) */
export const TRAINER_DRAW_COST = 100;
export const TRAINER_DRAW_MULTI = 10;

/**
 * 보유 효과 능력치는 등급 안에서 이 순서로 돌린다 — 다섯 종이 고르게 퍼진다.
 * 전설 셋은 따로 정했다 (`TRAINER_LEGEND_STATS`).
 */
const STAT_CYCLE: TrainerStat[] = ['attack', 'defense', 'maxHp', 'crit', 'critDamage'];
const TRAINER_LEGEND_STATS: TrainerStat[] = ['attack', 'maxHp', 'crit'];

/**
 * 명단 — 등급 순서대로. `look` 은 원화 프롬프트의 **사람마다 다른 부분**이다
 * (공통 꼬리는 `TRAINER_PROMPT_TAIL`). 손에 든 것은 T자세 3D 에서 뭉개지므로 소품은 허리·등에 단다.
 * 키(m)는 바르코 모델을 몇 배로 키울지 — 없으면 1.8.
 */
interface RosterRow {
  id: string;
  name: string;
  look: string;
  height?: number;
}

const ROSTER: RosterRow[][] = [
  // 일반 20 — 마을 체육관의 코치들
  [
    { id: 'n01', name: '근력 코치 브람', look: 'burly bald man in his 40s, short dark beard, gray tank top, black training shorts, white wrist wraps, sneakers' },
    { id: 'n02', name: '요가 강사 미라', look: 'slim calm woman, long brown braid over shoulder, teal sports top, loose cream yoga pants, barefoot' },
    { id: 'n03', name: '줄넘기 소녀 피피', look: 'energetic teen girl, pink twin tails, red sports headband, white t-shirt, red shorts, sneakers', height: 1.55 },
    { id: 'n04', name: '러닝 코치 테오', look: 'lean young man, messy blond hair, sleeveless orange running vest, black running shorts, running shoes, stopwatch hanging on belt' },
    { id: 'n05', name: '스트레칭 강사 로나', look: 'fit middle-aged woman, short gray bob hair, lavender tracksuit, white towel around neck' },
    { id: 'n06', name: '복싱 견습생 덱스', look: 'lean young man, red headband, white boxing hand wraps, bare toned chest, black boxing shorts with gold trim' },
    { id: 'n07', name: '수영 코치 마린', look: 'tanned athletic woman, swim goggles on forehead, navy one-piece swimsuit, blue jacket tied around waist, sandals' },
    { id: 'n08', name: '역도 초보 군', look: 'stocky young man, buzz cut, blue weightlifting singlet, thick leather lifting belt, knee sleeves', height: 1.7 },
    { id: 'n09', name: '필라테스 강사 엘라', look: 'elegant woman, high black ponytail, black leotard, light pink cardigan tied at waist, ballet flats' },
    { id: 'n10', name: '등산 가이드 호크', look: 'rugged man, wool beanie, red flannel shirt with rolled sleeves, brown cargo pants, hiking boots, coiled rope on back' },
    { id: 'n11', name: '권법 수련생 린', look: 'young woman martial arts student, short black hair, white training gi with white belt, barefoot' },
    { id: 'n12', name: '체조 선수 노바', look: 'petite girl gymnast, hair in a bun, sparkling blue gymnastics leotard, white chalk on hands', height: 1.5 },
    { id: 'n13', name: '나무꾼 트레이너 오크스', look: 'big bearded lumberjack man, green plaid shirt, suspenders, leather gloves tucked in belt, heavy boots', height: 1.95 },
    { id: 'n14', name: '조깅 할아버지 페드로', look: 'fit old man, big white mustache, green retro tracksuit, white sweatband on forehead, running shoes' },
    { id: 'n15', name: '댄스 강사 루루', look: 'cheerful woman, curly orange hair, cropped yellow hoodie, black leggings, striped leg warmers' },
    { id: 'n16', name: '씨름꾼 바우', look: 'large young Korean ssireum wrestler, topknot hair, red satba sash belt over white shorts, bare muscular chest', height: 1.9 },
    { id: 'n17', name: '사이클 코치 지나', look: 'athletic woman, yellow cycling jersey, black bike shorts, cycling helmet clipped on back, cycling shoes' },
    { id: 'n18', name: '짐꾼 훈련사 토르', look: 'muscular dwarf, long braided red beard, leather harness, big sack strapped on back, iron-toed boots', height: 1.35 },
    { id: 'n19', name: '궁도 체력관 세라', look: 'elf woman, long silver hair, pointed ears, green tunic, leather bracers, empty quiver on back' },
    { id: 'n20', name: '농부 근육맨 감자', look: 'sunburned farmer man, straw hat, denim overalls, rolled sleeves, huge forearms' },
  ],
  // 고급 15 — 한 갈래를 깊게 판 전문가
  [
    { id: 'a01', name: '킥복서 레이븐', look: 'woman kickboxer, black undercut hair, black sports bra, purple muay thai shorts, white shin guards, hand wraps' },
    { id: 'a02', name: '레슬러 맥', look: 'massive man pro wrestler, half face mask, red wrestling singlet, black knee pads, wrestling boots', height: 2.0 },
    { id: 'a03', name: '크로스핏 코치 제이드', look: 'athletic woman, green buzz cut, black tank top, gray shorts, knee sleeves, chalk bag at waist' },
    { id: 'a04', name: '파쿠르 러너 키트', look: 'nimble young man, gray hoodie, dark joggers, fingerless gloves, long red scarf' },
    { id: 'a05', name: '태권 사범 한결', look: 'Korean taekwondo master man, white dobok with black-trimmed collar, black belt, calm sharp eyes, barefoot' },
    { id: 'a06', name: '수인 트레이너 바크', look: 'wolf beastman, gray fur, wolf head, sleeveless dark blue gi, rope belt, barefoot paws', height: 1.9 },
    { id: 'a07', name: '방패술 교관 브리짓', look: 'stout woman knight instructor, padded brown gambeson, round wooden shield on back, braided blonde hair' },
    { id: 'a08', name: '오크 역사 그롬', look: 'green-skinned orc strongman, tusks, leather chest straps, iron wrist cuffs, fur loincloth over pants', height: 2.0 },
    { id: 'a09', name: '검무 강사 세이', look: 'graceful man, flowing white and sky-blue training robes, long ribbon sash, long black hair tied back' },
    { id: 'a10', name: '곰 조련사 우르사', look: 'big strong woman, bear pelt cloak with bear head hood, fur boots, leather vest' },
    { id: 'a11', name: '카포에라 마스터 지우', look: 'man capoeira master, white capoeira pants, colored cord belt, bare torso, dreadlocks' },
    { id: 'a12', name: '사막 체력관 사림', look: 'desert warrior man, sand-colored turban and face scarf, tan wrapped clothing, red sash belt' },
    { id: 'a13', name: '스모 선수 오야마', look: 'huge sumo wrestler, black mawashi belt, oiled topknot hair', height: 1.9 },
    { id: 'a14', name: '창술 교관 리엔', look: 'woman instructor, red qipao-style martial training outfit with side slits, black pants, hair buns' },
    { id: 'a15', name: '도깨비 코치 방망', look: 'Korean dokkaebi goblin, blue skin, single small horn, wild hair, tiger-pattern shorts, bare muscular chest' },
  ],
  // 희귀 10 — 이름난 사범
  [
    { id: 'r01', name: '무에타이 챔피언 칸', look: 'muay thai champion man, mongkol headband, prajiad armbands, gold-trimmed red shorts, scarred muscular body' },
    { id: 'r02', name: '강철 수도승 혜능', look: 'bald warrior monk, orange robe off one shoulder, large prayer beads necklace, iron bracers' },
    { id: 'r03', name: '엘프 무희 실바나', look: 'elf dancer woman, long green hair, flowing emerald silk outfit, gold arm rings and anklets' },
    { id: 'r04', name: '닌자 사범 카게', look: 'ninja master, dark navy ninja outfit, face mask pulled down, long gray scarf, tabi shoes' },
    { id: 'r05', name: '바이킹 역사 하랄드', look: 'huge viking man, braided red beard, fur mantle over shoulders, iron armbands, leather kilt', height: 2.0 },
    { id: 'r06', name: '사자 수인 레오닉', look: 'lion beastman, golden mane, lion head, gladiator leather skirt, leather chest straps, bronze wrist guards', height: 1.95 },
    { id: 'r07', name: '성기사 교관 아우렐', look: 'paladin trainer man, white and gold padded tunic, blue cape, short golden hair' },
    { id: 'r08', name: '거인족 장사 몰록', look: 'half-giant man, gray skin, bald, heavy chains worn as a belt, ragged trousers', height: 2.2 },
    { id: 'r09', name: '쌍권 여제 메이', look: 'kung fu woman master, red and gold changshan top, black pants, long black ponytail' },
    { id: 'r10', name: '해적 권투가 바르보사', look: 'pirate boxer man, tricorn hat, open long red coat, hand wraps, bare chest with tattoos' },
  ],
  // 영웅 5 — 이야기 속 영웅
  [
    { id: 'h01', name: '용권사 류', look: 'dragon fist martial artist man, glowing red dragon tattoo on arm, white gi with torn-off sleeves, red sash' },
    { id: 'h02', name: '검투왕 막시무스', look: 'gladiator king, bronze shoulder armor, crimson cape, leather pteruges skirt, laurel wreath', height: 1.95 },
    { id: 'h03', name: '대지의 장사 가이아', look: 'tall earth giantess woman, bronze skin, moss and stone ornaments, leaf skirt, glowing green runes', height: 2.0 },
    { id: 'h04', name: '바람의 권객 시엔', look: 'wind martial artist, flowing white and teal robes, floating wind ribbons, long white hair' },
    { id: 'h05', name: '흑룡 무투가 카이저', look: 'martial artist man in black armor with dark red accents, spiked armor pauldrons, black dragon motif' },
  ],
  // 전설 3 — 신화
  [
    { id: 'l01', name: '권신 아수라', look: 'god of fists, deity-like man, golden glowing markings on skin, ornate gold bracers and belt, flowing crimson scarf, golden halo ring behind back', height: 1.95 },
    { id: 'l02', name: '불멸의 철인 헤라클', look: 'mythic hero, lion pelt cloak with lion head hood, bronze laurel, legendary muscular body, bronze belt', height: 2.0 },
    { id: 'l03', name: '천상의 무희 선녀', look: 'celestial heavenly maiden, flowing ethereal white and pink robes, floating ribbon shawl, jade hair ornaments' },
  ],
];

/** 원화 프롬프트 공통 꼬리 — 마을 NPC 와 같은 결 (npc-town.md "외형") */
export const TRAINER_PROMPT_TAIL =
  'Full body character concept art of a single character, standing front view, arms slightly away from the body hanging down, ' +
  'both hands empty, feet shoulder-width apart, plain white background, painted anime style like the reference image, ' +
  'no weapons in hands, no text, no frame.';

export interface Trainer {
  id: string;
  name: string;
  grade: number;
  /** 보유 효과 능력치 */
  stat: TrainerStat;
  /** 보유 효과 값 (% 또는 %p) */
  owned: number;
  /** 동행 계승 % */
  inherit: number;
  height: number;
  /** 원화 프롬프트 (영어 — 바르코에 넣는다) */
  prompt: string;
}

function build(): Trainer[] {
  const out: Trainer[] = [];
  TRAINER_GRADES.forEach((g, gi) => {
    const rows = ROSTER[gi]!;
    rows.forEach((row, i) => {
      const stat = g.grade === 5 ? TRAINER_LEGEND_STATS[i]! : STAT_CYCLE[i % STAT_CYCLE.length]!;
      out.push({
        id: row.id,
        name: row.name,
        grade: g.grade,
        stat,
        owned: g.owned,
        inherit: g.inherit,
        height: row.height ?? 1.8,
        prompt: `${row.look}. ${TRAINER_PROMPT_TAIL}`,
      });
    });
  });
  return out;
}

export const TRAINERS: Trainer[] = build();

export function trainerById(id: string): Trainer | undefined {
  return TRAINERS.find((t) => t.id === id);
}

/** 갖고 있는 트레이너 목록 → 보유 효과 합 (공격력·방어력·체력은 %, 치명타 둘은 %p) */
export function trainerOwnedBonus(owned: Iterable<string>): Record<TrainerStat, number> {
  const sum: Record<TrainerStat, number> = { attack: 0, defense: 0, maxHp: 0, crit: 0, critDamage: 0 };
  for (const id of owned) {
    const t = trainerById(id);
    if (t) sum[t.stat] += t.owned;
  }
  return sum;
}
