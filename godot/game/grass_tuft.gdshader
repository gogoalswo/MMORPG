// 풀포기 — 엇갈려 세운 판 위에 잎 몇 가닥을 오려 낸다 (텍스처 없이).
// 법선은 메시에서 위(+y)로 들어온다 — 바닥과 같은 빛을 받아 튀지 않는다.
// 이유는 docs/features/world-zones.md 의 "덤불숲" 절에 있다.

shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.18, 0.23, 0.15);
uniform vec3 tip_color : source_color = vec3(0.29, 0.35, 0.21);
// 끝 색을 이만큼 밝힌다 — 볕 받는 잎 끝
uniform float tip_lift = 1.0;
// 바람에 흔들리는 폭(판 너비 기준)
uniform float sway = 0.05;

varying float seed;
varying float hue;
varying float shade;

void vertex() {
	seed = INSTANCE_CUSTOM.g;
	hue = INSTANCE_CUSTOM.r;
	shade = INSTANCE_CUSTOM.b;
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = sin(TIME * 1.4 + world.x * 0.6 + world.z * 0.45) + 0.4 * sin(TIME * 2.3 + world.z);
	VERTEX.xz += vec2(w, w * 0.6) * sway * UV.y * UV.y;
}

float h1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	float a = 0.0;
	float along = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i) + seed * 31.0;
		float x0 = 0.18 + 0.64 * h1(fi + 1.3);
		float top = 0.45 + 0.55 * h1(fi + 7.7);
		float lean = (h1(fi + 3.1) - 0.5) * 0.7;
		float base_w = 0.035 + 0.035 * h1(fi + 5.9);
		float t = UV.y / top;
		if (t < 1.0) {
			float cx = x0 + lean * t * t;
			float half_w = base_w * (1.0 - t);
			if (abs(UV.x - cx) < half_w) {
				a = 1.0;
				along = max(along, t);
			}
		}
	}
	if (a < 0.5) {
		discard;
	}
	vec3 tip = tip_color * tip_lift * mix(0.85, 1.15, hue);
	vec3 c = mix(base_color * 0.55, tip, smoothstep(0.0, 0.9, along));
	// 이동 끝 너머는 숲 그늘 (바닥의 edge_dark 와 같은 곳)
	ALBEDO = c * mix(1.0, 0.4, shade);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
