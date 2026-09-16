/**
 * 브라우저에서 `node:sqlite` 대신 쓰는 것. sql.js(웹어셈블리 SQLite)로 같은 SQL 을 돌린다.
 *
 * **db.ts 의 SQL 을 한 줄도 안 바꾸려고** 이렇게 했다. 저장을 키-값으로 새로 짜면
 * 서버 DB 와 로컬 DB 가 따로 놀기 시작하고, 서버를 붙일 때 둘을 다시 맞춰야 한다.
 *
 * 파일 대신 IndexedDB 에 DB 전체 바이트를 넣는다. 쓸 때마다 저장하면 느리므로
 * 쓰기가 멎고 0.5초 뒤에, 그리고 탭을 떠날 때 한 번 저장한다.
 *
 * DatabaseSync 생성자가 동기라 불러오기는 **모듈 최상위 await** 로 미리 끝내 둔다.
 */
import initSqlJs, { type Database, type SqlValue } from 'sql.js';
import wasmUrl from 'sql.js/dist/sql-wasm.wasm?url';

const IDB_NAME = 'mmo-local';
const IDB_STORE = 'files';
const SAVE_DELAY_MS = 500;

function openIdb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(IDB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(IDB_STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function loadFile(key: string): Promise<Uint8Array | undefined> {
  try {
    const idb = await openIdb();
    return await new Promise((resolve, reject) => {
      const req = idb.transaction(IDB_STORE).objectStore(IDB_STORE).get(key);
      req.onsuccess = () => resolve(req.result as Uint8Array | undefined);
      req.onerror = () => reject(req.error);
    });
  } catch (err) {
    // 시크릿 모드 등 — 저장 없이 이번 한 판만 돈다
    console.warn('[local-db] 불러오기 실패, 빈 DB 로 시작', err);
    return undefined;
  }
}

async function saveFile(key: string, bytes: Uint8Array): Promise<void> {
  try {
    const idb = await openIdb();
    await new Promise<void>((resolve, reject) => {
      const tx = idb.transaction(IDB_STORE, 'readwrite');
      tx.objectStore(IDB_STORE).put(bytes, key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch (err) {
    console.warn('[local-db] 저장 실패', err);
  }
}

const SQL = await initSqlJs({ locateFile: () => wasmUrl });
// 경로는 서버 기본값(data/game.db)을 그대로 키로 쓴다. DB 는 하나뿐이다.
const preloaded = new Map<string, Uint8Array | undefined>([['data/game.db', await loadFile('data/game.db')]]);

type Param = SqlValue | undefined | boolean;

/** node:sqlite 는 undefined 를 못 받지만 sql.js 는 아예 터진다. 둘 다 null 로 맞춘다 */
function toParams(params: Param[]): SqlValue[] {
  return params.map((p) => (p === undefined ? null : typeof p === 'boolean' ? Number(p) : p));
}

export class DatabaseSync {
  constructor(path: string) {
    this.path = path;
    this.db = new SQL.Database(preloaded.get(path));
    addEventListener('pagehide', () => this.flush());
  }
  private readonly path: string;
  private readonly db: Database;
  private saveTimer: ReturnType<typeof setTimeout> | undefined;

  exec(sql: string): void {
    this.db.exec(sql);
    this.scheduleSave();
  }

  prepare(sql: string) {
    return {
      run: (...params: Param[]) => {
        this.db.run(sql, toParams(params));
        const changes = this.db.getRowsModified();
        this.scheduleSave();
        return { changes, lastInsertRowid: 0 };
      },
      get: (...params: Param[]): Record<string, unknown> | undefined => {
        const stmt = this.db.prepare(sql, toParams(params));
        try {
          return stmt.step() ? stmt.getAsObject() : undefined;
        } finally {
          stmt.free();
        }
      },
      all: (...params: Param[]): Record<string, unknown>[] => {
        const stmt = this.db.prepare(sql, toParams(params));
        const rows: Record<string, unknown>[] = [];
        try {
          while (stmt.step()) rows.push(stmt.getAsObject());
        } finally {
          stmt.free();
        }
        return rows;
      },
    };
  }

  close(): void {
    this.flush();
    this.db.close();
  }

  private scheduleSave(): void {
    if (this.saveTimer !== undefined) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.flush(), SAVE_DELAY_MS);
  }

  private flush(): void {
    if (this.saveTimer === undefined) return;
    clearTimeout(this.saveTimer);
    this.saveTimer = undefined;
    const bytes = this.db.export();
    // export() 가 연결을 다시 열면서 PRAGMA 가 기본값으로 돌아간다
    this.db.exec('PRAGMA foreign_keys = ON');
    void saveFile(this.path, bytes);
  }
}
