/**
 * 존 전환 화면.
 *
 * 존 구성은 지면 텍스처 생성(1024² 픽셀 루프)과 잔디 6만 개 배치 때문에
 * 수백 ms 동안 메인 스레드를 잡는다. 그 사이 화면이 얼어붙으므로
 * 페이드가 실제로 그려진 뒤에 작업을 시작해야 한다.
 */
export class ZoneTransition {
  private readonly el: HTMLDivElement;
  private readonly title: HTMLDivElement;
  private busy = false;

  constructor(root: HTMLElement) {
    this.el = document.createElement('div');
    this.el.className = 'zone-fade';
    this.title = document.createElement('div');
    this.title.className = 'zone-fade-title';
    this.el.appendChild(this.title);
    root.appendChild(this.el);
  }

  get running(): boolean {
    return this.busy;
  }

  async run(zoneName: string, work: () => void | Promise<void>): Promise<void> {
    if (this.busy) return;
    this.busy = true;

    this.title.textContent = zoneName;
    this.el.classList.add('is-visible');
    await wait(320); // 페이드 아웃이 끝날 때까지

    // 페이드가 화면에 반영된 프레임을 한 번 흘려보낸 뒤에 무거운 작업을 한다
    await nextFrame();
    await nextFrame();

    // 존을 세우는 데 모델을 더 받아야 할 수도 있다. 그동안 화면은 덮여 있다.
    await work();

    // 새 존의 첫 프레임이 그려지고 나서 걷는다
    await nextFrame();
    await wait(120);
    this.el.classList.remove('is-visible');
    await wait(320);
    this.busy = false;
  }
}

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * 다음 프레임을 기다리되 타임아웃을 건다.
 * 탭이 백그라운드로 가면 requestAnimationFrame 이 멈춰서
 * 그냥 기다리면 로딩 화면에 갇힌다.
 */
function nextFrame(timeoutMs = 250): Promise<void> {
  return Promise.race([
    new Promise<void>((resolve) => requestAnimationFrame(() => resolve())),
    wait(timeoutMs),
  ]);
}
