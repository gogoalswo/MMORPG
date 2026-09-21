import { Room, type Client } from 'colyseus';
import { StateView } from '@colyseus/schema';
import {
  AreaOfInterest,
  SpatialGrid,
  TICK_MS,
  applyMove,
  pushOutOfSolids,
  monsterRadius,
  PLAYER_RADIUS,
  type Solid,
  getSpawn,
  getZone,
  zoneHalfSize,
  isJobId,
  BASIC_PROJECTILE,
  skillForJob,
  isRangedSkill,
  blastRadius,
  SKILL_BLAST_MIN,
  skillCooldown,
  SKILL_COOLDOWN_OFF,
  AUTO_SKILL_TEST_GAP,
  JOB_SKILLS,
  SKILLS,
  SKILL_BAR_SIZE,
  SKILL_UNLOCK_ALL,
  SKILL_POINT_PER_LEVEL,
  skillPointCost,
  canLearn,
  validateCharacterName,
  nameErrorMessage,
  applyExp,
  computeDamage,
  expReward,
  statsFor,
  rollOptions,
  effectiveCooldown,
  attackRootMs,
  GODMODE_ALLOWED,
  resolveZoneId,
  INVENTORY_SIZE,
  canEquip,
  canEnhance,
  enhanceCost,
  rollBossDrop,
  rollEnhance,
  ITEMS,
  JOB_IDS,
  NPC_REACH,
  gradeMultiplier,
  gradeForLevel,
  type NpcRole,
  equipmentStats,
  getItem,
  rollDrop,
  EQUIP_SLOTS,
  type EquipSlot,
  type Stats,
  HUNT_ARRIVE_EPS,
  clampHuntRadius,
  huntLeash,
  HUNT_HEAL_BELOW,
  HUNT_STANDOFF,
  RUN_SPEED,
  pickHuntTarget,
  standoffPoint,
  type JobId,
  getMonsterKind,
  type MonsterKind,
  type MoveInput,
  type ZoneDef,
} from '@mmo/shared';
import { Player, ZoneState, type MonsterState, type PlayerState } from './state.ts';

const clamp = (v: number, min: number, max: number): number =>
  v < min ? min : v > max ? max : v;
import { CombatSystem } from './combat.ts';
import { authenticate, linkOrLoginWithGoogle, type Session } from './auth.ts';
import {
  MAX_CHARACTERS,
  createCharacter,
  deleteOwnedCharacter,
  getCharactersByAccount,
  getOwnedCharacter,
  isNameTaken,
  saveCharacterItems,
  saveCharacterSkills,
  saveCharacterPosition,
  saveCharacterProgress,
  setCharacterJob,
  type CharacterRow,
} from './db.ts';

/** 채팅 한 줄 최대 길이 */
const MAX_CHAT_LENGTH = 200;
/** 도배 제한: CHAT_WINDOW_MS 안에 CHAT_BURST 줄까지 */
const CHAT_WINDOW_MS = 5000;
const CHAT_BURST = 5;

/** 위치를 DB 에 남기는 주기. 매 틱 쓰면 디스크가 못 버틴다 */
const SAVE_INTERVAL_MS = 15000;

interface Viewer {
  client: Client;
  aoi: AreaOfInterest;
  /** 현재 이 클라이언트에게 보이는 플레이어 id 집합 */
  visible: Set<string>;
  /** 이 세션이 조종하는 캐릭터 (저장 대상) */
  character: CharacterRow;
  accountId: string;
}

/**
 * 존 하나에 대응하는 룸.
 *
 * 권위 서버다 — 클라이언트는 "이 방향으로 이 시간만큼 움직이겠다"는 요청만 보내고,
 * 실제 좌표는 서버가 공유 이동 함수로 계산한다.
 */
/**
 * 충돌을 볼 때 훑는 반경 (m). 캐릭터 반지름 + 가장 큰 보스 반지름(1.16)보다 넉넉하면 된다.
 * 존 전체를 훑으면 입력마다 몬스터 수십 마리를 도는 셈이라 그게 곧 서버 부하다.
 */
const SOLID_SCAN_RANGE = 4;

export class ZoneRoom extends Room {
  state = new ZoneState();

  private def!: ZoneDef;
  private halfSize = 100;

  private readonly grid = new SpatialGrid<PlayerState>();
  private readonly viewers = new Map<string, Viewer>();

  /** 매 틱 재사용하는 임시 버퍼 (GC 압박을 줄인다) */
  private readonly scratch: PlayerState[] = [];

  /** 충돌용으로 근처 캐릭터를 담는 버퍼. `scratch` 와 따로 둔다 — 훑는 도중에 섞이면 안 된다 */
  private readonly solidScan: PlayerState[] = [];

  /** 세션별 최근 채팅 시각 (도배 제한) */
  private readonly chatHistory = new Map<string, number[]>();

  private saveTimer = 0;
  private combat!: CombatSystem;
  private lastTickAt = Date.now();

  /** 세션별 다음 공격 가능 시각 (쿨타임) */
  private readonly nextAttackAt = new Map<string, number>();
  /**
   * 세션별 **공격 경직이 풀리는 시각**. 이때까지는 이동을 받지 않는다
   * (`ATTACK_ROOT_MS`). 스키마에 넣지 않는 이유는 클라이언트가 이 값을
   * 상태로 볼 일이 없기 때문이다 — 자기 경직은 `swing`/`skill` 메시지에
   * 실려 오는 `rootMs` 로 알고, 남의 경직은 서버가 정한 위치로 이미 보인다.
   */
  private readonly rootedUntil = new Map<string, number>();
  /**
   * **무적 모드를 켠 세션** (테스트 도구, `GODMODE_ALLOWED`).
   *
   * 스키마가 아니라 여기 두는 이유는 남에게 보일 값이 아니어서다. 존을 옮기면
   * 룸이 새로 만들어져 저절로 꺼지므로, 클라이언트가 들어가서 다시 켠다.
   */
  private readonly godmode = new Set<string>();
  /** "세션:스킬" 별 쿨타임 */
  private readonly skillReadyAt = new Map<string, number>();

  /**
   * 자동 사냥을 켠 자리. 이 주변에서만 싸운다 —
   * 앵커가 없으면 몬스터를 따라 맵 끝까지 끌려간다.
   */
  private readonly autoAnchor = new Map<string, { x: number; z: number }>();
  /** 자동 사냥이 지금 물고 있는 몬스터 */
  private readonly autoTarget = new Map<string, string>();
  /**
   * 자동 사냥 중에 땅을 클릭했을 때 "여기 먼저 가라"는 지시.
   *
   * 있으면 대상을 고르지 않고 이 자리로 걷기만 한다. 도착하면 지워지고
   * 평소 자동 사냥으로 돌아간다. 앵커도 같은 자리로 옮기므로, 도착한 뒤에는
   * 그 주변을 사냥한다 — 앵커를 안 옮기면 도착하자마자 원래 자리로 되돌아간다.
   */
  private readonly moveOrder = new Map<string, { x: number; z: number }>();
  /**
   * 클릭으로 지목한 대상 (세션 → 몬스터 id).
   *
   * **적어두는 것은 "누구를 겨누고 있나" 뿐이고 이동은 건드리지 않는다.** ★
   * 예전에는 지목하면 서버가 붙어서 죽을 때까지 때렸다(클릭 추격). 그런데 그건
   * 자동 사냥과 하는 일이 같아서, 사람이 **직접 쏘려고** 지목한 것까지 서버가
   * 대신 해 버렸다. 지금은 겨누기만 하고, 때리는 건 사람이 누를 때 그쪽으로 나간다
   * (`focusOf` → `handleAttack` / `handleSkill`).
   */
  private readonly targets = new Map<string, string>();
  /** 세션별 사냥 반경 (사람이 조절한다) */
  private readonly autoRadius = new Map<string, number>();
  /**
   * 자동으로 쓸 스킬. 없으면 "아직 안 정했다"는 뜻이라 전부 쓴다 —
   * 예전 클라이언트가 접속해도 자동 사냥이 스킬을 쓰던 대로 돌아간다.
   */
  private readonly autoSkills = new Map<string, Set<string>>();

  /** 캐릭터 생성 화면에 머물러 있는 접속들 (아직 월드에 없다) */
  private readonly pending = new Map<
    string,
    { client: Client; auth: Session; options: { name?: string; job?: string; spawn?: string } }
  >();

  onCreate(options: { zoneId?: string }): void {
    const zoneId = resolveZoneId(options.zoneId);
    this.def = getZone(zoneId);
    this.halfSize = zoneHalfSize(this.def.size);
    this.state.zoneId = zoneId;

    this.combat = new CombatSystem(this.def, this.state as never);

    this.setPatchRate(TICK_MS);
    this.setSimulationInterval(() => this.tick(), TICK_MS);

    this.onMessage('input', (client, message: MoveInput) => this.handleInput(client, message));
    this.onMessage('chat', (client, text: string) => this.handleChat(client, text));
    this.onMessage('setJob', (client, job: string) => this.handleSetJob(client, job));
    this.onMessage('createCharacter', (client, msg: { name: string; job: string }) =>
      this.handleCreateCharacter(client, msg)
    );
    this.onMessage('selectCharacter', (client, msg: { id: string }) =>
      this.handleSelectCharacter(client, msg)
    );
    this.onMessage('deleteCharacter', (client, msg: { id: string }) =>
      this.handleDeleteCharacter(client, msg)
    );
    this.onMessage('attack', (client) => this.handleAttack(client));
    /**
     * 무적 모드 (테스트 도구). 값을 주면 그 값으로, 안 주면 뒤집는다.
     *
     * **스위치가 꺼져 있으면 아무 일도 안 한다** — 클라이언트 단추가 안 보이는
     * 것은 안내일 뿐이고, 막는 것은 여기다 (판정은 서버가 한다).
     */
    this.onMessage('godmode', (client, on?: boolean) => {
      if (!GODMODE_ALLOWED) return;
      const want = typeof on === 'boolean' ? on : !this.godmode.has(client.sessionId);
      if (want) this.godmode.add(client.sessionId);
      else this.godmode.delete(client.sessionId);
      // 켜졌는지는 **서버가 알려준다.** 단추가 제 값을 들고 있으면 서버가 거절해도 켜 보인다
      client.send('godmode', { on: want });
    });
    this.onMessage('target', (client, id: string | null) => this.handleTarget(client, id));
    this.onMessage('autohunt', (client, on: boolean) => this.handleAutoHunt(client, on));
    this.onMessage('moveTo', (client, msg: { x: number; z: number }) =>
      this.handleMoveTo(client, msg)
    );
    this.onMessage('autoSkills', (client, ids: string[]) => this.handleAutoSkills(client, ids));
    this.onMessage('learnSkill', (client, id: string) => this.handleLearnSkill(client, id));
    this.onMessage('setSkillBar', (client, ids: string[]) => this.handleSetSkillBar(client, ids));
    this.onMessage('npcOpen', (client, role: string) => this.handleNpcOpen(client, role));
    this.onMessage('npcBuy', (client, itemId: string) => this.handleNpcBuy(client, itemId));
    this.onMessage('npcSell', (client, index: number) => this.handleNpcSell(client, index));
    this.onMessage('npcJob', (client, job: string) => this.handleNpcJob(client, job));
    this.onMessage('npcEnhance', (client, index: number) => this.handleNpcEnhance(client, index));
    this.onMessage('autoRange', (client, radius: number) => {
      // 값은 서버가 다시 자른다. 클라이언트 슬라이더는 표시일 뿐이다.
      this.autoRadius.set(client.sessionId, clampHuntRadius(radius));
    });
    this.onMessage('equip', (client, index: number) => this.handleEquip(client, index));
    this.onMessage('unequip', (client, slot: string) => this.handleUnequip(client, slot));
    this.onMessage('skill', (client, skillId: string) => this.handleSkill(client, skillId));
    this.onMessage('linkGoogle', (client, idToken: string) => {
      void this.handleLinkGoogle(client, idToken);
    });

    console.log(`[zone] ${zoneId} 룸 생성 (roomId=${this.roomId})`);
  }

  /**
   * 접속 전에 계정을 확인한다.
   * 토큰이 없거나 만료됐으면 게스트 계정을 새로 만든다 — 접속 자체는 절대 막지 않는다.
   */
  onAuth(_client: Client, options: { token?: string }): Session {
    return authenticate(options?.token);
  }

  onJoin(
    client: Client,
    options: { name?: string; job?: string; spawn?: string; characterId?: string },
    auth: Session
  ): void {
    // 어떤 캐릭터로 들어올지 이미 정해서 왔다면 (선택 완료, 포탈 이동)
    if (options.characterId) {
      const chosen = getOwnedCharacter(auth.account.id, options.characterId);
      if (chosen) {
        this.enterWorld(client, auth, chosen, options);
        return;
      }
      // 소유자가 아니거나 삭제된 캐릭터 — 아래 선택 화면으로 떨어진다
    }

    this.pending.set(client.sessionId, { client, auth, options });
    this.sendCharacterList(client, auth);
  }

  /** 캐릭터가 없으면 생성 화면을, 있으면 선택 화면을 띄운다 */
  private sendCharacterList(client: Client, auth: Session): void {
    const characters = getCharactersByAccount(auth.account.id);
    if (characters.length === 0) {
      client.send('needsCharacter', { suggestedName: '' });
      return;
    }
    client.send('characterList', {
      max: MAX_CHARACTERS,
      characters: characters.map((c) => ({
        id: c.id,
        name: c.name,
        job: c.job,
        level: c.level,
        zoneId: c.zoneId,
      })),
    });
  }

  private handleSelectCharacter(client: Client, msg: { id: string }): void {
    const waiting = this.pending.get(client.sessionId);
    if (!waiting) return;

    const character = getOwnedCharacter(waiting.auth.account.id, msg?.id ?? '');
    if (!character) {
      this.sendCharacterList(client, waiting.auth);
      return;
    }

    // 마지막으로 있던 존이 지금 룸과 다르면 그 존으로 보낸다.
    // 여기서 그냥 입장시키면 로그아웃한 장소를 잃는다.
    // 없어진 존에 저장돼 있으면 시작 존으로 되돌린다
    const zoneId = resolveZoneId(character.zoneId);
    if (zoneId !== this.def.id) {
      client.send('switchZone', { zoneId, characterId: character.id });
      return;
    }

    this.enterWorld(client, waiting.auth, character, {});
  }

  private handleDeleteCharacter(client: Client, msg: { id: string }): void {
    const waiting = this.pending.get(client.sessionId);
    if (!waiting) return; // 월드에 들어온 뒤에는 삭제할 수 없다
    deleteOwnedCharacter(waiting.auth.account.id, msg?.id ?? '');
    this.sendCharacterList(client, waiting.auth);
  }

  /**
   * 캐릭터를 월드에 넣는다.
   * 기존 캐릭터로 접속할 때와 방금 만들었을 때 둘 다 여기를 지난다.
   */
  private enterWorld(
    client: Client,
    auth: Session,
    character: CharacterRow,
    options: { spawn?: string }
  ): void {

    // HP 0 으로 저장된 캐릭터는 되살려서 들여보낸다. ★
    // 죽으면 저절로 살아나지 않는다. 사람이 사망 화면을 눌러 마을로 들어오는
    // 것이 곧 부활이고, **그 부활을 하는 곳이 여기다.** 되살리지 않으면 죽은 채로
    // 들어와 영원히 못 움직인다 — 서버는 죽은 플레이어의 이동을 전부 거부하는데
    // 클라이언트는 혼자 예측하다 보정에 끌려와 캐릭터가 떤다.
    const revive = character.hp <= 0;

    // 스폰 지점을 지정해서 들어왔으면(포탈 통과) 그 자리에,
    // 아니면(재접속) 저장된 위치에 놓는다. 되살아난 경우는 죽은 자리가 아니라
    // 스폰 지점에서 시작한다 — 죽은 자리는 대개 그 죽인 놈 앞이다.
    const spawned = getSpawn(this.def, options.spawn ?? 'default');
    const restore = character.zoneId === this.def.id && !options.spawn && !revive;
    const sx = restore ? character.x : spawned[0];
    const sz = restore ? character.z : spawned[1];

    const player = new Player();
    player.id = client.sessionId;
    player.name = character.name;
    player.job = character.job;
    player.x = sx;
    player.z = sz;
    player.rotY = 0;
    // 아직 viewer 를 등록하기 전이라 statsOf 를 못 쓴다. 장비 보너스를 직접 더한다.
    const base = statsFor(character.job as JobId, character.level);
    const gear = equipmentStats(character.equipment);
    const stats = { maxHp: base.maxHp + gear.maxHp };
    player.hp = revive ? stats.maxHp : Math.min(character.hp, stats.maxHp);
    player.maxHp = stats.maxHp;
    player.level = character.level;
    player.exp = character.exp;
    player.dead = player.hp <= 0;
    // 스키마 불리언은 대입하기 전까지 undefined 라서 그대로 내려간다.
    // 클라이언트에서 undefined 를 받으면 classList.toggle(cls, undefined) 가
    // "강제 지정"이 아니라 "뒤집기"로 동작해 패치마다 버튼이 깜빡인다.
    player.auto = false;
    player.lastSeq = 0;

    /**
     * 스폰 지점은 모두에게 같은 한 점이라 **그냥 놓으면 서로 겹친 채로 시작한다.**
     * 겹친 둘은 아무도 움직이지 않으면 영원히 겹쳐 있다 — 미는 건 이동 계산 안에서만
     * 일어나기 때문이다. 그래서 들어오는 순간 한 번 밀어 자리를 띄운다.
     * 미는 쪽은 **들어온 쪽**이다 (이미 서 있던 사람을 밀면 그 사람 화면이 튄다).
     */
    pushOutOfSolids(player, this.solidsNear(player.x, player.z, player.id), this.halfSize);

    // 지금 존과 자리를 바로 기록해둔다. 다음 접속에 어디로 돌아갈지의 근거다.
    // 되살렸으면 그 HP 로 적어야 한다 — 0 을 다시 적으면 다음 접속에 또 죽은 채다.
    saveCharacterPosition(character.id, this.def.id, player.x, player.z, player.hp);

    this.state.players.set(client.sessionId, player);
    this.grid.insert(client.sessionId, player.x, player.z, player);

    // 이 클라이언트가 볼 수 있는 것만 담는 뷰.
    // 자기 자신은 거리와 무관하게 항상 보여야 한다.
    const view = new StateView();
    view.add(player);
    client.view = view;

    this.viewers.set(client.sessionId, {
      client,
      aoi: new AreaOfInterest(),
      visible: new Set([client.sessionId]),
      character,
      accountId: auth.account.id,
    });

    const entered = this.viewers.get(client.sessionId)!;
    // 들어오자마자 남들에게도 제 장비가 보여야 한다
    this.syncLook(client.sessionId, player);
    this.grantStartingSkill(entered, character.job as JobId, character.level);
    this.sendInventory(entered);
    this.sendSkills(entered);

    // 클라이언트가 토큰을 저장해야 다음 접속에 같은 계정으로 들어온다
    client.send('session', {
      token: auth.token,
      accountId: auth.account.id,
      characterId: character.id,
      characterName: character.name,
      job: character.job,
      zoneId: this.def.id,
      // 밀어낸 뒤의 자리를 보낸다 — 스폰 지점을 그대로 보내면 클라가 겹친 자리에서
      // 예측을 시작해 첫 보정에 튄다
      x: player.x,
      z: player.z,
      linkedGoogle: auth.account.googleEmail ?? null,
      isNewAccount: auth.isNewAccount,
    });

    this.pending.delete(client.sessionId);
    this.announce(`${player.name} 님이 접속했습니다.`);
    console.log(`[zone] ${this.def.id} + ${player.name} (${this.clients.length}명)`);
  }

  /** 생성 화면에서 온 요청. 이름 규칙과 중복을 **서버가 다시** 검사한다 */
  private handleCreateCharacter(client: Client, msg: { name: string; job: string }): void {
    const waiting = this.pending.get(client.sessionId);
    if (!waiting) return; // 이미 캐릭터가 있는데 다시 만들려는 요청은 무시

    const name = (msg?.name ?? '').trim();
    const error = validateCharacterName(name);
    if (error) {
      client.send('createResult', { ok: false, reason: nameErrorMessage(error) });
      return;
    }
    if (!isJobId(msg?.job)) {
      client.send('createResult', { ok: false, reason: '직업을 선택하세요.' });
      return;
    }
    if (isNameTaken(name)) {
      client.send('createResult', { ok: false, reason: '이미 사용 중인 이름입니다.' });
      return;
    }
    if (getCharactersByAccount(waiting.auth.account.id).length >= MAX_CHARACTERS) {
      client.send('createResult', {
        ok: false,
        reason: `캐릭터는 최대 ${MAX_CHARACTERS}개까지 만들 수 있습니다.`,
      });
      return;
    }

    const [sx, sz] = getSpawn(this.def, 'default');
    const character = createCharacter(waiting.auth.account.id, name, msg.job, this.def.id, sx, sz);
    client.send('createResult', { ok: true });
    this.enterWorld(client, waiting.auth, character, {});
  }

  onLeave(client: Client): void {
    const id = client.sessionId;
    const leaving = this.state.players.get(id);
    // 나가기 전에 위치를 남긴다. 안 하면 접속 종료 직전 이동이 통째로 사라진다.
    this.persist(id);
    if (leaving) this.announce(`${leaving.name} 님이 떠났습니다.`);
    this.state.players.delete(id);
    this.grid.remove(id);
    this.viewers.delete(id);
    this.chatHistory.delete(id);
    this.pending.delete(id);
    this.nextAttackAt.delete(id);
    this.rootedUntil.delete(id);
    this.godmode.delete(id);
    this.autoAnchor.delete(id);
    this.autoTarget.delete(id);
    this.moveOrder.delete(id);
    this.targets.delete(id);
    this.autoRadius.delete(id);
    this.autoSkills.delete(id);
    for (const skillId of JOB_SKILLS[(this.state.players.get(id)?.job ?? 'fighter') as JobId] ?? []) {
      this.skillReadyAt.delete(`${id}:${skillId}`);
    }
    this.combat.grid.remove(id);

    // 떠난 플레이어를 남은 사람들의 가시 목록에서도 지운다.
    // 안 지우면 다시 들어왔을 때 "이미 보이는 중"으로 오인해 추가되지 않는다.
    for (const viewer of this.viewers.values()) viewer.visible.delete(id);

    console.log(`[zone] ${this.def.id} - ${id} (${this.clients.length}명)`);
  }

  private handleInput(client: Client, message: MoveInput): void {
    const player = this.state.players.get(client.sessionId);
    if (!player || !message) return;

    // 순번이 역행하면 지연 도착한 중복 패킷이다
    if (typeof message.seq !== 'number' || message.seq <= player.lastSeq) return;

    // 죽어 있으면 위치는 고정하되 순번은 갱신한다 (클라 보정이 멈추지 않도록)
    if (player.dead) {
      player.lastSeq = message.seq;
      return;
    }

    // 자동 사냥 중에는 서버가 직접 움직인다. 클라이언트 이동은 무시하되
    // 순번은 갱신해야 클라 보정이 멈추지 않는다.
    //
    // **타겟을 잡고 있어도 이동은 사람 몫이다** — 지목은 "어디로 쏠까"만 정한다.
    if (player.auto) {
      player.lastSeq = message.seq;
      return;
    }

    /**
     * 휘두르는 중이면 발을 묶는다 (`ATTACK_ROOT_MS`). 죽었을 때와 같은 모양으로
     * **순번은 갱신하고 위치만 안 옮긴다** — 안 갱신하면 클라이언트 보정이 이 구간
     * 내내 멈춘다. 각도 그대로 둔다: 쏘는 순간 `faceMonster` 가 맞춰 둔 방향이
     * 공격이 끝날 때까지 판정 방향이어야 한다.
     */
    if (Date.now() < (this.rootedUntil.get(client.sessionId) ?? 0)) {
      player.lastSeq = message.seq;
      return;
    }

    applyMove(player, message, this.halfSize, this.solidsNear(player.x, player.z, player.id));
    player.lastSeq = message.seq;

    const moving = Math.hypot(message.dx, message.dz) > 1e-4;
    if (moving) player.rotY = Math.atan2(message.dx, message.dz);

    this.grid.move(client.sessionId, player.x, player.z);
  }

  /**
   * 채팅.
   *
   * 명령어 파싱과 도배 제한을 **서버에서** 한다. 클라이언트가 "이건 귓속말이야"
   * 하고 알려주는 걸 믿으면, 조작된 클라이언트가 남의 귓속말을 가로채거나
   * 초당 수백 줄을 뿌릴 수 있다.
   */
  private handleChat(client: Client, text: string): void {
    const player = this.state.players.get(client.sessionId);
    if (!player || typeof text !== 'string') return;

    const trimmed = text.trim().slice(0, MAX_CHAT_LENGTH);
    if (!trimmed) return;

    if (!this.allowChat(client.sessionId)) {
      client.send('chat', { kind: 'system', from: '', text: '너무 빠릅니다. 잠시 후 다시 시도하세요.' });
      return;
    }

    // /w 이름 내용  — 같은 존 안에서만 닿는다 (존마다 룸이 다르기 때문)
    const whisper = /^\/(?:w|귓)\s+(\S+)\s+([\s\S]+)$/.exec(trimmed);
    if (whisper) {
      const [, targetName, body] = whisper;
      const target = this.findByName(targetName!);
      if (!target) {
        client.send('chat', {
          kind: 'system',
          from: '',
          text: `이 지역에 '${targetName}' 님이 없습니다.`,
        });
        return;
      }
      const payload = { kind: 'whisper', from: player.name, to: target.name, text: body!.trim() };
      this.clients.getById(target.id)?.send('chat', payload);
      // 보낸 사람에게도 돌려줘야 대화가 이어진다
      if (target.id !== client.sessionId) client.send('chat', payload);
      return;
    }

    this.broadcast('chat', { kind: 'say', from: player.name, text: trimmed });
  }

  /** 한 세션의 현재 위치를 DB 에 남긴다 */
  private persist(sessionId: string): void {
    const viewer = this.viewers.get(sessionId);
    const player = this.state.players.get(sessionId);
    if (!viewer || !player) return;
    saveCharacterPosition(viewer.character.id, this.def.id, player.x, player.z, player.hp);
    saveCharacterItems(
      viewer.character.id,
      viewer.character.gold,
      viewer.character.inventory,
      viewer.character.equipment
    );
    saveCharacterSkills(
      viewer.character.id,
      viewer.character.skills,
      viewer.character.skillBar,
      viewer.character.skillPoints
    );
  }

  private handleSetJob(client: Client, job: string): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player) return;
    if (typeof job !== 'string' || !/^[a-z]{1,16}$/.test(job)) return;
    player.job = job;
    setCharacterJob(viewer.character.id, job);
  }

  private async handleLinkGoogle(client: Client, idToken: string): Promise<void> {
    const viewer = this.viewers.get(client.sessionId);
    if (!viewer || typeof idToken !== 'string') return;

    const result = await linkOrLoginWithGoogle(viewer.accountId, idToken);
    if (!result.ok) {
      client.send('linkResult', { ok: false, reason: result.reason });
      return;
    }

    client.send('linkResult', {
      ok: true,
      token: result.token,
      email: result.account.googleEmail,
      // 다른 계정으로 갈아탄 경우 그 계정의 캐릭터를 쓰려면 재접속해야 한다
      switched: result.switched,
    });
  }

  /**
   * 근접 공격.
   *
   * 쿨타임·사거리·방향·피해량을 **전부 서버가 계산한다.**
   * 클라이언트는 "때리겠다"는 의사만 보낸다.
   */
  /**
   * 자동 사냥 켜기/끄기.
   *
   * 켠 자리를 앵커로 잡는다. 이 판단과 이동을 서버가 하는 이유는,
   * 클라이언트에서 돌리면 사용자가 탭을 옮기는 순간 브라우저가
   * requestAnimationFrame 을 멈추고 타이머를 1Hz 로 조여서 캐릭터가 서기 때문이다.
   */
  private handleAutoHunt(client: Client, on: boolean): void {
    const player = this.state.players.get(client.sessionId);
    if (!player) return;

    const next = on === true;
    if (player.auto === next) return;
    player.auto = next;

    // 켜든 끄든 남아 있던 "여기 먼저 가라"는 버린다.
    // 켤 때는 앵커를 지금 자리로 새로 잡으므로 옛 지시가 남으면 엉뚱한 데로 걷는다.
    this.moveOrder.delete(client.sessionId);

    if (next) {
      this.autoAnchor.set(client.sessionId, { x: player.x, z: player.z });
    } else {
      this.autoAnchor.delete(client.sessionId);
      this.autoTarget.delete(client.sessionId);
    }
  }

  /**
   * 자동 사냥 중에 땅을 클릭했다 — 저기로 먼저 가라. ★
   *
   * 예전에는 클릭하면 자동 사냥이 꺼졌다. "저 자리로 옮겨서 계속 사냥"이 안 되고
   * 옮긴 다음 버튼을 다시 눌러야 했다. 이제 자동 사냥은 켜둔 채로 그 자리까지
   * 걸어가고, 도착하면 거기를 새 앵커 삼아 사냥을 이어간다.
   *
   * 앵커를 같이 옮기는 게 핵심이다. 앵커가 그대로면 도착하자마자
   * "대상이 없으면 앵커로 돌아간다"에 걸려 원래 자리로 되돌아간다.
   *
   * 자동 사냥이 꺼져 있으면 아무것도 하지 않는다 — 그때는 클라이언트가 직접
   * 예측해서 걷는 게 더 부드럽다(왕복 지연이 없다).
   */
  private handleMoveTo(client: Client, msg: { x: number; z: number }): void {
    const player = this.state.players.get(client.sessionId);
    if (!player || !msg || player.dead || !player.auto) return;
    if (!Number.isFinite(msg.x) || !Number.isFinite(msg.z)) return;

    const x = clamp(msg.x, -this.halfSize, this.halfSize);
    const z = clamp(msg.z, -this.halfSize, this.halfSize);

    this.moveOrder.set(client.sessionId, { x, z });
    this.autoAnchor.set(client.sessionId, { x, z });
    // 가는 길에 물고 있던 놈은 놓는다. 안 놓으면 첫 틱에 그놈에게 다시 붙는다.
    this.autoTarget.delete(client.sessionId);
  }

  /**
   * 자동 사냥 한 틱.
   *
   * 때리는 건 사람이 눌렀을 때와 **똑같은 경로**(handleAttack/handleSkill)로 보낸다.
   * 쿨타임·정면각 검증을 두 벌 만들면 반드시 어긋난다.
   */
  private driveAutoHunt(dt: number): void {
    for (const viewer of this.viewers.values()) {
      const id = viewer.client.sessionId;
      const player = this.state.players.get(id);
      if (!player) continue;

      /**
       * 두 가지 모드가 같은 길을 탄다.
       *
       * 자동 사냥은 **켠 자리**를 앵커로 삼아 그 주변을 돌고, 대상이 없으면
       * 앵커로 돌아간다. 자동 시전은 앵커가 **지금 서 있는 자리**라 돌아갈 곳이
       * 없고, 근처에 적이 있을 때만 붙어서 싸운다.
       *
       * 둘 다 "붙어서 때린다"는 동작은 같아서 코드를 나누면 한쪽만 고치는 실수가 난다.
       */
      const hunting = player.auto;
      const casting = !hunting && (this.autoSkills.get(id)?.size ?? 0) > 0;
      if (!hunting && !casting) continue;

      const anchor = hunting ? this.autoAnchor.get(id) : { x: player.x, z: player.z };
      if (!anchor) continue;

      // 죽어 있으면 부활을 기다린다. 앵커는 지우지 않는다 —
      // 마을에서 부활해도 원래 사냥터로 걸어 돌아가야 한다.
      if (player.dead) {
        this.autoTarget.delete(id);
        continue;
      }

      // --- "여기 먼저 가라"가 있으면 그것부터 ---
      // 자동 사냥 중에 땅을 클릭한 것이다. 도착할 때까지는 대상을 고르지 않는다 —
      // 가는 길에 아무나 물면 "저기로 옮겨라"가 아니라 "저쪽으로 싸우며 가라"가 된다.
      const order = this.moveOrder.get(id);
      if (order) {
        if (Math.hypot(order.x - player.x, order.z - player.z) <= HUNT_ARRIVE_EPS) {
          this.moveOrder.delete(id);
        } else {
          this.stepAutoPlayer(player, order.x, order.z, dt, null);
          continue;
        }
      }

      // --- 대상 고르기 ---
      //
      // **사람이 클릭으로 지목한 놈이 있으면 그놈부터.** 자동 사냥을 켜 둔 채로
      // "쟤부터 잡아" 라고 찍는 일이 있어서다. 리쉬 밖까지 따라가지는 않는다 —
      // 앵커를 두는 이유(맵 끝까지 끌려가지 않기)가 그대로 살아 있어야 한다.
      const radius = clampHuntRadius(this.autoRadius.get(id));
      const picked = this.targets.get(id);
      const pickedMonster = picked ? this.state.monsters.get(picked) : undefined;
      const usePicked =
        pickedMonster &&
        pickedMonster.hp > 0 &&
        Math.hypot(pickedMonster.x - anchor.x, pickedMonster.z - anchor.z) <= huntLeash(radius);

      const targetId = usePicked
        ? picked
        : pickHuntTarget(
            anchor.x,
            anchor.z,
            this.combat.grid.queryRadius(anchor.x, anchor.z, huntLeash(radius)),
            this.autoTarget.get(id) ?? null,
            radius
          );

      if (targetId) this.autoTarget.set(id, targetId);
      else this.autoTarget.delete(id);

      const target = targetId ? this.state.monsters.get(targetId) : undefined;

      // --- 대상이 없으면 ---
      if (!target) {
        // 자동 사냥은 켠 자리로 돌아가 기다린다.
        // 자동 시전은 돌아갈 곳이 없다 — 사람이 조종하는 이동을 방해하면 안 된다.
        if (hunting) this.stepAutoPlayer(player, anchor.x, anchor.z, dt, null);
        continue;
      }

      this.engageTarget(viewer.client, player, target, dt);
    }
  }

  /**
   * 겨누고 있던 놈이 죽었거나 사라졌으면 놓는다 (매 틱).
   *
   * 대상이 죽은 자리에 조준이 남아 있으면 다음 스킬이 **시체 자리로** 나간다.
   * 몬스터가 죽는 길이 여럿(내 공격·남의 공격·리스폰 정리)이라 지우는 자리를
   * 한 군데로 모았다.
   */
  private sweepTargets(): void {
    for (const [id, monsterId] of [...this.targets]) {
      const monster = this.state.monsters.get(monsterId);
      const player = this.state.players.get(id);
      if (!monster || monster.hp <= 0 || !player || player.dead) this.clearTarget(id);
    }
  }

  /** 대상에게 붙어서 한 틱 싸운다. 자동 사냥과 자동 시전이 함께 쓴다 */
  private engageTarget(client: Client, player: PlayerState, target: MonsterState, dt: number): void {
    const job = player.job as JobId;
    const stats = this.statsOf(client.sessionId, job, player.level);

    // --- 사거리 안으로 붙는다 ---
    const stand = standoffPoint(player.x, player.z, target.x, target.z, stats.attackRange * HUNT_STANDOFF);
    this.stepAutoPlayer(player, stand.x, stand.z, dt, target);

    // --- 때린다 ---
    // 어느 놈을 치는지 **그대로 넘긴다.** 안 넘기면 handleAttack 이 사람이 찍어 둔
    // 타겟을 보고 엉뚱한 쪽으로 몸을 돌린다 (자동 사냥이 고른 놈과 다를 수 있다).
    const distance = Math.hypot(target.x - player.x, target.z - player.z);
    if (this.tryAutoSkill(client, player, job, distance, target)) return;
    if (distance <= stats.attackRange) this.handleAttack(client, target);
  }

  /**
   * 클릭으로 겨눌 대상을 지정한다.
   *
   * 여기서 하는 일은 적어두는 것뿐이다 — **이동도 공격도 하지 않는다.**
   * 대상이 이 존에 실재하는지, 살아 있는지는 **서버가 다시 본다** —
   * 클라이언트가 보낸 id 를 그대로 믿으면 없는 몬스터를 겨눈 채로 굳는다.
   */
  private handleTarget(client: Client, id: string | null): void {
    const sessionId = client.sessionId;
    const player = this.state.players.get(sessionId);
    if (!player) return;

    if (typeof id !== 'string' || !id) {
      this.clearTarget(sessionId);
      return;
    }

    const monster = this.state.monsters.get(id);
    if (!monster || monster.hp <= 0 || player.dead) {
      this.clearTarget(sessionId);
      return;
    }

    // 자동 사냥은 **끄지 않는다.** 겨누기는 이동을 뺏지 않으므로 주인이 겹치지
    // 않고, 자동 사냥은 지목한 놈을 먼저 잡는다(driveAutoHunt).
    this.targets.set(sessionId, id);
    client.send('target', { id });
  }

  /** 조준을 푼다. 표시를 지우는 건 클라이언트 몫이라 알려준다 */
  private clearTarget(sessionId: string): void {
    if (!this.targets.delete(sessionId)) return;
    this.clients.getById(sessionId)?.send('target', { id: null });
  }

  /**
   * 지금 겨누고 있는 몬스터. 죽었거나 사라졌으면 놓고 null.
   *
   * 공격·스킬이 나갈 때마다 부른다 — 겨눈 놈이 그 사이 죽었을 수 있다.
   */
  private focusOf(sessionId: string): MonsterState | null {
    const id = this.targets.get(sessionId);
    if (!id) return null;
    const monster = this.state.monsters.get(id);
    if (!monster || monster.hp <= 0) {
      this.clearTarget(sessionId);
      return null;
    }
    return monster;
  }

  /**
   * 겨누는 놈이 없을 때 **사거리 안에서 가장 가까운 놈**을 대신 잡는다.
   *
   * 찍지 않고 스킬을 누르면 판정이 내 정면 부채꼴로만 나가서, 몬스터를 옆에 두고
   * 눌렀을 때 눈앞의 놈을 헛친다. 그래서 한 놈을 골라 **진짜 조준으로 등록한다**
   * (`handleTarget` 과 같은 자리 — `targets` 에 적고 `target` 메시지로 알린다).
   * 이 시전에만 몰래 쓰고 말면 클라이언트는 조준이 없는 줄 알고 이펙트를 정면으로
   * 그리는데 판정만 옆에서 나 둘이 어긋난다.
   *
   * 고르는 규칙은 자동 사냥과 **같은 `pickHuntTarget`** 이다. "가장 가까운 놈"을
   * 두 벌 만들면 자동 사냥과 손 시전이 서로 다른 놈을 고른다.
   */
  private acquireTarget(client: Client, player: PlayerState, range: number): MonsterState | null {
    const id = pickHuntTarget(
      player.x,
      player.z,
      this.combat.grid.queryRadius(player.x, player.z, range),
      null,
      range
    );
    if (!id) return null;
    const monster = this.state.monsters.get(id);
    if (!monster || monster.hp <= 0) return null;
    this.targets.set(client.sessionId, id);
    client.send('target', { id });
    return monster;
  }

  /**
   * 겨눈 쪽으로 몸을 돌린다.
   *
   * **판정(부채꼴)이 rotY 를 보므로 쏘기 직전에 여기서 정한다.** 클라이언트가
   * 보내는 건 "움직인 방향"뿐이라, 서서 쏘면 마지막으로 걷던 쪽을 향한 채로
   * 나간다 — 타겟을 찍어 놓고도 옆으로 휘두르는 게 그것이다.
   */
  private faceMonster(player: PlayerState, monster: MonsterState): void {
    const dx = monster.x - player.x;
    const dz = monster.z - player.z;
    if (Math.hypot(dx, dz) > 1e-3) player.rotY = Math.atan2(dx, dz);
  }

  /**
   * 판정을 **겨눈 놈의 자리에서** 할지 정한다. 아니면 null (내 몸이 중심).
   *
   * 원거리일 때만, 그리고 사거리 안일 때만이다. 사거리 밖을 찍어 놓고 눌러도
   * 날아가게 하면 사거리라는 수치가 없는 것과 같다 — 그때는 예전처럼 내 몸에서
   * 부채꼴로 재고, 닿는 게 없으면 헛친다.
   */
  private blastAt(
    player: PlayerState,
    aim: MonsterState | null,
    ranged: boolean,
    range: number
  ): { x: number; z: number } | null {
    if (!aim || !ranged) return null;
    if (Math.hypot(aim.x - player.x, aim.z - player.z) > range) return null;
    return { x: aim.x, z: aim.z };
  }

  /** 목표 지점 쪽으로 한 틱만큼 걷고, 대상이 있으면 그쪽을 본다 */
  private stepAutoPlayer(
    player: PlayerState,
    toX: number,
    toZ: number,
    dt: number,
    lookAt: { x: number; z: number; id?: string } | null
  ): void {
    const dx = toX - player.x;
    const dz = toZ - player.z;
    const distance = Math.hypot(dx, dz);

    /**
     * **휘두르는 중에는 발을 멈춘다** (`ATTACK_ROOT_MS`). 사람이 모는 쪽
     * (`handleInput`)만 막으면 자동 사냥은 그대로 미끄러지면서 친다 —
     * 여기가 서버가 직접 위치를 옮기는 다른 한 길이다. 각은 아래에서 계속
     * 맞춘다: 붙어 있는 대상을 향해 선 채로 치는 그림이어야 한다.
     */
    const rooted = Date.now() < (this.rootedUntil.get(player.id) ?? 0);

    if (!rooted && distance > HUNT_ARRIVE_EPS) {
      const step = Math.min(RUN_SPEED * dt, distance);
      player.x = clamp(player.x + (dx / distance) * step, -this.halfSize, this.halfSize);
      player.z = clamp(player.z + (dz / distance) * step, -this.halfSize, this.halfSize);
      /**
       * 서버가 몰 때도 몬스터를 통과하면 안 된다. 다만 **쫓는 대상은 빼 준다** —
       * 넣으면 사거리 안으로 붙으려는 걸 충돌이 밀어내 둘이 서로 밀치며 떤다.
       * 대상과는 어차피 `standoffPoint` 가 사거리만큼 떨어진 자리를 잡아 준다.
       */
      pushOutOfSolids(
        player,
        this.solidsNear(player.x, player.z, player.id, lookAt?.id),
        this.halfSize
      );
      this.grid.move(player.id, player.x, player.z);
    }

    // 서버가 직접 각을 정할 수 있으니 대상을 정확히 바라본다.
    // 클라이언트 이동으로는 "움직인 방향"밖에 못 정해서 옆구리로 굳는다.
    if (lookAt) {
      const fx = lookAt.x - player.x;
      const fz = lookAt.z - player.z;
      if (Math.hypot(fx, fz) > 1e-4) player.rotY = Math.atan2(fx, fz);
    } else if (distance > HUNT_ARRIVE_EPS) {
      player.rotY = Math.atan2(dx, dz);
    }
  }

  /**
   * 그 자리 근처에서 지나갈 수 없는 것들 — 살아 있는 몬스터와 **다른 캐릭터**.
   *
   * 존 전체를 훑지 않고 반경 안의 것만 본다. 몬스터가 수십 마리인데 입력은 사람마다
   * 초당 수십 번 오므로, 전부 훑으면 그게 곧 서버 부하다.
   *
   * 죽은 몬스터는 지나갈 수 있다 — 시체에 막히면 "왜 안 가지" 가 된다. 죽은 캐릭터도 같다.
   *
   * 캐릭터끼리는 **움직이는 쪽만 밀린다.** 여기서 나온 목록은 이동 계산(`applyMove`)
   * 안에서만 쓰이고, 서 있는 쪽은 입력이 없어 계산을 아예 돌지 않기 때문이다.
   * 그래서 둘이 서로 밀치며 떠는 일이 없다.
   */
  private solidsNear(x: number, z: number, selfId: string, exceptId?: string): Solid[] {
    const near: Solid[] = [];
    for (const monster of this.state.monsters.values()) {
      if (monster.hp <= 0) continue;
      if (monster.id === exceptId) continue;
      const dx = monster.x - x;
      const dz = monster.z - z;
      if (dx * dx + dz * dz > SOLID_SCAN_RANGE * SOLID_SCAN_RANGE) continue;
      const kind = getMonsterKind(monster.kind);
      if (!kind) continue;
      near.push({ x: monster.x, z: monster.z, r: monsterRadius(kind.scale) });
    }

    // 다른 캐릭터도 몸이다. 자기 자신과 시체는 뺀다.
    // 그리드로 추린다 — 존에 사람이 몰려도 훑는 수가 반경 안으로 묶인다.
    for (const other of this.grid.queryRadius(x, z, SOLID_SCAN_RANGE, this.solidScan)) {
      if (other.id === selfId || other.dead) continue;
      near.push({ x: other.x, z: other.z, r: PLAYER_RADIUS });
    }
    return near;
  }

  /** 쓸 수 있는 스킬을 우선순위대로 하나 시도한다 */
  /**
   * 자동으로 쓸 스킬 목록.
   *
   * 그 직업이 실제로 가진 스킬인지 **서버가 다시 확인한다.** 다른 직업 스킬을
   * 목록에 넣어 보내는 클라이언트가 있어도 그냥 걸러진다.
   */
  private handleAutoSkills(client: Client, ids: string[]): void {
    const player = this.state.players.get(client.sessionId);
    if (!player || !Array.isArray(ids)) return;

    const job = player.job as JobId;
    const allowed = new Set<string>();
    for (const id of ids) {
      if (typeof id === 'string' && skillForJob(job, id)) allowed.add(id);
    }
    this.autoSkills.set(client.sessionId, allowed);
  }

  /** 이 세션이 자동으로 쓸 스킬인지 (아직 안 정했으면 전부 쓴다) */
  private autoSkillEnabled(sessionId: string, skillId: string): boolean {
    const chosen = this.autoSkills.get(sessionId);
    return chosen ? chosen.has(skillId) : true;
  }

  private tryAutoSkill(
    client: Client,
    player: PlayerState,
    job: JobId,
    distance: number,
    focus?: MonsterState
  ): boolean {
    const viewer = this.viewers.get(client.sessionId);
    for (const skillId of viewer?.character.skillBar ?? []) {
      if (!this.autoSkillEnabled(client.sessionId, skillId)) continue;

      const skill = skillForJob(job, skillId);
      if (!skill) continue;

      const usable = skill.selfHeal
        ? player.hp / Math.max(1, player.maxHp) < HUNT_HEAL_BELOW
        : distance <= skill.range;
      if (!usable) continue;

      const key = `${client.sessionId}:${skill.id}`;
      // 쿨타임을 끈 테스트 중에도 자동 시전은 AUTO_SKILL_TEST_GAP 마다 한 번 — 안 그러면 매 틱 쏜다
      const gap = SKILL_COOLDOWN_OFF ? AUTO_SKILL_TEST_GAP : 0;
      if (Date.now() < (this.skillReadyAt.get(key) ?? 0) + gap) continue;

      this.handleSkill(client, skill.id, focus);
      return true;
    }
    return false;
  }

  /**
   * 장비까지 더한 실제 능력치.
   *
   * `statsFor` 를 직접 부르면 장비가 무시된다. 서버 안에서 능력치가 필요한 곳은
   * 전부 이 함수를 거쳐야 한다 — 한 군데라도 빠지면 "공격력은 올랐는데 체력은
   * 그대로" 같은 형태로 조용히 어긋난다.
   */
  private statsOf(sessionId: string, job: JobId, level: number): Stats {
    const base = statsFor(job, level);
    const viewer = this.viewers.get(sessionId);
    if (!viewer) return base;

    const bonus = equipmentStats(viewer.character.equipment);
    return {
      ...base,
      attack: base.attack + bonus.attack,
      defense: base.defense + bonus.defense,
      maxHp: base.maxHp + bonus.maxHp,
      // 상한은 쓰는 쪽(rollCrit / effectiveCooldown)에서 자른다
      crit: base.crit + bonus.crit,
      critDamage: base.critDamage + bonus.critDamage,
      attackSpeed: base.attackSpeed + bonus.attackSpeed,
    };
  }

  /** 가방·골드·장비를 본인에게만 보낸다 */
  private sendInventory(viewer: Viewer): void {
    viewer.client.send('inventory', {
      gold: viewer.character.gold,
      items: viewer.character.inventory,
      equipment: viewer.character.equipment,
    });
  }

  /** 장비가 바뀌면 최대치도, 남에게 보이는 겉모습도 따라 움직인다 */
  private refreshMax(sessionId: string, player: PlayerState): void {
    const stats = this.statsOf(sessionId, player.job as JobId, player.level);
    player.maxHp = stats.maxHp;
    player.hp = Math.min(player.hp, stats.maxHp);
    this.syncLook(sessionId, player);
  }

  /**
   * 화면에 그려지는 장비를 상태에 반영한다.
   *
   * 네 자리만 내려간다. 무기·투구는 모델에 붙일 것이 있고, 갑옷·신발은
   * 몸통과 다리 색으로 보여준다. 반지·목걸이는 **보여줄 방법이 없어서**
   * 안 보낸다 — 안 그릴 걸 보내면 대역폭만 쓴다.
   * (보조·귀걸이는 2026-09-18 에 슬롯 자체를 없앴다)
   */
  private syncLook(sessionId: string, player: PlayerState): void {
    const gear = this.viewers.get(sessionId)?.character.equipment;
    player.weapon = gear?.weapon?.id ?? '';
    player.helmet = gear?.helmet?.id ?? '';
    player.armor = gear?.armor?.id ?? '';
    player.boots = gear?.boots?.id ?? '';
  }

  /**
   * 장착.
   *
   * 가방에 있는지, 그 직업이 낄 수 있는지, 레벨이 되는지를 **서버가 다시 본다.**
   * 클라이언트 목록은 표시일 뿐이다.
   */
  /**
   * 장착.
   *
   * 아이템 id 가 아니라 **가방 칸 번호**로 받는다. 같은 아이템의 등급 다른 것이
   * 여러 개 있을 수 있어서 id 만으로는 어느 것을 낄지 정할 수 없다.
   *
   * 가방에 있는지, 그 직업이 낄 수 있는지, 레벨이 되는지를 **서버가 다시 본다.**
   */
  private handleEquip(client: Client, index: number): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player || typeof index !== 'number') return;

    const stack = viewer.character.inventory[index];
    if (!stack) return;

    const item = getItem(stack.id);
    if (!item || !item.slot) return; // 재료는 낄 수 없다
    if (!canEquip(item, player.job as JobId, player.level)) {
      client.send('notice', { text: '아직 착용할 수 없습니다.' });
      return;
    }

    // 끼고 있던 건 가방으로 돌려보낸다
    const previous = viewer.character.equipment[item.slot];
    viewer.character.inventory.splice(index, 1);
    if (previous) viewer.character.inventory.push(previous);
    viewer.character.equipment[item.slot] = stack;

    this.refreshMax(client.sessionId, player);
    this.sendInventory(viewer);
    this.persist(client.sessionId);
  }

  private handleUnequip(client: Client, slot: string): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player) return;
    if (!EQUIP_SLOTS.includes(slot as EquipSlot)) return;

    const itemId = viewer.character.equipment[slot];
    if (!itemId) return;
    if (viewer.character.inventory.length >= INVENTORY_SIZE) {
      client.send('notice', { text: '가방이 가득 찼습니다.' });
      return;
    }

    delete viewer.character.equipment[slot];
    viewer.character.inventory.push(itemId);

    this.refreshMax(client.sessionId, player);
    this.sendInventory(viewer);
    this.persist(client.sessionId);
  }

  /**
   * 처음 들어온 캐릭터에게 1레벨 스킬 하나와 그동안 쌓였을 포인트를 준다.
   *
   * 아무것도 없으면 때릴 수단이 기본 공격뿐이라 시작이 답답하고,
   * 스킬 시스템이 생기기 전에 키운 캐릭터는 포인트가 0인 채로 남는다.
   *
   * **테스트 스위치(`SKILL_UNLOCK_ALL`)가 켜져 있으면 그 직업 스킬을 전부 준다.**
   * 레벨과 포인트를 풀어 놔도 스킬창에서 한 번씩 눌러야 배워지는데, 이펙트나 판정을
   * 보려고 들어올 때마다 그걸 반복하는 건 확인이 아니라 잡일이다. 액션바는 4칸이라
   * 앞의 넷만 올라간다 — 나머지는 스킬창에서 바꿔 끼운다.
   * 스위치를 끄면 **이미 배운 것은 그대로 남는다** (저장된 캐릭터라서).
   */
  private grantStartingSkill(viewer: Viewer, job: JobId, level: number): void {
    const all = JOB_SKILLS[job] ?? [];

    if (SKILL_UNLOCK_ALL) {
      const before = viewer.character.skills.length;
      for (const id of all) {
        if (!viewer.character.skills.includes(id)) viewer.character.skills.push(id);
        if (viewer.character.skillBar.length < SKILL_BAR_SIZE && !viewer.character.skillBar.includes(id)) {
          viewer.character.skillBar.push(id);
        }
      }
      if (viewer.character.skills.length !== before) this.persist(viewer.client.sessionId);
      return;
    }

    if (viewer.character.skills.length === 0) {
      const first = all[0];
      if (first) {
        viewer.character.skills.push(first);
        viewer.character.skillBar.push(first);
        // 1레벨 스킬은 공짜로 준다. 그 뒤로 레벨마다 한 점씩.
        viewer.character.skillPoints += Math.max(0, level - 1);
        this.persist(viewer.client.sessionId);
      }
    }
  }

  // ---------------------------------------------------------------- 스킬

  /** 배운 스킬·액션바·포인트를 본인에게만 보낸다 */
  private sendSkills(viewer: Viewer): void {
    viewer.client.send('skills', {
      learned: viewer.character.skills,
      bar: viewer.character.skillBar,
      points: viewer.character.skillPoints,
    });
  }

  /**
   * 스킬 배우기.
   *
   * 그 직업 스킬인지, 레벨이 되는지, 포인트가 남았는지를 **서버가 다시 본다.**
   * 스킬창은 표시일 뿐이다.
   */
  private handleLearnSkill(client: Client, skillId: string): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player || typeof skillId !== 'string') return;

    const skill = SKILLS[skillId];
    if (!skill) return;

    if (viewer.character.skills.includes(skillId)) return; // 이미 배웠다

    // 테스트 스위치(SKILL_UNLOCK_ALL)가 켜져 있으면 레벨을 안 본다
    if (!canLearn(skill, player.job as JobId, player.level)) {
      client.send('notice', { text: `Lv.${skill.reqLevel} 부터 배울 수 있습니다.` });
      return;
    }
    // 같은 스위치가 켜져 있으면 0 이다 — 그때는 아래 검사도 차감도 그냥 지나간다
    const cost = skillPointCost();
    if (viewer.character.skillPoints < cost) {
      client.send('notice', { text: '스킬 포인트가 없습니다.' });
      return;
    }

    viewer.character.skills.push(skillId);
    viewer.character.skillPoints -= cost;

    // 자리가 비어 있으면 바로 올려준다 — 배우고 또 끌어다 놓게 하면 번거롭다
    if (viewer.character.skillBar.length < SKILL_BAR_SIZE) {
      viewer.character.skillBar.push(skillId);
    }

    client.send('notice', { text: `${skill.name} 을(를) 배웠습니다.` });
    this.sendSkills(viewer);
    this.persist(client.sessionId);
  }

  /** 액션바 구성 — 배운 것 중에서만, 최대 4개 */
  private handleSetSkillBar(client: Client, ids: string[]): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player || !Array.isArray(ids)) return;

    const job = player.job as JobId;
    const bar: string[] = [];
    for (const id of ids) {
      if (typeof id !== 'string') continue;
      if (bar.includes(id)) continue; // 같은 스킬을 두 칸에 두지 않는다
      if (!viewer.character.skills.includes(id)) continue;
      if (!skillForJob(job, id)) continue;
      bar.push(id);
      if (bar.length >= SKILL_BAR_SIZE) break;
    }

    viewer.character.skillBar = bar;
    this.sendSkills(viewer);
    this.persist(client.sessionId);
  }

  // ---------------------------------------------------------------- NPC

  /**
   * 그 역할의 NPC 옆에 서 있는지 확인한다.
   *
   * **위치를 서버가 다시 본다.** 안 그러면 사냥터 한복판에서 상점을 열어
   * 장비를 사고팔 수 있다. 마을까지 걸어오는 게 이 게임의 유일한 마찰이다.
   */
  private npcNear(player: PlayerState, role: NpcRole): boolean {
    for (const npc of this.def.npcs ?? []) {
      if (npc.role !== role) continue;
      if (Math.hypot(npc.x - player.x, npc.z - player.z) <= NPC_REACH) return true;
    }
    return false;
  }

  /**
   * 상점 재고 — 자기 직업의 **1등급 무기**만 판다.
   *
   * 좋은 물건은 사냥과 제작으로 얻는 게 이 게임의 뼈대다. 상점이 방어구까지
   * 다 갖추면 골드만 모아 한 번에 차려입게 되어 사냥할 이유가 준다.
   * 무기만 파는 건 "일단 때릴 건 있어야 시작한다"는 최소한이다.
   */
  private shopStock(player: PlayerState): string[] {
    // 장비는 직업을 안 탄다 (2026-09-21) — 진열은 등급으로만 거른다.
    // 낄 수 있는 등급과 그 아래 하나까지 — 아래를 같이 두는 건 강화 여벌 때문이다
    const top = gradeForLevel(player.level);
    return Object.values(ITEMS)
      .filter(
        (item) =>
          item.slot === 'weapon' && item.level <= player.level && item.grade >= top - 1
      )
      .map((item) => item.id);
  }

  private handleNpcOpen(client: Client, role: string): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player) return;
    if (role !== 'shop' && role !== 'smith' && role !== 'jobs') return;

    if (!this.npcNear(player, role)) {
      client.send('notice', { text: '너무 멉니다. 가까이 가세요.' });
      return;
    }

    client.send('npc', {
      role,
      stock: role === 'shop' ? this.shopStock(player) : [],
      // 대장간 제작(`forge`)은 2026-09-20 에 걷었다 — 클라이언트 호환을 위해 빈 칸만 남긴다
      forge: [],
      jobs: role === 'jobs' ? [...JOB_IDS] : [],
    });
  }

  private handleNpcBuy(client: Client, itemId: string): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player || typeof itemId !== 'string') return;
    if (!this.npcNear(player, 'shop')) return;

    // 파는 목록에 있는 물건만 살 수 있다 — 클라이언트가 보낸 id 를 믿지 않는다
    if (!this.shopStock(player).includes(itemId)) return;

    const item = getItem(itemId);
    if (!item) return;

    if (viewer.character.inventory.length >= INVENTORY_SIZE) {
      client.send('notice', { text: '가방이 가득 찼습니다.' });
      return;
    }
    if (viewer.character.gold < item.price) {
      client.send('notice', { text: `골드가 ${item.price - viewer.character.gold} 모자랍니다.` });
      return;
    }

    viewer.character.gold -= item.price;
    // 옵션은 **서버가** 굴린다. 물건이 생기는 자리마다 굴려야 굴리지 않은
    // 물건(옵션 0개)이 섞이지 않는다.
    viewer.character.inventory.push({ id: itemId, grade: 1, options: rollOptions(item, 1) });
    client.send('notice', { text: `${item.name} 구입` });
    this.sendInventory(viewer);
    this.persist(client.sessionId);
  }

  private handleNpcSell(client: Client, index: number): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player || typeof index !== 'number') return;
    if (!this.npcNear(player, 'shop')) return;

    const stack = viewer.character.inventory[index];
    if (!stack) return;

    const item = getItem(stack.id);
    if (!item) return;

    // 등급이 높으면 더 쳐준다. 애써 올린 걸 헐값에 넘기면 팔 이유가 없다.
    const price = Math.max(1, Math.round(item.price * 0.4 * gradeMultiplier(stack.grade)));
    viewer.character.inventory.splice(index, 1);
    viewer.character.gold += price;

    client.send('notice', { text: `${item.name} 판매 — ${price} G` });
    this.sendInventory(viewer);
    this.persist(client.sessionId);
  }

  /**
   * 강화 — 골드를 걸고 운을 본다.
   *
   * 굴림을 **서버가 한다.** 클라이언트가 결과를 보내게 두면 전부 성공이 된다.
   * 실패해도 골드는 돌려주지 않는다 — 걸었으니 잃는 게 이 시스템의 전부다.
   */
  private handleNpcEnhance(client: Client, index: number): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player || typeof index !== 'number') return;
    if (!this.npcNear(player, 'smith')) {
      client.send('notice', { text: '대장간에서만 강화할 수 있습니다.' });
      return;
    }

    const stack = viewer.character.inventory[index];
    if (!stack) return;

    const item = getItem(stack.id);
    if (!item) return;

    const level = stack.enhance ?? 0;
    if (!canEnhance(level)) {
      client.send('notice', { text: `+${level} 이 최고입니다.` });
      return;
    }

    const cost = enhanceCost(item, level);
    if (viewer.character.gold < cost) {
      client.send('notice', { text: `골드가 ${cost - viewer.character.gold} 모자랍니다.` });
      return;
    }

    viewer.character.gold -= cost;
    const result = rollEnhance(level, Math.random());

    if (result === 'success') {
      stack.enhance = level + 1;
      client.send('notice', { text: `${item.name} +${stack.enhance} 강화 성공!` });
    } else if (result === 'keep') {
      client.send('notice', { text: `${item.name} +${level} 유지 — 실패했습니다.` });
    } else {
      viewer.character.inventory.splice(index, 1);
      client.send('notice', { text: `${item.name} +${level} 이(가) 부서졌습니다.` });
    }

    client.send('enhanceResult', { result, level: stack.enhance ?? level });
    this.sendInventory(viewer);
    this.persist(client.sessionId);
  }

  /**
   * 전직.
   *
   * 직업이 바뀌면 무기와 보조는 못 쓰게 되므로 가방으로 돌려보낸다.
   * 낀 채로 두면 능력치는 붙는데 창에는 못 끼는 물건이 박혀 있는 꼴이 된다.
   */
  private handleNpcJob(client: Client, job: string): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player || !isJobId(job)) return;
    if (!this.npcNear(player, 'jobs')) return;

    if (player.job === job) {
      client.send('notice', { text: '이미 그 직업입니다.' });
      return;
    }

    for (const slot of EQUIP_SLOTS) {
      const equipped = viewer.character.equipment[slot];
      if (!equipped) continue;
      const item = getItem(equipped.id);
      if (!item?.job || item.job === job) continue;

      delete viewer.character.equipment[slot];
      if (viewer.character.inventory.length < INVENTORY_SIZE) {
        viewer.character.inventory.push(equipped);
      }
    }

    player.job = job;
    viewer.character.job = job;
    setCharacterJob(viewer.character.id, job);

    this.refreshMax(client.sessionId, player);
    // 스킬이 통째로 바뀌므로 쿨타임과 자동 시전 목록을 지운다
    this.autoSkills.delete(client.sessionId);
    for (const skillId of JOB_SKILLS[job] ?? []) {
      this.skillReadyAt.delete(`${client.sessionId}:${skillId}`);
    }

    client.send('jobChanged', { job });
    client.send('notice', { text: `${job} (으)로 전직했습니다.` });
    this.sendInventory(viewer);
    this.persist(client.sessionId);
  }

  /**
   * 기본 공격.
   *
   * `focus` 는 서버가 모는 경로(자동 사냥)가 "이 놈을 친다"고 넘겨준 것이다.
   * 사람이 눌렀으면 비어 있고, 그때는 **클릭으로 찍어 둔 타겟**을 쓴다.
   */
  private handleAttack(client: Client, focus?: MonsterState): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player || player.dead) return;

    const now = Date.now();
    const job = player.job as JobId;
    const stats = this.statsOf(client.sessionId, job, player.level);
    const aim = focus ?? this.focusOf(client.sessionId);
    if (aim) this.faceMonster(player, aim);
    const ready = this.nextAttackAt.get(client.sessionId) ?? 0;
    if (now < ready) return; // 쿨타임 — 연타해도 소용없다
    const cooldown = effectiveCooldown(stats.attackCooldown, stats.attackSpeed);
    this.nextAttackAt.set(client.sessionId, now + cooldown);

    // 휘두르는 동안은 못 움직인다 (`handleInput` · `stepAutoPlayer` 가 본다)
    const rootMs = attackRootMs(cooldown);
    this.rootedUntil.set(client.sessionId, now + rootMs);

    // 헛스윙도 클라이언트에 알려야 모션이 나온다.
    // `rootMs` 를 같이 보내는 이유는 클라이언트가 **같은 시간만큼** 예측을 멈춰야
    // 하기 때문이다. 장비가 붙인 공격 속도는 서버만 알아서 클라가 다시 못 구한다.
    this.broadcast('swing', { id: player.id, rootMs });

    // 원거리 직업(투사체가 있는 직업)은 겨눈 놈에게 날아가 맞는다.
    // 근접은 예전처럼 내 몸 앞 부채꼴이다 — 아래 handleSkill 과 같은 규칙이다.
    const onTarget = this.blastAt(player, aim, !!BASIC_PROJECTILE[job], stats.attackRange);

    const hits = this.combat.resolvePlayerAttack(
      player,
      stats.attack,
      onTarget ? SKILL_BLAST_MIN : stats.attackRange,
      now,
      undefined,
      1,
      {
        projectile: BASIC_PROJECTILE[job],
        crit: stats.crit,
        critDamage: stats.critDamage,
        ...(onTarget ? { origin: onTarget } : {}),
      }
    );
    this.awardHits(client, viewer, player, hits);
  }

  /**
   * 스킬 사용.
   *
   * 이 직업이 실제로 가진 스킬인지, 쿨타임이 돌았는지를
   * **서버가 다시 확인한다.** 클라이언트 액션바는 표시일 뿐이다.
   */
  private handleSkill(client: Client, skillId: string, focus?: MonsterState): void {
    const viewer = this.viewers.get(client.sessionId);
    const player = this.state.players.get(client.sessionId);
    if (!viewer || !player || player.dead) return;

    const job = player.job as JobId;
    const skill = skillForJob(job, typeof skillId === 'string' ? skillId : '');
    if (!skill) return; // 없는 스킬이거나 다른 직업 스킬

    /**
     * 배워서 액션바에 올린 것만 쓸 수 있다.
     *
     * **테스트 스위치(`SKILL_UNLOCK_ALL`)가 켜져 있으면 액션바를 안 본다.** 화면 왼쪽
     * 디버그 목록(`ui/skillDebug.ts`)이 장착 없이 바로 쏘기 때문이다. 직업과 쿨타임은
     * 그대로 본다 — 남의 직업 스킬까지 열어 주면 확인이 아니라 딴 게 된다.
     */
    if (!SKILL_UNLOCK_ALL && !viewer.character.skillBar.includes(skill.id)) return;

    // 겨눈 쪽으로 몸을 돌리는 것은 **쿨타임을 돌리기 전에** 한다. 회복기도
    // 대상을 향해 서야 이펙트가 엉뚱한 쪽을 보지 않는다.
    /**
     * 겨눈 놈이 없으면 **사거리 안에서 가장 가까운 놈**을 잡아서 그쪽으로 쏜다
     * (`acquireTarget`). 때리지 않는 스킬(회복기, `maxTargets <= 0`)은 잡지 않는다 —
     * 조준이 걸릴 이유가 없는데 엉뚱하게 표시만 켜진다.
     */
    const aim =
      focus ??
      this.focusOf(client.sessionId) ??
      (skill.maxTargets > 0 ? this.acquireTarget(client, player, skill.range) : null);
    if (aim) this.faceMonster(player, aim);

    const now = Date.now();
    const key = `${client.sessionId}:${skill.id}`;
    if (now < (this.skillReadyAt.get(key) ?? 0)) return;
    // 테스트 스위치(SKILL_COOLDOWN_OFF)가 켜져 있으면 0 이다
    const cooldown = skillCooldown(skill);
    this.skillReadyAt.set(key, now + cooldown);

    const stats = this.statsOf(client.sessionId, job, player.level);

    // 스킬도 같은 공격 모션을 쓰므로 같은 동안 발이 묶인다.
    // **기본 공격 간격으로 자른다** — 스킬 쿨타임(수 초)으로 자르면 걷지도 못하고,
    // 테스트 스위치(`SKILL_COOLDOWN_OFF`)로 쿨타임이 0 이 되면 경직까지 0 이 된다.
    const rootMs = attackRootMs(effectiveCooldown(stats.attackCooldown, stats.attackSpeed));
    this.rootedUntil.set(client.sessionId, now + rootMs);
    this.broadcast('skill', { id: player.id, skillId: skill.id, rootMs });

    // 회복형 스킬은 공격 판정을 하지 않는다
    if (skill.selfHeal) {
      const healed = Math.round(stats.maxHp * skill.selfHeal);
      const before = player.hp;
      player.hp = Math.min(stats.maxHp, player.hp + healed);
      this.broadcast('hit', {
        targetId: player.id,
        targetKind: 'player',
        amount: player.hp - before,
        killed: false,
        sourceId: player.id,
        x: player.x,
        z: player.z,
        heal: true,
      });
      return;
    }

    /**
     * **겨눈 놈이 있으면 원거리 스킬은 그 자리에서 터진다.** ★
     *
     * 근접기는 여전히 내 몸이 중심이다 — 내 앞을 베는 동작인데 판정만 저쪽에서
     * 나면 이펙트와 어긋난다. 원거리기는 반대로, 날아가서 터지는 것이라 시전자
     * 정면 부채꼴로 재면 "타겟을 찍었는데 옆에 있던 놈만 맞는" 일이 난다.
     */
    const onTarget = this.blastAt(player, aim, isRangedSkill(skill), skill.range);

    const hits = this.combat.resolvePlayerAttack(
      player,
      Math.round(stats.attack * skill.power),
      onTarget ? blastRadius(skill) : skill.range,
      now,
      skill.arc,
      skill.maxTargets,
      {
        projectile: skill.projectile,
        crit: stats.crit,
        critDamage: stats.critDamage,
        // 맞은 자리에서 그 스킬 이펙트가 터지도록 어느 스킬이었는지 같이 보낸다
        skillId: skill.id,
        ...(onTarget ? { origin: onTarget } : {}),
      }
    );
    this.awardHits(client, viewer, player, hits);
  }

  /** 명중 결과를 전파하고, 처치했으면 경험치를 준다 */
  private awardHits(
    client: Client,
    viewer: Viewer,
    player: PlayerState,
    hits: { targetId: string; killed: boolean }[]
  ): void {
    if (hits.length === 0) return;

    let gained = 0;
    let gold = 0;
    const killedNames: string[] = [];
    const lootedNames: string[] = [];

    for (const hit of hits) {
      this.broadcast('hit', hit);
      if (!hit.killed) continue;
      const kind = this.combat.monsterKindOf(hit.targetId);
      if (!kind) continue;
      gained += expReward(kind.level, player.level, kind.expReward);
      killedNames.push(kind.name);

      // 보상은 바로 가방으로 넣는다. 바닥에 떨어뜨리면 아이템도 하나의 엔티티가
      // 되어 AoI·동기화·줍기 판정이 전부 따라붙는다 — 지금 필요한 무게가 아니다.
      if (kind.boss) {
        // 보스 전용 아이템은 나중에 만든다 — 그때까지 보상은 금화뿐이다
        gold += rollBossDrop(kind.level).gold;
        this.announce(`${player.name} 님이 ${kind.name} 을(를) 쓰러뜨렸습니다!`);
        continue;
      }

      const drop = rollDrop(kind.level, player.job as JobId);
      gold += drop.gold;
      if (drop.item && viewer.character.inventory.length < INVENTORY_SIZE) {
        viewer.character.inventory.push(drop.item);
        const def = getItem(drop.item.id);
        lootedNames.push(`${def?.name ?? drop.item.id} (${drop.item.grade}등급)`);
      }
    }

    if (gained === 0) return;

    if (gold > 0 || lootedNames.length > 0) {
      viewer.character.gold += gold;
      client.send('loot', { gold, items: lootedNames });
      this.sendInventory(viewer);
    }

    const before = player.level;
    const after = applyExp(player.level, player.exp, gained);
    player.level = after.level;
    player.exp = after.exp;

    if (after.level !== before) {
      // 레벨이 오르면 최대치가 늘고 가득 채워준다
      const grown = this.statsOf(client.sessionId, player.job as JobId, player.level);
      player.maxHp = grown.maxHp;
      player.hp = grown.maxHp;
      // 레벨마다 스킬 포인트를 준다
      viewer.character.skillPoints += SKILL_POINT_PER_LEVEL * (after.level - before);
      this.sendSkills(viewer);
      client.send('levelUp', { level: player.level });
    }

    client.send('reward', { exp: gained, name: killedNames.join(', ') });
    saveCharacterProgress(viewer.character.id, player.level, player.exp);
  }

  /**
   * 범위 공격 예고.
   *
   * 원을 그릴 정보만 보낸다. **판정은 서버가 `burstAoe` 에서 따로 한다** —
   * 클라이언트가 "나는 피했다"고 말하게 두면 그 말을 믿어야 한다.
   * 그래서 이 메시지는 순전히 보여주기용이고, 안 받아도 맞을 사람은 맞는다.
   *
   * `hit` 과 마찬가지로 방 전체에 뿌린다. 멀리 있는 원은 화면 밖이라 보이지
   * 않고, 시야 목록을 따로 관리하는 비용이 그림 하나보다 비싸다.
   */
  private announceAoe(monster: MonsterState, kind: MonsterKind, x: number, z: number): void {
    if (!kind.aoe) return;
    this.broadcast('aoe', {
      id: monster.id,
      name: kind.name,
      x,
      z,
      radius: kind.aoe.radius,
      delayMs: kind.aoe.windupMs,
    });
  }

  /**
   * 범위 공격이 터졌다. 원 안에 서 있는 사람이 맞는다.
   *
   * 피해는 평타와 **같은 `damagePlayer`** 를 탄다. 방어 감쇠·`hit` 방송·
   * 사망 처리를 두 벌 만들면 반드시 한쪽만 고치는 실수가 난다.
   */
  private burstAoe(monster: MonsterState, kind: MonsterKind, x: number, z: number): void {
    if (!kind.aoe) return;
    const radius = kind.aoe.radius;
    const attack = Math.round(kind.attack * kind.aoe.power);
    for (const player of this.grid.queryRadius(x, z, radius)) {
      if (player.dead) continue;
      // 격자 조회는 사각형이라 모서리가 딸려 온다. 원으로 다시 자른다 —
      // 안 자르면 화면에 그린 원 밖에 서 있는데 맞는다.
      if (Math.hypot(player.x - x, player.z - z) > radius) continue;
      this.damagePlayer(player, attack, monster.id);
    }
  }

  /** 몬스터가 플레이어를 때렸다 */
  private damagePlayer(player: PlayerState, attack: number, sourceId: string): void {
    if (player.dead) return;
    const stats = this.statsOf(player.id, player.job as JobId, player.level);
    /**
     * 무적이면 체력을 안 깎는다. **그래도 `hit` 은 그대로 보낸다** (`amount: 0`) —
     * 몬스터의 공격 동작은 이 메시지로 도는 구조라(`monsters.swing`), 여기서
     * 막아 버리면 동작을 보려고 켠 무적이 동작을 못 보게 만든다.
     */
    const godmode = this.godmode.has(player.id);
    const amount = godmode ? 0 : computeDamage(attack, stats.defense);
    player.hp = Math.max(0, player.hp - amount);

    this.broadcast('hit', {
      targetId: player.id,
      targetKind: 'player',
      amount,
      killed: player.hp === 0,
      sourceId,
      x: player.x,
      z: player.z,
    });

    if (player.hp === 0) {
      // 시간이 지나도 저절로 살아나지 않는다. ★
      // 사람이 사망 화면을 눌러 마을 룸으로 들어오면 그때 되살아난다
      // (enterWorld 의 revive). 예전처럼 5초 뒤 제자리에서 일으켜 세우면
      // 죽은 걸 읽기도 전에 화면이 사라져서, 죽은 줄도 모르게 된다.
      player.dead = true;
      this.announce(`${player.name} 님이 쓰러졌습니다.`);
    }
  }

  private findByName(name: string): PlayerState | undefined {
    const lowered = name.toLowerCase();
    for (const player of this.state.players.values()) {
      if (player.name.toLowerCase() === lowered) return player;
    }
    return undefined;
  }

  /** 슬라이딩 윈도우 도배 제한 */
  private allowChat(sessionId: string): boolean {
    const now = Date.now();
    const history = this.chatHistory.get(sessionId) ?? [];
    const recent = history.filter((t) => now - t < CHAT_WINDOW_MS);
    if (recent.length >= CHAT_BURST) {
      this.chatHistory.set(sessionId, recent);
      return false;
    }
    recent.push(now);
    this.chatHistory.set(sessionId, recent);
    return true;
  }

  private announce(text: string): void {
    this.broadcast('chat', { kind: 'system', from: '', text });
  }

  /**
   * 관심영역 갱신.
   *
   * 매 틱 각 시청자의 구독 셀 안에 있는 플레이어를 모아 이전 집합과 비교한다.
   * "이동한 플레이어만 처리"하는 최적화도 가능하지만, 시청자가 움직인 경우와
   * 대상이 움직인 경우를 모두 놓치지 않으려면 이 방식이 확실하다.
   * 150명 존에서도 틱당 수천 번 수준이라 비용이 문제되지 않는다.
   */
  private tick(): void {
    const now = Date.now();
    const dt = Math.min((now - this.lastTickAt) / 1000, 0.5);
    this.lastTickAt = now;

    // --- 몬스터 AI ---
    this.combat.tick(dt, now, this.grid, (id) => this.state.players.get(id), {
      hitPlayer: (player, monster, kind) => this.damagePlayer(player, kind.attack, monster.id),
      aoeCast: (monster, kind, x, z) => this.announceAoe(monster, kind, x, z),
      aoeBurst: (monster, kind, x, z) => this.burstAoe(monster, kind, x, z),
    });

    // --- 자동 사냥 / 클릭 추격 ---
    this.driveAutoHunt(dt);
    this.sweepTargets();

    // 주기적으로 위치를 남긴다. 서버가 갑자기 죽어도 최근 위치는 지킨다.
    this.saveTimer += TICK_MS;
    if (this.saveTimer >= SAVE_INTERVAL_MS) {
      this.saveTimer = 0;
      for (const id of this.viewers.keys()) this.persist(id);
    }

    for (const viewer of this.viewers.values()) {
      const self = this.state.players.get(viewer.client.sessionId);
      if (!self) continue;

      viewer.aoi.update(this.grid, self.x, self.z);

      const view = viewer.client.view;
      if (!view) continue;

      const next = new Set<string>();

      const nearby = this.grid.queryCells(viewer.aoi.cells, this.scratch);
      for (const player of nearby) {
        next.add(player.id);
        if (!viewer.visible.has(player.id)) view.add(player);
      }

      // 몬스터도 같은 셀 기준으로 걸러 보낸다
      for (const monster of this.combat.grid.queryCells(viewer.aoi.cells)) {
        next.add(monster.id);
        if (!viewer.visible.has(monster.id)) view.add(monster);
      }

      // 자기 자신은 셀 밖으로 나갈 수 없지만, 방어적으로 항상 유지한다
      next.add(self.id);

      for (const id of viewer.visible) {
        if (next.has(id)) continue;
        const gonePlayer = this.state.players.get(id);
        if (gonePlayer) {
          view.remove(gonePlayer);
          continue;
        }
        const goneMonster = this.state.monsters.get(id);
        if (goneMonster) view.remove(goneMonster);
      }

      viewer.visible = next;
    }
  }
}
