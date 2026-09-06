import { AOI_CELL_SIZE } from './constants.ts';

/**
 * 균일 셀 공간 분할.
 *
 * 네트워크 관심영역(AoI)뿐 아니라 전투 판정·AI 어그로·포탈 근접처럼
 * 매 틱 도는 공간 질의가 전부 이걸 쓴다. 그래서 클라·서버 공유 코드다.
 * (클라는 예측용 로컬 질의, 서버는 권위 판정)
 */

export type CellKey = number;

/** 셀 좌표를 하나의 정수로 인코딩. Map 키로 문자열을 쓰면 GC 압박이 커진다. */
export function encodeCell(cx: number, cz: number): CellKey {
  // -32768..32767 범위. 셀 32m 기준 월드 ±1,048,576m — 충분하다.
  return ((cx + 32768) << 16) | (cz + 32768);
}

export function decodeCell(key: CellKey): { cx: number; cz: number } {
  return { cx: (key >>> 16) - 32768, cz: (key & 0xffff) - 32768 };
}

interface Entry<T> {
  id: string;
  x: number;
  z: number;
  cell: CellKey;
  item: T;
}

export class SpatialGrid<T> {
  private readonly cells = new Map<CellKey, Set<Entry<T>>>();
  private readonly entries = new Map<string, Entry<T>>();

  private readonly cellSize: number;

  constructor(cellSize: number = AOI_CELL_SIZE) {
    this.cellSize = cellSize;
  }

  get size(): number {
    return this.entries.size;
  }

  cellAt(x: number, z: number): CellKey {
    return encodeCell(Math.floor(x / this.cellSize), Math.floor(z / this.cellSize));
  }

  insert(id: string, x: number, z: number, item: T): void {
    this.remove(id);
    const cell = this.cellAt(x, z);
    const entry: Entry<T> = { id, x, z, cell, item };
    this.entries.set(id, entry);
    this.bucket(cell).add(entry);
  }

  /** 위치 갱신. 셀이 바뀌었으면 true — AoI 재계산이 필요하다는 신호다. */
  move(id: string, x: number, z: number): boolean {
    const entry = this.entries.get(id);
    if (!entry) return false;

    entry.x = x;
    entry.z = z;
    const next = this.cellAt(x, z);
    if (next === entry.cell) return false;

    this.cells.get(entry.cell)?.delete(entry);
    entry.cell = next;
    this.bucket(next).add(entry);
    return true;
  }

  remove(id: string): void {
    const entry = this.entries.get(id);
    if (!entry) return;
    const bucket = this.cells.get(entry.cell);
    if (bucket) {
      bucket.delete(entry);
      if (bucket.size === 0) this.cells.delete(entry.cell);
    }
    this.entries.delete(id);
  }

  /** 반경 안의 항목. 셀 단위로 추린 뒤 실제 거리로 거른다. */
  queryRadius(x: number, z: number, radius: number, out: T[] = []): T[] {
    out.length = 0;
    const r2 = radius * radius;
    const minX = Math.floor((x - radius) / this.cellSize);
    const maxX = Math.floor((x + radius) / this.cellSize);
    const minZ = Math.floor((z - radius) / this.cellSize);
    const maxZ = Math.floor((z + radius) / this.cellSize);

    for (let cx = minX; cx <= maxX; cx++) {
      for (let cz = minZ; cz <= maxZ; cz++) {
        const bucket = this.cells.get(encodeCell(cx, cz));
        if (!bucket) continue;
        for (const entry of bucket) {
          const dx = entry.x - x;
          const dz = entry.z - z;
          if (dx * dx + dz * dz <= r2) out.push(entry.item);
        }
      }
    }
    return out;
  }

  /** 지정한 셀들 안의 모든 항목 (거리 검사 없음 — AoI 브로드캐스트용) */
  queryCells(keys: Iterable<CellKey>, out: T[] = []): T[] {
    out.length = 0;
    for (const key of keys) {
      const bucket = this.cells.get(key);
      if (!bucket) continue;
      for (const entry of bucket) out.push(entry.item);
    }
    return out;
  }

  private bucket(cell: CellKey): Set<Entry<T>> {
    let bucket = this.cells.get(cell);
    if (!bucket) {
      bucket = new Set();
      this.cells.set(cell, bucket);
    }
    return bucket;
  }
}

/** (2*ring+1)^2 개의 주변 셀 */
export function cellsAround(
  grid: { cellAt(x: number, z: number): CellKey },
  x: number,
  z: number,
  ring: number,
  out: Set<CellKey> = new Set()
): Set<CellKey> {
  out.clear();
  const { cx, cz } = decodeCell(grid.cellAt(x, z));
  for (let dx = -ring; dx <= ring; dx++) {
    for (let dz = -ring; dz <= ring; dz++) {
      out.add(encodeCell(cx + dx, cz + dz));
    }
  }
  return out;
}

/**
 * 한 플레이어의 구독 셀 집합을 관리한다.
 *
 * 구독 반경(subscribeRing)보다 해제 반경(releaseRing)을 넓게 잡는 게 핵심이다.
 * 같으면 셀 경계에 서 있을 때 미세한 흔들림으로 구독/해제가 반복되면서
 * 주변 캐릭터가 깜빡인다(pop-in). 히스테리시스로 막는다.
 */
export class AreaOfInterest {
  private readonly current = new Set<CellKey>();
  private readonly scratch = new Set<CellKey>();

  private readonly subscribeRing: number;
  private readonly releaseRing: number;

  constructor(subscribeRing = 1, releaseRing = 2) {
    this.subscribeRing = subscribeRing;
    this.releaseRing = releaseRing;
  }

  get cells(): ReadonlySet<CellKey> {
    return this.current;
  }

  /**
   * 위치에 맞춰 구독 셀을 갱신하고, 바뀐 부분만 돌려준다.
   * entered = 새로 보이기 시작한 셀, left = 안 보이게 된 셀
   */
  update(
    grid: { cellAt(x: number, z: number): CellKey },
    x: number,
    z: number
  ): { entered: CellKey[]; left: CellKey[] } {
    const entered: CellKey[] = [];
    const left: CellKey[] = [];

    // 구독 반경 안은 무조건 포함
    cellsAround(grid, x, z, this.subscribeRing, this.scratch);
    for (const key of this.scratch) {
      if (!this.current.has(key)) {
        this.current.add(key);
        entered.push(key);
      }
    }

    // 해제 반경 밖으로 나간 것만 버린다 (히스테리시스)
    const keep = cellsAround(grid, x, z, this.releaseRing);
    for (const key of this.current) {
      if (!keep.has(key)) left.push(key);
    }
    for (const key of left) this.current.delete(key);

    return { entered, left };
  }

  clear(): void {
    this.current.clear();
  }
}
