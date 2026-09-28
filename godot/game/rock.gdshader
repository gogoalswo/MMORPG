// 바위 — 월드 좌표 노이즈로 얼룩과 금을 긋고, 위를 보는 면에 이끼를 얹는다.
// 텍스처 없이 칠해서 어느 크기로 늘려도 무늬가 같은 굵기다.
// 이유는 docs/features/world-zones.md 의 "덤불숲" 절에 있다.

shader_type spatial;

uniform vec3 rock_light : source_color = vec3(0.47, 0.45, 0.40);
uniform vec3 rock_dark : source_color = vec3(0.25, 0.24, 0.22);
uniform vec3 moss_color : source_color = vec3(0.25, 0.33, 0.14);
// 이끼가 덮는 양 (위를 보는 면 기준)
uniform float moss = 0.45;

varying vec3 wpos;
varying vec3 wnorm;
varying float local_y;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_y = VERTEX.y;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float n = fbm(wpos * 2.2);
	vec3 c = mix(rock_dark, rock_light, smoothstep(0.3, 0.7, n));
	// 금 — 가는 띠
	float crack = abs(fbm(wpos * 4.5 + 11.0) - 0.5);
	c *= mix(0.45, 1.0, smoothstep(0.0, 0.035, crack));
	// 이끼 — 위를 보는 면, 가장자리는 노이즈로 흩뜨림
	float m = smoothstep(0.55, 0.85, wnorm.y + (fbm(wpos * 1.6 + 5.0) - 0.5) * 0.9) * moss;
	c = mix(c, moss_color * mix(0.7, 1.25, n), m);
	// 밑동은 어둡게 — 땅에 앉은 느낌
	c *= mix(0.4, 1.0, smoothstep(-0.12, 0.25, local_y));
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
