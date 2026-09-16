import { GODMODE_ALLOWED } from '@mmo/shared';

/**
 * 무적 모드 단추 (테스트 도구) — 화면 왼쪽, 스킬 디버그 목록 바로 위.
 *
 * 몬스터 공격 동작·피격 연출처럼 **맞아 가며 봐야 하는 것**을 확인할 때 쓴다.
 * 안 죽으니 죽음 화면과 부활 대기 5초를 왕복하지 않아도 된다.
 *
 * **켜졌는지는 서버가 정한다.** 여기서는 눌렀다고 색을 바꾸지 않고, 서버가
 * `godmode` 로 돌려준 값(`setOn`)만 그린다 — 스위치(`GODMODE_ALLOWED`)가 꺼져 있으면
 * 서버가 무시하므로, 미리 켜 두면 안 켜진 것을 켜졌다고 보여주게 된다.
 *
 * **스위치가 꺼지면 아예 안 보인다.** 테스트 도구가 실제 플레이 화면에 남아 있으면
 * 그때부터는 버그다 (스킬 디버그 목록과 같은 규칙).
 *
 * 존을 옮기면 룸이 새로 생겨 서버 쪽이 꺼진다. 다시 켜는 것은 `Connection` 이
 * 접속 직후에 알아서 한다 (단추는 그때도 서버가 돌려준 값만 그린다).
 */
export class GodMode {
  readonly root = document.createElement('button');

  /** 눌렀다 — 서버로 보내는 건 부르는 쪽(main.ts)이 한다 */
  onToggle?: (want: boolean) => void;

  /** 서버가 알려준 지금 상태 */
  private on = false;

  constructor(parent: HTMLElement) {
    this.root.type = 'button';
    this.root.className = 'godmode';
    if (!GODMODE_ALLOWED) this.root.classList.add('is-hidden');
    this.paint();
    this.root.addEventListener('click', () => this.onToggle?.(!this.on));
    parent.append(this.root);
  }

  /** 서버가 정한 값 */
  setOn(on: boolean): void {
    if (this.on === on) return;
    this.on = on;
    this.paint();
  }

  private paint(): void {
    this.root.classList.toggle('is-on', this.on);
    this.root.innerHTML = `<b>무적 ${this.on ? '켜짐' : '꺼짐'}</b><small>테스트</small>`;
  }
}
