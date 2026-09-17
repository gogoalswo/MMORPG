/**
 * 짐승이 화면에서 차지하는 크기 — 키와 **클릭 판정 상자**.
 *
 * 그리는 건 클라이언트지만 값은 여기 둔다. `scripts/hit-probe.ts` 가 "몇 픽셀
 * 안에서 클릭되는가" 를 브라우저 없이 재는데, 클라이언트 모듈은 Node 에서
 * 임포트되지 않아서(상대 임포트에 확장자가 없다) 값을 복제하게 된다.
 * 복제한 순간 프로브는 **실제와 다른 상자를 재고도 통과한다** — 실제로 그래서
 * 상자가 2.4 배로 커진 것을 오래 못 잡았다 (2026-09-15).
 */

/**
 * 짐승 종류별 키(m).
 *
 * 높이로 크기를 맞추므로 여기 값이 곧 화면에서 보이는 크기다. 전부 같은 값으로
 * 두면 거미가 티라노사우루스만 해진다. 여기에 몬스터의 `scale`(레벨과 강함으로
 * 정해진다)이 곱해지므로, 보스는 자동으로 더 커진다.
 */
export const BEAST_HEIGHT: Record<string, number> = {
  // 작은 것들
  rat: 0.4,
  frog: 0.45,
  snake: 0.45,
  shibainu: 0.55,
  fox: 0.6,
  wasp: 0.65,
  spider: 0.65,
  // 네발 짐승
  husky: 0.8,
  wolf: 0.85,
  deer: 1.1,
  bull: 1.15,
  stag: 1.2,
  horse: 1.5,
  horse_white: 1.5,
  // 큰 것들
  velociraptor: 1.35,
  stegosaurus: 1.5,
  triceratops: 1.5,
  parasaurolophus: 1.8,
  trex: 2.4,
  apatosaurus: 2.6,
  // VARCO 오우거 — 사람(1.8)보다 머리 하나 반 크다. 파일 높이가 0.88~0.94 라 2.4 배쯤 키운다
  varco_ogre1: 2.2,
  varco_ogre2: 2.2,
  varco_ogre3: 2.2,
  varco_ogre4: 2.2,
  varco_ogre5: 2.2,
};
export const BEAST_HEIGHT_DEFAULT = 0.9;

/** 이름표를 띄우는 높이는 키보다 조금 위다 (m) */
const HEAD_MARGIN = 0.25;

/** 이 짐승이 세계에서 갖는 키 (m) */
export function beastHeight(look: string, scale: number): number {
  return (BEAST_HEIGHT[look] ?? BEAST_HEIGHT_DEFAULT) * scale;
}

/** 이름표·클릭 상자가 기준으로 삼는 머리 높이 (m) */
export function beastHeadHeight(look: string, scale: number): number {
  return beastHeight(look, scale) + HEAD_MARGIN;
}

/**
 * 클릭 판정 상자의 크기.
 *
 * **몸 메시로는 클릭이 잘 안 맞는다.** 몬스터는 스킨드 메시라 레이캐스트가
 * 팔·다리·꼬리 같은 실제 삼각형에 맞아야 하고, 애니메이션으로 자세가 바뀌면
 * 더 얇아진다. 그래서 몸 크기만 한 상자를 씌우고 그걸 맞힌다.
 */
const HIT_BOX = {
  /** 몸 반지름(충돌 반경)의 몇 배를 한 변으로 쓸지. 여유가 있어야 누르기 쉽다 */
  width: 2.4,
  /**
   * 키의 몇 배까지는 폭을 확보한다. ★
   *
   * 충돌 반경(`monsterRadius`)은 **레벨로만 정해져서 겉모습과 무관하다** —
   * 2.2m 오우거도 0.38m 늑대와 같은 값이다. 반경만 보면 오우거 상자가 어깨보다
   * 좁아져서 팔을 눌러도 땅으로 샌다. 키로 한 번 더 받쳐 준다.
   */
  widthOfHeight: 0.55,
  /** 아주 작은 몬스터도 이만큼은 (m) */
  minWidth: 1.0,
  /**
   * 머리 높이의 몇 배. ★
   *
   * **1 을 크게 넘기면 안 된다.** `beastHeadHeight` 가 이미 키 위로 여유를 주므로,
   * 여기서 또 키우면 상자가 머리 위 허공까지 먹는다. 그 허공이 **뒷줄 몬스터의
   * 몸을 덮어** 뒤에 선 놈을 눌러도 앞놈이 잡힌다 (`npm run hit-probe` 의 "뒷놈이
   * 몇 % 남는가"). 절차적 리그는 머리 높이가 몸보다 조금 낮아서 약간만 얹는다.
   */
  height: 1.05,
  minHeight: 1.0,
};

/**
 * 클릭 상자의 **월드 크기**(m). 바닥에서 재므로 상자 중심은 `h / 2` 에 놓는다.
 *
 * 리그의 자식으로 붙일 때는 **리그 그룹에 걸린 배율로 나눠야 한다** — 모델
 * 리그는 파일 단위를 세계에 맞추느라 그룹을 통째로 키운다(`fit`). 그냥 붙이면
 * 그 배율이 한 번 더 곱해진다.
 */
export function hitBoxSize(radius: number, headHeight: number): { w: number; h: number } {
  return {
    w: Math.max(HIT_BOX.minWidth, radius * HIT_BOX.width, headHeight * HIT_BOX.widthOfHeight),
    h: Math.max(HIT_BOX.minHeight, headHeight * HIT_BOX.height),
  };
}
