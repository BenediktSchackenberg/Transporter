class_name ParcelLayer
extends Node2D
## Kartenebenen der Stadtentwicklung (Auftrag 7, Abschnitt 16), Taste L schaltet weiter: Verfuegbarkeit, Eigentum, zulaessige Bebauung,
## Erschliessung, Antraege und Bauprojekte. Zeichnet nur flache Farbflaechen ueber dem Boden; liest nur aus Simulation.parcels.

const MODES := ["aus", "Verfügbarkeit", "Eigentum und Nutzungsrechte", "zulässige Bebauung", "Erschließungszustand", "Anträge und Bauprojekte", "Versorgungs- und Verkehrsengpässe"]
const LEGENDS := ["",
	"frei grün · reserviert gelb · privat gehalten grau · zur Entwicklung blau · genehmigt/im Bau orange · bebaut ausgeblendet",
	"Stadt blau · Haushalte grün · Unternehmen orange · Bauträger violett",
	"Wohnen grün · Mischgebiet gelb · Gewerbe orange · Industrie rot · öffentlich blau · Grün hellgrün · Korridor grau",
	"voll erschlossen grün · teilweise gelb · keine rot",
	"Antrag in Prüfung violett · genehmigt blau · Erschließung orange · im Bau rot · übergeben ausgeblendet",
	"Baustelle blockiert rot · wartet auf Lieferung orange · Straßensperrung/Baustelle/Überflutung dunkelrot · Stau gelb · Verkehrsdichte rot (je dichter)"]
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
			if o == Parcels.CITY:
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


func _tile_rect(r: Rect2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Iso.to_screen(r.position), Iso.to_screen(Vector2(r.end.x, r.position.y)), Iso.to_screen(r.end), Iso.to_screen(Vector2(r.position.x, r.end.y))]), col)


func _draw() -> void:
	if mode == 0 or sim == null:
		return
	if mode == 6:
		_draw_traffic()
	for p in sim.parcels.items.values():
		if p.state == "bebaut" and mode != 2 and mode != 3:
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
