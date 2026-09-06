import * as THREE from 'three';
import type { ZoneDef } from '@mmo/shared';
import { createGround, createPathMask, type Ground, type PathMask } from './ground';
import { createGrass, type GrassField } from './grass';
import { createPortal, type Portal } from './portal';
import { hash2 } from './palette';
import type { Assets } from './assets';
import type { CharacterRig } from '../game/characterRig';
import { createRig } from '../game/rigFactory';
import { CLASSES, type ClassId } from '../game/characterClasses';
import { NPC_LOOKS } from '../game/npcCharacters';

/**
 * 존 하나에 해당하는 씬 전체.
 *
 * 존을 넘어갈 때 통째로 붙였다 뗀다. dispose() 로 지오메트리/머티리얼을
 * 반드시 해제해야 한다 — 안 하면 존을 오갈 때마다 GPU 메모리가 샌다.
 */
export interface ZoneScene {
  def: ZoneDef;
  group: THREE.Group;
  /** 클릭 이동 레이캐스트 대상 */
  ground: THREE.Mesh;
  portals: Portal[];
  npcs: { name: string; subtitle?: string; hp: number; rig: CharacterRig }[];
  update(dt: number, elapsed: number): void;
  dispose(): void;
}

export function buildZoneScene(def: ZoneDef, assets: Assets): ZoneScene {
  const env = def.env;
  const group = new THREE.Group();
  group.name = 'zone:' + def.id;

  const mask: PathMask = createPathMask(env.roads);
  const blockers: { x: number; z: number; r: number }[] = [];
  const isBlocked = (x: number, z: number): boolean => {
    for (const b of blockers) {
      const dx = x - b.x;
      const dz = z - b.z;
      if (dx * dx + dz * dz < b.r * b.r) return true;
    }
    return false;
  };

  // 포탈 자리에는 풀도 나무도 두지 않는다
  for (const p of def.portals) {
    blockers.push({ x: p.position[0], z: p.position[1], r: p.radius + 1.5 });
  }

  // --- 지면 ---
  const ground: Ground = createGround(def.size, env, mask, assets);
  group.add(ground.mesh);

  // --- 잔디 ---
  const grass: GrassField = createGrass(env, mask, isBlocked);
  group.add(grass.mesh);

  // --- 포탈 ---
  const portals = def.portals.map((p) => {
    const portal = createPortal(p);
    group.add(portal.group);
    return portal;
  });

  // --- NPC ---
  const npcs = (def.npcs ?? []).map((n) => {
    // 고유 외형이 있으면 그걸 쓰고, 없으면 직업 외형으로 떨어진다
    const profile = (n.look ? NPC_LOOKS[n.look] : null) ?? CLASSES[n.job as ClassId] ?? CLASSES.knight;
    const rig = createRig(profile);
    rig.group.position.set(n.x, 0, n.z);
    rig.group.rotation.y = hash2(n.x, n.z) * Math.PI * 2;
    group.add(rig.group);
    return { name: n.name, subtitle: n.title, hp: n.hp ?? 100, rig };
  });

  return {
    def,
    group,
    ground: ground.mesh,
    portals,
    npcs,

    update(dt: number, elapsed: number): void {
      grass.update(elapsed);
      for (const portal of portals) portal.update(elapsed);
      for (const npc of npcs) npc.rig.update(dt, 0);
    },

    dispose(): void {
      grass.dispose();
      for (const portal of portals) portal.dispose();
      for (const npc of npcs) npc.rig.dispose();

      ground.dispose();
      group.clear();
    },
  };
}
