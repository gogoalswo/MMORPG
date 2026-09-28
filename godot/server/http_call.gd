class_name HttpCall
extends RefCounted

## HTTP 요청 한 번 — **노드 없이** `poll` 로 돌린다 (`LedgerServer` 는 노드가 아니라 `HTTPRequest` 를
## 못 쓴다). 결제 검증기(`GooglePlayVerifier`)가 구글에 물을 때 쓴다.
##
##   var call := HttpCall.new("POST", url, headers, body)
##   while not call.done: call.poll()
##   call.code · call.body
##
## `https://` 면 TLS 로 붙는다. 테스트는 `http://127.0.0.1:…` 의 가짜 서버에 붙인다.

## 이만큼 넘게 걸리면 실패로 끝낸다
const TIMEOUT_MS := 15000

var done := false
## HTTP 상태 코드. 붙지도 못했으면 0
var code := 0
var body := ""
var error := ""

var _http := HTTPClient.new()
var _method := HTTPClient.METHOD_GET
var _path := ""
var _headers: PackedStringArray
var _payload := ""
var _sent := false
var _chunks := PackedByteArray()
var _deadline := 0


func _init(method: String, url: String, headers: PackedStringArray = [], payload := "") -> void:
	_method = HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	_headers = headers
	_payload = payload
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	var tls := url.begins_with("https://")
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var host := rest if slash < 0 else rest.substr(0, slash)
	_path = "/" if slash < 0 else rest.substr(slash)
	var port := 443 if tls else 80
	if host.contains(":"):
		port = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	var err := _http.connect_to_host(host, port, TLSOptions.client() if tls else null)
	if err != OK:
		_finish("connect %s" % error_string(err))


func poll() -> void:
	if done:
		return
	if Time.get_ticks_msec() > _deadline:
		_finish("timeout")
		return
	_http.poll()
	match _http.get_status():
		HTTPClient.STATUS_CONNECTED:
			if not _sent:
				_sent = true
				var err := _http.request(_method, _path, _headers, _payload)
				if err != OK:
					_finish("request %s" % error_string(err))
			elif not _http.has_response():
				pass
		HTTPClient.STATUS_BODY:
			code = _http.get_response_code()
			var chunk := _http.read_response_body_chunk()
			if chunk.size() > 0:
				_chunks.append_array(chunk)
		HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, \
				HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_finish("status %d" % _http.get_status())
	# 본문을 다 읽으면 다시 CONNECTED 로 돌아온다 (또는 서버가 끊는다)
	if _sent and _http.has_response() and _http.get_status() != HTTPClient.STATUS_BODY:
		code = _http.get_response_code()
		_finish("")
	elif _sent and _http.get_status() == HTTPClient.STATUS_DISCONNECTED:
		_finish("" if code > 0 else "closed")  # 답 없이 끊겼으면 기다리지 않는다


func _finish(why: String) -> void:
	done = true
	error = why
	body = _chunks.get_string_from_utf8()
	_http.close()
