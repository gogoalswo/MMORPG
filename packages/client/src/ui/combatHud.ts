import * as THREE from 'three';
import { expToNext } from '@mmo/shared';

/**
 * 전투 표시 — 떠오르는 피해 숫자와 하단 상태바.
 *
 * 피해 숫자는 3D 가 아니라 HTML 이다. 폰트가 또렷하고 드로우콜을 늘리지 않는다.
 * 대신 화면 좌표로 직접 투영해야 한다.
 */

interface FloatingNumber {
  el: HTMLDivElement;
  /** 숫자가 떠오르기 시작한 월드 위치 */
  origin: THREE.Vector3;
  age: number;
  /** 좌우로 흩어지는 정도 — 여러 대가 겹칠 때 숫자가 포개지지 않게 */
  drift: number;
}

const LIFETIME = 1.1;
const RISE = 1.6;

export class CombatHud {
  private readonly layer: HTMLDivElement;
  private readonly bar: HTMLDivElement;
  private readonly hpFill: HTMLElement;
  private readonly expFill: HTMLElement;
  private readonly levelText: HTMLElement;
  private readonly hpText: HTMLElement;

  private readonly numbers: FloatingNumber[] = [];
  private readonly projected = new THREE.Vector3();

  constructor(parent: HTMLElement) {
    this.layer = document.createElement('div');
    this.layer.className = 'damage-layer';

    this.bar = document.createElement('div');
    this.bar.className = 'status';
    this.bar.innerHTML = `
      <div class="status-level"></div>
      <div class="status-bars">
        <div class="status-track status-hp"><i></i><span></span></div>
        <div class="status-track status-exp"><i></i></div>
      </div>`;

    parent.append(this.layer, this.bar);

    this.hpFill = this.bar.querySelector('.status-hp > i') as HTMLElement;
    this.hpText = this.bar.querySelector('.status-hp > span') as HTMLElement;
    this.expFill = this.bar.querySelector('.status-exp > i') as HTMLElement;
    this.levelText = this.bar.querySelector('.status-level') as HTMLElement;
  }

  setVisible(visible: boolean): void {
    this.bar.classList.toggle('is-hidden', !visible);
  }

  setStatus(level: number, hp: number, maxHp: number, exp: number): void {
    this.levelText.textContent = `Lv.${level}`;
    this.hpFill.style.width = `${Math.max(0, (hp / Math.max(1, maxHp)) * 100)}%`;
    this.hpText.textContent = `${hp} / ${maxHp}`;
    const need = expToNext(level);
    this.expFill.style.width = `${Math.min(100, (exp / Math.max(1, need)) * 100)}%`;
  }

  /** kind 로 색이 갈린다: 내가 준 피해 / 내가 받은 피해 / 처치 */
  addNumber(
    world: THREE.Vector3,
    text: string,
    kind: 'deal' | 'take' | 'kill' | 'gain',
    crit = false
  ): void {
    const el = document.createElement('div');
    // 치명타는 색을 바꾸지 않고 키운다 — 색까지 바꾸면 처치와 헷갈린다
    el.className = `damage damage-${kind}${crit ? ' is-crit' : ''}`;
    el.textContent = text;
    this.layer.appendChild(el);
    this.numbers.push({
      el,
      origin: world.clone(),
      age: 0,
      drift: (Math.random() - 0.5) * 46,
    });
  }

  update(dt: number, camera: THREE.Camera, width: number, height: number): void {
    for (let i = this.numbers.length - 1; i >= 0; i--) {
      const n = this.numbers[i]!;
      n.age += dt;
      if (n.age >= LIFETIME) {
        n.el.remove();
        this.numbers.splice(i, 1);
        continue;
      }

      const t = n.age / LIFETIME;
      this.projected.copy(n.origin);
      // 위로 떠오르되 끝으로 갈수록 느려진다
      this.projected.y += RISE * (1 - (1 - t) * (1 - t));
      this.projected.project(camera);

      if (this.projected.z > 1) {
        n.el.style.opacity = '0';
        continue;
      }

      const sx = (this.projected.x * 0.5 + 0.5) * width + n.drift * t;
      const sy = (-this.projected.y * 0.5 + 0.5) * height;
      n.el.style.transform = `translate(-50%, -50%) translate(${sx.toFixed(1)}px, ${sy.toFixed(1)}px)`;
      n.el.style.opacity = String(t < 0.7 ? 1 : 1 - (t - 0.7) / 0.3);
    }
  }

  clear(): void {
    for (const n of this.numbers) n.el.remove();
    this.numbers.length = 0;
  }
}
