/**
 * 브라우저에서 `node:fs` · `node:path` 대신 쓰는 것.
 * db.ts 가 파일 경로의 폴더를 만드는 데만 쓴다 — 브라우저 DB 는 IndexedDB 라 할 일이 없다.
 */

export function mkdirSync(_path: string, _options?: { recursive?: boolean }): void {}

export function dirname(path: string): string {
  const i = path.lastIndexOf('/');
  return i <= 0 ? (i === 0 ? '/' : '.') : path.slice(0, i);
}
