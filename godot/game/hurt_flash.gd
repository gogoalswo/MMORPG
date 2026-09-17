class_name HurtFlash
extends TextureRect

## 내가 맞았을 때 화면 가장자리가 붉어지는 비네트.
##
## 3D 이펙트는 **맞은 자리를 보고 있어야** 보인다 — 뒤에서 맞거나 손가락에 가리면
## 체력이 줄어든 뒤에야 안다. 화면 테두리는 어디를 보고 있든 보인다.
##
## 가운데는 비워 둔다(`FILL_RADIAL`). 시야를 덮으면 맞는 동안 도망칠 자리를
## 못 고른다 — 알리는 것이지 가리는 것이 아니다.
##
## 이미지를 쓰지 않고 그라디언트로 만든다 (hit_fx.gd 와 같은 이유).

## 다 사라지기까지 걸리는 시간
const FADE := 0.45
## 제일 진할 때의 불투명도. 더 올리면 화면이 빨개서 몬스터가 안 보인다
const PEAK := 0.55

var _alpha := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 화면 전체를 덮으므로 터치를 먹으면 걸을 수가 없다
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture = _vignette()
	modulate = Color(1, 1, 1, 0)
	visible = false


## 맞았다. `strength` 는 아픈 만큼(0~1) — 스치면 옅게, 크게 맞으면 진하게.
## **겹치면 더 진한 쪽을 남긴다** (더하면 연타에 화면이 새빨개진다)
func hit(strength: float = 1.0) -> void:
	_alpha = maxf(_alpha, PEAK * clampf(strength, 0.25, 1.0))
	visible = true
	modulate.a = _alpha


func _process(delta: float) -> void:
	if _alpha <= 0.0:
		return
	_alpha = maxf(0.0, _alpha - delta * (PEAK / FADE))
	modulate.a = _alpha
	visible = _alpha > 0.0


func _vignette() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.45)
	gradient.set_color(0, Color(0.85, 0.06, 0.05, 0.0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.85, 0.06, 0.05, 0.9))

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex
