extends SceneTree
## Wachstum ab einem Spielstand: N Tage weiterrechnen, dann Wohnungsbau (Bautraeger-Vorhaben), Wohneinheiten, Einwohner, Stadtkassen.
## Aufruf: Godot --headless --path . -s tests/probe_growth.gd -- [--days=20] [--file=user://saves/quicksave.json]

func _init() -> void:
	var path := "user://saves/quicksave.json"
	var days := 20
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.substr(7)
		if a.begins_with("--days="):
			days = int(a.substr(7))
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s := Simulation.from_dict(d.sim)
	var line := func(tag: String) -> void:
		var dev: Array = s.construction.projects.values().filter(func(p): return str(p.client) == "D0")
		print("%s Tag %d: Bautraeger-Vorhaben %d (laufend %d), Wohneinheiten %d, Einwohner %d, Kassen %s" % [tag, GameCalendar.day_of(s.game_min), dev.size(),
			dev.filter(func(p): return str(p.status) != "uebergeben").size(), s.housing.units.size(), s.citizens.population(),
			str(s.towns.list.map(func(t): return int(float(s.economy.accounts[Towns.account_of(int(t.id))]))))])
	line.call("vorher")
	for i in days * 600:
		s.step(0.1)
	line.call("nachher")
	var st := {}
	for p in s.construction.projects.values():
		if str(p.client) == "D0" and str(p.status) != "uebergeben":
			var key := "%s/%s/%s" % [str(p.status), str(p.get("phase", "")), "Firma " + str(p.get("builder", "-"))]
			st[key] = int(st.get(key, 0)) + 1
	print("Laufende Bautraeger-Vorhaben nach Status/Phase/Firma: ", st)
	var one: Array = s.construction.projects.values().filter(func(p): return str(p.client) == "D0" and str(p.status) != "uebergeben")
	if not one.is_empty():
		for pr in one.slice(0, 3):
			print("Beispiel %s %s Phase %s Blocker %s Verlauf: %s" % [pr.id, pr.def, str(pr.get("phase", "")), str(pr.get("blockers", [])), " | ".join(pr.history.slice(-5).map(func(h): return "T%d %s" % [int(h.day), h.text]))])
	print("Kommunale Dienste Tageskosten je Stadt: ", s.towns.list.map(func(t): return int(s.municipal.daily_cost(int(t.id)))))
	for f in s.municipal.facilities.values():   # Kosten je Einrichtung (Sach-/Fahrzeugkosten, Loehne je Tag)
		var lohn := 0.0
		for p in s.municipal.staff_of(f.id):
			lohn += float(p.wage) * Citizens.HOURS_PER_MONTH / 30.0
		var veh := 0.0
		for vid in f.vehicles:
			veh += float(s.municipal.vehicles[vid].cost)
		print("  %s %s (%s): Personal %d, Loehne %.0f, Fahrzeuge %.0f, Unterhalt %.0f je Tag%s" % [f.code, f.name, s.towns.name_of(int(f.town)), s.municipal.staff_count(f.id), lohn, veh,
			float(f.upkeep) * (0.3 + 0.7 * minf(1.0, float(s.citizens.population_of(int(f.town))) / Municipal.REF_POP)), (" (" + Municipal.refinanced(f.code) + ")") if Municipal.refinanced(f.code) != "" else ""])
	print("Invarianten: Geld %.4f, Buergerkonten %.4f" % [s.economy.conservation_error(), s.population.account_error()])
	quit()
