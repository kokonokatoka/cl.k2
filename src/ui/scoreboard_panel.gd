class_name ScoreboardPanel
extends CanvasLayer
## 戦績表。scoreboard アクション（Tab）を押している間だけ出る。

const REFRESH_SECONDS := 0.25

var _session: GameSession
var _panel: PanelContainer
var _grid: GridContainer
var _title: Label
var _timer: float = 0.0


func _ready() -> void:
	layer = 12
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 18)
	box.add_child(_grid)
	_panel.visible = false
	_retranslate()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _title != null:
		_retranslate()


func bind(session: GameSession) -> void:
	_session = session


func _process(delta: float) -> void:
	var show_panel := _session != null and Input.is_action_pressed("scoreboard")
	_panel.visible = show_panel
	if not show_panel:
		_timer = 0.0
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_SECONDS
		_refresh()


func _refresh() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for header in ["#", tr("score.name"), tr("hud.score"), tr("hud.kills"), tr("hud.deaths"), tr("score.ping")]:
		var label := Label.new()
		label.text = header
		label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		label.add_theme_font_size_override("font_size", 13)
		_grid.add_child(label)
	var rank := 0
	for row in _session.scoreboard():
		rank += 1
		var color: Color = UiTheme.ACCENT if row["local"] else UiTheme.TEXT
		var cells: Array = [str(rank), row["name"], str(row["score"]), str(row["kills"]), str(row["deaths"]),
			"-" if int(row["ping"]) <= 0 else "%d" % int(row["ping"])]
		for i in cells.size():
			var label := Label.new()
			label.text = cells[i]
			label.add_theme_color_override("font_color", color)
			if i == 1:
				label.custom_minimum_size.x = 190
				label.clip_text = true
			_grid.add_child(label)


func _retranslate() -> void:
	_title.text = tr("score.title")
