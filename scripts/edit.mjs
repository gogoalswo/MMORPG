/**
 * 개행에 신경 쓰지 않고 파일을 고친다.
 *
 * 이 저장소는 파일마다, 한 파일 안에서도 CRLF 와 LF 가 섞여 있다
 * (`core.autocrlf = true` 라 체크아웃한 파일은 CRLF 인데, 도구가 새로 쓴 파일은
 * LF 로 남는다). 그런데 **Git Bash 의 grep 으로는 어느 쪽인지 알 수 없다** —
 * CRLF 를 벗기고 읽어서 `grep -c $'\r$'` 가 LF 파일에도 전체 줄 수를 돌려준다.
 * 짐작으로 패치를 짜면 빗나가고, 확인하려 들면 왕복만 는다. 그래서 **묻지 않는다** —
 * 두 형태를 다 대보고, 넣을 때는 그 자리에 있던 개행을 그대로 쓴다.
 *
 *   node scripts/edit.mjs <파일> <<'EOF'
 *   찾을 줄들
 *   @@
 *   바꿀 줄들
 *   EOF
 *
 * `%%` 한 줄로 구분하면 한 번에 여러 곳을 고친다. 찾는 것이 없거나 두 군데
 * 이상이면 **아무것도 쓰지 않고** 멈춘다 — 반쯤 적용된 파일이 제일 비싸다.
 */
import { readFileSync, writeFileSync } from 'node:fs';

const file = process.argv[2];
if (!file) throw new Error("사용법: node scripts/edit.mjs <파일> <<'EOF' ... @@ ... EOF");

const toLf = (s) => s.split('\r\n').join('\n');
const head = (s) => s.split('\n')[0].trim().slice(0, 56);

const spec = toLf(readFileSync(0, 'utf8')).replace(/\n$/, '');
let text = readFileSync(file, 'utf8');
const done = [];

for (const block of spec.split('\n%%\n')) {
  const half = block.split('\n@@\n');
  if (half.length !== 2) throw new Error('블록마다 @@ 한 줄이 있어야 한다: ' + head(block));
  const [from, to] = half;

  // 같은 내용의 CRLF 판·LF 판을 차례로 대 본다. 맞는 쪽이 그 자리의 개행이다.
  let found = null;
  for (const cand of [from.split('\n').join('\r\n'), from]) {
    const at = text.indexOf(cand);
    if (at < 0) continue;
    if (text.indexOf(cand, at + 1) >= 0) throw new Error('두 군데 이상이다: ' + head(from));
    found = cand;
    break;
  }
  if (!found) throw new Error('못 찾음: ' + head(from));

  const nl = found.includes('\r\n') ? '\r\n' : '\n';
  text = text.replace(found, () => to.split('\n').join(nl));
  done.push(head(from));
}

writeFileSync(file, text);
console.log(`${file}: ${done.length}곳`);
for (const d of done) console.log('  · ' + d);
