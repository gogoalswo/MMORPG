class_name Build
extends RefCounted

## 이 빌드가 언제·어느 커밋으로 구워졌는지.
##
## **왜 있나** — 웹은 브라우저가 최대 10분 캐시하고(GitHub Pages `max-age=600`)
## 새로고침해도 이전 것이 나올 수 있다. 그러면 "고쳤는데 안 바뀌었다" 인지
## "아직 이전 버전을 보고 있다" 인지 구분할 방법이 없다 (2026-09-17 에 지적받았다).
## 화면에 찍어 두면 알려 준 값과 대보면 끝난다.
##
## `build.json` 은 **CI 가 굽기 직전에 쓴다**(pages.yml · android.yml). 커밋하지
## 않으므로 개발 중에는 없고, 그때는 "개발중" 으로 나온다.

const PATH := "res://build.json"

static var _cached := ""


static func stamp() -> String:
	if _cached != "":
		return _cached
	_cached = "개발중"
	if ResourceLoader.exists(PATH) or FileAccess.file_exists(PATH):
		var text := FileAccess.get_file_as_string(PATH)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			_cached = "%s %s" % [parsed.get("commit", "?"), parsed.get("at", "")]
	return _cached


## 서버에 더 새 빌드가 올라와 있나 — **웹에서만** 본다.
##
## 브라우저가 캐시한 것을 보고 있어도 이것만은 `?t=` 를 붙여 새로 받으므로,
## "지금 보는 것이 최신인가" 를 게임이 스스로 답할 수 있다. 사람이 빌드 표시를
## 외워 두고 대볼 필요가 없어진다.
##
## `build.txt` 는 pck 안이 아니라 **사이트에 나란히** 올라간다 (pages.yml).
static func check_latest(host: Node, on_stale: Callable) -> void:
	if not OS.has_feature("web") or stamp() == "개발중":
		return
	var http := HTTPRequest.new()
	host.add_child(http)
	http.request_completed.connect(
		func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if code != 200:
				return
			var latest := body.get_string_from_utf8().strip_edges()
			if latest != "" and latest != stamp():
				on_stale.call(latest)
	)
	# 캐시를 건너뛰려고 붙인다. 20바이트짜리라 매번 받아도 된다
	http.request("build.txt?t=%d" % Time.get_unix_time_from_system())
