extends SceneTree
## Ein Flughafen zeigt nur einen wirklichen Fracht- oder Passagierflug.

func _initialize() -> void:
	var players := []
	for i in 2:
		players.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i,
			"color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	var sim := Simulation.new()
	sim.setup(4242, players, 256, 0.5)
	var airport: Airport = sim.airport
	airport.enabled = true
	airport.track = {"size": 256, "run_x0": 5, "run_x1": 15, "run_y": 20, "apron": [10, 23], "dir": 1}
	var failures := 0
	airport.manifest.clear()
	airport.trips.clear()
	if airport.has_demand() or not airport.state(sim.game_min).is_empty():
		printerr("FEHLER: Flugzeug erscheint ohne Auftrag")
		failures += 1
	var count := int(airport.stats.fluege)
	airport.on_minute(float(airport._last_flight + 1) * Airport.PERIOD)
	if int(airport.stats.fluege) != count:
		printerr("FEHLER: Leerflug wurde gezaehlt")
		failures += 1
	airport.manifest.append({"ref": "TEST", "item": "schotter", "qty": 1, "left": 1, "since": sim.game_min})
	if not airport.has_demand() or (airport.flight_ok() and airport.state(sim.game_min).is_empty()):
		printerr("FEHLER: Frachtflug bleibt unsichtbar")
		failures += 1
	print("Flughafenbedarf: %d Fehler" % failures)
	quit(1 if failures > 0 else 0)
