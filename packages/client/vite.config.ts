import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

import { gameServer } from '../../scripts/vite-plugin-game-server.mjs';

// 에셋은 저장소 루트의 public/ 에 둔다 (서버 툴링도 같은 파일을 참조할 수 있게).
// Vite 의 기본 publicDir 은 프로젝트 루트 기준이라 명시해줘야 한다.
const publicDir = fileURLToPath(new URL('../../public', import.meta.url));

/**
 * 로컬 모드(서버 없이 브라우저 안에서 ZoneRoom 을 돌림)용 대체 모듈.
 * tsconfig.json 의 paths 와 같은 표다 — 하나를 고치면 다른 하나도 고친다.
 */
const shim = (file: string) => fileURLToPath(new URL(`./src/net/local/shims/${file}`, import.meta.url));
const nodeShims = [
  { find: /^colyseus$/, replacement: shim('colyseus.ts') },
  { find: /^node:sqlite$/, replacement: shim('sqlite.ts') },
  { find: /^node:crypto$/, replacement: shim('crypto.ts') },
  { find: /^node:(fs|path)$/, replacement: shim('node.ts') },
];

export default defineConfig({
  // dev 로 띄우면 게임 서버(:2567)도 없으면 같이 올라온다.
  plugins: [gameServer()],
  publicDir,
  // GitHub Pages 는 https://<아이디>.github.io/<저장소>/ 아래에 올라간다. 워크플로우가 넣어 준다.
  base: process.env.VITE_BASE ?? '/',
  resolve: { alias: nodeShims },
  // 서버 db.ts 가 읽는다. 브라우저엔 process 가 없다
  define: { 'process.env.DB_PATH': 'undefined' },
  server: { port: 5173, host: true },
  build: { target: 'es2022', sourcemap: true },
});
