extends SceneTree
## Integration: heimische Brennelemente fahren als Fracht, fremder Strom spart Brennstoff,
## Kraftwerksschaden loest sichtbare Folgen und eigenstaendige Notfallentscheidungen aus.

var failures := 0
var checks := 0


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FEHLER: ", label)


func _initialize() -> void:
	var players := []
	for i in 4:
		players.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i,
			"color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	var sim := Simulation.new()
	sim.setup(4242, players, 256, 0.5)
	var obs: Dictionary = ObservationBuilder.build(sim, 0, [], 0.0, 10.0)
	obs.spielminute = GameCalendar.days_to_min(20)
	obs.energie.auslastung = 0.95
	var decisions: Array = []
	RuleBrain._production(obs, obs.ich, 1000000.0, 10000.0, "wachstum", [], [], decisions, [])
	_check(decisions.any(func(a): return str(a.action) == "found_business" and str(a.branche) == "kohlekraftwerk"), "Unternehmer-KI plant bei Netzengpass ein Kohlekraftwerk")
	obs.produktion_markt.kohlekraftwerke = 1
	decisions.clear()
	RuleBrain._production(obs, obs.ich, 1000000.0, 10000.0, "wachstum", [], [], decisions, [])
	_check(obs.bergbau.has("kohle") and decisions.any(func(a): return str(a.action) in ["explore_deposit", "request_mining", "build_access"] or (str(a.action) == "found_business" and str(a.get("rohstoff", "")) == "kohle")), "Unternehmer-KI verfolgt Kohlelagerstaette und Abbaurecht")
	obs.betriebe.append({"id": "ERZ_TEST", "branche": "bergwerk", "rohstoff": "eisenerz", "status": "aktiv", "personal": 1, "personal_min": 1, "ergebnis": 0, "ausbau": {}})
	decisions.clear()
	RuleBrain._production(obs, obs.ich, 1000000.0, 10000.0, "wachstum", [], [], decisions, [])
	_check(decisions.any(func(a): return str(a.action) in ["explore_deposit", "request_mining", "build_access"] or (str(a.action) == "found_business" and str(a.get("rohstoff", "")) == "kohle")), "Ein Erzbergwerk blockiert den Kohleabbau nicht")
	obs.betriebe.pop_back()
	decisions.clear()
	RuleBrain._production(obs, obs.ich, 1000000.0, 10000.0, "risikospieler", [], [], decisions, [])
	_check(obs.bergbau.has("uranerz") and decisions.any(func(a): return str(a.action) in ["explore_deposit", "request_mining", "build_access"] or (str(a.action) == "found_business" and str(a.branche) == "uranbergwerk")), "Unternehmer-KI verfolgt Uranlagerstaette")
	var source := int(sim.trader.bauhof)
	var fuel_before := sim.plant.fuel_elements()
	sim.biz.items["ENERGY_TEST"] = {"id": "ENERGY_TEST", "branch": "brennelementwerk", "status": "aktiv", "owner": 0,
		"site": source, "prices": {PowerPlant.ITEM: 15000.0}, "decisions": [], "blockers": [], "sold_today": 0, "energy_kw": 0.0}
	sim.stock.add(PowerPlant.ITEM, 2, "C0", source, "Test: heimische Fertigung", sim.game_min)
	var left := sim.plant._ship(1)
	var domestic: Array = sim.prod.deals.values().filter(func(d): return d.item == PowerPlant.ITEM and d.buyer == "P0" and d.seller == "C0")
	_check(left == 0 and domestic.size() == 1, "Kraftwerk bestellt ein heimisches Brennelement")
	if not domestic.is_empty():
		var deal: Dictionary = domestic[0]
		_check(sim.contracts.has(str(deal.contract)) and sim.contracts[deal.contract].pickup == source and sim.contracts[deal.contract].dropoff == sim.plant.building,
			"Spezialtransport hat Abholort und Kraftwerk als Ziel")
		_check(sim.plant.fuel_elements() == fuel_before and sim.stock.available(PowerPlant.ITEM, "C0", source) == 1,
			"Ware bleibt bis zur Lieferung beim Werk reserviert")
		sim.prod._receive(deal)
		_check(sim.plant.fuel_elements() == fuel_before + 1 and deal.status == "geliefert", "Brennelement wird erst bei Ankunft Eigentum der Stadtwerke")
	# Bereits gekaufter Privatstrom darf kein zweites Mal Kernbrennstoff verbrauchen.
	var mwh_before := sim.plant.loaded_mwh
	var old_grid: Dictionary = sim.grid.last.duplicate(true)
	sim.grid.last = {"grundlast": 100.0, "versorgt": 0.0, "notstrom_kw": 0.0, "privat_kw": 100.0, "muell_kw": 0.0, "staedte": {}}
	sim.grid._bill()
	_check(is_equal_approx(sim.plant.loaded_mwh, mwh_before), "Kohlestrom verbraucht kein Brennelement")
	sim.grid.last = old_grid
	# Simulierter Gebäudeschaden nutzt denselben Pfad wie ein Angriff der gegnerischen KI.
	var plant: Dictionary = sim.city.building(sim.plant.building)
	var attack_from := Vector2i(int(plant.walk.x), int(plant.walk.y))
	sim.eko.arms.damage_building(plant, 90.0, {"name": "Testgegner"}, attack_from)
	_check(str(sim.plant.alarm.get("stufe", "")) == "katastrophe" and sim.plant.available_kw(1600.0) == 0.0, "Schwerer Angriff schaltet Kraftwerk ab")
	_check(sim.eko.arms.zones.any(func(z): return str(z.get("quelle", "")) == "kraftwerk"), "Sperrzone ist auf der Karte vorhanden")
	var choice: Dictionary = MayorBrain.decide(sim.towns.mayor(0).indicators())
	_check(choice.actions.any(func(a): return str(a.action) == "kraftwerk_notfall" and str(a.massnahme) == "evakuieren"), "Buergermeister-KI priorisiert Evakuierung")
	var before_zone := int(sim.plant.alarm.sperre_bis)
	var evacuation: Dictionary = sim.towns.mayor(0).execute({"action": "kraftwerk_notfall", "massnahme": "evakuieren", "reason": "Menschen in Sicherheit bringen"})
	var stabilize: Dictionary = sim.towns.mayor(0).execute({"action": "kraftwerk_notfall", "massnahme": "stabilisieren", "reason": "Anlage sichern"})
	_check(bool(evacuation.get("ok", false)) and bool(stabilize.get("ok", false)), "Stadt finanziert Evakuierung und Stabilisierung")
	_check(int(sim.plant.alarm.sperre_bis) < before_zone and bool(sim.plant.alarm.evakuiert), "Krisenmassnahmen verkuerzen die Sperre")
	var loaded := Simulation.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(str(loaded.plant.alarm.get("stufe", "")) == "katastrophe" and loaded.eko.arms.zones.any(func(z): return str(z.get("quelle", "")) == "kraftwerk"), "Notfall und Sperrzone bleiben im Spielstand")
	print("Energiekette: %d Prüfungen, %d Fehler" % [checks, failures])
	quit(1 if failures > 0 else 0)
