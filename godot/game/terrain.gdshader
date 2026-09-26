// 지형 — 바닥 네 장을 섞기 그림(splat)대로 섞는다. 한 장씩의 처리(대비·필터·
// 노멀 세기)는 ground.gdshader 와 같다. 이유는 docs/features/world-zones.md 의
// "바닥" 절과 "지형" 절에 있다.
//
// 층: 0 풀(나머지를 채운다) · 1 돌판(R) · 2 자갈(G) · 3 흙(B).
// UV 는 월드 미터 그대로 들어온다 — 층마다 제 타일 크기로 나눈다.

shader_type spatial;

uniform sampler2D splat : filter_linear, repeat_disable;
uniform float splat_half = 40.0;

uniform sampler2D albedo0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal0 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal3 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

// 층마다: 타일 크기(m) · 평균색(선형) · 틴트(반사율 배율 포함) · 러프니스
uniform vec4 tile = vec4(5.0);
uniform vec3 mean0 = vec3(0.5);
uniform vec3 mean1 = vec3(0.5);
uniform vec3 mean2 = vec3(0.5);
uniform vec3 mean3 = vec3(0.5);
uniform vec3 tint0 = vec3(1.0);
uniform vec3 tint1 = vec3(1.0);
uniform vec3 tint2 = vec3(1.0);
uniform vec3 tint3 = vec3(1.0);
uniform vec4 rough = vec4(0.9);

uniform float contrast = 1.0;
uniform float normal_depth = 1.0;
// 이만큼 기운 비탈(법선 y)부터 풀이 벗겨져 흙이 드러난다
uniform vec2 slope_dirt = vec2(0.92, 0.8);

varying vec3 up_normal;

void vertex() {
	// 지형은 원점에 회전 없이 놓이므로 모델 법선 = 월드 법선
	up_normal = NORMAL;
}

vec3 layer(sampler2D tex, vec2 uv, vec3 mean, vec3 tint) {
	vec3 c = texture(tex, uv).rgb;
	c = mean * pow(max(c, vec3(1e-4)) / mean, vec3(contrast));
	return c * tint;
}

void fragment() {
	vec3 s = texture(splat, (UV + splat_half) / (2.0 * splat_half)).rgb;
	float w1 = s.r;
	float w2 = s.g;
	float w3 = s.b;
	float w0 = max(0.0, 1.0 - w1 - w2 - w3);
	// 비탈은 흙으로 — 언덕이 풀 한 장으로 밋밋해지지 않게
	float steep = smoothstep(slope_dirt.x, slope_dirt.y, normalize(up_normal).y);
	w3 += w0 * steep;
	w0 *= 1.0 - steep;

	vec2 uv0 = UV / tile.x;
	vec2 uv1 = UV / tile.y;
	vec2 uv2 = UV / tile.z;
	vec2 uv3 = UV / tile.w;

	ALBEDO = layer(albedo0, uv0, mean0, tint0) * w0
		+ layer(albedo1, uv1, mean1, tint1) * w1
		+ layer(albedo2, uv2, mean2, tint2) * w2
		+ layer(albedo3, uv3, mean3, tint3) * w3;
	NORMAL_MAP = texture(normal0, uv0).rgb * w0
		+ texture(normal1, uv1).rgb * w1
		+ texture(normal2, uv2).rgb * w2
		+ texture(normal3, uv3).rgb * w3;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = dot(rough, vec4(w0, w1, w2, w3));
	METALLIC = 0.0;
}
