import { NPC_REACH, type NpcDef, type NpcRole } from '@mmo/shared';
import type * as THREE from 'three';

/**
 * NPC 근처에 서면 뜨는 말걸기 버튼.
 *
 * 화면 한가운데 아래에 고정한다 — 3D 위치를 따라다니게 하면 NPC 가 겹쳐 섰을 때
 * 버튼도 겹치고, 폰에서는 손가락에 가린다.
 *
 * 실제 판정(거리)은 서버가 다시 한다. 여기서 재는 건 버튼을 띄울지 정하기 위해서다.
 */
export class NpcPrompt {
  private readonly root: HTMLButtonElement;
  private current: NpcRole | null = null;

  onTalk: ((role: NpcRole) => void) | null = null;

  constructor(parent: HTMLElement) {
    this.root = document.createElement('button');
    this.root.type = 'button';
    this.root.className = 'npc-prompt is-hidden';
    this.root.addEventListener('click', () => {
      if (this.current) this.onTalk?.(this.current);
    });
    parent.appendChild(this.root);

    // F 로도 말을 건다
    window.addEventListener('keydown', (e) => {
      if (e.code !== 'KeyF' || !this.current) return;
      const el = e.target as HTMLElement | null;
      if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) return;
      e.preventDefault();
      this.onTalk?.(this.current);
    });
  }

  clear(): void {
    this.current = null;
    this.root.classList.add('is-hidden');
  }

  /** 매 프레임 — 가장 가까운 대화 가능 NPC 를 찾는다 */
  update(npcs: NpcDef[], position: THREE.Vector3): void {
    let best: NpcDef | null = null;
    let bestDist = NPC_REACH;

    for (const npc of npcs) {
      if (!npc.role) continue;
      const d = Math.hypot(npc.x - position.x, npc.z - position.z);
      if (d <= bestDist) {
        bestDist = d;
        best = npc;
      }
    }

    if (!best) {
      if (this.current !== null) this.clear();
      return;
    }

    if (this.current === best.role && !this.root.classList.contains('is-hidden')) return;

    this.current = best.role!;
    this.root.innerHTML =
      `<span class="npc-prompt-key">F</span>` +
      `<span class="npc-prompt-text">${best.name}<small>${best.title ?? ''}</small></span>`;
    this.root.classList.remove('is-hidden');
  }
}
