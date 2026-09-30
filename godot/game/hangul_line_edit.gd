class_name HangulLineEdit
extends LineEdit

## **윈도우에서 한글을 치면 앞 글자가 지워지는 것**을 메운 입력칸 (2026-09-30 지적 — 닉네임에
## 한 글자 치고 다음 글자를 치면 앞 글자가 사라졌다).
##
## 고도(4.7.2, master 도 같다)의 버그다. 윈도우 새 IME 는 음절이 넘어갈 때 **앞 음절 확정 →
## 조합 닫기 → 새 조합 시작** 을 한 번에 보낸다. 고도는 조합 시작(`WM_IME_STARTCOMPOSITION`)에서
## "조합을 시작한 키" 를 지우려고 **버퍼의 마지막 키를 하나 버리는데**, 그게 방금 확정된 앞
## 글자(`WM_CHAR`)다. 한글은 음절마다 조합을 새로 여니 매 글자가 걸린다. 일본어도 같은
## 원인으로 "山川 + あ → 山あ" 가 된다 (godotengine/godot#123716, 4.8 에서 고칠 예정).
##
## 엔진은 못 고치니 여기서 메운다: **한 프레임 안에 조합이 닫히고 곧바로 다시 열렸는데 확정
## 글자가 키로 안 들어왔으면** 버려진 것이다. 무엇이 확정됐는지는 IME 가 알려 주지 않지만
## 두벌식 규칙으로 정해진다 — 닫히기 전 조합("간")과 새 조합("나")을 보면 받침이 넘어갔으니
## "가" 다 (`committed`). 확정 글자가 제대로 들어오면(엔진이 고쳐지거나 다른 플랫폼) 손대지 않는다.
##
## 알림(`NOTIFICATION_OS_IME_UPDATE`)은 창 메시지를 받는 자리에서 바로 오고, 키는 그 뒤에
## 모아서 흘린다 — 그래서 판정은 키까지 다 받은 `_process` 에서 한다.

## 메우기를 켤까 — 버그는 윈도우에만 있다. 테스트가 켠다
var mend_enabled := OS.get_name() == "Windows"
## 메운 횟수 — 테스트가 본다
var mended := 0

## 지금 조합 중인 글자
var _composing := ""
## 이번 프레임에 닫힌 조합 ("" = 안 닫혔다)
var _closed := ""
## 닫힌 뒤 같은 프레임에 새로 열린 조합
var _reopened := ""
## 닫힌 뒤 확정 글자가 키로 들어왔나
var _arrived := false

## 두벌식 받침 → [남는 받침, 다음 음절로 넘어가는 초성] (유니코드 받침·초성 번호)
const _SPLIT := {
	1: [0, 0], 2: [0, 1], 3: [1, 9], 4: [0, 2], 5: [4, 12], 6: [4, 18], 7: [0, 3],
	8: [0, 5], 9: [8, 0], 10: [8, 6], 11: [8, 7], 12: [8, 9], 13: [8, 16], 14: [8, 17],
	15: [8, 18], 16: [0, 6], 17: [0, 7], 18: [17, 9], 19: [0, 9], 20: [0, 10], 21: [0, 11],
	22: [0, 12], 23: [0, 14], 24: [0, 15], 25: [0, 16], 26: [0, 17], 27: [0, 18],
}
const _HANGUL_FIRST := 0xAC00
const _HANGUL_LAST := 0xD7A3


func _init() -> void:
	set_process(false)


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_OS_IME_UPDATE:
		if mend_enabled and has_focus():
			ime_changed(DisplayServer.ime_get_text())
	elif what == NOTIFICATION_FOCUS_EXIT:
		_composing = ""
		_closed = ""


func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.unicode >= 32:
		_arrived = true


## IME 조합 글자가 바뀌었다
func ime_changed(now: String) -> void:
	if now == _composing:
		return
	if now.is_empty():
		_closed = _composing
		_reopened = ""
		_arrived = false
		set_process(true)
	elif not _closed.is_empty():
		_reopened = now
	_composing = now


func _process(_delta: float) -> void:
	settle()


## 이번 프레임 판정 — 닫혔다 다시 열렸는데 확정 글자가 안 왔으면 채워 넣는다
func settle() -> void:
	set_process(false)
	if not _closed.is_empty() and not _reopened.is_empty() and not _arrived:
		var lost := committed(_closed, _reopened)
		insert_text_at_caret(lost)
		mended += 1
		text_changed.emit(text)
	_closed = ""
	_reopened = ""
	_arrived = false


## 조합 `before` 가 닫히고 `after` 가 새로 열렸을 때 확정된 글자.
## 받침 뒤에 모음을 치면 받침(겹받침이면 뒤 자음)이 다음 음절 초성으로 넘어간다 — "간"+ㅏ → "가"+"나"
static func committed(before: String, after: String) -> String:
	if before.length() != 1 or after.is_empty():
		return before
	var code := before.unicode_at(0)
	var next := after.unicode_at(0)
	if code < _HANGUL_FIRST or code > _HANGUL_LAST or next < _HANGUL_FIRST or next > _HANGUL_LAST:
		return before
	var index := code - _HANGUL_FIRST
	var tail := index % 28
	if tail == 0:
		return before
	var split: Array = _SPLIT[tail]
	if split[1] != (next - _HANGUL_FIRST) / 588:
		return before
	return String.chr(code - tail + split[0])
