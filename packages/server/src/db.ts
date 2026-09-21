import { DatabaseSync } from 'node:sqlite';
import {
  GRADE_MAX,
  migrateItemId,
  GRADE_MIN,
  MAX_ENHANCE,
  getItem,
  rollOptions,
  sanitizeOptions,
  type ItemStack,
} from '@mmo/shared';
import { randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

/**
 * 저장소.
 *
 * SQLite 를 쓴다 — Node 24 에 내장(node:sqlite)이라 설치할 게 없고,
 * 서버가 아직 단일 프로세스라 Postgres 가 줄 이점(동시 접근, 복제)이 없다.
 * 여러 서버로 늘릴 때 이 파일의 함수 구현만 바꾸면 되도록,
 * 바깥에서는 SQL 을 직접 만지지 않는다.
 */

const DB_PATH = process.env.DB_PATH ?? 'data/game.db';

mkdirSync(dirname(DB_PATH), { recursive: true });
const db = new DatabaseSync(DB_PATH);

// WAL: 읽기와 쓰기가 서로를 막지 않는다. 게임 루프가 저장 때문에 멈추면 안 된다.
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS account (
    id            TEXT PRIMARY KEY,
    created_at    INTEGER NOT NULL,
    last_seen_at  INTEGER NOT NULL,
    -- 구글 연동 전에는 NULL. 연동하면 구글의 고유 사용자 id 가 들어간다.
    google_sub    TEXT UNIQUE,
    google_email  TEXT
  );

  CREATE TABLE IF NOT EXISTS auth_token (
    -- 토큰 원문은 저장하지 않는다. DB 가 새도 그대로 로그인에 쓸 수 없도록.
    token_hash  TEXT PRIMARY KEY,
    account_id  TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    created_at  INTEGER NOT NULL,
    expires_at  INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_token_account ON auth_token(account_id);

  CREATE TABLE IF NOT EXISTS character (
    id          TEXT PRIMARY KEY,
    account_id  TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    name        TEXT NOT NULL UNIQUE COLLATE NOCASE,
    job         TEXT NOT NULL,
    zone_id     TEXT NOT NULL,
    x           REAL NOT NULL,
    z           REAL NOT NULL,
    hp          INTEGER NOT NULL,
    max_hp      INTEGER NOT NULL,
    level       INTEGER NOT NULL DEFAULT 1,
    exp         INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_character_account ON character(account_id);
`);

/**
 * 이미 만들어진 DB 에 열을 덧붙인다.
 *
 * CREATE TABLE IF NOT EXISTS 는 표가 있으면 통째로 건너뛰므로, 나중에 추가한
 * 열은 이렇게 따로 붙여야 한다. 안 그러면 기존 DB 로 켰을 때만 터진다.
 */
function addColumnIfMissing(table: string, column: string, definition: string): void {
  const cols = db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[];
  if (cols.some((c) => c.name === column)) return;
  db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
}

addColumnIfMissing('character', 'gold', 'INTEGER NOT NULL DEFAULT 0');
addColumnIfMissing('character', 'inventory', "TEXT NOT NULL DEFAULT '[]'");
addColumnIfMissing('character', 'equipment', "TEXT NOT NULL DEFAULT '{}'");
addColumnIfMissing('character', 'skills', "TEXT NOT NULL DEFAULT '[]'");
addColumnIfMissing('character', 'skill_bar', "TEXT NOT NULL DEFAULT '[]'");
addColumnIfMissing('character', 'skill_points', 'INTEGER NOT NULL DEFAULT 0');

export interface Account {
  id: string;
  googleSub: string | null;
  googleEmail: string | null;
}

export interface CharacterRow {
  id: string;
  accountId: string;
  name: string;
  job: string;
  zoneId: string;
  x: number;
  z: number;
  hp: number;
  maxHp: number;
  level: number;
  exp: number;
  gold: number;
  /** 가방에 든 물건들 */
  inventory: ItemStack[];
  /** 슬롯별 착용 중인 물건 */
  equipment: Record<string, ItemStack>;
  /** 배운 스킬 */
  skills: string[];
  /** 액션바에 올린 스킬 (최대 4) */
  skillBar: string[];
  /** 아직 안 쓴 스킬 포인트 */
  skillPoints: number;
}

const now = () => Date.now();

// ---------------------------------------------------------------- 계정

export function createAccount(): Account {
  const id = randomUUID();
  const t = now();
  db.prepare('INSERT INTO account (id, created_at, last_seen_at) VALUES (?, ?, ?)').run(id, t, t);
  return { id, googleSub: null, googleEmail: null };
}

export function getAccount(id: string): Account | null {
  const row = db
    .prepare('SELECT id, google_sub, google_email FROM account WHERE id = ?')
    .get(id) as { id: string; google_sub: string | null; google_email: string | null } | undefined;
  if (!row) return null;
  return { id: row.id, googleSub: row.google_sub, googleEmail: row.google_email };
}

export function getAccountByGoogleSub(sub: string): Account | null {
  const row = db
    .prepare('SELECT id, google_sub, google_email FROM account WHERE google_sub = ?')
    .get(sub) as { id: string; google_sub: string | null; google_email: string | null } | undefined;
  if (!row) return null;
  return { id: row.id, googleSub: row.google_sub, googleEmail: row.google_email };
}

export function touchAccount(id: string): void {
  db.prepare('UPDATE account SET last_seen_at = ? WHERE id = ?').run(now(), id);
}

/** 게스트 계정에 구글을 붙인다. 이미 다른 계정이 쓰는 구글이면 실패한다. */
export function linkGoogle(accountId: string, sub: string, email: string | null): boolean {
  const taken = getAccountByGoogleSub(sub);
  if (taken && taken.id !== accountId) return false;
  db.prepare('UPDATE account SET google_sub = ?, google_email = ? WHERE id = ?').run(
    sub,
    email,
    accountId
  );
  return true;
}

// ---------------------------------------------------------------- 토큰

export function storeToken(accountId: string, tokenHash: string, ttlMs: number): void {
  const t = now();
  db.prepare(
    'INSERT OR REPLACE INTO auth_token (token_hash, account_id, created_at, expires_at) VALUES (?, ?, ?, ?)'
  ).run(tokenHash, accountId, t, t + ttlMs);
}

export function findTokenAccount(tokenHash: string): string | null {
  const row = db
    .prepare('SELECT account_id, expires_at FROM auth_token WHERE token_hash = ?')
    .get(tokenHash) as { account_id: string; expires_at: number } | undefined;
  if (!row) return null;
  if (row.expires_at < now()) {
    db.prepare('DELETE FROM auth_token WHERE token_hash = ?').run(tokenHash);
    return null;
  }
  return row.account_id;
}

/** 만료된 토큰 청소 (서버 시작 시 한 번) */
export function pruneTokens(): number {
  const info = db.prepare('DELETE FROM auth_token WHERE expires_at < ?').run(now());
  return Number(info.changes);
}

// ---------------------------------------------------------------- 캐릭터

function toCharacter(row: Record<string, unknown>): CharacterRow {
  return {
    id: row.id as string,
    accountId: row.account_id as string,
    name: row.name as string,
    job: row.job as string,
    zoneId: row.zone_id as string,
    x: row.x as number,
    z: row.z as number,
    hp: row.hp as number,
    maxHp: row.max_hp as number,
    level: row.level as number,
    exp: row.exp as number,
    gold: (row.gold as number) ?? 0,
    inventory: toStacks(parseJson<unknown[]>(row.inventory, [])),
    equipment: toStackMap(parseJson<Record<string, unknown>>(row.equipment, {})),
    skills: toStrings(parseJson<unknown[]>(row.skills, [])),
    skillBar: toStrings(parseJson<unknown[]>(row.skill_bar, [])),
    skillPoints: (row.skill_points as number) ?? 0,
  };
}

/**
 * 저장해 둔 JSON 을 읽는다.
 *
 * 깨진 값 하나 때문에 캐릭터가 영영 못 들어오면 안 되므로, 못 읽으면 빈 값으로
 * 떨어뜨린다. 가방을 잃는 건 아프지만 접속이 막히는 것보단 낫다.
 */
/**
 * 등급·옵션이 없던 시절의 데이터를 읽어들인다.
 *
 * 예전에는 아이템 id 문자열만 저장했다. 그대로 두면 등급이 undefined 가 되어
 * 능력치 계산이 NaN 으로 번지므로, 읽는 자리에서 1등급으로 올려준다.
 *
 * 옵션은 한 발 더 나간다 — **아예 없던 물건에는 여기서 굴려 붙인다.** 옵션이
 * 생기기 전에 주운 장비를 옵션 0개로 두면 영영 못 고치는 쓰레기가 되고,
 * 부수라고 하기에는 남의 가방이다. 한 번 굴리면 저장되므로 다음 접속부터는
 * 그대로다. 빈 배열([])은 "굴렸는데 안 붙었다"가 아니라 재료라는 뜻이므로
 * 다시 굴리지 않는다.
 */
function toStack(raw: unknown): ItemStack | null {
  if (typeof raw === 'string') return withOptions({ id: raw, grade: 1, enhance: 0 }, undefined);
  if (raw && typeof raw === 'object') {
    const o = raw as { id?: unknown; grade?: unknown; enhance?: unknown; options?: unknown };
    if (typeof o.id !== 'string') return null;
    const grade = typeof o.grade === 'number' && Number.isFinite(o.grade) ? Math.round(o.grade) : 1;
    const enhance =
      typeof o.enhance === 'number' && Number.isFinite(o.enhance) ? Math.round(o.enhance) : 0;
    return withOptions(
      {
        id: o.id,
        grade: Math.min(GRADE_MAX, Math.max(GRADE_MIN, grade)),
        enhance: Math.min(MAX_ENHANCE, Math.max(0, enhance)),
      },
      o.options
    );
  }
  return null;
}

/**
 * 저장된 옵션을 지금 규칙으로 다듬고, 없으면 한 번 굴려 붙인다.
 *
 * **id 와 등급도 여기서 맞춘다** (2026-09-21). 단계 축을 없애면서 옛 id 는
 * `migrateItemId` 로 옮기고, 등급은 이제 아이템이 들고 있으므로 저장값이 아니라
 * 표에서 가져온다 — 둘이 어긋나면 수치와 표시가 따로 논다
 */
function withOptions(stack: ItemStack, raw: unknown): ItemStack {
  const id = migrateItemId(stack.id);
  const item = id ? getItem(id) : null;
  if (!item) return { ...stack, options: [] };
  const moved: ItemStack = { ...stack, id: item.id, grade: item.grade };
  if (raw === undefined || raw === null) {
    return { ...moved, options: rollOptions(item, moved.grade) };
  }
  return { ...moved, options: sanitizeOptions(raw, item, moved.grade) };
}

function toStrings(raw: unknown[]): string[] {
  return Array.isArray(raw) ? raw.filter((x): x is string => typeof x === 'string') : [];
}

function toStacks(raw: unknown[]): ItemStack[] {
  return raw.map(toStack).filter((s): s is ItemStack => s !== null);
}

function toStackMap(raw: Record<string, unknown>): Record<string, ItemStack> {
  const out: Record<string, ItemStack> = {};
  for (const [slot, value] of Object.entries(raw)) {
    const stack = toStack(value);
    if (stack) out[slot] = stack;
  }
  return out;
}

function parseJson<T>(raw: unknown, fallback: T): T {
  if (typeof raw !== 'string') return fallback;
  try {
    const parsed: unknown = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? (parsed as T) : fallback;
  } catch {
    return fallback;
  }
}

/** 계정이 가질 수 있는 캐릭터 수 */
export const MAX_CHARACTERS = 4;

export function getCharactersByAccount(accountId: string): CharacterRow[] {
  const rows = db
    .prepare('SELECT * FROM character WHERE account_id = ? ORDER BY created_at')
    .all(accountId) as Record<string, unknown>[];
  return rows.map(toCharacter);
}

/** id 로 찾되 **소유자를 함께 확인한다** — 남의 캐릭터를 지정해 보낼 수 있다 */
export function getOwnedCharacter(accountId: string, characterId: string): CharacterRow | null {
  const row = db
    .prepare('SELECT * FROM character WHERE id = ? AND account_id = ?')
    .get(characterId, accountId) as Record<string, unknown> | undefined;
  return row ? toCharacter(row) : null;
}

export function deleteOwnedCharacter(accountId: string, characterId: string): boolean {
  const info = db
    .prepare('DELETE FROM character WHERE id = ? AND account_id = ?')
    .run(characterId, accountId);
  return Number(info.changes) > 0;
}

export function getCharacterByAccount(accountId: string): CharacterRow | null {
  const row = db
    .prepare('SELECT * FROM character WHERE account_id = ? ORDER BY created_at LIMIT 1')
    .get(accountId) as Record<string, unknown> | undefined;
  return row ? toCharacter(row) : null;
}

export function isNameTaken(name: string): boolean {
  return db.prepare('SELECT 1 FROM character WHERE name = ?').get(name) !== undefined;
}

export function createCharacter(
  accountId: string,
  name: string,
  job: string,
  zoneId: string,
  x: number,
  z: number
): CharacterRow {
  const id = randomUUID();
  const t = now();
  db.prepare(
    `INSERT INTO character (id, account_id, name, job, zone_id, x, z, hp, max_hp, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 100, 100, ?, ?)`
  ).run(id, accountId, name, job, zoneId, x, z, t, t);
  return {
    id,
    accountId,
    name,
    job,
    zoneId,
    x,
    z,
    hp: 100,
    maxHp: 100,
    level: 1,
    exp: 0,
    gold: 0,
    inventory: [],
    equipment: {},
    skills: [],
    skillBar: [],
    skillPoints: 0,
  };
}

/** 접속 종료·존 이동 시 위치를 남긴다 */
export function saveCharacterPosition(
  id: string,
  zoneId: string,
  x: number,
  z: number,
  hp: number
): void {
  db.prepare('UPDATE character SET zone_id = ?, x = ?, z = ?, hp = ?, updated_at = ? WHERE id = ?').run(
    zoneId,
    x,
    z,
    hp,
    now(),
    id
  );
}

/** 레벨업·경험치 획득 시점에 바로 남긴다 (위치와 달리 놓치면 아깝다) */
export function saveCharacterProgress(id: string, level: number, exp: number): void {
  db.prepare('UPDATE character SET level = ?, exp = ?, updated_at = ? WHERE id = ?').run(
    level,
    exp,
    now(),
    id
  );
}

/** 골드·가방·장비를 저장한다 */
export function saveCharacterItems(
  id: string,
  gold: number,
  inventory: ItemStack[],
  equipment: Record<string, ItemStack>
): void {
  db.prepare('UPDATE character SET gold = ?, inventory = ?, equipment = ?, updated_at = ? WHERE id = ?').run(
    Math.max(0, Math.round(gold)),
    JSON.stringify(inventory),
    JSON.stringify(equipment),
    now(),
    id
  );
}

/** 배운 스킬·액션바·남은 포인트를 저장한다 */
export function saveCharacterSkills(
  id: string,
  skills: string[],
  skillBar: string[],
  skillPoints: number
): void {
  db.prepare(
    'UPDATE character SET skills = ?, skill_bar = ?, skill_points = ?, updated_at = ? WHERE id = ?'
  ).run(JSON.stringify(skills), JSON.stringify(skillBar), Math.max(0, Math.round(skillPoints)), now(), id);
}

export function setCharacterJob(id: string, job: string): void {
  db.prepare('UPDATE character SET job = ?, updated_at = ? WHERE id = ?').run(job, now(), id);
}

/**
 * 캐릭터를 만들지 않고 떠난 게스트 계정을 지운다.
 *
 * 생성 화면에서 이탈할 때마다 빈 계정이 하나씩 쌓인다.
 * 구글이 연결된 계정은 캐릭터가 없어도 사용자의 의도가 담긴 것이므로 건드리지 않는다.
 */
export function pruneEmptyGuests(olderThanMs: number): number {
  const cutoff = now() - olderThanMs;
  const info = db
    .prepare(
      `DELETE FROM account
        WHERE google_sub IS NULL
          AND last_seen_at < ?
          AND id NOT IN (SELECT account_id FROM character)`
    )
    .run(cutoff);
  return Number(info.changes);
}

export function countAccounts(): number {
  const row = db.prepare('SELECT COUNT(*) AS n FROM account').get() as { n: number };
  return row.n;
}

export function closeDatabase(): void {
  db.close();
}
