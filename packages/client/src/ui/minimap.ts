import { zoneHalfSize, type ZoneDef } from '@mmo/shared';

/**
 * 미니맵.
 *
 * 존이 92×92 로 작아서 **한 장에 존 전체가 들어간다.** 주변만 확대해 보여주는 쪽이
 * 흔하지만, 이 게임에서 알고 싶은 건 "이 사냥터 어디쯤에 있고 몬스터가 어느 쪽에
 * 몰려 있나" 라서 전체를 보여주는 편이 쓸모 있다.
 *
 * **카메라가 돌면 같이 돈다.** 고정해 두면 화면에서 오른쪽에 있는 몬스터가 미니맵에서는
 * 오른쪽 위에 찍혀 매번 머릿속에서 돌려야 한다. 돌리면 존 경계(사각형)가 기울어 보이는데,
 * 둥근 테두리 안이라 그게 오히려 방향을 알려 준다.
 *
 * 3D 가 아니라 2D 캔버스다. 점 수십 개를 그리는 데 드로우콜을 쓸 이유가 없고,
 * DOM 오버레이와 같은 레이어에 있어야 창들과 겹침 순서를 맞추기 쉽다.
 */

/** 미니맵에 찍을 자리. 쓰는 쪽(`remoteMonsters` 등)이 이 모양으로 넘긴다 */
export interface MapPoint {
  x: number;
  z: number;
}

/** 한 변 (CSS 픽셀). 폰에서는 CSS 가 줄인다 */
const SIZE = 148;

/** 점 반지름 (픽셀). 카메라 거리와 무관하게 **화면 크기**로 고정한다 */
const DOT = {
  me: 4.2,
  player: 3,
  monster: 2.6,
  npc: 2.6,
  gate: 3.6,
};

const COLOR = {
  ground: 'rgba(14, 18, 24, 0.66)',
  border: 'rgba(150, 180, 210, 0.45)',
  /** 존 경계 — 여기까지만 걸어갈 수 있다 */
  edge: 'rgba(150, 180, 210, 0.5)',
  me: '#ffffff',
  /** 이름표와 같은 색을 쓴다 — 다른 곳에서 배운 색을 다시 배우게 하지 않는다 */
  player: '#bfe8a0',
  monster: '#ff6b5a',
  npc: '#ffdf3d',
  gate: '#8fd0ff',
};

export interface MinimapView {
  /** 내 자리 */
  me: MapPoint;
  /** 내가 보는 각 (모델 정면 +Z 기준, `rotY = atan2(dx, dz)`) */
  facing: number;
  /** 카메라가 돌아간 각. 맵을 이만큼 돌려 화면과 방향을 맞춘다 */
  cameraYaw: number;
  zone: ZoneDef | null;
  players: readonly MapPoint[];
  monsters: readonly MapPoint[];
}

export class Minimap {
  readonly root = document.createElement('div');

  private readonly canvas = document.createElement('canvas');
  private readonly ctx: CanvasRenderingContext2D;
  private readonly label = document.createElement('div');
  private labelText = '';
  private dpr = 0;

  constructor(parent: HTMLElement) {
    this.root.className = 'minimap';
    this.canvas.className = 'minimap-canvas';
    this.label.className = 'minimap-name';
    this.root.append(this.canvas, this.label);
    parent.append(this.root);

    const ctx = this.canvas.getContext('2d');
    if (!ctx) throw new Error('2d 컨텍스트를 못 얻었다');
    this.ctx = ctx;
  }

  /** 매 프레임 부른다. 그리는 값이 전부 밖에서 오므로 상태를 들고 있지 않는다 */
  update(view: MinimapView): void {
    this.resize();

    const { ctx } = this;
    const half = SIZE / 2;
    ctx.clearRect(0, 0, SIZE, SIZE);

    // 둥근 바탕. 잘라내기(clip)를 걸어 두면 존 모서리가 테두리 밖으로 안 삐져나온다
    ctx.save();
    ctx.beginPath();
    ctx.arc(half, half, half - 1, 0, Math.PI * 2);
    ctx.fillStyle = COLOR.ground;
    ctx.fill();
    ctx.clip();

    const zone = view.zone;
    if (zone) {
      /**
       * 존 한 변(±42)이 미니맵 한 변에 들어가게 맞춘다. 모서리는 둥근 테두리에
       * 잘리지만, 걸어갈 수 있는 끝(`zoneHalfSize`)은 경계선으로 보여 준다.
       */
      const limit = zoneHalfSize(zone.size);
      const scale = (SIZE - 10) / (limit * 2);
      const cos = Math.cos(view.cameraYaw);
      const sin = Math.sin(view.cameraYaw);
      /**
       * 월드 → 미니맵. 카메라 각만큼 돌린 뒤 화면 픽셀로 옮긴다.
       * 캔버스 변환(`ctx.rotate`)을 안 쓰는 이유: 배율까지 같이 먹어서 **점 크기와 선
       * 두께가 존 크기를 따라 변한다.** 자리만 옮기고 크기는 픽셀로 두는 게 맞다.
       */
      const at = (p: MapPoint): [number, number] => [
        half + (p.x * cos - p.z * sin) * scale,
        half + (p.x * sin + p.z * cos) * scale,
      ];

      // 걸어갈 수 있는 경계
      ctx.beginPath();
      const corners: MapPoint[] = [
        { x: -limit, z: -limit },
        { x: limit, z: -limit },
        { x: limit, z: limit },
        { x: -limit, z: limit },
      ];
      corners.forEach((corner, i) => {
        const [x, y] = at(corner);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.closePath();
      ctx.strokeStyle = COLOR.edge;
      ctx.lineWidth = 1;
      ctx.stroke();

      // 붙박이 — 차원문과 NPC 는 존 정의에 있다 (서버가 보내주지 않는다)
      this.dot(at(pointOf(zone.gate.position)), DOT.gate, COLOR.gate);
      for (const npc of zone.npcs ?? []) this.dot(at(npc), DOT.npc, COLOR.npc);

      // 살아 있는 것 — 몬스터를 먼저 찍어 사람이 위에 오게 한다
      for (const monster of view.monsters) this.dot(at(monster), DOT.monster, COLOR.monster);
      for (const player of view.players) this.dot(at(player), DOT.player, COLOR.player);

      this.me(at(view.me), view.facing + view.cameraYaw);
    }

    ctx.restore();

    // 테두리는 잘라내기 밖에서 — 안에서 그리면 선의 바깥 절반이 깎인다
    ctx.beginPath();
    ctx.arc(half, half, half - 1, 0, Math.PI * 2);
    ctx.strokeStyle = COLOR.border;
    ctx.lineWidth = 1.5;
    ctx.stroke();

    // 이름은 거의 안 바뀐다 — 매 프레임 DOM 을 건드리지 않는다 (이름표와 같은 이유)
    const name = view.zone?.name ?? '';
    if (name !== this.labelText) {
      this.labelText = name;
      this.label.textContent = name;
    }
  }

  private dot(at: [number, number], radius: number, color: string): void {
    const { ctx } = this;
    ctx.beginPath();
    ctx.arc(at[0], at[1], radius, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
  }

  /** 나 — 보는 쪽이 뾰족한 삼각형. 점으로 두면 어디를 향하는지 모른다 */
  private me(at: [number, number], angle: number): void {
    const { ctx } = this;
    const [x, y] = at;
    // 월드 +Z 가 미니맵 아래쪽이므로, 각을 그대로 쓰면 뾰족한 쪽이 정면을 향한다
    const dirX = Math.sin(angle);
    const dirY = Math.cos(angle);
    const tip = DOT.me * 1.9;
    const side = DOT.me * 0.95;

    ctx.beginPath();
    ctx.moveTo(x + dirX * tip, y + dirY * tip);
    ctx.lineTo(x - dirX * side + dirY * side, y - dirY * side - dirX * side);
    ctx.lineTo(x - dirX * side - dirY * side, y - dirY * side + dirX * side);
    ctx.closePath();
    ctx.fillStyle = COLOR.me;
    ctx.fill();
    // 몬스터 점 위에 서 있어도 구분되게 테를 두른다
    ctx.strokeStyle = 'rgba(0, 0, 0, 0.65)';
    ctx.lineWidth = 1;
    ctx.stroke();
  }

  /** 화면 밀도가 바뀔 때만 캔버스를 다시 잡는다 (창을 다른 모니터로 옮기면 바뀐다) */
  private resize(): void {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (dpr === this.dpr) return;
    this.dpr = dpr;
    this.canvas.width = SIZE * dpr;
    this.canvas.height = SIZE * dpr;
    this.canvas.style.width = `${SIZE}px`;
    this.canvas.style.height = `${SIZE}px`;
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
}

function pointOf(position: readonly [number, number]): MapPoint {
  return { x: position[0], z: position[1] };
}
