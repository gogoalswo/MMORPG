class_name ExpFx
extends Node3D

## 몬스터를 잡으면 쓰러진 자리에서 떠오르는 `+n EXP` 글자.
##
## 피해 숫자(`HitFx`)와 같은 규칙으로 짓는다 — 에셋 없이 `Label3D` 하나,
## 항상 앞에 그리고(`no_depth_test`), 스스로 `queue_free` 한다.
## **숫자는 `World` 가 낸 `reward` 이벤트 그대로다.** 화면이 따로 셈하지 않는다.
##
## 처치한 한 대의 피해 숫자와 같은 자리에서 나므로 **겹치지 않게 늦게, 느리게**
## 뜬다. 피해 숫자는 가슴 위 0.3m 에서 초당 1.8m 로 오르고, 이 글자는 가슴 아래
## `START_Y` 에서 `DELAY` 뒤에 초당 `RISE` 로 오른다 — 피해 숫자가 늘 위에 있다.

## 떠 있는 시간. 피해 숫자(0.75초)보다 길다 — 얼마 벌었는지는 읽고 넘어가야 한다
const LIFE := 1.4
## 피해 숫자가 먼저 튀고 나서 나온다
const DELAY := 0.2
## 초당 떠오르는 높이(m). 피해 숫자(1.8)의 절반이라 둘이 벌어진다
const RISE := 0.9
## 피해 숫자(`HitFx.NUMBER_SIZE` 0.011 ≈ 29px)보다 조금 작게 — 주인공은 타격이다
const SIZE := 0.0095
## 가슴보다 이만큼 아래에서 나온다. 찍어 보니 가슴에서 나오면 피해 숫자 아랫단과
## 겹쳤다 (2026-09-23) — 글자는 몸에 안 가리므로(`no_depth_test`) 내려도 보인다
const START_Y := -0.35
## 나올 때 이만큼 부풀었다가 제 크기로 돌아온다
const POP := 1.35
const POP_TIME := 0.12
## 화면 아래 경험치 띠와 같은 금빛 — 어디로 들어갔는지 색으로 잇는다
const COLOR := Color("#f2d060")

var _t := 0.0
var _label: Label3D


## 띄운다. `at` 은 월드 좌표(가슴 높이), `amount` 는 `reward` 이벤트의 `exp` 다
static func spawn(parent: Node3D, at: Vector3, amount: int, font: Font = null) -> ExpFx:
	var fx := ExpFx.new()
	fx.position = at
	parent.add_child(fx)
	fx._build(amount, font)
	return fx


func _build(amount: int, font: Font) -> void:
	_label = Label3D.new()
	_label.text = "+%d EXP" % amount
	if font != null:
		_label.font = font
	_label.font_size = 64
	_label.pixel_size = SIZE
	_label.modulate = COLOR
	_label.outline_size = 16
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 몬스터 몸에 가리면 안 보인다 — 피해 숫자와 같이 항상 앞에 그린다
	_label.no_depth_test = true
	# 피해 숫자보다 한 겹 위에 그린다. 겹쳐 지나갈 때 이 글자가 묻히지 않는다
	_label.render_priority = 1
	_label.outline_render_priority = 0
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	_t += delta
	var live := _t - DELAY
	if live < 0.0:
		return
	_label.visible = true
	_label.position.y = START_Y + RISE * live
	# 톡 튀어나왔다가 제 크기로
	var pop := clampf(live / POP_TIME, 0.0, 1.0)
	_label.scale = Vector3.ONE * lerpf(POP, 1.0, pop)
	# 끝 40% 동안만 흐려진다
	var span := LIFE - DELAY
	_label.modulate.a = clampf((span - live) / (span * 0.4), 0.0, 1.0)
	_label.outline_modulate.a = 0.8 * _label.modulate.a
	if _t >= LIFE:
		queue_free()
