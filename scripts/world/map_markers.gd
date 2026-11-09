class_name MapMarkers
extends Node2D
## Ereignismarker auf der Karte (UI-Neugestaltung): wichtige Ereignisse der letzten Spielstunden als Symbol am Ort, verblassen mit dem
## Alter und verschwinden; Hervorhebung beim Kamerasprung aus der Leitstelle (pulsierender Ring, 4 Sekunden). Hoechstens 24 Marker.

var sim
var _items: Array = []
var _hl_cell := Vector2i(-9999, -9999)
var _hl_t := 0.0
var _poll := 0.0
var _t := 0.0


func _ready() -> void:
	z_index = 50


func highlight(cell: Vector2i) -> void:
	_hl_cell = cell
	_hl_t = 4.0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_poll -= delta
	if _hl_t > 0.0:
		_hl_t -= delta
		queue_redraw()
	if _poll <= 0.0 and sim != null and sim.center != null:
		_poll = 1.0
		_items = sim.center.markers(12.0)
		queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var f: Font = ThemeDB.fallback_font
	for e in _items:
		var p := Iso.to_screen(sim.city.tile_center(Vector2i(int(e.cell[0]), int(e.cell[1])))) + Vector2(0, -70)
		var age := clampf((sim.game_min - float(e.t_last)) / 60.0, 0.0, 1.0)   # verblasst ueber 12 Spielstunden
		var col := Color(EventCenter.CATS.get(str(e.cat), EventCenter.CATS.normal).color)
		col.a = 1.0 - age * 0.7
		draw_circle(p, 17.0, Color(0.08, 0.08, 0.12, col.a * 0.85))
		draw_arc(p, 17.0, 0.0, TAU, 24, col, 3.0)
		var icon: String = EventCenter.CATS.get(str(e.cat), EventCenter.CATS.normal).icon
		draw_string(f, p + Vector2(-7, 7), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
	if _hl_t > 0.0:
		var c := Iso.to_screen(sim.city.tile_center(_hl_cell))
		var r := 40.0 + 18.0 * sin(_t * 6.0)
		draw_arc(c, r, 0.0, TAU, 40, Color(1.0, 0.85, 0.3, clampf(_hl_t / 4.0, 0.0, 1.0)), 5.0)
		draw_arc(c, r * 0.6, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, clampf(_hl_t / 4.0, 0.0, 1.0) * 0.7), 3.0)
