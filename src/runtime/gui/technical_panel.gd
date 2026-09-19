class_name TTechnicalPanel
extends Control
## The HUD's technical panel (Graphics/GUI/HUD/TechnicalPanel/TechnicalPanel.dui, style core_game.scss
## .technical-panel): top left, 158 x 34 with padding 10, "<hud.FPS> FPS", a ping icon (good < 200 ms, neutral < 500,
## bad), "<hud.Ping> ms"; text Proza Libre 500 (root FontWeight) in $font-color-black ($EF404040). The HUD refreshes
## FPS / Ping every frame from GFXD.FPS and ClientGame.Ping (TClientGUIComponent, BaseConflict.EntityComponents.Client
## .pas:1877). Visible when coGameplayShowTechnicalPanel is set (hud.IsTechnicalPanelVisible) and not in capture mode.
## Port: a stand-in until the GUI system (phase 7) draws the .dui; sizes are the stylesheet's pixels in the 1920 x 1080
## base the port's UI stretches from, the font size (the 14 px line the padding leaves) is not taken from the GUI
## engine's font metrics yet.

const C = preload("res://src/runtime/dws/dws_const.gd")
const FONT_PATH := "res://assets/graphics/fonts/prozalibre-medium.ttf"
const ICON_ROOT := "res://assets/graphics/gui/hud/technicalpanel/"
const PADDING := 10
const FONT_COLOR := Color(0x40 / 255.0, 0x40 / 255.0, 0x40 / 255.0, 0xEF / 255.0)

## hud.Ping's source; null = no game (the panel shows the FPS and 0 ms)
var PingSource: Callable
var _fps_label: Label
var _ping_label: Label
var _ping_icon: TextureRect
var _icons := {}


func _init() -> void:
	name = "TechnicalPanel"
	position = Vector2.ZERO
	size = Vector2(158, 34)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # MouseEvents : pePass
	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_fps_label = _label(Vector2(0, 0), Vector2(60, 14), font)
	_fps_label.text = "59 FPS"  # DefaultText
	_ping_icon = TextureRect.new()
	_ping_icon.position = Vector2(PADDING + 62, PADDING + 2)
	_ping_icon.size = Vector2(10, 14 * 0.6)
	_ping_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ping_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_ping_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ping_icon)
	for state in ["good", "neutral", "bad"]:
		var path := ICON_ROOT + "pingsymbol%s.png" % state
		_icons[state] = load(path) if ResourceLoader.exists(path) else null
	_ping_label = _label(Vector2(78, 0), Vector2(80, 14), font)


func _label(pos: Vector2, label_size: Vector2, font: Font) -> Label:
	var label := Label.new()
	label.position = pos + Vector2(PADDING, PADDING)
	label.size = label_size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", FONT_COLOR)
	add_child(label)
	return label


func _process(_delta: float) -> void:
	GFXD.FPSFrameTick()
	visible = TOptionManager.GetBooleanOption(C.coGameplayShowTechnicalPanel)
	var ping := int(PingSource.call()) if PingSource.is_valid() else 0
	_fps_label.text = "%d FPS" % GFXD.FPS()
	_ping_label.text = "%d ms" % ping
	_ping_icon.texture = _icons["good" if ping < 200 else ("neutral" if ping < 500 else "bad")]
