import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

/**
 * 여러 지오메트리를 하나로 합쳐 드로우콜을 줄인다.
 * BoxGeometry는 인덱스가 있고 ExtrudeGeometry/IcosahedronGeometry는 없어서
 * 그냥 섞어 넘기면 mergeGeometries가 실패한다. 먼저 non-indexed로 통일한다.
 */
export function mergeAll(geometries: THREE.BufferGeometry[]): THREE.BufferGeometry {
  const normalized = geometries.map((g) => (g.index ? g.toNonIndexed() : g));
  const merged = mergeGeometries(normalized, false);
  if (!merged) throw new Error('mergeAll: 병합 실패 — 어트리뷰트 구성이 다른 지오메트리가 섞여 있다');
  return merged;
}
