import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

// 에셋은 저장소 루트의 public/ 에 둔다 (서버 툴링도 같은 파일을 참조할 수 있게).
// Vite 의 기본 publicDir 은 프로젝트 루트 기준이라 명시해줘야 한다.
const publicDir = fileURLToPath(new URL('../../public', import.meta.url));

export default defineConfig({
  publicDir,
  server: { port: 5173, host: true },
  build: { target: 'es2022', sourcemap: true },
});
