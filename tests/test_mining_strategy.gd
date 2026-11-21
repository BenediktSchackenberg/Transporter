extends SceneTree
## Die KI muss ein erreichbares Vorkommen weiterverfolgen, während die Konkurrenz
## nach einem erteilten Abbaurecht einen anderen Standort wählen kann.

var failures := 0
var checks := 0

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
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
	obs.bergbau_lage.aktive_bauvorhaben = 1
	var planned_actions := []
	RuleBrain._production(obs, obs.ich, 1000000.0, 10000.0, "wachstum", [], [], planned_actions, [])
	_check(planned_actions.any(func(a): return str(a.action) == "explore_deposit" and str(a.get("grundstueck", "")) != ""), "Ersatz-KI beginnt bei Bautätigkeit die Rohstofferkundung")
	var coal: Array = sim.mining.site_options(0, "kohle", 2)
	_check(not coal.is_empty(), "Kohlevorkommen werden trotz reservierter Bergparzellen angeboten")
	if not coal.is_empty():
		var site: Dictionary = coal[0]
		_check(bool(site.strasse) or (int(site.zufahrt_kosten) > 0 and bool(sim.access.plan(str(site.grundstueck)).ok)), "Standort besitzt oder bekommt eine befahrbare Zufahrt")
		_check(int(site.kaufpreis) > 0 and int(site.rohstoffwert_geschaetzt) > 0, "KI sieht Kaufpreis und geschaetzten Rohstoffwert")
		var pid := str(site.grundstueck)
		_check(bool(sim.mining.explore(0, pid).ok), "Firma beginnt Probebohrung")
		_check(str(sim.mining.next_step(1, "kohle").get("grundstueck", "")) != pid, "Konkurrentin wartet nicht auf die fremde Probebohrung")
		sim.mining.on_day(Mining.EXPLORE_DAYS)
		_check(str(sim.mining.next_step(0, "kohle").get("schritt", "")) == "abbauantrag", "Nach Probebohrung folgt der Abbauantrag")
		_check(bool(sim.mining.request(0, pid, "eigene Kohleversorgung").ok), "Firma beantragt Abbaurecht")
		_check(bool(sim.mining.decide(pid, true, 0.08, "genehmigt", "Bauamt").ok), "Bauamt erteilt Abbaurecht")
		_check(str(sim.mining.next_step(0, "kohle").get("grundstueck", "")) == pid, "Firma setzt das genehmigte Vorhaben fort")
		_check(str(sim.mining.next_step(1, "kohle").get("grundstueck", "")) != pid, "Konkurrentin erhält keine fremde Abbaulizenz als Standort")
	var uranium: Array = sim.mining.site_options(0, "uranerz", 1)
	_check(not uranium.is_empty(), "Uranvorkommen ist als Option sichtbar")
	if not uranium.is_empty():
		var upid := str(uranium[0].grundstueck)
		sim.biz.items["URAN_TEST"] = {"id": "URAN_TEST", "branch": "uranbergwerk", "status": "aktiv", "owner": 0,
			"parcel": upid, "site": sim.trader.bauhof, "deposit": {"art": "uranerz"}}
		_check(str(sim.prod.mine_on(upid).get("id", "")) == "URAN_TEST", "Kartenansicht erkennt ein aktives Uranbergwerk")
	print("Bergbaustrategie: %d Prüfungen, %d Fehler" % [checks, failures])
	quit(1 if failures > 0 else 0)
