extends SceneTree
## Messung 18.11.: Kosten von EkoSettle.best_near (Erreichbarkeit per Gelaendeweg) und EkoWorld.observe in der Wildnis.
func _init() -> void:
	var T = load("res://tests/run_tests.gd").new()
	var s: Simulation = T.wildnis_sim(4)
	var E: EkoWorld = s.eko
	E.auto_estates = true
	var ps: Array = E.adopt_players(4)
	for p in ps:
		var B: Dictionary = E.beings[p]
		var v := E.own_truck(E.active_firm(B))
		B.mover.pos = v.pos
		E.settle._best_cache.clear()
		var t0 := Time.get_ticks_usec()
		var r: Array = E.settle.best_near(v.tile(), 70, 3)
		var t1 := Time.get_ticks_usec()
		E.settle._best_cache.clear()
		var o: Dictionary = E.observe(p)
		var t2 := Time.get_ticks_usec()
		var o2: Dictionary = E.observe(p)
		var t3 := Time.get_ticks_usec()
		var parts := {"next_steps": func(): return E.next_steps(B), "firm_obs": func(): return E.firm_obs(B), "estates.obs": func(): return E.estates.obs(B),
			"estates.visible": func(): return E.estates.visible(B), "home_obs": func(): return E._home_obs(B), "feelings": func(): return E.feelings(B),
			"dangers": func(): return E.arms.dangers(B), "office_obs": func(): return E.office_obs(B), "settle.obs": func(): return E.settle.obs(B, E.active_firm(B))}
		var line := ""
		for k in parts:
			var ta := Time.get_ticks_usec()
			parts[k].call()
			line += "%s %.0f · " % [k, (Time.get_ticks_usec() - ta) / 1000.0]
		print("   ", line)
		print("%s: best_near %.1f ms (%d Plaetze) | observe ohne Cache %.1f ms | observe mit Cache %.1f ms" % [p, (t1 - t0) / 1000.0, r.size(), (t2 - t1) / 1000.0, (t3 - t2) / 1000.0])
	var a := Vector2i(100, 100)
	var t4 := Time.get_ticks_usec()
	var pth := s.offroad_path(E.own_truck(0).tile(), Vector2i(5, 5))
	print("offroad_path zu Randfeld: %.1f ms (%d)" % [(Time.get_ticks_usec() - t4) / 1000.0, pth.size()])
	quit()
