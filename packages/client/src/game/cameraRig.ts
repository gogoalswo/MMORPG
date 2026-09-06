import * as THREE from 'three';

/**
 * 고정각 쿼터뷰 카메라.
 * 좁은 FOV(30도)로 원근을 죽여서 아이소메트릭 느낌을 내는 게 핵심이다.
 * 완전한 직교 투영은 건물 입체감이 사라져서 레퍼런스와 다르다.
 */
export class CameraRig {
  readonly camera: THREE.PerspectiveCamera;

  private yaw = Math.PI / 4;      // 45도
  private targetYaw = Math.PI / 4;
  private readonly pitch = THREE.MathUtils.degToRad(42);
  private distance = 40;
  private targetDistance = 40;
  private readonly focus = new THREE.Vector3();
  private readonly desired = new THREE.Vector3();
  private readonly offset = new THREE.Vector3();
  /** 캐릭터 원점은 발밑이다. 가슴 높이를 봐야 가까이 당겨도 머리가 안 잘린다 */
  private readonly focusHeight = 1.0;

  constructor(aspect: number) {
    this.camera = new THREE.PerspectiveCamera(30, aspect, 1, 400);
  }

  resize(aspect: number): void {
    this.camera.aspect = aspect;
    this.camera.updateProjectionMatrix();
  }

  /** Q/E — 45도 단위로 스냅 회전 */
  rotate(dir: -1 | 1): void {
    this.targetYaw += (dir * Math.PI) / 4;
  }

  zoom(delta: number): void {
    this.targetDistance = THREE.MathUtils.clamp(this.targetDistance + delta, 8, 60);
  }

  get yawAngle(): number {
    return this.yaw;
  }

  /** 존 진입 시 보간 없이 곧바로 자리잡는다 */
  snapTo(target: THREE.Vector3): void {
    this.focus.set(target.x, target.y + this.focusHeight, target.z);
    this.yaw = this.targetYaw;
    this.distance = this.targetDistance;
    this.update(1, target);
  }

  update(dt: number, target: THREE.Vector3): void {
    // 지수 감쇠 스무딩 — 프레임레이트에 독립적
    const k = 1 - Math.exp(-9 * dt);
    this.yaw += (this.targetYaw - this.yaw) * k;
    this.distance += (this.targetDistance - this.distance) * k;
    // 캐릭터를 화면 정중앙에 둔다
    this.desired.set(target.x, target.y + this.focusHeight, target.z);
    this.focus.lerp(this.desired, 1 - Math.exp(-11 * dt));

    const cosP = Math.cos(this.pitch);
    this.offset.set(
      cosP * Math.sin(this.yaw),
      Math.sin(this.pitch),
      cosP * Math.cos(this.yaw)
    ).multiplyScalar(this.distance);

    this.camera.position.copy(this.focus).add(this.offset);
    this.camera.lookAt(this.focus);
  }
}
