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

## 초점까지의 거리.
##
## 웹 클라는 40 인데 **1.5배 가깝게** 당겼다 (2026-09-17 요청). FOV 30 과 맞물려
## 화면 세로가 21.4m → 14.3m 이 된다. 각도(피치 42·요 45)는 그대로다
const DISTANCE := 40.0 / 1.5

## **캐릭터 원점은 발밑이다.** 가슴 높이를 봐야 가까이 당겨도 머리가 안 잘린다
const FOCUS_HEIGHT := 1.0

var _focus := Vector3.ZERO
## 흔들림 — 세기(m), 남은 시간, 처음 길이, 흐른 시간
var _shake := 0.0
var _shake_left := 0.0
var _shake_time := 0.0
var _shake_t := 0.0


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
	_apply_shake(delta)


## 화면을 흔든다 — `strength`(m) 만큼 `time`(초) 동안 떨다 잦아든다.
## 이미 흔들리는 중이면 센 쪽을 남긴다 (겹쳐 더하면 연타에 화면이 날아간다)
func shake(strength: float, time: float) -> void:
	if strength >= _shake * (_shake_left / maxf(_shake_time, 1e-4)):
		_shake = strength
		_shake_time = time
		_shake_left = time
		_shake_t = 0.0


## **자리만 옮기고 각은 그대로다.** 기울이면 쿼터뷰가 흔들려 멀미가 난다.
## 화면의 가로·세로(카메라 로컬 x·y)로만 떨고, 남은 시간의 제곱으로 잦아든다 —
## 선형으로 줄이면 끝에서 힘없이 흐느적거린다. 떨림은 난수가 아니라 서로
## 어긋난 사인 둘이다 — 프레임마다 난수면 fps 에 따라 결이 달라진다
func _apply_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	_shake_t += delta
	var k := _shake_left / _shake_time
	var amp := _shake * k * k
	var sx := sin(_shake_t * 53.0) * amp
	var sy := sin(_shake_t * 67.0 + 1.3) * amp
	position += global_transform.basis.x * sx + global_transform.basis.y * sy
