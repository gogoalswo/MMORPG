/**
 * 남은 이펙트(캐릭터 피격)를 **브라우저 없이** 돌려 보고 결과를 글로 찍는다.
 *
 * 원래는 스킬 이펙트 전부를 보는 도구였다. 스킬 이펙트를 걷어내면서
 * (2026-09-16, `docs/features/skills.md`) 확인할 것이 `hurt` 하나만 남아 줄였다.
 *
 * 이펙트는 눈으로 봐야 하는 것이라 그동안 스크린샷으로 확인했는데, 두 가지가 문제였다.
 * 하나는 토큰이 비싸고, 다른 하나는 **창이 가려지면 `requestAnimationFrame` 이 멈춰서**
 * 화면이 낡은 채로 굳는다는 것이다 (그 상태로 찍으면 "이펙트가 안 나온다" 로 오진한다).
 *
 * `SkillFx` 가 하는 일은 사실 전부 계산이다 — 어디에, 얼마나 크게, 어느 방향으로,
 * 언제까지. 그러니 three 를 Node 에서 그대로 불러 `update(dt)` 를 돌리고 좌표를 찍으면
 * 화면 없이도 맞는지 틀리는지 알 수 있다. 안 되는 것은 **색과 그림의 생김새**뿐이라,
 * 그건 사람이 한 번 보면 된다.
 *
 * 쓰는 법:
 *   npm run fx-probe
 *
 * 그림(`hit.png`)은 `TextureLoader` 가 `document` 를 찾으므로 Node 에서 못 받는다.
 * 그 자리는 "그림 N장"으로만 세고 넘어간다.
 */
import * as THREE from 'three';
import { SkillFx } from '../packages/client/src/scene/skillFx.ts';

/**
 * 그림(스프라이트)은 `TextureLoader` 가 `document` 를 찾으므로 Node 에서 못 받는다.
 * 빈 텍스처를 돌려주고 몇 장인지만 센다 — 자리와 시간은 그대로 계산된다.
 * 모듈 객체는 읽기 전용이라 클래스는 못 갈아 끼우고, 프로토타입 메서드만 바꾼다.
 */
let spriteCount = 0;
THREE.TextureLoader.prototype.load = function load(): THREE.Texture {
  spriteCount += 1;
  return new THREE.Texture();
};

/**
 * 스킬 id, 또는 스킬과 무관한 이펙트 이름.
 * 지금 스킬이 아닌 것은 `hurt` 하나뿐이다 — 몬스터에게 맞았을 때 뜨는 발톱 자국.
 */
const at = new THREE.Vector3(0, 0, 0);

const fx = new SkillFx();

console.log('# 피격 (hurt)');
console.log('  맞은 자리 (0, 0) — 스킬과 무관한 피격 표시다');
// 연달아 맞는 상황을 본다. 같은 자리에 포개지면 한 장처럼 보이므로 흩어져야 한다
for (let i = 0; i < 3; i++) fx.hurt(at);

const meshes = fx.group.children as THREE.Object3D[];
console.log(`\n## 띄운 것 ${meshes.length}개 (그림 ${spriteCount}장)`);
for (const [i, m] of meshes.entries()) {
  const kind = (m as THREE.Mesh).isMesh ? '메시' : '그림';
  const deg = ((m.rotation.y * 180) / Math.PI).toFixed(0);
  console.log(
    `  ${i}: ${kind} 자리(${m.position.x.toFixed(2)}, ${m.position.y.toFixed(2)}, ${m.position.z.toFixed(2)})` +
      ` 크기 ${m.scale.x.toFixed(2)} 방향 ${deg}° ${m.visible ? '' : '(대기)'}`
  );
}

/** 60Hz 로 돌리며 0.1초마다 살아 있는 것들의 자리를 찍는다 */
console.log('\n## 시간에 따라 (0.1초 간격)');
const dt = 1 / 60;
let elapsed = 0;
let nextReport = 0;
for (let step = 0; step < 60 * 3; step++) {
  fx.update(dt);
  elapsed += dt;
  if (elapsed < nextReport) continue;
  nextReport += 0.1;

  const live = fx.group.children.filter((m) => m.visible);
  if (live.length === 0) {
    if (fx.group.children.length === 0) {
      console.log(`  ${elapsed.toFixed(2)}s — 전부 끝났다`);
      break;
    }
    console.log(`  ${elapsed.toFixed(2)}s — 아직 대기 중 ${fx.group.children.length}개`);
    continue;
  }

  const far = Math.max(...live.map((m) => Math.hypot(m.position.x, m.position.z)));
  // 위로 가는 이펙트(올려차기·천붕각의 발)는 높이로만 움직인다 — 거리만 보면 안 움직인 줄 안다
  const high = Math.max(...live.map((m) => m.position.y));
  const opacity = Math.max(
    ...live.map((m) => ((m as THREE.Mesh).material as THREE.Material & { opacity: number }).opacity)
  );
  const spread = live
    .map((m) => `(${m.position.x.toFixed(1)},${m.position.z.toFixed(1)})`)
    .join(' ');
  console.log(
    `  ${elapsed.toFixed(2)}s  살아있음 ${live.length}  가장 먼 것 ${far.toFixed(2)}m  가장 높은 것 ${high.toFixed(2)}m  밝기 ${opacity.toFixed(2)}  ${spread}`
  );
}

console.log('\n## 확인할 것');
console.log('  - 세 장이 같은 자리에 포개지지 않는가 (HURT.spread 0.35m 안에서 흩어진다)');
console.log('  - 높이가 가슴께(1.2m)에서 조금 올라가는가');
console.log('  - 밝기가 도중에 0 으로 꺼지지 않는가 (커질 때 투명해지면 화면에서 사라진다)');

fx.dispose();
