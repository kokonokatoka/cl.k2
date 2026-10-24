extends Node
## 多言語対応（autoload: I18n）。翻訳表は strings.gd。画像や CSV のインポートを要しないので、ヘッドレスやCIでもそのまま動く。
## UI は `tr("ui.play")` のようにキーで引く。言語が変わると全ノードに NOTIFICATION_TRANSLATION_CHANGED が飛ぶ。

const LANGUAGES: PackedStringArray = ["en", "ja"]
const LANGUAGE_NAMES := {"en": "English", "ja": "日本語"}
const FALLBACK := "en"


func _ready() -> void:
	_register_translations()
	# 保存済みの言語設定は、読み込み後に Settings が set_language() で反映する
	set_language("auto")


## "auto"（OSの言語に合わせる）/ "en" / "ja"
func set_language(code: String) -> void:
	var resolved := code
	if code == "auto" or not LANGUAGES.has(code):
		var os_language := OS.get_locale_language()
		resolved = os_language if LANGUAGES.has(os_language) else FALLBACK
	if TranslationServer.get_locale() == resolved:
		return
	TranslationServer.set_locale(resolved)
	Events.language_changed.emit()


func current_language() -> String:
	return TranslationServer.get_locale().substr(0, 2)


func _register_translations() -> void:
	for index in LANGUAGES.size():
		var translation := Translation.new()
		translation.locale = LANGUAGES[index]
		for key: String in Strings.TABLE:
			translation.add_message(key, Strings.TABLE[key][index])
		TranslationServer.add_translation(translation)
