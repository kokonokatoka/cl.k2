class_name UiTheme
extends RefCounted
## 全 UI 共通のテーマ。暗いガラス調のパネルとオレンジのアクセント。コードで組むので色はここだけで変えられる。

const ACCENT := Color(0.95, 0.6, 0.22)
const ACCENT_DIM := Color(0.62, 0.4, 0.17)
const PANEL_BG := Color(0.06, 0.07, 0.1, 0.88)
const PANEL_BORDER := Color(0.22, 0.25, 0.32)
const TEXT := Color(0.9, 0.92, 0.96)
const TEXT_DIM := Color(0.6, 0.64, 0.72)
const GOOD := Color(0.45, 0.9, 0.55)
const BAD := Color(1.0, 0.4, 0.4)
const HEALTH := Color(0.9, 0.3, 0.35)
const ENERGY := Color(0.3, 0.8, 1.0)

const FONT_PATH := "res://assets/fonts/BIZUDGothic-Regular.ttf"

static var _theme: Theme
static var _font: Font


static func get_font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_PATH):
			_font = load(FONT_PATH) as Font
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func panel_style(background: Color = PANEL_BG, border: Color = PANEL_BORDER, radius: int = 8, margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin * 0.8
	style.content_margin_bottom = margin * 0.8
	return style


static func _build() -> Theme:
	var theme := Theme.new()
	var font := get_font()
	if font != null:
		theme.default_font = font
	theme.default_font_size = 16

	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "Panel", panel_style())

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.75))
	theme.set_constant("outline_size", "Label", 4)

	var normal := panel_style(Color(0.1, 0.12, 0.17, 0.95), PANEL_BORDER, 6, 14)
	var hover := panel_style(Color(0.16, 0.19, 0.26, 0.98), ACCENT_DIM, 6, 14)
	var pressed := panel_style(Color(0.24, 0.17, 0.1, 1.0), ACCENT, 6, 14)
	var disabled := panel_style(Color(0.08, 0.09, 0.12, 0.7), Color(0.16, 0.18, 0.22), 6, 14)
	var focus := panel_style(Color(0, 0, 0, 0), ACCENT, 6, 14)
	focus.set_border_width_all(2)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color(1, 1, 1))
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)

	for control in ["CheckBox", "CheckButton"]:
		theme.set_color("font_color", control, TEXT)
		theme.set_color("font_hover_color", control, Color(1, 1, 1))
		theme.set_stylebox("focus", control, focus)

	var line_edit := panel_style(Color(0.04, 0.05, 0.08, 0.95), PANEL_BORDER, 6, 10)
	var line_edit_focus := panel_style(Color(0.04, 0.05, 0.08, 0.95), ACCENT, 6, 10)
	theme.set_stylebox("normal", "LineEdit", line_edit)
	theme.set_stylebox("focus", "LineEdit", line_edit_focus)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)

	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.12, 0.14, 0.2)
	slider_bg.set_corner_radius_all(3)
	slider_bg.content_margin_top = 3
	slider_bg.content_margin_bottom = 3
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = ACCENT
	slider_fill.set_corner_radius_all(3)
	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	var option_normal := panel_style(Color(0.1, 0.12, 0.17, 0.95), PANEL_BORDER, 6, 10)
	theme.set_stylebox("normal", "OptionButton", option_normal)
	theme.set_stylebox("hover", "OptionButton", hover)
	theme.set_stylebox("pressed", "OptionButton", pressed)
	theme.set_stylebox("focus", "OptionButton", focus)

	theme.set_stylebox("panel", "PopupMenu", panel_style(Color(0.07, 0.08, 0.12, 0.98), PANEL_BORDER, 6, 6))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))

	var separator := StyleBoxLine.new()
	separator.color = PANEL_BORDER
	theme.set_stylebox("separator", "HSeparator", separator)
	return theme


## 数値バー（体力・エネルギー）用の背景/塗りのスタイル
static func bar_background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.06, 0.85)
	style.border_color = Color(0.25, 0.28, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style


static func bar_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style
