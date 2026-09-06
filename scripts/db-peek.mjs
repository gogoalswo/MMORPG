/** DB 내용을 빠르게 들여다본다 (개발용) */
import { DatabaseSync } from 'node:sqlite';
const db = new DatabaseSync(process.env.DB_PATH ?? 'data/game.db', { readOnly: true });
console.log('계정:', db.prepare('SELECT COUNT(*) n FROM account').get().n,
            '| 토큰:', db.prepare('SELECT COUNT(*) n FROM auth_token').get().n);
for (const c of db.prepare('SELECT name, job, zone_id, x, z, hp, level FROM character').all()) {
  console.log(`  ${c.name.padEnd(10)} ${c.job.padEnd(8)} ${c.zone_id.padEnd(16)} x=${c.x.toFixed(2)} z=${c.z.toFixed(2)} hp=${c.hp} lv=${c.level}`);
}
db.close();
