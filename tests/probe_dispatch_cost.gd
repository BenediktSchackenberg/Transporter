extends SceneTree
## Misst die Kosten einer Disposition-Runde (Beobachtung + Regel-KI) und die teuersten Teile der Beobachtung auf der Regionskarte.
## Aufruf: --headless --path . -s tests/probe_dispatch_cost.gd


func _init() -> void:
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(39181, ps, Catalog.MAP_SIZE, 0.5)
	for i in 600:
		s.step(0.5)
	for cid in 4:
		var t0 := Time.get_ticks_usec()
		var obs := ObservationBuilder.build(s, cid, [], 0.0, 10.0, "", "")
		var t1 := Time.get_ticks_usec()
		RuleBrain.decide(obs, s.company(cid).personality, RandomNumberGenerator.new(), s.strategy.params_of(cid))
		var t2 := Time.get_ticks_usec()
		print("Firma %d: Beobachtung %.1f ms, Regel-KI %.1f ms" % [cid, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	var cid := 0
	var parts := {
		"_available": func(): return ObservationBuilder._available(s, cid),
		"_chances": func(): return ObservationBuilder._chances(s),
		"_branches": func(): return ObservationBuilder._branches(s, cid),
		"_resources": func(): return ObservationBuilder._resources(s, cid),
		"_staff": func(): return ObservationBuilder._staff(s, cid),
		"_tasks": func(): return ObservationBuilder._tasks(s, cid),
		"_situation": func(): return ObservationBuilder._situation(s, cid),
		"_region": func(): return ObservationBuilder._region(s, cid),
		"_housing": func(): return ObservationBuilder._housing(s, cid),
		"_population": func(): return ObservationBuilder._population(s),
		"_bauhof": func(): return ObservationBuilder._bauhof(s, cid),
		"_bank": func(): return ObservationBuilder._bank(s, cid),
		"_weather": func(): return ObservationBuilder._weather(s),
		"_loyal": func(): return ObservationBuilder._loyal(s, cid),
		"_loan_reach": func(): return ObservationBuilder._loan_reach(s, cid),
		"prod.market_obs": func(): return s.prod.market_obs(),
		"biz.obs_of": func(): return s.biz.obs_of(cid),
		"mining.steps_for": func(): return s.mining.steps_for(cid),
		"it.offers": func(): return s.it.offers(),
		"estate.summary": func(): return s.estate.summary(cid),
		"operations.summary": func(): return s.operations.summary(cid),
		"insolvency.summary_of": func(): return s.insolvency.summary_of(cid),
		"households.summary_of": func(): return s.households.summary_of(cid),
		"care.summary_of": func(): return s.care.summary_of(cid),
		"workforce.summary_of": func(): return s.workforce.summary_of(cid),
		"rivalry.summary_of": func(): return s.rivalry.summary_of(cid),
		"strategy.summary_of": func(): return s.strategy.summary_of(cid),
		"plans.summary": func(): return s.plans.summary(cid),
		"experiments.summary": func(): return s.experiments.summary(cid),
		"player_loans.summary_of": func(): return s.player_loans.summary_of(cid),
		"harbor.summary": func(): return s.harbor.summary() if s.harbor.enabled else {},
		"social.agreements_of": func(): return s.social.agreements_of(cid),
		"_storage": func(): return ObservationBuilder._storage(s, cid),
	}
	var res: Array = []
	for n in parts:
		var t := Time.get_ticks_usec()
		parts[n].call()
		res.append([(Time.get_ticks_usec() - t) / 1000.0, n])
	res.sort_custom(func(a, b): return a[0] > b[0])
	for r in res.slice(0, 12):
		print("  %8.1f ms  %s" % r)
	quit()
