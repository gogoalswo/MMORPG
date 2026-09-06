/**
 * 게임 서버(:2567)를 Cloudflare Tunnel 로 인터넷에 노출한다.
 *
 * 공유기 포트를 여는 게 아니라 **내 PC 가 밖으로 연결을 거는** 방식이라
 * 홈 네트워크가 노출되지 않는다.
 *
 * 무료(quick) 터널은 실행할 때마다 주소가 바뀐다. 그래서 클라이언트는
 * 서버 주소를 빌드에 박지 않고 ?server= 쿼리로 받는다 (net/connection.ts).
 * 이 스크립트가 그 링크를 만들어준다.
 *
 * 사용:
 *   node scripts/tunnel.mjs
 *   node scripts/tunnel.mjs https://내프로젝트.pages.dev
 */
import { spawn } from 'node:child_process';

const SERVER_PORT = 2567;
const pagesUrl = (process.argv[2] ?? process.env.PAGES_URL ?? '').replace(/\/+$/, '');

const child = spawn(
  'cloudflared',
  ['tunnel', '--url', `http://localhost:${SERVER_PORT}`, '--no-autoupdate'],
  { stdio: ['ignore', 'pipe', 'pipe'] }
);

child.on('error', (err) => {
  if (err.code === 'ENOENT') {
    console.error('cloudflared 가 설치되어 있지 않습니다.\n');
    console.error('  winget install --id Cloudflare.cloudflared\n');
    console.error('설치 후 새 터미널에서 다시 실행하세요.');
  } else {
    console.error('터널 실행 실패:', err.message);
  }
  process.exit(1);
});

let announced = false;

function scan(chunk) {
  const text = chunk.toString();
  process.stderr.write(text);

  if (announced) return;
  const match = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/i.exec(text);
  if (!match) return;

  announced = true;
  const https = match[0];
  const wss = https.replace(/^https/, 'wss');

  const line = '─'.repeat(64);
  console.log(`\n${line}`);
  console.log('터널이 열렸습니다.\n');
  console.log(`  서버 주소   ${wss}`);
  if (pagesUrl) {
    console.log(`  공유 링크   ${pagesUrl}/?server=${wss}`);
  } else {
    console.log('  공유 링크   (Pages 주소를 인자로 주면 만들어 드립니다)');
    console.log(`              node scripts/tunnel.mjs https://내프로젝트.pages.dev`);
  }
  console.log(`  로컬 확인   http://localhost:5173/?server=${wss}`);
  console.log('\n친구는 공유 링크로 한 번만 들어오면 주소가 저장됩니다.');
  console.log('이 창을 닫으면 터널이 끊깁니다. Ctrl+C 로 종료.');
  console.log(`${line}\n`);
}

child.stdout.on('data', scan);
child.stderr.on('data', scan);

const stop = () => {
  child.kill();
  process.exit(0);
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);

child.on('exit', (code) => process.exit(code ?? 0));
