import { SKILLS, skillCooldown, type SkillDef } from '@mmo/shared';

/**
 * 액션바.
 *
 * 여기 보이는 쿨타임은 **표시일 뿐이다.** 실제 판정은 서버가 한다.
 * 그래도 클라이언트에서 미리 막아야 하는 이유는, 눌렀는데 아무 일도 안 일어나면
 * 게임이 고장난 것처럼 느껴지기 때문이다.
 */

interface Slot {
  skill: SkillDef;
  root: HTMLButtonElement;
  sweep: HTMLElement;
  timer: HTMLElement;
  auto: HTMLButtonElement;
  /** 쿨타임이 끝나는 시각 (performance.now 기준) */
  readyAt: number;
}

/** 자동 시전으로 켜둔 스킬. 직업이 바뀌어도 기억한다 */
const AUTO_KEY = 'mmo.autoSkills';

function readAuto(): Set<string> {
  try {
    const raw = JSON.parse(localStorage.getItem(AUTO_KEY) ?? '[]') as unknown;
    return new Set(Array.isArray(raw) ? raw.filter((x): x is string => typeof x === 'string') : []);
  } catch {
    return new Set();
  }
}

export class ActionBar {
  private readonly root: HTMLDivElement;
  private slots: Slot[] = [];
  /** 자동 시전으로 켜둔 스킬 id */
  private auto = readAuto();

  onUse: ((skillId: string) => void) | null = null;
  /** 자동 시전 목록이 바뀌었다 — 서버에 알려야 한다 */
  onAutoChange: ((skillIds: string[]) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'actionbar';
    parent.appendChild(this.root);
  }

  setVisible(visible: boolean): void {
    this.root.classList.toggle('is-hidden', !visible);
  }

  /**
   * 액션바를 다시 만든다.
   *
   * 예전에는 직업의 스킬 전부를 늘어놨지만, 이제 **스킬창에서 장착한 것**만
   * 올라온다. 목록이 바뀔 때마다 통째로 다시 그린다 — 칸이 넷뿐이라 싸다.
   */
  setSkills(ids: string[]): void {
    this.root.replaceChildren();
    this.slots = [];

    // 장착에서 내린 스킬은 자동 시전 목록에서도 뺀다
    this.auto = new Set([...this.auto].filter((id) => ids.includes(id)));
    ids.forEach((id, index) => {
      const skill = SKILLS[id];
      if (!skill) return;

      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'slot';
      button.title = `${skill.name} — ${skill.description}`;
      button.innerHTML = `
        <span class="slot-key">${index + 1}</span>
        <span class="slot-name">${skill.name}</span>
        <span class="slot-sweep"></span>
        <span class="slot-timer"></span>`;
      button.addEventListener('click', () => this.use(index));

      // 자동 시전 스위치. 스킬 버튼 안에 두되 클릭이 겹치지 않게 막는다.
      const auto = document.createElement('button');
      auto.type = 'button';
      auto.className = 'slot-auto';
      auto.textContent = 'A';
      auto.title = '켜면 사거리 안에 적이 있을 때 알아서 씁니다';
      auto.addEventListener('click', (e) => {
        e.stopPropagation();
        this.toggleAuto(skill.id);
      });
      button.appendChild(auto);

      this.root.appendChild(button);
      this.slots.push({
        skill,
        root: button,
        sweep: button.querySelector('.slot-sweep') as HTMLElement,
        timer: button.querySelector('.slot-timer') as HTMLElement,
        auto,
        readyAt: 0,
      });
    });

    this.paintAuto();
  }

  /**
   * 숫자키로 쓴다 (0-based).
   * 실제로 나갔는지 돌려준다 — 자동 사냥이 다음 스킬로 넘어갈지 판단해야 한다.
   */
  use(index: number): boolean {
    const slot = this.slots[index];
    if (!slot) return false;
    if (performance.now() < slot.readyAt) return false;

    // 서버 응답을 기다리지 않고 쿨타임을 돌린다 — 연타로 도배되는 걸 막는다.
    // 서버가 거절하면 그냥 쿨타임만 돈 셈이라 손해가 크지 않다.
    // 테스트 스위치(SKILL_COOLDOWN_OFF)가 켜져 있으면 0 — 서버와 같은 함수를 본다
    slot.readyAt = performance.now() + skillCooldown(slot.skill);
    this.onUse?.(slot.skill.id);
    return true;
  }

  /** 지금 켜둔 자동 시전 목록 — 접속하자마자 서버에 알려야 한다 */
  get autoSkills(): string[] {
    return [...this.auto];
  }

  private toggleAuto(skillId: string): void {
    if (this.auto.has(skillId)) this.auto.delete(skillId);
    else this.auto.add(skillId);

    try {
      localStorage.setItem(AUTO_KEY, JSON.stringify([...this.auto]));
    } catch {
      /* 저장이 막혀도 이번 판은 유지된다 */
    }
    this.paintAuto();
    this.onAutoChange?.(this.autoSkills);
  }

  private paintAuto(): void {
    for (const slot of this.slots) {
      slot.auto.classList.toggle('is-on', this.auto.has(slot.skill.id));
    }
  }

  update(): void {
    const now = performance.now();
    for (const slot of this.slots) {
      const remain = slot.readyAt - now;
      const onCooldown = remain > 0;

      slot.root.classList.toggle('is-cooling', onCooldown);

      if (onCooldown) {
        // 위에서 아래로 걷히는 그림자로 남은 시간을 보여준다
        slot.sweep.style.height = `${(remain / slot.skill.cooldown) * 100}%`;
        slot.timer.textContent = remain > 1000 ? String(Math.ceil(remain / 1000)) : remain.toFixed(0).slice(0, 1);
      } else if (slot.sweep.style.height !== '0%') {
        slot.sweep.style.height = '0%';
        slot.timer.textContent = '';
      }
    }
  }

  /** 존을 옮기거나 죽으면 쿨타임 표시를 초기화한다 */
  reset(): void {
    for (const slot of this.slots) {
      slot.readyAt = 0;
      slot.sweep.style.height = '0%';
      slot.timer.textContent = '';
    }
  }
}
