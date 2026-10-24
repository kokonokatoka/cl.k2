# cl.k2 - パーツ換装 × 見下ろし型ロボットアクション × サーバー権威オンライン

[![Deploy to GitHub Pages](https://github.com/kokonokatoka/cl.k2/actions/workflows/deploy.yml/badge.svg)](https://github.com/kokonokatoka/cl.k2/actions/workflows/deploy.yml)

🌐 **Webブラウザですぐ遊ぶ (GitHub Pages)**:  
👉 **[https://kokonokatoka.github.io/cl.k2/](https://kokonokatoka.github.io/cl.k2/)**

---

## 概要

**cl.k2** は、Godot 4（GL Compatibility / Web Export）で開発された、**「パーツ換装 × 見下ろし型ロボットアクション × サーバー権威型オンラインマルチプレイヤー」** のゲームプロジェクトです。

- **メイン起動シーン**: `res://scenes/boot.tscn`
- **サーバー権威型ネットコード**: 入力収集・予測・ロールバック・状態同期基盤
- **詳細設計ドキュメント**: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **開発・技術引き継ぎ書**: [`docs/HANDOVER.md`](docs/HANDOVER.md)

---

## 主な特徴とアーキテクチャ

1. **シミュレーション・コア (`src/sim/`)**
   - 決定論的シミュレーション構造、ワールド生成、エンティティ管理
2. **ネットコード (`src/netcode/`)**
   - サーバー権威アーキテクチャ、差分スナップショット、入力予測とリコンシリエーション
3. **データ＆コンテンツシステム (`content/`, `src/data/`)**
   - パーツ定義（ヘッド・ボディ・アーム・レッグ・武器）
   - 敵モブ定義（スカウト、ガンナー、ブルート）
4. **UI・HUD (`src/ui/`)**
   - レーダー、ステータスバー、視界オーバーレイ、チャットボックス、設定メニュー
5. **テストスイート (`tests/`)**
   - ユニットテスト、シミュレーション検証、E2Eネットコードテスト
6. **Web CI/CD 自動デプロイ (`.github/workflows/deploy.yml`)**
   - `main` ブランチへのプッシュで自動的に Godot 4 Web ビルドが行われ、GitHub Pages にデプロイされます。

---

## 開発環境 & テスト実行

- **Godot バージョン**: Godot 4.3+ (GL Compatibility / Web)
- **テスト実行 (Headless)**:
  ```bash
  godot --headless --path . -s res://tests/run_tests.gd
  ```
- **ソロプレイ (目視確認)**:
  ```bash
  godot --path . -- --solo --autoplay --seed=11
  ```
