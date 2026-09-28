// 답변이 끝날 때(Stop 훅) 마지막 답변이 영어로 쓰였으면 되돌려 보내 한국어로 다시 쓰게 한다.
// CLAUDE.md 규칙과 UserPromptSubmit 훅(알려 주기)만으로는 영어로 새는 일이 되풀이됐다 (2026-09-28).
// 코드 블록 · `식별자` · 주소는 원래 영어라 세지 않는다. 한 번 되돌린 뒤(stop_hook_active)에는
// 다시 막지 않는다 — 끝없이 도는 것을 막으려고.
import { readFileSync } from 'node:fs';

let input = {};
try { input = JSON.parse(readFileSync(0, 'utf8') || '{}'); } catch { process.exit(0); }
if (input.stop_hook_active || !input.transcript_path) process.exit(0);

let lines;
try { lines = readFileSync(input.transcript_path, 'utf8').trim().split('\n'); } catch { process.exit(0); }

let text = '';
for (let i = lines.length - 1; i >= 0 && !text; i--) {
  let row;
  try { row = JSON.parse(lines[i]); } catch { continue; }
  if (row.type !== 'assistant' || !Array.isArray(row.message?.content)) continue;
  text = row.message.content.filter((c) => c.type === 'text').map((c) => c.text).join('\n');
}
if (!text) process.exit(0);

const prose = text
  .replace(/```[\s\S]*?```/g, ' ')
  .replace(/`[^`]*`/g, ' ')
  .replace(/https?:\/\/\S+/g, ' ');
const hangul = (prose.match(/[가-힣]/g) || []).length;
const latin = (prose.match(/[A-Za-z]/g) || []).length;

if (latin >= 30 && hangul * 2 < latin) {
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason: `방금 답변이 영어로 쓰였다 (한글 ${hangul}자 · 영문 ${latin}자). 사용자는 한국어로만 답하라고 여러 번 지적했다 — 같은 내용을 한국어로 다시 써라. 코드 식별자·파일명·명령어만 원래 글자로 둔다.`,
  }));
}
