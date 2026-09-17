class_name Transport
extends Node

## 화면과 판정 사이의 유일한 통로.
##
## 지금은 LocalTransport 하나뿐이고 World 를 직접 부른다. 나중에 서버를 붙이면
## 여기에 구현을 하나 더 끼우고 화면 코드는 한 줄도 안 고친다 —
## 웹 클라이언트의 net/transport.ts `RoomLike` 과 같은 모양이다.
##
## **화면 코드가 World 를 직접 만지기 시작하면 이 구조가 무의미해진다.**

## 서버 → 클라 메시지에 해당 — 맞았다·죽었다·레벨 올랐다
signal event(name: StringName, payload: Dictionary)

func open(_zone_id: String) -> void:
	pass

## 클라 → 서버 메시지. 전부 "요청"이고 판정은 저쪽이 다시 한다
func send(_message: StringName, _payload: Dictionary) -> void:
	pass

## 지금 상태. 화면은 이것만 보고 그린다
func snapshot() -> Dictionary:
	return {}

## 내 캐릭터 id
func my_id() -> String:
	return ""
