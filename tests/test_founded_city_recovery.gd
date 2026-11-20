extends SceneTree
## Integration gegen einen echten Wildnis-Spielstand: gegruendete Orte, Netze, Hafen und Amt.

var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FEHLER: ", label)


func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for k in s.towns.count():
		if not s.town_ready(k):
			continue
		var id := "U%d" % k
		var target: Vector2i = s.grid.net._substation_cell(k)
		check(s.grid.net.nodes.has(id) and s.grid.net.nodes[id].cell.distance_to(target) <= 8.0,
			"Umspannwerk %s steht am gegruendeten Ort" % id)
		for edge in s.grid.net.edges:
			if str(edge.a) != id and str(edge.b) != id:
				continue
			var endpoint: Array = edge.cells[0] if str(edge.a) == id else edge.cells[-1]
			check(Vector2i(int(endpoint[0]), int(endpoint[1])).distance_to(s.grid.net.nodes[id].cell) <= 1.0,
				"Trasse %s endet am wirklichen Umspannwerk" % edge.id)
		var center: Array = s.settlements[str(k)].center
		for art in ["wasser", "abwasser"]:
			var near := false
			for key in s.water.main_cells(k, art):
				var xy := str(key).split(":")
				if absi(int(xy[0]) - int(center[0])) <= 25 and absi(int(xy[1]) - int(center[1])) <= 25:
					near = true
					break
			check(near, "%sleitung erreicht den gegruendeten Ort %d" % [art, k])
		var ranked: Dictionary = s.sites.rank(k, {"w": 3, "h": 3, "art": "oeffentlich", "label": "Stadtpark"})
		print("Stadtplan Standorte ", k, ": ", (ranked.list as Array).size())
		check((ranked.list as Array).all(func(site): return not str(site.viertel_text).contains("außerhalb")),
			"oeffentliche Standorte bleiben im Stadtplan")
	check(EkoWorld.normalize_office({"action": "kommunal_bauen", "typ": "KA-01"}) == "", "gueltige Klaeranlage wird angenommen")
	for k in s.towns.count():
		if s.municipal.of_town(k).any(func(f): return str(f.code) == "WW-01"):
			continue
		check(not s.municipal.kit_tried.has("%d|WW-01" % k), "fehlgeschlagener Wasserwerk-Bau darf erneut versucht werden")
	s.municipal.ensure_kit()
	s.municipal.ensure_regional()
	for k in s.towns.count():
		check(not s.water.works_of(k).is_empty(), "Wasserwerk in Stadt %d nachgeholt" % k)
	check(not s.water.plant().is_empty(), "regionale Klaeranlage nachgeholt")
	s.grid._allocate()
	s.water.on_day(GameCalendar.day_of(s.game_min))
	print("Nach Versorgungslauf: ", s.biz.items.values().map(func(b): return "%s:%s:%s" % [b.id, b.status,
		(b.get("blockers", []) as Array).map(func(x): return x.key)]))
	for id in ["B1", "B2", "B3", "B4"]:
		var business: Dictionary = s.biz.items[id]
		var building: Dictionary = s.city.building(int(business.site))
		print("Betriebsort ", id, " ", building.get("name", ""), " road=", building.get("road", ""), " stadt=", s.city.town_of_building(int(business.site)),
			" strom=", s.grid.net.distributed(s.city.town_of_building(int(business.site)), int(business.site)),
			" wasser=", s.water.building_on_net(s.city.town_of_building(int(business.site)), int(business.site)),
			" parzelle=", s.parcels.of_building(int(business.site)).get("erschliessung", {}))
	check(s.grid.net.distributed(0, int(s.biz.items["B1"].site)), "Betriebshof Auenhafen hat Strassen- und Stromanschluss")
	check(s.water.building_on_net(0, int(s.biz.items["B1"].site)), "Betriebshof Auenhafen hat Wasseranschluss")
	for id in ["B1", "B2"]:
		check(str(s.biz.items[id].status) == "aktiv" and (s.biz.items[id].get("blockers", []) as Array).is_empty(),
			"Transportbetrieb %s ist nach dem Versorgungslauf aktiv" % id)
	for k in s.towns.count():
		var t: Dictionary = s.city.towns[k]
		var yard: Dictionary = s.city.building(int(s.settlements[str(k)].get("yard", -1)))
		var hall: Dictionary = s.city.building(int(t.get("town_hall", -1)))
		print("Grundungsstrassen ", k, " yard=", yard.get("road", ""), " hall=", hall.get("road", ""), " path=", s.nav.road_path(yard.get("road", Vector2i.ZERO), hall.get("road", Vector2i.ZERO)).size())
	if s.trains.enabled():
		s.trains.ensure()
		s.trains.update(1.0)
		check(s.trains.drivers() >= s.trains.trains.size(), "Regionalbahn hat Fahrpersonal oder befristete Fahrer")
		for minute in 30:
			s.game_min += 1.0
			s.trains.update(1.0)
		check(s.trains.trains.any(func(t): return str(t.state) == "fahrt" or float(t.get("cells", 0.0)) > 0.0),
			"mindestens ein Zug faehrt wirklich")
	var harbor: Harbor = s.towns.harbor(0)
	if not harbor.queue.is_empty():
		check(harbor.workers().is_empty(), "Testhafen hat noch kein Stammpersonal")
		harbor.on_minute(s.game_min)
		check(harbor.rate_per_min() > 0.0 or harbor.queue.is_empty(), "externer Ladetrupp hebt Hafenblockade auf")
		check(harbor.contractor_until > s.game_min or harbor.queue.is_empty(), "Ladetrupp ist zeitlich begrenzt")
	print("Stadtgruendung und Versorgung: %d Pruefungen, %d Fehler" % [checks, failures])
	quit(1 if failures > 0 else 0)
