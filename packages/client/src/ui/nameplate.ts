import * as THREE from 'three';

/**
 * 머리 위 이름/HP바. 3D 텍스트가 아니라 HTML 오버레이다 —
 * 폰트가 항상 또렷하고 드로우콜을 늘리지 않는다.
 */
export interface NameplateTarget {
  object: THREE.Object3D;
  headHeight: number;
  name: string;
  /** 이름 아래 한 줄 — NPC 직함처럼 누구인지 알려줄 때 */
  subtitle?: string;
  hp: number;
  maxHp: number;
  /** 죽은 대상 등 일시적으로 감출 때 */
  hidden?: boolean;
  /** 지금 물고 있는 대상 — 이름표를 밝혀 어느 놈인지 보여준다 */
  highlight?: boolean;
}

const MAX_DISTANCE = 70;

export class NameplateLayer {
  private readonly entries: {
    target: NameplateTarget;
    el: HTMLDivElement;
    label: HTMLElement;
    bar: HTMLElement;
    shownName: string;
    shownHighlight: boolean;
  }[] = [];
  private readonly world = new THREE.Vector3();

  constructor(private readonly root: HTMLElement) {}

  add(target: NameplateTarget): void {
    const el = document.createElement('div');
    el.className = 'nameplate';
    el.innerHTML =
      `<div class="np-name"></div><div class="np-sub"></div><div class="np-hp"><i></i></div>`;
    const label = el.querySelector('.np-name') as HTMLElement;
    label.textContent = target.name;

    const sub = el.querySelector('.np-sub') as HTMLElement;
    // 직함이 없으면 줄 자체를 없앤다 — 빈 줄이 남으면 이름이 위로 뜬다
    if (target.subtitle) sub.textContent = target.subtitle;
    else sub.remove();
    const bar = el.querySelector('.np-hp > i') as HTMLElement;
    this.root.appendChild(el);
    this.entries.push({ target, el, label, bar, shownName: target.name, shownHighlight: false });
  }

  /** 관심영역 밖으로 나간 플레이어의 이름표를 뗀다 */
  remove(target: NameplateTarget): void {
    const i = this.entries.findIndex((e) => e.target === target);
    if (i < 0) return;
    this.entries[i]!.el.remove();
    this.entries.splice(i, 1);
  }

  /** 존이 바뀌면 이름표를 통째로 비운다 */
  clear(): void {
    for (const { el } of this.entries) el.remove();
    this.entries.length = 0;
  }

  update(camera: THREE.Camera, width: number, height: number): void {
    for (const entry of this.entries) {
      const { target, el, bar } = entry;
      target.object.getWorldPosition(this.world);
      this.world.y += target.headHeight;

      const dist = camera.position.distanceTo(this.world);
      this.world.project(camera);

      // 카메라 뒤 또는 너무 먼 대상은 숨긴다 (DOM 갱신 비용 절약)
      if (target.hidden || this.world.z > 1 || dist > MAX_DISTANCE) {
        if (el.style.display !== 'none') el.style.display = 'none';
        continue;
      }
      if (el.style.display === 'none') el.style.display = '';

      const sx = (this.world.x * 0.5 + 0.5) * width;
      const sy = (-this.world.y * 0.5 + 0.5) * height;
      el.style.transform = `translate(-50%, -100%) translate(${sx.toFixed(1)}px, ${sy.toFixed(1)}px)`;
      bar.style.width = `${(target.hp / target.maxHp) * 100}%`;

      // 이름은 거의 안 바뀌므로 달라졌을 때만 DOM 을 건드린다
      if (entry.shownName !== target.name) {
        entry.label.textContent = target.name;
        entry.shownName = target.name;
      }

      const highlight = target.highlight === true;
      if (entry.shownHighlight !== highlight) {
        el.classList.toggle('is-target', highlight);
        entry.shownHighlight = highlight;
      }
    }
  }
}
