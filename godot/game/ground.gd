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
## npm run sync:godot 을 안 돌린 사람도 게임은 돌아가야 한다
static func material_for(env: Dictionary, size: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var kind := str(env.get("ground", "grass"))
	var tint := str(env.get("groundTint", "#6a665c"))
	var look := look_of(kind)

	var color_path := DIR + "ground_%s_color.ktx2" % kind
	if look.is_empty() or not ResourceLoader.exists(color_path):
		mat.albedo_color = Color(tint)
		return mat

	mat.albedo_texture = load(color_path)
	mat.albedo_color = tint_for(tint, str(look.mean)) * ALBEDO
	mat.roughness = float(look.get("roughness", 0.9))
	mat.metallic = 0.0

	var normal_path := DIR + "ground_%s_normal.ktx2" % kind
	if ResourceLoader.exists(normal_path):
		mat.normal_enabled = true
		mat.normal_texture = load(normal_path)

	# 타일 크기는 미터다. 존이 92m 이고 풀이 4m 면 23번 반복된다
	var tile := maxf(1.0, float(look.get("tile", 6)))
	mat.uv1_scale = Vector3(size / tile, size / tile, 1.0)
	return mat
