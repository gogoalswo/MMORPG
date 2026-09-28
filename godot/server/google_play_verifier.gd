class_name GooglePlayVerifier
extends PurchaseVerifier

## 구글 플레이 결제 검증 (docs/features/server.md "유료 재화").
##
## 1. **서비스 계정**으로 접근 토큰을 받는다 — JWT(RS256)를 서비스 계정 비밀키로 서명해
##    `oauth2.googleapis.com/token` 에 내민다. 토큰은 한 시간 가니 만료 1분 전까지 다시 쓴다.
## 2. `androidpublisher v3` 의 `purchases.products.get` 으로 그 영수증(구매 토큰)을 묻는다.
##    **`purchaseState == 0`(결제됨)이고 `consumptionState == 0`(아직 소모 안 됨)** 이어야 받는다.
##
## 서비스 계정 키(JSON)와 패키지 이름은 `server_main.gd` 가 명령줄로 받는다 — 저장소에 넣지 않는다.
## 주소는 테스트가 가짜 서버로 바꿔 끼운다 (`token_url` · `api_base`).

const SCOPE := "https://www.googleapis.com/auth/androidpublisher"

var package_name := ""
var token_url := "https://oauth2.googleapis.com/token"
var api_base := "https://androidpublisher.googleapis.com"

var _email := ""
var _key: CryptoKey = null
var _access := ""
var _access_until := 0  # 유닉스 초
## 토큰을 받는 중이면 그 요청 — 여러 일감이 한 번만 받게 나눠 쓴다
var _token_call: HttpCall = null


## `service_account` 는 구글이 내려주는 키 JSON 을 읽은 사전 (`client_email` · `private_key`)
func _init(package: String, service_account: Dictionary) -> void:
	package_name = package
	_email = str(service_account.get("client_email", ""))
	_key = CryptoKey.new()
	if _key.load_from_string(str(service_account.get("private_key", ""))) != OK:
		push_error("서비스 계정 비밀키를 못 읽었다")
		_key = null


func start(product_id: String, token: String) -> Dictionary:
	var job := {"product": product_id, "token": token, "done": false, "ok": false, "reason": "", "call": null}
	if _key == null or package_name.is_empty():
		job.done = true
		job.reason = "no_credentials"
	return job


func poll(job: Dictionary) -> void:
	if job.done:
		return
	var now := int(Time.get_unix_time_from_system())
	# 1. 접근 토큰
	if _access.is_empty() or now >= _access_until - 60:
		_poll_token(now)
		if _token_call == null and _access.is_empty():
			_end(job, false, "token")
		return
	# 2. 영수증 묻기
	if job.call == null:
		var url := "%s/androidpublisher/v3/applications/%s/purchases/products/%s/tokens/%s" % [
			api_base, package_name.uri_encode(), str(job.product).uri_encode(), str(job.token).uri_encode()]
		job.call = HttpCall.new("GET", url, PackedStringArray(["Authorization: Bearer " + _access]))
		return
	var call: HttpCall = job.call
	call.poll()
	if not call.done:
		return
	if call.code != 200:
		_end(job, false, "http %d %s" % [call.code, call.error])
		return
	var found = JSON.parse_string(call.body)
	if typeof(found) != TYPE_DICTIONARY:
		_end(job, false, "bad_body")
		return
	job["order_id"] = str(found.get("orderId", ""))
	match int(found.get("purchaseState", -1)):
		0:
			if int(found.get("consumptionState", 0)) != 0:
				_end(job, false, "consumed")
			else:
				_end(job, true, "")
		1:
			_end(job, false, "canceled")
		2:
			_end(job, false, "pending")
		_:
			_end(job, false, "unknown_state")


func _end(job: Dictionary, ok: bool, reason: String) -> void:
	job.done = true
	job.ok = ok
	job.reason = reason
	job.call = null


func _poll_token(now: int) -> void:
	if _token_call == null:
		var form := "grant_type=%s&assertion=%s" % [
			"urn:ietf:params:oauth:grant-type:jwt-bearer".uri_encode(), jwt(now)]
		_token_call = HttpCall.new("POST", token_url,
			PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), form)
		return
	_token_call.poll()
	if not _token_call.done:
		return
	var parsed = JSON.parse_string(_token_call.body)
	_token_call = null
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("access_token"):
		_access = str(parsed.access_token)
		_access_until = now + int(parsed.get("expires_in", 3600))
	else:
		push_warning("구글 접근 토큰을 못 받았다")


## 서비스 계정 JWT — `헤더.내용.서명`, 셋 다 base64url(패딩 없음). 서명은 RS256
func jwt(now: int) -> String:
	var head := _b64url(JSON.stringify({"alg": "RS256", "typ": "JWT"}).to_utf8_buffer())
	var claim := _b64url(JSON.stringify({
		"iss": _email, "scope": SCOPE, "aud": token_url, "iat": now, "exp": now + 3600,
	}).to_utf8_buffer())
	var signing := "%s.%s" % [head, claim]
	var digest := signing.to_utf8_buffer()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(digest)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, hashing.finish(), _key)
	return "%s.%s" % [signing, _b64url(signature)]


static func _b64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")
