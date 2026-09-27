class_name TouchGuard
extends Node

## 폰에서 **"아무것도 안 눌린다"** 를 푼다 (2026-09-27 지적 — 화면은 계속 도는데 단추·땅이
## 전부 안 먹었다).
##
## 고도는 손가락을 마우스로 바꿔 보낸다(`emulate_mouse_from_touch`). 그런데 **한 번에 한
## 손가락만** 바꾸고, 그 손가락의 **떼기를 받아야** 다음 손가락을 받는다. 떼기를 한 번
## 놓치면 그 뒤 손가락은 전부 버려진다. 다른 플랫폼은 창에 초점이 돌아올 때
## `ensure_touch_mouse_raised` 로 풀어 주지만 **웹판은 그걸 안 부른다** — 새로고침 전까지
## 막힌다. 게임 판정·UI 는 헤드리스에서 몬스터 30마리가 붙어도 멀쩡했다.
##
## 막히면 **단추는 산다** — 고도 4.7 의 `Button` 은 손가락을 직접 받는다. 죽는 것은
## 마우스만 보는 **땅·몬스터 누르기**(`game.gd` 의 `_unhandled_input`)이고, 떼기를 못 받았으니
## 캐릭터는 **마지막 누른 쪽으로 계속 걷는다**.
##
## 그래서 여기서 본다: **단추가 받지 않은 손가락이 닿았는데 마우스 누름이 안 따라왔으면**
## 붙잡힌 손가락을 뗀 것으로 치고 이번 손가락을 다시 넣는다. 단추 위 누름에서는 풀지
## 않는다 — 걸으며(누른 채) 다른 손가락으로 스킬을 누르는 것은 정상이고, 그때 풀면
## 걷던 게 멈춘다.
##
## 넣은 이벤트는 고도가 모아 두었다가 다음 프레임에 흘린다 (누적 입력이 기본이라
## `_input` 안에서 넣어도 되돌아 들어오지 않는다).

## 지금 마우스로 바뀌어 나가는 손가락 (-1 = 없음)
var _mouse_index := -1
## 방금 흉내 낸 마우스 누름이 나왔나. 고도는 **마우스 누름을 먼저, 손가락을 뒤에** 보낸다
var _emulated := false
## 지금 손가락이 마우스로 바뀌었나 — `_input` 에서 재 두고 UI 를 지난 뒤(`_unhandled_input`) 본다
var _translated := false
## 푼 횟수 — 테스트가 본다
var rescued := 0


func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null:
		if click.device == InputEvent.DEVICE_ID_EMULATION and click.button_index == MOUSE_BUTTON_LEFT:
			_emulated = click.pressed
			if not click.pressed:
				_mouse_index = -1
		return
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return
	_translated = _emulated
	if _emulated:
		_mouse_index = touch.index
	_emulated = false


## 여기까지 왔으면 단추가 안 받은 누름이다 (땅·몬스터)
func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed or _translated:
		return
	if _mouse_index != -1 and _mouse_index != touch.index:
		_rescue(touch)


## 붙잡힌 손가락을 떼고 이번 손가락을 다시 넣는다
func _rescue(touch: InputEventScreenTouch) -> void:
	var lift := InputEventScreenTouch.new()
	lift.index = _mouse_index
	lift.pressed = false
	lift.canceled = true
	# 뗀 자리는 화면 밖 — 붙잡힌 손가락이 누르던 단추가 이 떼기로 눌리면 안 된다
	lift.position = Vector2(-10000, -10000)
	Input.parse_input_event(lift)
	Input.parse_input_event(touch.duplicate())
	_mouse_index = -1
	rescued += 1
