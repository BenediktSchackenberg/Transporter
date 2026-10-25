class_name ProfitChart
extends Control
## Linienchart: Gewinn- oder Liquiditaetsentwicklung aller Firmen ueber die Spielzeit.

var sim: Simulation
var series := 1          # 1 = Gewinn, 2 = Bargeld


func _draw() -> void:
	if sim == null:
		return
	var font := UITheme.font
	draw_rect(Rect2(Vector2.ZERO, size), Color("#15161f"))
	var pad := Vector2(52, 14)
	var area := Rect2(pad, size - pad - Vector2(10, 22))
	var t_max := maxf(60.0, sim.game_min)
	var lo := 0.0
	var hi := 1000.0
	for c in sim.companies:
		for h in c.ledger.history:
			lo = minf(lo, h[series])
			hi = maxf(hi, h[series])
	var span := hi - lo
	lo -= span * 0.05
	hi += span * 0.05
	var to_px := func(t: float, v: float) -> Vector2:
		return Vector2(area.position.x + t / t_max * area.size.x, area.end.y - (v - lo) / (hi - lo) * area.size.y)
	for k in 5:
		var v := lo + (hi - lo) * k / 4.0
		var y: float = to_px.call(0.0, v).y
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.07))
		draw_string(font, Vector2(2, y + 4), _short(v), HORIZONTAL_ALIGNMENT_LEFT, 48, 12, UITheme.MUTED)
	if lo < 0.0 and hi > 0.0:
		var y0: float = to_px.call(0.0, 0.0).y
		draw_line(Vector2(area.position.x, y0), Vector2(area.end.x, y0), Color(1, 1, 1, 0.35), 1.0)
	for c in sim.companies:
		var pts := PackedVector2Array()
		for h in c.ledger.history:
			pts.append(to_px.call(h[0], h[series]))
		if pts.size() >= 2:
			draw_polyline(pts, c.color, 2.0)
	draw_string(font, Vector2(area.position.x, size.y - 4), "Spielzeit →  (%s)" % Catalog.game_minutes_to_text(sim.game_min),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.MUTED)


static func _short(v: float) -> String:
	if absf(v) >= 1000.0:
		return "%.0fk" % (v / 1000.0)
	return "%.0f" % v
