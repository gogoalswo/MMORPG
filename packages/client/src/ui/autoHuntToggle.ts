import { HUNT_RADIUS, HUNT_RADIUS_MAX, HUNT_RADIUS_MIN, clampHuntRadius } from '@mmo/shared';

/** 고른 반경을 다음 접속에도 쓴다 */
const RANGE_KEY = 'mmo.autoRange';

function readRange(): number {
  try {
    return clampHuntRadius(Number(localStorage.getItem(RANGE_KEY) ?? HUNT_RADIUS));
  } catch {
    return HUNT_RADIUS;
  }
}

/**
 * 자동 사냥 토글 버튼.
 *
 * 액션바 오른쪽에 붙는 별도 요소다. 액션바 안에 넣지 않는 이유는
 * setJob() 이 슬롯을 통째로 다시 만들면서 같이 지워지기 때문이다.
 */
export class AutoHuntToggle {
  private readonly root: HTMLButtonElement;
  private readonly label: HTMLElement;
  private readonly rangeBox!: HTMLLabelElement;
  private readonly rangeInput!: HTMLInputElement;
  private readonly rangeValue!: HTMLElement;
  private range = HUNT_RADIUS;

  onToggle: (() => void) | null = null;
  onRange: ((radius: number) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('button');
    this.root.type = 'button';
    this.root.className = 'autohunt';
    this.root.title = '자동 사냥 — 켠 자리 주변의 몬스터를 알아서 찾아 싸운다';
    this.root.innerHTML = `
      <span class="autohunt-icon">⚔</span>
      <span class="autohunt-label">자동 사냥</span>
      <span class="autohunt-state">꺼짐</span>`;
    this.label = this.root.querySelector('.autohunt-state') as HTMLElement;

    this.root.addEventListener('click', () => this.onToggle?.());
    parent.appendChild(this.root);

    // --- 사냥 반경 ---
    this.range = readRange();
    this.rangeBox = document.createElement('label');
    this.rangeBox.className = 'autorange is-hidden';
    this.rangeBox.innerHTML = `
      <span class="autorange-label">범위 <b class="autorange-value">${this.range}</b>m</span>
      <input type="range" class="autorange-input"
             min="${HUNT_RADIUS_MIN}" max="${HUNT_RADIUS_MAX}" step="1" value="${this.range}">`;
    this.rangeValue = this.rangeBox.querySelector('.autorange-value') as HTMLElement;
    this.rangeInput = this.rangeBox.querySelector('.autorange-input') as HTMLInputElement;

    this.rangeInput.addEventListener('input', () => {
      this.range = clampHuntRadius(Number(this.rangeInput.value));
      this.rangeValue.textContent = String(this.range);
      try {
        localStorage.setItem(RANGE_KEY, String(this.range));
      } catch {
        /* 저장이 막혀도 이번 판은 유지된다 */
      }
      this.onRange?.(this.range);
    });
    // 슬라이더를 끌 때 캐릭터가 같이 움직이면 안 된다
    for (const type of ['pointerdown', 'pointermove', 'pointerup', 'wheel']) {
      this.rangeBox.addEventListener(type, (e) => e.stopPropagation());
    }

    parent.appendChild(this.rangeBox);
  }

  /** 지금 고른 반경 — 접속하자마자 서버에 알려야 한다 */
  get radius(): number {
    return this.range;
  }

  setVisible(visible: boolean): void {
    this.root.classList.toggle('is-hidden', !visible);
    this.rangeBox.classList.toggle('is-hidden', !visible);
  }

  setOn(on: boolean): void {
    // !! 를 빼면 안 된다 — toggle 의 두 번째 인자가 undefined 면 강제 지정이
    // 아니라 뒤집기가 되어, 상태 패치마다 버튼이 깜빡인다.
    const next = !!on;
    this.root.classList.toggle('is-on', next);
    this.label.textContent = next ? '켜짐' : '꺼짐';
  }
}
