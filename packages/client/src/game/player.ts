import * as THREE from 'three';
import { RUN_SPEED, applyMove, zoneHalfSize, type MoveInput } from '@mmo/shared';
import type { CharacterRig, GearLook } from './characterRig';
import { createRig } from './rigFactory';
import { CLASSES, type ClassId } from './characterClasses';

/** 이 이상 어긋나면 부드럽게 당기지 않고 즉시 스냅한다 (텔레포트, 서버 강제 보정 등) */
const SNAP_DISTANCE = 2.5;
/** 매 보정마다 오차를 이만큼 줄인다. 1이면 딱딱하고, 낮으면 늘어진다 */
const CORRECTION_RATE = 0.25;

export class Player {
  /** 컨테이너. 직업을 바꾸면 안의 리그만 갈아끼운다 */
  readonly group = new THREE.Group();
  readonly headHeight: number;
  readonly position: THREE.Vector3;

  private rig: CharacterRig;
  private classId: ClassId;
  /** 지금 그려둔 장비. 직업을 바꾸면 리그를 새로 만드므로 다시 입혀야 한다 */
  private gear: GearLook = { weapon: '', offhand: '', helmet: '' };

  private readonly moveTarget = new THREE.Vector3();
  private hasMoveTarget = false;
  private readonly dir = new THREE.Vector3();
  private facing = 0;
  private currentSpeed = 0;
  /** 현재 존의 이동 한계 (존마다 크기가 다르다) */
  private halfSize = 100;

  /** 서버가 아직 확인해주지 않은 입력들. 보정할 때 이것만 다시 적용한다 */
  private readonly pending: MoveInput[] = [];
  private seq = 0;
  private readonly replay = { x: 0, z: 0 };

  constructor(name: string, classId: ClassId) {
    this.group.name = name;
    this.position = this.group.position;
    this.classId = classId;
    this.rig = createRig(CLASSES[classId]);
    this.group.add(this.rig.group);
    this.headHeight = this.rig.headHeight;
  }

  get job(): ClassId {
    return this.classId;
  }

  get speed(): number {
    return this.currentSpeed;
  }

  setClass(classId: ClassId): void {
    if (classId === this.classId) return;
    this.group.remove(this.rig.group);
    this.rig.dispose();
    this.classId = classId;
    this.rig = createRig(CLASSES[classId]);
    this.group.add(this.rig.group);
    // 새 리그는 빈손으로 시작한다. 들고 있던 걸 다시 입힌다.
    this.rig.setGear(this.gear);
  }

  setBounds(zoneSize: number): void {
    this.halfSize = zoneHalfSize(zoneSize);
  }

  /**
   * 존 진입/포탈 도착 시 즉시 배치. 남아 있던 이동 명령과 예측 이력도 지운다.
   *
   * **seq 는 절대 되돌리지 않는다.** 서버는 `seq <= player.lastSeq` 인 입력을
   * 지연 도착한 중복 패킷으로 보고 버린다. 여기서 0 으로 되돌리면 이미 그 번호를
   * 지나온 서버가 다시 따라잡을 때까지 내 이동을 통째로 무시한다 — 클라이언트만
   * 혼자 걸어가고 보정은 계속 서버 자리(스폰 지점)로 끌어당겨서, 걷다가 한가운데로
   * 순간이동하고 자동 사냥을 켜서 예측을 멈추는 순간 그대로 스폰 지점에 붙는다.
   * 로그인·캐릭터 선택 화면에 머문 시간만큼 그 구간이 길어진다 (매 프레임 번호를
   * 하나 쓰므로 60fps 면 초당 60). 접속 하나에서 번호는 단조 증가만 한다. 존을
   * 옮기면 서버가 새 Player 를 만들며 lastSeq 를 0 으로 두므로 큰 번호가 이어져도
   * 문제없다.
   */
  teleport(x: number, z: number): void {
    this.position.set(x, 0, z);
    this.hasMoveTarget = false;
    this.dir.set(0, 0, 0);
    this.currentSpeed = 0;
    this.pending.length = 0;
  }

  /** 공격 모션 */
  swing(): void {
    this.rig.swing();
  }

  /** 손에 든 것과 투구. 서버가 내려준 값을 그대로 넘긴다 */
  setGear(gear: GearLook): void {
    this.gear = gear;
    this.rig.setGear(gear);
  }

  /** 클릭 이동 목표 지정 */
  setMoveTarget(point: THREE.Vector3): void {
    this.moveTarget.set(point.x, 0, point.z);
    this.hasMoveTarget = true;
  }

  /** 이동 목표를 버리고 제자리에 선다 (자동 사냥 해제, 사망 등) */
  stop(): void {
    this.hasMoveTarget = false;
  }

  /**
   * 한 프레임 진행하고, 서버에 보낼 입력을 돌려준다.
   *
   * 위치는 서버 응답을 기다리지 않고 즉시 반영한다(예측).
   * 서버가 확정 위치를 보내주면 reconcile() 이 차이를 메운다.
   */
  update(dt: number, axis: THREE.Vector2, camYaw: number): MoveInput {
    this.dir.set(0, 0, 0);

    if (axis.lengthSq() > 0.0001) {
      // 키보드 입력이 들어오면 클릭 이동은 취소
      this.hasMoveTarget = false;
      const sin = Math.sin(camYaw);
      const cos = Math.cos(camYaw);
      // 화면 오른쪽 = (cos, -sin), 화면 위쪽 = -(sin, cos)
      this.dir.set(cos * axis.x + sin * axis.y, 0, -sin * axis.x + cos * axis.y);
      this.dir.normalize();
    } else if (this.hasMoveTarget) {
      this.dir.subVectors(this.moveTarget, this.position);
      this.dir.y = 0;
      if (this.dir.lengthSq() < 0.02) {
        this.hasMoveTarget = false;
        this.dir.set(0, 0, 0);
      } else {
        this.dir.normalize();
      }
    }

    const input: MoveInput = { seq: ++this.seq, dx: this.dir.x, dz: this.dir.z, dt };
    const moving = this.dir.lengthSq() > 0.0001;

    if (moving) {
      // 서버와 완전히 같은 함수로 계산해야 보정이 튀지 않는다
      applyMove(this.position, input, this.halfSize);
      this.pending.push(input);

      const want = Math.atan2(this.dir.x, this.dir.z);
      let delta = want - this.facing;
      while (delta > Math.PI) delta -= Math.PI * 2;
      while (delta < -Math.PI) delta += Math.PI * 2;
      this.facing += delta * (1 - Math.exp(-14 * dt));
      this.group.rotation.y = this.facing;
    }

    this.currentSpeed = moving ? RUN_SPEED : 0;
    this.rig.update(dt, this.currentSpeed);

    return input;
  }

  /**
   * 서버 확정 위치로 보정한다.
   *
   * 서버 위치에서 시작해 "아직 확인 안 된 입력"만 다시 적용하면 지금 있어야 할
   * 위치가 나온다. 그 차이만큼만 당기므로 지연이 있어도 조작감이 죽지 않는다.
   */
  reconcile(serverX: number, serverZ: number, lastSeq: number): void {
    while (this.pending.length > 0 && this.pending[0]!.seq <= lastSeq) this.pending.shift();

    this.replay.x = serverX;
    this.replay.z = serverZ;
    for (const input of this.pending) applyMove(this.replay, input, this.halfSize);

    const dx = this.replay.x - this.position.x;
    const dz = this.replay.z - this.position.z;
    const error = Math.hypot(dx, dz);

    if (error < 0.002) return;
    if (error > SNAP_DISTANCE) {
      this.position.x = this.replay.x;
      this.position.z = this.replay.z;
      return;
    }
    this.position.x += dx * CORRECTION_RATE;
    this.position.z += dz * CORRECTION_RATE;
  }
}
