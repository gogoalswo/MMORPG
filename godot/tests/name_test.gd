extends SceneTree

## 캐릭터 이름 (docs/features/play-mode.md "이름") — 규칙 · 무작위 이름 · 시작 화면 ·
## 저장 · 서버(다시 거르기 · 채팅과 랭킹의 이름). 스크린샷 없이 노드와 값으로 본다.
##
##   godot --headless --path godot --script tests/name_test.gd

const DIR := "user://name_test_accounts"

var _failed := 0


func _init() -> void:
	Save.clear()
	_wipe()
	_case_rules()
	_case_random()
	_case_save()
	_case_server()
	_wipe()
	root.call_deferred("add_child", load("res://start.tscn").instantiate())
	_run_screen.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _case_rules() -> void:
	for good in ["용사", "Hero12", "푸른늑대37", "abcdefgh"]:
		if not Names.valid(good):
			_fail("'%s' 가 안 된다고 한다: %s" % [good, Names.why_invalid(good)])
	for bad in ["", "용", "아홉글자짜리이름들","용 사", "[운영자]", "모험가#AB12", "ㅋㅋ", "héro"]:
		if Names.valid(bad):
			_fail("'%s' 를 받았다" % bad)
	if Names.clean("  용사  ") != "용사":
		_fail("앞뒤 공백을 안 잘랐다")


func _case_random() -> void:
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		var name := Names.random(rng)
		if not Names.valid(name):
			_fail("무작위 이름 '%s' 가 규칙에 안 맞는다: %s" % [name, Names.why_invalid(name)])
			return
		seen[name] = true
	if seen.size() < 100:
		_fail("무작위 이름 200개 중 서로 다른 것이 %d개뿐이다" % seen.size())


## 정한 이름이 저장에 남고 다시 읽힌다 · 규칙에 안 맞는 이름은 안 받는다
func _case_save() -> void:
	var w := World.new()
	w.open("meadow")
	w.join("me")
	w.set_name("me", "용 사")
	if str(w._players.me.name) != "":
		_fail("규칙에 안 맞는 이름을 받았다")
	w.set_name("me", "용사")
	w.save("me")
	if str(Save.read().get("name", "")) != "용사":
		_fail("이름이 저장에 안 남았다")
	var again := World.new()
	again.open("meadow")
	again.join("me")
	again.restore("me")
	if str(again._players.me.name) != "용사":
		_fail("다시 읽은 이름이 '%s'" % again._players.me.name)
	Save.clear()


## 서버 — 같은 규칙으로 다시 거르고, 채팅·랭킹·welcome 에 그 이름이 나온다
func _case_server() -> void:
	var store := AccountStore.new(DIR)
	var server := LedgerServer.new(store)
	var a := {}
	var welcome := server.handle(a, {"t": "hello", "name": "용사"})
	if welcome.get("name") != "용사":
		_fail("welcome 의 이름이 %s" % welcome.get("name"))
	var b := {}
	var other := server.handle(b, {"t": "hello", "name": "[운영자]"})
	if not str(other.get("name", "")).begins_with("모험가#"):
		_fail("규칙에 안 맞는 이름을 서버가 받았다: %s" % other.get("name"))
	# 내보낼 때(`name_of`)만 거르면 파일에는 남는다 — **받을 때** 걸러야 한다
	if str(b.account.get("name", "")) != "":
		_fail("규칙에 안 맞는 이름이 계정에 남았다: %s" % b.account.get("name"))

	server.handle(a, {"t": "chat", "text": "안녕"})
	var line: Array = server.take_outbox()
	if line.is_empty() or line[0].get("from") != "용사":
		_fail("채팅 이름이 %s" % [line])
	var board := server.handle(a, {"t": "rank"})
	var names: Array = board.get("top", []).map(func(r: Dictionary) -> String: return str(r.name))
	if not ("용사" in names):
		_fail("랭킹에 이름이 없다: %s" % [names])

	# 들어올 때 새 이름을 주면 바꾼다 · 다시 켠 서버도 파일에서 이름을 읽는다
	server.handle({}, {"t": "hello", "token": welcome.token, "name": "검객"})
	var restarted := LedgerServer.new(store)
	var s := {}
	restarted.handle(s, {"t": "hello"})
	var top: Array = restarted.handle(s, {"t": "rank"}).get("top", []).map(func(r: Dictionary) -> String: return str(r.name))
	if not ("검객" in top) or "용사" in top:
		_fail("이름을 바꾼 뒤 다시 켠 서버의 랭킹이 %s" % [top])


## 시작 화면 — 비우고 들어가면 무작위 이름, 규칙에 안 맞으면 들어가지 않고 알린다
func _run_screen() -> void:
	await process_frame
	var screen: Control = root.get_child(root.get_child_count() - 1)
	if screen.name_input == null:
		_fail("시작 화면에 이름 입력칸이 없다")
		_done()
		return
	screen.name_input.text = ""
	var made: String = screen.resolve_name()
	if not Names.valid(made) or screen.name_input.text != made:
		_fail("비우고 들어가면 지은 이름이 '%s'" % made)
	screen.name_input.text = "  용사 "
	if screen.resolve_name() != "용사":
		_fail("입력한 이름을 그대로 안 썼다")
	PlayMode.current = ""
	screen.name_input.text = "용 사"
	screen.choose(PlayMode.NORMAL)
	if PlayMode.current != "" or screen.normal_button.disabled:
		_fail("규칙에 안 맞는 이름으로 들어갔다")
	if not screen._name_note.text.contains("한글"):
		_fail("안 되는 까닭을 안 알렸다: '%s'" % screen._name_note.text)
	_done()


func _done() -> void:
	Save.clear()
	if _failed == 0:
		print("이름: 전부 통과")
		quit(0)
	else:
		print("이름: %d개 실패" % _failed)
		quit(1)


func _wipe() -> void:
	var path := ProjectSettings.globalize_path(DIR)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(path)
