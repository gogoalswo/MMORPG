import { JOB_SKILLS, SKILLS, SKILL_UNLOCK_ALL, skillCooldown, type JobId } from '@mmo/shared';

/**
 * 스킬 디버그 목록 — 화면 왼쪽에 그 직업 스킬을 전부 늘어놓고, 누르면 바로 쏜다.
 *
 * 액션바는 4칸이라 그 이상은 스킬창(K)에서 갈아 끼워야 한다. 이펙트나 판정을 볼 때는
 * 그 왕복이 확인보다 오래 걸린다. 여기서는 **배우지도, 장착하지도 않고** 누르면 나간다.
 *
 * 서버도 같이 풀어 줘야 동작한다 — `handleSkill` 이 평소에는 액션바에 올라간 것만
 * 받아들인다 (`SKILL_UNLOCK_ALL` 이 켜져 있을 때만 그 검사를 건너뛴다).
 *
 * **스위치가 꺼져 있으면 아예 안 보인다.** 테스트 도구가 실제 플레이 화면에 남아 있으면
 * 그때부터는 버그다.
 */
export class SkillDebug {
  readonly root = document.createElement('div');

  /** 누르면 부른다. 서버로 보내는 건 부르는 쪽(main.ts)이 한다 */
  onCast?: (skillId: string) => void;

  private job: JobId | null = null;

  constructor(parent: HTMLElement) {
    this.root.className = 'skilldbg';
    if (!SKILL_UNLOCK_ALL) this.root.classList.add('is-hidden');
    parent.append(this.root);
  }

  /** 직업이 정해지거나 바뀌면 목록을 다시 만든다 */
  setJob(job: JobId): void {
    if (!SKILL_UNLOCK_ALL || job === this.job) return;
    this.job = job;
    this.root.replaceChildren();

    const title = document.createElement('div');
    title.className = 'skilldbg-title';
    title.textContent = '스킬 (테스트)';
    this.root.append(title);

    for (const id of JOB_SKILLS[job] ?? []) {
      const skill = SKILLS[id];
      if (!skill) continue;

      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'skilldbg-item';
      // 쿨타임은 테스트 스위치가 0 으로 만들어 둔다. 그래도 원래 값을 적어 둔다
      const cooldown = skillCooldown(skill) === 0 ? '쿨 0' : `${(skill.cooldown / 1000).toFixed(0)}초`;
      button.innerHTML =
        `<b>${skill.name}</b><small>Lv.${skill.reqLevel} · ${cooldown}</small>`;
      button.title = skill.description;
      button.addEventListener('click', () => this.onCast?.(id));
      this.root.append(button);
    }
  }
}
