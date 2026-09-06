import * as THREE from 'three';
import type { SkillDef } from '@mmo/shared';

/**
 * 스킬 이펙트.
 *
 * 지금까지 스킬은 **투사체와 피해 숫자만** 있었다. 근접기와 자기 주위로 터지는
 * 기술은 아무것도 안 보여서, 눌렀는데 숫자만 뜨는 것처럼 느껴졌다.
 *
 * 여기서 하는 일은 전부 **보여주기**다. 판정은 이미 서버가 끝냈고 화면은
 * 그 결과를 설명할 뿐이라, 이펙트가 하나 빠져도 게임은 그대로 돌아간다.
 *
 * 조명을 받지 않는 재질(MeshBasicMaterial)을 쓴다. 스스로 빛나는 것처럼
 * 보여야 하고, 어두운 사냥터에서도 같은 밝기로 읽혀야 한다.
 *
 * 메시는 모양별로 풀에 넣고 재사용한다. 난전이 되면 초당 수십 개가 생기는데
 * 그때마다 지오메트리를 만들면 프레임이 튄다 — 투사체와 같은 이유다.
 */

/** 한 번에 살아 있을 수 있는 이펙트 수. 넘으면 가장 오래된 것부터 지운다 */
const MAX_LIVE = 48;

interface Effect {
  mesh: THREE.Mesh;
  material: THREE.MeshBasicMaterial;
  /** 0 → 1 */
  t: number;
  duration: number;
  /** 시작·끝 크기 */
  from: number;
  to: number;
  /** 시작·끝 높이 */
  yFrom: number;
  yTo: number;
  opacity: number;
  /** 바닥 고리는 눕혀 두고, 구는 그대로 둔다 */
  spin: number;
}

/** 스킬 하나의 색 — 투사체가 있으면 그것과 맞추고, 없으면 직업으로 정한다 */
export function skillColor(skill: SkillDef): number {
  if (skill.selfHeal) return 0x8ce87a;
  if (skill.projectile === 'fireball') return 0xff9a3c;
  if (skill.projectile === 'spark') return 0x9fe6ff;
  if (skill.projectile === 'arrow') return 0xd8e8a0;
  if (skill.job === 'mage') return 0xc39cff;
  if (skill.job === 'archer') return 0xbfe8a0;
  return 0xffd28a; // 기사 — 칼에 실린 빛
}

export class SkillFx {
  readonly group = new THREE.Group();

  /** 바닥에 눕는 고리 (시전·전방위·회복) */
  private readonly ringGeo: THREE.RingGeometry;
  /** 명중 섬광 */
  private readonly burstGeo: THREE.IcosahedronGeometry;

  private readonly live: Effect[] = [];
  private readonly pool: Effect[] = [];

  constructor() {
    this.group.name = 'skillFx';
    // 안쪽이 뚫린 고리. 꽉 찬 원은 캐릭터와 지면을 덮어버린다.
    this.ringGeo = new THREE.RingGeometry(0.78, 1, 48);
    this.ringGeo.rotateX(-Math.PI / 2);
    this.burstGeo = new THREE.IcosahedronGeometry(1, 1);
  }

  /** 스킬을 쓰는 순간 발밑에서 솟는 고리 */
  cast(at: THREE.Vector3, color: number): void {
    this.spawn(this.ringGeo, color, {
      duration: 0.42,
      from: 0.35,
      to: 1.15,
      yFrom: 0.05,
      yTo: 1.05,
      opacity: 0.75,
      spin: 0,
    });
    this.place(at);
  }

  /**
   * 자기 주위로 터지는 기술 — 사거리만큼 퍼지는 고리.
   *
   * 실제 판정 범위와 같은 크기로 그린다. 보여주기용이라도 크기가 다르면
   * "분명 닿았는데 안 맞았다"가 된다.
   */
  nova(at: THREE.Vector3, radius: number, color: number): void {
    this.spawn(this.ringGeo, color, {
      duration: 0.5,
      from: 0.15,
      to: radius,
      yFrom: 0.08,
      yTo: 0.35,
      opacity: 0.85,
      spin: 0,
    });
    this.place(at);
  }

  /** 맞은 자리의 짧은 섬광 */
  impact(at: THREE.Vector3, color: number): void {
    this.spawn(this.burstGeo, color, {
      duration: 0.24,
      from: 0.12,
      to: 0.62,
      yFrom: 0.9,
      yTo: 1.15,
      opacity: 0.9,
      spin: 6,
    });
    this.place(at);
  }

  /** 회복 — 몸을 감싸고 올라간다 */
  heal(at: THREE.Vector3, color: number): void {
    this.spawn(this.ringGeo, color, {
      duration: 0.7,
      from: 0.9,
      to: 0.45,
      yFrom: 0.05,
      yTo: 2.1,
      opacity: 0.8,
      spin: 0,
    });
    this.place(at);
  }

  private spawn(
    geo: THREE.BufferGeometry,
    color: number,
    spec: Omit<Effect, 'mesh' | 'material' | 't'>
  ): void {
    // 너무 많으면 가장 오래된 것부터 거둔다. 안 그러면 난전에서 화면이 하얘진다.
    while (this.live.length >= MAX_LIVE) this.retire(0);

    let fx = this.pool.pop();
    if (!fx) {
      const material = new THREE.MeshBasicMaterial({
        transparent: true,
        depthWrite: false,
        side: THREE.DoubleSide,
        // 겹칠수록 밝아진다 — 여러 개가 한 자리에서 터질 때 자연스럽다
        blending: THREE.AdditiveBlending,
      });
      const mesh = new THREE.Mesh(geo, material);
      mesh.frustumCulled = false;
      fx = { mesh, material, t: 0, ...spec };
    }

    fx.mesh.geometry = geo;
    fx.material.color.setHex(color);
    fx.material.opacity = spec.opacity;
    fx.t = 0;
    Object.assign(fx, spec);
    fx.mesh.visible = true;
    fx.mesh.rotation.y = Math.random() * Math.PI * 2;

    this.group.add(fx.mesh);
    this.live.push(fx);
  }

  /** 방금 만든 것의 자리를 잡는다 */
  private place(at: THREE.Vector3): void {
    const fx = this.live[this.live.length - 1];
    if (!fx) return;
    fx.mesh.position.set(at.x, at.y + fx.yFrom, at.z);
    fx.mesh.scale.setScalar(fx.from);
  }

  private retire(index: number): void {
    const fx = this.live[index];
    if (!fx) return;
    this.live.splice(index, 1);
    this.group.remove(fx.mesh);
    fx.mesh.visible = false;
    this.pool.push(fx);
  }

  update(dt: number): void {
    for (let i = this.live.length - 1; i >= 0; i--) {
      const fx = this.live[i]!;
      fx.t += dt / fx.duration;
      if (fx.t >= 1) {
        this.retire(i);
        continue;
      }

      // 처음엔 빠르게 퍼지고 끝에서 느려진다 (ease-out)
      const e = 1 - (1 - fx.t) * (1 - fx.t);
      fx.mesh.scale.setScalar(fx.from + (fx.to - fx.from) * e);
      fx.mesh.position.y += (fx.yTo - fx.yFrom) * (dt / fx.duration);
      if (fx.spin) fx.mesh.rotation.y += fx.spin * dt;
      // 끝으로 갈수록 사라진다. 처음부터 옅으면 터진 걸 못 본다.
      fx.material.opacity = fx.opacity * (1 - fx.t) * (1 - fx.t);
    }
  }

  /** 존을 옮기거나 오래 안 그렸을 때 — 남은 걸 붙잡고 있어봐야 거짓말이다 */
  clear(): void {
    for (let i = this.live.length - 1; i >= 0; i--) this.retire(i);
  }

  dispose(): void {
    this.clear();
    for (const fx of this.pool) fx.material.dispose();
    this.pool.length = 0;
    this.ringGeo.dispose();
    this.burstGeo.dispose();
  }
}
