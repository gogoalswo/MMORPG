class_name CameraRig
extends Camera3D

## 고정각 쿼터뷰 카메라. 웹 클라의 game/cameraRig.ts 와 같은 값이다.
##
## **좁은 FOV(30도)로 원근을 죽여서 아이소메트릭 느낌을 내는 게 핵심이다.**
## 완전한 직교 투영은 입체감이 사라지고, 넓은 FOV(고도 기본 75)는 원근이 살아나
## 지평선까지 보인다 — 2026-09-17 에 "너무 아래서 바라본다" 고 지적받은 것이 이것이다.
##
## Q/E 회전과 줌은 아직 안 옮겼다. 웹 쪽에는 있다.

## 보는 방향 — 45도에서 내려다본다
const YAW := PI / 4
const PITCH := 42.0

## 초점까지의 거리. FOV 30 과 맞물려 화면 세로가 약 21m 잡힌다
const DISTANCE := 40.0

## **캐릭터 원점은 발밑이다.** 가슴 높이를 봐야 가까이 당겨도 머리가 안 잘린다
const FOCUS_HEIGHT := 1.0

var _focus := Vector3.ZERO


func _init() -> void:
	fov = 30.0
	near = 1.0
	far = 400.0
	current = true


## 지수 감쇠 스무딩 — 프레임레이트에 독립적이다.
## snap 은 존을 옮겼을 때처럼 보간 없이 곧바로 자리잡아야 할 때 쓴다
func follow(target: Vector3, delta: float, snap: bool = false) -> void:
	var desired := Vector3(target.x, target.y + FOCUS_HEIGHT, target.z)
	_focus = desired if snap else _focus.lerp(desired, 1.0 - exp(-11.0 * delta))

	var pitch := deg_to_rad(PITCH)
	var offset := Vector3(
		cos(pitch) * sin(YAW),
		sin(pitch),
		cos(pitch) * cos(YAW)
	) * DISTANCE
	position = _focus + offset
	look_at(_focus, Vector3.UP)
