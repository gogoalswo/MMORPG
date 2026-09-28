/**
 * 유료 재화 **다이아** — 구글 플레이 상품 id → 넣어 줄 다이아 (docs/features/server.md "유료 재화").
 *
 * **가격은 여기 없다** — 플레이 콘솔의 상품에서 정한다(나라마다 다르다). 여기는 "이 상품을 사면
 * 다이아 몇 개" 만 둔다. 서버는 영수증의 상품 id 로 이 표를 찾아 넣는다 — 기기가 보낸 개수는 믿지 않는다.
 *
 * 2026-09-28: 충전·검증만 먼저 만들었다 (다이아로 무엇을 파는지는 아직 없다). 개수는 **임시**다.
 */
export interface DiamondProduct {
  /** 플레이 콘솔의 상품 id (소모성 인앱 상품) */
  id: string;
  diamonds: number;
}

export const DIAMOND_PRODUCTS: readonly DiamondProduct[] = [
  { id: 'dia_100', diamonds: 100 },
  { id: 'dia_550', diamonds: 550 },
  { id: 'dia_1200', diamonds: 1200 },
];
