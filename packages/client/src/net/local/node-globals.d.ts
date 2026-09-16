// 서버 코드(db.ts)가 읽는 process.env. 값은 vite.config.ts 의 define 이 채운다.
declare const process: { env: Record<string, string | undefined> };
