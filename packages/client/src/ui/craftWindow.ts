import {
  EQUIP_SLOTS,
  GRADE_MAX,
  MAX_ENHANCE,
  TIER_COUNT,
  canEnhance,
  craftRequirement,
  enhanceCost,
  enhanceOdds,
  forgeRecipe,
  getItem,
  materialIdFor,
  slotLabel,
  tierForLevel,
  tierName,
  type EquipSlot,
  type ItemStack,
  type JobId,
} from '@mmo/shared';
import { itemIcon } from './itemIcons';
import type { InventoryState } from '../net/connection';

/**
 * 제작창 — 대장간에서 열린다.
 *
 * 하는 일 셋(**새로 만들기 / 강화 / 등급 올리기**)은 원래 NPC 창 하나에 위아래로
 * 쌓여 있었다. 그런데 `forgeableFor` 가 "내 직업 · 내 레벨 이하" 를 전부 돌려주기
 * 때문에 200레벨이면 새로 만들기 목록에만 180줄이 넘게 깔리고, 그 아래로 강화와
 * 등급 올리기가 이어 붙어서 원하는 자리를 찾을 수가 없었다. 그래서 이 창으로
 * 떼어내고 **탭 + 거르개**를 붙였다.
 *
 * **규칙은 하나도 바꾸지 않았다.** 재료 수·확률·옵션 굴림은 전부 서버가 하던
 * 그대로고, 여기서 보내는 메시지도 원래 쓰던 `npcForge` / `npcEnhance` / `craft`
 * 셋 그대로다. 이 창에 보이는 "가능/불가"는 전부 **안내일 뿐**이고, 가까이 있는지·
 * 재료가 있는지·골드가 되는지는 서버가 다시 본다.
 */

type Tab = 'forge' | 'enhance' | 'grade';

const TAB_LABEL: Record<Tab, string> = {
  forge: '새로 만들기',
  enhance: '강화',
  grade: '등급 올리기',
};

/** 거르개를 다음에도 그대로 쓴다 — 열 때마다 다시 고르는 게 이 창을 만든 이유다 */
const FILTER_KEY = 'mmo.craftFilter';

interface Filter {
  tab: Tab;
  slot: EquipSlot | 'all';
  tier: number | 'all';
  /** 지금 가진 재료로 만들 수 있는 것만 */
  readyOnly: boolean;
}

const DEFAULT_FILTER: Filter = {
  tab: 'forge',
  slot: 'all',
  tier: 'all',
  // 재료는 보스만 떨군다. 켜 두면 "실제로 지금 만들 수 있는 것" 만 남아서
  // 180줄이 대개 한 자릿수로 줄어든다. 끄면 전체 목록이 나온다.
  readyOnly: true,
};

function readFilter(): Filter {
  try {
    const raw = JSON.parse(localStorage.getItem(FILTER_KEY) ?? '');
    return {
      tab: TAB_LABEL[raw?.tab as Tab] ? (raw.tab as Tab) : DEFAULT_FILTER.tab,
      slot: raw?.slot === 'all' || EQUIP_SLOTS.includes(raw?.slot) ? raw.slot : DEFAULT_FILTER.slot,
      tier:
        raw?.tier === 'all' || (Number.isInteger(raw?.tier) && raw.tier >= 0 && raw.tier < TIER_COUNT)
          ? raw.tier
          : DEFAULT_FILTER.tier,
      readyOnly: typeof raw?.readyOnly === 'boolean' ? raw.readyOnly : DEFAULT_FILTER.readyOnly,
    };
  } catch {
    return { ...DEFAULT_FILTER };
  }
}

const pct = (v: number): string => `${Math.round(v * 100)}%`;

export class CraftWindow {
  private readonly root: HTMLDivElement;
  private readonly goldEl: HTMLElement;
  private readonly tabsEl: HTMLElement;
  private readonly filterEl: HTMLElement;
  private readonly bodyEl: HTMLElement;
  private readonly countEl: HTMLElement;

  private readonly tabButtons = new Map<Tab, HTMLButtonElement>();

  /** 서버가 알려준, 이 캐릭터가 만들 수 있는 것 목록 */
  private forgeable: string[] = [];
  private inventory: InventoryState = { gold: 0, items: [], equipment: {} };
  private job: JobId = 'knight';
  private filter: Filter = readFilter();

  /** 새로 만들기 — 아이템 id */
  onForge: ((itemId: string) => void) | null = null;
  /** 강화 — 가방 칸 번호 */
  onEnhance: ((index: number) => void) | null = null;
  /** 등급 올리기 — 가방 칸 번호 */
  onGrade: ((index: number) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'craft is-hidden';
    this.root.innerHTML = `
      <div class="craft-head">
        <span class="craft-title">대장간</span>
        <span class="craft-gold">0 G</span>
        <button type="button" class="craft-close" aria-label="닫기">✕</button>
      </div>
      <div class="craft-tabs"></div>
      <div class="craft-filter"></div>
      <div class="craft-body"></div>
      <div class="craft-count"></div>`;

    this.goldEl = this.root.querySelector('.craft-gold') as HTMLElement;
    this.tabsEl = this.root.querySelector('.craft-tabs') as HTMLElement;
    this.filterEl = this.root.querySelector('.craft-filter') as HTMLElement;
    this.bodyEl = this.root.querySelector('.craft-body') as HTMLElement;
    this.countEl = this.root.querySelector('.craft-count') as HTMLElement;

    for (const tab of Object.keys(TAB_LABEL) as Tab[]) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'craft-tab';
      b.textContent = TAB_LABEL[tab];
      b.addEventListener('click', () => {
        this.filter.tab = tab;
        this.saveFilter();
        this.render();
      });
      this.tabsEl.appendChild(b);
      this.tabButtons.set(tab, b);
    }

    (this.root.querySelector('.craft-close') as HTMLElement).addEventListener('click', () =>
      this.close()
    );

    // 창 위에서 누른 것이 3D 로 새어 나가면 대장간에서 캐릭터가 걸어다닌다
    for (const type of ['pointerdown', 'pointermove', 'pointerup', 'wheel']) {
      this.root.addEventListener(type, (e) => e.stopPropagation());
    }

    parent.appendChild(this.root);
  }

  get open(): boolean {
    return !this.root.classList.contains('is-hidden');
  }

  close(): void {
    this.root.classList.add('is-hidden');
  }

  show(forgeable: string[]): void {
    this.forgeable = forgeable;
    this.root.classList.remove('is-hidden');
    this.render();
  }

  setCharacter(job: JobId): void {
    this.job = job;
    if (this.open) this.render();
  }

  /** 서버가 가방을 다시 보낼 때마다 불린다 (제작·강화 결과가 여기로 온다) */
  setInventory(state: InventoryState): void {
    this.inventory = state;
    if (this.open) this.render();
  }

  private saveFilter(): void {
    try {
      localStorage.setItem(FILTER_KEY, JSON.stringify(this.filter));
    } catch {
      /* 저장이 막혀도 이번 판은 유지된다 */
    }
  }

  /** 가방에 든 개수 — 재료가 몇 개인지 세는 데 쓴다 */
  private countById(): Map<string, number> {
    const owned = new Map<string, number>();
    for (const stack of this.inventory.items) {
      owned.set(stack.id, (owned.get(stack.id) ?? 0) + 1);
    }
    return owned;
  }

  private render(): void {
    this.goldEl.textContent = `${this.inventory.gold.toLocaleString()} G`;
    for (const [tab, button] of this.tabButtons) {
      button.classList.toggle('is-on', tab === this.filter.tab);
    }

    this.filterEl.replaceChildren();
    this.bodyEl.replaceChildren();
    this.countEl.textContent = '';

    if (this.filter.tab === 'forge') this.renderForge();
    else if (this.filter.tab === 'enhance') this.renderEnhance();
    else this.renderGrade();
  }

  // ------------------------------------------------------------ 조각들

  private row(icon: string, name: string, meta: string): HTMLDivElement {
    const row = document.createElement('div');
    row.className = 'craft-row';
    row.innerHTML =
      `<span class="craft-row-icon">${icon}</span>` +
      `<span class="craft-row-text"><b>${name}</b><small>${meta}</small></span>`;
    return row;
  }

  private button(
    label: string,
    sub: string,
    enabled: boolean,
    onClick: () => void
  ): HTMLButtonElement {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'craft-btn' + (enabled ? '' : ' is-locked');
    b.innerHTML = `<span>${label}</span>${sub ? `<small>${sub}</small>` : ''}`;
    if (enabled) b.addEventListener('click', onClick);
    return b;
  }

  private empty(text: string): void {
    const el = document.createElement('div');
    el.className = 'craft-empty';
    el.textContent = text;
    this.bodyEl.appendChild(el);
  }

  private select<T extends string | number>(
    label: string,
    options: { value: T; label: string }[],
    current: T,
    onPick: (value: T) => void
  ): HTMLLabelElement {
    const wrap = document.createElement('label');
    wrap.className = 'craft-pick';
    wrap.innerHTML = `<span>${label}</span>`;
    const sel = document.createElement('select');
    for (const o of options) {
      const opt = document.createElement('option');
      opt.value = String(o.value);
      opt.textContent = o.label;
      if (o.value === current) opt.selected = true;
      sel.appendChild(opt);
    }
    sel.addEventListener('change', () => {
      const raw = sel.value;
      onPick((raw === 'all' ? 'all' : (Number.isNaN(Number(raw)) ? raw : Number(raw))) as T);
    });
    wrap.appendChild(sel);
    return wrap;
  }

  // ------------------------------------------------------------ 새로 만들기

  /**
   * 가진 재료를 한 줄로 보여준다.
   *
   * 0개인 단계는 빼고 적는다 — 20단계를 전부 적으면 그 줄이 화면 절반을
   * 차지하면서 "지금 뭘 만들 수 있나"는 오히려 안 보인다.
   */
  private materialStrip(owned: Map<string, number>): HTMLElement | null {
    const held: string[] = [];
    for (let tier = 0; tier < TIER_COUNT; tier++) {
      const count = owned.get(materialIdFor(tier)) ?? 0;
      if (count > 0) held.push(`<b>${tierName(tier)}</b> ${count}`);
    }
    if (held.length === 0) return null;

    const el = document.createElement('div');
    el.className = 'craft-mats';
    el.innerHTML = `<span class="craft-mats-label">가진 재료</span>${held.join('<i>·</i>')}`;
    return el;
  }

  private renderForge(): void {
    const owned = this.countById();

    // --- 거르개 ---
    const slots: { value: EquipSlot | 'all'; label: string }[] = [
      { value: 'all', label: '전체' },
      ...EQUIP_SLOTS.map((s) => ({ value: s, label: slotLabel(s, this.job) })),
    ];
    // 단계는 만들 수 있는 것에 실제로 있는 것만 고르게 한다.
    // 20개를 다 늘어놓으면 대부분이 빈 목록으로 이어진다.
    const tiersPresent = new Set<number>();
    for (const id of this.forgeable) {
      const item = getItem(id);
      if (item) tiersPresent.add(tierForLevel(item.level));
    }
    const tiers: { value: number | 'all'; label: string }[] = [
      { value: 'all', label: '전체' },
      ...[...tiersPresent]
        .sort((a, b) => b - a)
        .map((t) => ({ value: t, label: `${tierName(t)} (Lv.${t === 0 ? 1 : t * 10})` })),
    ];

    this.filterEl.appendChild(
      this.select('슬롯', slots, this.filter.slot, (v) => {
        this.filter.slot = v;
        this.saveFilter();
        this.render();
      })
    );
    this.filterEl.appendChild(
      this.select('단계', tiers, this.filter.tier, (v) => {
        this.filter.tier = v;
        this.saveFilter();
        this.render();
      })
    );

    const ready = document.createElement('label');
    ready.className = 'craft-toggle';
    ready.innerHTML = `<input type="checkbox"${this.filter.readyOnly ? ' checked' : ''}><span>만들 수 있는 것만</span>`;
    (ready.querySelector('input') as HTMLInputElement).addEventListener('change', (e) => {
      this.filter.readyOnly = (e.target as HTMLInputElement).checked;
      this.saveFilter();
      this.render();
    });
    this.filterEl.appendChild(ready);

    const strip = this.materialStrip(owned);
    if (strip) this.filterEl.appendChild(strip);

    // --- 목록 ---
    // 높은 단계가 위로 온다. 낮은 단계는 이미 지나온 자리라 찾을 일이 드물다.
    const rows = this.forgeable
      .map((id) => ({ id, item: getItem(id) }))
      .filter((e): e is { id: string; item: NonNullable<ReturnType<typeof getItem>> } => !!e.item)
      .sort((a, b) => b.item.level - a.item.level || a.item.slot!.localeCompare(b.item.slot!));

    let shown = 0;
    for (const { id, item } of rows) {
      if (this.filter.slot !== 'all' && item.slot !== this.filter.slot) continue;
      if (this.filter.tier !== 'all' && tierForLevel(item.level) !== this.filter.tier) continue;

      const recipe = forgeRecipe(item);
      if (!recipe) continue;

      const have = owned.get(recipe.materialId) ?? 0;
      const enough = have >= recipe.materialCount && this.inventory.gold >= recipe.gold;
      if (this.filter.readyOnly && !enough) continue;

      const row = this.row(
        itemIcon(item, 1),
        item.name,
        `${slotLabel(item.slot!, this.job)} · Lv.${item.level} · ${recipe.materialName} ${have}/${recipe.materialCount}`
      );
      row.appendChild(this.button('제작', `${recipe.gold} G`, enough, () => this.onForge?.(id)));
      this.bodyEl.appendChild(row);
      shown++;
    }

    if (shown === 0) {
      this.empty(
        this.filter.readyOnly
          ? '지금 가진 재료로 만들 수 있는 게 없습니다. 재료는 보스가 떨굽니다 — 「만들 수 있는 것만」을 끄면 전체 목록이 나옵니다.'
          : '조건에 맞는 게 없습니다.'
      );
    }
    this.countEl.textContent = `${shown}개 / 만들 수 있는 것 ${rows.length}개 · 1등급으로 나오고 옵션 1~3개를 굴립니다`;
  }

  // ------------------------------------------------------------ 강화

  private renderEnhance(): void {
    let shown = 0;

    this.inventory.items.forEach((stack, index) => {
      const item = getItem(stack.id);
      if (!item || item.material) return;

      const level = stack.enhance ?? 0;
      const odds = enhanceOdds(level);
      const cost = enhanceCost(item, level);

      const row = this.row(
        itemIcon(item, stack.grade),
        `${item.name}${level > 0 ? ` +${level}` : ''}`,
        canEnhance(level)
          ? `성공 ${pct(odds.success)} · 유지 ${pct(odds.keep)} · 파괴 ${pct(odds.destroy)}`
          : `+${MAX_ENHANCE} — 더 못 올립니다`
      );
      // 파괴 확률이 있는 구간은 줄에서 티가 나야 한다. 확률을 글로만 적으면
      // 목록을 훑을 때 안 읽고 누른다.
      if (odds.destroy > 0) row.classList.add('is-risky');

      if (canEnhance(level)) {
        row.appendChild(
          this.button(`+${level + 1} 시도`, `${cost} G`, this.inventory.gold >= cost, () =>
            this.onEnhance?.(index)
          )
        );
      }
      this.bodyEl.appendChild(row);
      shown++;
    });

    if (shown === 0) this.empty('강화할 장비가 없습니다.');
    this.countEl.textContent = '골드만 씁니다. 실패해도 돌려주지 않고, 높은 단계는 파괴됩니다';
  }

  // ------------------------------------------------------------ 등급 올리기

  private renderGrade(): void {
    const owned = this.countById();
    // 같은 물건·등급은 한 줄로 묶는다 — 가방과 같은 규칙이다
    const seen = new Set<string>();
    let shown = 0;

    this.inventory.items.forEach((stack: ItemStack, index) => {
      const item = getItem(stack.id);
      if (!item || item.material) return;

      const key = `${stack.id}#${stack.grade}`;
      if (seen.has(key)) return;
      seen.add(key);

      const need = craftRequirement(item, stack.grade);
      const row = this.row(
        itemIcon(item, stack.grade),
        `${item.name} (${stack.grade}등급)`,
        need
          ? `${need.materialName} ${owned.get(need.materialId) ?? 0}/${need.materialCount}`
          : `${GRADE_MAX}등급 — 더 올릴 수 없습니다`
      );

      if (need) {
        const enough =
          (owned.get(need.materialId) ?? 0) >= need.materialCount &&
          this.inventory.gold >= need.gold;
        row.appendChild(
          this.button(`▲ ${need.targetGrade}등급`, `${need.gold} G`, enough, () =>
            this.onGrade?.(index)
          )
        );
      }
      this.bodyEl.appendChild(row);
      shown++;
    });

    if (shown === 0) this.empty('올릴 장비가 없습니다.');
    this.countEl.textContent = '같은 단계 보스 재료를 씁니다 · 등급이 오르면 옵션을 다시 굴립니다';
  }
}
