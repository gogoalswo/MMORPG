import { FIELD_ORDER, START_ZONE, bossLevel, getZone, tierLevels } from '@mmo/shared';

/**
 * 차원문 창 — 갈 곳을 골라 바로 간다.
 *
 * 차원문을 밟으면 열린다. 고르면 그 존의 `default` 스폰(한가운데)으로 간다.
 * 몬스터 무리는 네 귀퉁이(±20)에 있으므로 도착하자마자 둘러싸이지 않는다.
 *
 * **존을 오가는 유일한 길이다.** 걸어 들어가면 옆 존으로 넘어가던 사슬 포탈을
 * 없앴기 때문에, 목록에 **마을이 맨 위에** 있어야 한다. 없으면 사냥터에 들어간
 * 캐릭터가 죽는 것 말고는 돌아올 방법이 없다.
 *
 * **잠그지 않는다.** 존에 들어가는 것 자체는 원래도 서버가 막지 않았고
 * (클라이언트가 룸을 고른다), 여기서만 막으면 규칙이 아니라 불편이 된다.
 * 대신 레벨대를 적어 주고 위험한 곳을 표시한다 — 파워레벨링은 경험치 감쇠가
 * 이미 막고 있다.
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
  zoneId: string;
  root: HTMLButtonElement;
  tag: HTMLElement;
  /** 이 사냥터 약한 쪽 / 강한 쪽 몬스터 레벨. 마을은 null */
  levels: { weak: number; strong: number } | null;
  fit: Fit | null;
  current: boolean;
}

const TAG_TEXT: Record<Fit, string> = { danger: '위험', fit: '적정', easy: '쉬움' };

export class ZoneGate {
  private readonly root: HTMLElement;
  private readonly rows: Row[] = [];
  private level = 1;
  /** 아직 모른다. START_ZONE 으로 두면 첫 mountZone 의 setZone 이 그대로 지나간다 */
  private here = '';

  /** 고른 곳으로 데려간다 */
  onPick: ((zoneId: string) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'gate is-hidden';
    this.root.innerHTML = `
      <div class="gate-head">
        <span class="gate-title">차원문</span>
        <span class="gate-sub">갈 곳을 골라 바로 갑니다</span>
        <button type="button" class="gate-close" aria-label="닫기">✕</button>
      </div>
      <div class="gate-list"></div>`;

    const list = this.root.querySelector('.gate-list') as HTMLElement;

    // 목록은 바뀌지 않는다. 한 번만 만들고, 열 때마다 표시만 고친다.
    // 마을이 맨 위 — 돌아가는 길이 목록 끝에 있으면 20줄을 훑어야 찾는다.
    this.addRow(list, START_ZONE, null);
    FIELD_ORDER.forEach((zoneId, index) => {
      const [weak, strong] = tierLevels(index);
      this.addRow(list, zoneId, { weak, strong, boss: bossLevel(index) });
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

  private addRow(
    list: HTMLElement,
    zoneId: string,
    levels: { weak: number; strong: number; boss: number } | null
  ): void {
    const def = getZone(zoneId);
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'gate-row';
    row.innerHTML = `
      <span class="gate-name">${def.name}</span>
      <span class="gate-lv">${
        levels ? `Lv.${levels.weak}~${levels.strong} <b>보스 ${levels.boss}</b>` : '안전지대'
      }</span>
      <span class="gate-tag"></span>`;
    row.addEventListener('click', () => {
      // 지금 서 있는 곳을 고르면 존을 다시 세우기만 하고 아무 데도 안 간다
      if (zoneId === this.here) return;
      this.close();
      this.onPick?.(zoneId);
    });
    list.appendChild(row);

    this.rows.push({
      zoneId,
      root: row,
      tag: row.querySelector('.gate-tag') as HTMLElement,
      levels: levels && { weak: levels.weak, strong: levels.strong },
      fit: null,
      current: false,
    });
  }

  /**
   * 내 레벨. 표시가 달라질 때만 DOM 을 건드린다 —
   * 상태 패치마다(≈20Hz) 불리므로 매번 다시 쓰면 21줄이 계속 갈린다.
   */
  setLevel(level: number): void {
    if (level === this.level) return;
    this.level = level;
    this.refresh();
  }

  /** 지금 서 있는 존. 그 줄은 "현재" 로 표시하고 누를 수 없게 한다 */
  setZone(zoneId: string): void {
    if (zoneId === this.here) return;
    this.here = zoneId;
    this.refresh();
  }

  private refresh(): void {
    for (const row of this.rows) {
      const current = row.zoneId === this.here;
      if (current !== row.current) {
        row.current = current;
        row.root.classList.toggle('is-current', current);
        row.root.disabled = current;
      }

      // 마을에는 레벨대가 없다. "현재" 는 적정/위험보다 먼저 보여야 한다.
      if (current) {
        if (row.fit !== null || row.tag.textContent !== '현재') {
          row.fit = null;
          row.tag.textContent = '현재';
          row.root.classList.remove('is-danger', 'is-easy', 'is-fit');
        }
        continue;
      }
      if (!row.levels) {
        row.tag.textContent = '';
        continue;
      }

      const { weak, strong } = row.levels;
      const fit: Fit =
        this.level < weak - REACH ? 'danger' : this.level > strong + REACH ? 'easy' : 'fit';
      if (fit === row.fit) continue;
      row.fit = fit;
      row.tag.textContent = TAG_TEXT[fit];
      row.root.classList.toggle('is-danger', fit === 'danger');
      row.root.classList.toggle('is-easy', fit === 'easy');
      row.root.classList.toggle('is-fit', fit === 'fit');
    }
  }

  get open(): boolean {
    return !this.root.classList.contains('is-hidden');
  }

  show(): void {
    this.refresh();
    this.root.classList.remove('is-hidden');
  }

  close(): void {
    this.root.classList.add('is-hidden');
  }
}
