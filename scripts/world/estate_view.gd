class_name EstateView
extends Node2D
## Firmengrundstuecke und Betriebseinrichtungen (isometrisch): Grundstuecksgrenze in Firmenfarbe, Namensschild, Einrichtungen
## (Baustelle halbtransparent mit Absperrung und Fortschrittsbalken), Ausbaustufe. Liest nur aus Simulation.estate.

var sim: Simulation
var view: CityView
var _plots := {}        # Grundstueck -> {node, owner, warn}
var _facs := {}         # Einrichtungs-ID -> {node, sprites, masks, site, bar_bg, bar, level, lit}


func setup(simulation: Simulation, city_view: CityView) -> void:
	sim = simulation
	view = city_view
	y_sort_enabled = true
	for id in sim.estate.plots:
		var n := Node2D.new()
		n.z_index = -9         # flach auf dem Boden: ueber den Kacheln (-10), unter allen Objekten
		add_child(n)
		_plots[id] = {"node": n, "owner": -2}
	update_view(true)


func update_view(blink_on: bool) -> void:
	for id in _plots:
		var p: Dictionary = sim.estate.plots[id]
		if _plots[id].owner != p.owner:
			_draw_plot(id)
		# Betriebsstoerung (Sabotage/Ereignis): blinkende Warnung ueber dem Hof
		var warn: Sprite2D = _plots[id].get("warn")
		var disrupted: bool = p.owner >= 0 and int(p.parent) < 0 and sim.company(p.owner).is_disrupted(sim.game_min)
		if disrupted and warn == null:
			warn = Sprite2D.new()
			warn.texture = view.tex("i_warn")
			warn.scale = Vector2(2, 2)
			warn.position = Iso.to_screen(Vector2(p.x * 32.0 + p.w * 16.0, p.y * 32.0 + p.h * 16.0)) + Vector2(0, -50)
			warn.z_index = 40
			_plots[id].node.add_child(warn)
			_plots[id]["warn"] = warn
		elif not disrupted and warn != null:
			warn.queue_free()
			_plots[id].erase("warn")
		elif warn != null:
			warn.visible = blink_on
	for fid in _facs.keys():
		if not sim.estate.facilities.has(fid):
			_remove_fac(fid)
	for f in sim.estate.facilities.values():
		if not _facs.has(f.id):
			_add_fac(f)
		_update_fac(f, blink_on)


func _wp(x: float, y: float) -> Vector2:
	return Iso.to_screen(Vector2(x, y))


func _draw_plot(id: int) -> void:
	var p: Dictionary = sim.estate.plots[id]
	var entry: Dictionary = _plots[id]
	var n: Node2D = entry.node
	for ch in n.get_children():
		ch.queue_free()
	entry.erase("warn")
	entry.owner = p.owner
	var col := Color(0.75, 0.75, 0.7, 0.8) if p.owner < 0 else sim.company(p.owner).color
	var x0: float = p.x * 32.0
	var y0: float = p.y * 32.0
	var x1: float = x0 + p.w * 32.0
	var y1: float = y0 + p.h * 32.0
	var up := Vector2(0, -2)
	var ring := PackedVector2Array([_wp(x0 + 1, y0 + 1) + up, _wp(x1 - 1, y0 + 1) + up, _wp(x1 - 1, y1 - 1) + up, _wp(x0 + 1, y1 - 1) + up, _wp(x0 + 1, y0 + 1) + up])
	var fill := Polygon2D.new()
	fill.polygon = ring.slice(0, 4)
	fill.color = Color(col, 0.10)
	n.add_child(fill)
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = col
	line.points = ring
	n.add_child(line)
	if int(p.parent) < 0:   # Erweiterungen nutzen die Einfahrt des Hauptgrundstuecks
		var ex: float = int(p.entrance[0]) * 32.0
		var ey: float = (int(p.entrance[1]) + 1) * 32.0
		var gate := Polygon2D.new()
		gate.polygon = PackedVector2Array([_wp(ex, ey - 6) + up, _wp(ex + 32, ey - 6) + up, _wp(ex + 32, ey) + up, _wp(ex, ey) + up])
		gate.color = Color(0.9, 0.8, 0.3, 0.7)
		n.add_child(gate)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.1))
	label.add_theme_constant_override("outline_size", 4)
	label.position = _wp(x0, y0) + Vector2(-60, -22)
	label.z_index = 40
	if p.owner >= 0:
		label.text = sim.company(p.owner).company_name + ("" if int(p.parent) < 0 else " (Erweiterung)")
		label.add_theme_color_override("font_color", col.lightened(0.3))
	else:
		label.text = "ZU VERKAUFEN / PACHTEN"
		label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	n.add_child(label)


func _key(f: Dictionary) -> String:
	var spec: Dictionary = Estate.FACILITIES[f.typ]
	var rotated := int(f.rot) == 90 and int(spec.w) != int(spec.h)
	return "fac_%s%s" % [f.typ, "_r" if rotated else ""]


func _add_fac(f: Dictionary) -> void:
	var key := _key(f)
	var info: Dictionary = view.man.facilities[key]
	var w := int(f.w)
	var h := int(f.h)
	var origin := Iso.tile_origin(Vector2i(int(f.x), int(f.y)))
	var holder := Node2D.new()
	add_child(holder)
	var sprites := view.add_iso_object(holder, key, info, origin, w, h, true, key + "_mask")
	var masks: Array = []
	for s in sprites:
		for ch in s.get_children():
			if ch.has_meta("mask"):
				masks.append(ch)
	var tint: Color = sim.company(int(f.owner)).color if int(f.owner) >= 0 else Color(0.6, 0.6, 0.6)
	for m in masks:
		m.modulate = tint
	var site := Node2D.new()   # Absperrung waehrend des Baus: Gitterelemente entlang des Umrisses
	for y in h:
		for x in w:
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				var fence := Sprite2D.new()
				fence.texture = view.tex("fac_site")
				fence.centered = false
				fence.offset = -view.pivot_of("fac_site")
				fence.position = Iso.to_screen(Vector2((int(f.x) + x) * 32.0 + 16.0, (int(f.y) + y) * 32.0 + 16.0))
				fence.modulate.a = 0.7
				site.add_child(fence)
	site.z_index = 3
	holder.add_child(site)
	var top := origin + Iso.to_screen(Vector2(w * 16.0, h * 16.0)) + Vector2(0, -2.0 * float(info.get("height", 40)) - 10.0)
	var ui := Node2D.new()
	ui.position = top
	ui.z_index = 41
	holder.add_child(ui)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.1, 0.1, 0.14, 0.85)
	bar_bg.size = Vector2(64, 6)
	bar_bg.position = Vector2(-32, 0)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.color = Color(0.95, 0.7, 0.2)
	bar.position = Vector2(1, 1)
	bar.size = Vector2(0, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar)
	ui.add_child(bar_bg)
	var level := Label.new()
	level.add_theme_font_size_override("font_size", 12)
	level.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	level.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.1))
	level.add_theme_constant_override("outline_size", 4)
	level.position = Vector2(-20, 6)
	ui.add_child(level)
	var lit: Sprite2D = null
	if info.lit:
		lit = Sprite2D.new()
		lit.centered = false
		lit.texture = view.tex(key + "_lit")
		lit.position = origin - Vector2(info.anchor[0], info.anchor[1])
		lit.modulate.a = 0.0
		view.lights_layer.add_child(lit)
	_facs[f.id] = {"node": holder, "sprites": sprites, "masks": masks, "site": site, "bar_bg": bar_bg, "bar": bar, "level": level, "lit": lit}


func _remove_fac(fid: String) -> void:
	var e: Dictionary = _facs[fid]
	e.node.queue_free()
	if e.lit:
		e.lit.queue_free()
	_facs.erase(fid)


func _update_fac(f: Dictionary, blink_on: bool) -> void:
	var e: Dictionary = _facs[f.id]
	var building: bool = f.status == "im_bau"
	var waiting_material := building and int(f.mat) < int(f.mat_needed)
	var a := (0.4 + 0.5 * float(f.progress)) if building else 1.0
	var wear := BuildingCare.tint(float(f.get("condition", 100.0)))
	for s in e.sprites:
		s.modulate = Color(wear.r, wear.g, wear.b, a)
	e.site.visible = building
	e.bar_bg.visible = f.status in ["im_bau", "ausbau"]
	e.bar.size.x = (e.bar_bg.size.x - 2) * float(f.progress)
	e.bar.color = Color(0.85, 0.3, 0.25) if waiting_material and not blink_on else Color(0.95, 0.7, 0.2)
	var stars := "★".repeat(int(f.level)) if int(Estate.FACILITIES[f.typ].max_level) > 1 else ""
	e.level.text = stars
	if e.lit:
		e.lit.modulate.a = 0.0 if building else view.night_factor
