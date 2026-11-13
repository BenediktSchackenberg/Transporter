class_name StoneView
extends Node2D
## Auftrag 23: sichtbare Steinbauten und Stein-Kreationen der Unternehmer (sw_<motiv> als Requisit,
## auf eigenen Grundstuecken). Geplant/im Bau: Bauzaun am Rand; fertig: das Werk. An bemalte Werke
## werden zwei Farbmasken gelegt (Grundton + Akzent in der Firma- bzw. Werkfarbe); unbemalt bleibt der
## Stein naturfarben (Farbbild mit eingebackenen Grauen). Die Engine (StoneWorks) liefert nur Zustand.

var sim: Simulation
var cv
var _nodes := {}        # Werk-ID -> [Node2D]
var _sig := {}         # Werk-ID -> Darstellungsstand


func setup(simulation: Simulation, city_view) -> void:
	sim = simulation
	cv = city_view
	if sim.stone != null:
		sim.stone.work_changed.connect(func(_id): _refresh())
	_refresh()


func _refresh() -> void:
	if sim.stone == null:
		return
	for a in sim.stone.works.values():
		var sig := "%s|%s|%s" % [a.status, a.base_color, a.accent_color]
		if _sig.get(a.id, "") == sig:
			continue
		_sig[a.id] = sig
		for n in _nodes.get(a.id, []):
			n.queue_free()
		_nodes[a.id] = _make(a)


func _make(a: Dictionary) -> Array:
	var out: Array = []
	var r := Rect2i(int(a.rect[0]), int(a.rect[1]), int(a.rect[2]), int(a.rect[3]))
	match str(a.status):
		"geplant", "im_bau":
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					out.append(_sprite("fac_site", Vector2(x * 32 + 16, y * 32 + 16)))
			return out
		"fertig", "angemalt", "natur":
			pass
		_:
			return out
	var spr := "sw_%s" % str(a.motif)
	if not cv.has_tex(spr):
		return out
	var w := Vector2((float(r.position.x) + float(r.size.x) * 0.5) * 32.0, (float(r.position.y) + float(r.size.y) * 0.5) * 32.0)
	var s := _sprite(spr, w)
	var tint := str(StoneWorks.MATERIALS.get(str(a.get("material", "stein")), {}).get("tint", ""))
	if tint != "":   # Bronze, Holz, Stahl, Beton: Naturfarbe des Materials (Farbmasken liegen darueber)
		s.self_modulate = Color(tint)
	out.append(s)
	if str(a.base_color) != "" and cv.has_tex(spr + "_mask"):
		var m := Sprite2D.new()
		m.texture = cv.tex(spr + "_mask")
		m.centered = false
		m.offset = s.offset
		m.modulate = Color(str(a.base_color))
		s.add_child(m)
		out.append(m)
	if str(a.accent_color) != "" and cv.has_tex(spr + "_amask"):
		var am := Sprite2D.new()
		am.texture = cv.tex(spr + "_amask")
		am.centered = false
		am.offset = s.offset
		am.modulate = Color(str(a.accent_color))
		s.add_child(am)
		out.append(am)
	return out


func _sprite(name: String, world: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = cv.tex(name)
	s.centered = false
	s.offset = -cv.pivot_of(name)
	s.position = Iso.to_screen(world)
	cv.buildings_node.add_child(s)
	return s
