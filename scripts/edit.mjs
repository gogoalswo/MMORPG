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
 *
 * **긴 덩어리는 `...` 한 줄로 가운데를 생략한다** (2026-09-17 에 추가).
 *
 *   node scripts/edit.mjs godot/game/game.gd <<'EOF'
 *   func _show_npc(payload: Dictionary) -> void:
 *   ...
 *   	_npc_panel.visible = true
 *   @@
 *   새 함수 전체
 *   EOF
 *
 * 없을 때는 파일을 통째로 다시 쓰게 되는데, 그러면 **하네스가 바뀐 파일을
 * 통째로 되돌려 준다** — 쓴 만큼 다시 받는다. 815줄짜리 items.ts 를 그렇게
 * 고쳤다가 파일 전체를 되받았다.
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
  const found = from.includes('\n...\n') ? locateRange(text, from) : locateExact(text, from);

  const nl = found.includes('\r\n') ? '\r\n' : '\n';
  text = text.replace(found, () => to.split('\n').join(nl));
  done.push(head(from));
}

writeFileSync(file, text);
console.log(`${file}: ${done.length}곳`);
for (const d of done) console.log('  · ' + d);

/** 정확히 그 글자를 찾는다. CRLF 판·LF 판을 차례로 대 본다 */
function locateExact(text, from) {
  for (const cand of [from.split('\n').join('\r\n'), from]) {
    const at = text.indexOf(cand);
    if (at < 0) continue;
    if (text.indexOf(cand, at + 1) >= 0) throw new Error('두 군데 이상이다: ' + head(from));
    return cand;
  }
  throw new Error('못 찾음: ' + head(from));
}

/**
 * `앞 조각 ... 뒤 조각` — 그 사이를 통째로 잡는다.
 *
 * 함수 하나를 갈아 끼울 때 가운데를 다시 적지 않아도 된다. 가운데를 적는 값이
 * 아까워 파일을 통째로 쓰기 시작하면 훨씬 비싸게 친다.
 */
function locateRange(text, from) {
  const parts = from.split('\n...\n');
  if (parts.length !== 2) throw new Error('`...` 는 한 블록에 한 번만: ' + head(from));

  for (const nl of ['\r\n', '\n']) {
    const open = parts[0].split('\n').join(nl);
    const close = parts[1].split('\n').join(nl);
    const start = text.indexOf(open);
    if (start < 0) continue;
    if (text.indexOf(open, start + 1) >= 0) throw new Error('시작이 두 군데 이상이다: ' + head(open));
    const end = text.indexOf(close, start + open.length);
    if (end < 0) throw new Error('끝을 못 찾음: ' + head(parts[1]));
    return text.slice(start, end + close.length);
  }
  throw new Error('못 찾음: ' + head(from));
}
