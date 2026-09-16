/**
 * 몬스터를 **몇 픽셀 안에서 클릭할 수 있는지** 브라우저 없이 세어 본다.
 *
 * "클릭이 잘 안 된다" 는 눈으로는 원인을 못 잡는다 — 빗나간 클릭은 그냥 이동이
 * 되어 버려서, 표적이 작은 것인지 판정이 없는 것인지 구분이 안 간다. 게다가
 * 브라우저 창이 가려지면 `requestAnimationFrame` 이 멈춰 화면과 좌표가 굳는다
 * (docs/features/verification.md). 그래서 카메라·히트박스·레이캐스트만 Node 에서
 * 그대로 세운다. 클릭 판정은 전부 계산이라 화면 없이도 답이 나온다.
 *
 * **상자 크기는 shared 의 `hitBoxSize` 를 그대로 쓴다.** ★ 예전에는 여기에 같은
 * 공식을 베껴 뒀는데, 실제 상자는 리그 배율이 한 번 더 곱해져 2.4 배였고
 * 프로브는 그걸 모른 채 "72×92픽셀, 넉넉하다" 를 찍고 있었다 (2026-09-15).
 *
 *   npm run hit-probe
 */
import * as THREE from 'three';
import {
  beastHeadHeight,
  getMonsterKind,
  hitBoxSize,
  monsterRadius,
} from '../packages/shared/src/index.ts';

// cameraRig.ts 와 같은 값 — 바뀌면 여기도 바꾼다
const FOV = 30;
const DISTANCE = 40;
const PITCH = THREE.MathUtils.degToRad(42);
const YAW = Math.PI / 4;
const FOCUS_HEIGHT = 1.0;

const W = 1920;
const H = 1080;

const camera = new THREE.PerspectiveCamera(FOV, W / H, 1, 400);
const focus = new THREE.Vector3(0, FOCUS_HEIGHT, 0);
const cosP = Math.cos(PITCH);
camera.position
  .set(cosP * Math.sin(YAW), Math.sin(PITCH), cosP * Math.cos(YAW))
  .multiplyScalar(DISTANCE)
  .add(focus);
camera.lookAt(focus);
camera.updateMatrixWorld(true);

const ray = new THREE.Raycaster();
const ndc = new THREE.Vector2();
const geo = new THREE.BoxGeometry(1, 1, 1);
const mat = new THREE.MeshBasicMaterial();

/** 화면에서 카메라 쪽으로 가는 방향 (여기서 멀어지면 뒷줄이다) */
const TOWARD_CAMERA = new THREE.Vector2(Math.sin(YAW), Math.cos(YAW));

/** 클라이언트가 만드는 것과 같은 상자를 그 자리에 세운다 */
function hitBox(id: string, x: number, z: number): THREE.Mesh {
  const kind = getMonsterKind(id);
  // 모델 리그가 실제로 쓰는 머리 높이. 절차적 리그로 떨어지면 조금 작다.
  const { w, h } = hitBoxSize(monsterRadius(kind.scale), beastHeadHeight(kind.look, kind.scale));
  const box = new THREE.Mesh(geo, mat);
  box.scale.set(w, h, w);
  box.position.set(x, h / 2, z);
  box.updateMatrixWorld(true);
  box.userData.size = `${w.toFixed(2)}m × ${h.toFixed(2)}m`;
  return box;
}

/**
 * 화면을 훑어 `want` 가 **가장 앞에서 맞는** 픽셀을 센다.
 *
 * 앞에 선 몬스터의 상자가 뒷놈을 덮으면 그 픽셀은 앞놈 것이다 — 실제 클릭도
 * 가장 가까운 것만 잡는다(`Input.pickTarget`).
 */
function count(scene: THREE.Mesh[], want: THREE.Mesh): { px: number; w: number; h: number } {
  // 4픽셀 간격으로 훑는다. 한 픽셀씩 보면 200만 번이라 느리고, 폭을 재는 데는 충분하다
  const STEP = 4;
  let hits = 0;
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  for (let py = 0; py < H; py += STEP) {
    for (let px = 0; px < W; px += STEP) {
      ndc.set((px / W) * 2 - 1, -(py / H) * 2 + 1);
      ray.setFromCamera(ndc, camera);
      const first = ray.intersectObjects(scene, false)[0];
      if (!first || first.object !== want) continue;
      hits++;
      minX = Math.min(minX, px);
      maxX = Math.max(maxX, px);
      minY = Math.min(minY, py);
      maxY = Math.max(maxY, py);
    }
  }
  if (hits === 0) return { px: 0, w: 0, h: 0 };
  return { px: hits * STEP * STEP, w: maxX - minX + STEP, h: maxY - minY + STEP };
}

function label(id: string): string {
  const kind = getMonsterKind(id);
  return `${id} ${kind.name}`.padEnd(20);
}

/** 한 마리만 세워 두고 표적 크기를 잰다 */
function alone(id: string, away: number): void {
  const box = hitBox(id, 0, -away);
  const r = count([box], box);
  if (r.px === 0) {
    console.log(`${label(id)} ${away}m 뒤: 화면 밖`);
    return;
  }
  console.log(
    `${label(id)} ${String(away).padStart(2)}m 뒤: 가로 ${String(r.w).padStart(3)}px × 세로 ${String(
      r.h
    ).padStart(3)}px (상자 ${box.userData.size})`
  );
}

/**
 * 무리 지어 서 있을 때 **뒷줄이 얼마나 남는가**.
 *
 * 앞줄과 겹쳐 선 것이 실제 사냥터 그림이다. 상자가 몸보다 크면 앞줄이 뒷줄을
 * 통째로 덮어, 뒤에 선 놈은 눌러도 앞놈이 잡힌다.
 */
function behind(id: string, gap: number): void {
  const front = hitBox(id, 0, 0);
  const d = TOWARD_CAMERA.clone().multiplyScalar(-gap);
  const back = hitBox(id, d.x, d.y);
  const solo = count([back], back);
  const covered = count([front, back], back);
  const left = solo.px > 0 ? Math.round((covered.px / solo.px) * 100) : 0;
  console.log(
    `${label(id)} ${gap}m 뒤에 한 마리 더: 뒷놈이 ${left}% 남는다 ` +
      `(혼자 ${solo.px}px² → 가려서 ${covered.px}px²)`
  );
}

console.log(`카메라 거리 ${DISTANCE} · FOV ${FOV} · 내림각 42° · ${W}×${H}`);
for (const id of ['mob003', 'mob008', 'boss00']) {
  alone(id, 3);
  alone(id, 9);
  behind(id, 2);
  behind(id, 3);
}
