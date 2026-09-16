import * as THREE from 'three';
import { INTERP_DELAY_MS, PLAYER_RADIUS, type Solid } from '@mmo/shared';
import {
  sampleRemote,
  lerpAngle,
  sameGear,
  EMPTY_GEAR,
  type GearLook,
  type RemoteEntity,
} from '../net/connection';
import type { CharacterRig, WeaponEdge } from './characterRig';
import { createRig } from './rigFactory';
import { CLASSES, type ClassId } from './characterClasses';
import type { NameplateLayer, NameplateTarget } from '../ui/nameplate';
import type { MapPoint } from '../ui/minimap';

interface Remote {
  entity: RemoteEntity;
  rig: CharacterRig;
  /** 마지막으로 그린 장비. 매 프레임 갈아끼우지 않으려고 기억해 둔다 */
  gear: GearLook;
  plate: NameplateTarget;
  /** 애니메이션 속도 계산용 직전 위치 */
  lastX: number;
  lastZ: number;
  /** 급변을 완화한 속도 */
  speed: number;
  spawned: boolean;
}

/**
 * 다른 플레이어들의 렌더링.
 *
 * 서버가 15Hz 로 보내는 위치를 그대로 찍으면 뚝뚝 끊긴다.
 * INTERP_DELAY_MS 만큼 과거를 재생하면서 스냅샷 사이를 보간한다.
 */
export class RemotePlayers {
  readonly group = new THREE.Group();

  private readonly remotes = new Map<string, Remote>();
  private readonly pointBuffer: MapPoint[] = [];
  private readonly solidBuffer: Solid[] = [];
  private readonly sample = { x: 0, z: 0, rotY: 0 };

  constructor(private readonly nameplates: NameplateLayer) {
    this.group.name = 'remote-players';
  }

  /** 현재 보이는 다른 플레이어 수 */
  get count(): number {
    return this.remotes.size;
  }

  /** 피해 숫자를 띄울 위치 */
  /** 미니맵이 찍을 자리 — 화면에 그려지는 자리를 쓴다. 배열은 다시 쓴다 */
  points(): MapPoint[] {
    this.pointBuffer.length = 0;
    for (const remote of this.remotes.values()) {
      const at = remote.rig.group.position;
      this.pointBuffer.push({ x: at.x, z: at.z });
    }
    return this.pointBuffer;
  }

  /**
   * 지나갈 수 없는 몸들 — 내 이동 예측이 쓴다. 몬스터 쪽(`RemoteMonsters.solids`)과 같은 규칙이다.
   *
   * **보간한 자리가 아니라 서버가 마지막으로 보낸 자리**를 쓴다. 서버도 그 값으로 밀어내므로,
   * 화면에 그리는 자리(`INTERP_DELAY_MS` 만큼 과거)를 쓰면 두 쪽 계산이 어긋나 보정이 튄다.
   * 다른 캐릭터는 몬스터와 달리 **실제로 움직이므로** 여기서는 차이가 늘 난다 — 반드시 마지막
   * 스냅샷이어야 한다.
   *
   * 죽은 캐릭터는 지나간다 (서버도 같이 뺀다). 배열은 다시 쓴다.
   */
  solids(): Solid[] {
    this.solidBuffer.length = 0;
    for (const remote of this.remotes.values()) {
      if (remote.entity.hp <= 0) continue;
      const last = remote.entity.buffer[remote.entity.buffer.length - 1];
      if (!last) continue;
      this.solidBuffer.push({ x: last.x, z: last.z, r: PLAYER_RADIUS });
    }
    return this.solidBuffer;
  }

  positionOf(id: string): THREE.Vector3 | null {
    return this.remotes.get(id)?.rig.group.position ?? null;
  }

  /** 바라보는 방향(모델 정면 +Z 기준 각) — 정면에서 나오는 스킬 그림에 쓴다 */
  facingOf(id: string): number | null {
    return this.remotes.get(id)?.rig.group.rotation.y ?? null;
  }

  swing(id: string): void {
    this.remotes.get(id)?.rig.swing();
  }

  /** 한 대 맞았다 — 안 보이는 사람이면 아무 일도 안 한다 */
  flash(id: string): void {
    this.remotes.get(id)?.rig.flash();
  }

  /** 궤적용 — 그 사람이 아직 보이면 무기 위치를 알려줄 것을 돌려준다 */
  weaponOf(id: string): WeaponEdge | null {
    return this.remotes.get(id)?.rig ?? null;
  }

  add(entity: RemoteEntity): void {
    if (this.remotes.has(entity.id)) return;

    const profile = CLASSES[entity.job as ClassId] ?? CLASSES.knight;
    const rig = createRig(profile);
    // 첫 스냅샷을 받기 전에는 원점에 서 있는 게 보이면 안 된다
    rig.group.visible = false;
    this.group.add(rig.group);

    const plate: NameplateTarget = {
      object: rig.group,
      headHeight: rig.headHeight,
      name: entity.name + ' (' + profile.label + ')',
      hp: entity.hp,
      maxHp: entity.maxHp,
    };
    this.nameplates.add(plate);

    const gear = entity.gear ?? EMPTY_GEAR;
    rig.setGear(gear);

    this.remotes.set(entity.id, {
      entity,
      rig,
      plate,
      gear,
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

      // 보간된 위치의 변화량으로 이동속도를 역산해 걷기/대기를 고른다.
      // 서버가 속도를 따로 보내지 않아도 되므로 대역폭이 절약된다.
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
      remote.rig.update(dt, remote.speed);
      remote.plate.hp = remote.entity.hp;

      // 남이 장비를 갈아입으면 손에 든 것도 바뀐다. 바뀐 프레임에만 손댄다.
      const gear = remote.entity.gear;
      if (gear && !sameGear(gear, remote.gear)) {
        remote.gear = gear;
        remote.rig.setGear(gear);
      }
    }
  }
}
