import * as THREE from 'three';

/**
 * 피격 표시 — 맞은 캐릭터가 잠깐 하얗게 번쩍인다.
 *
 * 예전에는 맞은 자리에 섬광 덩어리를 띄웠는데, 난전에서 화면이 번쩍이는 것에
 * 비해 **누가 맞았는지는 오히려 안 보였다.** 몸 자체를 물들이면 시선이
 * 그 캐릭터로 간다.
 *
 * 재질을 새로 만들지 않고 **가지고 있던 것을 잠깐 바꿔치웠다가 되돌린다.**
 * 모델마다 메시가 열몇 개씩이라, 맞을 때마다 복제하면 난전에서 그것만으로
 * 프레임이 튄다.
 */

/** 번쩍이는 시간 (초). 길면 하얀 인형이 걸어다니는 것으로 보인다 */
const FLASH_SEC = 0.09;

/**
 * 모두가 함께 쓰는 흰 재질.
 *
 * 조명을 받지 않는다 — 어두운 사냥터에서도 똑같이 하얘야 "맞았다"로 읽힌다.
 * `SkinnedMesh` 에도 그대로 쓸 수 있다 (스키닝은 메시 종류를 보고 붙는다).
 */
const WHITE = new THREE.MeshBasicMaterial({ color: 0xffffff, fog: false });

interface Saved {
  mesh: THREE.Mesh;
  material: THREE.Material | THREE.Material[];
}

export class HitFlash {
  private readonly root: THREE.Object3D;
  private readonly saved: Saved[] = [];
  private left = 0;

  constructor(root: THREE.Object3D) {
    this.root = root;
  }

  /** 한 대 맞았다 */
  flash(): void {
    // 이미 번쩍이는 중이면 다시 담지 않는다 —
    // 흰 재질을 "원래 것"으로 저장해 버리면 영영 하얗게 남는다.
    if (this.left <= 0) this.capture();
    this.left = FLASH_SEC;
  }

  private capture(): void {
    this.saved.length = 0;
    this.root.traverse((o) => {
      const mesh = o as THREE.Mesh;
      if (!mesh.isMesh || !mesh.material) return;
      this.saved.push({ mesh, material: mesh.material });
      mesh.material = Array.isArray(mesh.material) ? mesh.material.map(() => WHITE) : WHITE;
    });
  }

  private restore(): void {
    for (const s of this.saved) s.mesh.material = s.material;
    this.saved.length = 0;
  }

  /** 리그의 update 안에서 부른다 */
  update(dt: number): void {
    if (this.left <= 0) return;
    this.left -= dt;
    if (this.left <= 0) this.restore();
  }

  /** 리그를 버릴 때 — 흰 재질을 남긴 채 사라지지 않도록 */
  dispose(): void {
    if (this.left > 0) this.restore();
    this.left = 0;
  }
}
