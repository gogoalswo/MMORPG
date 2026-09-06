import {
  canEquip,
  describeOption,
  getItem,
  gradeMultiplier,
  slotLabel,
  type JobId,
  type NpcRole,
} from '@mmo/shared';
import { itemIcon } from './itemIcons';
import type { InventoryState } from '../net/connection';

/**
 * 마을 NPC 창 — 상점 / 전직.
 *
 * 둘을 한 창으로 묶은 이유는 하는 일이 "목록에서 하나 고르고 버튼을 누른다"로
 * 같기 때문이다.
 *
 * **대장간은 여기 없다.** 하는 일이 셋(제작·강화·등급)이고 목록이 길어서
 * 탭과 거르개가 필요했다 — `craftWindow.ts` 로 뗐다. `main.ts` 의 `onNpc` 가
 * role 로 갈라 보낸다.
 *
 * **여기 보이는 건 전부 안내다.** 살 수 있는지, 가까이 있는지, 그 직업이
 * 맞는지는 서버가 다시 본다.
 */

const TITLE: Record<NpcRole, string> = {
  shop: '상점',
  smith: '대장간',
  // 전직은 아직 넣지 않는다. 마을에 그 NPC 가 없어서 이 창은 열리지 않는다 —
  // 서버·클라 코드는 남겨두었으니 NPC 만 다시 세우면 살아난다.
  jobs: '전직',
};

const JOB_LABEL: Record<string, string> = {
  knight: '기사',
  mage: '마법사',
  archer: '궁수',
};

const JOB_DESC: Record<string, string> = {
  knight: '두꺼운 판금 갑옷과 방패. 앞에서 버틴다.',
  mage: '발목까지 오는 로브와 지팡이. 멀리서 큰 피해를 준다.',
  archer: '가벼운 가죽과 활. 거리를 유지하며 쏜다.',
};

export class NpcDialog {
  private readonly root: HTMLDivElement;
  private readonly titleEl: HTMLElement;
  private readonly goldEl: HTMLElement;
  private readonly bodyEl: HTMLElement;

  private role: NpcRole = 'shop';
  private stock: string[] = [];
  private jobs: string[] = [];
  private inventory: InventoryState = { gold: 0, items: [], equipment: {} };
  private job: JobId = 'knight';
  private level = 1;

  onBuy: ((itemId: string) => void) | null = null;
  onSell: ((index: number) => void) | null = null;
  onJob: ((job: string) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'npc is-hidden';
    this.root.innerHTML = `
      <div class="npc-head">
        <span class="npc-title">상점</span>
        <span class="npc-gold">0 G</span>
        <button type="button" class="npc-close">✕</button>
      </div>
      <div class="npc-body"></div>`;

    this.titleEl = this.root.querySelector('.npc-title') as HTMLElement;
    this.goldEl = this.root.querySelector('.npc-gold') as HTMLElement;
    this.bodyEl = this.root.querySelector('.npc-body') as HTMLElement;

    (this.root.querySelector('.npc-close') as HTMLElement).addEventListener('click', () =>
      this.close()
    );
    parent.appendChild(this.root);
  }

  get open(): boolean {
    return !this.root.classList.contains('is-hidden');
  }

  close(): void {
    this.root.classList.add('is-hidden');
  }

  setCharacter(job: JobId, level: number): void {
    this.job = job;
    this.level = level;
    if (this.open) this.render();
  }

  setInventory(state: InventoryState): void {
    this.inventory = state;
    if (this.open) this.render();
  }

  show(role: NpcRole, stock: string[], jobs: string[]): void {
    this.role = role;
    this.stock = stock;
    this.jobs = jobs;
    this.root.classList.remove('is-hidden');
    this.render();
  }

  private render(): void {
    this.titleEl.textContent = TITLE[this.role];
    this.goldEl.textContent = `${this.inventory.gold.toLocaleString()} G`;
    this.bodyEl.replaceChildren();

    // 대장간(smith)은 이 창으로 오지 않는다 — main.ts 가 제작창으로 보낸다
    if (this.role === 'shop') this.renderShop();
    else this.renderJobs();
  }

  /** 목록 한 줄 */
  private row(icon: string, name: string, meta: string): HTMLDivElement {
    const row = document.createElement('div');
    row.className = 'npc-row';
    row.innerHTML =
      `<span class="npc-row-icon">${icon}</span>` +
      `<span class="npc-row-text"><b>${name}</b><small>${meta}</small></span>`;
    return row;
  }

  private button(label: string, sub: string, enabled: boolean, onClick: () => void): HTMLButtonElement {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'npc-btn' + (enabled ? '' : ' is-locked');
    b.innerHTML = `<span>${label}</span>${sub ? `<small>${sub}</small>` : ''}`;
    if (enabled) b.addEventListener('click', onClick);
    return b;
  }

  private section(label: string): HTMLElement {
    const h = document.createElement('div');
    h.className = 'npc-section';
    h.textContent = label;
    this.bodyEl.appendChild(h);
    return h;
  }

  private renderShop(): void {
    this.section('살 물건');
    if (this.stock.length === 0) {
      this.empty('지금 살 수 있는 게 없습니다.');
    }
    for (const id of this.stock) {
      const item = getItem(id);
      if (!item) continue;
      const row = this.row(
        itemIcon(item, 1),
        item.name,
        `${slotLabel(item.slot!, this.job)} · Lv.${item.level} · 1등급 · 옵션 1~3개 무작위`
      );
      row.appendChild(
        this.button('구입', `${item.price} G`, this.inventory.gold >= item.price, () => this.onBuy?.(id))
      );
      this.bodyEl.appendChild(row);
    }

    this.section('팔 물건');
    let sellable = 0;
    this.inventory.items.forEach((stack, index) => {
      const item = getItem(stack.id);
      if (!item) return;
      sellable++;
      // 등급이 높으면 더 쳐준다 (서버와 같은 식)
      const price = Math.max(1, Math.round(item.price * 0.4 * gradeMultiplier(stack.grade)));
      const options = (stack.options ?? []).map(describeOption).join(' · ');
      const row = this.row(
        itemIcon(item, stack.grade),
        item.name,
        item.material
          ? '제작 재료'
          : `${slotLabel(item.slot!, this.job)} · ${stack.grade}등급${options ? ` · ${options}` : ''}`
      );
      row.appendChild(this.button('판매', `${price} G`, true, () => this.onSell?.(index)));
      this.bodyEl.appendChild(row);
    });
    if (sellable === 0) this.empty('가방이 비어 있습니다.');
  }

  private renderJobs(): void {
    this.section('직업 바꾸기');

    const warn = document.createElement('div');
    warn.className = 'npc-warn';
    warn.textContent = '전직하면 무기와 보조 장비는 가방으로 돌아갑니다.';
    this.bodyEl.appendChild(warn);

    for (const job of this.jobs) {
      const current = job === this.job;
      const row = this.row('', JOB_LABEL[job] ?? job, JOB_DESC[job] ?? '');
      row.classList.add('npc-row-job');
      row.appendChild(
        this.button(current ? '현재 직업' : '전직', '', !current, () => this.onJob?.(job))
      );
      this.bodyEl.appendChild(row);
    }
  }

  private empty(text: string): void {
    const el = document.createElement('div');
    el.className = 'npc-empty';
    el.textContent = text;
    this.bodyEl.appendChild(el);
  }

  /** 착용 가능 여부는 상점에서 회색 처리에만 쓴다 */
  canUse(itemId: string): boolean {
    const item = getItem(itemId);
    return item ? canEquip(item, this.job, this.level) : false;
  }
}
