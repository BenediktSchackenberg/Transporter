extends SceneTree
## Auftrag 22, Abnahme als gemeinsamer Langlauf (offen seit Phase 8): eine Region mit vier Staedten laeuft N Spieltage mit allen
## Zufallsereignissen; danach 12 Pruefungen ueber die Systeme hinweg (je Phase die Kernaussage aus docs/INFRASTRUCTURE.md),
## Geldbilanz und Speichern/Laden. Kein Teil der normalen Testliste (Laufzeit mehrere Minuten).
##   Godot_console.exe --headless --path . -s tests/probe_infra_acceptance.gd -- --days=12 [--seed=4242]

var fails := 0
var checks := 0


func ok(c: bool, text: String) -> void:
	checks += 1
	if not c:
		fails += 1
	print(("  ok:     " if c else "  FEHLER: ") + text)


func _initialize() -> void:
	var days := 12
	var seed_v := 4242
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a).begins_with("--seed="):
			seed_v = int(str(a).trim_prefix("--seed="))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, ps, Catalog.MAP_SIZE, 0.5)
	var t0 := Time.get_ticks_msec()
	var mayor_day := -1
	while GameCalendar.day_of(s.game_min) < days:
		var day := GameCalendar.day_of(s.game_min)
		if day != mayor_day:   # Regel-Buergermeister wie im Spiel ohne Modell
			mayor_day = day
			for M in s.towns.mayors:
				for a in MayorBrain.decide(M.indicators()).actions:
					M.execute(a)
		s.step(0.1)
	print("== Abnahmelauf Auftrag 22: Seed %d, %d Spieltage, %.0f s Rechenzeit" % [seed_v, days, (Time.get_ticks_msec() - t0) / 1000.0])
	var T: Towns = s.towns
	# 1 Muell: Tonnen werden geleert, Restmuell landet gewogen auf der gemeinsamen Deponie
	ok(s.waste.real and s.waste.tours > 0 and s.waste.deposited > 0.0 and not s.waste.scale_log.is_empty(),
		"1 Müll: %d Touren, %.1f t auf der Deponie, %d Wiegungen" % [s.waste.tours, s.waste.deposited, s.waste.scale_log.size()])
	# 2 Wertstoffe/Bio und Stadtreinigung
	ok(s.waste.tours_wert > 0 or float(s.recycling.stats.tonnen) > 0.0, "2 Wertstoffe: %d Wertstofftouren, Recycling %.1f t" % [s.waste.tours_wert, float(s.recycling.stats.tonnen)])
	# 3 Strom aus dem gemeinsamen Kraftwerk, je Stadt abgerechnet
	var st_towns: Dictionary = s.grid.last.get("staedte", {})
	ok(float(s.grid.last.get("grundlast", 0.0)) > 0.0 and st_towns.size() == T.count() and st_towns.values().all(func(x): return bool(x.get("netz", false))),
		"3 Strom: Grundlast %.0f kW aus dem gemeinsamen Kraftwerk, alle %d Städte am Netz, Betriebe %.0f kWh (%s)" % [float(s.grid.last.get("grundlast", 0.0)), T.count(), float(s.grid.stats.kwh), Catalog.money(float(s.grid.stats.erloes))])
	# 4 Stromnetz als Graph (Umspannwerke, Trassen)
	var net: Dictionary = s.grid.net.summary()
	ok(not net.is_empty(), "4 Stromnetz: %s" % str(net).left(140))
	# 5 Trinkwasser je Stadt verbraucht und berechnet
	var water_ok := true
	var wtxt: Array = []
	for t in T.list:
		var w: Dictionary = s.water.by_town.get(str(int(t.id)), {})
		water_ok = water_ok and float(w.get("m3", 0.0)) > 0.0
		wtxt.append("%s %.0f m³" % [T.name_of(int(t.id)), float(w.get("m3", 0.0))])
	ok(water_ok, "5 Wasser: " + ", ".join(wtxt))
	# 6 Abwasser zur Klaeranlage
	var sewage := 0.0
	for t in T.list:
		sewage += float(s.water.by_town.get(str(int(t.id)), {}).get("abwasser", 0.0))
	ok(sewage > 0.0, "6 Abwasser: %.0f m³" % sewage)
	# 7 Polizei: Wache je Stadt, Einsaetze
	ok(T.list.all(func(t): return not s.police.station_of(int(t.id)).is_empty()) and int(s.police.stats.unfaelle) + int(s.police.stats.kontrollen) + int(s.police.stats.muell) + int(s.police.stats.festnahmen) > 0,
		"7 Polizei: %s" % str(s.police.stats))
	# 8 Bahnhof je Stadt, Strecken
	ok(s.rail.is_built(), "8 Bahn: Netz gebaut (%s)" % str(s.rail.summary()).left(120))
	# 9 Personenzuege fahren mit Fahrgaesten
	ok(int(s.trains.stats.fahrten) > 0 and int(s.trains.stats.fahrgaeste) > 0, "9 Regionalbahn: %d Fahrten, %d Fahrgäste, Erlös %s" % [int(s.trains.stats.fahrten), int(s.trains.stats.fahrgaeste), Catalog.money(float(s.trains.stats.erloes))])
	# 10 Kommunale Dienste haben Personal und kosten die Stadtkassen
	var staffed: Array = s.municipal.facilities.values().filter(func(f): return f.status == "in_betrieb" and s.municipal.staff_count(f.id) > 0)
	ok(staffed.size() >= T.count() * 4 and float(s.municipal.stats.kosten) > 0.0, "10 Dienste: %d Einrichtungen mit Personal, Kosten %s" % [staffed.size(), Catalog.money(float(s.municipal.stats.kosten))])
	# 11 Lagebild je Stadt
	ok(T.list.all(func(t): return InfraStatus.of_town(s, int(t.id)).size() >= InfraStatus.AREAS.size()), "11 Lagebild: %s" % str(InfraStatus.AREAS))
	# 12 Speichern/Laden und Geldbilanz
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var s2: Simulation = Simulation.from_dict(d)
	var saved: bool = s2 != null and absf(s2.waste.deposited - s.waste.deposited) < 0.05 and int(s2.police.stats.muell) == int(s.police.stats.muell) 		and s2.police.missions.size() == s.police.missions.size() and int(s2.trains.stats.fahrgaeste) == int(s.trains.stats.fahrgaeste)
	ok(saved, "12 Speichern/Laden: Deponie %.1f/%.1f t, Polizei-Müll %s/%s, Einsätze %d/%d" % [s.waste.deposited, s2.waste.deposited if s2 != null else -1.0,
		str(s.police.stats.muell), str(s2.police.stats.muell) if s2 != null else "-", s.police.missions.size(), s2.police.missions.size() if s2 != null else -1])
	ok(absf(s.economy.conservation_error()) < 0.01 and absf(s.population.account_error()) < 0.01, "Geld erhalten (Fehler %.4f / %.4f EUR)" % [s.economy.conservation_error(), s.population.account_error()])
	print("== %d Prüfungen, %d Fehler" % [checks, fails])
	quit(1 if fails > 0 else 0)
