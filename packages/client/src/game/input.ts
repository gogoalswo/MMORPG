import * as THREE from 'three';
import { SKILL_BAR_SIZE } from '@mmo/shared';

/**
 * 입력.
 *
 * **이동은 마우스 클릭으로만 한다.** WASD·방향키 이동은 2026-09-11 에 뺐다 —
 * 키보드는 스킬(1~4)·카메라(Q/E)·단축키만 맡는다.
 */
export class Input {
  /** 눌려 있는 키 — 키를 누르고 있을 때 반복해서 오는 keydown 을 한 번으로 거른다 */
  private readonly keys = new Set<string>();
  /**
   * 커서 아래 지면 좌표. 누른 순간과, 누르고 있는 동안 매 프레임 호출된다.
   *
   * `pressed` 는 **누른 그 프레임에만** true 다. 끌고 다니는 동안 오는 것과
   * 구분하려고 붙였다 — 클릭 표시를 매 프레임 다시 찍으면 애니메이션이
   * 계속 처음으로 돌아가 멈춰 있는 것처럼 보인다.
   */
  onGroundPoint: ((point: THREE.Vector3, pressed: boolean) => void) | null = null;
  onRotate: ((dir: -1 | 1) => void) | null = null;
  onZoom: ((delta: number) => void) | null = null;
  /**
   * 몬스터를 눌렀다. 지면 이동 대신 이쪽이 불린다.
   *
   * 여기서는 "누구를 눌렀다"만 알린다. 붙고 때리는 건 서버가 한다.
   */
  onPickTarget: ((monsterId: string) => void) | null = null;
  /** 숫자키 1~4 로 액션바 칸 사용 (0-based 칸 번호) */
  onSkill: ((index: number) => void) | null = null;
  /** 스페이스바 공격 */
  onAttack: (() => void) | null = null;

  private readonly raycaster = new THREE.Raycaster();
  private readonly ndc = new THREE.Vector2();

  /** 왼쪽 버튼을 누르고 있는 중인지 */
  private held = false;

  /** 존이 바뀌면 레이캐스트 대상 지면도 바뀐다 */
  private ground: THREE.Object3D | null = null;

  /**
   * 클릭으로 고를 수 있는 대상들(몬스터). 지면보다 **먼저** 본다.
   *
   * 맞은 메시에서 몬스터 id 를 되찾는 건 이 클래스가 알 바가 아니라서,
   * 찾는 방법을 함께 받아둔다.
   */
  private targets: THREE.Object3D | null = null;
  private targetIdOf: ((object: THREE.Object3D) => string | null) | null = null;

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly camera: THREE.Camera
  ) {
    window.addEventListener('keydown', this.handleKeyDown);
    window.addEventListener('keyup', this.handleKeyUp);
    window.addEventListener('blur', () => this.keys.clear());
    canvas.addEventListener('pointerdown', this.handlePointerDown);
    canvas.addEventListener('pointermove', this.handlePointerMove);
    canvas.addEventListener('pointerup', this.handlePointerUp);
    canvas.addEventListener('pointercancel', this.handlePointerUp);
    canvas.addEventListener('wheel', this.handleWheel, { passive: false });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    // 창 밖에서 버튼을 떼면 pointerup 이 안 올 수 있다
    window.addEventListener('blur', this.cancelHold);
  }

  /** 채팅창 등 텍스트 입력에 포커스가 있으면 게임 조작을 막는다 */
  private static isTyping(e: Event): boolean {
    const el = e.target as HTMLElement | null;
    if (!el) return false;
    const tag = el.tagName;
    return tag === 'INPUT' || tag === 'TEXTAREA' || el.isContentEditable;
  }

  /**
   * 채팅창이 열릴 때 눌려 있던 키를 털어낸다. 누른 채 채팅으로 넘어가면 keyup 을
   * 못 받아서, 다음에 같은 키를 눌러도 "이미 눌려 있음" 으로 걸러져 안 먹는다.
   */
  clearKeys(): void {
    this.keys.clear();
  }

  private handleKeyDown = (e: KeyboardEvent): void => {
    if (Input.isTyping(e)) return;
    const k = e.code;
    if (!this.keys.has(k)) {
      if (k === 'Space') this.onAttack?.();
      if (k === 'KeyQ') this.onRotate?.(-1);
      if (k === 'KeyE') this.onRotate?.(1);
      if (k.startsWith('Digit')) {
        const n = Number(k.slice(5));
        // 액션바 칸 수만큼만 (1~4). 5~9 는 비워 둔다
        if (n >= 1 && n <= SKILL_BAR_SIZE) this.onSkill?.(n - 1);
      }
    }
    this.keys.add(k);
  };

  private handleKeyUp = (e: KeyboardEvent): void => {
    this.keys.delete(e.code);
  };

  private handleWheel = (e: WheelEvent): void => {
    e.preventDefault();
    this.onZoom?.(Math.sign(e.deltaY) * 3);
  };

  setGround(ground: THREE.Object3D): void {
    this.ground = ground;
  }

  setTargets(group: THREE.Object3D, idOf: (object: THREE.Object3D) => string | null): void {
    this.targets = group;
    this.targetIdOf = idOf;
  }

  private handlePointerDown = (e: PointerEvent): void => {
    if (e.button !== 0) return;
    this.held = true;
    // 캔버스 밖으로 끌고 나가도 계속 추적되도록.
    // 활성 포인터가 아니면 예외를 던지므로, 여기서 죽으면 이동 자체가 막힌다.
    try {
      this.canvas.setPointerCapture(e.pointerId);
    } catch {
      /* 캡처는 편의 기능이라 실패해도 이동은 계속돼야 한다 */
    }
    this.updateNdc(e);

    // 몬스터를 눌렀으면 이동이 아니라 지목이다.
    // 누른 채 끌면(held) 그 뒤로는 지면을 따라가므로, 여기서만 본다.
    const picked = this.pickTarget();
    if (picked) {
      this.held = false;
      this.onPickTarget?.(picked);
      return;
    }

    this.emitGroundPoint(true);
  };

  /** 커서 아래 몬스터. 없으면 null */
  private pickTarget(): string | null {
    if (!this.targets || !this.targetIdOf) return null;
    this.raycaster.setFromCamera(this.ndc, this.camera);
    for (const hit of this.raycaster.intersectObject(this.targets, true)) {
      const id = this.targetIdOf(hit.object);
      if (id) return id;
    }
    return null;
  }

  private handlePointerMove = (e: PointerEvent): void => {
    if (!this.held) return;
    this.updateNdc(e);
  };

  private handlePointerUp = (): void => {
    this.held = false;
  };

  /** 존 전환처럼 조작을 끊어야 할 때 */
  cancelHold = (): void => {
    this.held = false;
  };

  private updateNdc(e: PointerEvent): void {
    const rect = this.canvas.getBoundingClientRect();
    this.ndc.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
    this.ndc.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
  }

  private emitGroundPoint(pressed = false): void {
    if (!this.ground) return;
    this.raycaster.setFromCamera(this.ndc, this.camera);
    const hit = this.raycaster.intersectObject(this.ground, false)[0];
    // 커서가 하늘을 가리키면 직전 목표를 유지한다
    if (hit) this.onGroundPoint?.(hit.point, pressed);
  }

  /**
   * 매 프레임 호출. 버튼을 누르고 있는 동안 커서 아래 지면을 다시 계산한다.
   *
   * 커서가 멈춰 있어도 다시 쏴야 한다 — 카메라를 돌리거나 캐릭터가 움직이면
   * 같은 화면 좌표라도 월드 좌표가 달라진다.
   */
  update(): void {
    if (this.held) this.emitGroundPoint();
  }
}
