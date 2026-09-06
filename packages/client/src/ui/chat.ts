export type ChatKind = 'say' | 'whisper' | 'system';

export interface ChatMessage {
  kind: ChatKind;
  from: string;
  /** 귓속말 대상 (귓속말일 때만) */
  to?: string;
  text: string;
}

/** 화면에 남겨두는 최대 줄 수 */
const MAX_LINES = 60;

/**
 * 채팅 UI.
 *
 * 가장 신경 쓴 부분은 **입력 중에 캐릭터가 움직이지 않게** 하는 것이다.
 * 채팅창에 "wasd"를 치는 동안 캐릭터가 뛰어다니면 못 쓴다.
 * Input 쪽에서 포커스된 요소가 입력창이면 키를 무시하도록 막아두었다.
 */
export class ChatUI {
  private readonly root: HTMLDivElement;
  private readonly log: HTMLDivElement;
  private readonly form: HTMLFormElement;
  private readonly field: HTMLInputElement;

  onSend: ((text: string) => void) | null = null;
  /** 입력창을 열 때 눌린 키를 털어내기 위한 훅 */
  onFocusChange: ((typing: boolean) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'chat';

    this.log = document.createElement('div');
    this.log.className = 'chat-log';

    this.form = document.createElement('form');
    this.form.className = 'chat-form';
    this.field = document.createElement('input');
    this.field.className = 'chat-input';
    this.field.type = 'text';
    this.field.maxLength = 200;
    this.field.placeholder = '메시지 (/w 이름 내용 = 귓속말)';
    this.field.autocomplete = 'off';
    this.form.appendChild(this.field);

    this.root.append(this.log, this.form);
    parent.appendChild(this.root);

    this.form.addEventListener('submit', (e) => {
      e.preventDefault();
      const text = this.field.value.trim();
      this.field.value = '';
      if (text) this.onSend?.(text);
      this.close();
    });

    this.field.addEventListener('keydown', (e) => {
      // Esc 로 취소. stopPropagation 은 게임 단축키가 같이 먹는 걸 막는다
      if (e.code === 'Escape') {
        e.preventDefault();
        this.field.value = '';
        this.close();
      }
      e.stopPropagation();
    });

    // Enter 로 채팅창 열기
    window.addEventListener('keydown', (e) => {
      if (this.typing) return;
      if (e.code !== 'Enter' && e.code !== 'NumpadEnter') return;
      e.preventDefault();
      this.open();
    });

    this.addMessage({
      kind: 'system',
      from: '',
      text: 'Enter 로 채팅. /w 이름 내용 으로 귓속말.',
    });
  }

  get typing(): boolean {
    return document.activeElement === this.field;
  }

  private open(): void {
    this.root.classList.add('is-open');
    this.field.focus();
    this.onFocusChange?.(true);
  }

  private close(): void {
    this.root.classList.remove('is-open');
    this.field.blur();
    this.onFocusChange?.(false);
  }

  addMessage(msg: ChatMessage): void {
    const atBottom = this.log.scrollHeight - this.log.scrollTop - this.log.clientHeight < 24;

    const line = document.createElement('div');
    line.className = `chat-line chat-${msg.kind}`;

    if (msg.kind === 'system') {
      line.textContent = msg.text;
    } else if (msg.kind === 'whisper') {
      const label = document.createElement('span');
      label.className = 'chat-from';
      label.textContent = msg.to ? `${msg.from} → ${msg.to}` : msg.from;
      line.append(label, document.createTextNode(` ${msg.text}`));
    } else {
      const label = document.createElement('span');
      label.className = 'chat-from';
      label.textContent = `${msg.from}:`;
      line.append(label, document.createTextNode(` ${msg.text}`));
    }

    this.log.appendChild(line);
    while (this.log.childElementCount > MAX_LINES) this.log.firstElementChild?.remove();

    // 위로 올려 과거 로그를 보고 있으면 강제로 내리지 않는다
    if (atBottom) this.log.scrollTop = this.log.scrollHeight;
  }
}
