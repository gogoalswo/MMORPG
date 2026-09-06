// ==UserScript==
// @name         모닥 온라인 - 스킬 자동 사용 (Q W E R)
// @namespace    local.modak.autoskill
// @version      2.3
// @description  Q,W,E,R 스킬을 짧은 간격으로 순환 사용 (왼쪽 아래 버튼 또는 F8)
// @match        *://modakmmo.com/*
// @match        *://*.modakmmo.com/*
// @noframes
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
    'use strict';

    console.log('%c[AutoSkill] 스크립트 실행됨 v2.3', 'color:#4caf50;font-weight:bold');

    // ===== 설정 =====
    // 게임 스킬 슬롯 1~4 = Q, W, E, R
    // 특정 스킬을 더 자주 쓰려면 중복해서 넣으세요. 예: ['Q','W','Q','E','Q','R']
    const KEYS = ['Q', 'W', 'E', 'R'];
    let INTERVAL = 150;      // 키와 키 사이 간격(ms)
    const TOGGLE_KEY = 'F8'; // 시작/정지 단축키
    // ===============
    //
    // 참고: 게임 내부에 "같은 스킬 250ms 재사용 제한 + 쿨다운" 이 있어서
    // 한 바퀴(4키)가 250ms보다 짧아지면 일부 입력은 그냥 무시됩니다.
    // INTERVAL 은 70 이상이면 손해 없음. 더 줄여도 빨라지지 않습니다.

    const CODE = { Q: 'KeyQ', W: 'KeyW', E: 'KeyE', R: 'KeyR' };
    const KEYCODE = { Q: 81, W: 87, E: 69, R: 82 };

    let running = false;
    let timer = null;
    let idx = 0;

    function fire(type, k) {
        const ev = new KeyboardEvent(type, {
            key: k.toLowerCase(),
            code: CODE[k],
            keyCode: KEYCODE[k],
            which: KEYCODE[k],
            bubbles: true,
            cancelable: true,
            composed: true,
        });
        Object.defineProperty(ev, 'keyCode', { get: () => KEYCODE[k] });
        Object.defineProperty(ev, 'which', { get: () => KEYCODE[k] });
        // window 에만 한 번 발송한다.
        //  - 게임 리스너가 window(keydown) 하나뿐이라 이걸로 충분하고
        //  - target 이 window 라서 "입력창에 포커스" 판정에 걸리지 않는다.
        //  - 여러 곳에 뿌리면 버블링 때문에 한 번에 2~3회 발동된다.
        window.dispatchEvent(ev);
    }

    // 채팅/입력창에 포커스가 있으면 쉬어간다 (게임 기본 동작과 동일하게)
    function typing() {
        const el = document.activeElement;
        return !!(el && el.closest &&
            el.closest('input, textarea, select, [contenteditable="true"]'));
    }

    function step() {
        if (!running || typing()) return;
        const k = KEYS[idx];
        fire('keydown', k);
        setTimeout(() => fire('keyup', k), 30);
        idx = (idx + 1) % KEYS.length;
    }

    // 숨겨진 탭에서는 setTimeout 이 1초 이상으로 강제 지연된다.
    // Worker 안의 타이머는 그 제한을 덜 받으므로 박자를 Worker 에서 만든다.
    let worker = null;
    try {
        const src = 'let id=null;onmessage=function(e){' +
            'if(e.data.cmd==="start"){clearInterval(id);id=setInterval(function(){postMessage(0);},e.data.ms);}' +
            'else if(e.data.cmd==="stop"){clearInterval(id);id=null;}};';
        worker = new Worker(URL.createObjectURL(new Blob([src], { type: 'text/javascript' })));
        worker.onmessage = step;
    } catch (err) {
        console.warn('[AutoSkill] Worker 사용 불가, setTimeout 으로 대체:', err);
    }

    function tick() { if (!running) return; step(); timer = setTimeout(tick, INTERVAL); }

    function start() {
        if (running) return;
        running = true; idx = 0;
        if (worker) worker.postMessage({ cmd: 'start', ms: INTERVAL });
        else tick();
        updateUI();
    }
    function stop() {
        running = false;
        if (worker) worker.postMessage({ cmd: 'stop' });
        clearTimeout(timer);
        updateUI();
    }
    function toggle() { running ? stop() : start(); }

    // ===== 왼쪽 아래 패널 =====
    const box = document.createElement('div');
    box.style.cssText = [
        'position:fixed', 'left:12px', 'bottom:12px', 'z-index:2147483647',
        'background:rgba(0,0,0,.82)', 'color:#fff', 'font:12px/1.6 monospace',
        'padding:8px', 'border-radius:8px', 'user-select:none',
        'display:flex', 'flex-direction:column', 'gap:6px', 'width:150px',
        'box-shadow:0 2px 10px rgba(0,0,0,.5)', 'cursor:move',
    ].join(';');
    box.innerHTML =
        '<button id="as-btn" style="' +
            'width:100%;padding:9px 0;border:0;border-radius:6px;cursor:pointer;' +
            'font:bold 14px/1 monospace;color:#fff">매크로 OFF</button>' +
        '<div id="as-state" style="opacity:.75;text-align:center">F8 로도 켜고 끕니다</div>' +
        '<div style="display:flex;align-items:center;gap:4px;justify-content:center">' +
            '간격<input id="as-int" type="number" min="70" step="10" ' +
            'style="width:52px;background:#222;color:#fff;border:1px solid #555;' +
            'border-radius:3px;text-align:right" value="' + INTERVAL + '">ms</div>';

    function updateUI() {
        const btn = box.querySelector('#as-btn');
        const st = box.querySelector('#as-state');
        if (!btn) return;
        btn.textContent = running ? '매크로 ON' : '매크로 OFF';
        btn.style.background = running ? '#2e7d32' : '#555';
        st.textContent = !running
            ? 'F8 로도 켜고 끕니다'
            : (document.hidden ? '▶ 백그라운드 실행중' : '▶ ' + KEYS.join(' ') + ' 순환중');
    }

    (function mount() {
        if (!document.body) return setTimeout(mount, 300);
        document.body.appendChild(box);

        box.querySelector('#as-btn').addEventListener('click', function (e) {
            e.stopPropagation();
            toggle();
            this.blur(); // 포커스가 남으면 Enter/Space 로 다시 눌리므로 해제
        });
        box.querySelector('#as-int').addEventListener('change', (e) => {
            const v = parseInt(e.target.value, 10);
            if (isNaN(v) || v < 70) return;
            INTERVAL = v;
            if (running && worker) worker.postMessage({ cmd: 'start', ms: INTERVAL });
        });
        // 패널 안에서 누른 키가 게임으로 새지 않게
        box.addEventListener('keydown', (e) => e.stopPropagation());
        // 패널 위 클릭이 게임 화면(이동/타겟)으로 전달되지 않게
        box.addEventListener('pointerdown', (e) => e.stopPropagation());

        // 게임 UI를 가리면 드래그해서 옮기기
        let dx = 0, dy = 0, dragging = false;
        box.addEventListener('mousedown', (e) => {
            if (e.target.closest('button, input')) return;
            const r = box.getBoundingClientRect();
            dx = e.clientX - r.left; dy = e.clientY - r.top;
            dragging = true; e.preventDefault();
        });
        window.addEventListener('mousemove', (e) => {
            if (!dragging) return;
            box.style.left = (e.clientX - dx) + 'px';
            box.style.top = (e.clientY - dy) + 'px';
            box.style.bottom = 'auto';
        });
        window.addEventListener('mouseup', () => { dragging = false; });

        updateUI();
    })();

    // ===== 단축키 =====
    window.addEventListener('keydown', function (e) {
        if (e.key === TOGGLE_KEY) { e.preventDefault(); toggle(); }
    }, true);

    // SPA 화면 전환 등으로 패널이 사라지면 다시 붙인다
    setInterval(() => {
        if (document.body && !document.body.contains(box)) {
            document.body.appendChild(box);
            console.log('[AutoSkill] 패널 재부착');
        }
    }, 2000);

    // 탭을 벗어나도 정지하지 않는다. 상태 표시만 갱신.
    document.addEventListener('visibilitychange', updateUI);
})();
