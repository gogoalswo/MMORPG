import {
  ATTACK_SPEED_CAP,
  BASE_CRIT,
  BASE_CRIT_DAMAGE,
  CRIT_CAP,
  EQUIP_SLOTS,
  GRADE_MAX,
  INVENTORY_SIZE,
  slotLabel,
  baseBonus,
  canEquip,
  craftRequirement,
  describeOption,
  equipmentStats,
  getItem,
  isPercentOption,
  optionRange,
  type EquipSlot,
  type ItemBonus,
  type ItemDef,
  type ItemOption,
  type JobId,
} from '@mmo/shared';
import { itemIcon } from './itemIcons';
import type { InventoryState } from '../net/connection';

/**
 * 가방과 장비 창.
 *
 * 칸을 5개씩 한 줄로 놓고 아래로 늘어난다. **같은 물건은 한 칸에 겹쳐 놓고**
 * 개수를 적는다 — 재료를 아홉 개씩 모아야 하는데 한 줄에 하나씩 늘어놓으면
 * 화면이 금세 재료로 덮인다.
 *
 * 칸이 작아 이름을 다 못 쓰므로, 고른 것의 상세와 버튼은 아래 칸에서 보여준다.
 *
 * 여기 보이는 건 전부 **서버가 보내준 그대로**다. 착용 가능 여부를 흐리게
 * 표시하긴 하지만 그건 안내일 뿐이고, 실제 판정은 서버가 다시 한다.
 */

/** 한 줄에 놓는 칸 수 */
const COLUMNS = 5;

/** 같은 물건끼리 묶은 한 칸 */
interface Cell {
  key: string;
  item: ItemDef;
  grade: number;
  /** 강화 수치. 다르면 성능이 달라 한 칸에 겹치지 않는다 */
  enhance: number;
  /** 굴려서 붙은 옵션. 이게 다르면 성능도 달라 겹치지 않는다 */
  options: ItemOption[];
  count: number;
  /** 실제 가방에서의 자리들. 서버에는 이 중 첫 번째를 보낸다 */
  indices: number[];
}

/** 옵션까지 포함해 "같은 물건인가"를 가르는 열쇠 */
function stackKey(id: string, grade: number, enhance: number, options: ItemOption[]): string {
  return `${id}#${grade}#${enhance}#${options.map((o) => `${o.kind}:${o.value}`).join(',')}`;
}

function describeBonus(bonus: ItemBonus): string {
  const parts: string[] = [];
  if (bonus.attack) parts.push(`공격 +${bonus.attack}`);
  if (bonus.defense) parts.push(`방어 +${bonus.defense}`);
  if (bonus.maxHp) parts.push(`체력 +${bonus.maxHp}`);
  if (bonus.maxMp) parts.push(`마나 +${bonus.maxMp}`);
  return parts.join(' · ');
}

export class InventoryPanel {
  private readonly root: HTMLDivElement;
  private readonly goldEl: HTMLElement;
  private readonly equipEl: HTMLElement;
  private readonly gearSumEl: HTMLElement;
  private readonly gridEl: HTMLElement;
  private readonly countEl: HTMLElement;
  private readonly detailEl: HTMLElement;

  private state: InventoryState = { gold: 0, items: [], equipment: {} };
  private job: JobId = 'knight';
  private level = 1;
  /** 고른 칸의 key */
  private selected: string | null = null;

  onEquip: ((index: number) => void) | null = null;
  onUnequip: ((slot: EquipSlot) => void) | null = null;
  onCraft: ((index: number) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'bag is-hidden';
    this.root.innerHTML = `
      <div class="bag-head">
        <span class="bag-title">가방</span>
        <span class="bag-gold">0 G</span>
        <button type="button" class="bag-close">✕</button>
      </div>
      <div class="bag-equip"></div>
      <div class="bag-gear-sum"></div>
      <div class="bag-sub">가방 <span class="bag-count">0/${INVENTORY_SIZE}</span></div>
      <div class="bag-grid"></div>
      <div class="bag-detail is-empty"></div>`;

    this.goldEl = this.root.querySelector('.bag-gold') as HTMLElement;
    this.equipEl = this.root.querySelector('.bag-equip') as HTMLElement;
    this.gearSumEl = this.root.querySelector('.bag-gear-sum') as HTMLElement;
    this.gridEl = this.root.querySelector('.bag-grid') as HTMLElement;
    this.countEl = this.root.querySelector('.bag-count') as HTMLElement;
    this.detailEl = this.root.querySelector('.bag-detail') as HTMLElement;

    (this.root.querySelector('.bag-close') as HTMLElement).addEventListener('click', () =>
      this.setOpen(false)
    );
    parent.appendChild(this.root);
  }

  get open(): boolean {
    return !this.root.classList.contains('is-hidden');
  }

  setOpen(open: boolean): void {
    this.root.classList.toggle('is-hidden', !open);
    // 닫혀 있는 동안의 갱신은 건너뛰므로, 열 때 한 번 다시 그린다
    if (open) this.render();
  }

  toggle(): void {
    this.setOpen(!this.open);
  }

  /** 착용 가능 판정에 쓰인다 */
  setCharacter(job: JobId, level: number): void {
    this.job = job;
    this.level = level;
    if (this.open) this.render();
  }

  setState(state: InventoryState): void {
    this.state = state;
    this.render();
  }

  /** 같은 id·등급끼리 한 칸으로 묶는다 */
  private cells(): Cell[] {
    const byKey = new Map<string, Cell>();

    this.state.items.forEach((stack, index) => {
      const item = getItem(stack.id);
      if (!item) return; // 서버에만 있는 아이템 — 조용히 건너뛴다

      const enhance = stack.enhance ?? 0;
      const options = stack.options ?? [];
      const key = stackKey(stack.id, stack.grade, enhance, options);
      const found = byKey.get(key);
      if (found) {
        found.count++;
        found.indices.push(index);
        return;
      }
      byKey.set(key, {
        key,
        item,
        grade: stack.grade,
        enhance,
        options,
        count: 1,
        indices: [index],
      });
    });

    return [...byKey.values()];
  }

  private render(): void {
    this.goldEl.textContent = `${this.state.gold.toLocaleString()} G`;
    this.countEl.textContent = `${this.state.items.length}/${INVENTORY_SIZE}`;

    this.renderEquipment();
    this.renderGearSummary();

    const cells = this.cells();
    // 골라둔 칸이 사라졌으면(제작으로 등급이 바뀌는 등) 선택을 푼다
    if (this.selected && !cells.some((c) => c.key === this.selected)) this.selected = null;

    this.renderGrid(cells);
    this.renderDetail(cells.find((c) => c.key === this.selected) ?? null);
  }

  /**
   * 장비가 더해주는 것 중 **상태바에 안 나오는 것들**.
   *
   * 공격·방어·체력은 이미 상태바와 숫자로 보이지만, 치명타와 공격 속도는
   * 어디에도 안 나온다. 옵션으로만 붙는 값이라 여기서 합을 보여주지 않으면
   * 무엇을 끼웠는지 알 수 없다.
   */
  private renderGearSummary(): void {
    const gear = equipmentStats(this.state.equipment);
    const pct = (v: number) => Math.round(v * 100);

    this.gearSumEl.textContent =
      `치명타 ${pct(BASE_CRIT + gear.crit)}%` +
      ` · 치명타 데미지 ${pct(BASE_CRIT_DAMAGE + gear.critDamage)}%` +
      ` · 공격 속도 +${pct(gear.attackSpeed)}%`;
    this.gearSumEl.title =
      `치명타는 ${pct(CRIT_CAP)}%, 공격 속도는 +${pct(ATTACK_SPEED_CAP)}% 에서 멈춥니다`;
  }

  private renderEquipment(): void {
    this.equipEl.replaceChildren();

    for (const slot of EQUIP_SLOTS) {
      const stack = this.state.equipment[slot];
      const item = stack ? getItem(stack.id) : null;

      const cell = document.createElement('button');
      cell.type = 'button';
      cell.className = 'bag-slot' + (item ? ' is-filled' : '');
      const plus = stack?.enhance ? `+${stack.enhance}` : '';
      cell.innerHTML = item
        ? `${itemIcon(item, stack!.grade)}<span class="bag-badge-grade">${stack!.grade}</span>` +
          (plus ? `<span class="bag-badge-plus">${plus}</span>` : '')
        : `<span class="bag-slot-empty">${slotLabel(slot, this.job)}</span>`;
      const worn = [
        `${item?.name ?? ''} ${plus} (${stack?.grade ?? 1}등급)`,
        item ? describeBonus(baseBonus(item, stack!.enhance)) : '',
        ...(stack?.options ?? []).map((o) => `· ${describeOption(o)}`),
        '클릭하면 벗습니다',
      ];
      cell.title = item
        ? worn.filter(Boolean).join('\n')
        : `${slotLabel(slot, this.job)} 비어 있음`;
      if (item) cell.addEventListener('click', () => this.onUnequip?.(slot));
      this.equipEl.appendChild(cell);
    }
  }

  private renderGrid(cells: Cell[]): void {
    this.gridEl.replaceChildren();
    this.gridEl.style.gridTemplateColumns = `repeat(${COLUMNS}, 1fr)`;

    if (cells.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'bag-empty';
      empty.textContent = '비어 있습니다. 몬스터를 잡으면 들어옵니다.';
      this.gridEl.appendChild(empty);
      return;
    }

    for (const cell of cells) {
      const usable = canEquip(cell.item, this.job, this.level);

      const button = document.createElement('button');
      button.type = 'button';
      button.className =
        'bag-cell' +
        (this.selected === cell.key ? ' is-selected' : '') +
        (cell.item.material || usable ? '' : ' is-locked');
      button.innerHTML =
        itemIcon(cell.item, cell.grade) +
        (cell.item.material ? '' : `<span class="bag-badge-grade">${cell.grade}</span>`) +
        (cell.enhance > 0 ? `<span class="bag-badge-plus">+${cell.enhance}</span>` : '') +
        (cell.count > 1 ? `<span class="bag-badge-count">${cell.count}</span>` : '');
      button.title = `${cell.item.name}${cell.enhance > 0 ? ` +${cell.enhance}` : ''}${
        cell.item.material ? '' : ` (${cell.grade}등급)`
      }`;
      button.addEventListener('click', () => {
        this.selected = this.selected === cell.key ? null : cell.key;
        this.render();
      });
      this.gridEl.appendChild(button);
    }
  }

  private renderDetail(cell: Cell | null): void {
    this.detailEl.replaceChildren();

    if (!cell) {
      this.detailEl.className = 'bag-detail is-empty';
      this.detailEl.textContent = '칸을 고르면 자세히 보입니다.';
      return;
    }
    this.detailEl.className = 'bag-detail';

    const head = document.createElement('div');
    head.className = 'bag-detail-head';
    head.innerHTML =
      `<span class="bag-detail-name">${cell.item.name}${cell.enhance > 0 ? ` +${cell.enhance}` : ''}</span>` +
      (cell.item.material
        ? `<span class="bag-detail-meta">제작 재료 · ${cell.count}개</span>`
        : `<span class="bag-detail-meta">${slotLabel(cell.item.slot!, this.job)} · Lv.${cell.item.level} · ${cell.grade}등급${
            cell.count > 1 ? ` · ${cell.count}개` : ''
          }</span>`);
    this.detailEl.appendChild(head);

    if (!cell.item.material) {
      const bonus = document.createElement('div');
      bonus.className = 'bag-detail-bonus';
      bonus.textContent = describeBonus(baseBonus(cell.item, cell.enhance));
      this.detailEl.appendChild(bonus);

      // 옵션은 물건마다 다르다. 그 등급에서 나올 수 있었던 범위를 함께 달아둬야
      // 잘 뽑은 물건인지 알 수 있다.
      const list = document.createElement('div');
      list.className = 'bag-detail-options';

      if (cell.options.length === 0) {
        const none = document.createElement('span');
        none.className = 'bag-opt is-none';
        none.textContent = '옵션 없음';
        list.appendChild(none);
      }

      for (const option of cell.options) {
        const range = optionRange(option.kind, cell.grade, cell.item.level);
        const unit = isPercentOption(option.kind) ? '%' : '';
        const el = document.createElement('span');
        el.className = 'bag-opt';
        el.textContent = describeOption(option);
        el.title = `${cell.grade}등급 범위 ${range.min}~${range.max}${unit}`;
        list.appendChild(el);
      }
      this.detailEl.appendChild(list);
    }

    const actions = document.createElement('div');
    actions.className = 'bag-detail-actions';

    if (cell.item.material) {
      const hint = document.createElement('span');
      hint.className = 'bag-detail-hint';
      hint.textContent = '같은 단계 장비의 등급을 올릴 때 씁니다.';
      actions.appendChild(hint);
    } else {
      const usable = canEquip(cell.item, this.job, this.level);
      const equip = document.createElement('button');
      equip.type = 'button';
      equip.className = 'bag-action' + (usable ? '' : ' is-locked');
      equip.textContent = usable ? '착용' : `Lv.${cell.item.level} 필요`;
      if (usable) equip.addEventListener('click', () => this.onEquip?.(cell.indices[0]!));
      actions.appendChild(equip);

      const need = craftRequirement(cell.item, cell.grade);
      if (need) {
        const have = this.countOf(need.materialId);
        const ready = have >= need.materialCount;
        const craft = document.createElement('button');
        craft.type = 'button';
        craft.className = 'bag-action is-craft' + (ready ? '' : ' is-locked');
        craft.innerHTML =
          `<span>▲ ${need.targetGrade}등급</span>` +
          `<span class="bag-action-sub">${need.materialName} ${have}/${need.materialCount} · ${need.gold}G</span>`;
        craft.title = ready
          ? `${need.materialName} ${need.materialCount}개와 ${need.gold}G 를 씁니다\n등급이 오르면 옵션을 다시 굴립니다 (범위가 넓어집니다)`
          : `${need.materialName} 가 모자랍니다 — 보스가 떨굽니다`;
        if (ready) craft.addEventListener('click', () => this.onCraft?.(cell.indices[0]!));
        actions.appendChild(craft);
      } else if (cell.grade >= GRADE_MAX) {
        const done = document.createElement('span');
        done.className = 'bag-action is-locked';
        done.textContent = '최고 등급';
        actions.appendChild(done);
      }
    }

    this.detailEl.appendChild(actions);
  }

  private countOf(itemId: string): number {
    let n = 0;
    for (const stack of this.state.items) if (stack.id === itemId) n++;
    return n;
  }
}
