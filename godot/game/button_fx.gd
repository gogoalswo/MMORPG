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
## - **누름을 받는 것과 움직이는 것을 나눌 수 있다** (`target`). HUD 아이콘·퀵슬롯은 그림 위에 투명한
##   `hit` 단추를 덮어 누름을 받는다 — 그 단추는 안 보이니 **칸(`target`)을 움직인다**.
## - 번쩍임은 단추 자신이면 `self_modulate`(글자까지 번지지 않게), 칸이면 `modulate`(아이콘까지 밝게).
##   **원래 색은 클릭하는 순간에 읽는다** — 숨긴 칸(`_design_cell` 은 `modulate.a = 0`)을 붙일 때의
##   색으로 되돌리면 보이게 된다. 알파는 그대로 두고 밝기만 올린다.
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


## 단추에 붙인다. `target` 을 주면 그것을 움직인다 (없으면 단추 자신).
## 두 번 불러도 한 번만 붙는다 (`_make_button` 뒤에 `_gold_text` 를 또 부른다)
static func attach(button: BaseButton, target: Control = null) -> void:
	if button.has_meta(&"button_fx"):
		return
	button.set_meta(&"button_fx", true)
	var moved: Control = button if target == null else target
	var tint := "self_modulate" if moved == button else "modulate"
	button.button_down.connect(_press.bind(button, moved, tint))
	button.button_up.connect(func() -> void: _settle.call_deferred(button, moved, tint))
	button.pressed.connect(func() -> void: button.set_meta(&"button_fx_clicked", true))


## 누름 — 클릭 표시는 **여기서** 지운다. `button_up` 에서 지우면 `pressed` 가 먼저 온 판에서
## 클릭을 잃는다 (테스트에서 잡혔다)
static func _press(button: BaseButton, moved: Control, tint: String) -> void:
	button.set_meta(&"button_fx_clicked", false)
	var tween := _restart(moved, tint)
	tween.tween_property(moved, "scale", Vector2.ONE * PRESS_SCALE, PRESS_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 뗀 뒤 — 클릭이면 부풀었다 돌아오며 번쩍, 아니면 튕기듯 돌아온다
static func _settle(button: BaseButton, moved: Control, tint: String) -> void:
	if not is_instance_valid(button) or not is_instance_valid(moved):
		return
	var tween := _restart(moved, tint)
	if not button.get_meta(&"button_fx_clicked", false):
		tween.tween_property(moved, "scale", Vector2.ONE, RELEASE_SEC) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	button.set_meta(&"button_fx_clicked", false)
	# 셋을 나란히 돌린다 — 차례로 두면 번쩍임이 끝날 때까지 줄어들기가 기다린다
	tween.set_parallel(true)
	tween.tween_property(moved, "scale", Vector2.ONE * CLICK_SCALE, CLICK_UP_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(moved, "scale", Vector2.ONE, CLICK_DOWN_SEC).set_delay(CLICK_UP_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var base: Color = moved.get(tint)
	moved.set_meta(&"button_fx_base", base)
	moved.set(tint, Color(base.r * FLASH.r, base.g * FLASH.g, base.b * FLASH.b, base.a))
	tween.tween_property(moved, tint, base, FLASH_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void: moved.remove_meta(&"button_fx_base"))


## 도는 움직임을 끊고 새로 시작한다. 축은 지금 크기의 가운데. 번쩍이다 끊겼으면 밝은 채로
## 남지 않게 번쩍이기 전 색으로 되돌린다
static func _restart(moved: Control, tint: String) -> Tween:
	if moved.has_meta(&"button_fx_tween"):
		var old: Tween = moved.get_meta(&"button_fx_tween")
		if old != null and old.is_valid():
			old.kill()
	if moved.has_meta(&"button_fx_base"):
		moved.set(tint, moved.get_meta(&"button_fx_base"))
		moved.remove_meta(&"button_fx_base")
	moved.pivot_offset = moved.size / 2.0
	var tween := moved.create_tween()
	moved.set_meta(&"button_fx_tween", tween)
	return tween
