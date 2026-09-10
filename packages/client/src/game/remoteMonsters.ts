import * as THREE from 'three';
import { INTERP_DELAY_MS, getMonsterKind } from '@mmo/shared';
import { lerpAngle, sampleRemote, type RemoteEntity } from '../net/connection';
import type { MonsterRig } from './monsterRig';
import { createMonster } from './rigFactory';
import type { NameplateLayer, NameplateTarget } from '../ui/nameplate';

interface Remote {
  entity: RemoteEntity;
  rig: MonsterRig;
  plate: NameplateTarget;
  lastX: number;
  lastZ: number;
  speed: number;
  spawned: boolean;
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

  constructor(private readonly nameplates: NameplateLayer) {
    this.group.name = 'monsters';
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

  /** 화면 좌표로 가장 가까운 몬스터를 찾는다 (클릭 대상 표시용) */
  positionOf(id: string): THREE.Vector3 | null {
    return this.remotes.get(id)?.rig.group.position ?? null;
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

  /** 지금 물고 있는 대상. 이름표를 밝혀 어느 놈인지 보여준다 */
  setHighlight(id: string | null): void {
    for (const [key, remote] of this.remotes) remote.plate.highlight = key === id;
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
  }
}
