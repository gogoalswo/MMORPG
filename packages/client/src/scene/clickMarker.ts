import * as THREE from 'three';

/**
 * 클릭해서 이동할 때 그 자리 바닥에 찍히는 표시.
 *
 * **왜 있나** — 카메라가 멀고(거리 40) 캐릭터가 바로 출발하지 않는 순간이 있어서,
 * 눌렀는데 아무 일도 안 일어난 것처럼 보일 때가 있다. 어디를 눌렀는지 바닥에
 * 한 번 찍어 주면 "먹었다"가 즉시 읽힌다.
 *
 * **왜 `skillFx` 에 얹지 않았나** — 저쪽은 스킬 한 발마다 풀에서 꺼내 쓰는
 * 구조라 동시에 수십 개가 산다. 이건 **항상 하나뿐이다**(새로 누르면 앞의 것이
 * 지워진다). 메시 두 개를 만들어 두고 스케일·투명도만 건드리면 끝이라
 * 풀도, 수명 목록도 필요 없다.
 */

/** 한 번 찍힌 표시가 사라지기까지 (초) */
const DURATION = 0.5;
/**
 * 바깥 고리 반지름 — 퍼졌다가 조여든다.
 *
 * 처음에는 1.5 → 0.62 였는데 캐릭터(반지름 0.4 안팎)보다 커서 발밑을 덮었다.
 * 2026-09-15 에 절반으로 줄였다 — 끝 크기가 캐릭터 몸 반지름보다 작아야
 * "저 자리" 를 가리키는 점으로 읽힌다.
 */
const RING_FROM = 0.75;
const RING_TO = 0.31;
/** 가운데 점 */
const CORE_SIZE = 0.17;
/** 기본 색 — 지면 텍스처가 무엇이든 뜨도록 흰빛 도는 하늘색 */
const COLOR = 0x9fe9ff;
/**
 * 지면에서 띄우는 높이. 0 으로 두면 바닥 메시와 같은 평면이라 z-fighting 으로
 * 얼룩진다. 카메라가 거의 내려다보는 각이라 이 정도는 떠 보이지 않는다.
 */
const LIFT = 0.06;

export class ClickMarker {
  readonly group = new THREE.Group();

  private readonly ring: THREE.Mesh<THREE.RingGeometry, THREE.MeshBasicMaterial>;
  private readonly core: THREE.Mesh<THREE.CircleGeometry, THREE.MeshBasicMaterial>;

  /** 0~1 로 흐르는 진행도. 1 이상이면 꺼져 있다 */
  private t = 1;

  constructor() {
    this.group.name = 'clickMarker';
    // 음영(GTAO) 계산에서 뺀다 — 안 빼면 반투명 판이 까맣게 눌린다 (postfx.ts)
    this.group.userData.noAO = true;
    this.group.visible = false;

    const look = {
      color: COLOR,
      transparent: true,
      // 겹쳐 그릴 때 뒤엣것을 지우지 않는다. 바닥에 눕는 반투명 판의 기본
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      side: THREE.DoubleSide,
    } as const;

    const ringGeo = new THREE.RingGeometry(0.8, 1, 48);
    ringGeo.rotateX(-Math.PI / 2);
    this.ring = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({ ...look }));

    const coreGeo = new THREE.CircleGeometry(1, 24);
    coreGeo.rotateX(-Math.PI / 2);
    this.core = new THREE.Mesh(coreGeo, new THREE.MeshBasicMaterial({ ...look }));

    for (const m of [this.ring, this.core]) {
      // 지면 바로 위에 눕는 판이라 컬링 계산이 어긋나기 쉽다. 두 장뿐이니 그냥 그린다
      m.frustumCulled = false;
      m.renderOrder = 1;
      this.group.add(m);
    }
  }

  /** 누른 자리에 다시 찍는다. 이미 떠 있던 표시는 지워지고 처음부터 다시 돈다 */
  show(at: THREE.Vector3): void {
    this.group.position.set(at.x, at.y + LIFT, at.z);
    this.group.visible = true;
    this.t = 0;
    this.apply();
  }

  clear(): void {
    this.t = 1;
    this.group.visible = false;
  }

  update(dt: number): void {
    if (this.t >= 1) return;
    this.t += dt / DURATION;
    if (this.t >= 1) {
      this.clear();
      return;
    }
    this.apply();
  }

  private apply(): void {
    const t = this.t;
    // 처음엔 빠르게, 끝에서 느리게 조여든다
    const e = 1 - (1 - t) * (1 - t);
    const r = RING_FROM + (RING_TO - RING_FROM) * e;
    this.ring.scale.set(r, 1, r);
    this.core.scale.setScalar(CORE_SIZE * (0.4 + 0.6 * e));

    /**
     * 밝기 — **빠르게 켜고 끝에서만 끈다.** `1-t` 로 처음부터 흐려지게 두면
     * 가장 작아진(=가장 잘 보여야 할) 순간이 가장 투명한 순간과 겹쳐서,
     * 멀리 있는 카메라에서는 어느 프레임에도 눈에 걸리지 않는다.
     * 스킬 이펙트에서 같은 것으로 한 번 헤맸다 (`skillFx.ts` 의 밝기 곡선).
     */
    const a = Math.min(1, t / 0.08) * Math.min(1, (1 - t) / 0.4);
    this.ring.material.opacity = a;
    this.core.material.opacity = a * 0.7;
  }
}
