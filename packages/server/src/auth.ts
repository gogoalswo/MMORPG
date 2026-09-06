import { createHash, randomBytes } from 'node:crypto';
import {
  createAccount,
  findTokenAccount,
  getAccount,
  getAccountByGoogleSub,
  linkGoogle,
  storeToken,
  touchAccount,
  type Account,
} from './db.ts';

/**
 * 인증.
 *
 * 게스트로 즉시 시작하고, 원하면 나중에 구글을 붙이는 구조다.
 * 웹게임에서 흔한 방식 — 로그인 화면이 진입 장벽이 되지 않으면서도
 * 기기를 바꾸거나 브라우저 데이터를 지워도 진행도를 지킬 수 있다.
 *
 * 토큰은 원문을 저장하지 않고 SHA-256 해시만 남긴다.
 * DB 가 유출돼도 그 값으로 로그인할 수 없다.
 */

const TOKEN_TTL_MS = 1000 * 60 * 60 * 24 * 365; // 1년

function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

function issueToken(accountId: string): string {
  const token = randomBytes(32).toString('base64url');
  storeToken(accountId, hashToken(token), TOKEN_TTL_MS);
  return token;
}

export interface Session {
  account: Account;
  /** 새로 발급된 토큰. 클라이언트가 저장해야 다음에 같은 계정으로 들어온다 */
  token: string;
  isNewAccount: boolean;
}

/**
 * 토큰이 있으면 그 계정으로, 없거나 만료됐으면 새 게스트 계정을 만든다.
 * 절대 실패하지 않는다 — 접속 자체가 막히면 안 되기 때문이다.
 */
export function authenticate(token: string | undefined): Session {
  if (typeof token === 'string' && token.length > 0) {
    const accountId = findTokenAccount(hashToken(token));
    if (accountId) {
      const account = getAccount(accountId);
      if (account) {
        touchAccount(account.id);
        // 기존 토큰을 그대로 돌려준다 (재발급하면 다른 탭이 끊긴다)
        return { account, token, isNewAccount: false };
      }
    }
  }

  const account = createAccount();
  return { account, token: issueToken(account.id), isNewAccount: true };
}

// ---------------------------------------------------------------- 구글 연동

interface GoogleTokenInfo {
  sub: string;
  email?: string;
  aud: string;
  exp: string;
}

export type LinkResult =
  | { ok: true; account: Account; token: string; switched: boolean }
  | { ok: false; reason: string };

/**
 * 구글 ID 토큰을 검증한다.
 *
 * 구글의 tokeninfo 엔드포인트를 쓴다 — 로그인마다 네트워크 왕복이 한 번 늘지만
 * 의존성이 없고 서명 검증 로직을 직접 짤 일이 없다.
 * 로그인 트래픽이 커지면 JWKS 를 받아 로컬 검증으로 바꾸는 게 맞다.
 */
async function verifyGoogleIdToken(idToken: string): Promise<GoogleTokenInfo | null> {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  if (!clientId) return null;

  let info: GoogleTokenInfo;
  try {
    const res = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`
    );
    if (!res.ok) return null;
    info = (await res.json()) as GoogleTokenInfo;
  } catch {
    return null;
  }

  // aud 확인이 핵심이다. 이걸 빼먹으면 **다른 서비스용으로 발급된 토큰**으로도
  // 로그인이 뚫린다 — 구글 연동에서 가장 흔한 취약점.
  if (info.aud !== clientId) return null;
  if (!info.sub) return null;
  if (Number(info.exp) * 1000 < Date.now()) return null;

  return info;
}

/**
 * 구글 계정을 현재 세션에 연결한다.
 *
 * 세 가지 경우가 있다:
 *  1. 이 구글이 처음 → 지금 쓰던 게스트 계정에 붙인다 (진행도 유지)
 *  2. 이미 이 구글로 만든 계정이 있고 지금 계정과 같다 → 아무것도 안 한다
 *  3. 이미 있고 다른 계정이다 → 그 계정으로 갈아탄다 (기기 변경/재설치 복구)
 *
 * 3번에서 지금 게스트 계정의 진행도는 버려진다. 되돌릴 수 없으니
 * 클라이언트가 미리 경고해야 한다.
 */
export async function linkOrLoginWithGoogle(
  currentAccountId: string,
  idToken: string
): Promise<LinkResult> {
  const info = await verifyGoogleIdToken(idToken);
  if (!info) {
    return {
      ok: false,
      reason: process.env.GOOGLE_CLIENT_ID
        ? '구글 인증에 실패했습니다.'
        : '서버에 GOOGLE_CLIENT_ID 가 설정되지 않았습니다.',
    };
  }

  const existing = getAccountByGoogleSub(info.sub);

  if (existing && existing.id !== currentAccountId) {
    // 이미 이 구글로 만든 계정이 있다 — 그쪽으로 로그인한다
    touchAccount(existing.id);
    return { ok: true, account: existing, token: issueToken(existing.id), switched: true };
  }

  if (!linkGoogle(currentAccountId, info.sub, info.email ?? null)) {
    return { ok: false, reason: '이미 다른 계정에 연결된 구글 계정입니다.' };
  }

  const account = getAccount(currentAccountId);
  if (!account) return { ok: false, reason: '계정을 찾을 수 없습니다.' };
  return { ok: true, account, token: issueToken(account.id), switched: false };
}
