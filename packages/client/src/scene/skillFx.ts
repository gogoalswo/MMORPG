import * as THREE from 'three';
import type { SkillDef } from '@mmo/shared';

/**
 * 스킬 이펙트.
 *
 * 지금까지 스킬은 **투사체와 피해 숫자만** 있었다. 근접기와 자기 주위로 터지는
 * 기술은 아무것도 안 보여서, 눌렀는데 숫자만 뜨는 것처럼 느껴졌다.
 *
 * 여기서 하는 일은 전부 **보여주기**다. 판정은 이미 서버가 끝냈고 화면은
 * 그 결과를 설명할 뿐이라, 이펙트가 하나 빠져도 게임은 그대로 돌아간다.
 *
 * 조명을 받지 않는 재질(MeshBasicMaterial)을 쓴다. 스스로 빛나는 것처럼
 * 보여야 하고, 어두운 사냥터에서도 같은 밝기로 읽혀야 한다.
 *
 * 메시는 모양별로 풀에 넣고 재사용한다. 난전이 되면 초당 수십 개가 생기는데
 * 그때마다 지오메트리를 만들면 프레임이 튄다 — 투사체와 같은 이유다.
 */

/** 한 번에 살아 있을 수 있는 이펙트 수. 넘으면 가장 오래된 것부터 지운다 */
const MAX_LIVE = 48;

/** 스킬 그림 (까만 바탕이라 가산 혼합으로 바탕이 빠진다) */
const FIST_URL = `${import.meta.env.BASE_URL}assets/fx/fist.png`;
const SKY_FOOT_URL = `${import.meta.env.BASE_URL}assets/fx/sky_foot.png`;
const DUST_URL = `${import.meta.env.BASE_URL}assets/fx/dust.png`;
const TIGER_URL = `${import.meta.env.BASE_URL}assets/fx/tiger_roar.png`;
const WHITE_TIGER_URL = `${import.meta.env.BASE_URL}assets/fx/white_tiger.png`;
const HIT_URL = `${import.meta.env.BASE_URL}assets/fx/hit.png`;

/**
 * 천붕각 — 위에서 큰 발이 떨어지고, 닿는 순간 지면이 갈라진다.
 *
 * **순서가 전부다.** 발과 균열이 같이 뜨면 "떨어져서 갈라졌다" 가 아니라 한 덩어리로
 * 번쩍인 것으로 보인다. 발이 내려오는 동안(`fallTime`) 지면에는 아무것도 없고,
 * 닿는 순간에 균열과 충격 고리가 함께 뜬다.
 */
const SKY = {
  /** 발이 나타나는 높이 (m) — 카메라가 거리 40 · FOV 30 이라 화면 세로가 월드 21유닛이다 */
  from: 10,
  /** 발바닥이 멈추는 높이 (m) */
  to: 0.7,
  /** 떨어지는 데 걸리는 시간 (초). 길면 굼뜨고 짧으면 떨어진 줄 모른다 */
  fallTime: 0.3,
  /**
   * 발 그림의 시작·끝 크기 (m) — 가까워질수록 커진다.
   * 처음이 2m 면 캐릭터(1.8m)만 해서 하늘에 뭐가 떠 있는지 못 알아본다. 끝은 캐릭터 세 배다.
   */
  sizeFrom: 3.2,
  sizeTo: 6.5,
  /** 갈라진 지면이 남아 있는 시간 (초) */
  crackTime: 0.8,
  /** 갈라지는 금의 개수. 가늘어진 만큼 늘렸다 — 여섯은 성글어 보였다 */
  fissures: 8,
  /**
   * 틈이 차례로 벌어지는 간격 (초). **한꺼번에 열리면 무늬 한 장이 켜진 것으로 보인다** —
   * 지진은 땅이 순서대로 찢어지는 것이라, 조금씩 어긋나야 갈라져 나가는 것으로 읽힌다.
   */
  fissureStep: 0.035,
  /** 지진파 고리가 뒤따르는 간격 (초) — 둘이 겹쳐 나가면 여진으로 읽힌다 */
  waveGap: 0.18,
};

/**
 * 발이 닿으며 터지는 먼지 (`dust.png`).
 *
 * **먼지만 보통 혼합으로 그린다**(`blend: 'normal'`). 다른 이펙트는 전부 가산 혼합이라
 * 겹칠수록 밝아지는데, 먼지는 빛나는 게 아니라 **가려야** 하는 것이다 — 가산으로 두면
 * 흙먼지가 아니라 흰 연기가 빛나는 꼴이 된다. 그래서 그림도 알파를 가진 RGBA 다
 * (보통 혼합에서 알파가 없으면 까만 네모로 그려진다).
 */
const DUST = {
  /** 바깥으로 터져 나가는 덩이 수 */
  puffs: 8,
  /** 발밑에서 곧장 피어오르는 덩이 수 — 이게 없으면 가운데가 비어 고리로 보인다 */
  core: 3,
  /** 살아 있는 시간 (초). 먼지는 이펙트 중 제일 늦게까지 남는다 */
  time: 0.7,
  /** 밀려 나가는 속도 (m/s) */
  speed: 3,
  /** 흙색 — 흰 그림에 곱한다. 너무 진하면 그을음처럼 보인다 */
  color: 0xd9cdb6,
};

/**
 * 올려차기 — **앞을 긁어내는 할퀸 자국.** 날카로운 가닥 넷이 엇갈리며 번쩍인다.
 *
 * 두 번 갈아엎은 자리다. 처음엔 노란 검기를 정면으로 날렸는데 칼을 휘두른 것 같았고,
 * 다음엔 차오르는 발 그림을 썼는데 **캐릭터를 덮어버려** 무슨 일이 난 건지 안 보였다.
 * 큰 그림 한 장은 쿼터뷰에서 몸을 가린다 — 가느다란 선 여럿이 훨씬 잘 읽힌다.
 *
 * 그림을 안 쓰고 지오메트리로 그린다. 가닥은 **가운데가 굵고 양 끝이 뾰족한** 길쭉한
 * 마름모라(`makeSlashGeo`) 스치고 지나간 자국으로 보인다.
 */
const CLAW = {
  /** 한 번에 긋는 가닥 수 */
  strokes: 3,
  /**
   * 몇 번 긋는가. **둘이면 서로 반대로 그어져 X 로 엇갈린다** — 한 손으로 긁고
   * 반대 손으로 되긁는 모양이다. 한 번만 그으면 빗금 몇 개로만 보인다.
   */
  sets: 2,
  /** 가닥 사이 시간차 (초) — 차례로 그어져야 "긁었다" 로 보인다 */
  gap: 0.04,
  /** 한 번 긋고 반대로 되긋기까지 (초). 겹치면 두 번인 줄 모른다 */
  setGap: 0.1,
  /** 한 가닥이 떠 있는 시간 (초) */
  duration: 0.24,
  /**
   * 가닥이 기운 각 (rad, 약 40°). **한 번에 긋는 셋은 나란하다** — 각을 제각각 벌렸더니
   * 할퀸 자국이 아니라 **별표**가 됐다. 방향을 바꾸는 건 세트 단위다 (부호를 뒤집는다).
   */
  tilt: 0.7,
  /** 가닥마다 각을 조금씩 흔든다 (rad) — 완전히 평행하면 인쇄물처럼 보인다 */
  tiltJitter: 0.07,
  /** 가닥 사이 간격 (m). 자국에 **수직인** 방향으로 벌린다 */
  spacing: 0.32,
  /** 시작·끝 길이 배율 — 그어지며 조금 뻗는다 */
  sizeFrom: 0.85,
  sizeTo: 1.25,
  /** 자국 하나의 길이 (m) */
  length: 2.6,
  /** 몸에서 얼마나 앞인가 (m). 가까우면 캐릭터를 덮는다 */
  ahead: 1.1,
  /** 가슴 높이 (m) */
  height: 1.25,
  /** 자리를 조금씩 흩는 폭 (m) — 자로 그은 것처럼 보이지 않게 */
  spread: 0.12,
};

/**
 * 호포각 — **호랑이가 몸에서 솟아오르고 주위로 기운이 터진다.**
 *
 * 처음엔 호랑이 얼굴을 정면으로 날렸는데, 그건 "쏜" 것이지 "끌어올린" 것이 아니었다.
 * 지금은 제자리에서 솟는다 — 셋을 겹친다:
 *
 * 1. 호랑이가 캐릭터 위로 **커지면서 올라온다** (같은 그림, 훨씬 크게)
 * 2. 뾰족한 기운이 **바닥에 방사로 터진다** (`slashFlatGeo` — 할퀸 자국을 눕힌 것)
 * 3. 얇은 충격파가 사거리까지 퍼진다
 *
 * 기운은 **사거리만큼** 뻗는다. 이펙트가 사방인데 판정이 정면이면 "닿았는데 안 맞았다" 가
 * 되므로, 스킬 각도 전방위로 바꿨다 ([skills.md](../../docs/features/skills.md)).
 */
const TIGER = {
  /** 호랑이가 솟는 높이 (m) — 가슴에서 머리 위로 */
  from: 1.3,
  to: 2.9,
  /**
   * 호랑이 크기 (m). 캐릭터(1.8m)를 넘어야 "몸에서 나왔다" 로 보인다.
   * 작게 두면 가슴에 붙은 그림처럼 보인다.
   */
  sizeFrom: 2.2,
  sizeTo: 4.8,
  /** 호랑이가 떠 있는 시간 (초). 기운보다 길게 남아 마무리를 한다 */
  duration: 0.75,
  /**
   * 바닥으로 터지는 기운 줄기 수. **열 개로는 성글어서 약해 보였다** — 열여섯이면
   * 사이가 촘촘해 "터졌다" 가 된다.
   */
  spikes: 16,
  /** 기운이 떠 있는 시간 (초). 짧아야 터지는 것으로 읽힌다 */
  spikeTime: 0.3,
  /** 기운이 그려지는 높이 (m) — 지면에 딱 붙이면 묻힌다 */
  spikeHeight: 0.12,
  /**
   * 기운 길이 편차 — 사거리의 이만큼에서 사거리까지. 들쭉날쭉해야 터진 것 같다.
   * 짧은 쪽을 올리면 전체가 커 보인다. 최대는 **사거리**에 묶여 있다 (지금 6m).
   */
  spikeShortest: 0.8,
  /**
   * 기운 색. 스킬 색(`skillColor`)보다 **진하다** — 제 색이 없는 것을 옅게 주면 허옇게 뜬다.
   */
  spikeColor: 0x3fa8ff,
};

/**
 * 백호격 — 백호가 잔상을 남기며 정면으로 내달린다.
 *
 * 잔상은 **같은 그림을 조금 늦게, 작고 흐리게** 띄운 것이다. 속도가 같으니 간격을
 * 유지한 채 따라붙어 한 마리가 빠르게 지나간 자국으로 보인다.
 */
const TIGER_RUN = {
  /** 본체까지 합쳐 몇 장인가 (첫 장이 본체, 나머지가 잔상) */
  trail: 3,
  /** 잔상 사이 시간차 (초) */
  gap: 0.06,
  /** 잔상의 크기·밝기 배율 — 뒤로 갈수록 작고 옅다 */
  trailScale: 0.82,
  trailOpacity: 0.45,
  /** 시작·끝 크기 (m) */
  sizeFrom: 2.4,
  sizeTo: 2.9,
  /** 달리는 속도 (m/s). 호포각(6)보다 빨라야 "달린다" 로 보인다 */
  speed: 9,
  /** 달리는 높이 (m) — 네 발로 달리므로 얼굴(호포각)보다 낮다 */
  height: 1.1,
  /** 몸에서 얼마나 앞에서 나가는가 (m) */
  start: 0.8,
};

/**
 * 맞았을 때 — 몬스터에게 두들겨 맞은 자리에서 터지는 발톱 자국.
 *
 * **몸을 물들이는 것(`flash`)과 같이 쓴다.** 물들이는 쪽은 "누가 맞았는지" 를,
 * 이쪽은 "맞았다" 를 알려 준다. 둘 중 하나만으로는 난전에서 잘 안 읽혔다.
 *
 * 짧고 작다. 몬스터는 1초에 한 번쯤 때리는데 여럿에게 둘러싸이면 그만큼 겹치므로,
 * 스킬 이펙트만 하게 키우면 화면이 붉게 덮인다.
 */
const HURT = {
  /** 몸 어디에 뜨는가 (m) — 가슴께 */
  height: 1.2,
  /** 시작·끝 크기 (m) — 캐릭터(1.8m)보다 작아야 몸이 안 가려진다 */
  sizeFrom: 0.7,
  sizeTo: 1.5,
  /** 떠 있는 시간 (초) */
  duration: 0.3,
  /** 맞은 자리에서 흩어지는 폭 (m) — 같은 자리에 겹쳐 뜨면 한 장처럼 보인다 */
  spread: 0.35,
};

/** 정면 자리 계산용 — 매번 새로 만들지 않는다 */
const front = new THREE.Vector3();

interface Effect {
  /** 고리·섬광은 메시, 그림(주먹·발 연타)은 늘 카메라를 보는 스프라이트 */
  mesh: THREE.Mesh | THREE.Sprite;
  material: THREE.MeshBasicMaterial | THREE.SpriteMaterial;
  /** 0 → 1 */
  t: number;
  duration: number;
  /** 시작·끝 크기 */
  from: number;
  to: number;
  /** 시작·끝 높이 */
  yFrom: number;
  yTo: number;
  opacity: number;
  /** 바닥 고리는 눕혀 두고, 구는 그대로 둔다 */
  spin: number;
  /** 뜨기 전에 기다리는 시간(초) — 연타처럼 차례로 뜨는 것에 쓴다 */
  wait?: number;
  /**
   * 크기·높이 곡선. 기본은 ease-out(처음에 빠르게 퍼지고 끝에서 느려진다).
   * `'in'` 은 반대로 가속한다 — 떨어지는 것은 이래야 "쿵" 하고 닿는 것으로 보인다.
   */
  ease?: 'in';
  /** 끝에서 꺼지기 시작하는 지점(남은 시간 비율). 기본 0.45, 작을수록 늦게까지 밝다 */
  fade?: number;
  /**
   * 수평으로 나아가는 속도 (m/s). 없으면 제자리에서 커지기만 한다.
   * 날아가는 것은 이게 있어야 한다 — 투사체(`projectiles.ts`)는 대상이 정해진 것만 다루므로,
   * 대상 없이 허공으로 뻗는 검기는 여기서 민다.
   */
  vx?: number;
  vz?: number;
  /** 그림을 좌우로 뒤집는다 (옆모습이 진행 방향을 보게) */
  flipX?: boolean;
  /**
   * 깊이 검사를 끄고 몸 위에 그린다. 몸 앞에서 터지는 것은 이게 없으면 몸통에 가린다 —
   * 그림(스프라이트)은 늘 그렇게 그리지만, 메시는 기본이 꺼져 있다.
   */
  onTop?: boolean;
  /**
   * 보통 혼합으로 그린다 (기본은 가산). **먼지처럼 빛나는 게 아니라 가려야 하는 것**에만 쓴다 —
   * 가산으로 두면 흙먼지가 흰 연기처럼 빛난다. 쓰는 그림은 알파를 가지고 있어야 한다.
   */
  blend?: 'normal';
  /** 시전 지점의 지면 높이 — 높이를 매 프레임 누적하지 않고 여기서 다시 잡는다 */
  baseY: number;
}

/** 스킬 하나의 색 — 투사체가 있으면 그것과 맞추고, 없으면 직업으로 정한다 */
export function skillColor(skill: SkillDef): number {
  if (skill.selfHeal) return 0x8ce87a;
  /**
   * 호포각 — 푸른 기운. **그림을 회색조로 만들어 두었기 때문에** 아무 색이나 입는다
   * (`public/assets/fx/tiger_roar.png`). 주황 그림에 파랑을 곱하면 탁한 녹색이 된다.
   */
  if (skill.id === 'tiger_roar') return 0x8fd0ff;
  /**
   * 천붕각 — 노란 금빛. 발 그림(`sky_foot.png`)도 **회색조로 만들어 두었기 때문에**
   * 이 색 하나로 발·금·지진파가 전부 같이 물든다. 가산 혼합이라 겹치면 흰빛으로
   * 뜨므로, 연노랑이 아니라 **진한 금색**이어야 노랑으로 남는다.
   */
  if (skill.id === 'sky_breaker') return 0xffc23c;
  // 백호는 흰빛 그대로 — 물들이면 흰 털이 죽는다
  if (skill.id === 'white_tiger') return 0xffffff;
  if (skill.projectile === 'fireball') return 0xff9a3c;
  if (skill.projectile === 'spark') return 0x9fe6ff;
  if (skill.projectile === 'arrow') return 0xd8e8a0;
  if (skill.job === 'mage') return 0xc39cff;
  if (skill.job === 'archer') return 0xbfe8a0;
  if (skill.job === 'fighter') return 0xcfe8ff; // 주먹에 모인 기 — fist.png 의 푸르스름한 흰빛
  return 0xffd28a; // 기사 — 칼에 실린 빛
}

export class SkillFx {
  readonly group = new THREE.Group();

  /**
   * 카메라가 돌아간 각. 옆모습 그림(백호)을 좌우로 뒤집을지 정하는 데만 쓴다 —
   * 스프라이트는 늘 화면을 보므로, 화면에서 **왼쪽으로** 갈 때 그림도 왼쪽을 봐야 한다.
   * 매 프레임 `main.ts` 가 넣어 준다 (카메라는 사용자가 돌릴 수 있다).
   */
  cameraYaw = 0;

  /** 바닥에 눕는 고리 (시전·전방위·회복) */
  private readonly ringGeo: THREE.RingGeometry;
  /** 명중 섬광 */
  private readonly burstGeo: THREE.IcosahedronGeometry;
  /** 갈라지는 금 한 가닥 (천붕각) — 원점에서 +x 로 누워 있고 곁가지가 하나 난다 */
  private readonly fissureGeo: THREE.BufferGeometry;
  /** 할퀸 자국 한 가닥 — 가운데가 굵고 양 끝이 뾰족한 마름모 (세워서 쓴다) */
  private readonly slashGeo: THREE.BufferGeometry;
  /** 바닥에 방사로 터지는 기운 한 줄기 (호포각) — 안쪽이 굵고 바깥이 뾰족하다 */
  private readonly spikeGeo: THREE.BufferGeometry;
  /**
   * 밖으로 밀려나는 충격파 — `ringGeo` 보다 훨씬 얇다.
   *
   * 기본 고리는 두께가 반지름의 38% 라, 사거리 6 짜리에 쓰면 지름 12m 짜리 흰 도넛이
   * 화면을 덮어 정작 보여주려던 균열이 안 보인다. 밀려나는 것은 테가 얇아야 빠르게
   * 읽힌다.
   */
  private readonly shockGeo: THREE.RingGeometry;

  private readonly live: Effect[] = [];
  private readonly pool: Effect[] = [];
  /** 그림 스프라이트는 재질이 달라 따로 모아 둔다. 그림은 띄울 때 갈아 끼운다 */
  private readonly spritePool: Effect[] = [];
  private readonly textures = new Map<string, THREE.Texture>();

  constructor() {
    this.group.name = 'skillFx';
    // 음영(GTAO) 계산에서 뺀다 — 안 빼면 스프라이트가 까만 판자로 그려진다 (postfx.ts)
    this.group.userData.noAO = true;
    /**
     * 안쪽이 뚫린 고리. 꽉 찬 원은 캐릭터와 지면을 덮어버린다.
     *
     * 두께가 얇으면 **이 게임 카메라에서는 안 보인다.** 카메라가 거리 40 ·
     * FOV 30 이라 화면 세로가 월드 21유닛이다 — 두께 0.22 짜리 테는 1080p
     * 에서 10픽셀 남짓이고, 반투명이라 배경에 묻힌다.
     */
    this.ringGeo = new THREE.RingGeometry(0.62, 1, 48);
    this.ringGeo.rotateX(-Math.PI / 2);
    this.burstGeo = new THREE.IcosahedronGeometry(1, 1);
    this.fissureGeo = makeFissureGeo();
    // 테가 두꺼우면 갈라진 금보다 고리가 먼저 눈에 들어온다. 반지름의 3.5% 면
    // 사거리 6 에서 0.21m — 1080p 에서 열 픽셀쯤이다
    this.shockGeo = new THREE.RingGeometry(0.965, 1, 64);
    this.shockGeo.rotateX(-Math.PI / 2);
    this.slashGeo = makeSlashGeo();
    this.spikeGeo = makeSpikeGeo();
  }

  /** 스킬을 쓰는 순간 발밑에서 솟는 고리 */
  cast(at: THREE.Vector3, color: number): void {
    this.spawn(this.ringGeo, color, {
      duration: 0.45,
      from: 0.5,
      // 카메라가 멀어서(거리 40) 1.15 짜리 고리는 캐릭터에 가려 안 보인다
      to: 2.1,
      yFrom: 0.05,
      yTo: 1.2,
      opacity: 1,
      spin: 0,
    });
    this.place(at);
  }

  /**
   * 자기 주위로 터지는 기술 — 사거리만큼 퍼지는 고리.
   *
   * 실제 판정 범위와 같은 크기로 그린다. 보여주기용이라도 크기가 다르면
   * "분명 닿았는데 안 맞았다"가 된다.
   */
  nova(at: THREE.Vector3, radius: number, color: number): void {
    this.spawn(this.ringGeo, color, {
      duration: 0.5,
      from: 0.15,
      to: radius,
      yFrom: 0.08,
      yTo: 0.35,
      opacity: 1,
      spin: 0,
    });
    this.place(at);
  }

  /** 맞은 자리의 짧은 섬광 */
  impact(at: THREE.Vector3, color: number): void {
    this.spawn(this.burstGeo, color, {
      duration: 0.26,
      from: 0.2,
      to: 1.0,
      yFrom: 0.9,
      yTo: 1.15,
      opacity: 1,
      spin: 6,
    });
    this.place(at);
  }

  /** 회복 — 몸을 감싸고 올라간다 */
  heal(at: THREE.Vector3, color: number): void {
    this.spawn(this.ringGeo, color, {
      duration: 0.7,
      from: 0.9,
      to: 0.45,
      yFrom: 0.05,
      yTo: 2.1,
      opacity: 0.8,
      spin: 0,
    });
    this.place(at);
  }

  /**
   * 격투가 스킬이 맞은 자리 — 빛나는 주먹 (`public/assets/fx/fist.png`).
   *
   * 섬광(`impact`)만으로는 칼로 벤 것과 주먹으로 친 것이 똑같아 보인다.
   * 까만 바탕 그림이라 가산 혼합이면 바탕이 저절로 빠지고, 스프라이트라
   * 쿼터뷰 카메라를 늘 정면으로 본다. 섬광보다 조금 오래·크게 남긴다.
   */
  fist(at: THREE.Vector3, color: number): void {
    this.spawn(FIST_URL, color, {
      duration: 0.4,
      from: 1.1,
      to: 2.2,
      yFrom: 1.0,
      yTo: 1.5,
      opacity: 1,
      spin: 0,
    });
    this.place(at);
  }

  /**
   * 맞았을 때 — 그 자리에서 터지는 발톱 자국 (`HURT`, `public/assets/fx/hit.png`).
   *
   * **캐릭터가 맞은 자리에만 쓴다.** 몬스터가 맞을 때도 띄우면 사냥 내내 화면이
   * 번쩍이고, 그건 예전에 한 번 걷어낸 길이다 ("기본 공격에는 이펙트를 안 그린다").
   * 맞는 쪽이 나(또는 옆 사람)일 때만 나오므로 빈도가 훨씬 낮다.
   *
   * 그림이 이미 붉어서 색을 섞지 않는다 — 물들이면 붉은색이 두 번 먹어 죽는다.
   */
  hurt(at: THREE.Vector3): void {
    this.spawn(HIT_URL, 0xffffff, {
      duration: HURT.duration,
      from: HURT.sizeFrom,
      to: HURT.sizeTo,
      yFrom: HURT.height,
      yTo: HURT.height + 0.15,
      opacity: 1,
      spin: 0,
    });
    this.place(at);
    const fx = this.live[this.live.length - 1]!;
    // 연달아 맞을 때 같은 자리에 포개지지 않게 흩어 놓는다
    fx.mesh.position.x += (Math.random() - 0.5) * HURT.spread;
    fx.mesh.position.z += (Math.random() - 0.5) * HURT.spread;
    (fx.material as THREE.SpriteMaterial).rotation = Math.random() * Math.PI * 2;
  }

  /**
   * 백호격 — 백호가 잔상을 남기며 정면으로 내달린다 (`TIGER_RUN`).
   *
   * 그림이 **옆모습**이라 진행 방향에 따라 뒤집어야 한다. 스프라이트는 늘 화면을 보므로
   * 월드 각을 그대로 쓸 수 없고, **화면에서 어느 쪽으로 가는지**를 봐야 한다:
   * `sin(진행각 − 카메라각)` 이 음수면 화면 왼쪽으로 가는 것이다.
   * 안 뒤집으면 왼쪽으로 갈 때 뒷걸음질 치는 것처럼 보인다.
   */
  whiteTiger(at: THREE.Vector3, facing: number, radius: number, color: number): void {
    const duration = Math.max(0.15, (radius - TIGER_RUN.start) / TIGER_RUN.speed);
    const flipX = Math.sin(facing - this.cameraYaw) < 0;
    for (let i = 0; i < TIGER_RUN.trail; i++) {
      const dim = i === 0 ? 1 : TIGER_RUN.trailScale ** i;
      this.spawn(WHITE_TIGER_URL, color, {
        duration,
        from: TIGER_RUN.sizeFrom * dim,
        to: TIGER_RUN.sizeTo * dim,
        yFrom: TIGER_RUN.height,
        yTo: TIGER_RUN.height,
        opacity: i === 0 ? 1 : TIGER_RUN.trailOpacity,
        spin: 0,
        vx: Math.sin(facing) * TIGER_RUN.speed,
        vz: Math.cos(facing) * TIGER_RUN.speed,
        wait: i * TIGER_RUN.gap,
        fade: 0.2,
        flipX,
      });
      front.set(
        at.x + Math.sin(facing) * TIGER_RUN.start,
        at.y,
        at.z + Math.cos(facing) * TIGER_RUN.start
      );
      this.place(front);
    }
  }

  /**
   * 호포각 — 호랑이가 몸에서 솟고 주위로 기운이 터진다 (`TIGER`,
   * `public/assets/fx/tiger_roar.png`).
   *
   * 그림은 바르코(nano-banana-pro)로 만들었다. 까만 바탕에 불꽃 선으로만 그린 호랑이라
   * 가산 혼합이면 바탕이 저절로 빠지고, 캐릭터 위에 겹쳐도 몸이 비쳐 보인다.
   */
  tigerRoar(at: THREE.Vector3, radius: number, color: number): void {
    // 1. 바닥으로 터지는 기운 줄기들. 이게 "터졌다" 를 만든다
    for (let i = 0; i < TIGER.spikes; i++) {
      // 등간격에 조금씩 흔들어 놓는다. 딱 맞으면 톱니바퀴로 보인다
      const angle =
        (i / TIGER.spikes) * Math.PI * 2 + ((Math.random() - 0.5) * Math.PI) / TIGER.spikes;
      const length = radius * (TIGER.spikeShortest + Math.random() * (1 - TIGER.spikeShortest));

      this.spawn(this.spikeGeo, TIGER.spikeColor, {
        // 짧게, 거의 동시에 터진다. 차례로 뜨면 "긁었다" 가 되어 버린다
        duration: TIGER.spikeTime,
        from: length * 0.25,
        to: length,
        yFrom: TIGER.spikeHeight,
        yTo: TIGER.spikeHeight,
        opacity: 1,
        spin: 0,
        wait: Math.random() * 0.04,
        fade: 0.35,
      });
      /**
       * 줄기는 **원점에서 시작해 +x 로 뻗는다**(`makeSpikeGeo`). 그래서 자리를 밀 필요가
       * 없고, `rotation.y = 각 − π/2` 로 그 축을 방사 방향에 맞추기만 하면 된다.
       */
      this.place(at);
      this.live[this.live.length - 1]!.mesh.rotation.set(0, angle - Math.PI / 2, 0);
    }

    // 2. 호랑이가 몸에서 커지며 올라온다. 기운보다 오래 남아 마무리를 한다
    this.spawn(TIGER_URL, color, {
      duration: TIGER.duration,
      from: TIGER.sizeFrom,
      to: TIGER.sizeTo,
      yFrom: TIGER.from,
      yTo: TIGER.to,
      opacity: 1,
      spin: 0,
      fade: 0.35,
    });
    this.place(at);
  }

  /**
   * 올려차기 — **캐릭터가 보는 앞쪽을** 할퀴는 자국 넷 (`CLAW`).
   *
   * 자국은 **화면을 정면으로 보게 세운다** (`rotation.y = cameraYaw`). 월드 방향으로
   * 세우면 카메라 각에 따라 옆으로 누워 선 하나로 보인다 — 긁은 자국은 넓적한 면이
   * 보여야 읽힌다. 기울기(`rotation.z`)를 가닥마다 달리 줘서 엇갈리게 한다.
   *
   * **자리는 `facing` 을 따른다** — 캐릭터 앞 `ahead` 만큼. 화면이 아니라 캐릭터가
   * 보는 쪽에 나야 "내가 앞을 긁었다" 가 된다.
   */
  clawSlash(at: THREE.Vector3, facing: number, color: number): void {
    /**
     * 화면 가로 방향(월드 기준). 가닥을 **자국에 수직으로** 벌려 나란히 놓는 데 쓴다 —
     * 월드 x/z 로 벌리면 카메라 각에 따라 간격이 찌그러진다. 세로는 그냥 높이(y)다.
     */
    const rightX = Math.cos(this.cameraYaw);
    const rightZ = -Math.sin(this.cameraYaw);

    for (let set = 0; set < CLAW.sets; set++) {
      // 두 번째는 반대로 긋는다 — 그래야 X 로 엇갈린다
      const direction = set % 2 === 0 ? 1 : -1;

      for (let i = 0; i < CLAW.strokes; i++) {
        const tilt = direction * CLAW.tilt + (Math.random() - 0.5) * CLAW.tiltJitter * 2;
        // 가운데를 기준으로 좌우(=자국의 수직 방향)로 벌린다
        const offset = (i - (CLAW.strokes - 1) / 2) * CLAW.spacing;
        const normalX = -Math.sin(tilt);
        const normalY = Math.cos(tilt);

        this.spawn(this.slashGeo, color, {
          duration: CLAW.duration,
          from: CLAW.length * CLAW.sizeFrom,
          to: CLAW.length * CLAW.sizeTo,
          yFrom: CLAW.height,
          yTo: CLAW.height,
          opacity: 1,
          spin: 0,
          wait: set * CLAW.setGap + i * CLAW.gap,
          fade: 0.3,
          // 몸 앞에서 터지므로 몸통에 가리면 안 된다
          onTop: true,
        });
        front.set(
          at.x + Math.sin(facing) * CLAW.ahead,
          at.y,
          at.z + Math.cos(facing) * CLAW.ahead
        );
        this.place(front);

        const fx = this.live[this.live.length - 1]!;
        // 화면을 정면으로 본다. 그 위에서 z 로 기울인다 — 한 세트의 셋은 나란하다
        fx.mesh.rotation.set(0, this.cameraYaw, tilt);
        fx.mesh.position.x +=
          rightX * normalX * offset + (Math.random() - 0.5) * CLAW.spread;
        fx.mesh.position.z +=
          rightZ * normalX * offset + (Math.random() - 0.5) * CLAW.spread;
        fx.baseY += normalY * offset + (Math.random() - 0.5) * CLAW.spread;
      }
    }
  }

  /**
   * 천붕각 — 위에서 발톱이 떨어지고, 닿는 순간 **땅이 지진처럼 뒤집힌다** (`SKY`).
   *
   * 발은 네온 발톱 그림(`sky_foot.png`)이다. 스프라이트라 늘 카메라를 보므로, 위에서
   * 내려오면 밟아 누르는 것으로 읽힌다 — 발 하나를 새로 모델링할 이유가 없었다.
   * **그림에 제 색(파랑·초록·주황 네온)이 있어 흰빛으로 띄운다** — 직업 색을 곱하면
   * 색이 두 번 먹어 죽는다 (호포각 그림을 회색조로 만든 것과 같은 이유의 반대편이다).
   *
   * 바닥은 셋이 겹쳐 지진이 된다.
   * ① **틈이 차례로 벌어지고**(`fissureGeo`, `fissureStep` 만큼 어긋나게) ②
   * **지면 판이 들려 솟고**(`rubbleGeo`) ③ **지진파 고리 둘이 잇따라 밀려난다**
   * (`shockGeo`, `waveGap`). 하나짜리 방사 균열은 "갈라졌다" 까지는 되어도 **흔들리지는
   * 않았다** — 어긋난 시간차가 지진다움의 전부다.
   *
   * 전부 한 번에 띄우고 **바닥 셋은 발이 닿을 때까지 기다린다**(`wait`). 기다리는
   * 동안은 안 보인다 (`update`).
   */
  skyBreaker(at: THREE.Vector3, radius: number, color: number): void {
    // 1. 떨어지는 발톱 — 가속해서 내려오고(`ease: 'in'`), 닿기 직전까지 밝다
    this.spawn(SKY_FOOT_URL, color, {
      duration: SKY.fallTime,
      from: SKY.sizeFrom,
      to: SKY.sizeTo,
      yFrom: SKY.from,
      yTo: SKY.to,
      opacity: 1,
      spin: 0,
      ease: 'in',
      // 떨어지는 내내 밝아야 한다 — 기본 곡선은 절반쯤부터 흐려져 착지가 안 보인다
      fade: 0.12,
    });
    this.place(at);

    // 2. 차례로 벌어지는 틈 — 가장 긴 것이 판정 범위까지 간다 (고리와 같은 규칙)
    for (let i = 0; i < SKY.fissures; i++) {
      this.spawn(this.fissureGeo, color, {
        duration: SKY.crackTime,
        from: radius * 0.35,
        // 길이를 조금씩 달리한다 — 다 같으면 테두리가 맞아 떨어져 고리로 보인다
        to: radius * (i % 2 === 0 ? 1 : 0.78),
        yFrom: 0.06,
        yTo: 0.06,
        opacity: 1,
        spin: 0,
        wait: SKY.fallTime + i * SKY.fissureStep,
      });
      this.place(at);
      const fx = this.live[this.live.length - 1]!;
      // 틈은 +x 로 누워 있다. 등간격이면 눈에 걸리므로 각을 흔든다 (균열 = 별표 문제)
      fx.mesh.rotation.set(
        0,
        (i / SKY.fissures) * Math.PI * 2 + (Math.random() - 0.5) * 0.8,
        0
      );
    }

    // 3. 밟은 자리에서 터지는 먼지 — 바깥으로 밀려나며 부풀었다 사라진다
    for (let i = 0; i < DUST.puffs; i++) {
      // 등간격에서 조금씩 흔든다. 완전한 난수면 한쪽에 몰려 터진 자리가 치우쳐 보인다
      const angle = (i / DUST.puffs) * Math.PI * 2 + (Math.random() - 0.5) * 0.6;
      const speed = DUST.speed * (0.7 + Math.random() * 0.6);
      this.spawn(DUST_URL, DUST.color, {
        duration: DUST.time,
        from: radius * 0.16,
        to: radius * 0.4,
        yFrom: 0.25,
        yTo: 0.9,
        opacity: 0.55,
        spin: 0,
        wait: SKY.fallTime,
        fade: 0.7,
        blend: 'normal',
        vx: Math.cos(angle) * speed,
        vz: Math.sin(angle) * speed,
      });
      this.place(at);
      // 발 크기만큼 떨어진 자리에서 시작한다 — 한 점에서 나가면 공이 부푸는 것으로 보인다
      const fx = this.live[this.live.length - 1]!;
      fx.mesh.position.x += Math.cos(angle) * radius * 0.12;
      fx.mesh.position.z += Math.sin(angle) * radius * 0.12;
    }

    // 3-2. 발밑에서 곧장 피어오르는 기둥. 없으면 가운데가 비어 먼지 고리로 보인다
    for (let i = 0; i < DUST.core; i++) {
      this.spawn(DUST_URL, DUST.color, {
        duration: DUST.time + 0.15,
        from: radius * 0.2,
        to: radius * 0.55,
        yFrom: 0.2,
        yTo: 1.5,
        opacity: 0.45,
        spin: 0,
        wait: SKY.fallTime + i * 0.05,
        fade: 0.7,
        blend: 'normal',
      });
      this.place(at);
      const fx = this.live[this.live.length - 1]!;
      fx.mesh.position.x += (Math.random() - 0.5) * radius * 0.2;
      fx.mesh.position.z += (Math.random() - 0.5) * radius * 0.2;
    }

    // 4. 잇따라 밀려나는 지진파 둘. 여기서 그리므로 부르는 쪽은 `nova` 를 건너뛴다
    for (let i = 0; i < 2; i++) {
      this.spawn(this.shockGeo, color, {
        duration: 0.45,
        from: radius * 0.2,
        // 뒤따르는 것은 더 작게 — 판정 범위를 넘겨 그리면 "닿았는데 안 맞았다" 가 된다
        to: radius * (i === 0 ? 1 : 0.7),
        yFrom: 0.1,
        yTo: 0.5,
        // 갈라진 금이 먼저 읽혀야 한다 — 고리는 사거리를 알려 주는 데까지만 밝다
        opacity: i === 0 ? 0.5 : 0.32,
        spin: 0,
        wait: SKY.fallTime + i * SKY.waveGap,
      });
      this.place(at);
    }
  }

  /**
   * 시전하는 순간 그리는 그림 — **몬스터가 없어도 시전자 자리에서 나온다.**
   *
   * 맞힌 자리에만 그리면 허공에 쳤을 때 아무것도 안 보여서 "스킬이 안 나간다" 로
   * 읽혔다. 여기서 그린 스킬은 명중(`signature`) 때 다시 그리지 않는다 — 맞으면
   * 두 번 겹쳐 나온다. `facing` 은 모델 정면(+Z) 기준 각 (`rotY = atan2(dx, dz)`).
   *
   * **반환값은 "이 스킬은 여기서 다 그렸다"** 는 뜻이다. 부르는 쪽(main.ts)은 true 면
   * 전방위 고리(`nova`)를 따로 그리지 않는다 — 천붕각은 그 고리를 발이 닿는 순간에
   * 맞춰 스스로 그린다. 밖에서 먼저 그리면 발보다 고리가 앞서 퍼져 앞뒤가 뒤집힌다.
   */
  castSignature(at: THREE.Vector3, facing: number, skill: SkillDef): boolean {
    if (skill.id === 'sky_breaker') {
      // 자기 자리에 내리찍는다 — 전방위기라 앞으로 밀 이유가 없다
      this.skyBreaker(at, skill.range, skillColor(skill));
      return true;
    }
    if (skill.id === 'white_tiger') {
      this.whiteTiger(at, facing, skill.range, skillColor(skill));
      return true;
    }
    if (skill.id === 'tiger_roar') {
      // 제자리에서 솟는다 — 전방위기라 앞으로 밀 이유가 없다
      this.tigerRoar(at, skill.range, skillColor(skill));
      return true;
    }
    if (skill.id === 'rising_kick') {
      // 정면기라 고리(`nova`)는 원래 안 그린다
      this.clawSlash(at, facing, skillColor(skill));
      return true;
    }
    return false;
  }

  /** 스킬이 맞은 자리에 붙는 그림 — 없는 스킬은 아무것도 안 한다 (섬광 `impact` 는 따로 부른다) */
  signature(at: THREE.Vector3, skill: SkillDef): void {
    // 시전할 때 이미 그린 것들 — 여기서 또 그리면 두 번 겹친다 (castSignature)
    if (
      skill.id === 'sky_breaker' ||
      skill.id === 'rising_kick' ||
      skill.id === 'tiger_roar' ||
      skill.id === 'white_tiger'
    ) {
      return;
    }
    /**
     * **지금은 여기까지 오는 격투가 스킬이 없다** — 넷 다 위에서 걸러진다.
     * 그래도 규칙은 남겨 둔다. 시전 그림이 없는 스킬을 새로 만들면 이게 기본값이 된다
     * (섬광만으로는 칼로 벤 것과 주먹으로 친 것이 똑같아 보인다).
     */
    if (skill.job === 'fighter') this.fist(at, skillColor(skill));
  }

  /** geo 가 문자열이면 그 주소의 그림을 쓰는 스프라이트 */
  private spawn(
    geo: THREE.BufferGeometry | string,
    color: number,
    spec: Omit<Effect, 'mesh' | 'material' | 't' | 'baseY'>
  ): void {
    // 너무 많으면 가장 오래된 것부터 거둔다. 안 그러면 난전에서 화면이 하얘진다.
    while (this.live.length >= MAX_LIVE) this.retire(0);

    let fx = (typeof geo === 'string' ? this.spritePool : this.pool).pop();
    if (!fx) {
      const look = {
        transparent: true,
        depthWrite: false,
        // 겹칠수록 밝아진다 — 여러 개가 한 자리에서 터질 때 자연스럽다
        blending: THREE.AdditiveBlending,
      };
      if (typeof geo === 'string') {
        // 그림은 맞은 몸 한가운데(높이 1m 안팎)에서 터진다. 깊이 검사를 켜 두면 몸통 앞쪽이
        // 그림을 가린다 — 초원 오우거는 키가 2.2m 가 넘어 절반 넘게 먹혔다. 몸 위에 그린다.
        const material = new THREE.SpriteMaterial({ ...look, map: this.texture(geo), depthTest: false });
        fx = { mesh: new THREE.Sprite(material), material, t: 0, baseY: 0, ...spec };
        fx.mesh.renderOrder = 10;
      } else {
        const material = new THREE.MeshBasicMaterial({ ...look, side: THREE.DoubleSide });
        fx = { mesh: new THREE.Mesh(geo, material), material, t: 0, baseY: 0, ...spec };
      }
      fx.mesh.frustumCulled = false;
    }

    if (typeof geo === 'string') {
      const material = fx.material as THREE.SpriteMaterial;
      material.map = this.texture(geo);
      material.rotation = 0;
    } else {
      fx.mesh.geometry = geo;
      // 풀에서 꺼낸 것이라 매번 정해 준다 — 안 그러면 앞에 쓰던 설정이 남는다
      const onTop = spec.onTop === true;
      fx.material.depthTest = !onTop;
      fx.mesh.renderOrder = onTop ? 10 : 0;
    }
    fx.material.color.setHex(color);
    fx.material.opacity = spec.opacity;
    fx.t = 0;
    Object.assign(fx, spec);
    // 풀에서 꺼낸 것이라 안 준 값은 앞에 쓰던 게 남는다. 빠뜨리면 엉뚱하게 기다리거나 가속한다
    fx.wait = spec.wait ?? 0;
    fx.ease = spec.ease;
    fx.fade = spec.fade;
    fx.vx = spec.vx;
    fx.vz = spec.vz;
    fx.flipX = spec.flipX;
    fx.onTop = spec.onTop;
    fx.blend = spec.blend;
    // 풀에서 꺼낸 재질은 앞에 쓰던 혼합이 남아 있다 — 바뀔 때만 갈아 준다 (셰이더를 다시 짠다)
    const blending = spec.blend === 'normal' ? THREE.NormalBlending : THREE.AdditiveBlending;
    if (fx.material.blending !== blending) {
      fx.material.blending = blending;
      fx.material.needsUpdate = true;
    }
    // 기다리는 동안은 안 보인다 (연타의 뒤쪽 발)
    fx.mesh.visible = fx.wait <= 0;
    // 무늬가 매번 같은 각으로 서면 눈에 걸린다. 방향이 중요한 것(검기·할퀸 자국)은
    // 띄운 쪽에서 다시 정한다
    fx.mesh.rotation.set(0, Math.random() * Math.PI * 2, 0);

    this.group.add(fx.mesh);
    this.live.push(fx);
  }

  /** 방금 만든 것의 자리를 잡는다 */
  private place(at: THREE.Vector3): void {
    const fx = this.live[this.live.length - 1];
    if (!fx) return;
    fx.baseY = at.y;
    fx.mesh.position.set(at.x, at.y + fx.yFrom, at.z);
    fx.mesh.scale.set(fx.flipX ? -fx.from : fx.from, fx.from, fx.from);
  }

  /** 그림은 처음 쓸 때 받는다 — 그 스킬을 안 쓰는 존에서는 받을 이유가 없다 */
  private texture(url: string): THREE.Texture {
    let tex = this.textures.get(url);
    if (!tex) {
      tex = new THREE.TextureLoader().load(url);
      tex.colorSpace = THREE.SRGBColorSpace;
      this.textures.set(url, tex);
    }
    return tex;
  }

  private retire(index: number): void {
    const fx = this.live[index];
    if (!fx) return;
    this.live.splice(index, 1);
    this.group.remove(fx.mesh);
    fx.mesh.visible = false;
    (fx.mesh instanceof THREE.Sprite ? this.spritePool : this.pool).push(fx);
  }

  update(dt: number): void {
    for (let i = this.live.length - 1; i >= 0; i--) {
      const fx = this.live[i]!;
      // 차례를 기다리는 중 — 시간도 위치도 흐르지 않는다
      if (fx.wait && fx.wait > 0) {
        fx.wait -= dt;
        if (fx.wait > 0) continue;
        fx.mesh.visible = true;
      }
      fx.t += dt / fx.duration;
      if (fx.t >= 1) {
        this.retire(i);
        continue;
      }

      // 처음엔 빠르게 퍼지고 끝에서 느려진다 (ease-out). 떨어지는 것만 반대로 가속한다
      const e = fx.ease === 'in' ? fx.t * fx.t : 1 - (1 - fx.t) * (1 - fx.t);
      const size = fx.from + (fx.to - fx.from) * e;
      // 뒤집기는 x 만 음수로 준다. 스프라이트는 늘 화면을 보므로 이게 좌우 반전이 된다
      fx.mesh.scale.set(fx.flipX ? -size : size, size, size);
      // 높이는 매 프레임 더하지 않고 시작점에서 다시 잡는다 — 곡선을 바꿔도 어긋나지 않는다
      fx.mesh.position.y = fx.baseY + fx.yFrom + (fx.yTo - fx.yFrom) * e;
      if (fx.spin) fx.mesh.rotation.y += fx.spin * dt;
      // 날아가는 것 — 기다리는 동안은 위에서 걸러지므로 제자리에 떠 있다
      if (fx.vx) fx.mesh.position.x += fx.vx * dt;
      if (fx.vz) fx.mesh.position.z += fx.vz * dt;
      /**
       * 밝기 곡선 ★
       *
       * 예전에는 `opacity * (1-t)²` 였다. 그런데 크기는 `t` 를 따라 **커지므로**,
       * 가장 커지는 순간이 가장 투명한 순간과 겹쳤다. 카메라가 멀어서(거리 40)
       * 작을 때는 몇 픽셀뿐이라, 결국 어느 프레임에도 눈에 걸리는 그림이 없었다 —
       * 실제로 재보니 최대 밝기가 765 중 15~22 였다. "이펙트가 안 나온다" 가
       * 이것이다.
       *
       * 그래서 **빠르게 켜고, 커져 있는 동안 유지하다가, 끝에서 끈다.**
       */
      const rise = Math.min(1, fx.t / 0.12);
      const fall = Math.min(1, (1 - fx.t) / (fx.fade ?? 0.45));
      fx.material.opacity = fx.opacity * rise * fall;
    }
  }

  /** 존을 옮기거나 오래 안 그렸을 때 — 남은 걸 붙잡고 있어봐야 거짓말이다 */
  clear(): void {
    for (let i = this.live.length - 1; i >= 0; i--) this.retire(i);
  }

  dispose(): void {
    this.clear();
    for (const fx of [...this.pool, ...this.spritePool]) fx.material.dispose();
    this.pool.length = 0;
    this.spritePool.length = 0;
    for (const tex of this.textures.values()) tex.dispose();
    this.textures.clear();
    this.ringGeo.dispose();
    this.burstGeo.dispose();
    this.fissureGeo.dispose();
    this.shockGeo.dispose();
    this.slashGeo.dispose();
    this.spikeGeo.dispose();
  }
}

/**
 * 갈라지는 금 한 가닥 — **원점에서 +x 로 뻗으며 꺾이고, 곁가지가 한 번 난다.**
 *
 * 두 번 갈아엎은 자리다. ① 방사 균열 일곱 갈래를 **한 덩어리**로 만들어 한 번에 띄웠더니
 * (`makeCrackGeo`) 갈라진 것으로는 보여도 **흔들리지는 않았다** — 전부 같은 순간에 같은
 * 속도로 퍼져서 바닥에 무늬 한 장이 켜진 것과 다르지 않았다. ② 그래서 가닥을 따로 띄우고
 * 시간차를 줬는데, 이번엔 **틈을 벌린 것이 너무 두꺼웠다** (반폭 0.07 = 사거리 6 에서
 * 0.42m). 지진으로 갈라진 땅은 **가는 금**이지 벌어진 도랑이 아니다 (2026-09-16 지적).
 *
 * 지금은 반폭 0.012 — 사거리 6 에서 폭 0.14m, 1080p 에서 일곱 픽셀쯤이다. 가는 대신
 * **꺾임과 곁가지로** 금답게 만든다. 곧게 뻗기만 하면 갈라진 땅이 아니라 별표가 된다.
 *
 * 길이 1 기준이라 실제 길이는 `scale` 로 준다 (`spikeGeo` 와 같은 규칙). 방향은 띄우는
 * 쪽에서 `rotation.y` 로 준다.
 */
function makeFissureGeo(): THREE.BufferGeometry {
  /** 난수를 고정한다 — 모양이 매번 달라지면 "이번엔 왜 이래?" 를 확인할 수가 없다 */
  let seed = 11;
  const rand = () => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff;
  };

  /**
   * 뿌리 쪽 반폭 (길이 대비). **이 값이 두께의 전부다.**
   * 0.07 은 도랑이었고, 0.035(예전 균열)도 이 카메라에서는 굵은 편이었다.
   */
  const half = 0.012;
  /**
   * 발자국 바깥에서 시작한다. 중심에서 바로 뻗으면 금이 한 덩어리로 뭉쳐
   * 가운데가 꽉 찬 별이 된다.
   */
  const start = 0.12;

  const points: number[] = [];

  /** 금 한 가닥. 마디마다 꺾이고 가늘어지며, 두 번째 마디에서 곁가지가 하나 갈라진다 */
  const crack = (x: number, z: number, angle: number, w: number, length: number, depth: number) => {
    const segments = 5;
    const step = length / segments;
    for (let s = 0; s < segments; s++) {
      const nx = x + Math.cos(angle) * step;
      const nz = z + Math.sin(angle) * step;
      const next = w * (1 - (s + 1) / segments); // 끝은 뾰족하게 — 갈라짐이 사그라든다
      const px = -Math.sin(angle);
      const pz = Math.cos(angle);
      // 사다리꼴 하나 = 삼각형 둘. 재질이 양면이라 감는 방향은 상관없다
      points.push(x + px * w, 0, z + pz * w, x - px * w, 0, z - pz * w, nx - px * next, 0, nz - pz * next);
      points.push(x + px * w, 0, z + pz * w, nx - px * next, 0, nz - pz * next, nx + px * next, 0, nz + pz * next);
      // 곁가지 — **금다움의 전부다.** 한 번만 더 갈라진다 (더 두면 지면이 그물로 뭉개진다)
      if (depth > 0 && s === 1) {
        const side = rand() < 0.5 ? -1 : 1;
        crack(nx, nz, angle + side * (0.6 + rand() * 0.5), next * 0.75, length * 0.45, depth - 1);
      }
      x = nx;
      z = nz;
      w = next;
      angle += (rand() - 0.5) * 0.9; // 다음 마디는 꽤 꺾인다
    }
  };

  crack(start, 0, 0, half, 1 - start, 1);

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(points, 3));
  return geo;
}

/**
 * 할퀸 자국 한 가닥 — **가운데가 굵고 양 끝이 뾰족한** 길쭉한 마름모.
 *
 * 폭이 일정한 막대로 두면 끝이 뭉툭해서 "선을 그었다" 가 아니라 "막대를 놓았다" 로
 * 보인다. 스치고 지나간 자국은 가운데가 가장 깊고 양 끝에서 사라진다.
 *
 * 길이 1(=±0.5) 기준이라 실제 길이는 `scale` 로 준다. XY 평면에 누워 있으므로
 * 띄우는 쪽에서 `rotation.y` 로 화면을 보게 하고 `rotation.z` 로 기울인다.
 */
function makeSlashGeo(): THREE.BufferGeometry {
  const segments = 28;
  /**
   * 가장 굵은 곳의 반폭 (길이 대비). **가늘어야 한다.**
   * 0.045 로 뒀더니 길이의 1/11 이라 넓적한 마름모가 됐고, 넷이 겹쳐 별표로 보였다.
   * 그렇다고 1/40 까지 줄이면 이 카메라(거리 40)에서 **3픽셀**이라 배경에 묻힌다 —
   * 고리 두께로 한 번 겪은 일이다. 1/25 쯤이 가늘면서 보이는 선이다 (폭 약 5픽셀).
   */
  const half = 0.02;
  /** 중심선이 휘는 정도 (길이 대비). 곧은 자는 긁은 자국이 아니라 빗금이다 */
  const bend = 0.08;

  const points: number[] = [];
  for (let i = 0; i < segments; i++) {
    const t0 = i / segments;
    const t1 = (i + 1) / segments;
    const x0 = t0 - 0.5;
    const x1 = t1 - 0.5;
    // 양 끝에서 0 이 되는 곡선 — 가운데가 가장 굵고 끝은 뾰족하다
    const w0 = half * Math.sin(Math.PI * t0);
    const w1 = half * Math.sin(Math.PI * t1);
    // 중심선도 같은 모양으로 휘어 활처럼 굽는다
    const c0 = bend * Math.sin(Math.PI * t0);
    const c1 = bend * Math.sin(Math.PI * t1);
    points.push(x0, c0 + w0, 0, x1, c1 + w1, 0, x1, c1 - w1, 0);
    points.push(x0, c0 + w0, 0, x1, c1 - w1, 0, x0, c0 - w0, 0);
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(points, 3));
  return geo;
}

/**
 * 기운 한 줄기 — **안쪽이 굵고 바깥으로 갈수록 뾰족해지는 쐐기.**
 *
 * 할퀸 자국(`makeSlashGeo`)을 눕혀 써 봤는데, 그건 가운데가 굵고 양 끝이 뾰족한 데다
 * 폭이 길이의 1/25 이라 **터지는 기운이 아니라 허연 실선**으로 보였다. 터져 나오는 것은
 * 뿌리가 굵고 끝이 사라진다.
 *
 * 길이 1(원점 → +x)이라 자리를 밀 필요 없이 중심에 놓고 `rotation.y` 로 방향만 준다.
 * XZ 평면에 누워 나온다.
 */
function makeSpikeGeo(): THREE.BufferGeometry {
  const segments = 20;
  /**
   * 뿌리의 반폭 (길이 대비). 길이 4m 면 뿌리가 0.9m — 멀리서도 덩어리로 읽힌다.
   * 0.075 로 시작했다가 "더 크게" 라는 요청에 1.5배로 올렸다. **길이는 사거리에 묶여
   * 있어서** 굵기로 키운다 — 사거리보다 길게 뻗으면 "닿았는데 안 맞았다" 가 된다.
   */
  const half = 0.1125;

  const points: number[] = [];
  for (let i = 0; i < segments; i++) {
    const t0 = i / segments;
    const t1 = (i + 1) / segments;
    // 뿌리에서 굵고 끝에서 0. 제곱을 주면 끝이 길게 빠져 더 날카롭다
    const w0 = half * (1 - t0) ** 1.6;
    const w1 = half * (1 - t1) ** 1.6;
    points.push(t0, 0, w0, t1, 0, w1, t1, 0, -w1);
    points.push(t0, 0, w0, t1, 0, -w1, t0, 0, -w0);
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(points, 3));
  return geo;
}
