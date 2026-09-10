/**
 * 사망 화면.
 *
 * 예전에는 죽어도 화면에 아무 변화가 없었다. HP 만 0 이 되고 캐릭터는 선 채로
 * 조작만 안 먹어서, 죽은 줄 모르고 "왜 안 움직이지" 하고 있게 됐다.
 * 쓰러지는 동작(`CharacterRig.die`)과 이 화면이 그 신호다.
 *
 * 화면 전체를 덮고 **아무 데나 누르면** 마을로 돌아간다. 버튼 하나만 눌리게
 * 하면 죽은 정신에 그 작은 사각형을 찾아야 한다.
 */
export class DeathOverlay {
  private readonly root: HTMLElement;
  private shown = false;

  /** 화면을 눌렀다 — 마을로 보내달라 */
  onReturn: (() => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'death is-hidden';
    this.root.innerHTML = `
      <div class="death-title">사망했습니다</div>
      <div class="death-hint">클릭하면 마을로 돌아갑니다</div>`;

    this.root.addEventListener('click', () => {
      // 연타로 여러 번 보내지 않는다. 존 전환은 되돌릴 수 없다.
      if (!this.shown) return;
      this.hide();
      this.onReturn?.();
    });

    parent.appendChild(this.root);
  }

  get open(): boolean {
    return this.shown;
  }

  show(): void {
    if (this.shown) return;
    this.shown = true;
    this.root.classList.remove('is-hidden');
  }

  hide(): void {
    if (!this.shown) return;
    this.shown = false;
    this.root.classList.add('is-hidden');
  }
}
