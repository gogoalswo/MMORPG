class_name Ground
extends RefCounted

## 존 바닥 한 장.
##
## 이미지 7종(바르코 타일 텍스처)을 `env.ground` 로 고른다. 사냥터 20곳이
## 여섯 장을 나눠 쓰므로 **존 색(`groundTint`)으로 물들여 가른다** —
## 규칙과 이유는 docs/features/world-zones.md 의 "바닥" 절에 있다.
##
## 텍스처 성질(타일 크기·러프니스·평균색)은 존이 아니라 **이미지에 딸린 것**이라
## `zones.json` 의 `groundLooks` 에서 읽는다 (shared 의 `GROUND_LOOKS`).

const DIR := "res://assets/ground/"

## 바닥 반사율 배율. 바르코 이미지는 이미 화면에 보일 밝기로 그려져 있어서
## 그대로 깔면 눈·모래가 하얗게 날아가 무늬가 사라진다
const ALBEDO := 0.3

## 존 색으로 끌어당기는 비율. 1 이면 소금 평원이 마른 땅의 제 색을 잃고,
## 0 이면 초원과 검은 삼림이 같은 바닥이 된다
const TINT_PULL := 0.5

## 무늬 대비. 텍스처 평균색을 축으로 밝기 비율을 이만큼 지수로 벌린다.
## 1 이면 텍스처 그대로 — 그때는 돌 틈·풀이 화면에서 희미하다는 지적을 받았다
## (2026-09-17). 평균은 그대로라 존 밝기는 안 변한다
const CONTRAST := 1.4

## 노멀맵 세기. 노멀은 밝기를 높이로 봐서 만든 것이라(build-ground-textures.mjs)
## 기본 1.0 으로는 요철이 밋밋하다
const NORMAL_DEPTH := 2.0

const SHADER := preload("res://game/ground.gdshader")


static func look_of(kind: String) -> Dictionary:
	return GameData.zones().get("groundLooks", {}).get(kind, {})


## 텍스처 평균색을 존 색 쪽으로 끌어당긴 곱셈값.
## 명암(무늬)은 곱셈이라 그대로 남는다
static func tint_for(target_hex: String, mean_hex: String) -> Color:
	# 비율로 쓰는 값이라 선형으로 맞춘 뒤 나눈다 (three 쪽도 선형으로 곱한다)
	var t := Color(target_hex).srgb_to_linear()
	var m := Color(mean_hex).srgb_to_linear()
	return Color(
		lerpf(1.0, clampf(t.r / maxf(m.r, 1e-4), 0.3, 2.5), TINT_PULL),
		lerpf(1.0, clampf(t.g / maxf(m.g, 1e-4), 0.3, 2.5), TINT_PULL),
		lerpf(1.0, clampf(t.b / maxf(m.b, 1e-4), 0.3, 2.5), TINT_PULL),
	)


## 바닥 재질. 텍스처가 없으면 단색으로 떨어진다 —
## npm run sync:godot 을 안 돌린 사람도 게임은 돌아가야 한다.
##
## 텍스처가 있으면 ground.gdshader 를 쓴다. StandardMaterial3D 로는 무늬 대비를
## 못 벌리고(반사율 곱은 밝기만 낮춘다) 필터도 아니소트로픽으로 못 준다
static func material_for(env: Dictionary, size: float) -> Material:
	var kind := str(env.get("ground", "grass"))
	var tint := str(env.get("groundTint", "#6a665c"))
	var look := look_of(kind)

	var color_path := DIR + "ground_%s_color.ktx2" % kind
	if look.is_empty() or not ResourceLoader.exists(color_path):
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(tint)
		return flat

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("albedo_tex", load(color_path))
	mat.set_shader_parameter("tint", tint_for(tint, str(look.mean)) * ALBEDO)
	# 셰이더가 받는 텍스처 값은 선형이다. 평균색은 sRGB 바이트라 맞춰 준다
	mat.set_shader_parameter("mean_color", Color(str(look.mean)).srgb_to_linear())
	mat.set_shader_parameter("contrast", CONTRAST)
	mat.set_shader_parameter("rough", float(look.get("roughness", 0.9)))

	var normal_path := DIR + "ground_%s_normal.ktx2" % kind
	var has_normal := ResourceLoader.exists(normal_path)
	mat.set_shader_parameter("has_normal", has_normal)
	if has_normal:
		mat.set_shader_parameter("normal_tex", load(normal_path))
		mat.set_shader_parameter("normal_depth", NORMAL_DEPTH)

	# 타일 크기는 미터다. 존이 92m 이고 풀이 4m 면 23번 반복된다
	var tile := maxf(1.0, float(look.get("tile", 6)))
	mat.set_shader_parameter("tiling", Vector2(size / tile, size / tile))
	return mat
