// 바닥 한 장. 무늬(돌 틈·풀·자갈)가 화면에서 죽지 않게 세 가지를 여기서 한다.
// 왜 StandardMaterial3D 로는 안 되는지와 수치의 근거는
// docs/features/world-zones.md 의 "바닥" 절에 있다.
//
//  1. 아니소트로픽 필터 — 쿼터뷰(43도)라 바닥이 비스듬하다. 밉맵만 쓰면
//     세로로 눌린 만큼을 기준으로 단계가 잡혀서 가로 무늬까지 같이 뭉갠다.
//  2. 대비 — 텍스처 평균색을 축으로 비율을 벌린다(pow). 평균이 그대로라
//     밝기는 안 변하고 무늬만 또렷해진다. 빼기로 벌리면 어두운 쪽이
//     0 에 붙어 돌 틈이 새까만 선이 된다.
//  3. 노멀 세기 — 밝기로 만든 노멀맵이라 기본 1.0 이면 요철이 밋밋하다.

shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform vec3 tint = vec3(1.0);
uniform vec3 mean_color = vec3(0.5);
uniform float contrast = 1.0;
uniform float normal_depth = 1.0;
uniform float rough = 0.9;
uniform vec2 tiling = vec2(1.0);

void fragment() {
	vec2 uv = UV * tiling;
	vec3 c = texture(albedo_tex, uv).rgb;
	// 평균 대비 비율을 지수로 벌린다. c 가 0 이어도 pow(0, k) == 0 이라 안전하다
	c = mean_color * pow(max(c, vec3(1e-4)) / mean_color, vec3(contrast));
	ALBEDO = c * tint;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
