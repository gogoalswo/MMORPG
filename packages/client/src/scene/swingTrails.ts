import * as THREE from 'three';
import type { WeaponEdge } from '../game/characterRig';

/**
 * 무기 궤적.
 *
 * 공격 모션이 나가는 동안 무기의 날 양 끝을 매 프레임 받아 적고, 그 자국을
 * 리본으로 잇는다. 칼이 지나간 자리가 잠깐 남아야 "휘둘렀다" 가 읽힌다 —
 * 모션만으로는 프레임 사이에 칼이 순간이동한 것처럼 보인다.
 *
 * **날 위치는 리그가 알려준다** (`WeaponEdge`). 여기서 무기 모양을 알면
 * 직업이 늘거나 장비 메시가 바뀔 때마다 이 파일을 같이 고쳐야 한다.
 *
 * 사라지는 방식이 조금 특이하다. **가산 합성(AdditiveBlending)에서는 검은색이
 * 곧 투명**이라, 꼬리로 갈수록 색을 검게 깎는 것만으로 자연스럽게 사라진다.
 * 정점마다 알파를 따로 다루지 않아도 되고, 셰이더를 새로 쓸 필요도 없다.
 */

/** 날 자국을 남기는 시간 (초). 공격 모션 길이에 맞춘다 */
const SAMPLE_SEC = 0.3;
/** 자국 하나가 남아 있는 시간 (초) */
const LIFE_SEC = 0.22;
/** 리본 한 개가 가질 수 있는 최대 마디 수 (144Hz 에서도 넉넉하다) */
const MAX_STEPS = 56;
/** 이만큼 안 움직였으면 마디를 안 찍는다 — 제자리에서 겹쳐 찍히면 띠가 지저분해진다 */
const MIN_STEP = 0.004;

interface Step {
  bx: number;
  by: number;
  bz: number;
  tx: number;
  ty: number;
  tz: number;
  /** 찍힌 뒤 흐른 시간 (초) */
  age: number;
}

interface Trail {
  mesh: THREE.Mesh;
  geometry: THREE.BufferGeometry;
  position: THREE.BufferAttribute;
  color: THREE.BufferAttribute;
  source: WeaponEdge | null;
  steps: Step[];
  /** 남은 기록 시간 (초). 0 이 되면 꼬리만 사라지길 기다린다 */
  left: number;
  tint: THREE.Color;
}

export class SwingTrails {
  readonly group = new THREE.Group();

  private readonly material: THREE.MeshBasicMaterial;
  private readonly active: Trail[] = [];
  private readonly pool: Trail[] = [];

  private readonly base = new THREE.Vector3();
  private readonly tip = new THREE.Vector3();

  constructor() {
    this.group.name = 'swingTrails';
    // 캐릭터 뒤에 그려도 되지만, 칼날이 몸을 스칠 때 사라지지 않도록 깊이를
    // 쓰기만 안 한다. (깊이 검사는 남긴다 — 벽 너머로 비치면 더 이상하다)
    this.material = new THREE.MeshBasicMaterial({
      vertexColors: true,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      side: THREE.DoubleSide,
      toneMapped: false,
    });
  }

  private take(): Trail {
    const reused = this.pool.pop();
    if (reused) {
      reused.mesh.visible = true;
      return reused;
    }

    const geometry = new THREE.BufferGeometry();
    // 마디마다 정점 둘(뿌리·끝). 마디 사이를 사각형 하나로 잇는다.
    const position = new THREE.BufferAttribute(new Float32Array(MAX_STEPS * 2 * 3), 3);
    const color = new THREE.BufferAttribute(new Float32Array(MAX_STEPS * 2 * 3), 3);
    position.setUsage(THREE.DynamicDrawUsage);
    color.setUsage(THREE.DynamicDrawUsage);
    geometry.setAttribute('position', position);
    geometry.setAttribute('color', color);

    const index: number[] = [];
    for (let i = 0; i < MAX_STEPS - 1; i++) {
      const a = i * 2;
      index.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
    }
    geometry.setIndex(index);

    const mesh = new THREE.Mesh(geometry, this.material);
    // 리본은 항상 캐릭터 곁이라 화면 안이다. 컬링 계산을 아낀다.
    mesh.frustumCulled = false;
    this.group.add(mesh);

    return { mesh, geometry, position, color, source: null, steps: [], left: 0, tint: new THREE.Color() };
  }

  private give(trail: Trail): void {
    trail.mesh.visible = false;
    trail.source = null;
    trail.steps.length = 0;
    this.pool.push(trail);
  }

  /**
   * 궤적 하나를 시작한다.
   *
   * 같은 사람이 연타하면 앞의 궤적을 이어 쓰지 않고 새로 시작한다 — 이어 붙이면
   * 되돌아오는 자리가 한 줄로 이어져 리본이 접힌다.
   */
  begin(source: WeaponEdge, tint = 0xdfe8ff): void {
    // 그 사람의 이전 궤적은 기록만 멈추고 꼬리는 그대로 사라지게 둔다
    for (const t of this.active) if (t.source === source) t.left = 0;

    if (!source.weaponEdge(this.base, this.tip)) return; // 맨손이면 그릴 게 없다

    const trail = this.take();
    trail.source = source;
    trail.left = SAMPLE_SEC;
    trail.steps.length = 0;
    trail.tint.set(tint);
    this.active.push(trail);
  }

  update(dt: number): void {
    for (let i = this.active.length - 1; i >= 0; i--) {
      const trail = this.active[i]!;

      for (const step of trail.steps) step.age += dt;
      // 오래된 마디부터 버린다 (앞이 가장 오래된 것)
      while (trail.steps.length > 0 && trail.steps[0]!.age > LIFE_SEC) trail.steps.shift();

      // --- 새 마디 찍기 ---
      if (trail.left > 0 && trail.source) {
        trail.left -= dt;
        if (trail.source.weaponEdge(this.base, this.tip)) {
          const last = trail.steps[trail.steps.length - 1];
          const moved =
            !last ||
            Math.abs(this.tip.x - last.tx) +
              Math.abs(this.tip.y - last.ty) +
              Math.abs(this.tip.z - last.tz) >
              MIN_STEP;
          if (moved) {
            if (trail.steps.length >= MAX_STEPS) trail.steps.shift();
            trail.steps.push({
              bx: this.base.x, by: this.base.y, bz: this.base.z,
              tx: this.tip.x, ty: this.tip.y, tz: this.tip.z,
              age: 0,
            });
          }
        }
      }

      // 마디가 하나뿐이면 이을 면이 없다
      if (trail.steps.length < 2) {
        trail.mesh.visible = false;
        if (trail.left <= 0) {
          this.give(trail);
          this.active.splice(i, 1);
        }
        continue;
      }

      this.write(trail);
      trail.mesh.visible = true;
    }
  }

  /** 마디들을 리본 정점으로 옮긴다 */
  private write(trail: Trail): void {
    const pos = trail.position.array as Float32Array;
    const col = trail.color.array as Float32Array;
    const { r, g, b } = trail.tint;
    const count = trail.steps.length;

    for (let i = 0; i < count; i++) {
      const s = trail.steps[i]!;
      const v = i * 6;
      pos[v] = s.bx; pos[v + 1] = s.by; pos[v + 2] = s.bz;
      pos[v + 3] = s.tx; pos[v + 4] = s.ty; pos[v + 5] = s.tz;

      // 꼬리로 갈수록 어두워진다 = 가산 합성에서 사라진다.
      // 제곱으로 깎아야 끝이 흐지부지 남지 않고 확실히 없어진다.
      const life = 1 - s.age / LIFE_SEC;
      const fade = life * life;
      // 뿌리(손잡이 쪽)는 어둡고 날 끝이 밝다 — 칼날이 지나간 자리로 읽힌다
      const root = fade * 0.25;
      col[v] = r * root; col[v + 1] = g * root; col[v + 2] = b * root;
      col[v + 3] = r * fade; col[v + 4] = g * fade; col[v + 5] = b * fade;
    }

    trail.position.needsUpdate = true;
    trail.color.needsUpdate = true;
    // 마디 n 개 사이의 사각형은 n-1 개
    trail.geometry.setDrawRange(0, (count - 1) * 6);
  }

  /** 존을 옮기거나 화면이 오래 멈췄을 때. 남은 자국은 의미가 없다 */
  clear(): void {
    for (const trail of this.active) this.give(trail);
    this.active.length = 0;
  }

  dispose(): void {
    this.clear();
    for (const trail of this.pool) trail.geometry.dispose();
    this.pool.length = 0;
    this.material.dispose();
  }
}
