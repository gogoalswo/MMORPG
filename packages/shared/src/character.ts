/**
 * 캐릭터 규칙. 클라이언트와 서버가 함께 쓴다.
 *
 * 클라이언트는 입력 즉시 걸러 사용자에게 빨리 알려주고,
 * 서버는 **다시 검증한다** — 클라이언트를 우회해서 보낼 수 있기 때문이다.
 */

export const NAME_MIN = 2;
export const NAME_MAX = 12;

/** 한글·영문·숫자만. 공백과 특수문자는 귓속말 명령과 충돌한다 */
const NAME_PATTERN = /^[가-힣a-zA-Z0-9]+$/;

export type NameError = 'empty' | 'tooShort' | 'tooLong' | 'charset';

export function validateCharacterName(raw: string): NameError | null {
  const name = raw.trim();
  if (name.length === 0) return 'empty';
  if (name.length < NAME_MIN) return 'tooShort';
  if (name.length > NAME_MAX) return 'tooLong';
  if (!NAME_PATTERN.test(name)) return 'charset';
  return null;
}

export function nameErrorMessage(error: NameError): string {
  switch (error) {
    case 'empty':
      return '이름을 입력하세요.';
    case 'tooShort':
      return `${NAME_MIN}글자 이상이어야 합니다.`;
    case 'tooLong':
      return `${NAME_MAX}글자까지 가능합니다.`;
    case 'charset':
      return '한글, 영문, 숫자만 쓸 수 있습니다.';
  }
}

export const JOB_IDS = ['knight', 'mage', 'archer'] as const;
export type JobId = (typeof JOB_IDS)[number];

export function isJobId(value: unknown): value is JobId {
  return typeof value === 'string' && (JOB_IDS as readonly string[]).includes(value);
}
