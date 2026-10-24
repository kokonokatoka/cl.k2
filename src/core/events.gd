extends Node
## 疎結合のためのグローバルシグナル（autoload: Events）。
## ここに足すのは「無関係な複数のシステムが聞きたいもの」だけ。1対1の関係は直接シグナルを使う。

enum ToastKind { INFO, GOOD, WARN, BAD }

## 設定が変わった。key は "audio/master" のような形式
signal settings_changed(key: String)
signal language_changed
## 画面右上などに出す短い通知
signal toast(text: String, kind: ToastKind)
signal profile_changed
## セッション（ソロ/オンライン）の開始と終了
signal session_started
signal session_ended(reason: String)
