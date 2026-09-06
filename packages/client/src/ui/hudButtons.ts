/**
 * 화면 오른쪽 위의 창 여는 버튼들.
 *
 * 가방(I)·스킬(K)·채팅(Enter)은 **단축키로만** 열렸다. 키보드가 없는 폰에서는
 * 아이템을 끼는 것도, 스킬을 배우는 것도, 말을 거는 것도 불가능했다 —
 * 게임의 절반이 잠겨 있던 셈이다.
 *
 * PC 에서도 그대로 둔다. 단축키를 외우지 않은 사람에게는 여기가 유일한 길이고,
 * 외운 사람은 안 쳐다보면 그만이다. 대신 버튼에 단축키를 같이 적어둬서
 * 한 번 눌러본 사람은 다음부터 키를 쓰게 된다.
 */

export type HudPanel = 'bag' | 'skills' | 'chat';

interface Entry {
  id: HudPanel;
  glyph: string;
  label: string;
  key: string;
}

/** 위에서부터의 순서. 자주 여는 것이 위로 온다 */
const ENTRIES: Entry[] = [
  { id: 'bag', glyph: '▤', label: '가방', key: 'I' },
  { id: 'skills', glyph: '✦', label: '스킬', key: 'K' },
  { id: 'chat', glyph: '✎', label: '채팅', key: '⏎' },
];

export class HudButtons {
  private readonly root: HTMLDivElement;
  private readonly buttons = new Map<HudPanel, HTMLButtonElement>();
  /** 마지막으로 칠한 상태. 매 프레임 DOM 을 건드리지 않으려고 기억해 둔다 */
  private shown = new Set<HudPanel>();

  onOpen: ((panel: HudPanel) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'hudbtns is-hidden';

    for (const entry of ENTRIES) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'hudbtn';
      button.title = `${entry.label} (${entry.key})`;
      button.innerHTML =
        `<span class="hudbtn-glyph">${entry.glyph}</span>` +
        `<span class="hudbtn-label">${entry.label}</span>` +
        `<span class="hudbtn-key">${entry.key}</span>`;
      button.addEventListener('click', () => this.onOpen?.(entry.id));
      this.root.appendChild(button);
      this.buttons.set(entry.id, button);
    }

    parent.appendChild(this.root);
  }

  setVisible(visible: boolean): void {
    this.root.classList.toggle('is-hidden', !visible);
  }

  /**
   * 열려 있는 창을 밝힌다.
   *
   * 창은 자기 ✕ 로도 닫히므로 버튼 쪽에서 상태를 알 방법이 없다.
   * 그래서 매 프레임 물어보되, **바뀐 것만** 손댄다.
   */
  update(open: Set<HudPanel>): void {
    for (const [id, button] of this.buttons) {
      const now = open.has(id);
      if (now === this.shown.has(id)) continue;
      button.classList.toggle('is-on', now);
      if (now) this.shown.add(id);
      else this.shown.delete(id);
    }
  }
}
