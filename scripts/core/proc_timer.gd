class_name ProcTimer
extends RefCounted
## Ruckler-Suche: summiert die Rechenzeit je Knotenart (_process), ausgegeben in den perf-Eintraegen der Partie.

static var acc := {}

## Haenger-Melder: Der Hauptthread setzt vor jedem grossen Schritt eine Markierung; ein Waechter-Thread (main.gd) schreibt sie nach
## user://logs/haenger.txt, wenn mehr als 3 s kein Bild fertig wird. Nur Ganzzahlen, damit der Lesezugriff aus dem Thread sicher ist.
const PHASES := ["-", "main", "spielsitzung", "firmen_ki", "buergermeister_ki", "disponent_ki", "gespraeche_ki", "dienste", "ereignisfenster",
	"platzierung", "Simulation", "Simulation: Tageswechsel", "Stadtansicht", "Fahrzeuge/Figuren", "Aktivitaeten", "Betriebshof", "Oberflaeche",
	"Leistungslog", "KI: Beobachtung", "KI: Anfrage senden", "KI: Antwort verarbeiten", "KI: Aktionen ausfuehren", "KI: Hofrunde",
	"KI: Ersatzmodus", "KI: Nachkauf", "Partie wird aufgebaut (Karte, Ansicht)",
	"nach _process (Layout, _draw)", "Rendern", "nach Rendern",
	"zeichnen: activity_layer", "zeichnen: ambient_view.Spot", "zeichnen: ambient_view.GroundOverlay", "zeichnen: ambient_view.FoamOverlay", "zeichnen: ambient_view.EveningLights", "zeichnen: bridge_view.BridgeNode", "zeichnen: bridge_view.RoadWorksNode", "zeichnen: civic_view.LineLayer", "zeichnen: depot_view.DepotNode", "zeichnen: eko_view", "zeichnen: eko_view.TileNode", "zeichnen: eko_view.HouseNode", "zeichnen: eko_view.BeingNode", "zeichnen: fire_fx", "zeichnen: free_build_view.BuildNode", "zeichnen: highway_view", "zeichnen: map_markers", "zeichnen: mountain_view.MountainNode", "zeichnen: offroad_fx", "zeichnen: offroad_fx.DustLayer", "zeichnen: parcel_layer", "zeichnen: placement_overlay", "zeichnen: power_net_view", "zeichnen: rail_view", "zeichnen: road_state_view", "zeichnen: ship_view.JettyNode", "zeichnen: ship_view.ShipNode", "zeichnen: site_view.SiteNode", "zeichnen: waste_view.LandfillNode", "zeichnen: waste_view.CrewNode", "zeichnen: works_view.PlantNode", "zeichnen: works_view.ShopNode", "zeichnen: control_center.LineChart", "zeichnen: control_center.BarChart", "zeichnen: minimap", "zeichnen: portrait_art", "zeichnen: profit_chart"]
static var phase := 0
static var detail := 0
static var who := -1


static func mark(name: String, firm: int = -2) -> void:
	phase = maxi(0, PHASES.find(name))
	if firm != -2:
		who = firm


static var _sub_ms := 0


static func sub(name: String, firm: int = -2) -> void:
	var now := Time.get_ticks_msec()
	if now - _sub_ms > 1500 and _sub_ms > 0 and PHASES[detail].begins_with("zeichnen:"):
		_slow_note("zwischen \"%s\" und \"%s\": %d ms (Phase %s)" % [PHASES[detail], name, now - _sub_ms, PHASES[phase]])
	_sub_ms = now
	detail = maxi(0, PHASES.find(name))
	if firm != -2:
		who = firm


## Langsame Zeichenstrecke ins Haenger-Protokoll (nur im Hauptthread, selten).
static func _slow_note(text: String) -> void:
	var path := "user://logs/haenger.txt"
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s langsam %s" % [Time.get_datetime_string_from_system(), text])
	f.close()


static func text() -> String:
	return "%s / %s%s" % [PHASES[phase], PHASES[detail], (" (Firma %d)" % who) if who >= 0 else ""]


static func add(what: String, t0: int) -> void:
	acc[what] = float(acc.get(what, 0.0)) + (Time.get_ticks_usec() - t0) / 1000.0


## Summen seit dem letzten Aufruf je Bild (ms) und zuruecksetzen.
static func report(frames: int) -> Dictionary:
	var out := {}
	for k in acc:
		out[k] = snappedf(float(acc[k]) / maxf(1.0, float(frames)), 0.01)
	acc.clear()
	return out
