# アーキテクチャ

C.K.1.2 は「パーツを換装して戦う見下ろし型ロボットアクション」のオンライン対応ゲーム。
このドキュメントは設計の根幹（変えにくい決定）をまとめたもの。

## 設計の柱

1. **シミュレーションはシーンから切り離す**。`src/sim/` はノードもGodotの物理も使わない純粋なデータ＋算術。
   ソロ・サーバー・クライアント予測が同じコードを通るので、ネットコードが成立し、ヘッドレスでテストできる。
2. **サーバー権威**。オンラインでは専用サーバー（ヘッドレスGodot）が唯一の真実。クライアントは入力を送り、予測して見せる。
3. **データ駆動**。パーツ・武器・敵は `Resource`（`content/`）。コードを書かずに増やせる。
4. **ビューは薄く**。`src/game/` のノードは「描画するだけ」。状態を持たず、`RenderFrame` を受けて見た目を合わせる。
5. **テストできるものはテストする**。`tests/` がヘッドレスで走り、CIが回す。

## レイヤー

```
┌──────────── ui/ ────────────┐  メニュー・HUD・設定・チャット（コードで組むControl＋共通Theme）
├──────────── game/ ──────────┤  WorldView / RobotView / Camera / FX / Session（ソロ・オンライン）
├─────── net/ ─┬─ sim/ ───────┤  net: プロトコル・予測・補間・サーバー   sim: 決定論的ワールド
├──────────── data/ ──────────┤  RobotPart / RobotStats / Loadout / GameRules / PartRegistry
└──────────── core/ ──────────┘  Log / Cfg / Events / Settings / Save / Audio / I18n / Dev（autoload）
```

依存は下向きのみ。`sim/` と `data/` は `core/` のログ以外に依存しない。

## ディレクトリ

| パス | 内容 |
|---|---|
| `src/core/` | autoload とユーティリティ |
| `src/data/` | パーツ・性能値・ロードアウト・ルール |
| `src/sim/` | 決定論的シミュレーション（`SimWorld`、移動、戦闘、AI） |
| `src/net/` | ネットワーク（`Net`、スナップショット、予測、補間） |
| `src/game/` | シーン側（ビュー、カメラ、エフェクト、セッション） |
| `src/ui/` | UI |
| `content/` | パーツ等のデータ（`.tres`） |
| `scenes/` | シーン（薄い。ほとんどコードで組む） |
| `shaders/` | シェーダー |
| `tests/` | ヘッドレステスト（`run_tests.gd`） |
| `tools/` | 開発用スクリプト |
| `legacy/` | 旧 2D テンプレート（メインでは使わない） |

## シミュレーション（`src/sim/`）

- 固定 60Hz（`SimConfig.TICK_RATE`）。Godot の `_physics_process` から1回につき1ティック進める。
- 衝突は **自前**: 床 `y=0` ＋ 軸並行ボックス（`WorldGeometry`）。水平は円 vs AABB のスライド、
  垂直は重力とボックス天面への着地。低い遮蔽物はジャンプで乗り越えられる。
  Godot の物理サーバーは使わないので巻き戻し・再生が正確。
- 弾は物理ボディではなく **線分スイープ**（線分 vs AABB、線分 vs 円柱）。
- 乱数は **`DetRng`**（mulberry32）。エンジン版が違っても同じ結果になる。
- 座標系: Y 上、前方は `-Z`（`yaw=0`）。`SimMath.forward(yaw) = (-sin, 0, -cos)`。

### 1ティックの流れ（`SimWorld.step`）

入力適用（`PlayerSim.step`）→ 発砲 → 弾の移動と命中 → 敵AI → 拾得 → 死亡/リスポーン → ルール（敵スポーン）→ `tick++`。
発生したことは `SimEvent` として `events` に積む（SE・エフェクト・キルフィード・ネットワーク送信が購読する）。

### 性能値（`RobotStats`）

1. 既定値 → 2. 各パーツの `apply()` が基準値を書く → 3. `modifiers`（`StatModifier`）の ADD → 4. MULT。
バフ・パークは `modifiers` を足すだけでよい。

## ネットワーク（`src/net/`）

- トランスポート: `WebSocketMultiplayerPeer`（Web版ブラウザから接続できる唯一の現実解）。差し替え口は `NetTransport`。
- RPC は autoload `Net`（`/root/Net`）に集約。クライアント→サーバー: `c_hello` / `c_input` / `c_equip` / `c_chat` / `c_ping`。
  サーバー→クライアント: `s_welcome` / `s_reject` / `s_snapshot` / `s_events` / `s_pong`。
- **入力**: 9バイトに量子化（`PlayerInput`）。直近3件を重複送信し、サーバーは `seq` で重複排除。
  サーバーは1ティックにつき1入力しか消費しない（速度チート対策）。キューが溜まりすぎたら古いものを捨てる。
- **スナップショット**: 20Hz。受信者ごとに関連性（視界半径＋余白）で絞って量子化して送る（`SnapshotCodec`）。
  視界パーツが「見える範囲」と「サーバーが送る範囲」を兼ねる。
- **クライアント予測と補正**: ローカルは `PlayerSim.step` で即座に動かし、`ack_seq` 以降の入力を再生して補正。
  誤差は見た目だけ指数減衰で滑らかに寄せる（大きすぎればスナップ）。
- **補間**: 他者は ~100ms 遅らせて `InterpolationBuffer` で補間。
- **イベント**: 撃破・拾得・チャット等は信頼性チャンネル（`s_events`）。
- **検証**: プロトコル版とコンテンツハッシュ（`PartRegistry.content_hash`）を `c_hello` で照合。装備変更は所持品を検証。
- **開発支援**: `NetSim`（人工的な遅延・ジッタ・パケロス）を `Net` が内蔵。

## セッション（`src/game/`）

`GameSession`（基底）はビューから見た共通の口。実体は3つ:

- `LocalSession`: ソロ。ローカルの `SimWorld` が権威。
- `ClientSession`: オンライン。予測＋補間。
- サーバーは `GameServer`（ビューなし。`--server` で起動）。

ビューは毎フレーム `session.sample(alpha)` で `RenderFrame` を受け取って同期するだけ。

## 起動オプション（`Cfg`）

`godot --path . -- <args>`（`--` の後ろ）。環境変数 `CK_*` でも指定可。

| 引数 | 意味 |
|---|---|
| `--server` | 専用サーバーとして起動（ヘッドレス推奨） |
| `--port=8910` | サーバーのポート |
| `--max-players=16` | 最大人数 |
| `--seed=1234` | アリーナのシード |
| `--connect=ws://host:port` | 起動直後にサーバーへ接続 |
| `--solo` | メニューを飛ばしてソロ開始 |
| `--bot` | 入力をスクリプトで自動操作（結合テスト用） |
| `--latency=ms --jitter=ms --loss=0.05` | 人工ネットワーク劣化 |

## テスト

```
godot --headless --path . --import          # 初回（グローバルクラス登録）
godot --headless --path . -s res://tests/run_tests.gd
```

詳細は `tests/` を参照。

## 既知の制約

- 傾斜・段差は未対応（ボックスのみ）。
- WebSocket は TCP のため、パケットロス時に遅延が増える。`NetTransport` から WebRTC 等へ差し替えられる。
- Web版（HTTPSのGitHub Pages）から接続するサーバーは `wss://` が必須（リバースプロキシでTLS終端する。`docs/DEPLOYMENT.md`）。
- ラグ補償（過去位置に対する判定巻き戻し）は未実装。弾はサーバー上の実体として飛ぶ。
