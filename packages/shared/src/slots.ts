/**
 * 장비 슬롯 — **여섯 자리**.
 *
 * `items.ts` 에 있던 것을 2026-09-20 에 여기로 옮겼다. `gear.ts`(설계 표)와
 * `items.ts`(지금 도는 표)가 **서로를 임포트하게 되어 순환**이 생겼기 때문이다.
 * 슬롯 목록은 둘 다 필요하고 아무것도 임포트하지 않으므로, 맨 아래로 내렸다.
 * `items.ts` 가 그대로 다시 내보내니 부르는 쪽은 고칠 것이 없다.
 *
 * 2026-09-18 에 보조(보호대·마법서·화살통)와 귀걸이를 없앴다
 * (요청: "슬롯은 무기, 갑옷, 투구, 신발, 목걸이, 반지 이렇게야").
 * 직업을 타는 자리는 **무기 하나만** 남았다.
 */
export type EquipSlot = 'weapon' | 'armor' | 'helmet' | 'boots' | 'ring' | 'necklace';

/** 창에 놓이는 순서 */
export const EQUIP_SLOTS: EquipSlot[] = [
  'weapon',
  'armor',
  'helmet',
  'boots',
  'necklace',
  'ring',
];

/** 슬롯별 id 앞글자 */
export const SLOT_CODE: Record<EquipSlot, string> = {
  weapon: 'w',
  armor: 'a',
  helmet: 'h',
  boots: 'b',
  ring: 'r',
  necklace: 'n',
};

const SLOT_LABEL: Record<EquipSlot, string> = {
  weapon: '무기',
  armor: '갑옷',
  helmet: '투구',
  boots: '신발',
  ring: '반지',
  necklace: '목걸이',
};

/**
 * 슬롯 이름. `job` 을 받던 자리는 보조 때문이었는데 보조를 없애 쓰이지 않는다 —
 * 부르는 쪽(창·내보내기)을 다 고치지 않아도 되도록 인자는 남겨 두고 무시한다
 */
export function slotLabel(slot: EquipSlot, _job?: unknown): string {
  return SLOT_LABEL[slot];
}
