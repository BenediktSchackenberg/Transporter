class_name UITheme
extends RefCounted
## Einheitliches Retro-UI-Theme mit Pixel-Schrift (Pixelify Sans, OFL) und flachen Panels.

const BG := Color("#1c1d2b")
const PANEL := Color("#262838")
const PANEL_LIGHT := Color("#33364a")
const BORDER := Color("#0e0f17")
const ACCENT := Color("#f2c14e")
const TEXT := Color("#ece8dc")
const MUTED := Color("#9a98a8")
const GOOD := Color("#6fd08c")
const BAD := Color("#ff6b5e")
const WARN := Color("#ffb347")

static var _theme: Theme
static var font: FontFile


static func get_theme() -> Theme:
	if _theme:
		return _theme
	font = load("res://assets/fonts/PixelifySans.ttf")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 16
	var panel := box(PANEL, BORDER, 2, 3)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, BORDER, 2, 2))
	t.set_stylebox("hover", "Button", box(PANEL_LIGHT.lightened(0.15), ACCENT, 2, 2))
	t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.3), ACCENT, 2, 2))
	t.set_stylebox("disabled", "Button", box(PANEL, BORDER, 2, 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "LineEdit", box(Color("#15161f"), BORDER, 2, 2))
	t.set_stylebox("focus", "LineEdit", box(Color("#15161f"), ACCENT, 2, 2))
	t.set_stylebox("normal", "OptionButton", box(PANEL_LIGHT, BORDER, 2, 2))
	t.set_stylebox("hover", "OptionButton", box(PANEL_LIGHT.lightened(0.15), ACCENT, 2, 2))
	t.set_stylebox("normal", "SpinBox", box(Color("#15161f"), BORDER, 2, 2))
	t.set_stylebox("panel", "TabContainer", box(PANEL, BORDER, 2, 3))
	t.set_stylebox("tab_selected", "TabContainer", box(PANEL, ACCENT, 2, 2))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color("#1a1b27"), BORDER, 2, 2))
	t.set_stylebox("tab_hovered", "TabContainer", box(PANEL_LIGHT, BORDER, 2, 2))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "Tree", box(Color("#1a1b27"), BORDER, 1, 2))
	t.set_color("font_color", "Tree", TEXT)
	t.set_stylebox("panel", "PopupMenu", box(PANEL_LIGHT, BORDER, 2, 2))
	t.set_stylebox("panel", "TooltipPanel", box(Color("#101119"), ACCENT, 1, 4))
	_theme = t
	return t


## Unternehmer-Portraet aus dem 2x2-Atlas (assets/portraits/portraits.png), Index = Avatar % 4.
static func portrait(avatar_style: int) -> AtlasTexture:
	var atlas: Texture2D = load("res://assets/portraits/portraits.png")
	var half := atlas.get_width() / 2.0
	var i := avatar_style % 4
	var t := AtlasTexture.new()
	t.atlas = atlas
	t.region = Rect2((i % 2) * half, (i / 2) * half, half, half)
	return t


static func box(bg: Color, border: Color, bw: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 2)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = margin + 3
	s.content_margin_right = margin + 3
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


## Freundlicher Knopf in einer Farbe (Bedienleisten): rund, mit Hover-Aufhellung und Druckeffekt.
static func color_button(b: Button, base: Color, size: int = 17) -> void:
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", box(base, base.darkened(0.45), 2, 5))
	b.add_theme_stylebox_override("hover", box(base.lightened(0.18), Color.WHITE.darkened(0.15), 2, 5))
	b.add_theme_stylebox_override("pressed", box(base.darkened(0.25), ACCENT, 2, 6))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
