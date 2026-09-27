/**
 * 이빨 — 일곱 번째 장착 칸 (2026-09-27 지시).
 *
 * 지시: "이빨 슬롯을 넣어. 아이템 등급은 기존과 동일하고 옵션은 hp흡수 옵션이야.
 * 입힌 피해의 1% 부터 등급별로 1%씩 올라갈거야. 이 아이템은 드랍으로 안 나와.
 * 나중에 신규 던전 깨면 업그레이드 할 수 있게 할거야".
 * 갈래는 사용자가 골랐다 — **일반 이빨을 시작 지급**(기존 캐릭터도 한 번), **흡혈만**.
 *
 * ## 장비 6칸(`EQUIP_SLOTS`)과 따로 둔다 ★
 *
 * 장비 6칸은 설계 예산(`SLOT_SHARE` 의 열 합계 1.0)·드랍·강화·크리스탈 표에 묶여 있다.
 * 이빨은 그 어디에도 안 든다 — 공격·방어·HP 가 없고, 떨어지지 않고, 두드리지 않는다.
 * 그래서 `EquipSlot` 에 넣지 않고 표도 따로 둔다. **고도로 내보낼 때만 합친다**
 * (`items.json` 의 `items` 에 7종이 더 들고, `slots` 에 `tooth` 가 붙는다. 드랍은
 * `dropSlots` 만 본다).
 *
 * - 성능은 **흡혈 하나**: 입힌 피해의 `등급 × 1%` 만큼 HP 를 채운다 (일반 1% → 태초 7%).
 *   랜덤 옵션·크리스탈·강화·판매가 없다 — `fixed: true` 가 그 표시다.
 * - 등급 이름·색·착용 레벨은 다른 장비와 같다 (`GRADE_NAME` · `equipLevel`).
 * - 올리는 길(신규 던전 보상)은 아직 없다 — 붙일 때 이 표의 id 로 갈아 끼우면 된다.
 */
import { GRADE_COUNT, GRADE_NAME, equipLevel } from './gear.ts';

export const TOOTH_SLOT = 'tooth';
/** id 앞글자 — `g{등급}_t`. 장비 6칸의 `w a h b n r` 와 안 겹친다 */
export const TOOTH_CODE = 't';
export const TOOTH_LABEL = '이빨';
/** 등급 하나당 흡혈 (%) — 일반 1% · 고급 2% … 태초 7% */
export const TOOTH_LIFESTEAL_STEP = 1;

/** 등급마다 이름 — 장비처럼 등급 글자는 안 붙이고 재질(짐승)이 오른다. 등급은 이름 색이 알린다 */
const TOOTH_NAME = ['짐승', '늑대', '흑랑', '투사의', '용', '성운', '창세의'];

export interface ToothDef {
  id: string;
  name: string;
  slot: typeof TOOTH_SLOT;
  grade: number;
  level: number;
  /** `lifesteal` 은 **퍼센트 정수** (3 = 입힌 피해의 3%) — 옵션 저장 단위와 같다 */
  bonus: { lifesteal: number };
  /** 팔 수 없다 — 다시 얻을 길이 없다 */
  price: 0;
  /** 강화·크리스탈·판매·랜덤 옵션이 없는 물건 */
  fixed: true;
}

/** 그 등급의 흡혈 (%) */
export function toothLifesteal(grade: number): number {
  return Math.max(1, Math.min(GRADE_COUNT, Math.trunc(grade))) * TOOTH_LIFESTEAL_STEP;
}

export function toothId(grade: number): string {
  return `g${grade}_${TOOTH_CODE}`;
}

function buildTeeth(): Record<string, ToothDef> {
  const out: Record<string, ToothDef> = {};
  for (let grade = 1; grade <= GRADE_COUNT; grade++) {
    const id = toothId(grade);
    out[id] = {
      id,
      name: `${TOOTH_NAME[grade - 1]} 이빨`,
      slot: TOOTH_SLOT,
      grade,
      level: equipLevel(grade),
      bonus: { lifesteal: toothLifesteal(grade) },
      price: 0,
      fixed: true,
    };
  }
  return out;
}

/** 등급 7개 = **7종** */
export const TOOTH_ITEMS: Record<string, ToothDef> = buildTeeth();

// 이름 표가 등급 수와 어긋나면 여기서 바로 알린다
if (TOOTH_NAME.length !== GRADE_NAME.length) throw new Error('이빨 이름이 등급 수와 다르다');
