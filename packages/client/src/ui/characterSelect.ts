import { getZone } from '@mmo/shared';
import { CLASSES, type ClassId } from '../game/characterClasses';

/**
 * 캐릭터 선택 화면.
 *
 * 삭제는 되돌릴 수 없다. 그래서 한 번 더 눌러야 실행되도록 두 단계로 만들었다 —
 * 확인 대화상자를 띄우는 것보다 흐름이 덜 끊기면서 오작동은 막는다.
 */

export interface CharacterSummary {
  id: string;
  name: string;
  job: string;
  level: number;
  zoneId: string;
}

export class CharacterSelectUI {
  private readonly root: HTMLDivElement;
  private readonly list: HTMLDivElement;
  private readonly createButton: HTMLButtonElement;
  private readonly enterButton: HTMLButtonElement;

  private characters: CharacterSummary[] = [];
  private selectedId: string | null = null;
  /** 삭제 확인 대기 중인 캐릭터 */
  private confirmingDelete: string | null = null;

  onEnter: ((id: string) => void) | null = null;
  onDelete: ((id: string) => void) | null = null;
  onCreateNew: (() => void) | null = null;
  onPreview: ((job: ClassId) => void) | null = null;
  onVisibility: ((open: boolean) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'select';

    const panel = document.createElement('div');
    panel.className = 'create-panel';

    const title = document.createElement('h1');
    title.className = 'create-title';
    title.textContent = '캐릭터 선택';

    this.list = document.createElement('div');
    this.list.className = 'select-list';

    this.enterButton = document.createElement('button');
    this.enterButton.type = 'button';
    // 생성 화면의 버튼과 모양은 같지만 클래스는 구분한다 (선택이 헷갈리면 안 된다)
    this.enterButton.className = 'create-submit select-enter';
    this.enterButton.textContent = '입장';
    this.enterButton.addEventListener('click', () => {
      if (this.selectedId) this.onEnter?.(this.selectedId);
    });

    this.createButton = document.createElement('button');
    this.createButton.type = 'button';
    this.createButton.className = 'select-new';
    this.createButton.textContent = '새 캐릭터 만들기';
    this.createButton.addEventListener('click', () => this.onCreateNew?.());

    panel.append(title, this.list, this.enterButton, this.createButton);
    this.root.appendChild(panel);
    parent.appendChild(this.root);
  }

  get open(): boolean {
    return this.root.classList.contains('is-open');
  }

  show(characters: CharacterSummary[], max: number, preferredId: string | null): void {
    this.characters = characters;
    this.confirmingDelete = null;

    // 마지막에 플레이한 캐릭터를 미리 골라둔다
    const preferred = characters.find((c) => c.id === preferredId);
    this.selectedId = (preferred ?? characters[0])?.id ?? null;

    this.createButton.disabled = characters.length >= max;
    this.createButton.textContent =
      characters.length >= max ? `캐릭터 슬롯이 가득 찼습니다 (${max})` : '새 캐릭터 만들기';

    this.render();
    this.root.classList.add('is-open');
    this.onVisibility?.(true);
    this.previewSelected();
  }

  hide(): void {
    this.root.classList.remove('is-open');
    this.onVisibility?.(false);
  }

  private previewSelected(): void {
    const selected = this.characters.find((c) => c.id === this.selectedId);
    if (selected) this.onPreview?.(selected.job as ClassId);
  }

  private render(): void {
    this.list.replaceChildren();

    for (const c of this.characters) {
      const row = document.createElement('div');
      row.className = 'select-row';
      if (c.id === this.selectedId) row.classList.add('is-selected');

      const pick = document.createElement('button');
      pick.type = 'button';
      pick.className = 'select-pick';
      const job = CLASSES[c.job as ClassId]?.label ?? c.job;
      let zoneName = c.zoneId;
      try {
        zoneName = getZone(c.zoneId).name;
      } catch {
        /* 삭제된 존에 저장돼 있을 수 있다 */
      }
      pick.innerHTML =
        `<span class="select-name">${c.name}</span>` +
        `<span class="select-meta">Lv.${c.level} · ${job} · ${zoneName}</span>`;
      pick.addEventListener('click', () => {
        this.selectedId = c.id;
        this.confirmingDelete = null;
        this.render();
        this.previewSelected();
      });
      // 더블클릭으로 바로 입장
      pick.addEventListener('dblclick', () => this.onEnter?.(c.id));

      const del = document.createElement('button');
      del.type = 'button';
      del.className = 'select-delete';
      const confirming = this.confirmingDelete === c.id;
      del.textContent = confirming ? '정말 삭제?' : '삭제';
      if (confirming) del.classList.add('is-confirming');
      del.addEventListener('click', () => {
        if (this.confirmingDelete === c.id) {
          this.onDelete?.(c.id);
          this.confirmingDelete = null;
        } else {
          this.confirmingDelete = c.id;
          this.render();
        }
      });

      row.append(pick, del);
      this.list.appendChild(row);
    }

    this.enterButton.disabled = this.selectedId === null;
  }
}
