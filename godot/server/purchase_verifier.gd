class_name PurchaseVerifier
extends RefCounted

## 결제 영수증 검증기의 틀 (docs/features/server.md "유료 재화"). 스토어에 묻는 데 시간이 걸려서
## **일감(job)** 으로 돈다 — `start` 가 일감을 만들고 `LedgerServer.poll_jobs` 가 끝날 때까지 `poll` 한다.
##
## 일감은 사전이다. 끝나면 `done = true` 와 함께
##   ok       — 결제가 실제로 됐고 아직 소모되지 않았다
##   order_id — 스토어의 주문 번호 (기록용)
##   reason   — 안 됐으면 왜 (`canceled` · `pending` · `consumed` · `http 404` …)
##
## 실제 검증기는 `GooglePlayVerifier`. 테스트는 이것을 물려받은 가짜를 쓴다.

func start(product_id: String, token: String) -> Dictionary:
	return {"product": product_id, "token": token, "done": true, "ok": false, "reason": "no_verifier"}


func poll(_job: Dictionary) -> void:
	pass
