import { GRADE_MAX, type ItemDef } from '@mmo/shared';

/**
 * 아이템 아이콘.
 *
 * 그림 파일이 없으므로 **SVG 로 직접 그린다.** 이 프로젝트가 지형·캐릭터·텍스처를
 * 전부 코드로 만들어 온 것과 같은 방식이고, 아이템이 100종을 넘어서 그림을
 * 하나씩 준비하는 건 현실적이지 않다.
 *
 * 모양은 종류(검·지팡이·활·갑옷·반지·정수)로 정하고 색은 등급에서 뽑는다.
 * 그래서 같은 검이라도 등급이 오르면 눈에 띄게 달라 보인다.
 */

/** 등급별 색 — 낮으면 무채색, 높을수록 뜨거워진다 */
const GRADE_COLOR = [
  '#8b9280', // 1
  '#8b9280',
  '#9aa88c',
  '#7fc4e8', // 4
  '#7fc4e8',
  '#9be07a', // 6
  '#9be07a',
  '#e8c86a', // 8
  '#f0975a', // 9
  '#ef6f8c', // 10
];

export function gradeColor(grade: number): string {
  const i = Math.min(GRADE_MAX, Math.max(1, Math.round(grade))) - 1;
  return GRADE_COLOR[i] ?? GRADE_COLOR[0]!;
}

type Shape =
  | 'sword'
  | 'staff'
  | 'bow'
  | 'shield'
  | 'book'
  | 'quiver'
  | 'armor'
  | 'helmet'
  | 'boots'
  | 'ring'
  | 'necklace'
  | 'earring'
  | 'essence';

/** 아이템 하나가 어떤 그림을 쓸지 */
function shapeOf(item: ItemDef): Shape {
  if (item.material) return 'essence';

  switch (item.slot) {
    case 'weapon':
      return item.job === 'mage' ? 'staff' : item.job === 'archer' ? 'bow' : 'sword';
    case 'offhand':
      return item.job === 'mage' ? 'book' : item.job === 'archer' ? 'quiver' : 'shield';
    case 'armor':
      return 'armor';
    case 'helmet':
      return 'helmet';
    case 'boots':
      return 'boots';
    case 'necklace':
      return 'necklace';
    case 'earring':
      return 'earring';
    default:
      return 'ring';
  }
}

/**
 * 24×24 좌표계로 그린다. 칸 크기는 CSS 가 정하므로 여기서는 비율만 맞춘다.
 * `c` 는 등급색, `d` 는 그 어두운 짝이다.
 */
function draw(shape: Shape, c: string, d: string): string {
  switch (shape) {
    case 'sword':
      return (
        `<path d="M12 2 L14.6 6 L14.6 15 L12 17.5 L9.4 15 L9.4 6 Z" fill="${c}"/>` +
        `<rect x="7" y="16.4" width="10" height="1.9" rx="0.9" fill="${d}"/>` +
        `<rect x="11.2" y="18" width="1.6" height="4" rx="0.8" fill="${d}"/>`
      );
    case 'staff':
      return (
        `<rect x="11.1" y="7" width="1.8" height="15" rx="0.9" fill="${d}"/>` +
        `<circle cx="12" cy="5.4" r="3.6" fill="${c}"/>` +
        `<circle cx="10.8" cy="4.3" r="1.1" fill="#ffffff" opacity="0.55"/>`
      );
    case 'bow':
      return (
        `<path d="M8 3 A 11 11 0 0 1 8 21" stroke="${c}" stroke-width="2.3" fill="none" stroke-linecap="round"/>` +
        `<line x1="8" y1="3.4" x2="8" y2="20.6" stroke="${d}" stroke-width="1.1"/>` +
        `<line x1="8" y1="12" x2="17" y2="12" stroke="${d}" stroke-width="1.4" stroke-linecap="round"/>`
      );
    case 'shield':
      return (
        `<path d="M12 2.4 L19.4 5.4 L18.6 14 Q12 21.4 5.4 14 L4.6 5.4 Z" fill="${c}"/>` +
        `<path d="M12 5.4 L16.4 7.2 L15.9 13 Q12 17.4 8.1 13 L7.6 7.2 Z" fill="${d}"/>`
      );
    case 'book':
      return (
        `<path d="M4.4 4.6 Q12 2.6 19.6 4.6 L19.6 19 Q12 17 4.4 19 Z" fill="${c}"/>` +
        `<path d="M12 3.6 L12 18.2" stroke="${d}" stroke-width="1.3"/>` +
        `<path d="M6.6 8 L10 8.6 M14 8.6 L17.4 8" stroke="${d}" stroke-width="1" stroke-linecap="round"/>`
      );
    case 'quiver':
      return (
        `<rect x="7.6" y="8" width="8.8" height="14" rx="2.2" fill="${c}"/>` +
        `<path d="M10 8 L10 2.6 M12 8 L12 2 M14 8 L14 2.6" stroke="${d}" stroke-width="1.3" stroke-linecap="round"/>` +
        `<rect x="7.6" y="12.4" width="8.8" height="1.8" fill="${d}"/>`
      );
    case 'armor':
      return (
        `<path d="M12 2 L19 5 L18.4 14 Q12 21 5.6 14 L5 5 Z" fill="${c}"/>` +
        `<path d="M12 2 L12 19.6" stroke="${d}" stroke-width="1.2"/>` +
        `<path d="M6.4 8.5 L17.6 8.5" stroke="${d}" stroke-width="1.1"/>`
      );
    case 'helmet':
      return (
        `<path d="M5.6 14 A 6.4 6.4 0 0 1 18.4 14 L18.4 17.4 L5.6 17.4 Z" fill="${c}"/>` +
        `<rect x="10.9" y="9.6" width="2.2" height="7.8" fill="${d}"/>` +
        `<rect x="5.2" y="17.4" width="13.6" height="2.2" rx="1" fill="${d}"/>`
      );
    case 'boots':
      return (
        `<path d="M7.4 3.4 L12.2 3.4 L12.2 13 L18.4 16.4 L18.4 20.2 L7.4 20.2 Z" fill="${c}"/>` +
        `<rect x="6.6" y="19.4" width="12.6" height="2.2" rx="1" fill="${d}"/>`
      );
    case 'ring':
      return (
        `<circle cx="12" cy="14.5" r="6.2" stroke="${d}" stroke-width="2.4" fill="none"/>` +
        `<path d="M12 3.2 L15.4 6.6 L12 10 L8.6 6.6 Z" fill="${c}"/>`
      );
    case 'necklace':
      return (
        `<path d="M5.6 4.4 A 8.4 8.4 0 0 0 18.4 4.4" stroke="${d}" stroke-width="1.8" fill="none"/>` +
        `<path d="M12 11.4 L15.6 15.4 L12 20.6 L8.4 15.4 Z" fill="${c}"/>`
      );
    case 'earring':
      return (
        `<path d="M9 3.4 A 4.6 4.6 0 0 1 15 3.4" stroke="${d}" stroke-width="1.7" fill="none"/>` +
        `<circle cx="15" cy="8.6" r="1.5" fill="${d}"/>` +
        `<path d="M15 11.4 L18 16 L15 21 L12 16 Z" fill="${c}"/>`
      );
    case 'essence':
      return (
        `<path d="M12 2 L18.5 9 L12 22 L5.5 9 Z" fill="${c}" opacity="0.92"/>` +
        `<path d="M12 2 L12 22" stroke="#ffffff" stroke-width="0.9" opacity="0.35"/>` +
        `<path d="M5.5 9 L18.5 9" stroke="#ffffff" stroke-width="0.9" opacity="0.35"/>`
      );
  }
}

/** 어둡게 — 테두리나 손잡이에 쓴다 */
function darken(hex: string): string {
  const n = Number.parseInt(hex.slice(1), 16);
  const mix = (v: number) => Math.max(0, Math.round(v * 0.55));
  const r = mix((n >> 16) & 255);
  const g = mix((n >> 8) & 255);
  const b = mix(n & 255);
  return `rgb(${r}, ${g}, ${b})`;
}

/** 칸에 넣을 SVG 마크업 */
export function itemIcon(item: ItemDef, grade: number): string {
  const c = item.material ? gradeColor(6) : gradeColor(grade);
  return (
    `<svg class="item-icon" viewBox="0 0 24 24" aria-hidden="true">${draw(shapeOf(item), c, darken(c))}</svg>`
  );
}
