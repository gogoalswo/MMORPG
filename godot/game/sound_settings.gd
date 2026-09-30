class_name SoundSettings
extends RefCounted

## 소리 크기 — 전체(Master 버스) 볼륨을 0 ~ 100 으로 둔다 (2026-09-30 요청 "볼륨 조절 하는 기능 추가해").
##
## **판정이 아니라 기기 설정이다.** 그래서 캐릭터 저장(`save.gd`, 판정 값만)에 넣지 않고
## `user://settings.cfg` 에 따로 둔다 — 서버에 붙어도 기기마다 제 소리 크기를 쓴다.
## 웹에서는 `user://` 가 IndexedDB 라 브라우저마다 따로 남는다.
##
## 0 은 끔 — 버스를 음소거한다 (`linear_to_db(0)` 은 -inf 라 따로 막는다).

const PATH := "user://settings.cfg"
## 처음 값 — 한 번도 안 고른 기기는 이 크기로 시작한다. 100 이던 것을 70 으로 줄였다 (2026-09-30 요청)
const DEFAULT := 70
const STEP := 10
const MAX := 100


## 저장된 값 (없으면 `DEFAULT`)
static func volume() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return DEFAULT
	return clampi(int(cfg.get_value("sound", "volume", DEFAULT)), 0, MAX)


## 잘라서 버스에 걸고 저장한다. 건 값을 돌려준다
static func set_volume(value: int) -> int:
	var v := clampi(value, 0, MAX)
	apply(v)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("sound", "volume", v)
	cfg.save(PATH)
	return v


## 버스에만 건다 (게임을 켤 때 저장된 값으로 한 번)
static func apply(value: int) -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, value <= 0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 1) / float(MAX)))
