class_name ButtonFx
extends RefCounted

## 단추의 누름 · 뗌 · 클릭 움직임 (2026-09-29 요청: "버튼에 press, release, click 애니메이션 넣어").
##
## | 때 | 신호 | 움직임 |
## |---|---|---|
## | 누름 | `button_down` | 가운데를 축으로 `PRESS_SCALE` 로 줄어든다 |
## | 뗌 (밖에서 떼어 안 눌림) | `button_up` 만 | 튕기듯 제 크기로 (`TRANS_BACK`) |
## | 클릭 (안에서 뗌) | `button_up` + `pressed` | `CLICK_SCALE` 로 한 번 부풀었다 제 크기 + 잠깐 밝게 번쩍 |
##
## - **크기(`scale`)로만 움직인다** — 컨테이너는 자리·크기만 정하고 `scale` 은 안 건드려서
##   옆 칸이 밀리지 않는다. 축(`pivot_offset`)은 움직일 때마다 가운데로 다시 잡는다.
## - **번쩍임은 `self_modulate`** 로 한다. `modulate` 는 창·줄이 흐리게 할 때 쓰고 글자(자식)까지
##   번지므로 건드리지 않는다. 끝나면 붙일 때의 색으로 돌아간다.
## - 뗌과 클릭은 같은 프레임에 온다 (`button_up` · `pressed` 순서는 고도 판마다 다르다). 그래서
##   `button_up` 은 **한 프레임 미뤄서** 그사이 `pressed` 가 왔는지 보고 둘 중 하나만 한다.

const PRESS_SCALE := 0.92
const PRESS_SEC := 0.07
const RELEASE_SEC := 0.18
const CLICK_SCALE := 1.06
const CLICK_UP_SEC := 0.07
const CLICK_DOWN_SEC := 0.16
## 클릭 때 번쩍이는 색 — 청록 돌판 위에서 따뜻하게 밝아진다
const FLASH := Color(1.45, 1.38, 1.2)
const FLASH_SEC := 0.25


## 단추에 붙인다. 두 번 불러도 한 번만 붙는다 (`_make_button` 뒤에 `_gold_text` 를 또 부른다)
static func attach(button: BaseButton) -> void:
	if button.has_meta(&"button_fx"):
		return
	button.set_meta(&"button_fx", true)
	button.set_meta(&"button_fx_base", button.self_modulate)
	button.button_down.connect(_press.bind(button))
	button.button_up.connect(func() -> void: _settle.call_deferred(button))
	button.pressed.connect(func() -> void: button.set_meta(&"button_fx_clicked", true))


## 누름 — 클릭 표시는 **여기서** 지운다. `button_up` 에서 지우면 `pressed` 가 먼저 온 판에서
## 클릭을 잃는다 (테스트에서 잡혔다)
static func _press(button: BaseButton) -> void:
	button.set_meta(&"button_fx_clicked", false)
	var tween := _restart(button)
	tween.tween_property(button, "scale", Vector2.ONE * PRESS_SCALE, PRESS_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 뗀 뒤 — 클릭이면 부풀었다 돌아오며 번쩍, 아니면 튕기듯 돌아온다
static func _settle(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	var tween := _restart(button)
	if not button.get_meta(&"button_fx_clicked", false):
		tween.tween_property(button, "scale", Vector2.ONE, RELEASE_SEC) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	button.set_meta(&"button_fx_clicked", false)
	# 셋을 나란히 돌린다 — 차례로 두면 번쩍임이 끝날 때까지 줄어들기가 기다린다
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE * CLICK_SCALE, CLICK_UP_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, CLICK_DOWN_SEC).set_delay(CLICK_UP_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	button.self_modulate = FLASH
	tween.tween_property(button, "self_modulate", button.get_meta(&"button_fx_base"), FLASH_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 도는 움직임을 끊고 새로 시작한다. 축은 지금 크기의 가운데. 번쩍이다 끊겨도 밝은 채로
## 남지 않게 색을 되돌린다
static func _restart(button: BaseButton) -> Tween:
	if button.has_meta(&"button_fx_tween"):
		var old: Tween = button.get_meta(&"button_fx_tween")
		if old != null and old.is_valid():
			old.kill()
	button.self_modulate = button.get_meta(&"button_fx_base")
	button.pivot_offset = button.size / 2.0
	var tween := button.create_tween()
	button.set_meta(&"button_fx_tween", tween)
	return tween
