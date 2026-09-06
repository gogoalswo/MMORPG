import {
  JOB_SKILLS,
  SKILLS,
  SKILL_BAR_SIZE,
  canLearn,
  type JobId,
  type SkillDef,
} from '@mmo/shared';

/**
 * 스킬창 — 배우기와 장착.
 *
 * 직업이 가진 스킬 전부를 요구 레벨 순으로 늘어놓는다. 레벨이 되고 포인트가
 * 있으면 배울 수 있고, 배운 것 중 **넷만** 액션바에 올린다.
 *
 * 전부 안내다. 배울 수 있는지, 올릴 수 있는지는 서버가 다시 본다.
 */

export interface SkillState {
  learned: string[];
  bar: string[];
  points: number;
}

function describe(skill: SkillDef): string {
  const bits: string[] = [];
  if (skill.selfHeal) bits.push(`회복 ${Math.round(skill.selfHeal * 100)}%`);
  else bits.push(`배율 ${skill.power}`);
  if (skill.maxTargets > 1) bits.push(`${skill.maxTargets}명`);
  if (skill.range > 0) bits.push(`${skill.range}m`);
  bits.push(`${Math.round(skill.cooldown / 1000)}초`);
  return bits.join(' · ');
}

export class SkillBook {
  private readonly root: HTMLDivElement;
  private readonly pointsEl: HTMLElement;
  private readonly barEl: HTMLElement;
  private readonly listEl: HTMLElement;

  private state: SkillState = { learned: [], bar: [], points: 0 };
  private job: JobId = 'knight';
  private level = 1;

  onLearn: ((skillId: string) => void) | null = null;
  onBar: ((skillIds: string[]) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'sb is-hidden';
    this.root.innerHTML = `
      <div class="sb-head">
        <span class="sb-title">스킬</span>
        <span class="sb-points">포인트 0</span>
        <button type="button" class="sb-close">✕</button>
      </div>
      <div class="sb-sub">장착 (최대 ${SKILL_BAR_SIZE})</div>
      <div class="sb-bar"></div>
      <div class="sb-sub">배울 수 있는 스킬</div>
      <div class="sb-list"></div>`;

    this.pointsEl = this.root.querySelector('.sb-points') as HTMLElement;
    this.barEl = this.root.querySelector('.sb-bar') as HTMLElement;
    this.listEl = this.root.querySelector('.sb-list') as HTMLElement;

    (this.root.querySelector('.sb-close') as HTMLElement).addEventListener('click', () =>
      this.setOpen(false)
    );
    parent.appendChild(this.root);
  }

  get open(): boolean {
    return !this.root.classList.contains('is-hidden');
  }

  setOpen(open: boolean): void {
    this.root.classList.toggle('is-hidden', !open);
    if (open) this.render();
  }

  toggle(): void {
    this.setOpen(!this.open);
  }

  setCharacter(job: JobId, level: number): void {
    this.job = job;
    this.level = level;
    if (this.open) this.render();
  }

  setState(state: SkillState): void {
    this.state = state;
    if (this.open) this.render();
  }

  private render(): void {
    this.pointsEl.textContent = `포인트 ${this.state.points}`;
    this.renderBar();
    this.renderList();
  }

  private renderBar(): void {
    this.barEl.replaceChildren();

    for (let i = 0; i < SKILL_BAR_SIZE; i++) {
      const id = this.state.bar[i];
      const skill = id ? SKILLS[id] : null;

      const cell = document.createElement('button');
      cell.type = 'button';
      cell.className = 'sb-slot' + (skill ? ' is-filled' : '');
      cell.innerHTML = skill
        ? `<span class="sb-slot-key">${i + 1}</span><span class="sb-slot-name">${skill.name}</span>`
        : `<span class="sb-slot-key">${i + 1}</span><span class="sb-slot-empty">비어 있음</span>`;
      if (skill) {
        cell.title = '클릭하면 내립니다';
        cell.addEventListener('click', () => {
          this.onBar?.(this.state.bar.filter((x) => x !== id));
        });
      }
      this.barEl.appendChild(cell);
    }
  }

  private renderList(): void {
    this.listEl.replaceChildren();

    for (const id of JOB_SKILLS[this.job] ?? []) {
      const skill = SKILLS[id];
      if (!skill) continue;

      const learned = this.state.learned.includes(id);
      const onBar = this.state.bar.includes(id);
      const reachable = canLearn(skill, this.job, this.level);

      const row = document.createElement('div');
      row.className = 'sb-row' + (learned ? '' : ' is-locked');
      row.innerHTML =
        `<span class="sb-row-text">` +
        `<b>${skill.name}<small class="sb-req">Lv.${skill.reqLevel}</small></b>` +
        `<small>${skill.description}</small>` +
        `<small class="sb-stat">${describe(skill)}</small>` +
        `</span>`;

      const action = document.createElement('button');
      action.type = 'button';

      if (!learned) {
        const can = reachable && this.state.points > 0;
        action.className = 'sb-btn' + (can ? '' : ' is-locked');
        action.textContent = reachable ? '배우기' : `Lv.${skill.reqLevel}`;
        action.title = reachable
          ? '스킬 포인트 1을 씁니다'
          : `Lv.${skill.reqLevel} 부터 배울 수 있습니다`;
        if (can) action.addEventListener('click', () => this.onLearn?.(id));
      } else if (onBar) {
        action.className = 'sb-btn is-on';
        action.textContent = '장착 중';
        action.addEventListener('click', () => {
          this.onBar?.(this.state.bar.filter((x) => x !== id));
        });
      } else {
        const full = this.state.bar.length >= SKILL_BAR_SIZE;
        action.className = 'sb-btn' + (full ? ' is-locked' : '');
        action.textContent = full ? '자리 없음' : '장착';
        action.title = full ? `먼저 하나를 내리세요 (최대 ${SKILL_BAR_SIZE})` : '';
        if (!full) action.addEventListener('click', () => this.onBar?.([...this.state.bar, id]));
      }

      row.appendChild(action);
      this.listEl.appendChild(row);
    }
  }
}
