/**
 * 게임 서버를 띄우면서 출력을 logs/server.log 에도 남긴다.
 *
 * 콘솔로만 흘려보내면 나중에 "그때 서버가 뭐라고 했더라"를 확인할 방법이 없다.
 * 재시작하면 파일을 새로 시작한다 — 예전 실행의 오류가 섞이면 더 헷갈린다.
 */
import { spawn } from 'node:child_process';
import { createWriteStream, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const logPath = join(root, 'logs', 'server.log');
mkdirSync(dirname(logPath), { recursive: true });

const log = createWriteStream(logPath, { flags: 'w' });
log.write(`# 서버 시작 ${new Date().toISOString()}\n`);

const child = spawn(process.execPath, ['--watch', 'src/index.ts'], {
  cwd: join(root, 'packages', 'server'),
  stdio: ['inherit', 'pipe', 'pipe'],
});

for (const [stream, out] of [[child.stdout, process.stdout], [child.stderr, process.stderr]]) {
  stream.on('data', (chunk) => {
    out.write(chunk);
    log.write(chunk);
  });
}

child.on('exit', (code) => {
  log.write(`# 서버 종료 code=${code}\n`);
  process.exit(code ?? 0);
});
