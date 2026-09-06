import * as THREE from 'three';
import { PROJECTILE_SPEED, type ProjectileKind } from '@mmo/shared';

/**
 * 날아가는 투사체.
 *
 * 서버는 발사 시점에 이미 명중을 확정했다. 여기서 하는 일은 **보여주는 것**뿐이고,
 * 도착할 때 콜백으로 피해 숫자를 띄우게 한다. 그래야 "쏘고 → 날아가고 → 맞는다"는
 * 인과가 화면에 보인다. 발사와 동시에 숫자가 뜨면 원거리 직업이 근접처럼 느껴진다.
 *
 * 메시는 종류별로 풀에 넣고 재사용한다. 전투가 격해지면 초당 수십 개가 생기는데
 * 그때마다 지오메트리를 만들면 프레임이 튄다.
 */

/** 화살이 그리는 포물선 높이 (m). 마법은 직선으로 간다 */
const ARROW_ARC_HEIGHT = 0.9;
/** 너무 가까우면 날아가는 게 보이지 않으므로 최소 비행시간을 준다 */
const MIN_FLIGHT = 0.08;

interface Flying {
  mesh: THREE.Mesh;
  kind: ProjectileKind;
  from: THREE.Vector3;
  to: THREE.Vector3;
  /** 0 → 1 */
  t: number;
  duration: number;
  arcHeight: number;
  onArrive: () => void;
}

function createGeometry(kind: ProjectileKind): THREE.BufferGeometry {
  switch (kind) {
    case 'arrow': {
      // 가늘고 긴 축 — 진행 방향(+Z)으로 눕혀둔다
      const geo = new THREE.CylinderGeometry(0.028, 0.014, 0.75, 5);
      geo.rotateX(Math.PI / 2);
      return geo;
    }
    case 'fireball':
      return new THREE.IcosahedronGeometry(0.24, 1);
    case 'spark': {
      const geo = new THREE.CylinderGeometry(0.05, 0.05, 1.4, 4);
      geo.rotateX(Math.PI / 2);
      return geo;
    }
  }
}

function createMaterial(kind: ProjectileKind): THREE.Material {
  switch (kind) {
    case 'arrow':
      // 화살대는 빛을 받는 물체다 — 나무색으로 두면 배경에 묻히지 않는다
      return new THREE.MeshStandardMaterial({ color: 0x6b5540, roughness: 0.8 });
    case 'fireball':
      // 스스로 빛나는 것처럼 보여야 하므로 조명을 받지 않는 재질
      return new THREE.MeshBasicMaterial({ color: 0xff9a3c });
    case 'spark':
      return new THREE.MeshBasicMaterial({ color: 0x9fe6ff });
  }
}

export class Projectiles {
  readonly group = new THREE.Group();

  private readonly geometries = new Map<ProjectileKind, THREE.BufferGeometry>();
  private readonly materials = new Map<ProjectileKind, THREE.Material>();
  private readonly pool = new Map<ProjectileKind, THREE.Mesh[]>();
  private readonly active: Flying[] = [];

  constructor() {
    this.group.name = 'projectiles';
  }

  private take(kind: ProjectileKind): THREE.Mesh {
    const free = this.pool.get(kind);
    const reused = free?.pop();
    if (reused) {
      reused.visible = true;
      return reused;
    }

    let geo = this.geometries.get(kind);
    if (!geo) {
      geo = createGeometry(kind);
      this.geometries.set(kind, geo);
    }
    let mat = this.materials.get(kind);
    if (!mat) {
      mat = createMaterial(kind);
      this.materials.set(kind, mat);
    }

    const mesh = new THREE.Mesh(geo, mat);
    mesh.frustumCulled = false;
    this.group.add(mesh);
    return mesh;
  }

  private give(kind: ProjectileKind, mesh: THREE.Mesh): void {
    mesh.visible = false;
    const free = this.pool.get(kind);
    if (free) free.push(mesh);
    else this.pool.set(kind, [mesh]);
  }

  /**
   * from 에서 to 로 날린다. 도착하면 onArrive 가 불린다.
   * 대상이 도중에 사라질 수 있으므로 좌표는 여기서 복사해 둔다.
   */
  spawn(kind: ProjectileKind, from: THREE.Vector3, to: THREE.Vector3, onArrive: () => void): void {
    const start = from.clone();
    const end = to.clone();
    // 발밑이 아니라 몸통 높이에서 나가고, 몸통 높이에 맞는다
    start.y += 1.1;
    end.y += 0.8;

    const distance = start.distanceTo(end);
    const duration = Math.max(MIN_FLIGHT, distance / PROJECTILE_SPEED[kind]);

    const mesh = this.take(kind);
    mesh.position.copy(start);

    this.active.push({
      mesh,
      kind,
      from: start,
      to: end,
      t: 0,
      duration,
      // 멀리 쏠수록 더 크게 휜다
      arcHeight: kind === 'arrow' ? ARROW_ARC_HEIGHT * Math.min(1.6, distance / 8) : 0,
      onArrive,
    });
  }

  update(dt: number): void {
    for (let i = this.active.length - 1; i >= 0; i--) {
      const p = this.active[i]!;
      p.t += dt / p.duration;

      if (p.t >= 1) {
        this.give(p.kind, p.mesh);
        this.active.splice(i, 1);
        p.onArrive();
        continue;
      }

      const prevY = p.mesh.position.y;
      p.mesh.position.lerpVectors(p.from, p.to, p.t);
      // 포물선: 중간에서 가장 높다
      if (p.arcHeight > 0) p.mesh.position.y += Math.sin(p.t * Math.PI) * p.arcHeight;

      // 진행 방향을 바라보게 한다 (화살촉이 앞을 향하도록)
      const ahead = p.mesh.position.clone();
      ahead.sub(p.from).normalize();
      if (p.arcHeight > 0) {
        // 포물선이면 실제 이동 방향에 상하 성분이 섞인다
        ahead.y = (p.mesh.position.y - prevY) / Math.max(dt, 1e-4) * 0.05;
        ahead.normalize();
      }
      if (ahead.lengthSq() > 1e-6) {
        p.mesh.lookAt(p.mesh.position.clone().add(ahead));
      }

      if (p.kind === 'fireball') {
        const pulse = 1 + Math.sin(p.t * 40) * 0.12;
        p.mesh.scale.setScalar(pulse);
      }
    }
  }

  /** 존을 옮기면 날아가던 것들을 모두 없앤다 (콜백은 부르지 않는다) */
  clear(): void {
    for (const p of this.active) this.give(p.kind, p.mesh);
    this.active.length = 0;
  }

  dispose(): void {
    this.clear();
    for (const geo of this.geometries.values()) geo.dispose();
    for (const mat of this.materials.values()) mat.dispose();
    this.geometries.clear();
    this.materials.clear();
    this.pool.clear();
  }
}
