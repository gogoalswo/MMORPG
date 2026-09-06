import { JOB_IDS, NAME_MAX, nameErrorMessage, validateCharacterName, type JobId } from '@mmo/shared';
import { CLASSES } from '../game/characterClasses';

/**
 * 첫 접속 시 캐릭터 생성 화면.
 *
 * 미리보기를 위해 별도 3D 뷰를 만들지 않는다. 이미 씬 안에 서 있는 내 캐릭터의
 * 직업을 바꿔 보여주면 충분하다 — 렌더러를 하나 더 돌리는 비용이 없고,
 * 실제 게임 안에서 보이는 그대로를 확인할 수 있다.
 */

const JOB_BLURB: Record<JobId, string> = {
  knight: '두꺼운 판금 갑옷과 방패. 앞에서 버티는 역할.',
  mage: '발목까지 오는 로브와 지팡이. 멀리서 큰 피해를 준다.',
  archer: '가벼운 가죽과 활. 거리를 유지하며 싸운다.',
};

export interface CharacterCreateResult {
  name: string;
  job: JobId;
}

export class CharacterCreateUI {
  private readonly root: HTMLDivElement;
  private readonly field: HTMLInputElement;
  private readonly error: HTMLDivElement;
  private readonly submit: HTMLButtonElement;
  private readonly cards = new Map<JobId, HTMLButtonElement>();

  private job: JobId = 'knight';
  private busy = false;

  /** 직업을 고를 때마다 호출된다 — 씬의 캐릭터를 바꾸는 데 쓴다 */
  onPreview: ((job: JobId) => void) | null = null;
  onSubmit: ((result: CharacterCreateResult) => void) | null = null;
  /** 화면이 열리고 닫힐 때 */
  onVisibility: ((open: boolean) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'create';

    const panel = document.createElement('div');
    panel.className = 'create-panel';

    const title = document.createElement('h1');
    title.className = 'create-title';
    title.textContent = '캐릭터 만들기';

    const nameLabel = document.createElement('label');
    nameLabel.className = 'create-label';
    nameLabel.textContent = '이름';

    this.field = document.createElement('input');
    this.field.className = 'create-input';
    this.field.type = 'text';
    this.field.maxLength = NAME_MAX;
    this.field.placeholder = '한글·영문·숫자 2~12자';
    this.field.autocomplete = 'off';
    nameLabel.appendChild(this.field);

    this.error = document.createElement('div');
    this.error.className = 'create-error';

    const jobLabel = document.createElement('div');
    jobLabel.className = 'create-label';
    jobLabel.textContent = '직업';

    const jobList = document.createElement('div');
    jobList.className = 'create-jobs';
    for (const id of JOB_IDS) {
      const card = document.createElement('button');
      card.type = 'button';
      card.className = 'create-job';
      card.innerHTML =
        `<span class="create-job-name">${CLASSES[id].label}</span>` +
        `<span class="create-job-desc">${JOB_BLURB[id]}</span>`;
      card.addEventListener('click', () => this.selectJob(id));
      jobList.appendChild(card);
      this.cards.set(id, card);
    }

    this.submit = document.createElement('button');
    this.submit.type = 'submit';
    this.submit.className = 'create-submit';
    this.submit.textContent = '시작하기';

    const form = document.createElement('form');
    form.append(title, nameLabel, this.error, jobLabel, jobList, this.submit);
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      this.trySubmit();
    });

    panel.appendChild(form);
    this.root.appendChild(panel);
    parent.appendChild(this.root);

    // 입력하는 즉시 규칙을 알려준다 (서버 왕복을 기다리지 않는다)
    this.field.addEventListener('input', () => this.showLiveError());
    // 게임 단축키가 같이 먹지 않도록
    this.field.addEventListener('keydown', (e) => e.stopPropagation());

    this.selectJob('knight');
  }

  get open(): boolean {
    return this.root.classList.contains('is-open');
  }

  show(suggestedName: string): void {
    this.field.value = suggestedName.slice(0, NAME_MAX);
    this.error.textContent = '';
    this.busy = false;
    this.submit.disabled = false;
    this.root.classList.add('is-open');
    this.field.focus();
    this.onPreview?.(this.job);
    this.onVisibility?.(true);
  }

  hide(): void {
    this.root.classList.remove('is-open');
    this.field.blur();
    this.onVisibility?.(false);
  }

  /** 서버가 거절했을 때 (중복 이름 등) */
  showError(reason: string): void {
    this.error.textContent = reason;
    this.busy = false;
    this.submit.disabled = false;
    this.field.focus();
  }

  private selectJob(job: JobId): void {
    this.job = job;
    for (const [id, card] of this.cards) card.classList.toggle('is-selected', id === job);
    this.onPreview?.(job);
  }

  private showLiveError(): void {
    const value = this.field.value.trim();
    if (value.length === 0) {
      this.error.textContent = '';
      return;
    }
    const error = validateCharacterName(value);
    this.error.textContent = error ? nameErrorMessage(error) : '';
  }

  private trySubmit(): void {
    if (this.busy) return;

    const name = this.field.value.trim();
    const error = validateCharacterName(name);
    if (error) {
      this.error.textContent = nameErrorMessage(error);
      this.field.focus();
      return;
    }

    // 중복 여부는 서버만 안다. 응답이 올 때까지 중복 제출을 막는다.
    this.busy = true;
    this.submit.disabled = true;
    this.error.textContent = '';
    this.onSubmit?.({ name, job: this.job });
  }
}
