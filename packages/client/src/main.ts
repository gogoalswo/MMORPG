import * as THREE from 'three';
import {
  SKILLS,
  START_ZONE,
  ZONES,
  getMonsterKind,
  getSpawn,
  getZone,
  type ProjectileKind,
  type ZoneDef,
} from '@mmo/shared';
import { setupLighting } from './scene/lighting';
import { buildZoneScene, type ZoneScene } from './scene/zoneScene';
import { CLASSES, type ClassId } from './game/characterClasses';
import { CameraRig } from './game/cameraRig';
import { Input } from './game/input';
import { Player } from './game/player';
import { NameplateLayer } from './ui/nameplate';
import { ZoneTransition } from './ui/zoneTransition';
import { ChatUI } from './ui/chat';
import { CharacterCreateUI } from './ui/characterCreate';
import { CharacterSelectUI } from './ui/characterSelect';
import { ZoneConnection, readCharacterId } from './net/connection';
import { RemotePlayers } from './game/remotePlayers';
import { RemoteMonsters } from './game/remoteMonsters';
import { CombatHud } from './ui/combatHud';
import { ActionBar } from './ui/actionBar';
import { AutoHuntToggle } from './ui/autoHuntToggle';
import { InventoryPanel } from './ui/inventory';
import { NpcDialog } from './ui/npcDialog';
import { NpcPrompt } from './ui/npcPrompt';
import { SkillBook } from './ui/skillBook';
import { HudButtons, type HudPanel } from './ui/hudButtons';
import { loadAssets, type Assets } from './scene/assets';
import { ensureBeasts, setModels } from './game/rigFactory';
import { PostFX } from './render/postfx';
import { Projectiles } from './scene/projectiles';
import { SkillFx, skillColor } from './scene/skillFx';
import { AoeMarkers } from './scene/aoeMarkers';
import { ZoneGate } from './ui/zoneGate';
import { CraftWindow } from './ui/craftWindow';

const canvas = document.getElementById('game') as HTMLCanvasElement;
const overlay = document.getElementById('overlay') as HTMLElement;
const statsEl = document.getElementById('stats') as HTMLElement;

// --- 렌더러 ---
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
// 톤매핑은 후처리의 OutputPass 가 적용한다 (렌더러 설정을 그대로 읽어간다)
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
// 후처리는 여러 패스를 그린다. 자동 리셋을 끄고 프레임 단위로 합산해야 통계가 의미를 가진다.
renderer.info.autoReset = false;

const scene = new THREE.Scene();
const sun = setupLighting(scene);

// 텍스처와 HDRI 를 먼저 받아둔다. 이후 존 구성은 전부 동기 처리된다.
// 실패하면 검은 화면만 남으므로 이유를 화면에 띄운다.
let assets: Assets;
try {
  assets = await loadAssets(renderer);
} catch (err) {
  const reason = err instanceof Error ? err.message : String(err);
  statsEl.textContent = `에셋 로딩 실패\n${reason}\npublic/assets 경로를 확인하세요`;
  throw err;
}
scene.environment = assets.environment;
// 리그를 만드는 자리가 여러 곳이라, 모델은 여기서 한 번 넘겨둔다
setModels(assets.models);

// --- 플레이어 ---
/**
 * 테스트용 이름 지정: ?name=길동
 *
 * 브라우저를 두 개 띄워 확인할 때 둘 다 "나" 면 누가 누군지 구분이 안 된다.
 * Phase 2 에서 계정/캐릭터 시스템이 생기면 이 자리를 대체한다.
 */
function resolvePlayerName(): string {
  const fromQuery = new URLSearchParams(location.search).get('name');
  if (fromQuery) {
    const name = fromQuery.trim().slice(0, 12);
    try {
      localStorage.setItem('mmo:name', name);
    } catch {
      /* 저장이 막혀도 이번 접속은 된다 */
    }
    return name;
  }
  try {
    const saved = localStorage.getItem('mmo:name');
    if (saved) return saved;
  } catch {
    /* 무시 */
  }
  return '나';
}

// 서버가 확정해준 캐릭터 이름. 접속 전에는 요청값을 임시로 쓴다.
let characterName = resolvePlayerName();
const player = new Player(characterName, 'knight');
scene.add(player.group);

const nameplates = new NameplateLayer(overlay);
const playerPlate = {
  object: player.group,
  headHeight: player.headHeight,
  name: `${characterName} (${CLASSES[player.job].label})`,
  hp: 100,
  maxHp: 100,
};

// --- 네트워크 ---
const remotePlayers = new RemotePlayers(nameplates);
scene.add(remotePlayers.group);

const monsters = new RemoteMonsters(nameplates);
scene.add(monsters.group);

/** 서버가 알려준 명중 좌표를 담아 쓰는 임시 벡터 */
const hitPoint = new THREE.Vector3();

const projectiles = new Projectiles();
scene.add(projectiles.group);

const aoeMarkers = new AoeMarkers();
scene.add(aoeMarkers.group);
const skillFx = new SkillFx();
scene.add(skillFx.group);

/** 명중 섬광 색 — 투사체와 맞추고, 없으면 옅은 금색 */
const IMPACT_COLOR: Record<string, number> = {
  arrow: 0xd8e8a0,
  fireball: 0xff9a3c,
  spark: 0x9fe6ff,
};

const hud = new CombatHud(overlay);
hud.setVisible(false);

/** 마을 차원문 창 — 밟으면 열리고, 고르면 그 사냥터로 간다 */
const zoneGate = new ZoneGate(overlay);

/** 제작창 — 대장간에서 열린다. 상점·전직은 그대로 npcDialog 가 맡는다 */
const craftWindow = new CraftWindow(overlay);

const actionBar = new ActionBar(overlay);
actionBar.setVisible(false);

const autoHuntToggle = new AutoHuntToggle(overlay);
autoHuntToggle.setVisible(false);

const bag = new InventoryPanel(overlay);
const npcDialog = new NpcDialog(overlay);
const npcPrompt = new NpcPrompt(overlay);
const skillBook = new SkillBook(overlay);
const hudButtons = new HudButtons(overlay);
/** 매 프레임 다시 만들지 않으려고 하나를 재사용한다 */
const openPanels = new Set<HudPanel>();
hudButtons.setVisible(false);

/** 내 전투 상태 — 서버가 보내주는 값을 그대로 보여준다 */
let myState = {
  level: 1,
  hp: 0,
  maxHp: 1,
  exp: 0,
  dead: false,
  auto: false,
  chasing: false,
};

let netStatus = '연결 중';
let accountStatus = '확인 중';

const connection = new ZoneConnection({
  onSelf: (x, z, lastSeq, status) => {
    // 서버가 모는 동안에는 보정 대신 서버 자세를 그대로 따라간다
    if (status.auto || status.chasing) player.setServerPose(x, z, status.rotY);
    else player.reconcile(x, z, lastSeq);
    myState = status;
    hud.setStatus(status.level, status.hp, status.maxHp, status.exp);
    autoHuntToggle.setOn(status.auto);
    player.setGear(status.gear);
    bag.setCharacter(player.job, status.level);
    skillBook.setCharacter(player.job, status.level);
    npcDialog.setCharacter(player.job, status.level);
    zoneGate.setLevel(status.level);
    playerPlate.hp = status.hp;
    playerPlate.maxHp = status.maxHp;
  },
  onRemoteAdd: (entity) => remotePlayers.add(entity),
  onRemoteRemove: (id) => remotePlayers.remove(id),
  onMonsterAdd: (entity) => monsters.add(entity),
  onMonsterRemove: (id) => monsters.remove(id),

  onHit: (event) => {
    const iDealt = event.sourceId === connection.sessionId;
    // 보이는 대상이면 화면에 그려진 위치를 쓴다 — 보간 때문에 서버 좌표보다
    // 120ms 뒤처져 있고, 숫자는 눈에 보이는 몸통 위에 떠야 한다.
    const rendered =
      event.targetKind === 'monster'
        ? monsters.positionOf(event.targetId)
        : event.targetId === connection.sessionId
          ? player.position
          : remotePlayers.positionOf(event.targetId);
    // 막타는 대상이 같은 틱에 시야에서 빠져 위치를 찾을 수 없다.
    // 그때는 서버가 알려준 명중 좌표로 띄운다.
    const target = rendered ?? hitPoint.set(event.x, 0, event.z);

    const kind = event.heal
      ? 'gain'
      : event.killed
        ? 'kill'
        : iDealt
          ? 'deal'
          : event.targetKind === 'player'
            ? 'take'
            : 'deal';
    const text = event.heal ? `+${event.amount}` : String(event.amount);
    const crit = event.crit === true;

    // 원거리 공격이면 투사체가 도착할 때 숫자를 띄운다.
    // 쏘자마자 숫자가 뜨면 원거리 직업이 근접처럼 보인다.
    const source =
      event.sourceId === connection.sessionId
        ? player.position
        : remotePlayers.positionOf(event.sourceId);

    // 맞은 자리에 섬광 하나. 숫자만 뜨면 어디서 맞았는지 눈이 못 따라간다.
    const flash = event.heal
      ? 0x8ce87a
      : (event.projectile ? IMPACT_COLOR[event.projectile] : undefined) ?? 0xffe0a8;

    if (event.projectile && source) {
      // 대상이 도중에 사라질 수 있으므로 지금 위치를 복사해 둔다
      const landing = target.clone();
      projectiles.spawn(event.projectile as ProjectileKind, source, target, () => {
        hud.addNumber(landing, text, kind, crit);
        skillFx.impact(landing, flash);
      });
      return;
    }

    hud.addNumber(target, text, kind, crit);
    skillFx.impact(target, flash);
  },

  /**
   * 보스 범위 공격 예고. 원을 띄우는 것 말고는 아무것도 하지 않는다 —
   * 맞았는지 피했는지는 서버가 판정해서 `hit` 으로 따로 알려준다.
   */
  onAoe: (event) => aoeMarkers.add(event.x, event.z, event.radius, event.delayMs),

  onSwing: (id) => {
    if (id === connection.sessionId) player.swing();
    else remotePlayers.swing(id);
  },

  onSkill: (id, skillId) => {
    // 스킬도 같은 스윙 모션을 쓴다. 스킬별 전용 모션은 다음 단계.
    const mine = id === connection.sessionId;
    if (mine) player.swing();
    else remotePlayers.swing(id);

    const skill = SKILLS[skillId];
    if (mine && skill) hud.addNumber(player.position, skill.name, 'gain');

    // --- 이펙트 ---
    // 남이 쓴 것도 보여야 한다. 옆에서 뭘 하는지 안 보이면 같이 노는 느낌이 안 난다.
    const at = mine ? player.position : remotePlayers.positionOf(id);
    if (!skill || !at) return;

    const color = skillColor(skill);
    if (skill.selfHeal) {
      skillFx.heal(at, color);
      return;
    }

    skillFx.cast(at, color);
    // 자기 주위로 터지는 기술은 사거리만큼 고리를 그린다.
    // 날아가는 게 있으면 투사체가 대신 보여주므로 겹쳐 그리지 않는다.
    if (skill.arc >= Math.PI * 2 && !skill.projectile) {
      skillFx.nova(at, skill.range, color);
    }
  },

  onNotice: (text) => chat.addMessage({ kind: 'system', from: '', text }),

  onInventory: (state) => {
    bag.setState(state);
    npcDialog.setInventory(state);
    // 제작·강화 결과는 가방이 다시 오는 것으로 알 수 있다. 열려 있으면 다시 그린다.
    craftWindow.setInventory(state);
  },

  /**
   * 서버가 "이 창을 열어도 된다"고 확인해준 뒤에 온다 (거리 검사 통과).
   *
   * 대장간만 따로 뗀 이유는 하는 일이 셋(제작·강화·등급)이고 목록이 길어서다 —
   * 상점·전직과 같은 창에 쌓으면 200레벨에서 제작 목록만 180줄이 된다.
   */
  onNpc: (info) => {
    if (info.role === 'smith') craftWindow.show(info.forge);
    else npcDialog.show(info.role, info.stock, info.jobs);
  },

  onSkills: (state) => {
    skillBook.setState(state);
    // 액션바는 장착한 스킬만 보여준다
    actionBar.setSkills(state.bar);
    connection.setAutoSkills(actionBar.autoSkills);
  },

  onJobChanged: (job) => {
    // 직업이 바뀌면 외형·스킬·자동 시전 목록이 전부 따라 바뀐다
    player.setClass(job as ClassId);
    skillBook.setCharacter(job as ClassId, myState.level);
    bag.setCharacter(job as ClassId, myState.level);
    npcDialog.setCharacter(job as ClassId, myState.level);
    craftWindow.setCharacter(job as ClassId);
    playerPlate.name = `${characterName} (${CLASSES[job as ClassId].label})`;
  },

  onLoot: (gold, items) => {
    // 자동 획득이라 바닥에서 줍는 연출이 없다. 대신 확실히 알려준다.
    if (gold > 0) hud.addNumber(player.position, `+${gold} G`, 'gain');
    for (const name of items) chat.addMessage({ kind: 'system', from: '', text: `${name} 획득` });
  },

  onReward: (exp, name) => {
    hud.addNumber(player.position, `+${exp} EXP`, 'gain');
    chat.addMessage({ kind: 'system', from: '', text: `${name} 처치 — 경험치 ${exp}` });
  },

  onLevelUp: (level) => {
    hud.addNumber(player.position, `LEVEL ${level}!`, 'gain');
    chat.addMessage({ kind: 'system', from: '', text: `레벨 ${level} 달성!` });
  },

  onRespawn: (x, z) => {
    player.teleport(x, z);
    rig.snapTo(player.position);
    chat.addMessage({ kind: 'system', from: '', text: '마을에서 부활했습니다.' });
  },

  // 물고 있는 대상은 서버가 정한다 — 죽거나 너무 멀어지면 서버가 놓고 알려준다.
  // 여기서 하는 일은 어느 놈인지 이름표를 밝히는 것뿐이다.
  onTarget: (monsterId) => {
    targetId = monsterId;
    monsters.setHighlight(monsterId);
  },
  onChat: (message) => chat.addMessage(message),

  // 서버가 계정을 확정해서 알려준다. 이름이 중복이면 서버가 바꿔서 돌려주므로 반영한다.
  onNeedsCharacter: (suggestedName) => {
    netStatus = '캐릭터 생성 중';
    selectUI.hide();
    createUI.show(suggestedName);
  },

  onCharacterList: ({ max, characters }) => {
    netStatus = '캐릭터 선택 중';
    createUI.hide();
    selectUI.show(characters, max, readCharacterId() ?? null);
  },

  // 고른 캐릭터가 다른 존에 있다. 그 존으로 옮겨서 같은 캐릭터로 다시 들어간다.
  onSwitchZone: (zoneId, characterId) => {
    selectUI.hide();
    travel(zoneId, undefined, characterId);
  },

  onCreateResult: (result) => {
    // 성공하면 곧이어 session 이 오고 거기서 화면을 닫는다
    if (!result.ok) createUI.showError(result.reason ?? '만들 수 없습니다.');
  },

  onSession: (info) => {
    createUI.hide();
    selectUI.hide();
    hud.setVisible(true);
    actionBar.setVisible(true);
    hudButtons.setVisible(true);
    autoHuntToggle.setVisible(true);
    // 저장해둔 설정을 서버에 알려준다 — 안 보내면 서버는 기본값으로 돈다
    connection.setAutoRange(autoHuntToggle.radius);
    connection.setAutoSkills(actionBar.autoSkills);
    skillBook.setCharacter(info.job as ClassId, myState.level);
    activeCharacterId = info.characterId;
    netStatus = '접속됨';
    characterName = info.characterName;
    // 서버가 저장된 위치로 복원했을 수 있다. 보정이 크게 튀기 전에 맞춰준다.
    player.teleport(info.x, info.z);
    rig.snapTo(player.position);
    playerPlate.name = `${characterName} (${CLASSES[player.job].label})`;
    if (info.job !== player.job) player.setClass(info.job as ClassId);
    // 로컬 플레이어는 knight 로 만들어졌다가 여기서 교정된다.
    // 가방의 착용 판정이 이 값을 쓰므로 확정되는 즉시 넘겨야 한다.
    bag.setCharacter(info.job as ClassId, myState.level);
    accountStatus = info.linkedGoogle ? `구글 (${info.linkedGoogle})` : '게스트';
    if (info.isNewAccount) {
      chat.addMessage({
        kind: 'system',
        from: '',
        text: `게스트로 시작합니다. 이름: ${characterName}`,
      });
    } else {
      chat.addMessage({ kind: 'system', from: '', text: `${characterName} (으)로 접속했습니다.` });
    }
  },

  onLinkResult: (result) => {
    if (!result.ok) {
      chat.addMessage({ kind: 'system', from: '', text: `연동 실패: ${result.reason}` });
      return;
    }
    accountStatus = `구글 (${result.email ?? '연동됨'})`;
    chat.addMessage({
      kind: 'system',
      from: '',
      text: result.switched
        ? '기존 구글 계정으로 전환했습니다. 새로고침하면 그 캐릭터로 접속합니다.'
        : '구글 계정을 연동했습니다. 이제 다른 기기에서도 이어서 할 수 있습니다.',
    });
  },
  onError: (message) => {
    netStatus = '오프라인 (' + message + ')';
    console.warn('[net]', message);
  },
});

// --- 카메라 & 입력 ---
const rig = new CameraRig(window.innerWidth / window.innerHeight);
const input = new Input(canvas, rig.camera);
// 클릭으로 문 몬스터. 화면 표시용이고 실제 대상은 서버가 들고 있다
let targetId: string | null = null;
input.setTargets(monsters.group, (object) => monsters.idAt(object));

/** 물고 있던 대상을 놓는다 (다른 곳을 클릭, 키보드 이동, 존 이동, 사망) */
function releaseTarget(): void {
  if (!targetId && !myState.chasing) return;
  targetId = null;
  monsters.setHighlight(null);
  connection.setTarget(null);
}
const transition = new ZoneTransition(overlay);
const chat = new ChatUI(overlay);
const createUI = new CharacterCreateUI(overlay);
const selectUI = new CharacterSelectUI(overlay);

// 직업을 고르면 씬에 서 있는 캐릭터를 바로 갈아입힌다
createUI.onPreview = (job) => player.setClass(job);
// 생성 중에는 이름표를 숨긴다 — 아직 확정되지 않은 이름/직업이라 오해를 부른다
createUI.onVisibility = (open) => overlay.classList.toggle('creating', open);

selectUI.onPreview = (job) => player.setClass(job);
selectUI.onVisibility = (open) => overlay.classList.toggle('creating', open);
selectUI.onEnter = (id) => connection.selectCharacter(id);
selectUI.onDelete = (id) => connection.deleteCharacter(id);
selectUI.onCreateNew = () => {
  selectUI.hide();
  createUI.show('');
};
createUI.onSubmit = ({ name, job }) => connection.createCharacter(name, job);

chat.onSend = (text) => connection.sendChat(text);
// 채팅창을 열 때 눌려 있던 이동키를 털지 않으면 계속 달린다
chat.onFocusChange = (typing) => {
  if (typing) input.clearKeys();
};

input.onRotate = (d) => rig.rotate(d);
input.onZoom = (d) => rig.zoom(d);
input.onSkill = (index) => {
  if (createUI.open || selectUI.open || chat.typing || myState.dead) return;
  actionBar.use(index);
};
actionBar.onUse = (skillId) => connection.useSkill(skillId);
actionBar.onAutoChange = (ids) => connection.setAutoSkills(ids);
skillBook.onLearn = (id) => connection.learnSkill(id);
skillBook.onBar = (ids) => connection.setSkillBar(ids);

// K 로 스킬창 여닫기
window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyK' || chat.typing || createUI.open || selectUI.open) return;
  e.preventDefault();
  skillBook.toggle();
});

/**
 * 자동 사냥.
 *
 * 판단과 이동을 **서버가** 한다. 클라이언트에서 돌리면 사용자가 탭을 옮기는
 * 순간 브라우저가 requestAnimationFrame 을 멈추고 타이머를 1Hz 로 조여서
 * 캐릭터가 그 자리에 선다. 여기서는 켜고 끄는 신호만 보내고,
 * 실제 상태는 서버가 state 로 돌려주는 걸 그대로 따른다.
 */
npcDialog.onBuy = (id) => connection.buyItem(id);
npcDialog.onSell = (index) => connection.sellItem(index);
npcDialog.onJob = (job) => connection.changeJob(job);

// 제작창은 **원래 쓰던 메시지 셋을 그대로** 보낸다. 서버에 새 경로를 뚫지 않았다.
craftWindow.onForge = (id) => connection.forgeItem(id);
craftWindow.onEnhance = (index) => connection.enhanceItem(index);
craftWindow.onGrade = (index) => connection.craft(index);
npcPrompt.onTalk = (role) => connection.openNpc(role);

bag.onEquip = (index) => connection.equip(index);
bag.onCraft = (index) => connection.craft(index);
bag.onUnequip = (slot) => connection.unequip(slot);

// I 로 가방 여닫기
window.addEventListener('keydown', (e) => {
  if (e.code !== 'KeyI' || chat.typing || createUI.open || selectUI.open) return;
  e.preventDefault();
  bag.toggle();
});

/**
 * 차원문에서 사냥터를 골랐다.
 *
 * 'default' 스폰은 맵 한가운데다. 무리는 네 귀퉁이(±20)에 있으니 도착하자마자
 * 둘러싸이지 않는다. 존을 옮기는 길은 포탈로 걸어갈 때와 **같은 `travel`** 이다 —
 * 룸을 나가고 들어가는 순서를 두 벌 만들면 한쪽만 고치는 실수가 난다.
 */
zoneGate.onPick = (zoneId) => travel(zoneId, 'default');

// 차원문에는 여는 단축키가 없다(문을 밟아야 열린다). 닫는 건 Esc 로도 되게 둔다.
window.addEventListener('keydown', (e) => {
  if (e.code !== 'Escape') return;
  if (!zoneGate.open && !craftWindow.open) return;
  e.preventDefault();
  zoneGate.close();
  craftWindow.close();
});

/**
 * 창 여는 버튼.
 *
 * 단축키(I / K / Enter)와 **같은 일**을 한다. 두 벌로 만들면 한쪽만 고치게 된다.
 */
hudButtons.onOpen = (panel: HudPanel) => {
  if (createUI.open || selectUI.open) return;
  if (panel === 'bag') bag.toggle();
  else if (panel === 'skills') skillBook.toggle();
  else chat.openInput();
};

autoHuntToggle.onRange = (radius) => connection.setAutoRange(radius);

autoHuntToggle.onToggle = () => {
  if (createUI.open || selectUI.open || myState.dead) return;
  connection.setAutoHunt(!myState.auto);
};

/**
 * 몬스터를 누르면 그놈을 문다.
 *
 * 여기서 하는 일은 "저놈"이라고 알리는 것뿐이다. 붙는 것도 때리는 것도
 * **서버가** 한다 — 폰에서 화면이 꺼지거나 앱을 옮기면 브라우저가 루프를
 * 멈춰서, 클라이언트가 몰면 그 자리에 선다. 자동 사냥과 같은 이유다.
 */
input.onPickTarget = (monsterId) => {
  if (createUI.open || selectUI.open || chat.typing || myState.dead) return;
  connection.setTarget(monsterId);
};

// 직접 조작하면 자동 사냥과 추격을 모두 끈다 —
// 두 주인이 이동을 두고 싸우면 캐릭터가 떨린다
input.onGroundPoint = (p) => {
  if (myState.auto) connection.setAutoHunt(false);
  releaseTarget();
  player.setMoveTarget(p);
};
input.onAttack = () => {
  if (createUI.open || selectUI.open || chat.typing || myState.dead) return;
  connection.attack();
};

// --- 존 관리 ---
let zone: ZoneScene | null = null;
/**
 * 지금 플레이 중인 캐릭터.
 *
 * **최초 접속에는 넘기지 않는다** — 넘기면 서버가 곧장 입장시켜서
 * 캐릭터 선택 화면을 볼 수 없고, 결국 캐릭터를 바꿀 방법이 사라진다.
 * 포탈로 존을 옮길 때만 넘겨서 같은 캐릭터를 유지한다.
 */
let activeCharacterId: string | undefined;

/**
 * 마지막으로 있던 존을 기억한다.
 *
 * 서버는 캐릭터가 어느 존에 있었는지 알지만, 클라이언트가 접속할 룸을
 * **고르기 전에** 알아야 한다. 그래서 존 id 만 브라우저에 남긴다.
 * 존 안의 위치는 서버가 권위를 갖는다.
 */
const ZONE_KEY = 'mmo:zone';

function rememberZone(zoneId: string): void {
  try {
    localStorage.setItem(ZONE_KEY, zoneId);
  } catch {
    /* 무시 */
  }
}

function lastZone(): string {
  try {
    const saved = localStorage.getItem(ZONE_KEY);
    if (saved && saved in ZONES) return saved;
  } catch {
    /* 무시 */
  }
  return START_ZONE;
}

/**
 * spawnName 을 주지 않으면 서버가 저장된 위치로 복원한다 (재접속).
 * characterId 를 주면 선택 화면을 건너뛰고 그 캐릭터로 바로 들어간다 (존 이동).
 */
/** 이 사냥터에 나오는 짐승 모델 이름들 */
function beastLooks(def: ZoneDef): string[] {
  const out: string[] = [];
  for (const spawn of def.monsters ?? []) {
    try {
      out.push(getMonsterKind(spawn.kind).look);
    } catch {
      // 서버가 새 몬스터를 넣었는데 클라가 구버전인 경우 — 조용히 넘어간다
    }
  }
  return out;
}

async function mountZone(zoneId: string, spawnName?: string, characterId?: string): Promise<void> {
  // 모델을 먼저 받아둔다. 존을 헐고 나서 기다리면 그동안 화면이 비어 버린다.
  await ensureBeasts(beastLooks(getZone(zoneId)));

  if (zone) {
    scene.remove(zone.group);
    zone.dispose();
  }

  const def = getZone(zoneId);
  zone = buildZoneScene(def, assets);
  scene.add(zone.group);

  sun.applyEnv(scene, def.env);
  // 환경맵은 공유하고 세기만 존에 맞춘다 (숲은 어둡다)
  scene.environmentIntensity = def.env.hemiIntensity * 0.85;
  input.setGround(zone.ground);
  // 새 존에 도착하자마자 커서 쪽으로 걸어가지 않도록 누름 상태를 푼다
  input.cancelHold();
  player.setBounds(def.size);

  const [sx, sz] = getSpawn(def, spawnName ?? 'default');
  player.teleport(sx, sz);
  rig.snapTo(player.position);
  sun.follow(player.position);

  // 이름표는 존 소속이므로 통째로 다시 만든다
  nameplates.clear();
  nameplates.add(playerPlate);
  for (const npc of zone.npcs) {
    nameplates.add({
      object: npc.rig.group,
      headHeight: npc.rig.headHeight,
      name: npc.name,
      subtitle: npc.subtitle,
      hp: npc.hp,
      maxHp: 100,
    });
  }

  document.title = def.name + ' — MMORPG';
  rememberZone(def.id);

  // 존마다 룸이 다르다. 이전 룸에서 나가고 새 룸에 들어간다.
  remotePlayers.clear();
  monsters.clear();
  targetId = null;
  projectiles.clear();
  aoeMarkers.clear();
  skillFx.clear();
  hud.clear();
  actionBar.reset();
  bag.setOpen(false);
  skillBook.setOpen(false);
  zoneGate.close();
  craftWindow.close();
  npcDialog.close();
  npcPrompt.clear();
  netStatus = '연결 중';
  void connection
    .join(def.id, spawnName, characterName, player.job, characterId)
    .then(() => {
      if (connection.connected) netStatus = '접속됨';
    });
}

/** 포탈 이동. 지금 플레이 중인 캐릭터를 그대로 데려간다 */
function travel(zoneId: string, spawnName?: string, characterId = activeCharacterId): void {
  const def = getZone(zoneId);
  void transition.run(def.name, () => mountZone(zoneId, spawnName, characterId));
}

await mountZone(lastZone());

const postfx = new PostFX(renderer, scene, rig.camera, window.innerWidth, window.innerHeight);

// 사양이 낮으면 P 로 후처리를 끈다 (GTAO 가 가장 비싸다)
window.addEventListener('keydown', (e) => {
  if (chat.typing || createUI.open || selectUI.open) return;
  if (e.code === 'KeyP') postfx.toggle();
});

window.addEventListener('resize', () => {
  const w = Math.max(1, window.innerWidth);
  const h = Math.max(1, window.innerHeight);
  renderer.setSize(w, h);
  rig.resize(w / h);
  postfx.setSize(w, h);
});

// --- 루프 ---
const timer = new THREE.Timer();
const MAX_DT = 0.05; // 탭 복귀 시 순간이동 방지

/**
 * 프레임이 이만큼 끊기면 화면을 안 보고 있었다고 본다.
 *
 * 넉넉하게 잡는다. 약한 기기에서 한 프레임이 몇백 ms 걸리는 건 정상 범위라
 * 짧게 잡으면 멀쩡히 보고 있는데 전투 숫자가 지워진다. 반대로 탭을 옮기면
 * 간격이 몇 초 단위로 벌어지므로 놓칠 걱정은 없다.
 */
const STALL_MS = 1500;
let lastFrameAt = performance.now();

/**
 * 안 보는 동안 밀린 연출을 버린다.
 *
 * 자동 사냥은 서버에서 계속 도는데 투사체 도착 판정과 피해 숫자는 렌더 루프에
 * 묶여 있다. 그대로 두면 탭으로 돌아오는 순간 수십 개가 한꺼번에 터져서,
 * 정작 지금 벌어지는 전투가 파묻힌다. 전투 결과(경험치·레벨·처치)는
 * 채팅과 상태바에 남으므로 연출만 버리면 잃는 정보가 없다.
 */
function dropStaleVisuals(): void {
  projectiles.clear(); // 도착 콜백을 부르지 않고 버린다
  aoeMarkers.clear(); // 이미 터졌을 예고를 붙잡고 있어봐야 거짓말이다
  skillFx.clear();
  hud.clear();
}

// 탭을 내리는 순간 미리 비운다 (돌아왔을 때 한 프레임이라도 깨끗하도록)
document.addEventListener('visibilitychange', () => {
  if (document.hidden) dropStaleVisuals();
});
const axis = new THREE.Vector2();
let fpsWindowStart = performance.now();
let fpsFrames = 0;

function frame(now: number): void {
  requestAnimationFrame(frame);
  renderer.info.reset();

  // document.hidden 이 false 인데도 합성이 멈추는 경우가 있다(가려진 창, 다른
  // 창에 완전히 덮인 탭). 가시성 이벤트만 믿으면 그때를 놓치므로 간격도 본다.
  const gap = now - lastFrameAt;
  lastFrameAt = now;
  if (gap > STALL_MS) dropStaleVisuals();

  timer.update(now);
  const dt = Math.min(timer.getDelta(), MAX_DT);
  const elapsed = timer.getElapsed();

  // 전환 중에는 입력을 막는다 — 로딩 화면 뒤에서 캐릭터가 걸어다니면 곤란하다
  if (transition.running || createUI.open || selectUI.open) {
    axis.set(0, 0);
  } else {
    input.moveAxis(axis);
    input.update(); // 마우스를 누르고 있으면 커서 쪽으로 계속 이동
    // 키보드로 직접 움직이면 자동 사냥도 추격도 끈다
    if (axis.lengthSq() > 0.0001) {
      if (myState.auto) connection.setAutoHunt(false);
      releaseTarget();
    }
  }

  // 자동 사냥·추격 중에는 서버가 위치를 정한다. 예측을 멈추고 서버 위치를
  // 따라간다 — 양쪽이 동시에 움직이면 보정이 계속 싸워서 캐릭터가 떨린다.
  const driven = myState.auto || myState.chasing;
  player.setDriven(driven);
  if (driven) {
    axis.set(0, 0);
    player.stop();
  }

  const moveInput = player.update(dt, axis, rig.yawAngle);
  // 정지 중에도 보내야 서버가 마지막 순번을 확인해준다 (보정 기준점 갱신)
  connection.sendInput(moveInput);
  remotePlayers.update(dt);
  monsters.update(dt);
  projectiles.update(dt);
  aoeMarkers.update(dt);
  skillFx.update(dt);
  npcPrompt.update(zone?.def.npcs ?? [], player.position);
  rig.update(dt, player.position);
  sun.follow(player.position);

  if (zone) {
    zone.update(dt, elapsed);

    if (!transition.running) {
      for (const portal of zone.portals) {
        if (portal.test(player.position.x, player.position.z)) {
          travel(portal.def.target.zone, portal.def.target.spawn);
          break;
        }
      }
      // 차원문은 밟아도 이동하지 않는다. 어디로 갈지 먼저 고른다.
      // test() 는 반경을 한 번 벗어나야 다시 발동하므로, 닫고 그 자리에
      // 서 있어도 창이 계속 다시 열리지 않는다.
      if (zone.gate?.test(player.position.x, player.position.z)) zoneGate.show();
    }
  }

  postfx.render(scene);
  nameplates.update(rig.camera, window.innerWidth, window.innerHeight);
  hud.update(dt, rig.camera, window.innerWidth, window.innerHeight);
  actionBar.update();
  // 창은 자기 ✕ 로도 닫히므로 버튼이 먼저 알 방법이 없다. 매 프레임 물어본다.
  openPanels.clear();
  if (bag.open) openPanels.add('bag');
  if (skillBook.open) openPanels.add('skills');
  if (chat.inputOpen) openPanels.add('chat');
  hudButtons.update(openPanels);

  // FPS는 시뮬레이션 dt가 아니라 실제 경과 시간으로 재야 한다
  fpsFrames++;
  const windowMs = now - fpsWindowStart;
  if (windowMs >= 500) {
    const info = renderer.info.render;
    statsEl.textContent =
      `FPS   ${Math.round((fpsFrames * 1000) / windowMs)}\n` +
      `draws ${info.calls}\n` +
      `tris  ${(info.triangles / 1000).toFixed(0)}k\n` +
      `zone  ${zone?.def.id ?? '-'}\n` +
      `net   ${netStatus}\n` +
      `동접  ${remotePlayers.count + 1}\n` +
      `후처리 ${postfx.enabled ? 'on' : 'off'} (P)
` +
      `서버  ${connection.serverUrl}
` +
      `계정  ${accountStatus}`;
    fpsWindowStart = now;
    fpsFrames = 0;
  }
}

requestAnimationFrame(frame);
