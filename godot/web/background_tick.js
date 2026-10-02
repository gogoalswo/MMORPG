// 탭을 옮겨도 게임이 멈추지 않게 한다 (웹 빌드 전용).
//
// 브라우저는 가려진 탭의 requestAnimationFrame 을 아예 부르지 않는다. 고도 웹 빌드는
// 그 신호로 한 프레임씩 돌기 때문에 판정(World.step)까지 같이 멈춘다.
// 그래서 가려졌을 때만 Web Worker 의 타이머로 박자를 대 준다 — 가려진 탭의 본 스레드
// 타이머는 1초에 한 번(5분 뒤엔 1분에 한 번)으로 묶이지만 워커가 보내는 메시지는 안 묶인다.
//
// 고도 엔진 스크립트보다 먼저 읽혀야 한다 → export_presets.cfg 의 html/head_include.
// 자세한 건 docs/features/godot-migration.md "탭을 옮겨도 멈추지 않는다".
(function () {
	"use strict";
	var HIDDEN_FPS = 20; // 가려졌을 때 박자. 판정만 돌면 되니 낮게 둔다
	var raf = window.requestAnimationFrame.bind(window);
	var caf = window.cancelAnimationFrame.bind(window);
	var pending = new Map(); // 우리 번호 → { cb, rafId }
	var seq = 0;
	var worker = null;

	function run(id, time) {
		var entry = pending.get(id);
		if (!entry) return;
		pending.delete(id);
		caf(entry.rafId);
		entry.cb(time);
	}

	// 진짜 rAF 와 워커 박자 중 먼저 오는 쪽이 한 번만 부른다.
	// 가려지기 직전에 걸어 둔 rAF 도 워커가 이어받아야 고리가 끊기지 않는다
	window.requestAnimationFrame = function (cb) {
		var id = ++seq;
		pending.set(id, { cb: cb, rafId: raf(function (t) { run(id, t); }) });
		return id;
	};
	window.cancelAnimationFrame = function (id) {
		var entry = pending.get(id);
		if (!entry) return;
		pending.delete(id);
		caf(entry.rafId);
	};

	function tick() {
		if (!document.hidden) return;
		var now = performance.now();
		Array.from(pending.keys()).forEach(function (id) { run(id, now); });
	}

	function sync() {
		if (document.hidden && !worker) {
			var src = "setInterval(function(){postMessage(0)}," + Math.round(1000 / HIDDEN_FPS) + ")";
			worker = new Worker(URL.createObjectURL(new Blob([src], { type: "text/javascript" })));
			worker.onmessage = tick;
		} else if (!document.hidden && worker) {
			worker.terminate();
			worker = null;
		}
	}

	document.addEventListener("visibilitychange", sync);
	sync();
})();
