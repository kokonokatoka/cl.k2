class_name ClockSync
extends RefCounted
## サーバー時刻とローカル時刻の差の推定。スナップショットが届くたびに更新する。
## 「サーバー時刻 - 到着時のローカル時刻」は、通信が遅れたぶん小さくなる。
## だから、大きい値（遅れの小さい通信）には素早く追従し、小さい値にはゆっくりしか寄らない。

const RISE_RATE := 0.25
const FALL_RATE := 0.02

var offset: float = 0.0
var _initialized: bool = false


func observe(server_time: float, local_time: float) -> void:
	var sample := server_time - local_time
	if not _initialized:
		offset = sample
		_initialized = true
	elif sample > offset:
		offset = lerpf(offset, sample, RISE_RATE)
	else:
		offset = lerpf(offset, sample, FALL_RATE)


func is_ready() -> bool:
	return _initialized


func server_time(local_time: float) -> float:
	return local_time + offset
