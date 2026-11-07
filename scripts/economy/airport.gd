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
const TICKET := 28.0            # Hin- und Rückflug, gezahlt aus dem Buergerguthaben (Etappe E3)
const LANDING_FEE := 40.0       # die Stadt kassiert je Passagierflug eine Landegebuehr (X0 -> P0)
const TRIP_CHANCE := 0.004      # je Buerger und Tag: Reise ins Ausland (Urlaub, Arzt, Geschaeft)
const MIN_BALANCE := 150.0      # darunter ist das Ticket zu teuer (kein Urlaub auf Pump)
const STAY_DAYS := 2            # Aufenthaltsdauer im Ausland; die Rueckkehr fliegt mit dem regelmaeßigen Verkehr
const TRIPS_PER_FLIGHT := 4     # Plaetze im Passagierteil
const REASONS := ["Urlaub", "Familienbesuch", "Arzt", "Geschaftsreise", "Einkauf"]

var sim
var enabled := false
var track := {}                # {size, run_x0, run_x1, run_y, apron:[x,y], cargo} – Feld-/Gebaeude-Koordinaten
var cargo_building := -1       # Flughafen-Frachtterminal (Anlieferungspunkt der Luftfracht)
var manifest: Array = []       # wartende Luftfracht {ref, item, qty, since}
var trips := {}                # Auslandsreisen {id: "Y<n>", person, reason, status, return_day, flight} (Etappe E3)
var _last_trip_day := -1       # letzter Tag, an dem neue Auslandsreisen zugelassen wurden (Etappe E3)
var _next_trip := 1
var _last_flight := 0          # letzte entladene Landung (Flugzaehler; mitgespeichert)
var stats := {"fluege": 0, "abgebrochen": 0, "einheiten_ein": 0, "passagiere": 0}


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
	sim.day_changed.connect(on_day)


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
		_passengers_go(flights_done)
	else:
		if not manifest.is_empty():
			stats.abgebrochen = int(stats.abgebrochen) + 1
		# Passagiere bleiben am Boden (Wetter); bei der Rueckkehr gilt das Gleiche – sie warten auf klareren Himmel.

# ------------------------------------------------------------------ Passagiere (Etappe E3)
## Auslandsreisen: Bewohner fliegen ins Ausland (Urlaub, Arzt, Geschaeft). Das Ticket (Hin- und Rueckflug) zahlt die
## Person aus ihrem Guthaben (R0 -> X0); bei jeder Passagier-Landung kassiert die Stadt eine Landegebuehr (X0 -> P0).
## Es werden keine neuen Personen angelegt – Reisende tragen im Personendatensatz das Merkmal "away" und laufen
## solange nicht auf der Karte umher. Der Abflug erfolgt mit der naechsten Landung (Wetter-Gate gemeinsam mit der Fracht);
## nach dem Aufenthalt fliegen sie mit der naechsten Landung zurueck. Die Buchungen laufen deterministisch vom Tag
## (Hash aus Welt-Seed und Spieltag), damit speichern/laden kein anderes Ergebnis erzeugt.
func on_day(day: int) -> void:
	if not enabled:
		return
	if day <= _last_trip_day:
		return
	_last_trip_day = day
	for t in trips.values():
		if str(t.status) == "unterwegs" and day >= int(t.get("return_day", day + 1)):
			t.status = "return"   # Aufenthalt vorbei: der Rueckflug sitzt auf dem naechsten Flug
	_book_trips(day)

## Neue Auslandsreisen buchen: je Buerger die Chance TRIP_CHANCE, mit ausreichend Guthaben, nicht im Gefaengnis,
## nicht schon unterwegs. Pro Tag steigen hoechstens TRIPS_PER_FLIGHT neue Reisende ein.
func _book_trips(day: int) -> void:
	var taken := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.city.seed_value, day, "airport_reisen"])
	for p in sim.citizens.people:
		if taken >= TRIPS_PER_FLIGHT:
			break
		if p.has("away") or PublicSafety.in_prison(p, day) or float(p.get("balance", 0.0)) < MIN_BALANCE:
			continue
		if rng.randf() >= TRIP_CHANCE:
			continue
		var id := "Y%d" % _next_trip
		_next_trip += 1
		var reason: String = REASONS[posmod(int(p.id) + day, REASONS.size())]
		trips[id] = {"id": id, "person": int(p.id), "reason": reason, "status": "gebucht", "return_day": 0, "flight": -1}
		sim.population.pay_out("X0", [[p, TICKET]])
		taken += 1
	if taken > 0:
		sim.log_event("Flughafen: %d Buerger buchen Auslandsreisen (naechster Flug)." % taken, "info")

## Passagier-Bewegung pro (flugwettergaeltiger) Landung: Rueckkehrer zuerst, dann neue Abreisende, bis der
## Passagierteil voll ist. Die Stadtkasse kassiert die Landegebuehr, wenn jemand ein- oder aussteigt.
func _passengers_go(flight_no: int) -> void:
	var idx: Dictionary = sim.population.person_index()
	var day: int = GameCalendar.day_of(sim.game_min)
	var moving: Array = []
	for t in trips.values():
		if str(t.status) == "return" or str(t.status) == "gebucht":
			moving.append(t)
	moving.sort_custom(func(a, b): return str(a.id) < str(b.id))
	var boarded := 0
	var arrived := 0
	for t in moving:
		if boarded >= TRIPS_PER_FLIGHT:
			break
		var p: Dictionary = idx.get(int(t.person), {})
		if p.is_empty():
			trips.erase(t.id)   # zugezogen ohne Rueckflug: die Reise laeuft ins Leere
			continue
		if str(t.status) == "gebucht" and PublicSafety.in_prison(p, day):
			trips.erase(t.id)
			sim.population.pay_in("X0", [[p, TICKET]])   # Inhaftierung vor dem Abflug: Erstattung
			continue
		boarded += 1
		t["flight"] = flight_no
		if str(t.status) == "return":
			t.status = "fertig"
			p.erase("away")
			arrived += 1
		else:
			t.status = "unterwegs"
			t["return_day"] = day + STAY_DAYS
			p["away"] = {"trip": t.id, "reason": t.reason, "boarded": flight_no}
	if boarded > 0:
		sim.economy.transfer("X0", "P0", LANDING_FEE)   # Landegebuehr der Stadt
		stats.passagiere = int(stats.passagiere) + boarded
		sim.log_event("Flughafen: %d Passagiere gestiegen, %d Rueckkehrer gelandet (Flug %d)." % [boarded - arrived, arrived, flight_no], "info")

## Laeufige Auslandsreise eines Buerger-Datensatzes ("" = nicht unterwegs). Fuer die Darstellung: unterwegs
## laufende Buerger sollen nicht auf der Karte spazieren.
func away_of(p: Dictionary) -> String:
	var aw: Dictionary = p.get("away", {})
	if aw.is_empty():
		return ""
	var t: Dictionary = trips.get(str(aw.get("trip", "")), {})
	if t.is_empty() or str(t.status) == "fertig":
		p.erase("away")
		return ""
	return str(aw.get("reason", "Auslandsreise"))

func away_count() -> int:
	var n := 0
	for p in sim.citizens.people:
		if p.has("away") and away_of(p) != "":
			n += 1
	return n

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
	return {"enabled": enabled, "manifest": manifest.duplicate(true), "last_flight": _last_flight, "stats": stats.duplicate(),
		"trips": trips.duplicate(true), "next_trip": _next_trip, "last_trip_day": _last_trip_day}

func from_dict(d: Dictionary) -> void:
	manifest = d.get("manifest", []).duplicate(true)
	for m in manifest:
		m.qty = int(m.qty)
	_last_flight = int(d.get("last_flight", 0))
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k]
	trips = d.get("trips", {}).duplicate(true)
	for t in trips.values():
		t.person = int(t.person)
		t.return_day = int(t.return_day)
		t.flight = int(t.flight)
	_next_trip = int(d.get("next_trip", 1))
	_last_trip_day = int(d.get("last_trip_day", _last_trip_day))
