class_name Armor
extends RefCounted

## 갑옷·투구·신발을 **몸에 입힌다** — 장비 칸의 등급이 바뀌면 그 부위의 스킨이 바뀐다.
##
## 뼈에 딱딱한 도형을 붙이지 않는다. 몸 메시에서 **그 부위의 삼각형만 떼어** 법선 쪽으로
## 조금 부풀린 껍데기를 만들고, 같은 뼈대·같은 스킨에 묶는다 — 그래서 달리고 차는 동안
## 몸과 같이 휘고, 모델을 갈아 끼워도 잰 수치가 없다. 어느 삼각형이 어느 부위인지는
## **뼈 가중치**가 정한다 (`BONES` 에 든 뼈에 0.5 넘게 묶인 정점).
##
## 껍데기 모양은 부위마다 한 번만 짓고(`_shells` 캐시), 등급은 **재질**과 뼈에 붙이는
## **장식**(보석·가시·고리)만 바꾼다. 색은 건틀릿(`Gauntlet`)과 같은 등급 색이다 —
## 붕대 → 가죽 → 은 → 보라 쇠 → 금 → 검은 쇠 → 흰빛.
## → docs/features/characters-and-animation.md "장비 스킨"

## 부위 → 덮는 뼈
const BONES := {
	"armor": ["Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm"],
	"helmet": ["Head"],
	"boots": ["LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"],
}
const SLOTS := ["armor", "helmet", "boots"]
## 그 부위 뼈에 묶인 가중치 합이 이만큼 넘는 정점만 덮는다. 갑옷은 배까지 덮으려고 낮췄다 —
## 배는 몸통 뼈와 골반 뼈에 반반 묶여 있어서 0.5 로는 가슴과 반바지 사이가 비었다
const COVER := {"armor": 0.3, "helmet": 0.5, "boots": 0.5}
## 법선 쪽으로 부풀리는 두께 (모델 단위 — 게임에서 1.85배쯤 커진다. 0.006 ≈ 1.1cm)
const PUSH := {"armor": 0.007, "helmet": 0.009, "boots": 0.007}
## 껍데기를 몇 번 펴나 — 근육·머리카락 굴곡을 죽여 판처럼 보이게 (`_smooth`)
const SMOOTH := {"armor": 8, "helmet": 6, "boots": 6}
## 투구는 얼굴을 덮지 않는다 — 이마 위와 뒤통수만 덮는다. 앞이 +Z 다.
## **모델 축으로 잰 머리 상자에 대한 비율**로 잡는다 (`_head_frame`). 머리 뼈 좌표로 잡으면
## 목이 숙여진 몸(주먹 몸은 목 35°)에서 이마선이 비스듬해져 얼굴을 가로질렀고, 고정 수치(0.058)는
## 머리 뼈 자리가 바뀌자 눈높이에 걸렸다. 이마 = 상자 아래에서 62%, 뒤통수 = 가운데보다 0.02 뒤
const HELMET_BROW_AT := 0.62
const HELMET_BACK_BY := 0.02
## 배를 덮는 허리선 — 골반 뼈 좌표 y. 몸통 쪽(몸통·골반·허벅지 뼈에 90% 넘게 묶인 — 팔·머리는
## 빠진다) 정점 가운데 이보다 위는 갑옷이 덮는다. 아랫배는 **허벅지 뼈**에 주로 묶여 있어서
## 가중치만으로는 가슴과 반바지 사이가 비었다 (골반 위 0.02~0.05 가 그랬다)
const WAIST := 0.025

## 등급 재질 — **아이콘(`icons/<부위>_g<등급>.png`)에 맞춘 색과 무늬** (2026-09-26 요청: "아이콘
## 색상이랑 실제 모델이랑 너무 다르다 · 동일한 모델에 색상만 다른 느낌 — 재질이랑 무늬 다르게,
## 좋은 등급일수록 화려하게"). 무늬는 `SHADER` 의 `style` 이 고른다:
##   1 붕대 감은 회색 천 · 2 크림 가죽 판 + 올리브 틈 + 놋쇠 리벳 · 3 푸른 은빛 판금 마디 ·
##   4 보라 판금 + 빛나는 새김선 · 5 주황 금 용비늘 · 6 검은 돌 + 맥박 치는 용암 금 ·
##   7 진주빛(보는 각에 따라 무지개) + 금빛 무늬
## base 바탕 · alt 둘째 색 · line 홈·틈 · glow 빛(새김·금·무늬) · energy 빛 세기 ·
## metal · rough · rim 테두리 빛(보는 각이 비스듬할수록)
const LOOK := {
	1: {"base": Color("#8e8e8b"), "alt": Color("#b4b4af"), "line": Color("#4a4a48"), "glow": Color.BLACK,
		"energy": 0.0, "metal": 0.0, "rough": 0.95, "rim": 0.0},
	2: {"base": Color("#ddd3a4"), "alt": Color("#7d8a4c"), "line": Color("#4b4a2a"), "glow": Color("#d6ad4e"),
		"energy": 0.0, "metal": 0.0, "rough": 0.7, "rim": 0.0},
	3: {"base": Color("#c3d4e6"), "alt": Color("#e9f1f8"), "line": Color("#5f7389"), "glow": Color.BLACK,
		"energy": 0.0, "metal": 0.85, "rough": 0.28, "rim": 0.15},
	4: {"base": Color("#5d3796"), "alt": Color("#a888dc"), "line": Color("#2a1745"), "glow": Color("#c07cff"),
		"energy": 2.2, "metal": 0.7, "rough": 0.3, "rim": 0.5},
	5: {"base": Color("#f0a22e"), "alt": Color("#ffd36a"), "line": Color("#7a3812"), "glow": Color("#ffb347"),
		"energy": 0.9, "metal": 0.85, "rough": 0.3, "rim": 0.7},
	6: {"base": Color("#221c1c"), "alt": Color("#3a302e"), "line": Color("#0c0808"), "glow": Color("#ff3a14"),
		"energy": 3.2, "metal": 0.4, "rough": 0.7, "rim": 0.8},
	7: {"base": Color("#f4f1ea"), "alt": Color("#ffffff"), "line": Color("#d49a2a"), "glow": Color("#ffd27a"),
		"energy": 1.6, "metal": 0.35, "rough": 0.25, "rim": 1.0},
}
## 장식 색 — 테두리·보석 (아이콘의 테두리 색)
const TRIM := {
	1: Color("#6f6f6c"), 2: Color("#c8a24a"), 3: Color("#8fa6bd"), 4: Color("#c9b0f0"),
	5: Color("#8a3a18"), 6: Color("#ff3a1a"), 7: Color("#ffd27a"),
}

## 껍데기 셰이더. 무늬는 **바인드 자세 좌표**(정점에 구워 둔 `UV`·`UV2`·`COLOR`)로 그린다 —
## 스키닝된 자리로 그리면 달릴 때 무늬가 몸 위를 흘러간다. 면 방향에 따라 세 평면에서 뽑아 섞는다
const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform int style = 1;
uniform vec3 base : source_color;
uniform vec3 alt : source_color;
uniform vec3 line : source_color;
uniform vec3 glow : source_color;
uniform float energy = 0.0;
uniform float metal = 0.0;
uniform float rough = 0.8;
uniform float rim = 0.0;
varying vec3 bp;
varying vec3 bn;

void vertex() {
	bp = vec3(UV.x, UV.y, UV2.x);
	bn = COLOR.rgb * 2.0 - 1.0;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
// 보로노이 가장자리까지 거리 — 용암 금
float crack(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); float d1 = 8.0; float d2 = 8.0;
	for (int y = -1; y <= 1; y++) { for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = vec2(hash(i + g), hash(i + g + 17.0));
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	} }
	return d2 - d1;
}
// 비늘 — 줄마다 반 칸 어긋난 둥근 비늘, **윗줄이 아랫줄을 덮는다** (물고기 비늘).
// 0 = 비늘 뿌리, 1 = 가장자리. 한 줄짜리 원으로 그렸더니 가장자리가 굵어 호랑이 줄무늬로 보였다
float scale_of(vec2 p) {
	p.x += 0.5 * mod(floor(p.y), 2.0);
	vec2 f = fract(p);
	float up = min(length(f - vec2(0.0, 1.0)), length(f - vec2(1.0, 1.0)));
	float here = length(f - vec2(0.5, 0.0));
	return (up < 0.72 ? up : here) / 0.72;
}
vec3 tri_w() { vec3 w = pow(abs(bn), vec3(4.0)); return w / (w.x + w.y + w.z + 1e-4); }

void fragment() {
	vec3 w = tri_w();
	vec3 col = base;
	vec3 emit = vec3(0.0);
	float m = metal;
	float r = rough;
	if (style == 1) {
		// 붕대 — 비스듬히 감긴 띠와 띠 사이 어두운 틈, 천 결
		float b = fract(bp.y * 52.0 + (bp.x + bp.z) * 9.0);
		float gap = smoothstep(0.0, 0.1, b) * smoothstep(1.0, 0.86, b);
		col = mix(line, mix(base, alt, smoothstep(0.3, 0.7, b)), gap);
		col *= 0.88 + 0.12 * noise(vec2(bp.x + bp.z, bp.y) * 700.0);
	} else if (style == 2) {
		// 가죽 — 크림 판과 올리브 틈, 판 위 끝 바늘땀, 판 아래 끝 놋쇠 리벳
		float band = fract(bp.y * 15.0);
		float plate = step(band, 0.72);
		col = mix(alt, base, plate) * (0.9 + 0.1 * noise(vec2(bp.x + bp.z, bp.y) * 300.0));
		float dash = step(0.5, fract((bp.x + bp.z) * 140.0));
		col = mix(col, line, (1.0 - smoothstep(0.0, 0.025, abs(band - 0.66))) * dash * 0.8);
		float rv = 1.0 - smoothstep(0.1, 0.16, length(vec2(fract((bp.x + bp.z) * 24.0) - 0.5, (band - 0.08) * 2.4)));
		col = mix(col, glow, rv); m = mix(m, 0.45, rv); r = mix(r, 0.35, rv);
	} else if (style == 3 || style == 4) {
		// 판금 — 가로 마디마다 홈, 마디 위쪽이 밝게 꺾이고 결이 얇게 긁혔다
		float band = fract(bp.y * 13.0);
		float groove = smoothstep(0.0, 0.07, band) * smoothstep(1.0, 0.95, band);
		col = mix(line, mix(alt, base, smoothstep(0.0, 0.5, band)), groove);
		col *= 0.94 + 0.06 * noise(vec2((bp.x + bp.z) * 900.0, bp.y * 30.0));
		if (style == 4) {
			// 새김선 — 판 위에 마름모 격자로 새기고 보랏빛으로 빛난다
			float a = abs(fract((bp.x + bp.z) * 16.0 + bp.y * 16.0) - 0.5);
			float c = abs(fract((bp.x + bp.z) * 16.0 - bp.y * 16.0) - 0.5);
			float lines = (1.0 - smoothstep(0.0, 0.035, min(a, c))) * groove;
			col = mix(col, glow, lines * 0.6);
			emit += glow * lines * energy * (0.8 + 0.2 * sin(TIME * 2.0));
		}
	} else if (style == 5) {
		// 용비늘 — 세 평면에서 뽑아 섞는다. 가운데가 밝고 가장자리가 붉게 어둡다
		float s = scale_of(bp.zy * 34.0) * w.x + scale_of(bp.xz * 34.0) * w.y + scale_of(bp.xy * 34.0) * w.z;
		col = mix(alt, base, smoothstep(0.0, 0.85, s));
		col = mix(col, line, smoothstep(0.86, 1.0, s) * 0.85);
		emit += glow * (1.0 - smoothstep(0.0, 0.35, s)) * energy * (0.6 + 0.4 * sin(TIME * 1.5 + bp.y * 40.0));
	} else if (style == 6) {
		// 용암 금 — 검은 돌의 갈라진 틈이 맥박 치며 빛난다
		float c = crack(bp.zy * 26.0) * w.x + crack(bp.xz * 26.0) * w.y + crack(bp.xy * 26.0) * w.z;
		float lava = 1.0 - smoothstep(0.0, 0.07, c);
		col = mix(base, alt, noise(vec2(bp.x + bp.z, bp.y) * 120.0));
		float pulse = 0.65 + 0.35 * sin(TIME * 3.0 + bp.y * 50.0);
		col = mix(col, glow, lava);
		emit += glow * lava * energy * pulse;
		r = mix(r, 0.4, lava);
	} else {
		// 진주 — 보는 각에 따라 무지개빛이 돌고, 금빛 덩굴 무늬가 빛난다
		float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		vec3 iris = 0.5 + 0.5 * cos(6.2831 * (f * 1.2 + vec3(0.0, 0.33, 0.67)) + TIME * 0.6);
		col = mix(base, iris, 0.22 * f + 0.06);
		float vine = abs(sin((bp.x + bp.z) * 45.0 + sin(bp.y * 40.0) * 2.5));
		float gold = 1.0 - smoothstep(0.05, 0.3, vine);
		col = mix(col, line, gold * 0.9);
		emit += glow * gold * energy;
	}
	// 테두리 빛 — 비스듬히 보이는 가장자리일수록 등급 빛이 돈다
	emit += glow * rim * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col;
	METALLIC = m;
	ROUGHNESS = r;
	EMISSION = emit;
}
"""

## 몸 메시 → {부위 → ArrayMesh}. 등급을 바꿀 때마다 다시 떼지 않는다
static var _shells := {}
## 몸 메시 → {뼈 이름 → [뼈 좌표 상자 AABB, 앞쪽 방향]}. 장식 자리를 잡는다
static var _boxes := {}
static var _mats := {}


## 부위 하나를 등급으로 입힌다. 0 이면 벗긴다(맨몸). 몸 메시·뼈가 없으면 조용히 넘어간다
static func wear(rig: Node3D, slot: String, grade: int) -> void:
	var body := _body(rig)
	if body == null:
		return
	var shell := body.get_parent().get_node_or_null("Gear_" + slot) as MeshInstance3D
	if shell == null:
		var mesh := shell_mesh(body, slot)
		if mesh == null:
			return
		shell = MeshInstance3D.new()
		shell.name = "Gear_" + slot
		shell.mesh = mesh
		shell.skin = body.skin
		shell.cast_shadow = body.cast_shadow
		body.get_parent().add_child(shell)
		# 몸과 형제라 몸이 뼈대를 가리키는 상대 경로가 그대로 맞는다
		shell.skeleton = body.skeleton
	shell.visible = grade > 0
	if grade > 0:
		shell.material_override = material(grade)
	_decorate(rig, body, slot, grade)
	# 오로라 — 4등급부터, 고도 이펙트로 뼈 소켓에 붙인다 (`GearAura`)
	GearAura.wear(rig, body, slot, grade)


## 등급 재질 — 무늬 셰이더, 4등급부터 오로라 한 겹(`next_pass`). 등급마다 한 벌을 나눠 쓴다
static func material(grade: int) -> ShaderMaterial:
	grade = clampi(grade, 1, 7)
	if _mats.has(grade):
		return _mats[grade]
	if not _mats.has("shader"):
		var shader := Shader.new()
		shader.code = SHADER
		_mats["shader"] = shader
	var look: Dictionary = LOOK[grade]
	var mat := ShaderMaterial.new()
	mat.shader = _mats["shader"]
	mat.set_shader_parameter("style", grade)
	for key in ["base", "alt", "line", "glow", "energy", "metal", "rough", "rim"]:
		mat.set_shader_parameter(key, look[key])
	_mats[grade] = mat
	return mat


## 장식(어깨받이·무릎받이·뿔)의 재질 — 무늬 없이 그 등급 바탕색
static func _decor_mat(grade: int) -> StandardMaterial3D:
	var look: Dictionary = LOOK[clampi(grade, 1, 7)]
	var key := "decor/%d" % grade
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = look.base
	mat.metallic = look.metal
	mat.roughness = look.rough
	if float(look.rim) > 0.0:
		mat.rim_enabled = true
		mat.rim = look.rim
	_mats[key] = mat
	return mat


## 부위 껍데기 — 몸 메시에서 그 부위 삼각형을 떼어 부풀린 것. 몸이 스킨이 아니면 null
static func shell_mesh(body: MeshInstance3D, slot: String) -> ArrayMesh:
	var key := body.mesh.get_instance_id()
	if _shells.has(key) and _shells[key].has(slot):
		return _shells[key][slot]
	var mesh := _cut(body, slot)
	if not _shells.has(key):
		_shells[key] = {}
	_shells[key][slot] = mesh
	return mesh


static func _cut(body: MeshInstance3D, slot: String) -> ArrayMesh:
	var skin := body.skin
	var source := body.mesh as ArrayMesh
	if skin == null or source == null:
		return null
	# 스킨 인덱스 → 이 부위 뼈인가
	var wanted: Array = BONES[slot]
	var bind_in := PackedByteArray()
	bind_in.resize(skin.get_bind_count())
	var head := -1
	var hips := -1
	var lower := PackedByteArray()
	lower.resize(skin.get_bind_count())
	for i in skin.get_bind_count():
		var bone_name := str(skin.get_bind_name(i))
		bind_in[i] = 1 if bone_name in wanted else 0
		if bone_name == "Head":
			head = i
		if bone_name == "Hips":
			hips = i
		if bone_name in ["Hips", "LeftUpLeg", "RightUpLeg"]:
			lower[i] = 1
	var head_frame := _head_frame(body)
	var head_box: AABB = head_frame[1]
	var head_at: Vector3 = head_frame[2]
	var brow := head_box.position.y + head_box.size.y * HELMET_BROW_AT
	var back := head_box.get_center().z - HELMET_BACK_BY

	var out := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights.is_empty():
			continue
		var per := weights.size() / pos.size()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(pos.size())
			for i in pos.size():
				indices[i] = i
		# 정점마다 — 이 부위 뼈에 묶인 가중치 합이 절반을 넘는가
		var inside := PackedByteArray()
		inside.resize(pos.size())
		for v in pos.size():
			var sum := 0.0
			var on_head := 0.0
			var on_hips := 0.0
			for k in per:
				var w := weights[v * per + k]
				var b := int(bones[v * per + k])
				if bind_in[b]:
					sum += w
				if b == head:
					on_head += w
				if lower[b]:
					on_hips += w
			var yes := sum > float(COVER[slot])
			if not yes and slot == "armor" and hips >= 0 and sum + on_hips > 0.9:
				# 배 — 허리선 위 몸통이면 덮는다
				yes = (skin.get_bind_pose(hips) * pos[v]).y > WAIST
			if yes and slot == "helmet" and on_head > 0.5:
				# 머리 뼈 좌표로 옮겨 얼굴을 걸러 낸다
				var local := pos[v] - head_at
				yes = local.y > brow or local.z < back
			inside[v] = 1 if yes else 0

		# 세 정점이 다 들어온 삼각형만 — 새 번호를 매겨 옮긴다
		var remap := PackedInt32Array()
		remap.resize(pos.size())
		remap.fill(-1)
		var new_pos := PackedVector3Array()
		var new_normal := PackedVector3Array()
		var new_bones := PackedInt32Array()
		var new_weights := PackedFloat32Array()
		var new_index := PackedInt32Array()
		var push: float = PUSH[slot]
		for t in range(0, indices.size() - 2, 3):
			var a := indices[t]
			var b := indices[t + 1]
			var c := indices[t + 2]
			if not (inside[a] and inside[b] and inside[c]):
				continue
			for v in [a, b, c]:
				if remap[v] < 0:
					remap[v] = new_pos.size()
					new_pos.append(pos[v])
					for k in per:
						new_bones.append(int(bones[v * per + k]))
						new_weights.append(weights[v * per + k])
				new_index.append(remap[v])
		if new_index.is_empty():
			continue
		# 근육 굴곡을 죽여 판처럼 — 편 다음 새 법선 쪽으로 부풀린다
		var smoothed := _smooth(new_pos, new_index, SMOOTH[slot])
		new_pos = smoothed[0]
		new_normal = smoothed[1]
		# 무늬를 붙일 바인드 자세 좌표 — 자리는 UV(x, y)·UV2(z), 법선은 정점 색에 굽는다
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var tint := PackedColorArray()
		uv.resize(new_pos.size())
		uv2.resize(new_pos.size())
		tint.resize(new_pos.size())
		for v in new_pos.size():
			uv[v] = Vector2(new_pos[v].x, new_pos[v].y)
			uv2[v] = Vector2(new_pos[v].z, 0.0)
			var n := new_normal[v] * 0.5 + Vector3(0.5, 0.5, 0.5)
			tint[v] = Color(n.x, n.y, n.z)
			new_pos[v] += new_normal[v] * push
		var cut := []
		cut.resize(Mesh.ARRAY_MAX)
		cut[Mesh.ARRAY_VERTEX] = new_pos
		cut[Mesh.ARRAY_NORMAL] = new_normal
		cut[Mesh.ARRAY_TEX_UV] = uv
		cut[Mesh.ARRAY_TEX_UV2] = uv2
		cut[Mesh.ARRAY_COLOR] = tint
		cut[Mesh.ARRAY_BONES] = new_bones
		cut[Mesh.ARRAY_WEIGHTS] = new_weights
		cut[Mesh.ARRAY_INDEX] = new_index
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cut, [], {}, flags)
	return out if out.get_surface_count() > 0 else null


## 껍데기를 편다 (Taubin — 줄었다 늘었다 하며 부피를 지킨다). 몸 메시는 UV 이음새마다
## 정점이 갈라져 있어서, **같은 자리 정점을 한 점으로 묶어** 편다 — 안 그러면 이음새가 벌어진다.
## 가장자리(한 삼각형에만 쓰인 변) 점은 그대로 둔다. 돌려주는 것: [자리, 법선]
static func _smooth(pos: PackedVector3Array, index: PackedInt32Array, rounds: int) -> Array:
	# 같은 자리 → 한 점
	var ids := {}
	var point := PackedInt32Array()
	point.resize(pos.size())
	var at := PackedVector3Array()
	for v in pos.size():
		var key := Vector3i((pos[v] * 100000.0).round())
		if not ids.has(key):
			ids[key] = at.size()
			at.append(pos[v])
		point[v] = ids[key]
	# 이웃과 가장자리
	var near := []
	near.resize(at.size())
	for p in at.size():
		near[p] = {}
	var edges := {}
	for t in range(0, index.size() - 2, 3):
		for e in 3:
			var a := point[index[t + e]]
			var b := point[index[t + (e + 1) % 3]]
			near[a][b] = true
			near[b][a] = true
			var key := Vector2i(mini(a, b), maxi(a, b))
			edges[key] = int(edges.get(key, 0)) + 1
	var rim := PackedByteArray()
	rim.resize(at.size())
	for key in edges:
		if edges[key] == 1:
			rim[key.x] = 1
			rim[key.y] = 1
	for round in rounds:
		for step in [0.5, -0.53]:
			var moved := at.duplicate()
			for p in at.size():
				if rim[p] or near[p].is_empty():
					continue
				var mean := Vector3.ZERO
				for q in near[p]:
					mean += at[q]
				mean /= near[p].size()
				moved[p] = at[p] + (mean - at[p]) * step
			at = moved
	# 면 법선을 모아 점 법선으로
	var normal := PackedVector3Array()
	normal.resize(at.size())
	for t in range(0, index.size() - 2, 3):
		var a := point[index[t]]
		var b := point[index[t + 1]]
		var c := point[index[t + 2]]
		# 고도는 시계 방향 감김이 앞면이라 (c-a)×(b-a) 가 바깥이다
		var face := (at[c] - at[a]).cross(at[b] - at[a])
		normal[a] += face
		normal[b] += face
		normal[c] += face
	var out_pos := PackedVector3Array()
	var out_normal := PackedVector3Array()
	out_pos.resize(pos.size())
	out_normal.resize(pos.size())
	for v in pos.size():
		out_pos[v] = at[point[v]]
		out_normal[v] = normal[point[v]].normalized()
	return [out_pos, out_normal]


# ─── 장식 ─────────────────────────────────────────────────
# 껍데기만으로는 은 갑옷과 은빛 페인트가 구별이 안 된다. 등급이 오를수록 뼈에 붙는
# 조각이 는다 — 어깨받이(3~) · 가슴·이마 보석(4~) · 가시(5~6) · 떠 있는 고리(7).
# 자리는 **그 뼈에 묶인 정점의 상자**(`_box`)와 **앞쪽**(모델 +Z 를 뼈 좌표로 옮긴 것)으로 잡는다.

static func _decorate(rig: Node3D, body: MeshInstance3D, slot: String, grade: int) -> void:
	var sockets := _decor_bones(slot)
	for bone in sockets:
		var socket: BoneAttachment3D = rig.fist_socket(bone)
		if socket == null:
			continue
		var old := socket.get_node_or_null("GearDecor_" + slot)
		if old != null:
			socket.remove_child(old)
			old.queue_free()
	if grade < 3:
		return
	var trim := _plain(TRIM[grade], 0.9, 0.3, grade >= 4)
	var base := _decor_mat(grade)
	match slot:
		"armor":
			for bone in ["LeftArm", "RightArm"]:
				var holder := _holder(rig, bone, slot)
				if holder == null:
					continue
				# 어깨받이 — 위팔 뿌리를 덮는 반구. 크기는 위팔 굵기에서
				var box := _box(body, bone)
				var r := maxf(box[0].size.x, box[0].size.z) * 0.62
				var pad := _part(holder, _sphere(r), base, Vector3(0, r * 0.35, 0))
				pad.scale = Vector3(1.0, 0.7, 1.0)
				if grade in [5, 6]:
					_spike(holder, trim if grade == 6 else base, Vector3(0, r * 0.9, 0), Vector3.UP, r * 0.9)
			if grade >= 4:
				var chest := _holder(rig, "Spine1", slot)
				if chest != null:
					var box := _box(body, "Spine1")
					var front: Vector3 = box[1]
					var at: Vector3 = box[0].get_center() + front * _reach(box[0], front) + front * 0.012
					_part(chest, _sphere(0.02), _gem(grade), at)
			if grade == 7:
				var back := _holder(rig, "Spine2", slot)
				if back != null:
					var box := _box(body, "Spine1")
					var ring := _part(back, _ring(0.075, 0.005), trim, -box[1] * 0.13 + Vector3(0, 0.05, 0))
					ring.basis = Basis.looking_at(box[1], Vector3.UP)
		"helmet":
			var holder := _holder(rig, "Head", slot)
			if holder == null:
				return
			# 머리 장식은 **모델 축**으로 짓고 통째로 머리 뼈 좌표로 옮긴다 (`_head_frame`)
			var frame := _head_frame(body)
			var to_bone: Transform3D = frame[0]
			var box: AABB = frame[1]
			var hat := Node3D.new()
			hat.transform = to_bone
			holder.add_child(hat)
			var mid := box.get_center()
			var brow := box.position.y + box.size.y * HELMET_BROW_AT
			var top := Vector3(mid.x, box.end.y, mid.z)
			# 이마 테 — 투구 가장자리를 따라 두른다
			var band := _part(hat, _ring(box.size.x * 0.52, 0.006), trim, Vector3(mid.x, brow, mid.z))
			band.scale = Vector3(1.0, 1.0, box.size.z / box.size.x)
			if grade >= 4:
				_part(hat, _sphere(0.014), _gem(grade), Vector3(mid.x, brow + 0.012, box.end.z * 0.92))
			if grade in [5, 6]:
				# 뿔 둘 — 정수리 양옆에서 비스듬히
				for side in [-1.0, 1.0]:
					var dir := (Vector3.UP * 0.8 + Vector3(side, 0, 0) * 0.6 - Vector3.BACK * 0.2).normalized()
					_spike(hat, trim if grade == 6 else base, top + Vector3(side * box.size.x * 0.3, -0.02, 0), dir, 0.06)
			if grade == 7:
				_part(hat, _ring(0.06, 0.005), trim, top + Vector3(0, 0.045, 0))
		"boots":
			for bone in ["LeftLeg", "RightLeg"]:
				var holder := _holder(rig, bone, slot)
				if holder == null:
					continue
				var box := _box(body, bone)
				var front: Vector3 = box[1]
				# 무릎받이 — 정강이 뼈 뿌리(무릎) 앞
				var knee := front * (_reach(box[0], front) + 0.004) + Vector3(0, 0.012, 0)
				var cap := _part(holder, _sphere(0.034), base, knee)
				cap.basis = Basis.looking_at(front, Vector3.UP).scaled(Vector3(1.0, 1.0, 0.55))
				if grade >= 4:
					_part(holder, _sphere(0.012), _gem(grade), knee + front * 0.018)
				if grade in [5, 6]:
					_spike(holder, trim if grade == 6 else base, knee + front * 0.01, front, 0.04)


static func _decor_bones(slot: String) -> Array:
	match slot:
		"armor":
			return ["LeftArm", "RightArm", "Spine1", "Spine2"]
		"helmet":
			return ["Head"]
		"boots":
			return ["LeftLeg", "RightLeg"]
	return []


## 뼈 소켓 안의 부위 묶음. 뼈가 없으면 null
static func _holder(rig: Node3D, bone: String, slot: String) -> Node3D:
	var socket: BoneAttachment3D = rig.fist_socket(bone)
	if socket == null:
		return null
	var holder := Node3D.new()
	holder.name = "GearDecor_" + slot
	socket.add_child(holder)
	return holder


## 머리를 **모델 축**으로 잰다 — [모델 축 → 머리 뼈 좌표 변환, 머리 상자(머리 뼈 자리를 원점으로
## 한 모델 축 좌표), 머리 뼈 자리(모델 좌표)]. 머리 뼈 좌표로 재면 목 기울기만큼 비스듬하다
static func _head_frame(body: MeshInstance3D) -> Array:
	var key := "head/%d" % body.mesh.get_instance_id()
	if _boxes.has(key):
		return _boxes[key]
	var skin := body.skin
	var head := -1
	for i in skin.get_bind_count():
		if str(skin.get_bind_name(i)) == "Head":
			head = i
	if head < 0:
		return [Transform3D(), AABB(Vector3(-0.05, 0, -0.05), Vector3(0.1, 0.12, 0.1)), Vector3.ZERO]
	var bind := skin.get_bind_pose(head)
	var at := bind.affine_inverse().origin
	var box := AABB()
	var first := true
	var source := body.mesh as ArrayMesh
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights.is_empty():
			continue
		var per := weights.size() / pos.size()
		for v in pos.size():
			var w := 0.0
			for k in per:
				if int(bones[v * per + k]) == head:
					w += weights[v * per + k]
			if w <= 0.5:
				continue
			var local := pos[v] - at
			box = AABB(local, Vector3.ZERO) if first else box.expand(local)
			first = false
	# 모델 축 좌표 p(머리 뼈 자리 원점) → 머리 뼈 좌표 = bind · (at + p)
	var to_bone := bind * Transform3D(Basis(), at)
	_boxes[key] = [to_bone, box, at]
	return _boxes[key]


## 그 뼈에 0.5 넘게 묶인 정점의 상자(뼈 좌표)와 앞쪽 방향(뼈 좌표)
static func _box(body: MeshInstance3D, bone: String) -> Array:
	var key := body.mesh.get_instance_id()
	if not _boxes.has(key):
		_boxes[key] = _measure(body)
	return _boxes[key].get(bone, [AABB(Vector3(-0.03, 0, -0.03), Vector3(0.06, 0.1, 0.06)), Vector3.BACK])


static func _measure(body: MeshInstance3D) -> Dictionary:
	var skin := body.skin
	var source := body.mesh as ArrayMesh
	var boxes := {}
	var first := {}
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights.is_empty():
			continue
		var per := weights.size() / pos.size()
		for v in pos.size():
			for k in per:
				if weights[v * per + k] <= 0.5:
					continue
				var b := int(bones[v * per + k])
				var p := skin.get_bind_pose(b) * pos[v]
				if first.has(b):
					boxes[b] = (boxes[b] as AABB).expand(p)
				else:
					boxes[b] = AABB(p, Vector3.ZERO)
					first[b] = true
	var out := {}
	for b in boxes:
		# 모델의 앞(+Z)을 뼈 좌표로 — 바인드 자세의 뼈 회전을 되돌린다
		var front := (skin.get_bind_pose(b).basis * Vector3.BACK).normalized()
		out[str(skin.get_bind_name(b))] = [boxes[b], front]
	return out


## 상자 가운데에서 `dir` 쪽 겉면까지의 거리
static func _reach(box: AABB, dir: Vector3) -> float:
	var half := box.size * 0.5
	return absf(dir.x) * half.x + absf(dir.y) * half.y + absf(dir.z) * half.z


## 몸 메시 — 스킨이 붙은 것 중 가장 큰 것
static func _body(rig: Node3D) -> MeshInstance3D:
	var best: MeshInstance3D = null
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.skin == null or mesh_node.name.begins_with("Gear_") or not (mesh_node.mesh is ArrayMesh):
			continue
		if best == null or mesh_node.mesh.get_aabb().size.length() > best.mesh.get_aabb().size.length():
			best = mesh_node
	return best


static func _gem(grade: int) -> StandardMaterial3D:
	var glow: Color = {4: Color("#b85cff"), 5: Color("#ffb347"), 6: Color("#ff2a10"), 7: Color("#fff1c0")}.get(grade, Color("#b85cff"))
	return _plain(glow, 0.2, 0.1, true)


static func _plain(color: Color, metal: float, rough: float, glow: bool) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.6
	_mats[key] = mat
	return mat


static func _spike(root: Node3D, mat: Material, at: Vector3, dir: Vector3, length: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = length * 0.28
	cone.height = length
	cone.radial_segments = 10
	var node := _part(root, cone, mat, at + dir.normalized() * length * 0.5)
	node.basis = _up_to(dir)


## +Y 를 `dir` 로 돌리는 기저
static func _up_to(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var axis := Vector3.UP.cross(d)
	if axis.length() < 1e-4:
		return Basis() if d.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), Vector3.UP.angle_to(d))


static func _part(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	root.add_child(node)
	return node


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


static func _ring(radius: float, thick: float) -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thick
	torus.outer_radius = radius + thick
	torus.rings = 24
	torus.ring_segments = 6
	return torus
