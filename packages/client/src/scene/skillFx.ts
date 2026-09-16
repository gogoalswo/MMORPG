import * as THREE from 'three';
import type { SkillDef } from '@mmo/shared';

/**
 * 피격 표시와 스킬 색.
 *
 * 원래 여기에 스킬 이펙트가 전부 있었다 — 시전 고리(`cast`) · 전방위 고리(`nova`) ·
 * 명중 섬광(`impact`) · 회복 고리(`heal`) 와 스킬별 그림(할퀸 자국 · 호포각 ·
 * 백호격 · 천붕각 · 주먹). **고도 엔진으로 이관하면서 새로 그리기로 해서
 * 2026-09-16 에 걷어냈다.** 지운 것은 git 이력에 그대로 있다.
 *
 * 남긴 것은 둘뿐이고, 둘 다 스킬 이펙트가 아니라서 남았다.
 *
 * - `hurt` — 캐릭터가 맞은 자리에 뜨는 발톱 자국. **피격 표시**라 기본 공격에도
 *   뜬다 ([combat.md](../../../../docs/features/combat.md)). 같이 지우면 몸이
 *   잠깐 하얘지는 것 말고는 맞았다는 표시가 없어진다.
 * - `skillColor` — 투사체 궤적(`trailFor`)이 아직 쓴다. 스킬을 쓰면 궤적이 그
 *   스킬 색으로 남아서 기본 공격과 구별된다.
 *
 * 여기서 하는 일은 전부 **보여주기**다. 판정은 이미 서버가 끝냈고 화면은 그
 * 결과를 설명할 뿐이라, 이게 빠져도 게임은 그대로 돌아간다.
 */

/** 한 번에 살아 있을 수 있는 수. 넘으면 가장 오래된 것부터 지운다 */
const MAX_LIVE = 48;

const HIT_URL = `${import.meta.env.BASE_URL}assets/fx/hit.png`;

/**
 * 맞았을 때 뜨는 발톱 자국.
 *
 * 몸이 잠깐 하얘지는 것은 "누가 맞았나" 를 알려 주고, 이쪽은 "맞았다" 를 알려 준다.
 * 둘 중 하나만으로는 난전에서 잘 안 읽혔다.
 *
 * 짧고 작다. 몬스터는 1초에 한 번쯤 때리는데 여럿에게 둘러싸이면 그만큼 겹치므로,
 * 크게 키우면 화면이 붉게 덮인다.
 */
const HURT = {
  /** 몸 어디에 뜨는가 (m) — 가슴께 */
  height: 1.2,
  /** 시작·끝 크기 (m) — 캐릭터(1.8m)보다 작아야 몸이 안 가려진다 */
  sizeFrom: 0.7,
  sizeTo: 1.5,
  /** 떠 있는 시간 (초) */
  duration: 0.3,
  /** 맞은 자리에서 흩어지는 폭 (m) — 같은 자리에 겹쳐 뜨면 한 장처럼 보인다 */
  spread: 0.35,
};

/**
 * 떠 있는 그림 한 장. 스프라이트라 늘 카메라를 본다.
 *
 * 고리·섬광 같은 **메시** 이펙트가 있던 동안은 여기에 `spin` · `vx/vz` · `ease` ·
 * `flipX` 같은 것이 같이 있었다. 남은 게 발톱 자국 하나뿐이라 쓰지 않는 것은
 * 다 걷어냈다 — 새로 넣을 때 필요한 만큼만 다시 만드는 편이 낫다.
 */
interface Effect {
  mesh: THREE.Sprite;
  material: THREE.SpriteMaterial;
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
  /** 뜬 자리의 지면 높이 — 높이를 매 프레임 누적하지 않고 여기서 다시 잡는다 */
  baseY: number;
}

/**
 * 스킬 하나의 색 — 투사체가 있으면 그것과 맞추고, 없으면 직업으로 정한다.
 *
 * 지금 쓰는 곳은 투사체 궤적 하나뿐이다. 그림이 있던 스킬(호포각 · 천붕각 ·
 * 백호격)의 색도 그대로 두었다 — 궤적은 스킬을 쓸 때마다 남으므로 이 셋도
 * 여전히 여기를 지나간다.
 */
export function skillColor(skill: SkillDef): number {
  if (skill.selfHeal) return 0x8ce87a;
  if (skill.id === 'tiger_roar') return 0x8fd0ff; // 호포각 — 푸른 기운
  if (skill.id === 'sky_breaker') return 0xffc23c; // 천붕각 — 진한 금빛
  if (skill.id === 'white_tiger') return 0xffffff; // 백호 — 흰빛 그대로
  if (skill.projectile === 'fireball') return 0xff9a3c;
  if (skill.projectile === 'spark') return 0x9fe6ff;
  if (skill.projectile === 'arrow') return 0xd8e8a0;
  if (skill.job === 'mage') return 0xc39cff;
  if (skill.job === 'archer') return 0xbfe8a0;
  if (skill.job === 'fighter') return 0xcfe8ff; // 주먹에 모인 기
  return 0xffd28a; // 기사 — 칼에 실린 빛
}

export class SkillFx {
  readonly group = new THREE.Group();

  private readonly live: Effect[] = [];
  private readonly pool: Effect[] = [];
  private readonly textures = new Map<string, THREE.Texture>();

  constructor() {
    this.group.name = 'skillFx';
    // 음영(GTAO) 계산에서 뺀다 — 안 빼면 스프라이트가 까만 판자로 그려진다 (postfx.ts)
    this.group.userData.noAO = true;
  }

  /**
   * 맞았을 때 — 그 자리에서 터지는 발톱 자국 (`HURT`, `public/assets/fx/hit.png`).
   *
   * **캐릭터가 맞은 자리에만 쓴다.** 몬스터가 맞을 때도 띄우면 사냥 내내 화면이
   * 번쩍이고, 그건 예전에 한 번 걷어낸 길이다. 맞는 쪽이 나(또는 옆 사람)일 때만
   * 나오므로 빈도가 훨씬 낮다.
   *
   * 그림이 이미 붉어서 색을 섞지 않는다 — 물들이면 붉은색이 두 번 먹어 죽는다.
   */
  hurt(at: THREE.Vector3): void {
    this.spawn(HIT_URL, 0xffffff, {
      duration: HURT.duration,
      from: HURT.sizeFrom,
      to: HURT.sizeTo,
      yFrom: HURT.height,
      yTo: HURT.height + 0.15,
      opacity: 1,
    });
    this.place(at);
    const fx = this.live[this.live.length - 1]!;
    // 연달아 맞을 때 같은 자리에 포개지지 않게 흩어 놓는다
    fx.mesh.position.x += (Math.random() - 0.5) * HURT.spread;
    fx.mesh.position.z += (Math.random() - 0.5) * HURT.spread;
    fx.material.rotation = Math.random() * Math.PI * 2;
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
      const size = fx.from + (fx.to - fx.from) * e;
      fx.mesh.scale.set(size, size, size);
      // 높이는 매 프레임 더하지 않고 시작점에서 다시 잡는다 — 곡선을 바꿔도 어긋나지 않는다
      fx.mesh.position.y = fx.baseY + fx.yFrom + (fx.yTo - fx.yFrom) * e;
      /**
       * 밝기 곡선 ★
       *
       * 예전에는 `opacity * (1-t)²` 였다. 그런데 크기는 `t` 를 따라 **커지므로**,
       * 가장 커지는 순간이 가장 투명한 순간과 겹쳤다. 카메라가 멀어서(거리 40)
       * 작을 때는 몇 픽셀뿐이라, 결국 어느 프레임에도 눈에 걸리는 그림이 없었다 —
       * 실제로 재보니 최대 밝기가 765 중 15~22 였다. "이펙트가 안 나온다" 가
       * 이것이다.
       *
       * 그래서 **빠르게 켜고, 커져 있는 동안 유지하다가, 끝에서 끈다.**
       * 새로 이펙트를 만들 때도 같은 함정을 밟지 않도록 여기 남겨 둔다.
       */
      const rise = Math.min(1, fx.t / 0.12);
      const fall = Math.min(1, (1 - fx.t) / 0.45);
      fx.material.opacity = fx.opacity * rise * fall;
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
    for (const tex of this.textures.values()) tex.dispose();
    this.textures.clear();
  }

  private spawn(
    url: string,
    color: number,
    spec: Omit<Effect, 'mesh' | 'material' | 't' | 'baseY'>
  ): void {
    // 너무 많으면 가장 오래된 것부터 거둔다. 안 그러면 난전에서 화면이 하얘진다.
    while (this.live.length >= MAX_LIVE) this.retire(0);

    let fx = this.pool.pop();
    if (!fx) {
      /**
       * 그림은 맞은 몸 한가운데(높이 1m 안팎)에서 터진다. 깊이 검사를 켜 두면 몸통
       * 앞쪽이 그림을 가린다 — 초원 오우거는 키가 2.2m 가 넘어 절반 넘게 먹혔다.
       * 몸 위에 그린다. 가산 혼합이라 겹칠수록 밝아진다.
       */
      const material = new THREE.SpriteMaterial({
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        map: this.texture(url),
        depthTest: false,
      });
      fx = { mesh: new THREE.Sprite(material), material, t: 0, baseY: 0, ...spec };
      fx.mesh.renderOrder = 10;
      fx.mesh.frustumCulled = false;
    }

    // 풀에서 꺼낸 것이라 매번 정해 준다 — 안 그러면 앞에 쓰던 설정이 남는다
    fx.material.map = this.texture(url);
    fx.material.rotation = 0;
    fx.material.color.setHex(color);
    fx.material.opacity = spec.opacity;
    Object.assign(fx, spec);
    fx.t = 0;
    fx.mesh.visible = true;

    this.group.add(fx.mesh);
    this.live.push(fx);
  }

  /** 방금 만든 것의 자리를 잡는다 */
  private place(at: THREE.Vector3): void {
    const fx = this.live[this.live.length - 1];
    if (!fx) return;
    fx.baseY = at.y;
    fx.mesh.position.set(at.x, at.y + fx.yFrom, at.z);
    fx.mesh.scale.set(fx.from, fx.from, fx.from);
  }

  /** 그림은 처음 쓸 때 받는다 */
  private texture(url: string): THREE.Texture {
    let tex = this.textures.get(url);
    if (!tex) {
      tex = new THREE.TextureLoader().load(url);
      tex.colorSpace = THREE.SRGBColorSpace;
      this.textures.set(url, tex);
    }
    return tex;
  }

  private retire(index: number): void {
    const fx = this.live[index];
    if (!fx) return;
    this.live.splice(index, 1);
    this.group.remove(fx.mesh);
    fx.mesh.visible = false;
    this.pool.push(fx);
  }
}
