extends SceneTree

## 한글 입력칸(`HangulLineEdit`) — 윈도우 새 IME 에서 음절이 넘어갈 때 고도가 버리는 앞 글자를
## 메우는지 본다. 헤드리스에는 IME 가 없어서 알림(`ime_changed`)·키(`_gui_input`)를 직접 넣고,
## 한 프레임 판정(`settle`)을 부른다.
##
##   godot --headless --path godot --script tests/hangul_input_test.gd

var _failed := 0


func _init() -> void:
	_run.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _expect(what: String, got: Variant, want: Variant) -> void:
	if got != want:
		_fail("%s — %s 여야 하는데 %s" % [what, want, got])


func _run() -> void:
	_case_committed()
	var edit := HangulLineEdit.new()
	edit.mend_enabled = true
	root.add_child(edit)
	edit.grab_focus()
	_case_split(edit)
	_case_new_syllable(edit)
	_case_compound(edit)
	_case_arrived(edit)
	_case_erased(edit)
	_done()


## 두벌식 확정 글자 — 받침이 다음 음절로 넘어가는지
func _case_committed() -> void:
	_expect("간 → 나", HangulLineEdit.committed("간", "나"), "가")
	_expect("닭 → 가", HangulLineEdit.committed("닭", "가"), "달")
	_expect("값 → 사", HangulLineEdit.committed("값", "사"), "갑")
	_expect("난 → 나", HangulLineEdit.committed("난", "나"), "나")
	_expect("간 → ㄱ (못 붙는 자음)", HangulLineEdit.committed("간", "ㄱ"), "간")
	_expect("가 → 나 (받침 없음)", HangulLineEdit.committed("가", "나"), "가")
	_expect("영문은 그대로", HangulLineEdit.committed("a", "b"), "a")


## 조합 순서를 한 프레임씩 넣는다 — 한 줄이 한 알림
func _compose(edit: HangulLineEdit, steps: Array) -> void:
	for step in steps:
		edit.ime_changed(step)


## "가" 다음 "나" — 앞 글자가 안 들어오면(고도가 버림) 메운다
func _case_split(edit: HangulLineEdit) -> void:
	edit.text = ""
	_compose(edit, ["ㄱ", "가"])
	edit.settle()
	_compose(edit, ["간"])
	edit.settle()
	_compose(edit, ["", "나"])  # 확정 → 닫힘 → 새 조합, 확정 글자는 버려졌다
	edit.settle()
	_expect("가+나 에서 앞 글자", edit.text, "가")
	_compose(edit, ["", "다"])  # 받침 없이 넘어감 — "나" 가 확정됐다
	edit.settle()
	_expect("가나+다", edit.text, "가나")


## 받침에 못 붙는 자음 — 조합 글자 통째로 확정
func _case_new_syllable(edit: HangulLineEdit) -> void:
	edit.text = ""
	edit.ime_changed("")
	edit.settle()
	_compose(edit, ["간"])
	edit.settle()
	_compose(edit, ["", "ㄱ"])
	edit.settle()
	_expect("간+ㄱ", edit.text, "간")


## 겹받침 — 뒤 자음만 넘어간다
func _case_compound(edit: HangulLineEdit) -> void:
	edit.text = ""
	edit.ime_changed("")
	edit.settle()
	_compose(edit, ["닭"])
	edit.settle()
	_compose(edit, ["", "가"])
	edit.settle()
	_expect("닭+ㅏ", edit.text, "달")


## 확정 글자가 제대로 들어오면(엔진이 고쳐지면) 두 번 넣지 않는다
func _case_arrived(edit: HangulLineEdit) -> void:
	edit.text = ""
	edit.ime_changed("")
	edit.settle()
	var before := edit.mended
	_compose(edit, ["간"])
	edit.settle()
	_compose(edit, ["", "나"])
	var key := InputEventKey.new()
	key.pressed = true
	key.unicode = "가".unicode_at(0)
	edit._gui_input(key)
	edit.settle()
	_expect("확정 글자가 들어왔을 때 메운 횟수", edit.mended, before)


## 지우개로 조합을 다 지웠을 때(닫히고 안 열림) — 아무것도 넣지 않는다
func _case_erased(edit: HangulLineEdit) -> void:
	edit.text = ""
	edit.ime_changed("")
	edit.settle()
	_compose(edit, ["ㄱ"])
	edit.settle()
	_compose(edit, [""])
	edit.settle()
	_expect("조합을 지웠을 때", edit.text, "")


func _done() -> void:
	if _failed == 0:
		print("한글 입력: 통과")
		quit(0)
	else:
		print("한글 입력: %d개 실패" % _failed)
		quit(1)
