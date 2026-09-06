/**
 * 브라우저에서 UI 상태를 **글로** 뽑아내는 조각들.
 *
 * 스크린샷 대신 이걸 쓴다. 창이 가려져 있으면 requestAnimationFrame 이 멈춰서
 * 화면이 낡은 채로 굳고, 그 상태로 좌표를 찍어 클릭하면 엉뚱한 자리를 누른다.
 * DOM 은 그런 것과 무관하게 항상 지금 값을 들고 있다.
 *
 * 이 파일은 import 하는 게 아니라 **필요한 함수 본문을 골라 붙여 넣는 용도**다
 * (브라우저 콘솔 / javascript_tool). 마지막 줄의 값이 그대로 결과가 된다.
 *
 * rAF 로만 갱신되는 것(이름표 위치, 쿨타임 표시, 프롬프트)은 창이 가려져 있으면
 * 낡은 값이다. 그것들을 봐야 하면 창을 앞으로 꺼낸 뒤 같은 호출 안에서 읽는다.
 */

/** 전체 요약 — 어디에 있고 무엇이 열려 있나 */
const summary = () =>
  JSON.stringify({
    zone: document.title,
    hp: document.querySelector('.status-hp span')?.textContent,
    level: document.querySelector('.status-level')?.textContent,
    open: [...document.querySelectorAll('.bag, .npc, .sb')]
      .filter((e) => !e.classList.contains('is-hidden'))
      .map((e) => e.className),
    prompt: document.querySelector('.npc-prompt:not(.is-hidden)')?.textContent ?? null,
    autohunt: document.querySelector('.autohunt-state')?.textContent,
    target: document.querySelector('.nameplate.is-target .np-name')?.textContent ?? null,
    chat: [...document.querySelectorAll('.chat-line')].slice(-4).map((e) => e.textContent),
  });

/** 가방 — 칸마다 이름·등급·강화·옵션 */
const bag = () => {
  const bagEl = document.querySelector('.bag');
  return JSON.stringify({
    gold: bagEl.querySelector('.bag-gold')?.textContent,
    count: bagEl.querySelector('.bag-count')?.textContent,
    gear: bagEl.querySelector('.bag-gear-sum')?.textContent,
    equip: [...bagEl.querySelectorAll('.bag-slot')].map((e) => e.title),
    cells: [...bagEl.querySelectorAll('.bag-cell')].map((e) => e.title),
    detail: bagEl.querySelector('.bag-detail')?.textContent,
    options: [...bagEl.querySelectorAll('.bag-opt')].map((e) => [e.textContent, e.title]),
  });
};

/** NPC 창 — 섹션과 줄 */
const npc = () => {
  const el = document.querySelector('.npc');
  return JSON.stringify({
    open: !el.classList.contains('is-hidden'),
    title: el.querySelector('.npc-title')?.textContent,
    gold: el.querySelector('.npc-gold')?.textContent,
    sections: [...el.querySelectorAll('.npc-section')].map((e) => e.textContent),
    rows: [...el.querySelectorAll('.npc-row')].map((e) => e.textContent),
  });
};

/** 레이아웃 검사 — 화면 밖으로 밀려났거나 눌리지 않는 것 찾기 */
const layout = () => {
  const names = ['.actionbar', '.autohunt', '.autorange', '.npc-prompt', '.npc', '.bag', '.sb', '.status', '.chat'];
  return JSON.stringify({
    viewport: [innerWidth, innerHeight],
    parts: names.map((s) => {
      const e = document.querySelector(s);
      if (!e) return [s, '없음'];
      const b = e.getBoundingClientRect();
      const off = b.right > innerWidth || b.left < 0 || b.bottom > innerHeight || b.top < 0;
      return [s, getComputedStyle(e).pointerEvents, [b.left, b.top, b.right, b.bottom].map(Math.round), off ? '화면밖' : 'ok'];
    }),
  });
};

/** 히트 테스트 — 그 자리를 누르면 정말 그 버튼이 눌리나 */
const hitTest = (selector) => {
  const b = document.querySelector(selector).getBoundingClientRect();
  const el = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2);
  return JSON.stringify([selector, el ? el.tagName + '.' + el.className : '없음']);
};

/** 손가락 탭 흉내 — 실제 히트 테스트를 거쳐 누른다 */
const tap = (selector) => {
  const b = document.querySelector(selector).getBoundingClientRect();
  const x = b.left + b.width / 2;
  const y = b.top + b.height / 2;
  const el = document.elementFromPoint(x, y);
  for (const t of ['pointerdown', 'pointerup']) {
    el.dispatchEvent(new PointerEvent(t, { bubbles: true, clientX: x, clientY: y, pointerType: 'touch', isPrimary: true, button: 0 }));
  }
  el.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: x, clientY: y }));
  return `tapped ${selector} → ${el.tagName}.${el.className}`;
};
