extends SceneTree
## Messung 18.11.: welcher Teil der Buergermeister-Beobachtung kostet beim ersten Aufruf ~1 s?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for k in s.towns.count():
		var M: Mayor = s.towns.mayor(k)
		var Z = s.citizens
		var pre := {"employment": func(): return Z.employment_rate_of(k), "unemployed": func(): return Z.unemployed_of(k), "homeless": func(): return s.housing.homeless_count(),
			"vacancy": func(): return M.vacancy(), "occupied": func(): return M.occupied_units(), "rent_index": func(): return M.rent_index(), "traffic": func(): return M._traffic_indicators(0),
			"permits_cap": func(): return s.permits.capacity(), "counts": func(): return M._counts(), "goals": func(): return M.goals(), "reserve": func(): return M.reserve_cash(), "budget": func(): return M.available_budget(), "access": func(): return M.access_indicators(), "infra": func(): return InfraStatus.compact(s, k), "road_care": func(): return s.road_care.summary(), "population": func(): return s.population.summary(), "grid": func(): return s.grid.summary(), "region": func(): return M._region_obs()}
		var l0 := ""
		for p in pre:
			var t := Time.get_ticks_usec()
			pre[p].call()
			l0 += "%s %.0f · " % [p, (Time.get_ticks_usec() - t) / 1000.0]
		print("  ", l0)
		var parts := {"civic": func(): return s.civic.mayor_obs(k), "services": func(): return s.services.mayor_obs(k), "vworks": func(): return s.vworks.mayor_obs(k),
			"planning_aids": func(): return s.housing.planning_aids(), "quarter_candidates": func(): return M.quarter_candidates(3), "zoning": func(): return M.zoning(),
			"indicators": func(): return M.indicators()}
		var line := ""
		for p in parts:
			var t := Time.get_ticks_usec()
			parts[p].call()
			line += "%s %.0f · " % [p, (Time.get_ticks_usec() - t) / 1000.0]
		print("%s: %s" % [s.towns.name_of(k), line])
	quit()
