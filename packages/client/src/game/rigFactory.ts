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

let models: Models | null = null;

export function setModels(loaded: Models | null): void {
  models = loaded;
}

export function hasModels(): boolean {
  return models !== null;
}

export function createRig(profile: ClassProfile): CharacterRig {
  if (models && profile.model && models.characters[profile.model]) {
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
