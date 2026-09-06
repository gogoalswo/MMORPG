import * as THREE from 'three';

/**
 * 바닥에 그리는 범위 공격 예고 원.
 *
 * 보스가 범위 공격을 걸면 서버가 "여기에, 이만큼, 몇 ms 뒤"를 알려준다.
 * 여기서 하는 일은 **보여주는 것뿐**이다. 실제로 누가 맞았는지는 서버가 따로
 * 판정해서 `hit` 으로 알려준다 — 클라이언트가 "나는 피했다"고 말하게 두면 그
 * 말을 믿어야 하기 때문이다. 그래서 이 원이 틀려도 피해는 달라지지 않고,
 * 반대로 이 원이 안 떠도 맞을 사람은 맞는다.
 *
 * 원은 **시전을 시작한 자리에 고정**된다. 보스를 따라다니면 붙어서 때리는
 * 쪽은 피할 방법이 없다.
 *
 * 채워지는 안쪽 원이 곧 남은 시간이다. 숫자를 띄우지 않는 이유는 발밑을 보는
 * 시선을 화면 밖으로 끌고 가지 않기 위해서다 — 다 차면 터진다.
 */

/** 터진 뒤 사라지기까지 (초). 짧게 번쩍이고 없어진다 */
const FLASH_SEC = 0.34;
/** 지면과 겹쳐 어른거리지 않게 살짝 띄운다 */
const GROUND_OFFSET = 0.06;
/** 테두리 안쪽 반지름 비율. 원이 커져도 굵기가 눈에 비슷하게 보인다 */
const RIM = 0.955;

const RING_OPACITY = 0.95;
const FILL_OPACITY = 0.3;

interface Marker {
  ring: THREE.Mesh;
  fill: THREE.Mesh;
  ringMat: THREE.MeshBasicMaterial;
  fillMat: THREE.MeshBasicMaterial;
  radius: number;
  /** 0 → 1 로 차오른다 */
  t: number;
  /** 다 차는 데 걸리는 시간 (초) */
  duration: number;
  /** 터진 뒤 흐른 시간 (초). 0 이면 아직 안 터졌다 */
  flash: number;
}

export class AoeMarkers {
  readonly group = new THREE.Group();

  private readonly ringGeo: THREE.RingGeometry;
  private readonly fillGeo: THREE.CircleGeometry;

  private readonly active: Marker[] = [];
  /** 다 쓴 것은 버리지 않고 돌려 쓴다 — 보스전 내내 계속 뜬다 */
  private readonly pool: Marker[] = [];

  constructor() {
    this.group.name = 'aoe';
    // 지면보다 나중에 그려서 z-fighting 없이 위에 얹는다
    this.group.renderOrder = 2;

    // 반지름 1 로 만들어 두고 scale 로 키운다. 시전할 때마다 지오메트리를
    // 새로 만들면 첫 시전에서 프레임이 튄다.
    this.ringGeo = new THREE.RingGeometry(RIM, 1, 64);
    this.ringGeo.rotateX(-Math.PI / 2);
    this.fillGeo = new THREE.CircleGeometry(1, 64);
    this.fillGeo.rotateX(-Math.PI / 2);
  }

  /**
   * 재질은 **표시 하나마다 따로** 둔다. 공유하면 투명도를 개별로 못 줘서
   * 터질 때 사라지지 못하고 그냥 꺼진다 — 그러면 터진 순간을 놓친다.
   * 동시에 뜨는 개수는 보스 수만큼이라 비용이 문제되지 않는다.
   */
  private take(): Marker {
    const reused = this.pool.pop();
    if (reused) {
      reused.ring.visible = true;
      reused.fill.visible = true;
      return reused;
    }

    // 조명을 받지 않는 재질이다. 사냥터마다 지면 색과 밝기가 크게 달라서
    // (눈밭·용암·늪) 빛을 받으면 어떤 존에서는 경고가 배경에 묻힌다.
    const base = {
      transparent: true,
      depthWrite: false,
      toneMapped: false,
      side: THREE.DoubleSide,
    } as const;
    const ringMat = new THREE.MeshBasicMaterial({ ...base, color: 0xff4a33, opacity: RING_OPACITY });
    const fillMat = new THREE.MeshBasicMaterial({ ...base, color: 0xff7a45, opacity: FILL_OPACITY });

    const ring = new THREE.Mesh(this.ringGeo, ringMat);
    const fill = new THREE.Mesh(this.fillGeo, fillMat);
    // 원은 항상 누군가의 발밑이라 화면 안에 있다. 컬링 계산을 아낀다.
    ring.frustumCulled = false;
    fill.frustumCulled = false;
    this.group.add(ring, fill);

    return { ring, fill, ringMat, fillMat, radius: 1, t: 0, duration: 1, flash: 0 };
  }

  private give(marker: Marker): void {
    marker.ring.visible = false;
    marker.fill.visible = false;
    this.pool.push(marker);
  }

  /**
   * 예고 하나를 띄운다.
   *
   * `delayMs` 는 서버가 정한 시간을 그대로 쓴다. 여기서 늘리거나 줄이면
   * 화면에서는 아직 안 찼는데 피해가 들어온다.
   */
  add(x: number, z: number, radius: number, delayMs: number): void {
    const m = this.take();
    m.radius = radius;
    m.t = 0;
    m.duration = Math.max(0.05, delayMs / 1000);
    m.flash = 0;

    m.ring.position.set(x, GROUND_OFFSET, z);
    m.ring.scale.setScalar(radius);
    m.ringMat.opacity = RING_OPACITY;
    m.fill.position.set(x, GROUND_OFFSET, z);
    m.fill.scale.setScalar(0.001);
    m.fillMat.opacity = FILL_OPACITY;

    this.active.push(m);
  }

  update(dt: number): void {
    for (let i = this.active.length - 1; i >= 0; i--) {
      const m = this.active[i]!;

      // --- 터진 뒤: 밖으로 퍼지며 사라진다 ---
      // 그냥 꺼지면 터진 걸 못 보고 넘긴다.
      if (m.flash > 0) {
        m.flash += dt;
        const k = Math.min(1, m.flash / FLASH_SEC);
        const spread = m.radius * (1 + k * 0.14);
        m.ring.scale.setScalar(spread);
        m.fill.scale.setScalar(spread);
        m.ringMat.opacity = RING_OPACITY * (1 - k);
        // 터지는 순간 안쪽이 확 밝아졌다가 같이 사라진다
        m.fillMat.opacity = (FILL_OPACITY + 0.35) * (1 - k);
        if (k >= 1) {
          this.give(m);
          this.active.splice(i, 1);
        }
        continue;
      }

      // --- 차오르는 중 ---
      m.t += dt / m.duration;
      if (m.t >= 1) {
        m.t = 1;
        m.flash = 1e-4;
      }
      m.fill.scale.setScalar(Math.max(0.001, m.radius * m.t));
      // 마지막 순간에 테두리가 빨라진다 — 언제 터지는지 발밑만 봐도 알게
      m.ringMat.opacity = RING_OPACITY * (0.72 + 0.28 * Math.abs(Math.sin(m.t * m.t * 18)));
    }
  }

  /** 존을 옮기거나 화면이 오래 멈췄을 때. 남은 예고는 의미가 없다 */
  clear(): void {
    for (const m of this.active) this.give(m);
    this.active.length = 0;
  }

  dispose(): void {
    this.clear();
    this.ringGeo.dispose();
    this.fillGeo.dispose();
    for (const m of this.pool) {
      m.ringMat.dispose();
      m.fillMat.dispose();
    }
    this.pool.length = 0;
  }
}
