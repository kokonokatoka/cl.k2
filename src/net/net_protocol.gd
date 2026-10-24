class_name NetProtocol
extends RefCounted
## ネットワークの取り決め。サーバーとクライアントで同じ値でなければならない定数を集める。

## 通信の仕様を変えたら上げる。違う版のクライアントは接続時に断られる
const VERSION: int = 1

const DEFAULT_PORT: int = 8910
## スナップショットの送信間隔（ティック数）。60Hz ÷ 3 = 20Hz
const SNAPSHOT_INTERVAL: int = 3
## 入力は直近この数だけまとめて送る（取りこぼしても次の通信で補える）
const INPUT_REDUNDANCY: int = 3
## 他のプレイヤーを描画する時刻の遅れ[秒]（補間のため）
const INTERPOLATION_DELAY: float = 0.1
const MAX_NAME_LENGTH: int = 16
const MAX_CHAT_LENGTH: int = 120
