/**
 * vite dev 서버가 뜰 때 게임 서버(:2567)가 없으면 같이 띄운다.
 *
 * 터미널을 두 개 여는 걸 자꾸 잊어서, 5173 은 열리는데 접속만 안 되는
 * 상태로 한참 헤매는 일이 반복됐다. 클라이언트 없이 게임 서버만 띄우는
 * 경우(probe, 부하 확인)는 여전히 `npm run server` 로 따로 돌리면 된다.
 *
 * 이미 떠 있으면 건드리지 않는다 — `npm run server` 를 먼저 돌려 둔
 * 터미널의 로그를 빼앗지 않기 위해서다.
 */
import { spawn } from 'node:child_process';
import { connect } from 'node:net';
import { fileURLToPath } from 'node:url';

// vite 를 띄우는 쪽(에디터 preview 등)이 PORT=5173 을 넣어두는 경우가 있다.
// 게임 서버도 같은 변수를 읽어서 5173 을 잡으려다 EADDRINUSE 로 죽었다.
// 그래서 여기서는 환경변수를 보지 않고, 자식에게도 PORT 를 물려주지 않는다.
const SERVER_PORT = 2567;

/** 127.0.0.1:port 에 붙어보고 곧바로 끊는다. 400ms 안에 안 붙으면 없는 것으로 본다. */
function isListening(port) {
  return new Promise((resolve) => {
    const socket = connect({ port, host: '127.0.0.1' });
    const done = (up) => {
      socket.destroy();
      resolve(up);
    };
    socket.setTimeout(400);
    socket.on('connect', () => done(true));
    socket.on('timeout', () => done(false));
    socket.on('error', () => done(false));
  });
}

/**
 * serve.mjs 는 자기도 자식(node --watch src/index.ts)을 낳는다.
 * 그래서 부모만 죽이면 손자가 포트를 쥔 채 남는다 — 다음 실행에서
 * EADDRINUSE 로 터진다. 윈도우는 taskkill /T, 그 외는 프로세스 그룹째 보낸다.
 */
function killTree(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  if (process.platform === 'win32') {
    spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
  } else {
    try {
      process.kill(-child.pid);
    } catch {
      child.kill();
    }
  }
}

export function gameServer() {
  return {
    name: 'mmo-game-server',
    apply: 'serve',
    async configureServer(server) {
      const { logger } = server.config;

      if (await isListening(SERVER_PORT)) {
        logger.info(`  게임 서버  :${SERVER_PORT} 이미 떠 있음`);
        return;
      }

      const script = fileURLToPath(new URL('./serve.mjs', import.meta.url));
      const env = { ...process.env };
      delete env.PORT;
      const child = spawn(process.execPath, [script], {
        stdio: 'inherit',
        detached: process.platform !== 'win32',
        env,
      });
      logger.info(`  게임 서버  :${SERVER_PORT} 자동 실행 (로그: logs/server.log)`);

      child.on('exit', (code) => {
        if (code) logger.error(`  게임 서버가 code=${code} 로 끝났습니다. logs/server.log 를 보세요.`);
      });

      const stop = () => killTree(child);
      process.once('exit', stop);
      process.once('SIGINT', () => {
        stop();
        process.exit(0);
      });
      server.httpServer?.once('close', stop);
    },
  };
}
