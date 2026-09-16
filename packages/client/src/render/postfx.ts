import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/examples/jsm/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { SMAAPass } from 'three/examples/jsm/postprocessing/SMAAPass.js';

/**
 * 후처리 파이프라인.
 *
 * 실사 인상에서 가장 큰 몫은 앰비언트 오클루전이다. 물체가 맞닿는 곳
 * (풀 밑동, 벽과 바닥, 캐릭터 발밑)이 어두워져야 물체가 바닥에 "붙어" 보인다.
 * 없으면 전부 공중에 떠 있는 것처럼 보이고, 그게 찰흙 느낌의 큰 원인이다.
 *
 * GTAO 는 비싸다. 사양이 낮으면 P 키로 끌 수 있게 해뒀다.
 */
export class PostFX {
  private readonly composer: EffectComposer;
  private readonly gtao: GTAOPass;
  enabled = true;

  constructor(
    private readonly renderer: THREE.WebGLRenderer,
    scene: THREE.Scene,
    private readonly camera: THREE.Camera,
    width: number,
    height: number
  ) {
    this.composer = new EffectComposer(renderer);
    this.composer.addPass(new RenderPass(scene, camera));

    this.gtao = new GTAOPass(scene, camera, width, height);
    this.gtao.output = GTAOPass.OUTPUT.Default;
    // 반경이 크면 넓은 지면까지 어두워져 지저분해진다. 접촉부만 잡는다.
    this.gtao.updateGtaoMaterial({
      radius: 0.5,
      distanceExponent: 1.2,
      thickness: 1.0,
      scale: 1.1,
      samples: 12,
      screenSpaceRadius: false,
    });
    this.composer.addPass(this.gtao);

    /**
     * 빛나는 효과는 가림(음영) 계산에서 뺀다 ★
     *
     * GTAO 는 표면 방향·깊이를 얻으려고 장면을 한 번 더 그리는데, 이때 모든 물체를 같은
     * 재질로 덮어 그린다. 스프라이트는 여기서 화면을 향해 돌지 않고 **서 있는 판자**로 그려지고,
     * 그 판자 둘레가 짙게 가려진 것으로 계산돼 까만 네모가 됐다 (2026-09-12 발 연타).
     * three 는 점·선만 빼 주므로, `userData.noAO` 가 붙은 물체(와 그 자식)도 같이 숨긴다.
     * three 의 내부 함수(`_overrideVisibility`)에 기대므로 three 를 올리면 이게 그대로인지 볼 것.
     */
    const pass = this.gtao as unknown as {
      _overrideVisibility(): void;
      _visibilityCache: THREE.Object3D[];
    };
    const hidePointsAndLines = pass._overrideVisibility.bind(this.gtao);
    pass._overrideVisibility = () => {
      hidePointsAndLines();
      scene.traverse((object) => {
        if (object.userData.noAO && object.visible) {
          object.visible = false;
          pass._visibilityCache.push(object); // 끝나면 three 가 다시 보이게 돌려놓는다
        }
      });
    };

    // 블룸은 아주 약하게. 세게 넣으면 게임이 뿌옇고 싸구려로 보인다.
    const bloom = new UnrealBloomPass(new THREE.Vector2(width, height), 0.14, 0.6, 0.92);
    this.composer.addPass(bloom);

    // OutputPass 가 톤매핑과 sRGB 변환을 담당한다
    this.composer.addPass(new OutputPass());
    this.composer.addPass(new SMAAPass());

    this.setSize(width, height);
  }

  setSize(width: number, height: number): void {
    // 창이 최소화되거나 패널이 숨겨지면 0 이 들어온다.
    // 그대로 넘기면 렌더타깃 첨부물이 0 크기가 되어 매 프레임 GL 오류가 난다.
    const w = Math.max(1, Math.floor(width));
    const h = Math.max(1, Math.floor(height));
    this.composer.setSize(w, h);
    this.gtao.setSize(w, h);
  }

  render(scene: THREE.Scene): void {
    if (this.enabled) this.composer.render();
    else this.renderer.render(scene, this.camera);
  }

  toggle(): boolean {
    this.enabled = !this.enabled;
    return this.enabled;
  }
}
