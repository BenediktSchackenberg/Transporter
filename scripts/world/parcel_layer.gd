class_name ParcelLayer
extends Node2D
## Kartenebenen der Stadtentwicklung (Auftrag 7, Abschnitt 16), Taste L schaltet weiter: Verfuegbarkeit, Eigentum, zulaessige Bebauung,
## Erschliessung, Antraege und Bauprojekte. Zeichnet nur flache Farbflaechen ueber dem Boden; liest nur aus Simulation.parcels.

const MODES := ["aus", "Verfügbarkeit", "Eigentum und Nutzungsrechte", "zulässige Bebauung", "Erschließungszustand", "Anträge und Bauprojekte", "Versorgungs- und Verkehrsengpässe", "Rohstoffe", "Stadtplan"]
const LEGENDS := ["",
	"frei grün · reserviert gelb · privat gehalten grau · zur Entwicklung blau · genehmigt/im Bau orange · bebaut ausgeblendet",
	"Stadt blau · Haushalte grün · Unternehmen orange · Bauträger violett",
	"Wohnen grün · Mischgebiet gelb · Gewerbe orange · Industrie rot · öffentlich blau · Grün hellgrün · Korridor grau",
	"voll erschlossen grün · teilweise gelb · keine rot",
	"Antrag in Prüfung violett · genehmigt blau · Erschließung orange · im Bau rot · übergeben ausgeblendet",
	"Baustelle blockiert rot · wartet auf Lieferung orange · Straßensperrung/Baustelle/Überflutung dunkelrot · Stau gelb · Verkehrsdichte rot (je dichter)",
	"Eisenerz rotbraun · Kohle schwarz · Kalkstein hell · Kies/Sand ocker · Naturstein blaugrau · kräftig = erkundet, blass = nur geschätzt · Rand weiß = Bergwerk/Abbaurecht",
	"Viertel nach Zone (Wohnen grün · Mischgebiet gelb · Gewerbe orange · Grün hellgrün) · Rand gestrichelt = Entwurf, voll = beschlossen/in Erschließung, kräftig gefüllt = erschlossen · geplante Straßen orange · reservierte Grundstücke gelb umrandet · Stern = Ortskern"]
const DEPOSIT_COLORS := {"eisenerz": Color("a0522d"), "kohle": Color("2b2b2b"), "uranerz": Color("75a74e"), "kalkstein": Color("e6e2d0"), "rohmaterial": Color("d0a050"), "naturstein": Color("8f9aa6")}
const ZONE_COLORS := {"wohnen": Color("5fb85f"), "mischgebiet": Color("e0c050"), "gewerbe": Color("e08a3c"), "industrie": Color("d0504a"), "oeffentlich": Color("4a8fd0"),
	"gruen": Color("a6d98a"), "korridor": Color("8a8a8a")}

var sim: Simulation
var mode := 0
var _t := 0.0
var _sig := ""


func setup(simulation: Simulation) -> void:
	sim = simulation
	z_index = -9
	visible = false


func cycle() -> String:
	mode = (mode + 1) % MODES.size()
	visible = mode > 0
	z_index = 60 if MODES[mode] == "Stadtplan" else -9   # Planungsbild ueber Gebaeuden und Fahrzeugen, sonst flach auf dem Boden
	_sig = ""
	queue_redraw()
	return "Kartenebene: %s" % MODES[mode] + ("\n" + LEGENDS[mode] if mode > 0 else "")


func update_view(delta: float) -> void:
	if mode == 0:
		return
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var sig := "%d|%d|%d|%d" % [mode, sim.parcels.touched.size(), sim.permits.apps.size(), sim.construction.projects.size()]
	for pr in sim.construction.projects.values():
		sig += pr.status.left(2) + str(pr.blockers.size())
	if mode == 6:
		sig += "|%d|%d" % [int(sim.game_min / 20.0), sim.traffic_events.size()]
	if mode == 8:
		var cam := get_viewport().get_camera_2d()
		sig += "|%.2f|" % (cam.zoom.x if cam != null else 1.0) + str(hash(sim.town_plan.towns)) + "|" + str(sim.towns.mayors.map(func(M): return M.projects.size()))
	if sig != _sig:
		_sig = sig
		queue_redraw()


func color_of(p: Dictionary) -> Color:
	match mode:
		1:
			match str(p.state):
				"frei": return Color(0.3, 0.8, 0.3, 0.5)
				"reserviert": return Color(0.95, 0.85, 0.2, 0.5)
				"privat_gehalten": return Color(0.6, 0.6, 0.6, 0.5)
				"zur_entwicklung": return Color(0.3, 0.55, 0.95, 0.5)
				"genehmigt", "in_erschliessung", "im_bau": return Color(0.95, 0.55, 0.15, 0.55)
		2:
			var o := str(p.owner)
			if Towns.is_public(o):   # auch Grundstuecke der anderen Staedte (stadt<k>)
				return Color(0.3, 0.55, 0.95, 0.5)
			if o.begins_with("H"):
				return Color(0.3, 0.8, 0.3, 0.5)
			if o.begins_with("C"):
				return Color(0.95, 0.55, 0.15, 0.5)
			return Color(0.7, 0.35, 0.85, 0.5)
		3:
			var c: Color = ZONE_COLORS.get(str(p.zone), Color.WHITE)
			c.a = 0.5
			return c
		4:
			match sim.parcels.utility_level(p):
				"voll": return Color(0.3, 0.8, 0.3, 0.5)
				"teilweise": return Color(0.95, 0.85, 0.2, 0.5)
				_: return Color(0.9, 0.3, 0.25, 0.5)
		5:
			var app_id := str(p.application)
			var a: Dictionary = sim.permits.apps.get(app_id, {})
			match str(p.state):
				"genehmigt": return Color(0.3, 0.55, 0.95, 0.55)
				"in_erschliessung": return Color(0.95, 0.55, 0.15, 0.55)
				"im_bau": return Color(0.9, 0.3, 0.25, 0.55)
			if not a.is_empty() and a.status != "entschieden":
				return Color(0.7, 0.35, 0.85, 0.55)
		7:
			var dp: Dictionary = sim.prod.deposit_of(str(p.id))
			if not dp.is_empty():
				var dc: Color = DEPOSIT_COLORS.get(str(dp.art), Color.WHITE)
				dc.a = 0.65 if sim.mining.explored.has(str(p.id)) or not sim.mining.enabled else 0.3
				return dc
		6:
			for pr in sim.construction.projects.values():
				if pr.parcel == p.id and pr.status in Construction.ACTIVE_STATES:
					if not pr.blockers.is_empty():
						return Color(0.9, 0.25, 0.2, 0.6)
					for d in sim.construction.deliveries.values():
						if d.project == pr.id and d.status == "offen":
							return Color(0.95, 0.6, 0.15, 0.6)
	return Color(0, 0, 0, 0)


## Verkehrsengpaesse: gesperrte/gestaute Abschnitte und Fahrzeugdichte je 4x4-Feldblock.
func _draw_traffic() -> void:
	var density := {}
	for m in sim.traffic:
		var t := CityData.to_tile(m.pos)
		var k := Vector2i(t.x / 4, t.y / 4)
		density[k] = int(density.get(k, 0)) + 1
	for v in sim.vehicles.values():
		var t := CityData.to_tile(v.pos)
		var k := Vector2i(t.x / 4, t.y / 4)
		density[k] = int(density.get(k, 0)) + 1
	for k in density:
		if int(density[k]) >= 3:
			_tile_rect(Rect2(float(k.x) * 128.0, float(k.y) * 128.0, 128.0, 128.0), Color(0.9, 0.25, 0.2, clampf(0.12 * float(density[k]), 0.2, 0.6)))
	for e in sim.traffic_events:
		var col := Color(0.95, 0.85, 0.2, 0.7) if e.kind == "stau" else Color(0.6, 0.05, 0.05, 0.8)
		for c in e.cells:
			_tile_rect(Rect2(float(c.x) * 32.0, float(c.y) * 32.0, 32.0, 32.0), col)


## Auftrag 8, Abschnitt 11: Planungsbild – Viertel mit Rolle und Status, geplante Strassen laufender Viertel-Projekte, reservierte
## Grundstuecke, Ortskern. Entwurf (unverbindlich) gestrichelt, beschlossen/in Erschliessung voll umrandet, erschlossen gefuellt.
func _draw_plan() -> void:
	var font := ThemeDB.fallback_font
	var cam := get_viewport().get_camera_2d()
	var zs := 1.0 / maxf(0.25, cam.zoom.x if cam != null else 1.0)   # Schrift und Linien bleiben beim Herauszoomen lesbar
	var fs := int(15.0 * zs)
	for p in sim.parcels.items.values():   # reservierte Grundstuecke (harte Reservierung mit Halter)
		if str(p.state) == "reserviert":
			var r := Rect2(float(p.rect[0]) * 32.0, float(p.rect[1]) * 32.0, float(p.rect[2]) * 32.0, float(p.rect[3]) * 32.0)
			var pts := PackedVector2Array([Iso.to_screen(r.position), Iso.to_screen(Vector2(r.end.x, r.position.y)), Iso.to_screen(r.end), Iso.to_screen(Vector2(r.position.x, r.end.y)), Iso.to_screen(r.position)])
			draw_polyline(pts, Color(0.98, 0.85, 0.2, 0.9), 3.0 * zs)
	for M in sim.towns.mayors:   # geplante Strassen laufender Viertel-Projekte
		for prj in M.projects.values():
			if prj.has("road_plan") and str(prj.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
				for q in prj.road_plan:
					_tile_rect(Rect2(float(q[0]) * 32.0 + 6.0, float(q[1]) * 32.0 + 6.0, 20.0, 20.0), Color(0.98, 0.55, 0.12, 0.75))
	for key in sim.town_plan.towns:
		var pl: Dictionary = sim.town_plan.towns[key]
		for v in pl.viertel:
			var c := Vector2(float(v.mitte[0]) + 0.5, float(v.mitte[1]) + 0.5) * 32.0
			var rad := float(v.radius) * 32.0
			var col: Color = ZONE_COLORS.get(str(v.zone), Color.WHITE)
			var ring := PackedVector2Array()
			for i in 33:
				ring.append(Iso.to_screen(c + Vector2.RIGHT.rotated(TAU * i / 32.0) * rad))
			match str(v.status):
				"erschlossen":
					draw_colored_polygon(ring.slice(0, 32), Color(col, 0.35))
					draw_polyline(ring, Color(col, 0.95), 3.0 * zs)
				"in_erschliessung":
					draw_colored_polygon(ring.slice(0, 32), Color(col, 0.2))
					draw_polyline(ring, Color(col, 0.95), 3.0 * zs)
				_:
					draw_colored_polygon(ring.slice(0, 32), Color(col, 0.1))
					for i in range(0, 32, 2):
						draw_line(ring[i], ring[i + 1], Color(col, 0.95), 3.0 * zs)
			var design := str(v.get("entwurf", ""))
			var design_name := str(TownPlan.QUARTER_DESIGNS.get(design, {}).get("label", ""))
			var label := "%s %s · %s%s" % [v.id, str(v.text), {"entwurf": "Entwurf", "in_erschliessung": "in Erschließung", "erschlossen": "erschlossen"}.get(str(v.status), str(v.status)), (" · " + design_name) if design_name != "" else ""]
			var at := Iso.to_screen(c) + Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / 2.0, 0)
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * zs), Color(0, 0, 0, 0.75))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var kc := Iso.to_screen((Vector2(float(pl.kern[0]), float(pl.kern[1])) + Vector2(0.5, 0.5)) * 32.0) + Vector2(0, -26)
		var star := PackedVector2Array()
		for i in 10:
			star.append(kc + Vector2.UP.rotated(TAU * i / 10.0) * (14.0 if i % 2 == 0 else 6.0) * zs)
		draw_colored_polygon(star, Color("ffd34d"))
		var title := "%s – %s" % [sim.towns.name_of(int(key)), str(pl.label)]
		var ts := int(19.0 * zs)
		var tp := kc + Vector2(-font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x / 2.0, -18.0 * zs)
		draw_string_outline(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, int(5 * zs), Color(0, 0, 0, 0.8))
		draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color("ffd34d"))


func _tile_rect(r: Rect2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Iso.to_screen(r.position), Iso.to_screen(Vector2(r.end.x, r.position.y)), Iso.to_screen(r.end), Iso.to_screen(Vector2(r.position.x, r.end.y))]), col)


func _draw() -> void:
	ProcTimer.sub("zeichnen: parcel_layer")   # Haenger-Suche 18.11.: welche Ebene zeichnet gerade
	if mode == 0 or sim == null:
		return
	if mode == 6:
		_draw_traffic()
	if mode == 8:
		_draw_plan()
		return
	for p in sim.parcels.items.values():
		if p.state == "bebaut" and mode != 2 and mode != 3 and mode != 7:
			continue
		if p.zone == "korridor" and mode != 3:
			continue
		var col := color_of(p)
		if col.a <= 0.0:
			continue
		var x := float(p.rect[0]) * 32.0
		var y := float(p.rect[1]) * 32.0
		var w := float(p.rect[2]) * 32.0
		var h := float(p.rect[3]) * 32.0
		draw_colored_polygon(PackedVector2Array([Iso.to_screen(Vector2(x, y)), Iso.to_screen(Vector2(x + w, y)), Iso.to_screen(Vector2(x + w, y + h)), Iso.to_screen(Vector2(x, y + h))]), col)
