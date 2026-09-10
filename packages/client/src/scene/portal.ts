import * as THREE from 'three';
import type { PortalVisual } from '@mmo/shared';

/**
 * 차원문. 바닥의 빛나는 고리와 위로 솟는 빛기둥으로 표시한다.
 *
 * 진입 판정에 armed 플래그가 중요하다. 없으면 문 위에 서 있는 내내 매 프레임
 * 발동해서, 창을 닫아도 곧바로 다시 열린다. 그래서 "반경 밖으로 한 번 나간
 * 뒤"부터 발동하게 한다.
 */
export interface Portal<D extends PortalVisual = PortalVisual> {
  def: D;
  group: THREE.Group;
  update(elapsed: number): void;
  /** 플레이어가 진입했는지. 발동하면 true 를 한 번만 돌려준다 */
  test(x: number, z: number): boolean;
  dispose(): void;
}

/**
 * 정의를 그대로 돌려주도록 제네릭으로 둔다. 부르는 쪽이 `def.name` 같은
 * 제 필드를 그대로 읽을 수 있어야 한다. 그리는 데 필요한 건 위치·반경·색뿐이다.
 */
export function createPortal<D extends PortalVisual>(def: D): Portal<D> {
  const group = new THREE.Group();
  group.position.set(def.position[0], 0, def.position[1]);

  const color = new THREE.Color(def.color);
  const disposables: { dispose(): void }[] = [];

  const track = <T extends THREE.BufferGeometry | THREE.Material>(x: T): T => {
    disposables.push(x);
    return x;
  };

  // 바닥 고리
  const ringGeo = track(new THREE.TorusGeometry(def.radius, 0.13, 6, 28));
  ringGeo.rotateX(Math.PI / 2);
  const ringMat = track(new THREE.MeshBasicMaterial({ color }));
  const ring = new THREE.Mesh(ringGeo, ringMat);
  ring.position.y = 0.06;
  group.add(ring);

  // 안쪽 원반 — 반투명하게 깔아 진입 범위를 알려준다
  const discGeo = track(new THREE.CircleGeometry(def.radius * 0.94, 24));
  discGeo.rotateX(-Math.PI / 2);
  const discMat = track(
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.16, depthWrite: false })
  );
  const disc = new THREE.Mesh(discGeo, discMat);
  disc.position.y = 0.04;
  group.add(disc);

  // 빛기둥
  const columnGeo = track(
    new THREE.CylinderGeometry(def.radius * 0.72, def.radius * 0.86, 5.5, 16, 1, true)
  );
  const columnMat = track(
    new THREE.MeshBasicMaterial({
      color,
      transparent: true,
      opacity: 0.2,
      side: THREE.DoubleSide,
      depthWrite: false,
    })
  );
  const column = new THREE.Mesh(columnGeo, columnMat);
  column.position.y = 2.75;
  group.add(column);

  // 회전하는 룬 조각들
  const shardGeo = track(new THREE.TetrahedronGeometry(0.16));
  const shardMat = track(new THREE.MeshBasicMaterial({ color }));
  const shards: THREE.Mesh[] = [];
  for (let i = 0; i < 5; i++) {
    const shard = new THREE.Mesh(shardGeo, shardMat);
    const a = (i / 5) * Math.PI * 2;
    shard.position.set(Math.cos(a) * def.radius * 0.8, 0.7 + i * 0.22, Math.sin(a) * def.radius * 0.8);
    group.add(shard);
    shards.push(shard);
  }

  // 문 위에 서 있는 내내 다시 열리는 걸 막는다 — 반경을 한 번 벗어나야 발동한다
  let armed = false;
  const r2 = def.radius * def.radius;

  return {
    def,
    group,

    update(elapsed: number): void {
      ring.rotation.y = elapsed * 0.5;
      const pulse = 0.85 + Math.sin(elapsed * 2.2) * 0.15;
      ring.scale.set(pulse, 1, pulse);
      columnMat.opacity = 0.14 + Math.sin(elapsed * 1.7) * 0.06;
      for (let i = 0; i < shards.length; i++) {
        const shard = shards[i]!;
        const a = (i / shards.length) * Math.PI * 2 + elapsed * 0.7;
        shard.position.x = Math.cos(a) * def.radius * 0.8;
        shard.position.z = Math.sin(a) * def.radius * 0.8;
        shard.position.y = 0.7 + i * 0.22 + Math.sin(elapsed * 1.6 + i) * 0.12;
        shard.rotation.y = elapsed * 1.4;
        shard.rotation.x = elapsed * 0.9;
      }
    },

    test(x: number, z: number): boolean {
      const dx = x - def.position[0];
      const dz = z - def.position[1];
      const inside = dx * dx + dz * dz <= r2;
      if (!inside) {
        armed = true;
        return false;
      }
      if (!armed) return false;
      armed = false;
      return true;
    },

    dispose(): void {
      for (const d of disposables) d.dispose();
    },
  };
}
