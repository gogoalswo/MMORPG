import { randomUUID } from 'node:crypto';
import {
  ATTACK_ARC,
  SpatialGrid,
  computeDamage,
  rollCrit,
  BASE_CRIT_DAMAGE,
  getMonsterKind,
  type MonsterKind,
  type MonsterSpawnDef,
  type ZoneDef,
} from '@mmo/shared';
import { Monster, type MonsterState, type PlayerState } from './state.ts';

/**
 * 몬스터 스폰과 AI.
 *
 * **전부 서버에서만 돈다.** 클라이언트는 결과(위치·HP·상태)만 받아 그린다.
 * 클라이언트가 "내가 몬스터를 죽였다"고 말하는 걸 믿으면 게임이 성립하지 않는다.
 */

/** 몬스터 하나의 서버 전용 정보 (네트워크로 보내지 않는 것들) */
interface MonsterRuntime {
  state: MonsterState;
  kind: MonsterKind;
  /** 무리 중심 — 여기서 너무 멀어지면 돌아간다 */
  homeX: number;
  homeZ: number;
  spawn: MonsterSpawnDef;
  targetId: string | null;
  nextAttackAt: number;
  /** 죽은 뒤 다시 나올 시각 (0 이면 살아 있음) */
  respawnAt: number;
  /** 다음 범위 공격을 시작해도 되는 시각 */
  nextAoeAt: number;
  /**
   * 예고한 범위 공격이 터지는 시각 (0 이면 시전 중이 아니다).
   *
   * 시전을 시작한 자리를 함께 붙잡아 둔다. 터질 때 몬스터의 **현재** 위치를
   * 쓰면 예고한 원과 실제로 맞는 자리가 어긋나서 피할 수가 없다.
   */
  aoeBurstAt: number;
  aoeX: number;
  aoeZ: number;
}

/** 몬스터 AI 한 틱에서 방으로 올려보내는 일들 */
export interface MonsterEvents {
  /** 평타가 들어갔다 */
  hitPlayer(player: PlayerState, monster: MonsterState, kind: MonsterKind): void;
  /** 범위 공격 예고 — 클라이언트에 원을 그리라고 알린다 */
  aoeCast(monster: MonsterState, kind: MonsterKind, x: number, z: number): void;
  /** 범위 공격이 터졌다 — 원 안의 플레이어를 방이 훑어서 피해를 준다 */
  aoeBurst(monster: MonsterState, kind: MonsterKind, x: number, z: number): void;
}

export interface HitEvent {
  targetId: string;
  targetKind: 'monster' | 'player';
  amount: number;
  killed: boolean;
  /** 치명타로 터졌는지 — 클라이언트가 숫자를 다르게 띄운다 */
  crit?: boolean;
  /** 때린 쪽 */
  sourceId: string;
  /**
   * 맞은 지점.
   *
   * 클라이언트가 대상 id 로 위치를 찾게 두면 **막타에서 숫자가 사라진다** —
   * 죽은 몬스터는 같은 틱에 그리드에서 빠져 시야에서 제거되기 때문이다.
   * 어디서 맞았는지는 서버가 이미 알고 있으니 그냥 같이 보낸다.
   */
  x: number;
  z: number;
  /** 있으면 클라이언트가 날아가는 모습을 보여주고, 도착할 때 피해를 표시한다 */
  projectile?: string;
}

/** 죽은 몬스터가 시체로 남아 있는 시간 */
const CORPSE_MS = 2500;

export class CombatSystem {
  readonly grid = new SpatialGrid<MonsterState>();
  private readonly monsters = new Map<string, MonsterRuntime>();

  // Node 의 타입 스트리핑은 파라미터 프로퍼티(constructor(private x))를 지원하지 않는다.
  // 서버는 빌드 없이 그대로 실행되므로 명시적 필드로 쓴다.
  private readonly state: { monsters: Map<string, MonsterState> };

  constructor(def: ZoneDef, state: { monsters: Map<string, MonsterState> }) {
    this.state = state;
    for (const spawn of def.monsters ?? []) {
      for (let i = 0; i < spawn.count; i++) this.spawnOne(spawn);
    }
  }

  get all(): IterableIterator<MonsterRuntime> {
    return this.monsters.values();
  }

  private spawnOne(spawn: MonsterSpawnDef): void {
    const kind = getMonsterKind(spawn.kind);
    const angle = Math.random() * Math.PI * 2;
    const dist = Math.sqrt(Math.random()) * spawn.radius;
    const x = spawn.x + Math.cos(angle) * dist;
    const z = spawn.z + Math.sin(angle) * dist;

    const monster = new Monster();
    monster.id = randomUUID();
    monster.kind = kind.id;
    monster.x = x;
    monster.z = z;
    monster.rotY = Math.random() * Math.PI * 2;
    monster.hp = kind.maxHp;
    monster.maxHp = kind.maxHp;
    monster.state = 'idle';

    this.state.monsters.set(monster.id, monster);
    this.grid.insert(monster.id, x, z, monster);
    this.monsters.set(monster.id, {
      state: monster,
      kind,
      homeX: x,
      homeZ: z,
      spawn,
      targetId: null,
      nextAttackAt: 0,
      respawnAt: 0,
      nextAoeAt: 0,
      aoeBurstAt: 0,
      aoeX: 0,
      aoeZ: 0,
    });
  }

  /**
   * 플레이어의 공격을 판정한다 (기본 공격과 스킬 공용).
   *
   * 대상은 **서버가 고른다** — 클라이언트가 대상 id 를 보내게 하면
   * 사거리 밖이나 벽 너머의 적을 지정할 수 있다.
   * 정면 부채꼴 안에서 가까운 순서로 maxTargets 만큼 친다.
   */
  resolvePlayerAttack(
    player: PlayerState,
    attack: number,
    range: number,
    now: number,
    arc = ATTACK_ARC,
    maxTargets = 1,
    /**
     * 투사체 종류와 치명타 수치.
     *
     * 뒤에 파라미터를 계속 붙이면 호출부가 `undefined, 1, undefined` 처럼
     * 읽을 수 없게 된다. 여기서부터는 이름을 붙여 넘긴다.
     */
    extra: { projectile?: string; crit?: number; critDamage?: number } = {}
  ): HitEvent[] {
    const candidates = this.grid.queryRadius(player.x, player.z, range);
    if (candidates.length === 0) return [];

    const facingX = Math.sin(player.rotY);
    const facingZ = Math.cos(player.rotY);
    const halfArc = arc / 2;

    const inRange: { monster: MonsterState; dist: number }[] = [];
    for (const monster of candidates) {
      if (monster.hp <= 0) continue;
      const dx = monster.x - player.x;
      const dz = monster.z - player.z;
      const dist = Math.hypot(dx, dz);

      // 전방향 스킬이 아니면 등 뒤는 맞지 않는다
      if (arc < Math.PI * 2 && dist >= 1e-3) {
        const dot = (dx / dist) * facingX + (dz / dist) * facingZ;
        if (Math.acos(Math.min(1, Math.max(-1, dot))) > halfArc) continue;
      }
      inRange.push({ monster, dist });
    }

    // 가까운 순서로 — 범위기라도 눈앞의 적부터 맞는 게 자연스럽다
    inRange.sort((a, b) => a.dist - b.dist);

    const hits: HitEvent[] = [];
    for (const { monster } of inRange.slice(0, Math.max(1, maxTargets))) {
      const runtime = this.monsters.get(monster.id);
      if (!runtime) continue;

      // 치명타는 대상마다 따로 굴린다 — 범위기 한 방이 통째로 터지면
      // 피해가 뭉쳐서 숫자가 튄다
      const crit = rollCrit(extra.crit ?? 0, Math.random());
      const base = computeDamage(attack, runtime.kind.defense);
      const amount = crit
        ? Math.max(1, Math.round(base * (extra.critDamage ?? BASE_CRIT_DAMAGE)))
        : base;
      monster.hp = Math.max(0, monster.hp - amount);

      // 맞으면 때린 쪽을 쫓는다
      runtime.targetId = player.id;
      runtime.state.state = 'chase';

      const killed = monster.hp === 0;
      if (killed) {
        monster.state = 'dead';
        runtime.targetId = null;
        // 시전 중에 죽으면 예고는 없던 일이 된다. 안 지우면 되살아난 뒤
        // 엉뚱한 자리에서 터진다.
        runtime.aoeBurstAt = 0;
        runtime.respawnAt = now + Math.max(CORPSE_MS, runtime.spawn.respawnMs);
        this.grid.remove(monster.id);
      }

      hits.push({
        targetId: monster.id,
        targetKind: 'monster',
        amount,
        killed,
        sourceId: player.id,
        x: monster.x,
        z: monster.z,
        ...(crit ? { crit: true } : {}),
        ...(extra.projectile ? { projectile: extra.projectile } : {}),
      });
    }

    return hits;
  }

  monsterKindOf(id: string): MonsterKind | null {
    return this.monsters.get(id)?.kind ?? null;
  }

  /**
   * 몬스터 AI 한 틱.
   *
   * 상태 기계: idle → (플레이어 접근) chase → (사거리 도달) attack
   *            → (너무 멀어짐) 복귀 → idle
   */
  tick(
    dt: number,
    now: number,
    players: SpatialGrid<PlayerState>,
    getPlayer: (id: string) => PlayerState | undefined,
    /**
     * 결과를 올려보내는 자리. 콜백이 셋이라 위치 인자로 두면 호출부가
     * `undefined, fn, fn` 처럼 읽을 수 없게 된다 — 이름을 붙여 넘긴다.
     */
    on: MonsterEvents
  ): void {
    for (const runtime of this.monsters.values()) {
      const m = runtime.state;

      // --- 죽어 있으면 리스폰만 기다린다 ---
      if (m.hp <= 0) {
        if (runtime.respawnAt !== 0 && now >= runtime.respawnAt) this.respawn(runtime);
        continue;
      }

      const kind = runtime.kind;

      // --- 범위 공격 시전 중 ---
      // 예고한 뒤에는 **그 자리에 선다.** 원은 시전을 시작한 자리에 고정돼
      // 있으므로, 여기서 따라 움직이면 표시와 터지는 자리가 어긋나 붙어 있는
      // 쪽은 피할 방법이 없다. 리쉬·대상 재탐색보다 먼저 보는 이유도 같다 —
      // 한번 예고한 것은 대상이 도망가든 죽든 그대로 터진다.
      if (runtime.aoeBurstAt !== 0) {
        m.state = 'cast';
        if (now >= runtime.aoeBurstAt) {
          runtime.aoeBurstAt = 0;
          on.aoeBurst(m, kind, runtime.aoeX, runtime.aoeZ);
        }
        continue;
      }

      const homeDist = Math.hypot(m.x - runtime.homeX, m.z - runtime.homeZ);

      // --- 너무 멀리 왔으면 포기하고 복귀 ---
      if (homeDist > kind.leashRange) {
        runtime.targetId = null;
        m.state = 'chase';
        this.moveToward(runtime, runtime.homeX, runtime.homeZ, kind.moveSpeed, dt);
        // 집에 거의 닿으면 체력을 회복한다 (도망쳐서 안전하게 잡는 걸 막는다)
        if (Math.hypot(m.x - runtime.homeX, m.z - runtime.homeZ) < 1) {
          m.hp = kind.maxHp;
          m.state = 'idle';
        }
        continue;
      }

      // --- 대상 확인 / 탐색 ---
      let target = runtime.targetId ? (getPlayer(runtime.targetId) ?? null) : null;
      if (target && (target.dead || Math.hypot(target.x - m.x, target.z - m.z) > kind.leashRange)) {
        target = null;
        runtime.targetId = null;
      }
      if (!target) {
        target = this.findNearestPlayer(players, m.x, m.z, kind.aggroRange);
        runtime.targetId = target?.id ?? null;
      }

      if (!target) {
        // 집에서 벗어나 있으면 슬슬 돌아간다
        if (homeDist > 1.5) {
          m.state = 'chase';
          this.moveToward(runtime, runtime.homeX, runtime.homeZ, kind.moveSpeed * 0.5, dt);
        } else {
          m.state = 'idle';
        }
        continue;
      }

      const dist = Math.hypot(target.x - m.x, target.z - m.z);

      // --- 범위 공격 시작 (보스) ---
      // 평타 사거리가 아니라 **원 안**에 들어오면 건다. 그래야 "보스 7m 안은
      // 위험하다"는 한 줄로 설명되고, 멀리서 쏘는 직업(마법사 9 · 궁수 12)은
      // 자기 사거리를 지키는 것만으로 자연히 피한다.
      if (kind.aoe && now >= runtime.nextAoeAt && dist <= kind.aoe.radius) {
        runtime.nextAoeAt = now + kind.aoe.cooldownMs;
        runtime.aoeBurstAt = now + kind.aoe.windupMs;
        runtime.aoeX = m.x;
        runtime.aoeZ = m.z;
        m.state = 'cast';
        m.rotY = Math.atan2(target.x - m.x, target.z - m.z);
        on.aoeCast(m, kind, runtime.aoeX, runtime.aoeZ);
        continue;
      }

      if (dist > kind.attackRange) {
        m.state = 'chase';
        this.moveToward(runtime, target.x, target.z, kind.moveSpeed, dt);
        continue;
      }

      // --- 사거리 안 — 공격 ---
      m.state = 'attack';
      m.rotY = Math.atan2(target.x - m.x, target.z - m.z);
      if (now >= runtime.nextAttackAt) {
        runtime.nextAttackAt = now + kind.attackCooldown;
        on.hitPlayer(target, m, kind);
      }
    }
  }

  private respawn(runtime: MonsterRuntime): void {
    const spawn = runtime.spawn;
    const angle = Math.random() * Math.PI * 2;
    const dist = Math.sqrt(Math.random()) * spawn.radius;
    const m = runtime.state;

    runtime.homeX = spawn.x + Math.cos(angle) * dist;
    runtime.homeZ = spawn.z + Math.sin(angle) * dist;
    m.x = runtime.homeX;
    m.z = runtime.homeZ;
    m.hp = runtime.kind.maxHp;
    m.state = 'idle';
    runtime.respawnAt = 0;
    runtime.targetId = null;
    runtime.aoeBurstAt = 0;
    runtime.nextAoeAt = 0;
    this.grid.insert(m.id, m.x, m.z, m);
  }

  private moveToward(
    runtime: MonsterRuntime,
    tx: number,
    tz: number,
    speed: number,
    dt: number
  ): void {
    const m = runtime.state;
    const dx = tx - m.x;
    const dz = tz - m.z;
    const dist = Math.hypot(dx, dz);
    if (dist < 1e-3) return;

    const step = Math.min(dist, speed * dt);
    m.x += (dx / dist) * step;
    m.z += (dz / dist) * step;
    m.rotY = Math.atan2(dx, dz);
    this.grid.move(m.id, m.x, m.z);
  }

  private findNearestPlayer(
    players: SpatialGrid<PlayerState>,
    x: number,
    z: number,
    range: number
  ): PlayerState | null {
    let best: PlayerState | null = null;
    let bestDist = Infinity;
    for (const p of players.queryRadius(x, z, range)) {
      if (p.dead) continue;
      const dist = Math.hypot(p.x - x, p.z - z);
      if (dist < bestDist) {
        best = p;
        bestDist = dist;
      }
    }
    return best;
  }
}
