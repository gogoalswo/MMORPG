class_name AccountStore
extends RefCounted

## 계정 저장소 — **계정 하나 = JSON 파일 하나** (docs/features/server.md "저장").
##
## SQLite(`godot-sqlite`)를 안 쓴 이유: 클라우드 세션에서 확장을 받을 수 없어(403) 세션마다
## 서버 테스트를 못 돌린다. 플레이어끼리 거래가 없으니 여러 계정을 묶는 트랜잭션도 필요 없다.
## 더 커지면 이 파일만 DB 로 갈아 끼운다 — 바깥은 `create` · `find` · `write` 만 안다.
##
## 토큰은 `<id>.<비밀>` 이다. 파일에는 **비밀의 해시만** 남긴다 — 저장소가 새도 토큰은 안 샌다.
## 쓰기는 임시 파일에 쓰고 이름을 바꾼다 — 쓰다가 꺼져도 앞의 것이 온전히 남는다.

const VERSION := 1
const ID_BYTES := 8        # 16자리 16진수
const SECRET_BYTES := 24   # 48자리 16진수

var _dir := ""
var _crypto := Crypto.new()


## `dir` 은 `user://…` 나 절대 경로. 없으면 만든다
func _init(dir: String) -> void:
	_dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(_dir)


## 새 계정. `{id, token, ledger}` — 토큰은 이때 한 번만 알 수 있다
func create(ledger: Dictionary) -> Dictionary:
	var id := _crypto.generate_random_bytes(ID_BYTES).hex_encode()
	while FileAccess.file_exists(_path(id)):
		id = _crypto.generate_random_bytes(ID_BYTES).hex_encode()
	var secret := _crypto.generate_random_bytes(SECRET_BYTES).hex_encode()
	var account := {"id": id, "secret_hash": secret.sha256_text(), "ledger": ledger}
	write(account)
	var out := account.duplicate()
	out["token"] = "%s.%s" % [id, secret]
	return out


## 토큰으로 찾는다. 모양이 틀렸거나 · 없거나 · 비밀이 안 맞으면 빈 사전
func find(token: String) -> Dictionary:
	var parts := token.split(".")
	if parts.size() != 2 or not _valid_id(parts[0]):
		return {}
	var path := _path(parts[0])
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != VERSION:
		return {}
	if str(parsed.get("secret_hash", "")) != parts[1].sha256_text():
		return {}
	parsed.erase("version")
	return Ledger.from_json(parsed)


## 저장된 계정 전부 `[{id, ledger}]` — 서버가 켤 때 랭킹을 세우려고 한 번 읽는다
## (docs/features/server.md "랭킹"). 토큰 확인 없이 읽는다 — 서버 안에서만 쓴다
func all() -> Array:
	var out: Array = []
	var dir := DirAccess.open(_dir)
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".json") or not _valid_id(name.get_basename()):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join(name)))
		if typeof(parsed) == TYPE_DICTIONARY and int(parsed.get("version", 0)) == VERSION:
			out.append({"id": name.get_basename(), "name": str(parsed.get("name", "")),
				"ledger": Ledger.from_json(parsed.get("ledger", {}))})
	return out


## 통째로 쓴다. 임시 파일 → 이름 바꾸기
func write(account: Dictionary) -> bool:
	var id := str(account.get("id", ""))
	if not _valid_id(id):
		return false
	var body := account.duplicate()
	body.erase("token")
	body["version"] = VERSION
	var temp := _path(id) + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("계정 저장 못 함 %s: %s" % [id, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(body))
	file.close()
	return DirAccess.rename_absolute(temp, _path(id)) == OK


## --- 주문 (docs/features/server.md "유료 재화") ---
## 구매 토큰 하나 = 파일 하나 (`orders/<토큰의 sha256>.json`) — **어느 계정이든** 같은 영수증으로
## 두 번 받지 못하게. 토큰 원문은 남기지 않는다

func find_order(key: String) -> Dictionary:
	if not _valid_order(key) or not FileAccess.file_exists(_order_path(key)):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_order_path(key)))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func write_order(key: String, order: Dictionary) -> bool:
	if not _valid_order(key):
		return false
	DirAccess.make_dir_recursive_absolute(_dir.path_join("orders"))
	var temp := _order_path(key) + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(order))
	file.close()
	return DirAccess.rename_absolute(temp, _order_path(key)) == OK


func _order_path(key: String) -> String:
	return _dir.path_join("orders").path_join(key + ".json")


func _valid_order(key: String) -> bool:
	return key.length() == 64 and key.is_valid_hex_number()


func _path(id: String) -> String:
	return _dir.path_join(id + ".json")


## 파일 이름으로 쓰기 전에 본다 — 토큰에 `../` 를 넣어 밖의 파일을 읽지 못하게
func _valid_id(id: String) -> bool:
	return id.length() == ID_BYTES * 2 and id.is_valid_hex_number()
