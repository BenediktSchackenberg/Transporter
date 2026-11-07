class_name Airport
extends RefCounted
## Flughafen-Betrieb (Auftrag 16). Die Flugbewegung (Etappe E2) ist eine deterministische Funktion der Spielzeit:
## ein kleines Flugzeug erscheint am Kartenrand, setzt auf der Startbahn auf, rollt zum Vorfeld, steht kurz
## (Abfertigung) und fliegt wieder ab. Die Geometrie (Startbahn, Vorfeld) kommt aus city_data.airport (Seed).
## Position und Hohe sind reine Funktionen der Spieluhr, daher bleibt der Flug bei Speichern/Laden nahtlos.
##
## Etappe E2, Teil Luftfracht: das Flugzeug ist zugleich der Transportweg. Bestellte Luftfracht (vom Stadtlager,
## via_air) wartet im Luftfracht-Manifest und wird bei der naechsten Landung geliefert – aber nur bei Flugwetter:
## Starkregen, Sturm, Schnee, Glaette oder dichter Nebel lassen den Flug ausfallen (die Ware wartet). Die Ware
## landet als X0-Importware im Flughafen-Frachtterminal und wird per Transportauftrag ins Zentrallager gebracht –
## genau so wie die Schifffahrt am Hafen (Auftrag 15, Etappe C), nur schneller und wetterhaengig. Jede Landung
## kostet die Stadt eine kleine Abfuhr (Luftfracht-Pauschale).

const PERIOD := 60.0           # Spielminuten je Flugbewegung (Regelverkehr, ~30 s Echtzeit)
const EDGE_OFF := 8.0          # wie weit auessel der Karte Flugzeuge eintreffen/verschwinden (Feld)
const AIRFREIGHT_FEE := 180.0  # Stadtkasse zahlt je Landung, die Luftfracht mitnimmt (Betreiberpauschale)

var sim
var enabled := false
var track := {}                # {size, run_x0, run_x1, run_y, apron:[x,y], cargo} – Feld-/Gebaeude-Koordinaten
var cargo_building := -1       # Flughafen-Frachtterminal (Anlieferungspunkt der Luftfracht)
var manifest: Array = []       # wartende Luftfracht {ref, item, qty, since}
var _last_flight := 0          # letzte entladene Landung (Flugzaehler; mitgespeichert)
var stats := {"fluege": 0, "abgebrochen": 0, "einheiten_ein": 0}


func setup(simulation) -> void:
	sim = simulation
	var a: Dictionary = sim.city.airport
	if a.is_empty():
		return
	enabled = true
	cargo_building = int(a.get("cargo", -1))
	# Stehplatz: der erste genannte Vorfeldpunkt, der frei ist (die Nennpunkte können unter Gebäuden liegen),
	# sonst eine freie Vorfeldzelle in der Reihe unter den Gebäuden.
	var spot: Array = []
	for p in a.apron:
		var c := Vector2i(int(p[0]), int(p[1]))
		if sim.city.inside(c) and sim.city.building_at[sim.city.idx(c)] == -1:
			spot = [c.x, c.y]
			break
	if spot.is_empty():
		var ry: int = int(a.run_y)
		for xx in range(int(a.run_x0), int(a.run_x1) + 1):
			var c := Vector2i(xx, ry + 4)
			if sim.city.inside(c) and sim.city.g(c) == CityData.G.APRON and sim.city.building_at[sim.city.idx(c)] == -1:
				spot = [c.x, c.y]
				break
	if spot.is_empty() and not a.apron.is_empty():
		spot = [int(a.apron[0][0]), int(a.apron[0][1])]
	track = {
		"size": sim.city.size,
		"run_x0": int(a.run_x0), "run_x1": int(a.run_x1), "run_y": int(a.run_y),
		"apron": spot,
	}


## Flugzeug zu Spielzeit now: {pos: Vector2 (Feld), h: Hoehe (Feld), dir: 0..3, on_ground}. leer = nicht vorhanden.
func state(now: float) -> Dictionary:
	if not enabled:
		return {}
	var t := fmod(float(now), PERIOD) / PERIOD
	var rx0: float = float(track.run_x0)
	var rx1: float = float(track.run_x1)
	var ry: float = float(track.run_y)
	var ax: float = float(track.apron[0])
	var ay: float = float(track.apron[1])
	var edge: float = float(track.size) + EDGE_OFF
	# Key-Points [t, x, y, h]: Anflug vom Kartenrand, Touchdown, Rollen, Vorfeld (stehend), Rollen, Abflug.
	# Der letzte Punkt gleicht dem ersten, damit sich die Periode nahtlos wiederholt.
	var kp: Array = [
		[0.00, edge, ry - 14.0, 11.0],
		[0.30, rx1 + 8.0, ry - 5.0, 5.5],
		[0.42, rx1, ry, 0.0],
		[0.55, rx0 + 1.0, ry, 0.0],
		[0.65, ax, ay, 0.0],
		[0.85, ax, ay, 0.0],
		[0.90, rx0 + 1.0, ry, 0.0],
		[0.96, rx1 + 3.0, ry, 0.4],
		[1.00, edge, ry - 14.0, 11.0],
	]
	var i := 0
	while i < kp.size() - 1 and kp[i + 1][0] < t:
		i += 1
	var a_kp: Array = kp[mini(i, kp.size() - 2)]
	var b_kp: Array = kp[mini(i + 1, kp.size() - 1)]
	var k := clampf((t - a_kp[0]) / maxf(b_kp[0] - a_kp[0], 0.001), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)          # weiche Bewegung
	var x: float = float(a_kp[1]) + (float(b_kp[1]) - float(a_kp[1])) * k
	var y: float = float(a_kp[2]) + (float(b_kp[2]) - float(a_kp[2])) * k
	var h: float = float(a_kp[3]) + (float(b_kp[3]) - float(a_kp[3])) * k
	var dx: float = float(b_kp[1]) - float(a_kp[1])
	var dy: float = float(b_kp[2]) - float(a_kp[2])
	var dir: int
	if absf(dx) >= absf(dy):
		dir = 0 if dx >= 0.0 else 2
	else:
		dir = 1 if dy >= 0.0 else 3
	return {"pos": Vector2(x, y), "h": h, "dir": dir, "on_ground": h < 0.3}


## Flugbewegungen seit Beginn (Kennzahl fuer E2/E3): naehere an der Uhr, gerundet.
func movements_since_start(now: float) -> int:
	if not enabled or now <= 0.0:
		return 0
	return int(float(now) / PERIOD) + 1


## Die Startbahn als [x0, x1, y] in Feldern (fuer die Darstellung/Abnahme).
func runway() -> Array:
	return [int(track.run_x0), int(track.run_x1), int(track.run_y)] if enabled else []

# ------------------------------------------------------------------ Luftfracht (Etappe E2, Teil 2)
## Bestellte Luftfracht wird im Manifest vormerk (analog Hafen.ship_in). `ref` = Bestell-ID des Stadtlagers.
func cargo_in(order_id: String, item: String, qty: int) -> void:
	manifest.append({"ref": order_id, "item": item, "qty": qty, "since": GameCalendar.day_of(sim.game_min)})

## Flugwetter-Gate: bei Starkregen, Sturm, Schnee, Glätte oder dichtem Nebel fällt die Landung aus
## und die wartende Fracht kommt erst mit dem nächsten Flug. Das Flugzeug selbst fliegt weiterhin seine
## Animation (pure clock) – die Wirtschaft (Frachtlieferung) ist wetterabhängig.
func flight_ok() -> bool:
	var wx: Weather = sim.wx
	return not (wx.is_heavy_rain() or wx.is_snow() or wx.is_strong_wind() or wx.is_icy() or wx.is_fog())

## Pro Minute-Tick: Ein neuer Flugzyklus (PERIOD Spielminuten) beendet sich genau einmal pro Periode.
## Bei Flugwetter wird die wartende Fracht ins Frachtterminal ausgeliefert, bei schlechtem Wetter
## faellt der eine Flug aus (ein Abbruch, nicht pro Minute). Der Flugzaehler laeuft weiter, damit die
## naechste Periode korrekt erkannt wird und der ausgefallene Flug genau ein Mal gezahlt wird.
func on_minute(now: float) -> void:
	if not enabled:
		return
	var flights_done := int(float(now) / PERIOD)
	if flights_done <= _last_flight:
		return
	_last_flight = flights_done
	if flight_ok():
		if not manifest.is_empty():
			_unload_manifest()
	else:
		if not manifest.is_empty():
			stats.abgebrochen = int(stats.abgebrochen) + 1

## Wartende Luftfracht wird als X0-Importware ins Frachtterminal ausgeliefert und die
## Stadtlager-Bestellung wird übergeben (analog Hafen._unload → city_depot.on_ship).
func _unload_manifest() -> void:
	var unloaded := 0
	for m in manifest:
		var qty := int(m.qty)
		if qty > 0:
			sim.stock.add(str(m.item), qty, Production.IMPORT, cargo_building, "Luftfracht (Flugzeug)", sim.game_min)
			sim.city_depot.on_aircraft(str(m.ref))
			stats.einheiten_ein = int(stats.einheiten_ein) + qty
			unloaded += 1
	manifest.clear()
	if unloaded > 0:
		sim.economy.transfer("P0", "X0", AIRFREIGHT_FEE)   # Betreiberpauschale
		stats.fluege = int(stats.fluege) + 1
		sim.log_event("Luftfracht: %d Posten gelandet, %d Einheiten im Frachtterminal" % [unloaded, stats.einheiten_ein], "info")
		sim.activity.add("stadt", cargo_building, "sonstiges", "Luftfracht gelandet",
			"%d Posten ins Frachtterminal gebracht (Wetter: %s)" % [unloaded, str(sim.wx.cur.get("cond", ""))],
			sim.city.building(cargo_building).road)

func to_dict() -> Dictionary:
	return {"enabled": enabled, "manifest": manifest.duplicate(true), "last_flight": _last_flight, "stats": stats.duplicate()}

func from_dict(d: Dictionary) -> void:
	manifest = d.get("manifest", []).duplicate(true)
	for m in manifest:
		m.qty = int(m.qty)
	_last_flight = int(d.get("last_flight", 0))
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k]
