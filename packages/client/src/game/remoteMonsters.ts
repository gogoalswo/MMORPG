import * as THREE from 'three';
import {
  INTERP_DELAY_MS,
  getMonsterKind,
  hitBoxSize,
  monsterRadius,
  type Solid,
} from '@mmo/shared';
import type { MapPoint } from '../ui/minimap';
import { lerpAngle, sampleRemote, type RemoteEntity } from '../net/connection';
import type { MonsterRig } from './monsterRig';
import { createMonster } from './rigFactory';
import type { NameplateLayer, NameplateTarget } from '../ui/nameplate';

/**
 * 겨눈 대상 발밑에 그리는 고리.
 *
 * 이름표 금색(`.nameplate.is-target`)만으로는 난전에서 어느 놈을 물었는지 안 보인다.
 * 이름표는 머리 위에 여럿이 겹쳐 뜨는데, **발밑은 한 놈에 하나뿐**이라 눈이 바로 간다.
 *
 * 수치는 카메라(거리 40 · FOV 30 → 화면 세로 21유닛)에 맞춘 것이다. 스킬 이펙트에서
 * 한 번 겪은 것과 같은 문제다 — 얇으면 1080p 에서 몇 픽셀이라 배경에 묻힌다
 * (docs/features/skills.md 의 이펙트 절).
 */
const TARGET_RING = {
  /** 이름표 하이라이트와 같은 금색 (style.css 의 `.nameplate.is-target`) */
  color: 0xffd36b,
  /**
   * 테 두께 — **비율이 아니라 미터다.** ★
   *
   * 처음엔 반지름의 24% 로 잡았는데, 들늑대(몸반지름 0.38m)에서 테가 0.12m =
   * **1080p 에서 6픽셀**이었다. 스킬 고리에서 이미 겪은 것과 같다 — 작은 놈일수록
   * 얇아져서 정작 자주 보는 몬스터에서 안 보인다. 지금은 몬스터 크기와 무관하게
   * 0.22m 고정이고, 이 카메라에서 1080p 11픽셀 · 800p 8픽셀이다.
   */
  thickness: 0.22,
  /** 몸 반지름의 몇 배로 그릴지. 발끝보다 조금 밖이어야 "딛고 선" 것으로 보인다 */
  scale: 1.3,
  /** 지면 위로 띄우는 높이 — 0 이면 바닥과 z-fighting 으로 깜빡인다 */
  y: 0.03,
  /** 맥동 (반지름 대비 비율, Hz). 가만히 있으면 바닥 무늬로 보인다 */
  pulse: 0.05,
  pulseHz: 1.4,
};

/**
 * 클릭 판정용 상자.
 *
 * 크기(`hitBoxSize`)와 그 이유는 shared 에 있다 — `scripts/hit-probe.ts` 가 같은
 * 함수로 재야 프로브가 실제와 같은 상자를 본다.
 *
 * 여기서 정하는 건 **어떻게 안 그릴 것인가** 다. `colorWrite: false` 라 화면에는
 * 안 그려지지만 레이캐스트는 된다 — `visible = false` 로 하면 레이캐스터가
 * 통째로 건너뛰므로 그 방법은 못 쓴다.
 */

/** 상자는 전부 같은 것을 쓰고 크기는 scale 로 맞춘다 — 몬스터마다 만들면 버릴 것이 는다 */
const HIT_GEO = new THREE.BoxGeometry(1, 1, 1);
const HIT_MAT = new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false });

interface Remote {
  entity: RemoteEntity;
  rig: MonsterRig;
  plate: NameplateTarget;
  lastX: number;
  lastZ: number;
  speed: number;
  spawned: boolean;
  /** 지나갈 수 없는 몸의 반지름. 종류마다 고정이라 만들 때 한 번 구해 둔다 */
  radius: number;
}

/**
 * 몬스터 렌더링.
 *
 * 플레이어와 같은 원리다 — 서버가 15Hz 로 보내는 위치를 그대로 찍으면 끊기므로
 * INTERP_DELAY_MS 만큼 과거를 재생하며 보간한다.
 */
export class RemoteMonsters {
  readonly group = new THREE.Group();

  private readonly remotes = new Map<string, Remote>();
  private readonly sample = { x: 0, z: 0, rotY: 0 };
  /** 겨눈 대상 발밑 고리 — 하나만 만들어 대상이 바뀔 때마다 옮긴다 */
  private readonly ring: THREE.Mesh;
  private ringFor: string | null = null;
  private ringTime = 0;
  private readonly solidBuffer: Solid[] = [];
  private readonly pointBuffer: MapPoint[] = [];

  constructor(private readonly nameplates: NameplateLayer) {
    this.group.name = 'monsters';

    // 지오메트리는 대상이 바뀔 때 그 몬스터 크기로 다시 만든다(`shapeRing`).
    // scale 로 키우면 테 두께까지 같이 스케일되어 작은 놈에서 실선이 된다.
    this.ring = new THREE.Mesh(
      new THREE.RingGeometry(0.5, 0.7, 48),
      new THREE.MeshBasicMaterial({
        color: TARGET_RING.color,
        transparent: true,
        opacity: 0.85,
        // 어두운 사냥터에서도 같은 밝기로 읽히도록 가산 혼합. 바닥에 겹쳐 그리므로
        // 깊이는 읽되 쓰지 않는다 — 써 두면 뒤에 오는 반투명이 잘려 나간다.
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        side: THREE.DoubleSide,
      })
    );
    this.ring.rotation.x = -Math.PI / 2;
    this.ring.visible = false;
    this.ring.renderOrder = 5;
    // 클릭 레이캐스트가 몬스터 그룹을 훑으므로 고리는 아예 빼 둔다
    this.ring.raycast = () => {};
    // 가산 혼합은 GTAO 가 검은 네모로 그린다 (docs/features/skills.md)
    this.ring.userData.noAO = true;
    this.group.add(this.ring);
  }

  get count(): number {
    return this.remotes.size;
  }

  add(entity: RemoteEntity): void {
    if (this.remotes.has(entity.id)) return;

    let kind;
    try {
      kind = getMonsterKind(entity.job); // job 필드에 몬스터 종류가 담겨 온다
    } catch {
      return; // 서버가 새 몬스터를 추가했는데 클라가 구버전인 경우
    }

    const rig = createMonster(kind);
    rig.group.visible = false;
    // 클릭한 메시에서 어느 몬스터인지 되찾는 표식. 부모를 타고 올라가며 찾는다.
    rig.group.userData.monsterId = entity.id;
    rig.group.add(makeHitBox(monsterRadius(kind.scale), rig.headHeight, rig.group.scale.x));
    this.group.add(rig.group);

    const plate: NameplateTarget = {
      object: rig.group,
      headHeight: rig.headHeight,
      name: `${kind.name} Lv.${kind.level}`,
      hp: entity.hp,
      maxHp: entity.maxHp,
    };
    this.nameplates.add(plate);

    this.remotes.set(entity.id, {
      entity,
      rig,
      plate,
      lastX: 0,
      lastZ: 0,
      speed: 0,
      spawned: false,
      radius: monsterRadius(kind.scale),
    });
  }

  remove(id: string): void {
    const remote = this.remotes.get(id);
    if (!remote) return;
    this.group.remove(remote.rig.group);
    remote.rig.dispose();
    this.nameplates.remove(remote.plate);
    this.remotes.delete(id);
  }

  clear(): void {
    for (const id of [...this.remotes.keys()]) this.remove(id);
  }

  /**
   * 지나갈 수 없는 몸들 — 내 이동 예측이 쓴다.
   *
   * **보간한 자리가 아니라 서버가 마지막으로 보낸 자리**를 쓴다. 서버도 그 값으로
   * 밀어내므로, 여기서 화면에 그리는 자리(`INTERP_DELAY_MS` 만큼 과거)를 쓰면 두 쪽
   * 계산이 어긋나 보정이 튄다. 몬스터는 제자리에 서 있어서 평소엔 둘이 같지만,
   * 어긋나는 날을 만들 이유가 없다.
   *
   * 죽은 것은 뺀다 — 시체에 막히면 "왜 안 가지" 가 된다 (서버도 같이 뺀다).
   * 배열은 다시 쓴다. 매 프레임 새로 만들면 그만큼 쓰레기가 쌓인다.
   */
  solids(): Solid[] {
    this.solidBuffer.length = 0;
    for (const remote of this.remotes.values()) {
      if (remote.entity.hp <= 0) continue;
      const last = remote.entity.buffer[remote.entity.buffer.length - 1];
      if (!last) continue;
      this.solidBuffer.push({ x: last.x, z: last.z, r: remote.radius });
    }
    return this.solidBuffer;
  }

  /**
   * 미니맵이 찍을 자리 — 살아 있는 것만. 배열은 다시 쓴다.
   *
   * 여기서는 **화면에 그려지는 자리**(보간된 것)를 쓴다. 충돌(`solids`)과 반대인데,
   * 저쪽은 서버와 계산을 맞춰야 하고 이쪽은 눈에 보이는 것과 맞아야 하기 때문이다.
   */
  points(): MapPoint[] {
    this.pointBuffer.length = 0;
    for (const remote of this.remotes.values()) {
      if (remote.entity.hp <= 0) continue;
      const at = remote.rig.group.position;
      this.pointBuffer.push({ x: at.x, z: at.z });
    }
    return this.pointBuffer;
  }

  /** 화면 좌표로 가장 가까운 몬스터를 찾는다 (클릭 대상 표시용) */
  positionOf(id: string): THREE.Vector3 | null {
    return this.remotes.get(id)?.rig.group.position ?? null;
  }

  /**
   * 반경 안에서 가장 가까운 살아 있는 몬스터. 없으면 null.
   *
   * 조준 없이 스킬을 눌렀을 때 **서버가 고를 놈과 같은 놈**을 미리 보고 그쪽으로
   * 몸을 돌리려고 쓴다 (서버는 `ZoneRoom.acquireTarget`). 그래서 보간된 위치가
   * 아니라 `solids()` 와 같은 **서버가 준 마지막 좌표**로 잰다 — 판정이 그 좌표로
   * 나기 때문이다.
   */
  nearest(x: number, z: number, range: number): string | null {
    let bestId: string | null = null;
    let best = range;
    for (const [id, remote] of this.remotes) {
      if (remote.entity.hp <= 0) continue;
      const last = remote.entity.buffer[remote.entity.buffer.length - 1];
      if (!last) continue;
      const dist = Math.hypot(last.x - x, last.z - z);
      if (dist < best) {
        best = dist;
        bestId = id;
      }
    }
    return bestId;
  }

  /**
   * 레이캐스트로 맞은 메시가 어느 몬스터인지.
   *
   * 맞는 건 팔·다리 같은 부품이라 표식은 뿌리에만 있다. 부모를 타고 올라간다.
   * 죽은 몬스터는 고를 수 없다 — 시체를 눌러놓고 안 때린다고 하면 곤란하다.
   */
  idAt(object: THREE.Object3D): string | null {
    for (let node: THREE.Object3D | null = object; node; node = node.parent) {
      const id = node.userData.monsterId as string | undefined;
      if (!id) continue;
      const remote = this.remotes.get(id);
      return remote && remote.entity.hp > 0 ? id : null;
    }
    return null;
  }

  /** 한 대 맞았다 — 이미 시야에서 빠진 놈이면 아무 일도 안 한다 */
  flash(id: string): void {
    this.remotes.get(id)?.rig.flash();
  }

  /**
   * 한 번 휘두른다. 서버가 사람을 때렸다고 알려준 순간(`hit`) 부른다.
   *
   * **모르는 id 면 아무 일도 안 한다** — 부르는 쪽(`main.ts` 의 `onHit`)은 때린 게
   * 몬스터인지 사람인지 가리지 않고 넘긴다. 여기서 없으면 몬스터가 아닌 것이다.
   */
  swing(id: string): void {
    this.remotes.get(id)?.rig.swing();
  }

  /** 지금 겨누는 대상. 이름표를 밝히고 발밑에 고리를 놓는다 */
  setHighlight(id: string | null): void {
    for (const [key, remote] of this.remotes) remote.plate.highlight = key === id;

    const remote = id ? this.remotes.get(id) : undefined;
    this.ringFor = remote ? id : null;
    // 자리를 잡는 건 update 가 한다. 여기서 켜면 한 프레임 동안 옛 자리에 뜬다.
    this.ring.visible = false;
    if (remote) {
      this.ringTime = 0;
      this.shapeRing(remote.radius);
    }
  }

  /**
   * 그 몬스터 몸에 맞춰 고리를 다시 만든다.
   *
   * 대상이 바뀔 때만 부르므로(사람이 클릭할 때뿐) 지오메트리를 새로 만들어도 된다.
   * 옛 것은 반드시 버린다 — 사냥 한 판이면 수백 번 바뀐다.
   */
  private shapeRing(radius: number): void {
    const outer = radius * TARGET_RING.scale;
    const inner = Math.max(0.05, outer - TARGET_RING.thickness);
    this.ring.geometry.dispose();
    this.ring.geometry = new THREE.RingGeometry(inner, outer, 48);
  }

  update(dt: number): void {
    const renderTime = performance.now() - INTERP_DELAY_MS;

    for (const remote of this.remotes.values()) {
      if (!sampleRemote(remote.entity, renderTime, this.sample)) continue;
      const { x, z, rotY } = this.sample;

      if (!remote.spawned) {
        remote.spawned = true;
        remote.rig.group.visible = true;
        remote.lastX = x;
        remote.lastZ = z;
      }

      if (dt > 0) {
        const moved = Math.hypot(x - remote.lastX, z - remote.lastZ) / dt;
        remote.speed += (moved - remote.speed) * (1 - Math.exp(-10 * dt));
      }
      remote.lastX = x;
      remote.lastZ = z;

      remote.rig.group.position.set(x, 0, z);
      remote.rig.group.rotation.y = lerpAngle(
        remote.rig.group.rotation.y,
        rotY,
        1 - Math.exp(-12 * dt)
      );
      remote.rig.update(dt, remote.entity.state ?? 'idle', remote.speed);

      remote.plate.hp = remote.entity.hp;
      // 죽은 몬스터의 이름표는 숨긴다
      remote.plate.hidden = remote.entity.hp <= 0;
    }

    this.updateRing(dt);
  }

  /**
   * 겨눈 놈 발밑으로 고리를 옮긴다 — **몬스터를 그린 뒤에** 부른다.
   *
   * 고리를 몬스터 리그에 자식으로 붙이지 않는 이유: 리그는 회전하고 종류마다
   * 크기 보정이 달라서, 붙이면 고리가 같이 돌고 찌그러진다. 자리만 따라간다.
   *
   * 대상이 죽거나 시야에서 빠지면 서버가 조준을 풀어 주지만(`sweepTargets`),
   * 그 한 틱 동안 시체 발밑에 고리가 남는다. 여기서도 본다.
   */
  private updateRing(dt: number): void {
    const remote = this.ringFor ? this.remotes.get(this.ringFor) : undefined;
    if (!remote || !remote.spawned || remote.entity.hp <= 0) {
      this.ring.visible = false;
      return;
    }

    this.ringTime += dt;
    const at = remote.rig.group.position;
    this.ring.position.set(at.x, TARGET_RING.y, at.z);

    // 맥동은 scale 로만 준다. 폭이 ±5% 라 테 두께가 같이 흔들려도 눈에 안 걸린다.
    const pulse = 1 + Math.sin(this.ringTime * Math.PI * 2 * TARGET_RING.pulseHz) * TARGET_RING.pulse;
    this.ring.scale.setScalar(pulse);
    this.ring.visible = true;
  }
}

/**
 * 몸 크기에 맞춘 클릭 판정 상자를 만든다.
 *
 * 리그의 자식으로 붙으므로 몬스터를 따라 움직이고 같이 돈다 — 상자는 대칭이라
 * 돌아도 상관없다. 표식(`monsterId`)은 뿌리에만 있고 `idAt` 이 부모를 타고
 * 올라가 찾으므로, 상자에는 아무것도 안 붙여도 된다.
 *
 * **리그 그룹에 걸린 배율(`rigScale`)로 나눠서 붙인다.** ★ 모델 리그는 파일
 * 단위를 세계에 맞추려고 그룹을 통째로 키우고(오우거는 2.4 배), 절차적 리그는
 * `kind.scale` 을 건다. 월드 미터로 잰 크기를 그냥 넣으면 그 배율이 한 번 더
 * 곱해져서, 오우거 상자가 폭 2.5m · 높이 7m 가 된다 — 머리 위 허공과 옆 땅까지
 * 클릭을 먹고, 앞줄 몬스터가 뒷줄을 가려서 **뒤에 선 놈이 안 찍혔다**.
 */
function makeHitBox(radius: number, headHeight: number, rigScale: number): THREE.Mesh {
  const { w, h } = hitBoxSize(radius, headHeight);
  const s = rigScale || 1;
  const box = new THREE.Mesh(HIT_GEO, HIT_MAT);
  box.scale.set(w / s, h / s, w / s);
  // 발밑(y=0)에서 머리까지 세운다
  box.position.y = h / 2 / s;
  // 안 그려지는 것이라 음영 계산에도 넣지 않는다 (GTAO 는 깊이를 다시 그린다)
  box.userData.noAO = true;
  box.renderOrder = -1;
  return box;
}
