import { FIELD_ORDER, bossLevel, getZone, tierLevels } from '@mmo/shared';

/**
 * 차원문 창 — 사냥터를 골라 바로 간다.
 *
 * 마을 차원문을 밟으면 열린다. 고르면 그 존의 `default` 스폰(한가운데)으로
 * 간다. 몬스터 무리는 네 귀퉁이(±20)에 있으므로 도착하자마자 둘러싸이지 않는다.
 *
 * **잠그지 않는다.** 존에 들어가는 것 자체는 원래도 서버가 막지 않았고
 * (클라이언트가 룸을 고른다), 여기서만 막으면 걸어서 가는 길로 우회하면
 * 그만이라 규칙이 아니라 불편이 된다. 대신 레벨대를 적어 주고 위험한 곳을
 * 표시한다 — 파워레벨링은 경험치 감쇠가 이미 막고 있다.
 */

/**
 * "상대할 만하다"고 보는 레벨 차이.
 *
 * `combat.test.ts` 가 레벨 곡선을 검사할 때 쓰는 값과 같은 눈금이다.
 * 여기만 따로 정하면 화면에 "적정" 이라고 떠 있는데 경험치는 거의 안 붙는
 * 구간이 생긴다.
 */
const REACH = 4;

type Fit = 'danger' | 'fit' | 'easy';

interface Row {
  root: HTMLButtonElement;
  tag: HTMLElement;
  /** 이 사냥터 약한 쪽 / 강한 쪽 몬스터 레벨 */
  weak: number;
  strong: number;
  fit: Fit | null;
}

const TAG_TEXT: Record<Fit, string> = { danger: '위험', fit: '적정', easy: '쉬움' };

export class ZoneGate {
  private readonly root: HTMLElement;
  private readonly rows: Row[] = [];
  private level = 1;

  /** 고른 사냥터로 데려간다 */
  onPick: ((zoneId: string) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'gate is-hidden';
    this.root.innerHTML = `
      <div class="gate-head">
        <span class="gate-title">차원문</span>
        <span class="gate-sub">사냥터를 골라 바로 갑니다</span>
        <button type="button" class="gate-close" aria-label="닫기">✕</button>
      </div>
      <div class="gate-list"></div>`;

    const list = this.root.querySelector('.gate-list') as HTMLElement;

    // 사냥터 목록은 바뀌지 않는다. 한 번만 만들고, 열 때마다 표시만 고친다.
    FIELD_ORDER.forEach((zoneId, index) => {
      const def = getZone(zoneId);
      const [weak, strong] = tierLevels(index);

      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'gate-row';
      row.innerHTML = `
        <span class="gate-name">${def.name}</span>
        <span class="gate-lv">Lv.${weak}~${strong} <b>보스 ${bossLevel(index)}</b></span>
        <span class="gate-tag"></span>`;
      row.addEventListener('click', () => {
        this.close();
        this.onPick?.(zoneId);
      });
      list.appendChild(row);

      this.rows.push({
        root: row,
        tag: row.querySelector('.gate-tag') as HTMLElement,
        weak,
        strong,
        fit: null,
      });
    });

    (this.root.querySelector('.gate-close') as HTMLElement).addEventListener('click', () =>
      this.close()
    );

    // 창 위에서 누른 것이 3D 로 새어 나가면 문 안에서 캐릭터가 움직인다
    for (const type of ['pointerdown', 'pointermove', 'pointerup', 'wheel']) {
      this.root.addEventListener(type, (e) => e.stopPropagation());
    }

    parent.appendChild(this.root);
  }

  get open(): boolean {
    return !this.root.classList.contains('is-hidden');
  }

  /**
   * 내 레벨. 표시가 달라질 때만 DOM 을 건드린다 —
   * 상태 패치마다(≈20Hz) 불리므로 매번 다시 쓰면 20줄이 계속 갈린다.
   */
  setLevel(level: number): void {
    if (level === this.level) return;
    this.level = level;
    this.refresh();
  }

  private refresh(): void {
    for (const row of this.rows) {
      const fit: Fit =
        this.level < row.weak - REACH ? 'danger' : this.level > row.strong + REACH ? 'easy' : 'fit';
      if (fit === row.fit) continue;
      row.fit = fit;
      row.tag.textContent = TAG_TEXT[fit];
      row.root.classList.toggle('is-danger', fit === 'danger');
      row.root.classList.toggle('is-easy', fit === 'easy');
      row.root.classList.toggle('is-fit', fit === 'fit');
    }
  }

  show(): void {
    this.refresh();
    this.root.classList.remove('is-hidden');
  }

  close(): void {
    this.root.classList.add('is-hidden');
  }
}
