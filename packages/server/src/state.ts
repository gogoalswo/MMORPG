import { schema, t } from '@colyseus/schema';

/**
 * 네트워크로 동기화되는 상태.
 *
 * 데코레이터(@type) 대신 schema()/t.* 함수형 정의를 쓴다 —
 * Node 가 타입만 벗겨내고 그대로 실행할 수 있어서 빌드 단계가 필요 없다.
 *
 * 좌표는 float32 로 보낸다. 월드가 ±110 이라 정밀도는 충분하고 대역폭은 절반이다.
 */

export const Player = schema({
  id: t.string(),
  name: t.string(),
  job: t.string(),

  x: t.float32(),
  z: t.float32(),
  rotY: t.float32(),

  hp: t.uint16(),
  maxHp: t.uint16(),
  mp: t.uint16(),
  maxMp: t.uint16(),
  level: t.uint16(),
  exp: t.uint32(),
  /** 죽은 상태면 조작을 막고 리스폰을 기다린다 */
  dead: t.boolean(),

  /**
   * 자동 사냥 중인지. **판단과 이동을 서버가 한다** —
   * 클라이언트에서 돌리면 탭을 옮기는 순간 브라우저가 루프를 멈춘다.
   */
  auto: t.boolean(),

  /**
   * 클릭으로 지정한 대상을 쫓는 중인지.
   *
   * 자동 사냥과 마찬가지로 **이동을 서버가 한다.** 클라이언트는 이 값을 보고
   * 자기 예측을 멈춘다 — 둘이 동시에 움직이면 보정이 싸워서 캐릭터가 떨린다.
   */
  chasing: t.boolean(),

  /**
   * 남에게도 보이는 장비.
   *
   * 가방은 본인에게만 보내지므로(inventory 메시지), 그것만으로는 **남의 손에
   * 뭐가 들렸는지 알 수 없다.** 화면에 그려야 하는 세 자리만 상태로 내려보낸다.
   * 값은 아이템 id 이고, 빈 문자열이면 그 자리가 비어 있다는 뜻이다.
   */
  weapon: t.string(),
  offhand: t.string(),
  helmet: t.string(),

  /** 서버가 마지막으로 처리한 입력 번호. 클라이언트 예측 보정의 기준점 */
  lastSeq: t.uint32(),
});

export type PlayerState = InstanceType<typeof Player>;

export const Monster = schema({
  id: t.string(),
  kind: t.string(),
  x: t.float32(),
  z: t.float32(),
  rotY: t.float32(),
  hp: t.uint16(),
  maxHp: t.uint16(),
  /**
   * 클라이언트가 애니메이션을 고르는 데 쓴다:
   * idle | chase | attack | **cast**(범위 공격 예고 중) | dead
   */
  state: t.string(),
});

export type MonsterState = InstanceType<typeof Monster>;

export const ZoneState = schema({
  zoneId: t.string(),
  /**
   * .view() 가 핵심이다. 이 맵은 클라이언트별 StateView 에 등록된 항목만 전송된다.
   * 즉 주변 셀에 있는 플레이어만 내려간다 (관심영역 필터링).
   */
  players: t.map(Player).view(),
  /** 몬스터도 관심영역 필터를 탄다 — 존 반대편 몬스터까지 보낼 이유가 없다 */
  monsters: t.map(Monster).view(),
});

export type ZoneStateType = InstanceType<typeof ZoneState>;
