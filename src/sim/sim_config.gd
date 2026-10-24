class_name SimConfig
extends RefCounted
## シミュレーション全体で共有する定数。サーバーとクライアントで必ず同じ値にする（変えたら content_hash と併せて版を上げる）。

const TICK_RATE: int = 60
const DT: float = 1.0 / 60.0

const GRAVITY: float = 19.6
## この高さまでの段差は乗り越える／乗れる
const STEP_HEIGHT: float = 0.3

const PLAYER_RADIUS: float = 0.4
## 足元から胴体上端までの高さ（ride_height を足すと全高）
const PLAYER_HEIGHT: float = 1.1
## 足元から銃口までの高さ（ride_height を足す）と、前方へのずらし量
const MUZZLE_HEIGHT: float = 0.75
const MUZZLE_FORWARD: float = 0.6

const PICKUP_RADIUS: float = 1.1
const PICKUP_HEIGHT: float = 2.0

## 入力キューの上限。これを超えたら古い入力を捨てる（速度チート・遅延の累積対策）
const INPUT_QUEUE_MAX: int = 8
## このティック数だけ入力が来なければ、最後の入力を繰り返さず中立にする
const INPUT_REPEAT_MAX: int = 6

const MAX_EVENTS_PER_TICK: int = 128
