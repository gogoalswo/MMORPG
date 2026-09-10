import type { MonsterKind } from '@mmo/shared';
import type { Models } from '../scene/models';
import { createCharacterRig, type CharacterRig, type ClassProfile } from './characterRig';
import { createMonsterRig, type MonsterRig } from './monsterRig';
import { createModelCharacterRig, createModelMonsterRig } from './modelRig';

/**
 * 리그를 어느 쪽으로 만들지 정하는 곳.
 *
 * 모델(.glb)이 있으면 그걸 쓰고, 없으면 절차적으로 만든 것으로 떨어진다.
 * 절차적 리그를 지우지 않고 남겨둔 이유는 **모델을 못 받아도 게임이 돌아야**
 * 하기 때문이다 — 에셋은 저장소에 커밋하지 않아서, 새로 클론한 사람은
 * scripts/fetch-assets.sh 를 돌리기 전까지 파일이 없다.
 *
 * 모델은 부팅 때 한 번 넘겨받는다. 리그를 만드는 자리가 셋(내 캐릭터, 다른
 * 플레이어, NPC)이라 그때마다 인자로 끌고 다니면 서명이 지저분해진다.
 */

/**
 * 모델 파일로 그릴 사람 모델. ★
 *
 * **여기 없는 모델은 절차적 리그로 그린다.** 직업이 아니라 모델로 정하는 이유는,
 * 모델로 그릴 수 있느냐가 그 파일의 비율에 달려 있기 때문이다.
 *
 * KayKit Adventurers 는 **머리가 큰 3등신** 팩이다. 비율이 파일에 박혀 있어서
 * 코드로는 8등신이 되지 않는다 — 머리 뼈만 줄이면 팔다리가 짧은 난쟁이가 될
 * 뿐이다. 그래서 KayKit 을 쓰는 직업(마법사·궁수)은 절차적 리그로 간다.
 * 그쪽은 처음부터 8등신이다(characterRig 의 HEIGHT/8).
 *
 * `varco_knight` · `varco_mage` 는 VARCO 커스텀 워크플로우로 만든 8등신이라 그대로 쓴다.
 * 대신 **장비가 겉모습에 안 나타난다** — 무기·방패가 몸과 한 덩어리로 구워져
 * 있어서 갈아끼울 메시가 없다(modelRig 의 GEAR_MESHES 참고).
 * 절차적 리그도 마찬가지다(setGear 가 빈 함수다).
 *
 * 짐승은 언제나 모델을 쓴다. 네발짐승은 등신 개념이 없다.
 */
const MODEL_RIGS = new Set<string>(['varco_knight', 'varco_mage', 'varco_archer']);

let models: Models | null = null;

export function setModels(loaded: Models | null): void {
  models = loaded;
}

export function hasModels(): boolean {
  return models !== null;
}

export function createRig(profile: ClassProfile): CharacterRig {
  // 파일을 못 받았으면(models.characters 에 없으면) 조용히 절차적 리그로 떨어진다
  if (models && profile.model && MODEL_RIGS.has(profile.model) && models.characters[profile.model]) {
    return createModelCharacterRig(models, profile);
  }
  return createCharacterRig(profile);
}

export function createMonster(kind: MonsterKind): MonsterRig {
  // 그 짐승 모델이 아직 안 왔으면 null 이 온다 (존 전환 중 먼저 뜬 몬스터 등)
  const rig = models ? createModelMonsterRig(models, kind) : null;
  return rig ?? createMonsterRig(kind);
}

/** 이 존에서 필요한 짐승 모델 이름들 */
export async function ensureBeasts(looks: string[]): Promise<void> {
  await models?.ensureBeasts(looks);
}
